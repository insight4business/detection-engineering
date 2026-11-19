# Use cases by technology

One folder per product or data source, the way Microsoft Sentinel content is organised: analytic rules (`kql/`, `spl/`), watchlists and lookups next to the rules they feed. Pick the folder for the platform you are monitoring.

| Technology | Rules (KQL / SPL) | Typical question |
|---|---|---|
| [Entra ID](./entra-id) | 13 / 5 | Who signed in, from where, and what changed in the tenant? |
| [Microsoft 365: Exchange Online](./microsoft-365-exchange) | 2 / 1 | Is a mailbox forwarding or hiding mail? |
| [Microsoft 365: SharePoint, OneDrive and Teams](./microsoft-365-sharepoint-teams) | 1 / 1 | Is someone downloading files in bulk? |
| [Azure platform](./azure-platform) | 6 / 3 | Did someone weaken or expose an Azure resource? |
| [Endpoint: Defender and Windows](./endpoint-defender-windows) | 4 / 6 | What ran on the host and did it tamper with logs? |
| [Active Directory and identity attacks](./active-directory-identity-attacks) | 2 / 5 | Is someone attacking Windows accounts or moving laterally? |
| [Network, firewall, proxy and DNS](./network-vpn) | 0 / 3 | Is traffic probing or leaving the network? |
| [Cross-platform](./cross-platform) | 0 / 1 | Does the detection need more than one source? |

No `aws/` folder yet: there are no AWS rules in this library. Add `aws/kql` or `aws/spl` (CloudTrail, GuardDuty) when you write them, following the same layout.

To add a rule: copy the template in [../use-case-management](../use-case-management), save the query in the right technology folder, add a register row and update the coverage matrix.
