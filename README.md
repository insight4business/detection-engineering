# Detection Engineering

Detection use cases in KQL (Microsoft Sentinel and Defender XDR) and SPL (Splunk) mapped to MITRE ATT&CK, with tuning, testing and detection-as-code. All content is generic and fictional (Contoso Ltd.); documentation IP ranges and `contoso.com` are used everywhere.

## Find what you need

| Sub-process | Folder | What it contains |
|---|---|---|
| Build and run detections | [use-cases-by-technology/](./use-cases-by-technology) | One folder per technology (Entra ID, Exchange, SharePoint and Teams, Azure platform, endpoint, Active Directory attacks, network, cross-platform) with `kql/`, `spl/`, watchlists or lookups and a rule list |
| Manage the use case lifecycle | [use-case-management/](./use-case-management) | Template, register (53 rows), tuning, testing, detection-as-code pipelines and the MITRE coverage matrix |

## Technologies

| Technology | KQL | SPL |
|---|---|---|
| [Entra ID](./use-cases-by-technology/entra-id) | 13 | 5 |
| [Microsoft 365: Exchange](./use-cases-by-technology/microsoft-365-exchange) | 2 | 1 |
| [Microsoft 365: SharePoint and Teams](./use-cases-by-technology/microsoft-365-sharepoint-teams) | 1 | 1 |
| [Azure platform](./use-cases-by-technology/azure-platform) | 6 | 3 |
| [Endpoint: Defender and Windows](./use-cases-by-technology/endpoint-defender-windows) | 4 | 6 |
| [Active Directory and identity attacks](./use-cases-by-technology/active-directory-identity-attacks) | 2 | 5 |
| [Network, firewall, proxy and DNS](./use-cases-by-technology/network-vpn) | 0 | 3 |
| [Cross-platform](./use-cases-by-technology/cross-platform) | 0 | 1 |

## How to use

1. Copy the template you need.
2. Replace every `<PLACEHOLDER>` with your own values.
3. Review with your own legal and security teams before adopting.
4. Treat every rule as `Draft` until it passes the tests in [use-case-management/testing](./use-case-management/testing); validate table and field names in your environment.
5. Run the lint in [detection-as-code](./use-case-management/detection-as-code) and the repository sanitization gate before committing.

## License
Elastic License 2.0: free to use, copy and modify, including inside your own company and for your own clients' projects. You may not provide it to third parties as a hosted or managed service. See [LICENSE](./LICENSE).
