# Azure platform

Control plane and resource logs: Key Vault, storage, NSG and firewall, Azure Policy, diagnostic settings, WAF.

**Use this folder when:** You are watching changes to subscriptions and exposure of Azure resources.

**Data sources:** AzureActivity, AzureDiagnostics (Key Vault, WAF); index=azure and index=waf in Splunk.

## Rules

| ID | Name | MITRE technique | Severity | Data source |
|---|---|---|---|---|
| [KQL-010](./kql/kql-010-key-vault-secret-access-anomaly.kql) | Key Vault secret access from a new caller | T1555.006 | High | AzureDiagnostics |
| [KQL-011](./kql/kql-011-nsg-firewall-rule-changed.kql) | Network security group or firewall rule changed | T1562.007 | Medium | AzureActivity |
| [KQL-012](./kql/kql-012-azure-policy-assignment-deleted.kql) | Azure Policy assignment deleted or exempted | T1562 | High | AzureActivity |
| [KQL-013](./kql/kql-013-storage-public-access-enabled.kql) | Storage account or container public access enabled | T1530 | High | AzureActivity |
| [KQL-018](./kql/kql-018-audit-diagnostic-settings-disabled.kql) | Audit or diagnostic logging disabled | T1562.008 | High | AzureActivity |
| [KQL-023](./kql/kql-023-waf-block-spike.kql) | WAF block spike against a web application | T1190 | Medium | AzureDiagnostics |
| [SPL-022](./spl/spl-022-nsg-firewall-change.spl) | Network security group or firewall rule changed (Azure) | T1562.007 | Medium | index=azure (activity log) |
| [SPL-023](./spl/spl-023-diagnostic-settings-disabled.spl) | Diagnostic settings or log workspace deleted (Azure) | T1562.008 | High | index=azure (activity log) |
| [SPL-025](./spl/spl-025-waf-block-spike.spl) | WAF block spike | T1190 | Medium | index=waf |

6 KQL rule(s) in `kql/` (Microsoft Sentinel and Defender XDR) and 3 SPL search(es) in `spl/` (Splunk).

## Conventions
- KQL: time filter first, tunable values as `let` statements, entities projected for mapping. Validate table and column names in your workspace.
- SPL: example indexes (`wineventlog`, `sysmon`, `azure`, `o365`, `firewall`, `proxy`, `dns`, `waf`); rename to your own.
- Every rule starts as `Draft`; test it as described in [../../use-case-management/testing](../../use-case-management/testing/README.md) before promoting.
