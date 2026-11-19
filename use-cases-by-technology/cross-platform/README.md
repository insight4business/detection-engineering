# Cross-platform

Detections that span more than one data source, such as TOR activity in cloud sign-ins and firewall logs.

**Use this folder when:** The use case needs several data sources at once.

**Data sources:** Sign-in logs plus network logs.

## Rules

| ID | Name | MITRE technique | Severity | Data source |
|---|---|---|---|---|
| [SPL-021](./spl/spl-021-tor-exit-node-activity.spl) | Activity from TOR exit nodes | T1090.003 | Medium | index=azure; index=firewall; lookup tor_exit_nodes |

0 KQL rule(s) in `kql/` (Microsoft Sentinel and Defender XDR) and 1 SPL search(es) in `spl/` (Splunk).

## Lookups (examples)
Fictional sample data for the SPL searches.

| File | Used by | Columns |
|---|---|---|
| [tor_exit_nodes.csv](./lookups/tor_exit_nodes.csv) | SPL-021 | ip, is_tor, source, added_on |

Upload as lookup table files (CSV) in your app context and restrict edit rights to the detection team.

## Conventions
- KQL: time filter first, tunable values as `let` statements, entities projected for mapping. Validate table and column names in your workspace.
- SPL: example indexes (`wineventlog`, `sysmon`, `azure`, `o365`, `firewall`, `proxy`, `dns`, `waf`); rename to your own.
- Every rule starts as `Draft`; test it as described in [../../use-case-management/testing](../../use-case-management/testing/README.md) before promoting.
