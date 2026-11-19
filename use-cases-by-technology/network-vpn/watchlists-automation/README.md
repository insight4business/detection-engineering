# Watchlists Automation

Scripts for the **network-vpn** technology in this sub-process.

## Scripts adapted from field work

Each script solves one problem. They were adapted from real operations work: replace every `ENTRE_AQUI_COM_SEU_*` marker, review, and test in a non-production tenant first.

| Script | Problem it solves | What it does | Requires | Effect | Notes |
|---|---|---|---|---|---|
| `sentinel-watchlist-firewall-blocked-ips.ps1` | Alerts must know which IPs are blocked. | Syncs IP Group addresses to a watchlist. | Az.Network, Sentinel Contributor | changes-state | Hard-coded org IP Group ID |
