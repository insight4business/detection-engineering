# Problem solved : Enrich with mailbox inventory.
# What it does    : Refreshes mailboxes and distribution groups watchlist.
# Requires        : ExchangeOnlineManagement
# Effect          : changes-state (review and test before use)
# Origin          : adapted from field work; replace every ENTRE_AQUI_COM_SEU_* marker with your own value

###
# ExchangeOnlineManagement
# Az.Accounts

$ErrorActionPreference = "Stop"

$subscriptionId = "ENTRE_AQUI_COM_SEU_ID"
$workspaceResourceGroup = "Sentinel"
$workspaceName = "ENTRE_AQUI_COM_SEU_RECURSO"

$watchlistToUpdate = "Exchange-MailboxesAndDistributionGroups"

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

Connect-ExchangeOnline -ManagedIdentity -Organization 'ENTRE_AQUI_COM_SEU_TENANT.onmicrosoft.com' -ErrorAction Stop | Out-Null

## QUERY
## Mailboxes
$propertiesToReturn = @(
    "Guid",
    "Id",
    "DisplayName",
    "UserPrincipalName",
    "EmailAddresses",
    "Identity",
    "RecipientType",
    "RecipientTypeDetails",
    "ExternalDirectoryObjectId",
    "DistinguishedName"
)

$mailboxes = Get-EXOMailbox -ResultSize unlimited -IncludeInactiveMailbox 
# -Properties $propertiesToReturn
$mailboxes = $mailboxes += (Get-ExoMailbox -ResultSize unlimited -SoftDeletedMailbox)

Write-Host "Total mailboxes: $($mailboxes.Count)"

# Filter wanted mailboxes
$mailboxes = $mailboxes | Where-Object {$_.RecipientTypeDetails -ne "UserMailbox"}

# Treat fields
foreach ($m in $mailboxes) {
    Write-Progress -Id 1 -Activity "Processing mailboxes" -Status "[$($mailboxes.IndexOf($m) + 1) / $($mailboxes.Count)] Processing mailbox $($m.DisplayName)" -PercentComplete (($mailboxes.IndexOf($m) + 1) / $mailboxes.Count * 100)

    if ($m.Identity -like "Soft Deleted Objects\*") {
        $m | Add-Member -MemberType NoteProperty -Name "SoftDeleted" -Value $true -Force
    } else {
        $m | Add-Member -MemberType NoteProperty -Name "SoftDeleted" -Value $false -Force
    }
}
Write-Progress -Id 1 -Activity "Processing mailboxes" -Completed

$propertiesToReturn += ("SoftDeleted")

# Export Groups
$mailboxes = $mailboxes | Select-Object $propertiesToReturn

## Distribution Groups
$propertiesToReturn = @(
    "Guid",
    "Id",
    "Description",
    "DisplayName",
    "PrimarySmtpAddress",
    "EmailAddresses",
    "Identity",
    "RecipientType",
    "RecipientTypeDetails"
    "WhenChangedUTC",
    "WhenCreatedUTC",
    "ExternalDirectoryObjectId",
    "DistinguishedName"
)

$distributionGroups = Get-DistributionGroup -ResultSize unlimited -SortBy DisplayName

Write-Host "Total distribution groups: $($distributionGroups.Count)"

# Treat fields
foreach ($dg in $distributionGroups) {
    Write-Progress -Id 1 -Activity "Processing distribution groups" -Status "[$($distributionGroups.IndexOf($dg) + 1) / $($distributionGroups.Count)] Processing distribution group $($dg.DisplayName)" -PercentComplete (($distributionGroups.IndexOf($dg) + 1) / $distributionGroups.Count * 100)    

    $dg.Description = ($dg.Description)[0] -replace "`r`n", " "

    $dg.EmailAddresses = $dg.EmailAddresses -join ','
}
Write-Progress -Id 1 -Activity "Processing distribution groups" -Completed

# Export Groups
$distributionGroups = $distributionGroups | Select-Object $propertiesToReturn

