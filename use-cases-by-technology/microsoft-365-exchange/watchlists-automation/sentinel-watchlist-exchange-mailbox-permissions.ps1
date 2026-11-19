# Problem solved : Detect abnormal mailbox delegations.
# What it does    : Collects mailbox/DL permissions into a watchlist.
# Requires        : ExchangeOnlineManagement; Sentinel Contributor
# Effect          : changes-state (review and test before use)
# Origin          : adapted from field work; replace every ENTRE_AQUI_COM_SEU_* marker with your own value

###
# ExchangeOnlineManagement
# Az.Accounts

$ErrorActionPreference = "Stop"

$subscriptionId = "ENTRE_AQUI_COM_SEU_ID"
$workspaceResourceGroup = "Sentinel"
$workspaceName = "ENTRE_AQUI_COM_SEU_RECURSO"

$watchlistToUpdate = "Exchange-MailboxesAndDistGroups-Permissions"

## MAIN
# Log in first with Connect-AzAccount if not using Cloud Shell
Connect-AzAccount -Subscription $subscriptionId -Identity -ErrorAction Stop
# Connect-AzAccount -Subscription $subscriptionId

Connect-ExchangeOnline -Organization 'ENTRE_AQUI_COM_SEU_TENANT.onmicrosoft.com' -ManagedIdentity -ErrorAction Stop | Out-Null

$azContext = Get-AzContext
$azProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
$profileClient = New-Object -TypeName Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient -ArgumentList ($azProfile)
$token = $profileClient.AcquireAccessToken($azContext.Subscription.TenantId)
$authHeader = @{
    'Content-Type'='application/json'
    'Authorization'='Bearer ' + $token.AccessToken
}

## QUERY
## Mailboxes
$propertiesToReturn = @(
    "Guid",
    "Id",
    "UserPrincipalName",
    "DisplayName",
    "EmailAddresses",
    "RecipientType",
    "RecipientTypeDetails",
    "Identity",
    "ExternalDirectoryObjectId",
    "DistinguishedName"
)

$mailboxes = Get-EXOMailbox -ResultSize unlimited -IncludeInactiveMailbox -Properties $propertiesToReturn
$mailboxes = $mailboxes += (Get-ExoMailbox -ResultSize unlimited -SoftDeletedMailbox)

Write-Host "Total mailboxes: $($mailboxes.Count)"

# Filter wanted mailboxes
$mailboxes = $mailboxes | Where-Object {$_.RecipientTypeDetails -ne "UserMailbox"}

# Get permissions for each mailbox
$permissionList = @()
foreach ($m in $mailboxes) {
    Write-Progress -Id 1 -Activity "Processing mailboxes" -Status "[$($mailboxes.IndexOf($m) + 1) / $($mailboxes.Count)] Getting members for '$($m.DisplayName)'" -PercentComplete (($mailboxes.IndexOf($m) + 1) / $mailboxes.Count * 100)

    $permissions = @()
    # $permissions = [array]((Get-EXOMailboxPermission -Identity $m.Guid -ResultSize unlimited) | Where-Object {$_.User -ne 'NT AUTHORITY\SELF'} | Select-Object Identity, User, AccessRights, IsInherited, Deny, InheritanceType)
    $permissions = [array]((Get-MailboxPermission -Identity $m.Guid -ResultSize unlimited) | Where-Object {$_.User -ne 'NT AUTHORITY\SELF'} | Select-Object Identity, User, UserSid,AccessRights, IsInherited, Deny, InheritanceType)
    
    if ($permissions.Count -gt 0) {
        foreach ($p in $permissions) {
            $permissionList += [PSCustomObject]@{
                Guid = $m.Guid
                Type = "Mailbox"
                Permission_Identity = $p.Identity
                Permission_User = $p.User
                Permission_AccessRights = $p.AccessRights -join ','
                Permission_IsInherited = $p.IsInherited
                Permission_Deny = $p.Deny.IsPresent
                Permission_InheritanceType = $p.InheritanceType
                UniqueId = "$($m.Guid)+$($p.UserSid)+$($p.AccessRights -join '')"
            }
        }
    }
}
Write-Progress -Id 1 -Activity "Processing mailboxes" -Completed

$propertiesToReturn = @(
    "Guid",
    "Type",
    "Permission_Identity",
    "Permission_User",
    "Permission_AccessRights",
    "Permission_IsInherited",
    "Permission_Deny",
    "Permission_InheritanceType"
    "UniqueId"
)

# Export Groups
$permissionList = $permissionList | Select-Object $propertiesToReturn

