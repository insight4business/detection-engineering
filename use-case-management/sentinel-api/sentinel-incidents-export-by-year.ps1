# Problem solved : Annual incident report.
# What it does    : Lists incidents of year through REST.
# Requires        : Az.Accounts; Sentinel Reader
# Effect          : read-only
# Known issues    : Hard-coded year 2023
# Origin          : adapted from field work; replace every ENTRE_AQUI_COM_SEU_* marker with your own value

###

$year = 2023
$maxResults = 10000

$outputPath = "C:\Temp"

if (!(Test-Path $outputPath)) {
    New-Item -Path ($outputPath) -ItemType Directory
}

## Main
Connect-AzAccount
	
$azContext = Get-AzContext
$azProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
$profileClient = New-Object -TypeName Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient -ArgumentList ($azProfile)
$token = $profileClient.AcquireAccessToken($azContext.Subscription.TenantId)
$authHeader = @{
    'Content-Type'='application/json'
    'Authorization'='Bearer ' + $token.AccessToken
}

# Invoke the REST API
$outputReport = [System.Collections.Generic.List[Object]]::new() # Create output file

$count = 0
while ($count -lt ([math]::ceiling($maxResults / 1000))) {
    Write-Output "$([int]$($count.ToString() + "000")) - $([int]$($count.ToString() + "000") + 1000)"

    if ($count -eq 0) {
        # First page
        $restUri = "https://management.azure.com/subscriptions/ENTRE_AQUI_COM_SEU_ID/resourceGroups/sentinel/providers/Microsoft.OperationalInsights/workspaces/ENTRE_AQUI_COM_SEU_RECURSO/providers/Microsoft.SecurityInsights/incidents?api-version=2022-07-01-preview&`$top=1000"

        $response = Invoke-RestMethod -Uri $restUri -Method Get -Headers $authHeader
    } else {
        # Next pages
        $restUri = $response.nextLink

        $response = Invoke-RestMethod -Uri $restUri -Method Get -Headers $authHeader
    }

    $yearIncidents = $null
    $yearIncidents = $response.value | Where-Object {[datetime]$($_.properties.createdTimeUtc) -gt [datetime]$("01/01/$year 00:00:00") -and [datetime]$($_.properties.createdTimeUtc) -lt [datetime]$("01/01/$($year+1) 00:00:00")}

    foreach ($i in $yearIncidents) {
        $obj = $null
        $obj = [PSCustomObject]@{
            CreatedDateTime = $i.properties.createdTimeUtc
            IncidentNumber = $i.properties.incidentNumber
            IncidentDisplayName = $i.properties.title
            Severity = $i.properties.severity
            Status = $i.properties.status
            Classification = $i.properties.classification
            ClassificationReason = $i.properties.classificationReason
            AssignedTo = $i.properties.owner.userPrincipalName
            Tags = ($i.properties.labels.labelName) -join ", "
            Provider = $i.properties.providerName
            AlertCount = $i.properties.additionalData.alertsCount
            Tactics = ($i.properties.additionalData.tactics) -join ", "
            Techniques = ($i.properties.additionalData.techniques) -join ", "
        } 
        $outputReport.Add($obj)
    }
    $count++
}

$outputReport | Export-Excel "$outputPath\$year - All Sentinel Incidents.xlsx"
