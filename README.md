# InforcerCommunity PowerShell Module

[PowerShell Gallery](https://www.powershellgallery.com/packages/InforcerCommunity)
[CI](https://github.com/royklo/InforcerCommunity/actions)
[License: MIT](LICENSE)

Community PowerShell module for the **inforcer API**. Connect, query tenants, baselines, policies, alignment scores, and audit events with consistent parameters and output.

## About

This module was **created by Roy Klooster** for the community. It is **not owned or officially maintained by inforcer**; it is a community project built by a community member to make it easier to work with the inforcer API from PowerShell.

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
│   ├── API-REFERENCE.md      # API schemas, response structures, permissions
│   └── openapi-snapshot*.json # Tracked inforcer API specs (beta, v1)
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
    ├── Consistency.Tests.ps1  # Pester tests
    └── V1.*.Tests.ps1         # Mocked v1 (client credentials) suites
```

## Prerequisites

- **PowerShell 7.0+** (cross-platform: Windows, macOS, Linux)
- An **inforcer API client** (client ID and secret) - recommended. Create one in the inforcer portal under **Configure > REST API**, and grant it the permissions the cmdlets you use need (see [API Reference](docs/API-REFERENCE.md#api-client-permissions-v1)).
- or, **legacy**: an **inforcer API key** (still works, see [Legacy API key](#legacy-api-key-login))

The module picks the API from the way you log in: an API client uses the current **v1** API, an API key uses the legacy **beta** API. You never choose per cmdlet.

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

Always run `Import-Module` from the **repository root** and use `./module/InforcerCommunity.psd1`. If you see an error about `inforcer.Format.ps1xml` or a path containing `Inforcer-Powershell-Module`, you are loading the manifest from the wrong directory or an old copy of the repo; switch to the InforcerCommunity repo root and use the path above.

## Quick start

### Client credentials (recommended)

```powershell
# Connect with an API client. The access token lasts 60 minutes and is renewed automatically.
$secret = Read-Host -AsSecureString -Prompt 'Client secret'
Connect-Inforcer -ClientId '<client-id>' -ClientSecret $secret -Region uk

# List tenants (name, DNS name and Microsoft tenant ID)
Get-InforcerTenant

# Full tenant records (licenses, secure score, baseline flag, tags, alignment) - one extra call per tenant
Get-InforcerTenant -Detailed

# Tenants are addressed by Microsoft tenant ID (GUID) or name
Get-InforcerTenantPolicies -TenantId '00000000-0000-0000-0000-000000000000'
Get-InforcerTenant | Get-InforcerSecureScore   # pipeline binds MsTenantId

# Alignment score table
Get-InforcerAlignmentDetails
```

`-TenantId` accepts the aliases `ClientTenantId` and `MsTenantId`, so objects from `Get-InforcerTenant` bind through the pipeline in both logins.

### API key (legacy)

```powershell
# Connect with your API key (prints a warning, see below)
Connect-Inforcer -ApiKey "your-api-key" -Region uk

# Numeric Client Tenant IDs work only with an API key
Get-InforcerTenantPolicies -TenantId 482

# Show policy changes (PolicyDiff on each tenant when available)
Get-InforcerTenant | Select-Object ClientTenantId, TenantFriendlyName, PolicyDiff
```

### Documentation, comparison and cleanup

```powershell

# Generate tenant documentation as HTML. -OutputPath is what writes the file: omit it and the
# DocModel is returned instead, so you can read the configuration without producing artefacts.
# The report opens in your browser automatically, unless you are on a CI runner or pass -Show:$false.
Export-InforcerTenantDocumentation -Format Html -TenantId 'Contoso' -OutputPath ./docs

# Generate documentation for a specific baseline with Graph group name resolution
Connect-Inforcer -ClientId '<client-id>' -ClientSecret $secret -Region uk -FetchGraphData
Export-InforcerTenantDocumentation -Format Html -TenantId 'Contoso' -Baseline "Production" -FetchGraphData -OutputPath ./docs

# Disconnect when done
Disconnect-Inforcer
```

## Legacy API key login

inforcer's API keys use the **legacy beta API**, which inforcer says is due to be retired. No retirement date has been announced; it only receives bug fixes. `Connect-Inforcer -ApiKey` keeps working and its output is unchanged, but it prints a warning on every login. Switch to client credentials when you can (next section).

## Migrating from API key to client credentials

| What | API key (beta) | Client credentials (v1) |
|------|----------------|--------------------------|
| Login | `Connect-Inforcer -ApiKey $key -Region uk` | `Connect-Inforcer -ClientId $id -ClientSecret $secret -Region uk` |
| Tenant ID | numeric Client Tenant ID, Microsoft tenant ID (GUID) or name | Microsoft tenant ID (GUID) or tenant name. A numeric ID fails with `TenantIdNumericNotSupportedOnV1`. |
| `ClientTenantId` property | present | **absent** (use `MsTenantId`) |
| `Get-InforcerTenant` | rich objects | name, DNS name and Microsoft tenant ID; add `-Detailed` (or `-TenantId`) for the rich fields. `-Detailed` is ignored with an API key, so scripts work with both logins. |
| Permissions | key scopes (`Tenants.Read`, ...) | API client permissions plus optional tenant filters, set in the portal |
| Rate limit | 400 calls/hour per key | 400 calls/minute per partner; throttled calls are retried using `Retry-After` |
| Output | unchanged | the same property names; v1 responses are mapped to them. v1-only fields are added; fields v1 does not have are missing. |

Steps:

1. Create an API client in the inforcer portal (Configure > REST API) and grant the permissions for the cmdlets you use. Keep the secret in a vault or SecureString; it is shown once.
2. Replace the `Connect-Inforcer -ApiKey` line with the `-ClientId`/`-ClientSecret` form.
3. Replace numeric tenant IDs with the Microsoft tenant ID or name (`Get-InforcerTenant` lists them). Scripts that read `ClientTenantId` should read `MsTenantId`.
4. Add `-Detailed` where a script reads `IsBaseline`, licenses, tags, `SecureScore` or alignment summaries from `Get-InforcerTenant`.
5. **Intune gap for now:** the v1 tenant policies endpoint currently returns no Intune policies (and no Defender settings-catalog policies, type 10), with no error. `Get-InforcerTenantPolicies` warns about it once per tenant, and `Export-InforcerTenantDocumentation` and `Compare-InforcerEnvironments` add a note to their reports (no second warning). Until inforcer fixes this, use an API key for Intune-centred documentation and comparison. API-key output is unchanged.

The full list of differences per object is in the [API Reference](docs/API-REFERENCE.md#v1-api-client-credentials).

## Cmdlets


| Cmdlet                         | Description                                                 |
| ------------------------------ | ----------------------------------------------------------- |
| **Connect-Inforcer**           | Establishes a secure connection to the inforcer REST API with an API client (`-ClientId`/`-ClientSecret`, v1) or a legacy API key (`-ApiKey`, beta). Supports `-FetchGraphData` to also connect Microsoft Graph. |
| **Disconnect-Inforcer**        | Disconnects and clears the session (including Graph if connected). |
| **Test-InforcerConnection**    | Tests the API connection; returns `$true` or `$false`.      |
| **Get-InforcerTenant**         | Retrieves tenant information (optional filter by TenantId; `-Detailed` loads the full record on v1). |
| **Get-InforcerBaseline**       | Retrieves baseline groups and members.                      |
| **Get-InforcerTenantPolicies** | Retrieves policies for a specified tenant.                  |
| **Get-InforcerAlignmentDetails** | Retrieves alignment scores (table or raw format).           |
| **Get-InforcerAuditEvent**     | Retrieves audit events (optional EventType, date range; -EventType has tab completion). |
| **Get-InforcerSupportedEventType** | Returns the canonical list of audit event types accepted by `Get-InforcerAuditEvent -EventType`. Drives the tab completer; cached after first call. |
| **Get-InforcerUser**           | Retrieves users from a tenant (list/search or detail by UserId). |
| **Get-InforcerGroup**          | Retrieves Entra ID groups from a tenant (list/search or detail by GroupId). |
| **Get-InforcerRole**           | Retrieves Entra ID directory role definitions from a tenant. |
| **Get-InforcerSecureScore**    | Retrieves the current and 90-day historic Microsoft Secure Score for a tenant, including per-category scores and actionable control profiles. |
| **Export-InforcerTenantDocumentation** | Generates comprehensive tenant documentation in HTML, Markdown, or Excel format. Pass `-OutputPath` to write files; without it the DocModel is returned and nothing is written. |
| **Compare-InforcerEnvironments** | Compares two tenants' Intune configuration and generates an interactive HTML comparison report. Pass `-OutputPath` to write the file; without it the comparison model is returned and nothing is written. Supports baseline-scoped comparison via `-SourceBaselineId` / `-DestinationBaselineId` with automatic baseline owner resolution. |
| **Get-InforcerAssessment**     | Lists available assessments (CIS, Essential Eight, etc.). |
| **Invoke-InforcerAssessment**  | Runs an assessment against one or more tenants. Supports HTML/CSV export. |
| **Get-InforcerReportType**     | Lists the report catalog from the Reports API. Cached after first call; supports `-Key`, `-Tag`, and `-OutputFormat` filters. |
| **Invoke-InforcerReport**      | Queues a report run, polls until complete, and saves outputs to disk. Use `-NoWait` for async or `-NoSave` to download metadata only. |
| **Get-InforcerReportRun**      | Lists report runs (last 7 days, capped at 500). Use `-Wait` with `-RunId` to bypass the 4-minute list propagation lag. |
| **Save-InforcerReportOutput**  | Downloads a report output to disk using the server's `Content-Disposition` filename. Pipeline-friendly for bulk download. |


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

[MIT](LICENSE) — This module was created by Roy Klooster for the community. It is not owned or officially maintained by inforcer; it is a community project built by a community member to make it easier to work with the inforcer API from PowerShell.

---

