# Problem solved : Exported bulk ARM template is hard to manage per rule.
# What it does    : Splits exported JSON into one file per rule with actions.
# Requires        : none
# Effect          : read-only
# Origin          : adapted from field work; replace every ENTRE_AQUI_COM_SEU_* marker with your own value

###

$ErrorActionPreference = "Stop"

# Files in folder:
$files = Get-ChildItem -File

foreach ($file in ($files | Where-Object {$_.Name -like "Azure_Sentinel_analytics_rules*"})) {
    $content = Get-Content $file.FullName

    $content = $content | ConvertFrom-Json

    # Separate rules and rule actions
    $actions = $content.resources | Where-Object {$_.type -eq "Microsoft.OperationalInsights/workspaces/providers/alertRules/actions"}
    $rules = $content.resources | Where-Object {$_.type -eq "Microsoft.OperationalInsights/workspaces/providers/alertRules"}
    
    foreach ($r in $rules) { 
        # Search for associated actions
        $a = $null
        $a = $actions | Where-Object {$_.properties.ruleId -eq $r.id}

        # Build JSON
        $fullcontent = $content | ConvertTo-Json -Depth 10

        $fullcontent = $fullcontent | ConvertFrom-Json
    
        $fullcontent.resources = if ($a) { [array]@($r, $a) } else { [array]@($r) }
        
        # Output to file
        $fileName = ($($r.properties.displayName)).Replace("[", "(").Replace("]", ")")
        # $fileName = ($($r.properties.displayName)).Replace("[", "").Replace("]", "")

        foreach ($resource in $fullcontent.resources) {
            if ($resource.properties.query) {
                $resource.properties.query = $resource.properties.query.Replace("`"", "\`"")
            }
        }

        # Replace new lines
        $fullcontent = ($fullcontent | ConvertTo-Json -Depth 10 -Compress | % { [System.Text.RegularExpressions.Regex]::Unescape($_) }).Replace("`r`n", "\r\n").Replace("}}}", "}}]}").Replace("`"resources`":{", "`"resources`":[{")

        if (!$a) {
            $fullcontent | Out-file ".\Rules\$fileName.json"
        } else {
            Write-Output "SKIPPED: $fileName"
        }
    }
}

