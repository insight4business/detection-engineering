# Microsoft 365: SharePoint, OneDrive and Teams

Mass download and exfiltration from SharePoint and OneDrive.

**Use this folder when:** You are watching data leaving collaboration platforms.

**Data sources:** OfficeActivity (SharePoint and OneDrive workloads); index=o365 in Splunk.

## Rules

| ID | Name | MITRE technique | Severity | Data source |
|---|---|---|---|---|
| [KQL-014](./kql/kql-014-mass-download-exfiltration.kql) | Mass file download from SharePoint or OneDrive | T1567 | Medium | OfficeActivity |
| [SPL-020](./spl/spl-020-o365-mass-download.spl) | Mass file download from SharePoint or OneDrive (Office 365) | T1530 | Medium | index=o365 |

1 KQL rule(s) in `kql/` (Microsoft Sentinel and Defender XDR) and 1 SPL search(es) in `spl/` (Splunk).

## Conventions
- KQL: time filter first, tunable values as `let` statements, entities projected for mapping. Validate table and column names in your workspace.
- SPL: example indexes (`wineventlog`, `sysmon`, `azure`, `o365`, `firewall`, `proxy`, `dns`, `waf`); rename to your own.
- Every rule starts as `Draft`; test it as described in [../../use-case-management/testing](../../use-case-management/testing/README.md) before promoting.
