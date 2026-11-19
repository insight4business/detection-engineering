# Endpoint: Defender and Windows

Process, service, task and event-log activity on Windows endpoints and servers: PowerShell, LSASS access, service creation, log clearing, local admin changes.

**Use this folder when:** You are watching hosts for execution, persistence and defense evasion.

**Data sources:** DeviceProcessEvents, SecurityEvent, Event; index=wineventlog and index=sysmon in Splunk.

## Rules

| ID | Name | MITRE technique | Severity | Data source |
|---|---|---|---|---|
| [KQL-021](./kql/kql-021-remote-service-creation.kql) | Suspicious service installed (remote execution pattern) | T1543.003 | High | SecurityEvent |
| [KQL-022](./kql/kql-022-suspicious-powershell.kql) | Suspicious PowerShell command line | T1059.001 | Medium | DeviceProcessEvents |
| [KQL-025](./kql/kql-025-lsass-credential-dumping.kql) | Credential dumping from LSASS process memory | T1003.001 | High | DeviceProcessEvents |
| [KQL-026](./kql/kql-026-security-event-log-cleared.kql) | Windows event log cleared | T1070.001 | High | SecurityEvent; Event |
| [SPL-003](./spl/spl-003-new-local-admin.spl) | Member added to local Administrators group | T1098 | High | index=wineventlog (Security) |
| [SPL-004](./spl/spl-004-service-creation.spl) | Suspicious Windows service creation | T1543.003 | High | index=wineventlog (System, Security) |
| [SPL-013](./spl/spl-013-event-log-cleared.spl) | Windows event log cleared | T1070.001 | High | index=wineventlog |
| [SPL-014](./spl/spl-014-suspicious-powershell.spl) | Suspicious PowerShell command line | T1059.001 | Medium | index=sysmon (process creation) |
| [SPL-015](./spl/spl-015-lsass-access.spl) | Process access to LSASS with dump-capable rights | T1003.001 | High | index=sysmon (process access) |
| [SPL-018](./spl/spl-018-scheduled-task-created.spl) | Scheduled task created with a script host or odd path | T1053.005 | Medium | index=wineventlog (Security) |

4 KQL rule(s) in `kql/` (Microsoft Sentinel and Defender XDR) and 6 SPL search(es) in `spl/` (Splunk).

## Lookups (examples)
Fictional sample data for the SPL searches.

| File | Used by | Columns |
|---|---|---|
| [lsass_allowed_sources.csv](./lookups/lsass_allowed_sources.csv) | SPL-015 | SourceImage, owner, notes |

Upload as lookup table files (CSV) in your app context and restrict edit rights to the detection team.

## Conventions
- KQL: time filter first, tunable values as `let` statements, entities projected for mapping. Validate table and column names in your workspace.
- SPL: example indexes (`wineventlog`, `sysmon`, `azure`, `o365`, `firewall`, `proxy`, `dns`, `waf`); rename to your own.
- Every rule starts as `Draft`; test it as described in [../../use-case-management/testing](../../use-case-management/testing/README.md) before promoting.
