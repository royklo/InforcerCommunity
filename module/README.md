# InforcerCommunity PowerShell Script Module

This is the script implementation of the InforcerCommunity module (community project for the Inforcer API). It provides cmdlets to connect to the Inforcer API and work with tenants, baselines, policies, alignment scores, audit events, users, groups, roles, assessments, and reports — plus utility cmdlets for documentation export and cross-tenant comparison.

## Module structure

```
module/
├── InforcerCommunity.psd1           # Module manifest
├── InforcerCommunity.psm1           # Root script (dot-sources Public + Private)
├── InforcerCommunity.Format.ps1xml  # Default table/list formats
├── InforcerCommunity.Types.ps1xml   # Type definitions
├── README.md                        # This file
├── Public/                          # Exported cmdlets (21)
│   ├── Connect-Inforcer.ps1
│   ├── Disconnect-Inforcer.ps1
│   ├── Test-InforcerConnection.ps1
│   ├── Get-InforcerTenant.ps1
│   ├── Get-InforcerBaseline.ps1
│   ├── Get-InforcerTenantPolicies.ps1
│   ├── Get-InforcerAlignmentDetails.ps1
│   ├── Get-InforcerAuditEvent.ps1
│   ├── Get-InforcerSupportedEventType.ps1
│   ├── Get-InforcerUser.ps1
│   ├── Get-InforcerGroup.ps1
│   ├── Get-InforcerRole.ps1
│   ├── Get-InforcerSecureScore.ps1
│   ├── Export-InforcerTenantDocumentation.ps1
│   ├── Compare-InforcerEnvironments.ps1
│   ├── Get-InforcerAssessment.ps1
│   ├── Invoke-InforcerAssessment.ps1
│   ├── Get-InforcerReportType.ps1
│   ├── Invoke-InforcerReport.ps1
│   ├── Get-InforcerReportRun.ps1
│   └── Save-InforcerReportOutput.ps1
└── Private/                         # Helpers (not exported)
    └── ... (see directory listing)
```

For the full list of cmdlets with descriptions, see the repository root [`README.md`](../README.md). For parameter-level docs, see [`docs/CMDLET-REFERENCE.md`](../docs/CMDLET-REFERENCE.md). For endpoint and schema docs, see [`docs/API-REFERENCE.md`](../docs/API-REFERENCE.md).

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
