# Problem solved : Rule inventory.
# What it does    : Lists rules via REST.
# Requires        : Az.Accounts
# Effect          : read-only
# Known issues    : Hard-coded subscription placeholder in URI
# Origin          : adapted from field work; replace every ENTRE_AQUI_COM_SEU_* marker with your own value

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
$restUri = "https://management.azure.com/subscriptions/ENTRE_AQUI_COM_SEU_ID/resourceGroups/Sentinel/providers/Microsoft.OperationalInsights/workspaces/ENTRE_AQUI_COM_SEU_RECURSO/providers/Microsoft.SecurityInsights/alertRules?api-version=2021-10-01"
$response = Invoke-RestMethod -Uri $restUri -Method Get -Headers $authHeader

$response.value | Select-Object Name, Properties
