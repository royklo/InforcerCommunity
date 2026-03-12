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
│   ├── Public/               # Exported cmdlets
│   └── Private/              # Helpers (API, session, aliases, etc.)
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
Get-InforcerAlignmentScore

# Get policies for a tenant
Get-InforcerTenantPolicies -TenantId 482

# Show policy changes (PolicyDiffFormatted on each tenant when available)
Get-InforcerTenant | Select-Object ClientTenantId, TenantFriendlyName, PolicyDiffFormatted

# Disconnect when done
Disconnect-Inforcer
```

## Cmdlets


| Cmdlet                         | Description                                                 |
| ------------------------------ | ----------------------------------------------------------- |
| **Connect-Inforcer**           | Establishes a secure connection to the Inforcer REST API.   |
| **Disconnect-Inforcer**        | Disconnects and clears the session.                         |
| **Test-InforcerConnection**    | Tests the API connection.                                   |
| **Get-InforcerTenant**         | Retrieves tenant information (optional filter by TenantId). |
| **Get-InforcerBaseline**       | Retrieves baseline groups and members.                      |
| **Get-InforcerTenantPolicies** | Retrieves policies for a specified tenant.                  |
| **Get-InforcerAlignmentScore** | Retrieves alignment scores (table or raw format).           |
| **Get-InforcerAuditEvent**     | Retrieves audit events (optional EventType, date range; -EventType has tab completion). |


For full parameter details and example output, see **[Cmdlet Reference](docs/CMDLET-REFERENCE.md)**. For detailed API schemas and response structures, see **[API Reference](docs/API-REFERENCE.md)**.

## Contributing

We welcome contributions: fork the repo, make your changes, and open a pull request. See **[CONTRIBUTING.md](CONTRIBUTING.md)** for the workflow, code style, and how to report bugs.

## Issues

Found a bug or have a feature idea? Please open an issue:

- [Bug report](https://github.com/royklo/InforcerCommunity/issues/new?template=bug_report.md)
- [Feature request](https://github.com/royklo/InforcerCommunity/issues/new?template=feature_request.md)

## License

[MIT](LICENSE) — This module was created by Roy Klooster for the community. It is not owned or officially maintained by Inforcer; it is a community project built by a community member to make it easier to work with the Inforcer API from PowerShell.

---

