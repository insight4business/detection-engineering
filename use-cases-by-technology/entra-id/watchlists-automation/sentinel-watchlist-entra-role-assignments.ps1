# Problem solved : Detect privileged role changes by comparing with known assignments.
# What it does    : Refreshes watchlist of directory role assignments.
# Requires        : Microsoft.Graph
# Effect          : changes-state (review and test before use)
# Origin          : adapted from field work; replace every ENTRE_AQUI_COM_SEU_* marker with your own value

###
# Microsoft.Graph.Users
# Microsoft.Graph.Groups
# Az.Accounts

$ErrorActionPreference = "Stop"

$subscriptionId = "ENTRE_AQUI_COM_SEU_ID"
$workspaceResourceGroup = "Sentinel"
$workspaceName = "ENTRE_AQUI_COM_SEU_RECURSO"

$watchlistToUpdate = "AzureAD-RoleAssignments"

## MAIN
# Log in first with Connect-AzAccount if not using Cloud Shell
Connect-AzAccount -Identity -Subscription $subscriptionId -ErrorAction Stop
# Connect-AzAccount -Subscription $subscriptionId -ErrorAction Stop

$azContext = Get-AzContext
$azProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
$profileClient = New-Object -TypeName Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient -ArgumentList ($azProfile)
$token = $profileClient.AcquireAccessToken($azContext.Subscription.TenantId)
$authHeader = @{
    'Content-Type'='application/json'
    'Authorization'='Bearer ' + $token.AccessToken
}

