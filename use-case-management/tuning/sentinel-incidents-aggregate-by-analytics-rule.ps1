# Problem solved : I need data to tune a noisy rule.
# What it does    : Queries incidents for a rule and aggregates events to Excel.
# Requires        : Az.OperationalInsights, ImportExcel
# Effect          : read-only
# Known issues    : Hard-coded rule name
# Origin          : adapted from field work; replace every ENTRE_AQUI_COM_SEU_* marker with your own value

###


$subscriptionId ="ENTRE_AQUI_COM_SEU_ID"
$resourceGroupName = "sentinel"
$workspaceName = "ENTRE_AQUI_COM_SEU_RECURSO"
$workspaceId = "ENTRE_AQUI_COM_SEU_ID"
$timeLimit = 60 # Days

$ruleToSearch = "Suspicious granting of permissions to an account"

$currentDate = Get-Date -Format 'yyyy-MM-dd'
$outputPath = "c:\Temp\$currentDate - Incident results - $ruleToSearch.xlsx"


## Main
# Log in first with Connect-AzAccount if not using Cloud Shell
Connect-AzAccount -Subscription $subscriptionId
	
$azContext = Get-AzContext
$azProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
$profileClient = New-Object -TypeName Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient -ArgumentList ($azProfile)
$token = $profileClient.AcquireAccessToken($azContext.Subscription.TenantId)
$authHeader = @{
    'Content-Type'='application/json'
    'Authorization'='Bearer ' + $token.AccessToken
}

# Get Sentinel rules
$restUri = "https://management.azure.com/subscriptions/ENTRE_AQUI_COM_SEU_ID/resourceGroups/Sentinel/providers/Microsoft.OperationalInsights/workspaces/ENTRE_AQUI_COM_SEU_RECURSO/providers/Microsoft.SecurityInsights/alertRules?api-version=2021-10-01"
$rules = (Invoke-RestMethod -Uri $restUri -Method Get -Headers $authHeader).value

$rule = $rules | Where-Object {$_.properties.displayName -eq $ruleToSearch}

# Invoke the Incidents REST API
$maxResults = 5000
$restUriIncidents = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/incidents?api-version=2022-07-01-preview&`$top=$maxResults"

$response = Invoke-RestMethod -Uri $restUriIncidents -Method Get -Headers $authHeader

# Get the incidents from the last 60 days
$incidents = $response.value | Where-Object {$_.properties.createdTimeUtc -gt (Get-Date).AddDays(-$timeLimit)}
$incidents = $incidents | Where-Object {$_.properties.title -eq $ruleToSearch}


$outputReport = [System.Collections.Generic.List[Object]]::new() # Create output file

# 
foreach ($incident in $incidents) {
    # Define query now time
    $queryNow = ([datetime]$incident.properties.createdTimeUtc).AddSeconds(1).ToString("yyyy-MM-ddTHH:mm:ss.0000000Z")

    # Get the incident alerts
    $restUriAlerts = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroupName/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/incidents/$($incident.name)/alerts?api-version=2022-11-01-preview"

    $response = Invoke-RestMethod -Uri $restUriAlerts -Method Post -Headers $authHeader

    # Define query
    $query = "set query_now = datetime($queryNow);`n$($rule.properties.query)"

    # $querySplit = ($rule.properties.query).Split("| summarize")
    # $queryFixed = $querySplit[0] + "| summarize " + $querySplit[1] + "// JOIN" + $querySplit[2].Split("// JOIN")[1]

    $query = "set query_now = datetime($queryNow);`n$queryFixed"

    # Run query
    $results = Invoke-AzOperationalInsightsQuery -WorkspaceId $workspaceId -Query $query -ErrorAction Stop | Select-Object -ExpandProperty Results

    $outputReport.Add($results)
}

$outputReport | Export-Excel -Path $outputPath