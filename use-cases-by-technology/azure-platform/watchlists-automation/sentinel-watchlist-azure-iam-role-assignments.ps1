# Problem solved : Detections need current Azure role assignments.
# What it does    : Resolves Azure role assignments with Graph and refreshes a Sentinel watchlist.
# Requires        : Az, Microsoft.Graph; Sentinel Contributor
# Effect          : changes-state (review and test before use)
# Known issues    : Org tenant/workspace placeholders; managed identity
# Origin          : adapted from field work; replace every ENTRE_AQUI_COM_SEU_* marker with your own value

###
# Microsoft.Graph.Users
# Microsoft.Graph.Groups
# Microsoft.Graph.Authentication
# Microsoft.Graph.Identity.DirectoryManagement
# Az

$ErrorActionPreference = "Stop"

$subscriptionId = "ENTRE_AQUI_COM_SEU_ID"
$workspaceResourceGroup = "Sentinel"
$workspaceName = "ENTRE_AQUI_COM_SEU_RECURSO"

$watchlistToUpdate = "Azure-IAM"

## MAIN
# Log in first with Connect-AzAccount if not using Cloud Shell
Connect-AzAccount -Identity -Subscription $subscriptionId -ErrorAction Stop
# Connect-AzAccount -Subscription $subscriptionId

$azContext = Get-AzContext
$azProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
$profileClient = New-Object -TypeName Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient -ArgumentList ($azProfile)
$token = $profileClient.AcquireAccessToken($azContext.Subscription.TenantId)
$authHeader = @{
    'Content-Type'='application/json'
    'Authorization'='Bearer ' + $token.AccessToken
}

