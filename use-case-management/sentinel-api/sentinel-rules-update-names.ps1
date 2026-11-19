# Problem solved : Rule naming convention.
# What it does    : Adds prefixes to rule display names.
# Requires        : Az.SecurityInsights; Sentinel Contributor
# Effect          : changes-state (review and test before use)
# Known issues    : Portuguese warning: update disables CreateIncident option; org naming prefix
# Origin          : adapted from field work; replace every ENTRE_AQUI_COM_SEU_* marker with your own value

###

## CUIDADO COM A OPÇÃO 'CREATEINCIDENT', UPDATE DESABILITA A OPÇÃO PARA AS REGRAS

# Connect-AzAccount

# Add a prefix to the rule name
$rules = Get-AzSentinelAlertRule -ResourceGroupName 'sentinel' -WorkspaceName 'ENTRE_AQUI_COM_SEU_RECURSO'
$rules = $rules | Where-Object { $_.Kind -ne "MicrosoftSecurityIncidentCreation" }
$rules = $rules | Where-Object { $_.DisplayName -notlike "*``[Homolog``]*" }
$rules = $rules | Where-Object { $_.DisplayName -notlike "*``[Test``]*" }
# $rules = $rules | Where-Object { $_.DisplayName -notlike "UC0*" }
$rules = $rules | Sort-Object DisplayName
$counter = 0
foreach ($rule in $rules) {
    $counter++
    $newDisplayName = "UC$('{0:d3}' -f $counter) - $($rule.DisplayName)"
    Write-Host "Old rule: $($rule.DisplayName)"
    Write-Host "New rule: $($newDisplayName)"
    $ruleId = ($rule.Id -split "/")[-1]

    # If rule is alert only or disabled, don't create incident
    if ($rule.Enabled -eq 'False' -and $rule.DisplayName -notlike "*(Alert only)*") {
        Write-Host "Disabling rule: $($rule.DisplayName)"
        # Update-AzSentinelAlertRule -ResourceGroupName 'sentinel' -WorkspaceName 'ENTRE_AQUI_COM_SEU_RECURSO' -Scheduled -RuleId $ruleId -DisplayName $newDisplayName
    } else {
        # Update-AzSentinelAlertRule -ResourceGroupName 'sentinel' -WorkspaceName 'ENTRE_AQUI_COM_SEU_RECURSO' -Scheduled -RuleId $ruleId -DisplayName $newDisplayName -CreateIncident
    }
}

# # Fix prefix
# $rules = Get-AzSentinelAlertRule -ResourceGroupName 'sentinel' -WorkspaceName 'ENTRE_AQUI_COM_SEU_RECURSO'
# $rules = $rules | Where-Object { $_.Kind -ne "MicrosoftSecurityIncidentCreation" }
# $rules = $rules | Where-Object { $_.DisplayName -notlike "*``[Homolog``]*" }
# $rules = $rules | Where-Object { $_.DisplayName -notlike "*``[Test``]*" }
# # $rules = $rules | Where-Object { $_.DisplayName -notlike "UC0*" }
# $rules = $rules | Sort-Object DisplayName
# foreach ($rule in $rules) {
#     $newDisplayName = $rule.DisplayName.Replace("UC0", "[UC0").Replace("UC1", "[UC1").Insert(6, "] ").Replace("]  - ", "] ")
#     Write-Host "Old rule: $($rule.DisplayName)"
#     Write-Host "New rule: $($newDisplayName)"
#     $ruleId = ($rule.Id -split "/")[-1]
    
    # # If rule is alert only or disabled, don't create incident
    # if ($rule.Enabled -eq 'False' -and $rule.DisplayName -notlike "*(Alert only)*") {
    #     Write-Host "Disabling rule: $($rule.DisplayName)"
    #     # Update-AzSentinelAlertRule -ResourceGroupName 'sentinel' -WorkspaceName 'ENTRE_AQUI_COM_SEU_RECURSO' -Scheduled -RuleId $ruleId -DisplayName $newDisplayName
    # } else {
    #     # Update-AzSentinelAlertRule -ResourceGroupName 'sentinel' -WorkspaceName 'ENTRE_AQUI_COM_SEU_RECURSO' -Scheduled -RuleId $ruleId -DisplayName $newDisplayName -CreateIncident
    # }
# }

# Change Homolog prefix
$rules = Get-AzSentinelAlertRule -ResourceGroupName 'sentinel' -WorkspaceName 'ENTRE_AQUI_COM_SEU_RECURSO'
$rules = $rules | Where-Object { $_.Kind -ne "MicrosoftSecurityIncidentCreation" }
foreach ($rule in $rules) {
    $newDisplayName = $rule.DisplayName.Replace("Homolog - ", "[Homolog] ")
    if ($newDisplayName -eq $rule.DisplayName) { continue }
    Write-Host "Old rule: $($rule.DisplayName)"
    Write-Host "New rule: $($newDisplayName)"
    $ruleId = ($rule.Id -split "/")[-1]
    
    # If rule is alert only or disabled, don't create incident
    if ($rule.Enabled -eq 'False' -and $rule.DisplayName -notlike "*(Alert only)*") {
        Write-Host "Disabling rule: $($rule.DisplayName)"
        # Update-AzSentinelAlertRule -ResourceGroupName 'sentinel' -WorkspaceName 'ENTRE_AQUI_COM_SEU_RECURSO' -Scheduled -RuleId $ruleId -DisplayName $newDisplayName
    } else {
        # Update-AzSentinelAlertRule -ResourceGroupName 'sentinel' -WorkspaceName 'ENTRE_AQUI_COM_SEU_RECURSO' -Scheduled -RuleId $ruleId -DisplayName $newDisplayName -CreateIncident
    }
}

# Change Test prefix
$rules = Get-AzSentinelAlertRule -ResourceGroupName 'sentinel' -WorkspaceName 'ENTRE_AQUI_COM_SEU_RECURSO'
$rules = $rules | Where-Object { $_.Kind -ne "MicrosoftSecurityIncidentCreation" }
foreach ($rule in $rules) {
    $newDisplayName = $rule.DisplayName.Replace("Test - ", "[Test] ")
    if ($newDisplayName -eq $rule.DisplayName) { continue }
    Write-Host "Old rule: $($rule.DisplayName)"
    Write-Host "New rule: $($newDisplayName)"
    $ruleId = ($rule.Id -split "/")[-1]
    
    # If rule is alert only or disabled, don't create incident
    if ($rule.Enabled -eq 'False' -and $rule.DisplayName -notlike "*(Alert only)*") {
        Write-Host "Disabling rule: $($rule.DisplayName)"
        # Update-AzSentinelAlertRule -ResourceGroupName 'sentinel' -WorkspaceName 'ENTRE_AQUI_COM_SEU_RECURSO' -Scheduled -RuleId $ruleId -DisplayName $newDisplayName
    } else {
        # Update-AzSentinelAlertRule -ResourceGroupName 'sentinel' -WorkspaceName 'ENTRE_AQUI_COM_SEU_RECURSO' -Scheduled -RuleId $ruleId -DisplayName $newDisplayName -CreateIncident
    }
}