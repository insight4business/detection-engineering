# Problem solved : Rule inventory/catalog.
# What it does    : Exports analytics rules metadata.
# Requires        : Az.Accounts
# Effect          : read-only
# Origin          : adapted from field work; replace every ENTRE_AQUI_COM_SEU_* marker with your own value

###


$subscriptionId = "ENTRE_AQUI_COM_SEU_ID"


##
# Log in first with Connect-AzAccount if not using Cloud Shell
Connect-AzAccount -SubscriptionId $subscriptionId

$azContext = Get-AzContext
$azProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
$profileClient = New-Object -TypeName Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient -ArgumentList ($azProfile)
$token = $profileClient.AcquireAccessToken($azContext.Subscription.TenantId)
$authHeader = @{
    'Content-Type'='application/json'
    'Authorization'='Bearer ' + $token.AccessToken
}


##
# Invoke the REST API
$restUri = "https://management.azure.com/subscriptions/ENTRE_AQUI_COM_SEU_ID/resourceGroups/Sentinel/providers/Microsoft.OperationalInsights/workspaces/ENTRE_AQUI_COM_SEU_RECURSO/providers/Microsoft.SecurityInsights/alertRules?api-version=2021-10-01"
$response = Invoke-RestMethod -Uri $restUri -Method Get -Headers $authHeader

#
$outputReport = [System.Collections.Generic.List[Object]]::new()
foreach ($uc in $response.value) {
    $outputReport.Add([PSCustomObject]@{
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

#
$outputReport | export-excel