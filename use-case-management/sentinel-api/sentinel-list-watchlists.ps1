# Problem solved : Watchlist inventory.
# What it does    : Exports watchlists to CSV.
# Requires        : Az.Accounts
# Effect          : read-only
# Origin          : adapted from field work; replace every ENTRE_AQUI_COM_SEU_* marker with your own value

###

$subscriptionId = "ENTRE_AQUI_COM_SEU_ID"
$workspaceResourceGroup = "Sentinel"
$workspaceId = "ENTRE_AQUI_COM_SEU_ID"
$currentDay = Get-Date -Format "yyyy-MM-dd"
$outputPath = "C:\Temp\$currentDay - Watchlists.csv"


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
$restUri = "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$workspaceResourceGroup/providers/Microsoft.OperationalInsights/workspaces/$workspaceName/providers/Microsoft.SecurityInsights/watchlists?api-version=2021-10-01"
$response = Invoke-RestMethod -Uri $restUri -Method Get -Headers $authHeader

$outputFile = [System.Collections.Generic.List[Object]]::new() # Create output file
foreach ($watchlist in $response.value) {
    $info = [PSCustomObject]@{
        ID = $watchlist.properties.watchlistId
        Name = $watchlist.properties.displayName
        Alias = $watchlist.name
        SearchKey = $watchlist.properties.itemsSearchKey
        CreatedAt = $watchlist.systemData.createdAt
        LastModified = $watchlist.systemData.lastModifiedAt 
        IsDeleted = $watchlist.properties.isDeleted
    }
    $outputFile.Add($info)
}

# $outputFile | Export-Csv $outputPath -NoTypeInformation
$outputFile | Export-Excel $outputPath.Replace(".csv", ".xlsx")
$outputFile | ConvertTo-Json -Depth 5 | Out-File -FilePath $outputPath.Replace(".csv", ".json") -Encoding UTF8
