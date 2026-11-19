# Sentinel Api

Scripts for the **sentinel-api** technology in this sub-process.

## Scripts adapted from field work

Each script solves one problem. They were adapted from real operations work: replace every `ENTRE_AQUI_COM_SEU_*` marker, review, and test in a non-production tenant first.

| Script | Problem it solves | What it does | Requires | Effect | Notes |
|---|---|---|---|---|---|
| `sentinel-export-use-case-information.ps1` | Rule inventory/catalog. | Exports analytics rules metadata. | Az.Accounts | read-only |  |
| `sentinel-incidents-export-by-year.ps1` | Annual incident report. | Lists incidents of year through REST. | Az.Accounts; Sentinel Reader | read-only | Hard-coded year 2023 |
| `sentinel-list-automation-rules.ps1` | What automation rules exist? | Exports automation rules via REST. | Az.Accounts; Sentinel Reader | read-only | Legacy token acquisition |
| `sentinel-list-watchlists.ps1` | Watchlist inventory. | Exports watchlists to CSV. | Az.Accounts | read-only |  |
| `sentinel-rules-delete-rule.ps1` | Remove obsolete rule. | Deletes a rule by ID via REST. | Az.Accounts; Sentinel Contributor | destructive | ruleId empty by default |
| `sentinel-rules-list.ps1` | Rule inventory. | Lists rules via REST. | Az.Accounts | read-only | Hard-coded subscription placeholder in URI |
| `sentinel-rules-search-by-table.ps1` | Which rules depend on a table? | Filters rules by table in query. | Az.Accounts | read-only | Hard-coded URI placeholder |
| `sentinel-rules-update-names.ps1` | Rule naming convention. | Adds prefixes to rule display names. | Az.SecurityInsights; Sentinel Contributor | changes-state | Portuguese warning: update disables CreateIncident option; org naming prefix |
| `sentinel-rules-using-watchlists.ps1` | Impact analysis before changing a watchlist. | Searches rule queries for watchlist usage. | Az.Accounts | read-only |  |
| `sentinel-split-exported-analytics-rules.ps1` | Exported bulk ARM template is hard to manage per rule. | Splits exported JSON into one file per rule with actions. | none | read-only |  |
| `sentinel-watchlist-use-case-catalog.ps1` | I need the rule inventory searchable in KQL. | Exports analytic rule metadata into a watchlist. | Az.Accounts; Sentinel Contributor | changes-state | Workspace placeholders |
