# Microsoft 365: Exchange Online

Mailbox forwarding and suspicious inbox rules, the usual business e-mail compromise footprint.

**Use this folder when:** You are watching e-mail abuse and mailbox persistence.

**Data sources:** OfficeActivity (Exchange workload); index=o365 in Splunk.

## Rules

| ID | Name | MITRE technique | Severity | Data source |
|---|---|---|---|---|
| [KQL-015](./kql/kql-015-mailbox-forwarding-rule-created.kql) | Mailbox forwarding configured | T1114.003 | High | OfficeActivity |
| [KQL-016](./kql/kql-016-inbox-rule-suspicious.kql) | Suspicious inbox rule that hides or deletes mail | T1564.008 | High | OfficeActivity |
| [SPL-006](./spl/spl-006-o365-mailbox-rules.spl) | Mailbox forwarding or redirect rule (Office 365) | T1114.003 | High | index=o365 |

2 KQL rule(s) in `kql/` (Microsoft Sentinel and Defender XDR) and 1 SPL search(es) in `spl/` (Splunk).

## Conventions
- KQL: time filter first, tunable values as `let` statements, entities projected for mapping. Validate table and column names in your workspace.
- SPL: example indexes (`wineventlog`, `sysmon`, `azure`, `o365`, `firewall`, `proxy`, `dns`, `waf`); rename to your own.
- Every rule starts as `Draft`; test it as described in [../../use-case-management/testing](../../use-case-management/testing/README.md) before promoting.
