# Problem solved : Rules must know who belongs to sensitive groups.
# What it does    : Dumps group membership into a watchlist.
# Requires        : Microsoft.Graph; Sentinel Contributor
# Effect          : changes-state (review and test before use)
# Origin          : adapted from field work; replace every ENTRE_AQUI_COM_SEU_* marker with your own value

###
# Microsoft.Graph.Users
# Microsoft.Graph.Groups
# Microsoft.Graph.Authentication
# Microsoft.Graph.Identity.DirectoryManagement
# Az.Accounts

$ErrorActionPreference = "Stop"

$subscriptionId = "ENTRE_AQUI_COM_SEU_ID"
$workspaceResourceGroup = "Sentinel"
$workspaceName = "ENTRE_AQUI_COM_SEU_RECURSO"

$watchlistToUpdate = "AzureAD-GroupMembership"

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
    Groups = @( "Id", "DisplayName", "Description", "CreatedDateTime", "DeletedDateTime", "SecurityEnabled", "MailEnabled", "GroupTypes", "Visibility", "MembershipRule" )
    Users = @( "Id", "DisplayName", "UserPrincipalName", "AccountEnabled", "JobTitle", "Department", "CompanyName", "Country", "UserType", "CreatedDateTime", "DeletedDateTime")
    Devices = @( "Id", "DisplayName", "DeviceId", "AccountEnabled", "IsCompliant", "IsManaged", "ProfileType", "TrustType", "AdditionalProperties")
    ServicePrincipals = @( "Id", "AppId", "DisplayName", "AccountEnabled", "ServicePrincipalType", "AdditionalProperties")
}

# GROUPS
$groups = Get-MgGroup -All -Property $propertiesToReturn.Groups | Sort-Object DisplayName | Select-Object $propertiesToReturn.Groups
$groups | ForEach-Object { $_ | Add-Member -MemberType NoteProperty -Name "MemberType" -Value "Group" }
Write-Host "Total groups: $groupCount"

# USERS
$users = Get-MgUser -All -Property $propertiesToReturn.Users | Sort-Object DisplayName | Select-Object $propertiesToReturn.Users
$users | ForEach-Object { $_ | Add-Member -MemberType NoteProperty -Name "MemberType" -Value "User" }

# DEVICES
$devices = Get-MgDevice -All -Property $propertiesToReturn.Devices | Sort-Object DisplayName | Select-Object $propertiesToReturn.Devices
$devices | ForEach-Object { $_ | Add-Member -MemberType NoteProperty -Name "MemberType" -Value "Device" }

# SERVICE PRINCIPALS
$servicePrincipals = Get-MgServicePrincipal -All -Property $propertiesToReturn.ServicePrincipals | Sort-Object DisplayName | Select-Object $propertiesToReturn.ServicePrincipals
$servicePrincipals | ForEach-Object { $_ | Add-Member -MemberType NoteProperty -Name "MemberType" -Value "ServicePrincipal" }

# Treat fields
foreach ($g in $groups) {

    $groupType, $groupMembership = $null
    
    $groupType = switch ($g) {
        { $_.GroupTypes -contains "Unified" } { "Microsoft 365" }
        { $_.GroupTypes -notcontains "Unified" -and $_.MailEnabled -eq $true } { "Mail" }
        Default { "Security" }
    }
    
    $groupMembership = switch ($g) {
        { $_.GroupTypes -contains "DynamicMembership" } { "Dynamic" }
        Default { "Assigned" }
    }

    $securityBaseline = switch($g) {
        { $_.Description -like '*`[SecurityBaseline`]*' } { $true }
        Default { $false }
    }

    $g | Add-Member -MemberType NoteProperty -Name "GroupType" -Value $groupType
    $g | Add-Member -MemberType NoteProperty -Name "GroupMembership" -Value $groupMembership
    $g | Add-Member -MemberType NoteProperty -Name "SecurityBaseline" -Value $securityBaseline
}

# Groups
$groupPropertiesToReturn += ("GroupMembership", "GroupType", "SecurityBaseline")
$propertiesToReturn.Groups = $propertiesToReturn.Groups | Where-Object {$_ -notin ("GroupTypes")}

## Group memberships
# Get members and owners
$membershipList = @()