## Distribution Groups
$propertiesToReturn = @(
    "Guid",
    "Id",
    "Description",
    "DisplayName",
    "EmailAddresses",
    "PrimarySmtpAddress",
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

# Get permissions for each Distribution Group
$membershipList = @()
foreach ($dg in $distributionGroups) {
    Write-Progress -Id 1 -Activity "Processing distribution groups" -Status "[$($distributionGroups.IndexOf($dg) + 1) / $($distributionGroups.Count)] Getting members for '$($dg.DisplayName)'" -PercentComplete (($distributionGroups.IndexOf($dg) + 1) / $distributionGroups.Count * 100)

    # Owners
    if ($dg.ManagedBy.Count -gt 0) {
        foreach ($o in $dg.ManagedBy) {
            # $mailboxInfo = Get-EXOMailbox -Identity $o
            $mailboxInfo = Get-Mailbox -Identity $o

            $membershipList += [PSCustomObject]@{
                Guid = $dg.Guid
                Type = "DistributionGroup"
                Permission_Guid = $mailboxInfo.Guid
                Permission_Id = $mailboxInfo.Id
                Permission_Identity = $mailboxInfo.Identity
                Permission_DisplayName = $mailboxInfo.DisplayName
                Permission_PrimarySmtpAddress = $mailboxInfo.PrimarySmtpAddress
                Permission_RecipientTypeDetails = $mailboxInfo.RecipientTypeDetails
                Permission_DistinguishedName = $mailboxInfo.DistinguishedName
                Permission_Permission = "Owner"
                UniqueId = "$($dg.Guid)+$($mailboxInfo.Guid)+Owner"
            }
        }
    }

    # Members
    $members = @()
    $members = [array]((Get-DistributionGroupMember -Identity $dg.Guid -ResultSize unlimited) | Select-Object Guid, Id, Identity, DisplayName, PrimarySmtpAddress, RecipientTypeDetails, DistinguishedName)
    
    if ($members.Count -gt 0) {
        foreach ($m in $members) {
            $membershipList += [PSCustomObject]@{
                Guid = $dg.Guid
                Type = "DistributionGroup"
                Permission_Guid = $m.Guid
                Permission_Id = $m.Id
                Permission_Identity = $m.Identity
                Permission_DisplayName = $m.DisplayName
                Permission_PrimarySmtpAddress = $m.PrimarySmtpAddress
                Permission_RecipientTypeDetails = $m.RecipientTypeDetails
                Permission_DistinguishedName = $m.DistinguishedName
                Permission_Permission = "Member"
                UniqueId = "$($dg.Guid)+$($m.Guid)+Member"
            }
        }
    }
}
Write-Progress -Id 1 -Activity "Processing distribution groups" -Completed

$propertiesToReturn = @(
    "Guid",
    "Type",
    "Permission_Guid",
    "Permission_Id",
    "Permission_Identity",
    "Permission_DisplayName",
    "Permission_PrimarySmtpAddress",
    "Permission_RecipientTypeDetails",
    "Permission_DistinguishedName",
    "Permission_Permission",
    "UniqueId"
)

# Export Groups
$membershipList = $membershipList | Select-Object $propertiesToReturn

## COMBINE
$fullList = $permissionList + $membershipList

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
    if ($item.properties.itemsKeyValue.UniqueId -notin $fullList.UniqueId) {
        $restUriWatchlistItemDelete = $null

        # Remove watchlist item
        Write-Host "Removing '$($item.properties.itemsKeyValue.UniqueId)' ($($item.properties.itemsKeyValue.DisplayName)) from '$($watchlist.properties.displayName)'..."

        $restUriWatchlistItemDelete = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$workspaceResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/watchlists/$($watchlist.Name)/watchlistItems/$($item.properties.watchlistItemId)?api-version=2022-07-01-preview"
        Invoke-RestMethod -Uri $restUriWatchlistItemDelete -Method Delete -Headers $authHeader | Out-Null

        if($?) {
            $removed += "REMOVED: '$($item.properties.itemsKeyValue.UniqueId)' ($($item.properties.itemsKeyValue.DisplayName)) from $($watchlist.properties.displayName)"
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
    if ($listItem.UniqueId -notin ($watchlistItems.properties.itemsKeyValue.UniqueId)) {
        # Add watchlist item
        $count += 1

        Write-Host "Adding '$($listItem.UniqueId)' ($($listItem.DisplayName)) to '$($watchlist.properties.displayName)'..."

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
                    "Type" = $listItem.Type
                    "Permission_Guid" = $listItem.Permission_Guid
                    "Permission_Id" = $listItem.Permission_Id
                    "Permission_Identity" = $listItem.Permission_Identity
                    "Permission_DisplayName" = $listItem.Permission_DisplayName
                    "Permission_PrimarySmtpAddress" = $listItem.Permission_PrimarySmtpAddress
                    "Permission_RecipientTypeDetails" = $listItem.Permission_RecipientTypeDetails
                    "Permission_DistinguishedName" = $listItem.Permission_DistinguishedName
                    "Permission_Permission" = $listItem.Permission_Permission
                    "Permission_User" = $listItem.Permission_User
                    "Permission_AccessRights" = $listItem.Permission_AccessRights
                    "Permission_IsInherited" = $listItem.Permission_IsInherited
                    "Permission_Deny" = $listItem.Permission_Deny
                    "Permission_InheritanceType" = $listItem.Permission_InheritanceType
                    "UniqueId" = $listItem.UniqueId
                }
            }
        }
        $body = $body | ConvertTo-Json -Depth 10

        $restUriWatchlistItemCreate = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$workspaceResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/watchlists/$($watchlist.Name)/watchlistItems/$($etag)?api-version=2022-07-01-preview"
        Invoke-RestMethod -Uri $restUriWatchlistItemCreate -Method Put -Headers $authHeader -Body $body -ContentType 'application/json; charset=utf-16' | Out-Null

        if($?) {
            $added += "ADDED: '$($listItem.UniqueId)' ($($listItem.DisplayName)) to '$($watchlist.properties.displayName)'"
        }

    } else {
        # Update values in watchlist
        $watchlistItem = ($watchlistItems | Where-Object {$_.properties.itemsKeyValue.UniqueId -eq $listItem.UniqueId})

        if ( $watchlistItem.properties.itemsKeyValue.Guid -ne $listItem.Guid `
            -or $watchlistItem.properties.itemsKeyValue.Type -ne $listItem.Type `
            -or $watchlistItem.properties.itemsKeyValue.Permission_Guid -ne $listItem.Permission_Guid `
            -or $watchlistItem.properties.itemsKeyValue.Permission_Id -ne $listItem.Permission_Id `
            -or $watchlistItem.properties.itemsKeyValue.Permission_Identity -ne $listItem.Permission_Identity `
            -or $watchlistItem.properties.itemsKeyValue.Permission_DisplayName -ne $listItem.Permission_DisplayName `
            -or $watchlistItem.properties.itemsKeyValue.Permission_PrimarySmtpAddress -ne $listItem.Permission_PrimarySmtpAddress `
            -or $watchlistItem.properties.itemsKeyValue.Permission_RecipientTypeDetails -ne $listItem.Permission_RecipientTypeDetails `
            -or $watchlistItem.properties.itemsKeyValue.Permission_DistinguishedName -ne $listItem.Permission_DistinguishedName `
            -or $watchlistItem.properties.itemsKeyValue.Permission_Permission -ne $listItem.Permission_Permission `
            -or $watchlistItem.properties.itemsKeyValue.Permission_User -ne $listItem.Permission_User `
            -or $watchlistItem.properties.itemsKeyValue.Permission_AccessRights -ne $listItem.Permission_AccessRights `
            -or $watchlistItem.properties.itemsKeyValue.Permission_IsInherited -ne $listItem.Permission_IsInherited `
            -or $watchlistItem.properties.itemsKeyValue.Permission_Deny -ne $listItem.Permission_Deny `
            -or $watchlistItem.properties.itemsKeyValue.Permission_InheritanceType -ne $listItem.Permission_InheritanceType
        ) {
            $body = @{
                "properties" = @{
                    "etag" = $etag
                    "itemsKeyValue" = @{
                        "Guid" = $listItem.Guid
                        "Type" = $listItem.Type
                        "Permission_Guid" = $listItem.Permission_Guid
                        "Permission_Id" = $listItem.Permission_Id
                        "Permission_Identity" = $listItem.Permission_Identity
                        "Permission_DisplayName" = $listItem.Permission_DisplayName
                        "Permission_PrimarySmtpAddress" = $listItem.Permission_PrimarySmtpAddress
                        "Permission_RecipientTypeDetails" = $listItem.Permission_RecipientTypeDetails
                        "Permission_DistinguishedName" = $listItem.Permission_DistinguishedName
                        "Permission_Permission" = $listItem.Permission_Permission
                        "Permission_User" = $listItem.Permission_User
                        "Permission_AccessRights" = $listItem.Permission_AccessRights
                        "Permission_IsInherited" = $listItem.Permission_IsInherited
                        "Permission_Deny" = $listItem.Permission_Deny
                        "Permission_InheritanceType" = $listItem.Permission_InheritanceType
                        "UniqueId" = $listItem.UniqueId
                    }
                }
            }
    
            $body = $body | ConvertTo-Json -Depth 10
    
            $restUriWatchlistItemUpdate = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$workspaceResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/watchlists/$($watchlist.Name)/watchlistItems/$($watchlistItem.properties.watchlistItemId)?api-version=2022-07-01-preview"
            Invoke-RestMethod -Uri $restUriWatchlistItemUpdate -Method Put -Headers $authHeader -Body $body -ContentType 'application/json; charset=utf-16' | Out-Null
    
            if($?) {
                $updated += "UPDATED: '$($item.properties.itemsKeyValue.UniqueId)' ($($item.properties.itemsKeyValue.DisplayName)) in $($watchlist.properties.displayName)"
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