$fullList = $mailboxes + $distributionGroups

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
    if (($fullList.Guid) -notcontains ($item.properties.itemsKeyValue.Guid)) {
        $restUriWatchlistItemDelete = $null

        # Remove watchlist item
        Write-Host "Removing '$($item.properties.itemsKeyValue.Guid)' ($($item.properties.itemsKeyValue.DisplayName)) from '$($watchlist.properties.displayName)'..."

        $restUriWatchlistItemDelete = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$workspaceResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/watchlists/$($watchlist.Name)/watchlistItems/$($item.properties.watchlistItemId)?api-version=2022-07-01-preview"
        Invoke-RestMethod -Uri $restUriWatchlistItemDelete -Method Delete -Headers $authHeader | Out-Null

        if($?) {
            $removed += "REMOVED: '$($item.properties.itemsKeyValue.Guid)' ($($item.properties.itemsKeyValue.DisplayName)) from $($watchlist.properties.displayName)"
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
foreach ($listItem in $fullList) {
    if ($listItem.Guid -notin ($watchlistItems.properties.itemsKeyValue.Guid)) {
        # Add watchlist item
        $count += 1

        Write-Host "Adding '$($listItem.Guid)' ($($listItem.DisplayName)) to '$($watchlist.properties.displayName)'..."

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
                    "Guid" = $listItem.Guid
                    "Id" = $listItem.Id
                    "Description" = $listItem.Description
                    "DisplayName" = $listItem.DisplayName
                    "PrimarySmtpAddress" = $listItem.PrimarySmtpAddress
                    "UserPrincipalName" = $listItem.UserPrincipalName
                    "EmailAddresses" = $listItem.EmailAddresses -join ";"
                    "Identity" = $listItem.Identity
                    "RecipientType" = $listItem.RecipientType
                    "RecipientTypeDetails" = $listItem.RecipientTypeDetails
                    "WhenChangedUTC" = $listItem.WhenChangedUTC
                    "WhenCreatedUTC" = $listItem.WhenCreatedUTC
                    "ExternalDirectoryObjectId" = $listItem.ExternalDirectoryObjectId
                    "DistinguishedName" = $listItem.DistinguishedName
                }
            }
        }
        $body = $body | ConvertTo-Json -Depth 10

        $restUriWatchlistItemCreate = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$workspaceResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/watchlists/$($watchlist.Name)/watchlistItems/$($etag)?api-version=2022-07-01-preview"
        Invoke-RestMethod -Uri $restUriWatchlistItemCreate -Method Put -Headers $authHeader -Body $body -ContentType 'application/json; charset=utf-16' | Out-Null

        if($?) {
            $added += "ADDED: '$($listItem.Guid)' ($($listItem.DisplayName)) to '$($watchlist.properties.displayName)'"
        }

    } else {
        # Update values in watchlist
        $watchlistItem = ($watchlistItems | Where-Object {$_.properties.itemsKeyValue.Guid -eq $listItem.Guid})

        if ($watchlistItem.properties.itemsKeyValue.Id -ne $listItem.Id `
            -or $watchlistItem.properties.itemsKeyValue.Description -ne $listItem.Description `
            -or $watchlistItem.properties.itemsKeyValue.DisplayName -ne $listItem.DisplayName `
            -or $watchlistItem.properties.itemsKeyValue.PrimarySmtpAddress -ne $listItem.PrimarySmtpAddress `
            -or $watchlistItem.properties.itemsKeyValue.UserPrincipalName -ne $listItem.UserPrincipalName `
            -or $watchlistItem.properties.itemsKeyValue.EmailAddresses -ne ($listItem.EmailAddresses -join ";") `
            -or $watchlistItem.properties.itemsKeyValue.Identity -ne $listItem.Identity `
            -or $watchlistItem.properties.itemsKeyValue.RecipientType -ne $listItem.RecipientType `
            -or $watchlistItem.properties.itemsKeyValue.RecipientTypeDetails -ne $listItem.RecipientTypeDetails `
            -or $watchlistItem.properties.itemsKeyValue.WhenChangedUTC -ne $listItem.WhenChangedUTC `
            -or $watchlistItem.properties.itemsKeyValue.WhenCreatedUTC -ne $listItem.WhenCreatedUTC `
            -or $watchlistItem.properties.itemsKeyValue.ExternalDirectoryObjectId -ne $listItem.ExternalDirectoryObjectId `
            -or $watchlistItem.properties.itemsKeyValue.DistinguishedName -ne $listItem.DistinguishedName
        ) {
            $body = @{
                "properties" = @{
                    "etag" = $etag
                    "itemsKeyValue" = @{
                        "Guid" = $listItem.Guid
                        "Id" = $listItem.Id
                        "Description" = $listItem.Description
                        "DisplayName" = $listItem.DisplayName
                        "PrimarySmtpAddress" = $listItem.PrimarySmtpAddress
                        "UserPrincipalName" = $listItem.UserPrincipalName
                        "EmailAddresses" = $listItem.EmailAddresses -join ";"
                        "Identity" = $listItem.Identity
                        "RecipientType" = $listItem.RecipientType
                        "RecipientTypeDetails" = $listItem.RecipientTypeDetails
                        "WhenChangedUTC" = $listItem.WhenChangedUTC
                        "WhenCreatedUTC" = $listItem.WhenCreatedUTC
                        "ExternalDirectoryObjectId" = $listItem.ExternalDirectoryObjectId
                        "DistinguishedName" = $listItem.DistinguishedName
                    }
                }
            }
    
            $body = $body | ConvertTo-Json -Depth 10
    
            $restUriWatchlistItemUpdate = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$workspaceResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/watchlists/$($watchlist.Name)/watchlistItems/$($watchlistItem.properties.watchlistItemId)?api-version=2022-07-01-preview"
            Invoke-RestMethod -Uri $restUriWatchlistItemUpdate -Method Put -Headers $authHeader -Body $body -ContentType 'application/json; charset=utf-16' | Out-Null
    
            if($?) {
                $updated += "UPDATED: '$($item.properties.itemsKeyValue.Guid)' ($($item.properties.itemsKeyValue.DisplayName)) in $($watchlist.properties.displayName)"
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