# Changelog

All notable changes to this project will be documented in this file.

The format follows [Conventional Commits](https://www.conventionalcommits.org/) and this project adheres to [Semantic Versioning](https://semver.org/). Release notes for each version are also generated from git history by the automation pipeline using the same conventional types (feat, fix, docs, refactor, test, etc.).

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

