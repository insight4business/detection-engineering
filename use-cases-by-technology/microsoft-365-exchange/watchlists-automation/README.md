# Watchlists Automation

Scripts for the **microsoft-365-exchange** technology in this sub-process.

## Scripts adapted from field work

Each script solves one problem. They were adapted from real operations work: replace every `ENTRE_AQUI_COM_SEU_*` marker, review, and test in a non-production tenant first.

| Script | Problem it solves | What it does | Requires | Effect | Notes |
|---|---|---|---|---|---|
| `sentinel-watchlist-exchange-mailbox-permissions.ps1` | Detect abnormal mailbox delegations. | Collects mailbox/DL permissions into a watchlist. | ExchangeOnlineManagement; Sentinel Contributor | changes-state |  |
| `sentinel-watchlist-exchange-mailboxes-and-groups.ps1` | Enrich with mailbox inventory. | Refreshes mailboxes and distribution groups watchlist. | ExchangeOnlineManagement | changes-state |  |
