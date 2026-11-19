# Problem solved : Detections need current privileged Azure roles.
# What it does    : Refreshes watchlist of Azure role definitions.
# Requires        : Az.Accounts, Graph
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

$watchlistToUpdate = "Azure_Roles"

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
$propertiesToReturn = @(
    "Name",
    "Id",
    "Description",
    "IsCustom",
    "Actions",
    "NotActions",
    "DataActions",
    "NotDataActions",
    "AssignableScopes"
)

$roles = Get-AzRoleDefinition
$roles = $roles | Select-Object $propertiesToReturn

Write-Host "Total roles: $($roles.Count)"

$roleList = @()
foreach ($r in $roles) {
    $allActions = @()
    foreach ($a in $r.Actions) {
        $allActions += [PSCustomObject]@{
            Action = $a
            ActionType = "Action"
        }
    }

    foreach ($a in $r.NotActions) {
        $allActions += [PSCustomObject]@{
            Action = $a
            ActionType = "NotAction"
        }
    }

    foreach ($a in $r.DataActions) {
        $allActions += [PSCustomObject]@{
            Action = $a
            ActionType = "DataAction"
        }
    }

    foreach ($a in $r.NotDataActions) {
        $allActions += [PSCustomObject]@{
            Action = $a
            ActionType = "NotDataAction"
        }
    }

    foreach ($action in $allActions) {
        $roleList += [PSCustomObject]@{
            Name = $r.Name
            Id = $r.Id
            Description = $r.Description
            IsCustom = $r.IsCustom
            AssignableScopes = ($r.AssignableScopes | ConvertTo-Json -Compress).ToString()
            ActionType = $action.ActionType
            Action = $action.Action
            UniqueId = "$($r.Id)+$($action.Action)"
        }
    }
}

$roleList = $roleList | Sort-Object -Property UniqueId -Unique

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
    if ($item.properties.itemsKeyValue.UniqueId -notin $roleList.UniqueId) {
        # Remove watchlist item
        Write-Host "Removing '$($item.properties.itemsKeyValue.UniqueId)' ($($item.properties.itemsKeyValue.Name)) from '$($watchlist.properties.displayName)'..."

        $restUriWatchlistItemDelete = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$workspaceResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/watchlists/$($watchlist.Name)/watchlistItems/$($item.properties.watchlistItemId)?api-version=2022-07-01-preview"
        Invoke-RestMethod -Uri $restUriWatchlistItemDelete -Method Delete -Headers $authHeader | Out-Null

        if($?) {
            $removed += "REMOVED: '$($item.properties.itemsKeyValue.Id)' ($($item.properties.itemsKeyValue.Name)) from $($watchlist.properties.displayName)"
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
foreach ($r in $roleList) {
    Write-Progress -Id 1 -Activity "Updating watchlist '$($watchlist.properties.displayName)'" -Status "[($($roleList.IndexOf($r)) / $($roleList.Count))] Checking role '$($r.Name)' to '$($watchlist.properties.displayName)'..." -PercentComplete (($roleList.IndexOf($r) / $roleList.Count) * 100)

    if ($r.UniqueId -notin ($watchlistItems.properties.itemsKeyValue.UniqueId)) {
        # Add watchlist item
        $count += 1

        Write-Host "Adding '$($r.UniqueId)' ($($r.Name)) to '$($watchlist.properties.displayName)'..."

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
                    "Name" = $r.Name
                    "Id" = $r.Id
                    "Description" = $r.Description
                    "IsCustom" = $r.IsCustom
                    "Action" = $r.Action
                    "ActionType" = $r.ActionType
                    "AssignableScopes" = $r.AssignableScopes
                    "UniqueId" = $r.UniqueId
                }
            }
        }
        $body = $body | ConvertTo-Json -Depth 10

        $restUriWatchlistItemCreate = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$workspaceResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/watchlists/$($watchlist.Name)/watchlistItems/$($etag)?api-version=2022-07-01-preview"
        Invoke-RestMethod -Uri $restUriWatchlistItemCreate -Method Put -Headers $authHeader -Body $body -ContentType 'application/json; charset=utf-16' | Out-Null

        if($?) {
            $added += "ADDED: '$($r.UniqueId)' ($($r.Name)) to '$($watchlist.properties.displayName)'"
        }
    } else {
        # Update values in watchlist
        $watchlistItem = ($watchlistItems | Where-Object {$_.properties.itemsKeyValue.UniqueId -eq $r.UniqueId})

        if ( $watchlistItem.properties.itemsKeyValue.Name -ne $r.Name `
            -or $watchlistItem.properties.itemsKeyValue.Id -ne $r.Id `
            -or $watchlistItem.properties.itemsKeyValue.Description -ne $r.Description `
            -or $watchlistItem.properties.itemsKeyValue.IsCustom -ne $r.IsCustom `
            -or $watchlistItem.properties.itemsKeyValue.Action -ne $r.Action `
            -or $watchlistItem.properties.itemsKeyValue.ActionType -ne $r.ActionType `
            -or $watchlistItem.properties.itemsKeyValue.AssignableScopes -ne $r.AssignableScopes
        ) {
            $body = @{
                "properties" = @{
                    "etag" = $etag
                    "itemsKeyValue" = @{
                        "Name" = $r.Name
                        "Id" = $r.Id
                        "Description" = $r.Description
                        "IsCustom" = $r.IsCustom
                        "Action" = $r.Action
                        "ActionType" = $r.ActionType
                        "AssignableScopes" = $r.AssignableScopes
                        "UniqueId" = $r.UniqueId
                    }
                }
            }
    
            $body = $body | ConvertTo-Json -Depth 10
    
            $restUriWatchlistItemUpdate = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$workspaceResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/watchlists/$($watchlist.Name)/watchlistItems/$($watchlistItem.properties.watchlistItemId)?api-version=2022-07-01-preview"
            Invoke-RestMethod -Uri $restUriWatchlistItemUpdate -Method Put -Headers $authHeader -Body $body -ContentType 'application/json; charset=utf-16' | Out-Null
    
            if($?) {
                $updated += "UPDATED: '$($item.properties.itemsKeyValue.UniqueId)' ($($item.properties.itemsKeyValue.Name)) in $($watchlist.properties.displayName)"
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