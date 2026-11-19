# Problem solved : Remove obsolete rule.
# What it does    : Deletes a rule by ID via REST.
# Requires        : Az.Accounts; Sentinel Contributor
# Effect          : destructive (review and test before use)
# Known issues    : ruleId empty by default
# Origin          : adapted from field work; replace every ENTRE_AQUI_COM_SEU_* marker with your own value

###


$subscriptionId = "ENTRE_AQUI_COM_SEU_ID"

$resourceGroup = "Sentinel"

$workspaceName = "ENTRE_AQUI_COM_SEU_RECURSO"

$ruleId = ""

##
Connect-AzAccount -SubscriptionId $subscriptionId
	
$azContext = Get-AzContext
$azProfile = [Microsoft.Azure.Commands.Common.Authentication.Abstractions.AzureRmProfileProvider]::Instance.Profile
$profileClient = New-Object -TypeName Microsoft.Azure.Commands.ResourceManager.Common.RMProfileClient -ArgumentList ($azProfile)
$token = $profileClient.AcquireAccessToken($azContext.Subscription.TenantId)
$authHeader = @{
    'Content-Type'='application/json'
    'Authorization'='Bearer ' + $token.AccessToken
}

$restUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$resourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/alertRules/$($ruleId)?api-version=2023-11-01"


$response = Invoke-RestMethod -Uri $restUri -Headers $authHeader -Method DELETE