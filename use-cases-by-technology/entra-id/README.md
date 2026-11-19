# Entra ID

Microsoft Entra ID sign-in and audit logs: impossible travel, MFA abuse, brute force and spray, privileged roles, Conditional Access, app consent, service principal credentials, anonymizer sign-ins.

**Use this folder when:** You are watching identities and directory changes in a Microsoft cloud tenant.

**Data sources:** SigninLogs, AuditLogs (Entra ID connector in Microsoft Sentinel); index=azure in Splunk.

## Rules

| ID | Name | MITRE technique | Severity | Data source |
|---|---|---|---|---|
| [KQL-001](./kql/kql-001-impossible-travel.kql) | Impossible travel between successful sign-ins | T1078.004 | Medium | SigninLogs |
| [KQL-002](./kql/kql-002-mfa-fatigue-repeated-denials.kql) | MFA fatigue: repeated MFA denials followed by success | T1621 | High | SigninLogs |
| [KQL-003](./kql/kql-003-risky-sign-in.kql) | Risky sign-in detected by identity protection | T1078 | Medium | SigninLogs; Watchlist VIPUsers |
| [KQL-004](./kql/kql-004-brute-force-sign-in.kql) | Brute force: many password failures for one account | T1110.001 | Medium | SigninLogs |
| [KQL-005](./kql/kql-005-password-spray.kql) | Password spray: few attempts across many accounts | T1110.003 | High | SigninLogs |
| [KQL-006](./kql/kql-006-privileged-role-assignment.kql) | Privileged directory role assigned | T1098.003 | High | AuditLogs |
| [KQL-007](./kql/kql-007-conditional-access-policy-changed.kql) | Conditional Access policy created, changed or deleted | T1556.009 | High | AuditLogs |
| [KQL-008](./kql/kql-008-app-registration-consent-grant.kql) | New application registration or consent grant | T1528 | Medium | AuditLogs |
| [KQL-009](./kql/kql-009-service-principal-credential-added.kql) | Credential added to application or service principal | T1098.001 | High | AuditLogs |
| [KQL-017](./kql/kql-017-tor-anonymizer-sign-in.kql) | Sign-in from TOR or anonymizer address | T1090.003 | Medium | SigninLogs; AADNonInteractiveUserSignInLogs; Watchlist TorExitNodes |
| [KQL-019](./kql/kql-019-new-admin-account-created.kql) | New account created and given a privileged role | T1136.003 | High | AuditLogs |
| [KQL-024](./kql/kql-024-privileged-sign-in-without-mfa.kql) | Privileged account signed in with single-factor authentication | T1078.004 | High | SigninLogs; Watchlist PrivilegedAccounts |
| [KQL-027](./kql/kql-027-mfa-method-registered.kql) | MFA method registered or changed | T1556.006 | Medium | AuditLogs; Watchlist PrivilegedAccounts |
| [SPL-008](./spl/spl-008-impossible-travel.spl) | Impossible travel between sign-ins | T1078.004 | Medium | index=azure (sign-in logs) |
| [SPL-009](./spl/spl-009-mfa-fatigue.spl) | MFA fatigue: repeated MFA denials | T1621 | High | index=azure (sign-in logs) |
| [SPL-010](./spl/spl-010-privileged-role-assignment.spl) | Privileged directory role assigned | T1098.003 | High | index=azure (audit logs) |
| [SPL-011](./spl/spl-011-conditional-access-policy-change.spl) | Conditional Access policy changed | T1556.009 | High | index=azure (audit logs) |
| [SPL-012](./spl/spl-012-app-consent-and-credentials.spl) | Application consent or credential added | T1528 | Medium | index=azure (audit logs) |

13 KQL rule(s) in `kql/` (Microsoft Sentinel and Defender XDR) and 5 SPL search(es) in `spl/` (Splunk).

## Watchlists (examples)
All values are fictional. Documentation IP ranges and `contoso.com` addresses only.

| File | Alias | Search key | Used by |
|---|---|---|---|
| [PrivilegedAccounts.csv](./watchlists/PrivilegedAccounts.csv) | `PrivilegedAccounts` | `UserPrincipalName` | KQL-024, KQL-027 |
| [TorExitNodes.csv](./watchlists/TorExitNodes.csv) | `TorExitNodes` | `IPAddress` | KQL-017 |
| [VIPUsers.csv](./watchlists/VIPUsers.csv) | `VIPUsers` | `UserPrincipalName` | KQL-003 |

Create a Sentinel watchlist with the alias above and upload the CSV; queries read it through `_GetWatchlist('<alias>')`. Replace the sample rows with your own data. Refresh TOR data daily from a threat intelligence source; the sample addresses are not real exit nodes. Keep an owner and review date for each list and limit who can edit it.

## Conventions
- KQL: time filter first, tunable values as `let` statements, entities projected for mapping. Validate table and column names in your workspace.
- SPL: example indexes (`wineventlog`, `sysmon`, `azure`, `o365`, `firewall`, `proxy`, `dns`, `waf`); rename to your own.
- Every rule starts as `Draft`; test it as described in [../../use-case-management/testing](../../use-case-management/testing/README.md) before promoting.
