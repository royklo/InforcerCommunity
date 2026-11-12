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

# List tenants (licenses, secure score, baseline flag, tags, alignment)
Get-InforcerTenant

# Tenants are addressed by Microsoft tenant ID (GUID) or name
Get-InforcerTenantPolicies -TenantId '00000000-0000-0000-0000-000000000000'
Get-InforcerTenant | Get-InforcerSecureScore   # pipeline binds MsTenantId; each result carries TenantId

# Alignment score table
Get-InforcerAlignmentDetails
```

`-TenantId` accepts the aliases `ClientTenantId` and `MsTenantId`, so objects from `Get-InforcerTenant` bind through the pipeline in both logins. Results from piped tenants carry a `TenantId` property, and `-OutputType JsonObject` returns one JSON array for all of them.

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

# Generate documentation for a specific baseline with Graph name resolution (see Microsoft Graph below)
Connect-Inforcer -ClientId '<client-id>' -ClientSecret $secret -Region uk -FetchGraphData
Export-InforcerTenantDocumentation -Format Html -TenantId 'Contoso' -Baseline "Production" -FetchGraphData -OutputPath ./docs

# Document several tenants: pass a directory, one file per tenant
Get-InforcerTenant | Export-InforcerTenantDocumentation -Format Html -OutputPath ./docs -Show:$false

# Disconnect when done
Disconnect-Inforcer
```

## Legacy API key login

inforcer's API keys use the **legacy beta API**, which inforcer says is due to be retired. No retirement date has been announced; it only receives bug fixes. `Connect-Inforcer -ApiKey` keeps working and its output is unchanged, but it prints a warning on every login. Switch to client credentials when you can (next section).

## Migrating from API key to client credentials

| What | API key (beta) | Client credentials (v1) |
|------|----------------|--------------------------|
| Login | `Connect-Inforcer -ApiKey $key -Region uk` | `Connect-Inforcer -ClientId $id -ClientSecret $secret -Region uk` |
| Tenant ID | numeric Client Tenant ID, Microsoft tenant ID (GUID) or name | Microsoft tenant ID (GUID) or tenant name. A numeric ID fails with an error that says to use the GUID or name (`InvalidTenantId`; `TenantResolutionFailed` in `Invoke-InforcerReport`). |
| `ClientTenantId` property | present | **absent** (use `MsTenantId`) |
| `Get-InforcerTenant` | rich objects | the same rich objects, without `ClientTenantId` |
| Permissions | key scopes (`Tenants.Read`, ...) | API client permissions plus optional tenant filters, set in the portal |
| Rate limit | 400 calls/hour per key; a throttled (`429`) call fails at once | 400 calls/minute per partner; throttled calls are retried using `Retry-After` (up to 3 times, at most 300 s each). Report-file downloads are not retried on `429`. |
| Output | unchanged | the same property names; v1 responses are mapped to them. v1-only fields are added; fields v1 does not have are missing. |

Steps:

1. Create an API client in the inforcer portal (Configure > REST API) and grant the permissions for the cmdlets you use. Keep the secret in a vault or SecureString; it is shown once.
2. Replace the `Connect-Inforcer -ApiKey` line with the `-ClientId`/`-ClientSecret` form.
3. Replace numeric tenant IDs with the Microsoft tenant ID or name (`Get-InforcerTenant` lists them). Scripts that read `ClientTenantId` should read `MsTenantId`.

