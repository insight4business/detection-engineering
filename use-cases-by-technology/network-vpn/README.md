# Network, firewall, proxy and DNS

Perimeter and network telemetry: firewall deny spikes, proxy exfiltration, DNS tunneling. Extend with VPN gateway logs.

**Use this folder when:** You are watching traffic leaving or probing the network.

**Data sources:** index=firewall, index=proxy, index=dns in Splunk; CommonSecurityLog in Sentinel.

## Rules

| ID | Name | MITRE technique | Severity | Data source |
|---|---|---|---|---|
| [SPL-005](./spl/spl-005-firewall-deny-spike.spl) | Firewall deny spike by source | T1046 | Low | index=firewall |
| [SPL-007](./spl/spl-007-proxy-data-exfiltration.spl) | Large outbound transfer through the web proxy | T1567 | Medium | index=proxy |
| [SPL-019](./spl/spl-019-dns-tunneling.spl) | DNS tunneling indicators | T1071.004 | Medium | index=dns |

0 KQL rule(s) in `kql/` (Microsoft Sentinel and Defender XDR) and 3 SPL search(es) in `spl/` (Splunk).

## Lookups (examples)
Fictional sample data for the SPL searches.

| File | Used by | Columns |
|---|---|---|
| [sanctioned_destinations.csv](./lookups/sanctioned_destinations.csv) | SPL-007 | domain, owner, notes |

Upload as lookup table files (CSV) in your app context and restrict edit rights to the detection team.

## Conventions
- KQL: time filter first, tunable values as `let` statements, entities projected for mapping. Validate table and column names in your workspace.
- SPL: example indexes (`wineventlog`, `sysmon`, `azure`, `o365`, `firewall`, `proxy`, `dns`, `waf`); rename to your own.
- Every rule starts as `Draft`; test it as described in [../../use-case-management/testing](../../use-case-management/testing/README.md) before promoting.
