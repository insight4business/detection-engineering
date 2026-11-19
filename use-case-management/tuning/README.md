# Tuning

Scripts for the **sentinel-api** technology in this sub-process.

## Scripts adapted from field work

Each script solves one problem. They were adapted from real operations work: replace every `ENTRE_AQUI_COM_SEU_*` marker, review, and test in a non-production tenant first.

| Script | Problem it solves | What it does | Requires | Effect | Notes |
|---|---|---|---|---|---|
| `sentinel-incidents-aggregate-by-analytics-rule.ps1` | I need data to tune a noisy rule. | Queries incidents for a rule and aggregates events to Excel. | Az.OperationalInsights, ImportExcel | read-only | Hard-coded rule name |
