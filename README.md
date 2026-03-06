# Inforcer PowerShell Module

[PowerShell Gallery](https://www.powershellgallery.com/packages/Inforcer)
[CI](https://github.com/royklo/Inforcer-Powershell-Module/actions)
[License: MIT](LICENSE)

PowerShell module for the **Inforcer API**. Connect, query tenants, baselines, policies, alignment scores, and audit events with consistent parameters and output.

## About

This module was **created by Roy Klooster** for the community. It is **not owned or officially maintained by Inforcer**; it is a community project built by a community member to make it easier to work with the Inforcer API from PowerShell.

- **Repository:** [https://github.com/royklo/Inforcer-Powershell-Module](https://github.com/royklo/Inforcer-Powershell-Module)
- **PowerShell Gallery:** [https://www.powershellgallery.com/packages/Inforcer](https://www.powershellgallery.com/packages/Inforcer)

## Repository structure

```
Inforcer-Powershell-Module/
├── README.md                 # This file
├── LICENSE                   # MIT (community project disclaimer)
├── CONTRIBUTING.md           # How to contribute, fork & PR
├── .gitignore
├── .github/
│   ├── ISSUE_TEMPLATE/       # Bug report, feature request
│   ├── PULL_REQUEST_TEMPLATE.md
│   └── workflows/            # build-and-test.yml
├── docs/
│   └── CMDLET-REFERENCE.md   # Parameters and example output
├── CHANGELOG.md              # Release history
├── module/                 # Script module (see module/README.md)
│   ├── Inforcer.psd1
│   ├── Inforcer.psm1
│   ├── Inforcer.Format.ps1xml
│   ├── Inforcer.Types.ps1xml
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
Install-Module -Name Inforcer -Scope CurrentUser
```

### From source (GitHub)

```powershell
git clone https://github.com/royklo/Inforcer-Powershell-Module.git
cd Inforcer-Powershell-Module
Import-Module ./module -Force
```

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


For full parameter details and example output, see **[Cmdlet Reference](docs/CMDLET-REFERENCE.md)**.

## Contributing

We welcome contributions: fork the repo, make your changes, and open a pull request. See **[CONTRIBUTING.md](CONTRIBUTING.md)** for the workflow, code style, and how to report bugs.

## Issues

Found a bug or have a feature idea? Please open an issue:

- [Bug report](https://github.com/royklo/Inforcer-Powershell-Module/issues/new?template=bug_report.md)
- [Feature request](https://github.com/royklo/Inforcer-Powershell-Module/issues/new?template=feature_request.md)

## License

[MIT](LICENSE) — (c) Roy Klooster. Community project, not affiliated with Inforcer.

---

