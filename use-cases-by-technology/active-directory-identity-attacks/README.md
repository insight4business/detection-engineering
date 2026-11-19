# Active Directory and identity attacks

Credential attacks against Windows and directory accounts: Kerberoasting, password spray, logon failures, lockouts, remote logon fan-out.

**Use this folder when:** You are watching on-premises identity attacks and lateral movement.

**Data sources:** SecurityEvent, DeviceLogonEvents; index=wineventlog in Splunk.

## Rules

| ID | Name | MITRE technique | Severity | Data source |
|---|---|---|---|---|
| [KQL-020](./kql/kql-020-lateral-movement-remote-services.kql) | Lateral movement: one account logs on to many devices remotely | T1021 | Medium | DeviceLogonEvents |
| [KQL-028](./kql/kql-028-kerberoasting.kql) | Kerberoasting: many service tickets with weak encryption | T1558.003 | High | SecurityEvent |
| [SPL-001](./spl/spl-001-windows-logon-failures-burst.spl) | Windows logon failures from one source | T1110 | Medium | index=wineventlog (Security) |
| [SPL-002](./spl/spl-002-password-spray.spl) | Password spray against Windows or directory accounts | T1110.003 | High | index=wineventlog (Security) |
| [SPL-016](./spl/spl-016-lateral-movement-fanout.spl) | Remote logon fan-out across many hosts | T1021 | Medium | index=wineventlog (Security) |
| [SPL-017](./spl/spl-017-account-lockout-spike.spl) | Account lockout spike | T1110 | Medium | index=wineventlog (Security) |
| [SPL-024](./spl/spl-024-kerberoasting.spl) | Kerberoasting: many RC4 service tickets | T1558.003 | High | index=wineventlog (Security) |

2 KQL rule(s) in `kql/` (Microsoft Sentinel and Defender XDR) and 5 SPL search(es) in `spl/` (Splunk).

## Conventions
- KQL: time filter first, tunable values as `let` statements, entities projected for mapping. Validate table and column names in your workspace.
- SPL: example indexes (`wineventlog`, `sysmon`, `azure`, `o365`, `firewall`, `proxy`, `dns`, `waf`); rename to your own.
- Every rule starts as `Draft`; test it as described in [../../use-case-management/testing](../../use-case-management/testing/README.md) before promoting.
