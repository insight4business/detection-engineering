# Problem solved : Alerts must know which IPs are blocked.
# What it does    : Syncs IP Group addresses to a watchlist.
# Requires        : Az.Network, Sentinel Contributor
# Effect          : changes-state (review and test before use)
# Known issues    : Hard-coded org IP Group ID
# Origin          : adapted from field work; replace every ENTRE_AQUI_COM_SEU_* marker with your own value

###

$ErrorActionPreference = 'Stop'

$subscriptionId = "ENTRE_AQUI_COM_SEU_ID"
$workspaceResourceGroup = "Sentinel"
$workspaceName = "ENTRE_AQUI_COM_SEU_RECURSO"

$watchlistName = "Firewall_BlockedIPs"

$ipGroupResourceId = "/subscriptions/ENTRE_AQUI_COM_SEU_ID/resourceGroups/ENTRE_AQUI_COM_SEU_RECURSO/providers/Microsoft.Network/ipGroups/ENTRE_AQUI_COM_SEU_RECURSO"


## Main
$startTime = Get-Date

# Log in first with Connect-AzAccount if not using Cloud Shell
Connect-AzAccount -Identity -Subscription $subscriptionId -ErrorAction Stop

$azContext = Get-AzContext
$azProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
$profileClient = New-Object -TypeName Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient -ArgumentList ($azProfile)
$token = $profileClient.AcquireAccessToken($azContext.Subscription.TenantId)
$authHeader = @{
	'Content-Type'='application/json'
	'Authorization'='Bearer ' + $token.AccessToken
}


## First step: Get IP Group and watchlist items
# Get IP Group
$ipGroup = Get-AzIpGroup -ResourceId $ipGroupResourceId

# Get updated watchlist items
$watchlistItems = @()
$restUriWatchlistItems = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$workspaceResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/watchlists/$($watchlistName)/watchlistItems?api-version=2022-11-01-preview"
do {
    $watchlistItemsCurrent = Invoke-RestMethod -Uri $restUriWatchlistItems -Method Get -Headers $authHeader
    $watchlistItems += $watchlistItemsCurrent.value
    $restUriWatchlistItems = $watchlistItemsCurrent.nextLink
} while (
    $null -ne $watchlistItemsCurrent.nextLink
)

## Second step: Remove IPs older than 90 days from IP Group
# Get IPs older than 90 days using the watchlist information and remove them from the IP Group
foreach ($ip in $watchlistItems.properties.itemsKeyvalue) {
    $blockDateDatetime = [datetime]::ParseExact($ip.BlockDate, "yyyy/MM/dd HH:mm", $null)
    if ($blockDateDatetime -lt (Get-Date).AddDays(-90)) {
        Write-Output "IP Address $($ip.IP) is older than 90 days and will be removed from watchlist '$watchlistName'"
        $ipGroup.IpAddresses.Remove($ip.IP)
    }
}

# Update IP Group
Set-AzIpGroup -IpGroup $ipGroup
# # Get IP Group
# $ipGroup = Get-AzIpGroup -ResourceId $ipGroupResourceId

## Third step: Check if IPs from IP Group are in the watchlist
# Get IPs from IP Group and check if they are in the watchlist
$results = @()
foreach ($ipAddress in $ipGroup.IpAddresses) {
	$obj = [PSCustomObject]@{
		IP = $ipAddress
	}
	if ($ipAddress -in $watchlistItems.properties.itemsKeyvalue.ip) {
		# Write-Output "IP Address $ipAddress already exists in watchlist $watchlistName"
		$obj | Add-Member -MemberType NoteProperty -Name IsInWatchlist -Value $true
	} else {
		Write-Output "IP Address $ipAddress does not exist in watchlist $watchlistName"
		$obj | Add-Member -MemberType NoteProperty -Name IsInWatchlist -Value $false
	}
	$results += $obj
}


## Fourth step: Add new IPs to watchlist
# For all IPs that are not in the watchlist, add them
$count = 0
foreach ($ip in ($results | Where-Object {$_.IsInWatchlist -eq $false})) {
    $count += 1
	Write-Output "Adding '$($ip.IP)' to watchlist '$watchlistName'..."

	# Get last watchlist item and create new one with incremented etag (HEX code)
	$lastWatchlistGuid = $watchlistItems[-1].name

	# Convert first set of characters to decimal
	$newGuid = [convert]::toint32($lastWatchlistGuid.Replace('"','').split('-')[0], 16)
	# Subtracts the amount of added items times 256
	$newGuid = $newGuid - (256 * $count)
	# Reconvert to HEX
	$newGuid = ($('{0:X}' -f $newGuid) + "-" + $($lastWatchlistGuid.Replace('"','').split('-')[1..4] -join "-")).ToLower()

	# Add IP Address to watchlist	
	$restUriWatchlistItemsCreate = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$workspaceResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/watchlists/$($watchlistName)/watchlistItems/$($newGuid)?api-version=2022-11-01-preview"

	$watchlistItem = @{
		"properties" = @{
			"itemsKeyValue" = @{
				"IP" = $ip.IP
				"BlockDate" = (Get-Date).ToString("yyyy/MM/dd HH:mm")
			}
		}
	}
	Invoke-RestMethod -Uri $restUriWatchlistItemsCreate -Method Put -Headers $authHeader -Body ($watchlistItem | ConvertTo-Json -Depth 10)
}

## Fifth step: Remove deleted IPs from watchlist
# For all IPs that are in the watchlist but are not in the IP Group, remove them
foreach ($item in $watchlistItems) {
	if ($item.properties.itemsKeyvalue.IP -notin $ipGroup.IpAddresses) {
		Write-Output "Removing '$($item.properties.itemsKeyvalue.IP)' from watchlist '$watchlistName'..."

		# Remove IP Address from watchlist
		$restUriWatchlistItemsDelete = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$workspaceResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/watchlists/$($watchlistName)/watchlistItems/$($item.properties.watchlistItemId)?api-version=2022-11-01-preview"
		Invoke-RestMethod -Uri $restUriWatchlistItemsDelete -Method Delete -Headers $authHeader
	}
}

$elapsedTime = (Get-Date) - $startTime
Write-Output $elapsedTime

exit 0