The full list of differences per object is in the [API Reference](docs/API-REFERENCE.md#v1-api-client-credentials).

## Security notes

- Requests that carry your API key, client secret or access token never follow a redirect. When the API answers with a redirect, the call fails with a message naming the target, so credentials are never sent to another address.
- Report downloads (`Invoke-InforcerReport`, `Save-InforcerReportOutput`) never overwrite an existing file (a taken name becomes `name (1).ext`) and use a safe file name; on Windows the files are marked as downloaded from the internet.
- Exported files neutralise formulas: Excel documentation writes values that start with `=` as text, and assessment CSV files prefix values that start with `=`, `+`, `-`, `@`, a tab or a carriage return with `'`.

## Microsoft Graph (optional)

`-FetchGraphData` on `Connect-Inforcer`, `Export-InforcerTenantDocumentation` and `Compare-InforcerEnvironments` signs in to Microsoft Graph interactively (module `Microsoft.Graph.Authentication`, not installed automatically) to turn IDs into names. It requests three delegated read scopes, so a consent prompt can appear once:

| Scope | Used for |
|-------|----------|
| `Directory.Read.All` | Group and user names (assignments, Conditional Access), directory roles including custom roles, application names in Conditional Access |
| `Policy.Read.All` | Named locations in Conditional Access |
| `DeviceManagementConfiguration.Read.All` | Assignment filters, scope tags, and compliance rules (Compare) |

A call Graph refuses leaves those IDs as they are, with a warning that names the likely missing scope. The Graph endpoints are listed in the [API Reference](docs/API-REFERENCE.md#microsoft-graph).

## Personal data

Some output contains personal data (names, UPNs, email addresses, IP addresses, sign-in details): user details (`Get-InforcerUser -UserId`, including the phone numbers and email addresses in `-IncludeAuthenticationMethods`), audit events, report outputs, and the files written by `Export-InforcerTenantDocumentation`, `Compare-InforcerEnvironments`, `Invoke-InforcerAssessment`, `Invoke-InforcerReport` and `Save-InforcerReportOutput`. The module caches no user or audit data. It writes files only where you ask: to `-OutputPath`, or for `Invoke-InforcerReport` and `Save-InforcerReportOutput` to the current directory when `-OutputPath` is omitted (`-NoSave` writes nothing). Handle those files as personal data: keep them access-controlled and delete them when no longer needed.

## Cmdlets


| Cmdlet                         | Description                                                 |
| ------------------------------ | ----------------------------------------------------------- |
| **Connect-Inforcer**           | Establishes a secure connection to the inforcer REST API with an API client (`-ClientId`/`-ClientSecret`, v1) or a legacy API key (`-ApiKey`, beta). Supports `-FetchGraphData` to also connect Microsoft Graph. |
| **Disconnect-Inforcer**        | Disconnects and clears the session (including Graph if connected). |
| **Test-InforcerConnection**    | Tests the API connection; returns `$true` or `$false`.      |
| **Get-InforcerTenant**         | Retrieves tenant information (optional filter by TenantId). |
| **Get-InforcerBaseline**       | Retrieves baseline groups and members.                      |
| **Get-InforcerTenantPolicies** | Retrieves policies for a specified tenant.                  |
| **Get-InforcerAlignmentDetails** | Retrieves alignment scores (table or raw format).           |
| **Get-InforcerAuditEvent**     | Retrieves audit events (optional EventType, date range; -EventType has tab completion). |
| **Get-InforcerSupportedEventType** | Returns the canonical list of audit event types accepted by `Get-InforcerAuditEvent -EventType`. Drives the tab completer; cached after first call. |
| **Get-InforcerUser**           | Retrieves users from a tenant (list/search or detail by UserId); `-IncludeAuthenticationMethods` adds their sign-in methods (API client login only). |
| **New-InforcerUser**           | Creates a Microsoft Entra user in a tenant (API client login only). |
| **Set-InforcerUser**           | Updates a user's profile, manager or sign-in, resets their password, removes sign-in methods or resets MFA, or signs them out everywhere; only the fields you pass change (API client login only). |
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
| **Save-InforcerReportOutput**  | Downloads a report output to disk using the server's `Content-Disposition` filename (or `-FileName`); never overwrites an existing file. Pipeline-friendly for bulk download. |


For full parameter details and example output, see **[Cmdlet Reference](docs/CMDLET-REFERENCE.md)**. For detailed API schemas and response structures, see **[API Reference](docs/API-REFERENCE.md)**.

## Settings Catalog data

`Export-InforcerTenantDocumentation` and `Compare-InforcerEnvironments` resolve Intune Settings Catalog settingDefinitionIDs to friendly names using data from the [IntuneSettingsCatalogData](https://github.com/royklo/IntuneSettingsCatalogData) repository. This data (~65 MB) is **automatically downloaded and cached** on first use at `~/.inforcercommunity/data/settings.json` with a 24-hour TTL.

- **No manual setup required** — the module handles download, caching, and freshness checks automatically. After 24 hours it checks the release and downloads only when a newer catalog exists.
- **Validated downloads** — a download replaces the cache only when it is a valid catalog of at most 512 MB; otherwise the cached copy is kept
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