# Connect MS Graph and Azure AD
$context = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile.DefaultContext
$graphToken = ([Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate($context.Account, $context.Environment, $context.Tenant.Id.ToString(), $null, [Microsoft.Azure.Commands.Common.Authentication.ShowDialog]::Never, $null, "https://graph.microsoft.com").AccessToken) | ConvertTo-SecureString -AsPlainText -Force
# $aadToken = ([Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate($context.Account, $context.Environment, $context.Tenant.Id.ToString(), $null, [Microsoft.Azure.Commands.Common.Authentication.ShowDialog]::Never, $null, "https://graph.windows.net").AccessToken) | ConvertTo-SecureString -AsPlainText -Force

Connect-MgGraph -AccessToken $graphToken -ErrorAction Stop
# Write-Output (Get-MgContext)

## QUERY
$propertiesToReturn = [PSCustomObject]@{
    Groups = @("Id", "DisplayName" )
    Users = @("Id", "DisplayName", "UserPrincipalName","AccountEnabled")
    Devices = @("Id", "DisplayName", "AccountEnabled")
    ServicePrincipals = @("Id", "AppId", "DisplayName", "AccountEnabled", "ServicePrincipalType", "AdditionalProperties")
}

# GROUPS
$groups = Get-MgGroup -All -Property $propertiesToReturn.Groups | Sort-Object DisplayName | Select-Object $propertiesToReturn.Groups
$groups | ForEach-Object { $_ | Add-Member -MemberType NoteProperty -Name "PrincipalType" -Value "Group" }
Write-Host "Total groups: $groupCount"

# USERS
$users = Get-MgUser -All -Property $propertiesToReturn.Users | Sort-Object DisplayName | Select-Object $propertiesToReturn.Users
$users | ForEach-Object { $_ | Add-Member -MemberType NoteProperty -Name "PrincipalType" -Value "User" }

# DEVICES
$devices = Get-MgDevice -All -Property $propertiesToReturn.Devices | Sort-Object DisplayName | Select-Object $propertiesToReturn.Devices
$devices | ForEach-Object { $_ | Add-Member -MemberType NoteProperty -Name "PrincipalType" -Value "Device" }

# SERVICE PRINCIPALS
$servicePrincipals = Get-MgServicePrincipal -All -Property $propertiesToReturn.ServicePrincipals | Sort-Object DisplayName | Select-Object $propertiesToReturn.ServicePrincipals
$servicePrincipals | ForEach-Object { $_ | Add-Member -MemberType NoteProperty -Name "PrincipalType" -Value "ServicePrincipal" }

# ROLES
$rolesUri = "https://graph.microsoft.com/v1.0/roleManagement/directory/roleDefinitions"
$roles = [array]((Invoke-MgGraphRequest -Uri $rolesUri -Method Get -Headers $authHeader).value)

$roleAssignmentsUri = "https://graph.microsoft.com/v1.0/roleManagement/directory/roleAssignments"
$roleAssignments = [array]((Invoke-MgGraphRequest -Uri $roleAssignmentsUri -Method Get -Headers $authHeader).value)

Write-Host "Total roles: $($roles.Count)"

$roleAssignmentList = @()
foreach ($ra in $roleAssignments) {
    $role = ($roles | Where-Object {$_.id -eq $ra.roleDefinitionId})

    $principalType = $null

    $principalType = ($users | Where-Object { $_.Id -eq $ra.principalId }).PrincipalType
    if ($null -eq $principalType) {
        $principalType = ($groups | Where-Object { $_.Id -eq $ra.principalId }).PrincipalType
        if ($null -eq $principalType) {
            $principalType = ($devices | Where-Object { $_.Id -eq $ra.principalId }).PrincipalType
            if ($null -eq $principalType) {
                $principalType = ($servicePrincipals | Where-Object { $_.Id -eq $ra.principalId }).PrincipalType
                if ($null -eq $principalType) {
                    $principalType = "Unknown"
                }
            }
        }
    }

    $roleAssignmentList += [pscustomobject]@{
        AssignmentId = $ra.id
        RoleDefinitionId = $ra.roleDefinitionId
        RoleDefinitionDisplayName = $role.displayName
        Scope = $ra.directoryScopeId
        PrincipalId = $ra.principalId
        PrincipalType = $principalType
    }
}

$roleAssignmentList = $roleAssignmentList | Sort-Object RoleDefinitionDisplayName

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

# Remove watchlist items which are not in the current group list
foreach ($item in $watchlistItems) {
    if ($item.properties.itemsKeyValue.AssignmentId -notin $roleAssignmentList.AssignmentId) {
        # Remove watchlist item
        Write-Host "Removing '$($item.properties.itemsKeyValue.AssignmentId)' ($($item.properties.itemsKeyValue.RoleDefinitionDisplayName)) from '$($watchlist.properties.displayName)'..."

        $restUriWatchlistItemDelete = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$workspaceResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/watchlists/$($watchlist.Name)/watchlistItems/$($item.properties.watchlistItemId)?api-version=2022-07-01-preview"
        Invoke-RestMethod -Uri $restUriWatchlistItemDelete -Method Delete -Headers $authHeader | Out-Null

        if($?) {
            $removed += "REMOVED: '$($item.properties.itemsKeyValue.AssignmentId)' ($($item.properties.itemsKeyValue.RoleDefinitionDisplayName)) from $($watchlist.properties.displayName)"
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
foreach ($ra in $roleAssignmentList) {
    Write-Progress -Id 1 -Activity "Updating watchlist '$($watchlist.properties.displayName)'" -Status "[($($roleAssignmentList.IndexOf($r)) / $($roleAssignmentList.Count))] Checking role '$($ra.RoleDefinitionDisplayName)' to '$($watchlist.properties.displayName)'..." -PercentComplete (($roleAssignmentList.IndexOf($r) / $roleAssignmentList.Count) * 100)

    if ($ra.AssignmentId -notin ($watchlistItems.properties.itemsKeyValue.AssignmentId)) {
        # Add watchlist item
        $count += 1

        Write-Host "Adding '$($ra.AssignmentId)' ($($ra.RoleDefinitionDisplayName)) to '$($watchlist.properties.displayName)'..."

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
                    "AssignmentId" = $ra.AssignmentId
                    "RoleDefinitionId" = $ra.RoleDefinitionId
                    "RoleDefinitionDisplayName" = $ra.RoleDefinitionDisplayName
                    "Scope" = $ra.Scope
                    "PrincipalId" = $ra.PrincipalId
                    "PrincipalType" = $ra.PrincipalType
                }
            }
        }
        $body = $body | ConvertTo-Json -Depth 10

        $restUriWatchlistItemCreate = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$workspaceResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/watchlists/$($watchlist.Name)/watchlistItems/$($etag)?api-version=2022-07-01-preview"
        Invoke-RestMethod -Uri $restUriWatchlistItemCreate -Method Put -Headers $authHeader -Body $body -ContentType 'application/json; charset=utf-16' | Out-Null

        if($?) {
            $added += "ADDED: '$($ra.AssignmentId)' ($($ra.DisplayName)) to '$($watchlist.properties.displayName)'"
        }
    } else {
        # Update values in watchlist
        $watchlistItem = ($watchlistItems | Where-Object {$_.properties.itemsKeyValue.AssignmentId -eq $ra.AssignmentId})

        if ($watchlistItem.properties.itemsKeyValue.RoleDefinitionId -ne $ra.RoleDefinitionId `
            -or $watchlistItem.properties.itemsKeyValue.RoleDefinitionDisplayName -ne $ra.RoleDefinitionDisplayName `
            -or $watchlistItem.properties.itemsKeyValue.Scope -ne $ra.Scope `
            -or $watchlistItem.properties.itemsKeyValue.PrincipalId -ne $ra.PrincipalId `
            -or $watchlistItem.properties.itemsKeyValue.PrincipalType -ne $ra.PrincipalType
        ) {
            $body = @{
                "properties" = @{
                    "etag" = $etag
                    "itemsKeyValue" = @{
                        "AssignmentId" = $ra.AssignmentId
                        "RoleDefinitionId" = $ra.RoleDefinitionId
                        "RoleDefinitionDisplayName" = $ra.RoleDefinitionDisplayName
                        "Scope" = $ra.Scope
                        "PrincipalId" = $ra.PrincipalId
                        "PrincipalType" = $ra.PrincipalType
                    }
                }
            }
    
            $body = $body | ConvertTo-Json -Depth 10
    
            $restUriWatchlistItemUpdate = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$workspaceResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/watchlists/$($watchlist.Name)/watchlistItems/$($watchlistItem.properties.watchlistItemId)?api-version=2022-07-01-preview"
            Invoke-RestMethod -Uri $restUriWatchlistItemUpdate -Method Put -Headers $authHeader -Body $body -ContentType 'application/json; charset=utf-16' | Out-Null
    
            if($?) {
                $updated += "UPDATED: '$($item.properties.itemsKeyValue.Id)' ($($item.properties.itemsKeyValue.RoleDefinitionDisplayName)) in $($watchlist.properties.displayName)"
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