# Problem solved : I need the rule inventory searchable in KQL.
# What it does    : Exports analytic rule metadata into a watchlist.
# Requires        : Az.Accounts; Sentinel Contributor
# Effect          : changes-state (review and test before use)
# Known issues    : Workspace placeholders
# Origin          : adapted from field work; replace every ENTRE_AQUI_COM_SEU_* marker with your own value

###
# 

$ErrorActionPreference = "Stop"

$subscriptionId = "ENTRE_AQUI_COM_SEU_ID"
$workspaceResourceGroup = "Sentinel"
$workspaceName = "ENTRE_AQUI_COM_SEU_RECURSO"

$watchlistToUpdate = "Sentinel-UseCases"


## MAIN
# Log in first with Connect-AzAccount if not using Cloud Shell
Connect-AzAccount -Identity -Subscription $subscriptionId -ErrorAction Stop
# Connect-AzAccount -SubscriptionId $subscriptionId

$azContext = Get-AzContext
$azProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
$profileClient = New-Object -TypeName Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient -ArgumentList ($azProfile)
$token = $profileClient.AcquireAccessToken($azContext.Subscription.TenantId)
$authHeader = @{
    'Content-Type'='application/json'
    'Authorization'='Bearer ' + $token.AccessToken
}


## QUERY
# Invoke the REST API
$restUri = "https://management.azure.com/subscriptions/ENTRE_AQUI_COM_SEU_ID/resourceGroups/Sentinel/providers/Microsoft.OperationalInsights/workspaces/ENTRE_AQUI_COM_SEU_RECURSO/providers/Microsoft.SecurityInsights/alertRules?api-version=2021-10-01"
$response = Invoke-RestMethod -Uri $restUri -Method Get -Headers $authHeader

