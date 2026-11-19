# Problem solved : What automation rules exist?
# What it does    : Exports automation rules via REST.
# Requires        : Az.Accounts; Sentinel Reader
# Effect          : read-only
# Known issues    : Legacy token acquisition
# Origin          : adapted from field work; replace every ENTRE_AQUI_COM_SEU_* marker with your own value

# 
$currentDay = Get-Date -Format "yyyy-MM-dd"
$outputPath = "C:\Temp\$currentDay - AutomationRules.csv"

## Main
# Log in first with Connect-AzAccount if not using Cloud Shell
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
$restUri = "https://management.azure.com/subscriptions/ENTRE_AQUI_COM_SEU_ID/resourceGroups/Sentinel/providers/Microsoft.OperationalInsights/workspaces/ENTRE_AQUI_COM_SEU_RECURSO/providers/Microsoft.SecurityInsights/automationRules?api-version=2021-10-01"
$response = Invoke-RestMethod -Uri $restUri -Method Get -Headers $authHeader

$outputFile = [System.Collections.Generic.List[Object]]::new() # Create output file
foreach ($rule in $response.value) {
    $conditions = @()
    foreach ($condition in $rule.properties.triggeringLogic.conditions) {
        if ($condition.conditionProperties.propertyName -eq "IncidentRelatedAnalyticRuleIds") {
            $condition.conditionProperties.propertyValues = ($condition.conditionProperties.propertyValues).Split("/")[-1]
        }
        $filters = $null
        $filters = "'$($condition.conditionProperties.propertyName)' -$($condition.conditionProperties.operator) [$($condition.conditionProperties.propertyValues -join ";")]"
        # $filters = [PSCustomObject]@{
        #     field = $condition.conditionProperties.propertyName
        #     operator = $condition.conditionProperties.operator
        #     values = $condition.conditionProperties.propertyValues
        # }
        $conditions += $filters
    }

    $actions = @()
    foreach ($action in $rule.properties.actions) {
        if ($action.actionType -eq "RunPlaybook") {
            $action.actionConfiguration = $($action.actionConfiguration.logicAppResourceId).Split("/")[-1] + " (tenantId=$($action.actionConfiguration.tenantId))"
        } elseif ($action.actionType -eq "ModifyProperties") {
            if ($action.actionConfiguration.labels -ne $null) {
                $action.actionConfiguration.labels = ($action.actionConfiguration.labels.labelName).ToString()
            }
        }
        $actions += "$($action.actionType) - $($action.actionConfiguration -join ';')"
    }

    $ruleInfo = [PSCustomObject]@{
        ID = $rule.name
        Name = $rule.properties.displayName
        Priority = $rule.properties.order
        CreatedAt = $rule.properties.createdTimeUtc
        LastModified = $rule.properties.lastModifiedTimeUtc 
        Conditions = $conditions -join "\n"
        Actions = $actions -join "\n"
    }
    $outputFile.Add($ruleInfo)
}

# $outputFile | Export-Csv $outputPath -NoTypeInformation
$outputFile | Export-Excel $outputPath.Replace(".csv", ".xlsx")
$outputFile | ConvertTo-Json -Depth 5 | Out-File -FilePath $outputPath.Replace(".csv", ".json") -Encoding UTF8
