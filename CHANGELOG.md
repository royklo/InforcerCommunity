# Changelog

All notable changes to this project will be documented in this file.

The format follows [Conventional Commits](https://www.conventionalcommits.org/) and this project adheres to [Semantic Versioning](https://semver.org/). Release notes for each version are also generated from git history by the automation pipeline using the same conventional types (feat, fix, docs, refactor, test, etc.).

## [Unreleased]

### Features

- **New cmdlet: `Compare-InforcerEnvironments`** — compares two tenants' Intune configuration and generates an interactive HTML comparison report with 4 tabs: Comparison (flat table with sortable columns, status filters, category dropdown, advanced filters), Manual Review (50/50 source/destination layout with matching policies aligned side-by-side), Duplicates (settings in 2+ policies with different values), and Deprecated (settings flagged by Microsoft). Animated configuration match score with confetti at 100%.
- **New cmdlet: `Get-InforcerGroup`** — retrieves Entra ID groups from an Inforcer tenant. Supports list with search/pagination (GroupSummary) and detail by name or GUID via `-Group` (Group with members). Parameters: `-TenantId`, `-Group`, `-Search`, `-Filter`, `-MaxResults`, `-OutputType`.
- **New cmdlet: `Get-InforcerRole`** — retrieves Entra ID directory role definitions from an Inforcer tenant. Shows display name, description, and whether each role is built-in, enabled, or privileged. Parameters: `-TenantId`, `-OutputType`.
- **`Connect-Inforcer -PassThru`** — returns the session hashtable to the pipeline for cross-account comparison workflows.
- **Script/rules decoding:** Base64-encoded detection scripts, remediation scripts, and compliance rules (`rulesContent`) are automatically decoded and rendered as collapsible code blocks with syntax highlighting (PowerShell blue, Bash red, JSON indigo) in both Export and Compare HTML reports.
- **Friendly setting names:** Non-Settings-Catalog property names are converted from camelCase to Title Case (e.g., `allowBluetooth` → "Allow Bluetooth") across both Export and Compare reports.
- **Graph compliance rules:** When `-FetchGraphData` is specified, compliance policy detection rules (`rulesContent`) are fetched individually from Graph and discovery scripts are linked to parent compliance policies.
- **GitHub issues link:** Both Export and Compare HTML reports include a footer link to report bugs or missing information.

### Bug Fixes

- **Baseline filter matching:** Alignment API uses friendly names (e.g., "Default User Role Permissions") while tenant policies store internal names (e.g., "DefUserRolePerms"). Filter now checks all name fields (`displayName`, `friendlyName`, `name`, `policyData.displayName`, `policyData.name`) and GUID fields independently. Fixes issue where only 31 of 48 baseline policies matched. ([#15](https://github.com/royklo/InforcerCommunity/issues/15))
- **Baseline filter scope:** Excluded `additionalInSubjectUnaccepted` from baseline policy collection — these are tenant-only policies not in the baseline.
- **Intune assignment filters for All Users/All Devices:** Filter properties (`deviceAndAppManagementAssignmentFilterId`/`Type`) are now checked on both the `target` object and the `assignment` level, fixing resolution when API wrappers place filter data at the assignment level. ([#11](https://github.com/royklo/InforcerCommunity/issues/11))
- **Conditional Access GUID resolution:** Group, role, named location, and application GUIDs in CA policy conditions are now resolved to display names via Microsoft Graph when `-FetchGraphData` is used. ([#11](https://github.com/royklo/InforcerCommunity/issues/11))
- **Settings Catalog deferred loading:** Catalog (~65 MB) is only loaded when policyTypeId 10 (Intune/Defender) policies are present. Baselines without Intune policies skip the load entirely.
- **Error messages:** Improved tenant access error messages with specific guidance for 403 (permission) and 404 (not found) failures.
- **Export tenant name in Graph prompt:** Shows tenant friendly name during Graph sign-in (e.g., "Connecting to Microsoft Graph for Contoso...").

### Improvements

- **Friendly CA property names:** 50+ camelCase property names mapped to human-readable labels (e.g., `includeGroups` → "Include Groups", `builtInControls` → "Built-in Controls").
- **Auth combination labels:** camelCase values like `windowsHelloForBusiness` → "Windows Hello for Business", `password,softwareOath` → "Password + Software OATH Token".
- **ISO 8601 duration conversion:** Values like `PT0S` → "0 (immediate)", `P30D` → "30 days", `PT24H` → "24 hours" across all policy types.
- **Well-known app ID resolution:** 22 pre-mapped Microsoft application IDs (Intune, Graph, Teams, etc.) with Graph fallback for unknown IDs.
- **HTML multi-value display:** Comma-separated values render as vertical lists. Lists with 10+ items show first 10 with a "+ N more" expand button.
- **HTML hide empty fields by default:** Empty fields are hidden on page load (toggle still available in sidebar).
- **HTML search filtering:** Search now hides empty product sections and category headers with no matching policies.
- **HTML description visibility:** Long description fields show ~8 lines before requiring expand (previously ~2 lines).
- **Settings Catalog load performance:** Uses `-AsHashtable` for faster JSON parsing with visible progress message and timing.
- **Code quality:** Extracted shared helpers (`$enrichComplianceData`, `$resolveGuid`, `$getSettingPathHtml`), removed ~90 lines of dead code and duplication across 8 files, consolidated GUID resolution patterns, removed unused CSS classes.

### Tests

- Added `Tests/DocModel.Tests.ps1` with 61 tests covering noise exclusion, deprecated detection, duplicate detection (single-tenant, cross-tenant, duplicate-only exclusion), and setting path building.
- Added `Tests/Renderers.Tests.ps1` with 128 tests covering HTML structure, value display, assignments, table enhancements, filtering/navigation, manual review content, duplicate tab, and deprecated badge rendering.
- Added `Tests/GraphResolution.Tests.ps1` with 8 tests covering assignment filter fallback, CA GUID resolution (groups, roles, locations), multi-value handling, and non-GUID value preservation.
- Added consistency tests for `Get-InforcerGroup` and `Get-InforcerRole`: exported cmdlet count, parameter validation, no-silent-failure, parameter binding, and property alias tests for GroupSummary, Group, and Role object types.
- Updated `Tests/SettingsCatalog.Tests.ps1` for friendly setting names, DefinitionId property, and unknown ID handling.

---

## [0.2.0] - 2026-04-02

### Features

- **New cmdlet: `Export-InforcerTenantDocumentation`** — generates comprehensive, human-readable documentation of an entire M365 tenant's configuration. Supports HTML, Markdown, and Excel output formats. Parameters: `-Format`, `-TenantId`, `-OutputPath`, `-SettingsCatalogPath`, `-FetchGraphData`, `-Baseline`, `-Tag`.
- **Settings Catalog runtime fetch:** The module now automatically downloads and caches the Intune Settings Catalog data (~65 MB) from [IntuneSettingsCatalogData](https://github.com/royklo/IntuneSettingsCatalogData) GitHub Releases. Replaces the bundled static `settings.json`. Cache stored at `~/.inforcercommunity/data/` with 24-hour TTL, atomic writes, single retry, and offline fallback.
- **HTML output:** Modern 2025 admin dashboard design with glassmorphism sidebar, collapsible Product > Category > Policy navigation, tag filter pills (AND/OR), real-time search with text highlighting, dark/light mode toggle (localStorage persistence), hide empty fields toggle, show metadata toggle, back-to-top button, notch-style status bar, collapsible long values. Self-contained with embedded CSS and JavaScript (no CDN dependencies).
- **Excel export (`-Format Excel`):** Replaces CSV. Creates an `.xlsx` workbook with one sheet per product, auto-sized columns, filters, and frozen header row. Requires the `ImportExcel` module.
- **Graph integration (`-FetchGraphData`):** Resolves group ObjectIDs to display names, assignment filter IDs to names, and scope tag IDs to names via Microsoft Graph. Validates Graph tenant matches Inforcer tenant.
- **Baseline and tag filtering:** `-Baseline` filters to policies in a specific baseline via alignment details API. `-Tag` filters by Inforcer tag name (case-insensitive).
- **`Connect-Inforcer` updated:** Added `-FetchGraphData` switch to simultaneously connect to Microsoft Graph alongside Inforcer API.
- **`Disconnect-Inforcer` updated:** Now also disconnects Microsoft Graph session when active.

### New Private Functions

- `Get-InforcerSettingsCatalogPath` — 6-tier cache resolution strategy: explicit path → fresh cache → stale remote check → first-time download → fallback → offline with stale cache.
- `Export-InforcerDocExcel` — Renders DocModel to multi-sheet Excel workbook via ImportExcel.
- `Get-InforcerPolicyDisplayInfo` — maps API internal names to Microsoft admin portal categories (Entra 21 settings, SharePoint 11, M365 Admin Center 3).
- `Resolve-InforcerAssignments` — translates assignment `@odata.type` to friendly names (All Devices, All Users, Group Include/Exclude).
- `Connect-InforcerGraph` — auto-installs `Microsoft.Graph.Authentication`, handles Graph sign-in with tenant targeting.
- `Invoke-InforcerGraphRequest` — wraps `Invoke-MgGraphRequest` with retry logic and automatic paging.

### Changes

- `Import-InforcerSettingsCatalog` now delegates path resolution to `Get-InforcerSettingsCatalogPath` instead of looking for bundled/sibling files.
- `Export-InforcerTenantDocumentation` removed inline discovery chain (bundled → sibling → warn). `-SettingsCatalogPath` parameter now documents the auto-download behavior.
- `Export-InforcerTenantDocumentation` `-Format` replaced `Csv` with `Excel`. Removed `ConvertTo-InforcerDocCsv` renderer.
- Removed `module/data/.gitkeep` — settings catalog data is no longer bundled with the module.

### Improvements

- Object arrays (apps, approvedKeyboards) now display item count plus individual items instead of comma-separated empty strings.
- Categories sorted alphabetically and grouped by platform (e.g., Windows > subcategories).
- "All /" prefix stripped from category display names.
- Policy tags shown inline as blue-bordered badges; "None" shown for policies without assignments.
- Progress reporting during export; auto-opens HTML in browser after export.
- Returns `FileInfo` objects for exported files.

## [0.1.0] - 2026-03-30

### Features

- **New cmdlet: `Get-InforcerUser`** — list/search users or get full user detail by ID. Two ParameterSets (List, ById), auto-pagination via continuationToken, server-side `-Search`, `-MaxResults` cap, dual output types (UserSummary, User). Streams results to pipeline immediately.
- **New cmdlet: `Get-InforcerAlignmentDetails`** — replaces `Get-InforcerAlignmentScore`. Supports `-BaselineId` for per-policy alignment detail (matched, deviated, missing). Table and Raw formats. Baseline owner detection auto-includes aligned tenants.
- **New cmdlet: `Get-InforcerSupportedEventType`** — returns supported audit event types (moved from private helper to public cmdlet).
- **Tenant name resolution** — `-TenantId` now accepts tenant name (matched on `tenantFriendlyName` or `tenantDnsName`) in addition to numeric ID and GUID. Works across all cmdlets.
- **Pipeline support** — all cmdlets with `-TenantId` now support `ValueFromPipelineByPropertyName` with `[Alias('ClientTenantId')]` for proper piping (e.g. `Get-InforcerTenant | Get-InforcerUser`).

### Performance

- Switched `Invoke-InforcerApiRequest` from `Invoke-WebRequest` + `ConvertFrom-Json` to `Invoke-RestMethod` for faster API calls across all cmdlets.
- `Get-InforcerTenant` fetches tenant list once and reuses for both name/GUID resolution and output (no duplicate API call).
- `Get-InforcerTenant` JsonObject path filters PSObjects before JSON conversion (no serialize/deserialize round-trip).
- `Resolve-InforcerTenantId` uses `TryParse` instead of regex for numeric and GUID detection.
- All cmdlets use `$null =` instead of `| Out-Null`; removed `ForEach-Object { $_ }` output no-ops.

### Fixes

- `Get-InforcerUser` ById path only emits `UserNotFound` on actual 404 (not on 401/403/500).
- `Get-InforcerUser` JsonObject output no longer includes duplicate PascalCase alias fields.
- `Invoke-InforcerApiRequest` validates response type — non-JSON responses (e.g. HTML from misconfigured BaseUrl) get a clear `NonJsonResponse` error instead of crashing.
- `Invoke-InforcerApiRequest` error responses include HTTP status code in `ErrorId` (e.g. `ApiRequestFailed_404`) for programmatic handling.
- Rate limit detection (HTTP 429 and quota/throttle messages) with friendly error.
- API key redaction uses compiled regex for better performance.

### Documentation

- Added Get-InforcerUser to README, CMDLET-REFERENCE, API-REFERENCE (endpoints + UserSummary/User/UserLicense schemas), and module directory tree.
- Updated all TenantId parameter descriptions to reflect tenant name support.
- Format.ps1xml ListControl views for all object types (Tenant, Baseline, Policy, AlignmentScore, AlignmentDetailPolicy, AuditEvent, UserSummary, User).

### Tests

- 54 consistency tests (was 17): covers all cmdlets, private helpers (Resolve-InforcerTenantId, Add-InforcerPropertyAliases, Filter-InforcerResponse, ConvertTo-InforcerArray), both ParameterSets for Get-InforcerUser, no-silent-failure, JsonObject output.

## [0.0.3] - 2026-03-06

### Features

- PowerShell Gallery–ready metadata.
- README Quick start: example for showing policy changes per tenant.


### Documentation

- README, CONTRIBUTING, and LICENSE wording aligned; CONTRIBUTING.

### Refactoring

- Clearer error messages when API returns forbidden or no data; safer examples in docs.

### Tests

- Help coverage check (Synopsis and Example per cmdlet); parameter binding tests.

## [0.0.2] - 2026-03-06

### Improvements

- Various documentation updates, and test improvements.
- Consistency and no-silent-failure behaviour for all Get-* cmdlets.
- Clearer API error handling and alignment score filtering.

## [0.0.1] - 2026-03-05

### Features

- Initial release of the InforcerCommunity PowerShell module.
- Cmdlets: Connect-Inforcer, Disconnect-Inforcer, Test-InforcerConnection, Get-InforcerTenant, Get-InforcerBaseline, Get-InforcerTenantPolicies, Get-InforcerAlignmentScore, Get-InforcerAuditEvent.
- Tab completion for audit event types (-EventType on Get-InforcerAuditEvent).
- Region support (uk, eu, us, anz) and custom BaseUrl.
- Output types: PowerShellObject and JsonObject (depth 100).