foreach ($g in $groups) {
    $members, $owners = $null
    
    # Get group members
    $members = [array](Get-MgGroupMember -All -GroupId $g.Id)

    if ($members) {
        foreach ($m in $members) {
            $member = $null

            $member = $users | Where-Object { $_.Id -eq $m.Id }
            if ($null -eq $member) {
                $member = $groups | Where-Object { $_.Id -eq $m.Id }
                if ($null -eq $member) {
                    $member = $devices | Where-Object { $_.Id -eq $m.Id }
                    if ($null -eq $member) {
                        $member = $servicePrincipals | Where-Object { $_.Id -eq $m.Id }
                        if ($null -eq $member) {
                            $member = [PSCustomObject]@{
                                Id = $m.Id
                                DisplayName = $null
                                UserPrincipalName = $null
                                JobTitle = $null
                                Department = $null
                                Company = $null
                                UserType = $null
                                MemberType = "Unknown"
                            }
                        }
                    }
                }
            } 

            $membershipList += [PSCustomObject]@{
                Group_Id = $g.Id
                Member_Id = $m.Id
                Member_DisplayName = $m.AdditionalProperties['displayName']
                Member_JobTitle = $m.AdditionalProperties['jobTitle']
                Member_Mail = $m.AdditionalProperties['mail']
                Member_UserPrincipalName = $m.AdditionalProperties['userPrincipalName']
                Member_Permission = "Member"
                Member_Type = $member.MemberType
                UniqueId = "$($g.Id)+$($m.Id)+Member"
            }
        }
    }    

    # Get group owners
    $owners = [array](Get-MgGroupOwner -All -GroupId $g.Id)

    if ($owners) {
        foreach ($o in $owners) {
            $owner = $null

            $owner = $users | Where-Object { $_.Id -eq $o.Id }
            if ($null -eq $owner) {
                $owner = $groups | Where-Object { $_.Id -eq $o.Id }
                if ($null -eq $owner) {
                    $owner = $devices | Where-Object { $_.Id -eq $o.Id }
                    if ($null -eq $owner) {
                        $owner = $servicePrincipals | Where-Object { $_.Id -eq $o.Id }
                        if ($null -eq $owner) {
                            $owner = [PSCustomObject]@{
                                Id = $o.Id
                                DisplayName = $null
                                UserPrincipalName = $null
                                JobTitle = $null
                                Department = $null
                                Company = $null
                                UserType = $null
                                MemberType = "Unknown"
                            }
                        }
                    }
                }
            } 

            $membershipList += [PSCustomObject]@{
                Group_Id = $g.Id
                Member_Id = $o.Id
                Member_DisplayName = $o.AdditionalProperties['displayName']
                Member_JobTitle = $o.AdditionalProperties['jobTitle']
                Member_Mail = $o.AdditionalProperties['mail']
                Member_UserPrincipalName = $o.AdditionalProperties['userPrincipalName']
                Member_Permission = "Owner"
                Member_Type = $owner.MemberType
                UniqueId = "$($g.Id)+$($o.Id)+Owner"
            }
        }
    }
}

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
    if (($membershipList.UniqueId) -notcontains ($item.properties.itemsKeyValue.UniqueId)) {
        $restUriWatchlistItemDelete = $null

        # Remove watchlist item
        Write-Host "Removing '$($item.properties.itemsKeyValue.UniqueId)' from '$($watchlist.properties.displayName)'..."

        $restUriWatchlistItemDelete = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$workspaceResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/watchlists/$($watchlist.Name)/watchlistItems/$($item.properties.watchlistItemId)?api-version=2022-07-01-preview"
        Invoke-RestMethod -Uri $restUriWatchlistItemDelete -Method Delete -Headers $authHeader | Out-Null
        
        if($?) {
            $removed += "REMOVED: '$($item.properties.itemsKeyValue.UniqueId)' from $($watchlist.properties.displayName)"
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
foreach ($m in $membershipList) {
    if (($watchlistItems.properties.itemsKeyValue.UniqueId) -notcontains ($m.UniqueId)) {
        # Add watchlist item
        $count += 1

        Write-Host "Adding '$($m.UniqueId)' to '$($watchlist.properties.displayName)'..."

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
                    "UniqueId" = $m.UniqueId
                    "Group_Id" = $m.Group_Id
                    "Member_Id" = $m.Member_Id
                    "Member_DisplayName" = $m.Member_DisplayName
                    "Member_UserPrincipalName" = $m.Member_UserPrincipalName
                    "Member_Permission" = $m.Member_Permission
                    "Member_Type" = $m.Member_Type
                }
            }
        }
        $body = $body | ConvertTo-Json -Depth 10

        $restUriWatchlistItemCreate = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$workspaceResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/watchlists/$($watchlist.Name)/watchlistItems/$($etag)?api-version=2022-07-01-preview"
        Invoke-RestMethod -Uri $restUriWatchlistItemCreate -Method Put -Headers $authHeader -Body $body -ContentType 'application/json; charset=utf-16' | Out-Null

        if($?) {
            $added += "ADDED: '$($m.UniqueId)' to '$($watchlist.properties.displayName)'"
        }
    } else {
        $restUriWatchlistItemUpdate = $null

        # Update values in watchlist
        $watchlistItem = ($watchlistItems | Where-Object {$_.properties.itemsKeyValue.UniqueId -eq $m.UniqueId})

        if ($watchlistItem.properties.itemsKeyValue.Group_Id -ne $m.Group_Id `
            -or $watchlistItem.properties.itemsKeyValue.Member_Id -ne $m.Member_Id `
            -or $watchlistItem.properties.itemsKeyValue.Member_DisplayName -ne $m.Member_DisplayName `
            -or $watchlistItem.properties.itemsKeyValue.Member_UserPrincipalName -ne $m.Member_UserPrincipalName `
            -or $watchlistItem.properties.itemsKeyValue.Member_Permission -ne $m.Member_Permission `
            -or $watchlistItem.properties.itemsKeyValue.Member_Type -ne $m.Member_Type
        ) {
            $body = @{
                "properties" = @{
                    "etag" = $etag
                    "itemsKeyValue" = @{
                        "UniqueId" = $m.UniqueId
                        "Group_Id" = $m.Group_Id
                        "Member_Id" = $m.Member_Id
                        "Member_DisplayName" = $m.Member_DisplayName
                        "Member_UserPrincipalName" = $m.Member_UserPrincipalName
                        "Member_Permission" = $m.Member_Permission
                        "Member_Type" = $m.Member_Type
                    }
                }
            }
    
            $body = $body | ConvertTo-Json -Depth 10
    
            $restUriWatchlistItemUpdate = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$workspaceResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/watchlists/$($watchlist.Name)/watchlistItems/$($watchlistItem.properties.watchlistItemId)?api-version=2022-07-01-preview"
            Invoke-RestMethod -Uri $restUriWatchlistItemUpdate -Method Put -Headers $authHeader -Body $body -ContentType 'application/json; charset=utf-16' | Out-Null
    
            if($?) {
                $updated += "UPDATED: '$($m.UniqueId)' in $($watchlist.properties.displayName)"
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