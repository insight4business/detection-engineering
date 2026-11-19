# Watchlists Automation

Scripts for the **azure-platform** technology in this sub-process.

## Scripts adapted from field work

Each script solves one problem. They were adapted from real operations work: replace every `ENTRE_AQUI_COM_SEU_*` marker, review, and test in a non-production tenant first.

| Script | Problem it solves | What it does | Requires | Effect | Notes |
|---|---|---|---|---|---|
| `sentinel-watchlist-azure-iam-role-assignments.ps1` | Detections need current Azure role assignments. | Resolves Azure role assignments with Graph and refreshes a Sentinel watchlist. | Az, Microsoft.Graph; Sentinel Contributor | changes-state | Org tenant/workspace placeholders; managed identity |
| `sentinel-watchlist-azure-roles.ps1` | Detections need current privileged Azure roles. | Refreshes watchlist of Azure role definitions. | Az.Accounts, Graph | changes-state |  |
