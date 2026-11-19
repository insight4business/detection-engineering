# Problem solved : Detect abuse of app identities.
# What it does    : Refreshes watchlist of service principals.
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

$watchlistToUpdate = "AzureAD-ServicePrincipals"

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

# Connect MS Graph and Azure AD
$context = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile.DefaultContext
$graphToken = ([Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate($context.Account, $context.Environment, $context.Tenant.Id.ToString(), $null, [Microsoft.Azure.Commands.Common.Authentication.ShowDialog]::Never, $null, "https://graph.microsoft.com").AccessToken) | ConvertTo-SecureString -AsPlainText -Force
# $aadToken = ([Microsoft.Azure.Commands.Common.Authentication.AzureSession]::Instance.AuthenticationFactory.Authenticate($context.Account, $context.Environment, $context.Tenant.Id.ToString(), $null, [Microsoft.Azure.Commands.Common.Authentication.ShowDialog]::Never, $null, "https://graph.windows.net").AccessToken) | ConvertTo-SecureString -AsPlainText -Force

Connect-MgGraph -AccessToken $graphToken -ErrorAction Stop
# Write-Output (Get-MgContext)

## QUERY
$propertiesToReturn = @(
    "Id", 
    "AccountEnabled",
    "AdditionalProperties",
    "AppDisplayName",
    "AppDescription",
    "AppOwnerOrganizationId",
    "AppId",
    "Description",
    "DisplayName",
    "PreferredSingleSignOnMode",
    "SignInAudience"
)

$servicePrincipals = Get-MgServicePrincipal -All -Property $propertiesToReturn
$servicePrincipals = $servicePrincipals | Sort-Object DisplayName

Write-Host "Total service principals: $($servicePrincipals.Count)"

# Treat fields
foreach ($sp in $servicePrincipals) {
    $owners = $null
    $owners = [array](Get-MgServicePrincipalOwner -ServicePrincipalId $sp.Id -All)

    if ($owners) {
        $ownerList = @()
        foreach ($o in $owners) {
            $ownerList += $o.Id
        }
        $sp | Add-Member -MemberType NoteProperty -Name "Owners" -Value ($ownerList -join ',') -Force
    
        if ($null -ne $sp.AdditionalProperties['createdDateTime']) {
            $sp | Add-Member -MemberType NoteProperty -Name "CreatedDateTime" -Value $sp.AdditionalProperties['createdDateTime'] -Force
        } else {
            $sp | Add-Member -MemberType NoteProperty -Name "CreatedDateTime" -Value '' -Force
        }
    }    
}

$propertiesToReturn += ("CreatedDateTime", "Owners")
$propertiesToReturn = $propertiesToReturn | Where-Object {$_ -notin ("AdditionalProperties")}


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
    if (($servicePrincipals.AppId) -notcontains ($item.properties.itemsKeyValue.AppId)) {
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
foreach ($sp in $servicePrincipals) {
    if (($watchlistItems.properties.itemsKeyValue.AppId) -notcontains ($sp.AppId)) {
        # Add watchlist item
        $count += 1

        Write-Host "Adding '$($sp.Id)' ($($sp.DisplayName)) to '$($watchlist.properties.displayName)'..."

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
                    "Id" = $sp.Id
                    "AccountEnabled" = $sp.AccountEnabled
                    "AppDisplayName" = $sp.AppDisplayName
                    "AppDescription" = $sp.AppDescription
                    "AppOwnerOrganizationId" = $sp.AppOwnerOrganizationId
                    "AppId" = $sp.AppId
                    "Description" = $sp.Description
                    "DisplayName" = $sp.DisplayName
                    "PreferredSingleSignOnMode" = $sp.PreferredSingleSignOnMode
                    "SignInAudience" = $sp.SignInAudience
                    "CreatedDateTime" = $sp.CreatedDateTime
                    "Owners" = ($sp.Owners -join ';').ToString()
                }
            }
        }
        $body = $body | ConvertTo-Json -Depth 10

        $restUriWatchlistItemCreate = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$workspaceResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/watchlists/$($watchlist.Name)/watchlistItems/$($etag)?api-version=2022-07-01-preview"
        Invoke-RestMethod -Uri $restUriWatchlistItemCreate -Method Put -Headers $authHeader -Body $body -ContentType 'application/json; charset=utf-16' | Out-Null

        if($?) {
            $added += "ADDED: '$($sp.Id)' ($($sp.DisplayName)) to '$($watchlist.properties.displayName)'"
        }

    } else {
        # Update values in watchlist
        $watchlistItem = ($watchlistItems | Where-Object {$_.properties.itemsKeyValue.AppId -eq $sp.AppId})

        if ($watchlistItem.properties.itemsKeyValue.Id -ne $sp.Id `
            -or $watchlistItem.properties.itemsKeyValue.AccountEnabled -ne $sp.AccountEnabled `
            -or $watchlistItem.properties.itemsKeyValue.AppDisplayName -ne $sp.AppDisplayName `
            -or $watchlistItem.properties.itemsKeyValue.AppDescription -ne $sp.AppDescription `
            -or $watchlistItem.properties.itemsKeyValue.AppOwnerOrganizationId -ne $sp.AppOwnerOrganizationId `
            -or $watchlistItem.properties.itemsKeyValue.Description -ne $sp.Description `
            -or $watchlistItem.properties.itemsKeyValue.DisplayName -ne $sp.DisplayName `
            -or $watchlistItem.properties.itemsKeyValue.PreferredSingleSignOnMode -ne $sp.PreferredSingleSignOnMode `
            -or $watchlistItem.properties.itemsKeyValue.SignInAudience -ne $sp.SignInAudience `
            -or $watchlistItem.properties.itemsKeyValue.CreatedDateTime -ne $sp.CreatedDateTime `
            -or $watchlistItem.properties.itemsKeyValue.Owners -ne $sp.Owners
        ) {
            $body = @{
                "properties" = @{
                    "etag" = $etag
                    "itemsKeyValue" = @{
                        "Id" = $sp.Id
                        "AccountEnabled" = $sp.AccountEnabled
                        "AppDisplayName" = $sp.AppDisplayName
                        "AppDescription" = $sp.AppDescription
                        "AppOwnerOrganizationId" = $sp.AppOwnerOrganizationId
                        "AppId" = $sp.AppId
                        "Description" = $sp.Description
                        "DisplayName" = $sp.DisplayName
                        "PreferredSingleSignOnMode" = $sp.PreferredSingleSignOnMode
                        "SignInAudience" = $sp.SignInAudience
                        "CreatedDateTime" = $sp.CreatedDateTime
                        "Owners" = ($sp.Owners -join ';').ToString()
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