# Problem solved : Impact analysis before changing a watchlist.
# What it does    : Searches rule queries for watchlist usage.
# Requires        : Az.Accounts
# Effect          : read-only
# Origin          : adapted from field work; replace every ENTRE_AQUI_COM_SEU_* marker with your own value


$subscriptionId = "ENTRE_AQUI_COM_SEU_ID"


## Main
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

# Invoke the REST API
$restUri = "https://management.azure.com/subscriptions/ENTRE_AQUI_COM_SEU_ID/resourceGroups/Sentinel/providers/Microsoft.OperationalInsights/workspaces/ENTRE_AQUI_COM_SEU_RECURSO/providers/Microsoft.SecurityInsights/alertRules?api-version=2021-10-01"
$response = Invoke-RestMethod -Uri $restUri -Method Get -Headers $authHeader

$queriesUsingWatchlists = $response.value | Where-Object {$_.properties.query -like "*_GetWatchlist(*Acc-*"}

$queriesUsingWatchlists.properties.displayName