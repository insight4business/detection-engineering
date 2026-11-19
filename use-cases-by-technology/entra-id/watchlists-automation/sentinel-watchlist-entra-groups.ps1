# Problem solved : Enrich alerts with group info.
# What it does    : Refreshes Entra groups watchlist.
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

$watchlistToUpdate = "AzureAD-Groups"

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
# Get groups
$groupPropertiesToReturn = @(
    "Id", 
    "DisplayName",
    "Description",
    "CreatedDateTime",
    "GroupTypes",
    "MembershipRule",
    "SecurityEnabled",
    "MailEnabled",
    "Visibility"
)

$groups = Get-MgGroup -All -CountVariable groupCount -Property $groupPropertiesToReturn -Sort DisplayName

Write-Host "Total groups: $groupCount"

# Treat fields
foreach ($g in $groups) {
    $groupType, $groupMembership, $securityBaseline = $null
    
    $groupType = switch ($g) {
        { $_.GroupTypes -contains "Unified" } { "Microsoft 365" }
        { $_.GroupTypes -notcontains "Unified" -and $_.MailEnabled -eq $true } { "Mail" }
        Default { "Security" }
    }
    
    $groupMembership = switch ($g) {
        { $_.GroupTypes -contains "DynamicMembership" } { "Dynamic" }
        Default { "Assigned" }
    }

    $securityBaseline = switch ($g) {
        { $_.Description -like '*`[SecurityBaseline`]*' } { $true }
        Default { $false }
    }

    $g | Add-Member -MemberType NoteProperty -Name "GroupType" -Value $groupType
    $g | Add-Member -MemberType NoteProperty -Name "GroupMembership" -Value $groupMembership
    $g | Add-Member -MemberType NoteProperty -Name "Baseline" -Value $securityBaseline
}

# Groups
$groupPropertiesToReturn += ("GroupMembership", "GroupType", "Baseline")
$groupPropertiesToReturn = $groupPropertiesToReturn | Where-Object {$_ -notin ("GroupTypes")}

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
    if (($groups.Id) -notcontains ($item.properties.itemsKeyValue.Id)) {
        $restUriWatchlistItemDelete = $null

        # Remove watchlist item
        Write-Host "Removing '$($item.properties.itemsKeyValue.Id)' ($($item.properties.itemsKeyValue.DisplayName)) from '$($watchlist.properties.displayName)'..."

        $restUriWatchlistItemDelete = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$workspaceResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/watchlists/$($watchlist.Name)/watchlistItems/$($item.properties.watchlistItemId)?api-version=2022-07-01-preview"
        Invoke-RestMethod -Uri $restUriWatchlistItemDelete -Method Delete -Headers $authHeader | Out-Null

        if($?) {
            $removed += "REMOVED: '$($item.properties.itemsKeyValue.Id)' ($($item.properties.itemsKeyValue.DisplayName)) from $($watchlist.properties.displayName)"
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
foreach ($g in $groups) {
    if (($watchlistItems.properties.itemsKeyValue.Id) -notcontains ($g.Id)) {
        # Add watchlist item
        $count += 1

        Write-Host "Adding '$($g.Id)' ($($g.DisplayName)) to '$($watchlist.properties.displayName)'..."

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
                    "Id" = $g.Id
                    "DisplayName" = $g.DisplayName
                    "Description" = $g.Description
                    "CreatedDateTime" = ($g.CreatedDateTime).ToString("yyyy-MM-ddTHH:mm:ssZ")
                    "GroupMembership" = $g.GroupMembership
                    "MembershipRule" = $g.MembershipRule
                    "GroupType" = $g.GroupType
                    "SecurityEnabled" = $g.SecurityEnabled
                    "MailEnabled" = $g.MailEnabled
                    # "M365Enabled" = $g.M365Enabled
                    "Visibility" = $g.Visibility
                    "Baseline" = $g.Baseline
                }
            }
        }
        $body = $body | ConvertTo-Json -Depth 10

        $restUriWatchlistItemCreate = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$workspaceResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/watchlists/$($watchlist.Name)/watchlistItems/$($etag)?api-version=2022-07-01-preview"
        Invoke-RestMethod -Uri $restUriWatchlistItemCreate -Method Put -Headers $authHeader -Body $body -ContentType 'application/json; charset=utf-16' | Out-Null

        if($?) {
            $added += "ADDED: '$($g.Id)' ($($g.DisplayName)) to '$($watchlist.properties.displayName)'"
        }
    } else {
        $restUriWatchlistItemUpdate = $null

        # Update values in watchlist
        $watchlistItem = ($watchlistItems | Where-Object {$_.properties.itemsKeyValue.Id -eq $g.Id})

        # Update only if values have changed
        if ($watchlistItem.properties.itemsKeyValue.Id -ne $g.Id `
            -or $watchlistItem.properties.itemsKeyValue.DisplayName -ne $g.DisplayName `
            -or $watchlistItem.properties.itemsKeyValue.Description -ne $g.Description `
            -or $watchlistItem.properties.itemsKeyValue.CreatedDateTime -ne ($g.CreatedDateTime).ToString("yyyy-MM-ddTHH:mm:ssZ") `
            -or $watchlistItem.properties.itemsKeyValue.MembershipRule -ne $g.MembershipRule `
            -or $watchlistItem.properties.itemsKeyValue.GroupMembership -ne $g.GroupMembership `
            -or $watchlistItem.properties.itemsKeyValue.GroupType -ne $g.GroupType `
            -or $watchlistItem.properties.itemsKeyValue.SecurityEnabled -ne $g.SecurityEnabled `
            -or $watchlistItem.properties.itemsKeyValue.MailEnabled -ne $g.MailEnabled `
            -or $watchlistItem.properties.itemsKeyValue.Visibility -ne $g.Visibility `
            -or $watchlistItem.properties.itemsKeyValue.Baseline -ne $g.Baseline
        ) {
        
            $body = @{
                "properties" = @{ 
                    "etag" = $etag
                    "itemsKeyValue" = @{
                        "Id" = $g.Id
                        "DisplayName" = $g.DisplayName
                        "Description" = $g.Description
                        "CreatedDateTime" = ($g.CreatedDateTime).ToString("yyyy-MM-ddTHH:mm:ssZ")
                        "GroupMembership" = $g.GroupMembership
                        "MembershipRule" = $g.MembershipRule
                        "GroupType" = $g.GroupType
                        "SecurityEnabled" = $g.SecurityEnabled
                        "MailEnabled" = $g.MailEnabled
                        # "M365Enabled" = $g.M365Enabled
                        "Visibility" = $g.Visibility
                        "Baseline" = $g.Baseline
                    }
                }
            }
    
            $body = $body | ConvertTo-Json -Depth 10
    
            $restUriWatchlistItemUpdate = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$workspaceResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/watchlists/$($watchlist.Name)/watchlistItems/$($watchlistItem.properties.watchlistItemId)?api-version=2022-07-01-preview"
            Invoke-RestMethod -Uri $restUriWatchlistItemUpdate -Method Put -Headers $authHeader -Body $body -ContentType 'application/json; charset=utf-16' | Out-Null
    
            if($?) {
                $updated += "UPDATED: '$($item.properties.itemsKeyValue.Id)' ($($item.properties.itemsKeyValue.DisplayName)) in $($watchlist.properties.displayName)"
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