# # Connect MS Graph and Azure AD
$context = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile.DefaultContext
$graphToken = ([Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate($context.Account, $context.Environment, $context.Tenant.Id.ToString(), $null, [Microsoft.Azure.Commands.Common.Authentication.ShowDialog]::Never, $null, "https://graph.microsoft.com").AccessToken) | ConvertTo-SecureString -AsPlainText -Force
# $aadToken = ([Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate($context.Account, $context.Environment, $context.Tenant.Id.ToString(), $null, [Microsoft.Azure.Commands.Common.Authentication.ShowDialog]::Never, $null, "https://graph.windows.net").AccessToken) | ConvertTo-SecureString -AsPlainText -Force

Connect-MgGraph -AccessToken $graphToken -ErrorAction Stop
# Write-Output (Get-MgContext)

## QUERY
$propertiesToReturn = [PSCustomObject]@{
    RoleDefinition = @("Id", "Name")
    RoleAssignment = @("RoleAssignmentName", "Scope", "RoleDefinitionId", "RoleDefinitionName", "ObjectId", "ObjectType")
}

# ROLES
$roles = Get-AzRoleDefinition | Sort-Object Name | Select-Object $propertiesToReturn.RoleDefinition
$roleAssignments = Get-AzRoleAssignment | Sort-Object RoleDefinitionName | Select-Object $propertiesToReturn.RoleAssignment

#
$roleAssignmentList = [System.Collections.Generic.List[Object]]::new() # Create output file

foreach ($role in $roles) {
    $assignments = $roleAssignments | Where-Object { $_.RoleDefinitionId -eq $role.Id }

    if ($assignments) {
        foreach ($assignment in $assignments) {
            # Fix Scope
            $scope = $null
            $scope = $assignment.Scope.Split('/') | Where-Object { $_ -ne "" }

            $scopeObject = [PSCustomObject]@{
                ManagementGroup = $null
                Subscription = $null
                ResourceGroup = $null
                ResourceType = $null
                Resource = $null
            }

            foreach ($s in $scope) {
                if (($scope.IndexOf($s) % 2) -eq 0) {
                    switch ($s) {
                        "providers" { $scopeObject.ResourceType = $scope[($scope.IndexOf($s) +1)] }
                        "resourceGroups" { $scopeObject.ResourceGroup = $scope[($scope.IndexOf($s) +1)] }
                        "subscriptions" { $scopeObject.Subscription = $scope[($scope.IndexOf($s) +1)] }
                        "managementGroups" { $scopeObject.ManagementGroup = $scope[($scope.IndexOf($s) +1)] }
                        Default { $scopeObject.Resource = $scope[($scope.IndexOf($s)-1) .. ($scope.Length -1)] -join '/' }
                    }
                }
            }

            if ($null -ne $scopeObject.ResourceType -and $null -ne $scopeObject.Resource) {
                $scopeObject.Resource = ($scopeObject.Resource).Replace("$($scopeObject.ResourceType)/", "")
            }

            # Add to report
            $roleAssignmentList.Add([PSCustomObject]@{
                RoleAssignmentName = $assignment.RoleAssignmentName
                RoleDefinitionId = $role.Id
                RoleDefinitionName = $role.Name
                ScopeManagementGroup = $scopeObject.ManagementGroup
                ScopeSubscription = $scopeObject.Subscription
                ScopeResourceGroup = $scopeObject.ResourceGroup
                ScopeResourceType = $scopeObject.ResourceType
                ScopeResource = $scopeObject.Resource
                ObjectId = $assignment.ObjectId
                ObjectType = $assignment.ObjectType
            })
        }
    }
}

$roleAssignmentList = $roleAssignmentList | Where-Object {$_.RoleAssignmentName -ne $null} | Sort-Object RoleDefinitionId

## Get watchlists
# Invoke the REST API
$restUriWatchlists = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$workspaceResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/watchlists?api-version=2021-10-01"
$watchlists = Invoke-RestMethod -Uri $restUriWatchlists -Method Get -Headers $authHeader

$watchlist = ($watchlists.value | Where-Object {$_.properties.displayName -eq "$watchlistToUpdate"})

# 
$removed = @()
$added = @()
$updated = @()

# Get updated watchlist items
$watchlistItems = @()
$restUriWatchlistItems = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$workspaceResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/watchlists/$($watchlist.Name)/watchlistItems?api-version=2022-07-01-preview"
do {
    $watchlistItemsCurrent = Invoke-RestMethod -Uri $restUriWatchlistItems -Method Get -Headers $authHeader
    $watchlistItems += $watchlistItemsCurrent.value
    $restUriWatchlistItems = $watchlistItemsCurrent.nextLink
} while (
    $null -ne $watchlistItemsCurrent.nextLink
)

# Remove watchlist items which do not match the membership list
foreach ($item in $watchlistItems) {
    if (($roleAssignmentList.RoleAssignmentName) -notcontains ($item.properties.itemsKeyValue.RoleAssignmentName)) {
        $restUriWatchlistItemDelete = $null

        # Remove watchlist item
        Write-Host "Removing '$($item.properties.itemsKeyValue.RoleAssignmentName)' from '$($watchlist.properties.displayName)'..."

        $restUriWatchlistItemDelete = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$workspaceResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/watchlists/$($watchlist.Name)/watchlistItems/$($item.properties.watchlistItemId)?api-version=2022-07-01-preview"
        Invoke-RestMethod -Uri $restUriWatchlistItemDelete -Method Delete -Headers $authHeader | Out-Null
        
        if($?) {
            $removed += "REMOVED: '$($item.properties.itemsKeyValue.RoleAssignmentName)' from $($watchlist.properties.displayName)"
        }
    }
}

# Get updated watchlist items
$watchlistItems = @()
$restUriWatchlistItems = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$workspaceResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/watchlists/$($watchlist.Name)/watchlistItems?api-version=2022-07-01-preview"
do {
    $watchlistItemsCurrent = Invoke-RestMethod -Uri $restUriWatchlistItems -Method Get -Headers $authHeader
    $watchlistItems += $watchlistItemsCurrent.value
    $restUriWatchlistItems = $watchlistItemsCurrent.nextLink
} while (
    $null -ne $watchlistItemsCurrent.nextLink
)

# Add group items which are not in watchlist, and update information for groups which are in the watchlist
$count = 0
foreach ($r in $roleAssignmentList) {
    if (($watchlistItems.properties.itemsKeyValue.RoleAssignmentName) -notcontains ($r.RoleAssignmentName)) {
        # Add watchlist item
        $count += 1

        Write-Host "Adding '$($r.RoleAssignmentName)' to '$($watchlist.properties.displayName)'..."

        # Get last watchlist item and create new one with incremented etag (HEX code)
        $lastWatchlistEtag = ($watchlistItems[-1].etag).Replace('"','')

        # Convert first set of characters to decimal
        $convertEtag = [convert]::toint32($lastWatchlistEtag.split('-')[0], 16)
        # Subtracts the amount of added items times 256
        $etag = $convertEtag - (256 * $count)
        # Reconvert to HEX
        $etag = ($('{0:X8}' -f $etag) + "-" + $($lastWatchlistEtag.split('-')[1..4] -join "-")).ToLower()

        $body = @{
            "properties" = @{
                "etag" = $etag
                "itemsKeyValue" = @{
                    "RoleAssignmentName" = $r.RoleAssignmentName
                    "RoleDefinitionId" = $r.RoleDefinitionId
                    "RoleDefinitionName" = $r.RoleDefinitionName
                    "ScopeManagementGroup" = $r.ScopeManagementGroup
                    "ScopeSubscription" = $r.ScopeSubscription
                    "ScopeResourceGroup" = $r.ScopeResourceGroup
                    "ScopeResourceType" = $r.ScopeResourceType
                    "ScopeResource" = $r.ScopeResource
                    "ObjectId" = $r.ObjectId
                    "ObjectType" = $r.ObjectType
                }
            }
        }
        $body = $body | ConvertTo-Json -Depth 10

        $restUriWatchlistItemCreate = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$workspaceResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/watchlists/$($watchlist.Name)/watchlistItems/$($etag)?api-version=2022-07-01-preview"
        Invoke-RestMethod -Uri $restUriWatchlistItemCreate -Method Put -Headers $authHeader -Body $body -ContentType 'application/json; charset=utf-16' | Out-Null

        if($?) {
            $added += "ADDED: '$($r.RoleAssignmentName)' to '$($watchlist.properties.displayName)'"
        }
    } else {
        $restUriWatchlistItemUpdate = $null

        # Update values in watchlist
        $watchlistItem = ($watchlistItems | Where-Object {$_.properties.itemsKeyValue.RoleAssignmentName -eq $r.RoleAssignmentName})

        if ($watchlistItem.properties.itemsKeyValue.RoleAssignmentName -ne $r.RoleAssignmentName `
            -or $watchlistItem.properties.itemsKeyValue.RoleDefinitionId -ne $r.RoleDefinitionId `
            -or $watchlistItem.properties.itemsKeyValue.RoleDefinitionName -ne $r.RoleDefinitionName `
            -or $watchlistItem.properties.itemsKeyValue.ScopeManagementGroup -ne $r.ScopeManagementGroup `
            -or $watchlistItem.properties.itemsKeyValue.ScopeSubscription -ne $r.ScopeSubscription `
            -or $watchlistItem.properties.itemsKeyValue.ScopeResourceGroup -ne $r.ScopeResourceGroup `
            -or $watchlistItem.properties.itemsKeyValue.ScopeResourceType -ne $r.ScopeResourceType `
            -or $watchlistItem.properties.itemsKeyValue.ScopeResource -ne $r.ScopeResource `
            -or $watchlistItem.properties.itemsKeyValue.ObjectId -ne $r.ObjectId `
            -or $watchlistItem.properties.itemsKeyValue.ObjectType -ne $r.ObjectType
        ) {
            $body = @{
                "properties" = @{
                    "etag" = $etag
                    "itemsKeyValue" = @{
                        "RoleAssignmentName" = $r.RoleAssignmentName
                        "RoleDefinitionId" = $r.RoleDefinitionId
                        "RoleDefinitionName" = $r.RoleDefinitionName
                        "ScopeManagementGroup" = $r.ScopeManagementGroup
                        "ScopeSubscription" = $r.ScopeSubscription
                        "ScopeResourceGroup" = $r.ScopeResourceGroup
                        "ScopeResourceType" = $r.ScopeResourceType
                        "ScopeResource" = $r.ScopeResource
                        "ObjectId" = $r.ObjectId
                        "ObjectType" = $r.ObjectType
                    }
                }
            }
    
            $body = $body | ConvertTo-Json -Depth 10
    
            $restUriWatchlistItemUpdate = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$workspaceResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/watchlists/$($watchlist.Name)/watchlistItems/$($watchlistItem.properties.watchlistItemId)?api-version=2022-07-01-preview"
            Invoke-RestMethod -Uri $restUriWatchlistItemUpdate -Method Put -Headers $authHeader -Body $body -ContentType 'application/json; charset=utf-16' | Out-Null
    
            if($?) {
                $updated += "UPDATED: '$($r.RoleAssignmentName)' in $($watchlist.properties.displayName)"
            }  
        }
    }
}

# Results
Write-Output "RESULTS"
if ($($added + $removed) -eq 0) {
    Write-Output "No changes made"
} else  {
    Write-Output $removed
    Write-Output $added
    # Write-Output $updated

    Write-Output "Total added: $($added.Count)"
    Write-Output "Total removed: $($removed.Count)"
    Write-Output "Total updated: $($updated.Count)"
}

exit 0