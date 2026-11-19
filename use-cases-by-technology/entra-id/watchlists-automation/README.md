# Watchlists Automation

Scripts for the **entra-id** technology in this sub-process.

## Scripts adapted from field work

Each script solves one problem. They were adapted from real operations work: replace every `ENTRE_AQUI_COM_SEU_*` marker, review, and test in a non-production tenant first.

| Script | Problem it solves | What it does | Requires | Effect | Notes |
|---|---|---|---|---|---|
| `sentinel-watchlist-entra-group-membership.ps1` | Rules must know who belongs to sensitive groups. | Dumps group membership into a watchlist. | Microsoft.Graph; Sentinel Contributor | changes-state |  |
| `sentinel-watchlist-entra-groups.ps1` | Enrich alerts with group info. | Refreshes Entra groups watchlist. | Microsoft.Graph | changes-state |  |
| `sentinel-watchlist-entra-role-assignments.ps1` | Detect privileged role changes by comparing with known assignments. | Refreshes watchlist of directory role assignments. | Microsoft.Graph | changes-state |  |
| `sentinel-watchlist-entra-roles.ps1` | Enrich with role names. | Refreshes watchlist of Entra roles. | Microsoft.Graph | changes-state |  |
| `sentinel-watchlist-entra-service-principals.ps1` | Detect abuse of app identities. | Refreshes watchlist of service principals. | Microsoft.Graph | changes-state |  |