# Get updated use case list
$useCaseList = [System.Collections.Generic.List[Object]]::new()
foreach ($uc in $response.value) {
    $useCaseList.Add([PSCustomObject]@{
        ObjectId = $uc.name
        ResourceId = $uc.id
        Kind = $uc.kind
        DisplayName = $uc.properties.displayName
        Enabled = $uc.properties.enabled
        Description = $uc.properties.description
        Severity = $uc.properties.severity
        Tactics = $uc.properties.tactics -join ';'
        QueryFrequency = $uc.properties.queryFrequency
        QueryPeriod = $uc.properties.queryPeriod
        TriggerOperator = $uc.properties.triggerOperator
        TriggerThreshold = $uc.properties.triggerThreshold
        LastModified = ([datetime]$uc.properties.lastModifiedUtc).ToString("yyyy-MM-dd HH:mm:ss")
        CreateIncident = $uc.properties.incidentConfiguration.createIncident
        IncidentGroupingEnabled = $uc.properties.incidentConfiguration.groupingConfiguration.enabled
        IncidentGroupingLookbackDuration = $uc.properties.incidentConfiguration.groupingConfiguration.lookbackDuration
        IncidentGroupingMatchingMethod = $uc.properties.incidentConfiguration.groupingConfiguration.matchingMethod
        EventAggregationKind = $uc.properties.eventGroupingSettings.aggregationKind
    })
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

# Remove watchlist items which are not in the current group list
foreach ($item in $watchlistItems) {
    if ($item.properties.itemsKeyValue.ObjectId -notin $useCaseList.ObjectId) {
        # Remove watchlist item
        Write-Host "Removing '$($item.properties.itemsKeyValue.ObjectId)' ($($item.properties.itemsKeyValue.ObjectId)) from '$($watchlist.properties.displayName)'..."

        $restUriWatchlistItemDelete = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$workspaceResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/watchlists/$($watchlist.Name)/watchlistItems/$($item.properties.watchlistItemId)?api-version=2022-07-01-preview"
        Invoke-RestMethod -Uri $restUriWatchlistItemDelete -Method Delete -Headers $authHeader | Out-Null

        if($?) {
            $removed += "REMOVED: '$($item.properties.itemsKeyValue.ObjectId)' ($($item.properties.itemsKeyValue.ObjectId)) from $($watchlist.properties.displayName)"
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
foreach ($uc in $useCaseList) {
    Write-Progress -Id 1 -Activity "Updating watchlist '$($watchlist.properties.displayName)'" -Status "[($($useCaseList.IndexOf($uc)) / $($useCaseList.Count))] Checking role '$($uc.ObjectId)' to '$($watchlist.properties.displayName)'..." -PercentComplete (($useCaseList.IndexOf($uc) / $useCaseList.Count) * 100)

    if ($uc.ObjectId -notin ($watchlistItems.properties.itemsKeyValue.ObjectId)) {
        # Add watchlist item
        $count += 1

        Write-Host "Adding '$($uc.ObjectId)' ($($uc.DisplayName)) to '$($watchlist.properties.displayName)'..."

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
                    "ObjectId" = $uc.ObjectId
                    "ResourceId" = $uc.ResourceId
                    "Kind" = $uc.Kind
                    "DisplayName" = $uc.DisplayName
                    "Enabled" = $uc.Enabled
                    "Description" = $uc.Description
                    "Severity" = $uc.Severity
                    "Tactics" = $uc.Tactics
                    "QueryFrequency" = $uc.QueryFrequency
                    "QueryPeriod" = $uc.QueryPeriod
                    "TriggerOperator" = $uc.TriggerOperator
                    "TriggerThreshold" = $uc.TriggerThreshold
                    "LastModified" = $uc.LastModified
                    "CreateIncident" = $uc.CreateIncident
                    "IncidentGroupingEnabled" = $uc.IncidentGroupingEnabled
                    "IncidentGroupingLookbackDuration" = $uc.IncidentGroupingLookbackDuration
                    "IncidentGroupingMatchingMethod" = $uc.IncidentGroupingMatchingMethod
                    "EventAggregationKind" = $uc.EventAggregationKind
                }
            }
        }
        $body = $body | ConvertTo-Json -Depth 10

        $restUriWatchlistItemCreate = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$workspaceResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/watchlists/$($watchlist.Name)/watchlistItems/$($etag)?api-version=2022-07-01-preview"
        Invoke-RestMethod -Uri $restUriWatchlistItemCreate -Method Put -Headers $authHeader -Body $body -ContentType 'application/json; charset=utf-16' | Out-Null

        if($?) {
            $added += "ADDED: '$($uc.ObjectId)' ($($uc.DisplayName)) to '$($watchlist.properties.displayName)'"
        }
    } else {
        # Update values in watchlist
        $watchlistItem = ($watchlistItems | Where-Object {$_.properties.itemsKeyValue.ObjectId -eq $uc.ObjectId})

        if ($watchlistItem.properties.itemsKeyValue.ResourceId -ne $uc.ResourceId `
        -or $watchlistItem.properties.itemsKeyValue.Kind -ne $uc.Kind `
        -or $watchlistItem.properties.itemsKeyValue.DisplayName -ne $uc.DisplayName `
        -or $watchlistItem.properties.itemsKeyValue.Enabled -ne $uc.Enabled `
        -or $watchlistItem.properties.itemsKeyValue.Description -ne $uc.Description `
        -or $watchlistItem.properties.itemsKeyValue.Severity -ne $uc.Severity `
        -or $watchlistItem.properties.itemsKeyValue.Tactics -ne $uc.Tactics `
        -or $watchlistItem.properties.itemsKeyValue.QueryFrequency -ne $uc.QueryFrequency `
        -or $watchlistItem.properties.itemsKeyValue.QueryPeriod -ne $uc.QueryPeriod `
        -or $watchlistItem.properties.itemsKeyValue.TriggerOperator -ne $uc.TriggerOperator `
        -or $watchlistItem.properties.itemsKeyValue.TriggerThreshold -ne $uc.TriggerThreshold `
        -or $watchlistItem.properties.itemsKeyValue.LastModified -ne $uc.LastModified `
        -or $watchlistItem.properties.itemsKeyValue.CreateIncident -ne $uc.CreateIncident `
        -or $watchlistItem.properties.itemsKeyValue.IncidentGroupingEnabled -ne $uc.IncidentGroupingEnabled `
        -or $watchlistItem.properties.itemsKeyValue.IncidentGroupingLookbackDuration -ne $uc.IncidentGroupingLookbackDuration `
        -or $watchlistItem.properties.itemsKeyValue.IncidentGroupingMatchingMethod -ne $uc.IncidentGroupingMatchingMethod `
        -or $watchlistItem.properties.itemsKeyValue.EventAggregationKind -ne $uc.EventAggregationKind
        ) {
            $body = @{
                "properties" = @{
                    "etag" = $etag
                    "itemsKeyValue" = @{
                        "ObjectId" = $uc.ObjectId
                        "ResourceId" = $uc.ResourceId
                        "Kind" = $uc.Kind
                        "DisplayName" = $uc.DisplayName
                        "Enabled" = $uc.Enabled
                        "Description" = $uc.Description
                        "Severity" = $uc.Severity
                        "Tactics" = $uc.Tactics
                        "QueryFrequency" = $uc.QueryFrequency
                        "QueryPeriod" = $uc.QueryPeriod
                        "TriggerOperator" = $uc.TriggerOperator
                        "TriggerThreshold" = $uc.TriggerThreshold
                        "LastModified" = $uc.LastModified
                        "CreateIncident" = $uc.CreateIncident
                        "IncidentGroupingEnabled" = $uc.IncidentGroupingEnabled
                        "IncidentGroupingLookbackDuration" = $uc.IncidentGroupingLookbackDuration
                        "IncidentGroupingMatchingMethod" = $uc.IncidentGroupingMatchingMethod
                        "EventAggregationKind" = $uc.EventAggregationKind
                    }
                }
            }
    
            $body = $body | ConvertTo-Json -Depth 10
    
            $restUriWatchlistItemUpdate = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$workspaceResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/watchlists/$($watchlist.Name)/watchlistItems/$($watchlistItem.properties.watchlistItemId)?api-version=2022-07-01-preview"
            Invoke-RestMethod -Uri $restUriWatchlistItemUpdate -Method Put -Headers $authHeader -Body $body -ContentType 'application/json; charset=utf-16' | Out-Null
    
            if($?) {
                $updated += "UPDATED: '$($watchlistItem.properties.itemsKeyValue.ObjectId)' ($($watchlistItem.properties.itemsKeyValue.DisplayName)) in $($watchlist.properties.displayName)"
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
    Write-Output $updated

    Write-Output "Total added: $($added.Count)"
    Write-Output "Total removed: $($removed.Count)"
    Write-Output "Total updated: $($updated.Count)"
}

exit 0