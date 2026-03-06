# InforcerCommunity PowerShell Script Module

This is the script implementation of the InforcerCommunity module (community project for the Inforcer API). It provides cmdlets to connect to the Inforcer API and query tenants, baselines, policies, alignment scores, and audit events.

## Module structure

```
module/
├── InforcerCommunity.psd1           # Module manifest
├── InforcerCommunity.psm1           # Root script (dot-sources Public + Private)
├── InforcerCommunity.Format.ps1xml  # Default table/list formats
├── InforcerCommunity.Types.ps1xml   # Type definitions
├── README.md                        # This file
├── Public/                          # Exported cmdlets
│   ├── Connect-Inforcer.ps1
│   ├── Disconnect-Inforcer.ps1
│   ├── Test-InforcerConnection.ps1
│   ├── Get-InforcerTenant.ps1
│   ├── Get-InforcerBaseline.ps1
│   ├── Get-InforcerTenantPolicies.ps1
│   ├── Get-InforcerAlignmentScore.ps1
│   └── Get-InforcerAuditEvent.ps1
└── Private/                         # Helpers (not exported)
    ├── Invoke-InforcerApiRequest.ps1
    ├── Test-InforcerSession.ps1
    ├── Get-InforcerBaseUrl.ps1
    ├── Resolve-InforcerTenantId.ps1
    ├── Add-InforcerPropertyAliases.ps1
    ├── Filter-InforcerResponse.ps1
    ├── ConvertFrom-InforcerSecureString.ps1
    ├── ConvertTo-InforcerArray.ps1
    └── Get-InforcerAuditEventType.ps1
```

## Loading the script module

Run from the repository root so the path resolves to this repo's module folder.

From the repository root:

```powershell
Import-Module ./module/InforcerCommunity.psd1 -Force
```

Or from the `module` folder:

```powershell
Import-Module ./InforcerCommunity.psd1 -Force
```

## Quick start

```powershell
Connect-Inforcer -ApiKey "your-api-key" -Region uk
Get-InforcerTenant
Get-InforcerBaseline
```

For full documentation, prerequisites, and contributing, see the repository root **README.md** and **CONTRIBUTING.md**.
