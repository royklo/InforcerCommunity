# InforcerCommunity PowerShell Module

[PowerShell Gallery](https://www.powershellgallery.com/packages/InforcerCommunity)
[CI](https://github.com/royklo/InforcerCommunity/actions)
[License: MIT](LICENSE)

Community PowerShell module for the **Inforcer API**. Connect, query tenants, baselines, policies, alignment scores, and audit events with consistent parameters and output.

## About

This module was **created by Roy Klooster** for the community. It is **not owned or officially maintained by Inforcer**; it is a community project built by a community member to make it easier to work with the Inforcer API from PowerShell.

- **Repository:** [https://github.com/royklo/InforcerCommunity](https://github.com/royklo/InforcerCommunity)
- **PowerShell Gallery:** [https://www.powershellgallery.com/packages/InforcerCommunity](https://www.powershellgallery.com/packages/InforcerCommunity)

## Repository structure

```
InforcerCommunity/
├── README.md                 # This file
├── LICENSE                   # MIT (community project disclaimer)
├── CONTRIBUTING.md           # How to contribute, fork & PR
├── .gitignore
├── .github/
│   ├── ISSUE_TEMPLATE/       # Bug report, feature request
│   ├── PULL_REQUEST_TEMPLATE.md
│   └── workflows/            # build-and-test.yml
├── docs/
│   ├── CMDLET-REFERENCE.md   # Parameters and example output
│   └── API-REFERENCE.md      # API schemas and response structures
├── CHANGELOG.md              # Release history
├── module/                 # Script module (see module/README.md)
│   ├── InforcerCommunity.psd1
│   ├── InforcerCommunity.psm1
│   ├── InforcerCommunity.Format.ps1xml
│   ├── InforcerCommunity.Types.ps1xml
│   ├── README.md
│   ├── Public/               # Exported cmdlets (incl. Export-InforcerTenantDocumentation)
│   └── Private/              # Helpers (API, session, aliases, renderers, Graph, etc.)
└── Tests/
    └── Consistency.Tests.ps1  # Pester tests
```

## Prerequisites

- **PowerShell 7.0+** (cross-platform: Windows, macOS, Linux)
- An **Inforcer API key** (from your Inforcer tenant)

## Installation

### From PowerShell Gallery (recommended)

```powershell
Install-Module -Name InforcerCommunity -Scope CurrentUser
```

### From source (GitHub)

```powershell
git clone https://github.com/royklo/InforcerCommunity.git
cd InforcerCommunity
Import-Module ./module/InforcerCommunity.psd1 -Force
```

Always run `Import-Module` from the **repository root** and use `./module/InforcerCommunity.psd1`. If you see an error about `Inforcer.Format.ps1xml` or a path containing `Inforcer-Powershell-Module`, you are loading the manifest from the wrong directory or an old copy of the repo; switch to the InforcerCommunity repo root and use the path above.

## Quick start

```powershell
# Connect with your API key
Connect-Inforcer -ApiKey "your-api-key" -Region uk

# List tenants
Get-InforcerTenant

# Get alignment score table
Get-InforcerAlignmentDetails

# Get policies for a tenant
Get-InforcerTenantPolicies -TenantId 482

# Show policy changes (PolicyDiff on each tenant when available)
Get-InforcerTenant | Select-Object ClientTenantId, TenantFriendlyName, PolicyDiff

# Generate tenant documentation as HTML
Export-InforcerTenantDocumentation -Format Html -TenantId 482 -OutputPath ./docs

# Generate documentation for a specific baseline with Graph group name resolution
Connect-Inforcer -ApiKey "your-api-key" -Region uk -FetchGraphData
Export-InforcerTenantDocumentation -Format Html -TenantId 482 -Baseline "Production" -FetchGraphData

# Disconnect when done
Disconnect-Inforcer
```

## Cmdlets


| Cmdlet                         | Description                                                 |
| ------------------------------ | ----------------------------------------------------------- |
| **Connect-Inforcer**           | Establishes a secure connection to the Inforcer REST API. Supports `-FetchGraphData` to also connect Microsoft Graph. |
| **Disconnect-Inforcer**        | Disconnects and clears the session (including Graph if connected). |
| **Test-InforcerConnection**    | Tests the API connection.                                   |
| **Get-InforcerTenant**         | Retrieves tenant information (optional filter by TenantId). |
| **Get-InforcerBaseline**       | Retrieves baseline groups and members.                      |
| **Get-InforcerTenantPolicies** | Retrieves policies for a specified tenant.                  |
| **Get-InforcerAlignmentDetails** | Retrieves alignment scores (table or raw format).           |
| **Get-InforcerAuditEvent**     | Retrieves audit events (optional EventType, date range; -EventType has tab completion). |
| **Get-InforcerUser**           | Retrieves users from a tenant (list/search or detail by UserId). |
| **Get-InforcerGroup**          | Retrieves Entra ID groups from a tenant (list/search or detail by GroupId). |
| **Get-InforcerRole**           | Retrieves Entra ID directory role definitions from a tenant. |
| **Export-InforcerTenantDocumentation** | Generates comprehensive tenant documentation in HTML, Markdown, or Excel format. |


For full parameter details and example output, see **[Cmdlet Reference](docs/CMDLET-REFERENCE.md)**. For detailed API schemas and response structures, see **[API Reference](docs/API-REFERENCE.md)**.

## Settings Catalog data

The `Export-InforcerTenantDocumentation` cmdlet resolves Intune Settings Catalog settingDefinitionIDs to friendly names using data from the [IntuneSettingsCatalogData](https://github.com/royklo/IntuneSettingsCatalogData) repository. This data (~65 MB) is **automatically downloaded and cached** on first use at `~/.inforcercommunity/data/settings.json` with a 24-hour TTL.

- **No manual setup required** — the module handles download, caching, and freshness checks automatically
- **Offline support** — if the download fails, the module uses a stale cached copy (or proceeds without resolution, showing raw IDs)
- **Override** — use `-SettingsCatalogPath` to point to a local `settings.json` file instead

The data is refreshed nightly from Microsoft Graph by a GitHub Actions workflow in the [IntuneSettingsCatalogData](https://github.com/royklo/IntuneSettingsCatalogData) repo.

## Contributing

We welcome contributions: fork the repo, make your changes, and open a pull request. See **[CONTRIBUTING.md](CONTRIBUTING.md)** for the workflow, code style, and how to report bugs.

## Issues

Found a bug or have a feature idea? Please open an issue:

- [Bug report](https://github.com/royklo/InforcerCommunity/issues/new?template=bug_report.md)
- [Feature request](https://github.com/royklo/InforcerCommunity/issues/new?template=feature_request.md)

## License

[MIT](LICENSE) — This module was created by Roy Klooster for the community. It is not owned or officially maintained by Inforcer; it is a community project built by a community member to make it easier to work with the Inforcer API from PowerShell.

---

