---
phase: 01-data-pipeline-and-normalization
plan: 02
subsystem: api
tags: [powershell, docmodel, normalization, pester, pipeline, settings-catalog]

# Dependency graph
requires:
  - "01-01: ConvertTo-InforcerSettingRows, ConvertTo-FlatSettingRows, Import-InforcerSettingsCatalog"
  - "Existing cmdlets: Get-InforcerTenant, Get-InforcerBaseline, Get-InforcerTenantPolicies"
provides:
  - "Get-InforcerDocData: collects raw data from 3 existing cmdlets into a hashtable bundle"
  - "ConvertTo-InforcerDocModel: transforms raw bundle into Product->Category->Policy DocModel"
  - "Get-InforcerCategoryKey: primaryGroup/secondaryGroup deduplication helper"
  - "Get-InforcerPolicyName: D-13 fallback chain for policy display name resolution"
affects:
  - "02-html-renderer"
  - "02-markdown-renderer"
  - "02-json-csv-renderer"
  - "03-export-cmdlet"

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "[ordered]@{} for Products and Categories to ensure deterministic rendering order"
    - "InModuleScope BeforeAll pattern: re-evaluate paths inside BeforeAll (discovery-time $script: vars not accessible in run phase)"
    - "TDD with Pester 5.x: RED commit (failing tests) then GREEN commit (implementation)"
    - "policyTypeId routing: 10 -> ConvertTo-InforcerSettingRows, all others -> ConvertTo-FlatSettingRows"

key-files:
  created:
    - module/Private/Get-InforcerDocData.ps1
    - module/Private/ConvertTo-InforcerDocModel.ps1
    - Tests/DocModel.Tests.ps1
  modified: []

key-decisions:
  - "BeforeAll scope: Pester 5 discovery-time $script: variables are not accessible inside BeforeAll run phase -- re-evaluate paths locally in BeforeAll"
  - "DocModel uses [ordered]@{} for Products and Categories for deterministic policy ordering (per Pitfall 4)"
  - "PolicyName fallback chain: displayName -> friendlyName -> name -> policyData.name -> policyData.displayName -> Policy {id} (per D-13)"
  - "Category key dedup: secondaryGroup == primaryGroup OR == 'All' OR is empty -> use primaryGroup only (per D-11)"
  - "Assignments normalized from policyData.assignments first, falling back to policy.assignments (different API shapes)"

patterns-established:
  - "DocData bundle shape: Tenant, Baselines, Policies, TenantId, CollectedAt hashtable"
  - "DocModel shape: TenantName, TenantId, GeneratedAt, BaselineName, Products (ordered) tree"
  - "Test pattern for large data: load from file paths inside InModuleScope to avoid PSCustomObject serialization issues across InModuleScope boundaries"

requirements-completed: [DATA-01, DATA-02, DATA-03, DATA-04, NORM-01, NORM-02, NORM-03, NORM-04, NORM-05, NORM-06]

# Metrics
duration: 9min
completed: 2026-04-01
---

# Phase 01 Plan 02: DocModel Data Pipeline and Normalization Summary

**Get-InforcerDocData collects raw data from 3 existing Inforcer cmdlets into a bundle; ConvertTo-InforcerDocModel transforms the bundle into a format-agnostic Product->Category->Policy DocModel with Basics/Settings/Assignments sections, PolicyName fallback chain (D-13), and Settings Catalog resolution routing (policyTypeId 10 vs flat enumeration)**

## Performance

- **Duration:** 9 min
- **Started:** 2026-04-01T15:29:19Z
- **Completed:** 2026-04-01T15:38:30Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- `Get-InforcerDocData` calls `Get-InforcerTenant`, `Get-InforcerBaseline`, and `Get-InforcerTenantPolicies` with `-OutputType JsonObject`, deserializes with `ConvertFrom-Json -Depth 100`, loads the Settings Catalog via `Import-InforcerSettingsCatalog`, and returns a raw `@{ Tenant, Baselines, Policies, TenantId, CollectedAt }` bundle
- `ConvertTo-InforcerDocModel` normalizes 194 policies into `Products (ordered) -> Categories (ordered) -> @(policies)` hierarchy with no API calls
- `Get-InforcerCategoryKey` deduplicates `primaryGroup/secondaryGroup` when equal or secondaryGroup is "All"
- `Get-InforcerPolicyName` implements the full D-13 fallback chain; 0 policies with null name across all 194 sample data entries
- policyTypeId 10 (Settings Catalog) policies route to `ConvertTo-InforcerSettingRows` for friendly name resolution; all others route to `ConvertTo-FlatSettingRows` for flat property enumeration
- All 8 products (Entra, Intune, Defender, Exchange, SharePoint, Teams, M365 Admin Center, Purview) populated from sample data
- 30 Pester 5.x tests: 30 passed, 0 failed, 0 skipped (including integration tests against real 194-policy sample data)
- Plan 01 regression check: SettingsCatalog.Tests.ps1 still 24 passed, 0 failed

## Task Commits

1. **Task 1: Get-InforcerDocData** - `7888fdf` (feat)
2. **Task 2 RED: Failing DocModel tests** - `3db0cea` (test)
3. **Task 2 GREEN: ConvertTo-InforcerDocModel + fixed tests** - `304c67b` (feat)

## Files Created/Modified

- `module/Private/Get-InforcerDocData.ps1` - Stage 1 collection: 3 cmdlets -> raw bundle with session guard and TenantId resolution
- `module/Private/ConvertTo-InforcerDocModel.ps1` - Stage 2 normalization: raw bundle -> DocModel (contains Get-InforcerCategoryKey, Get-InforcerPolicyName, ConvertTo-InforcerDocModel)
- `Tests/DocModel.Tests.ps1` - 30 Pester 5.x tests covering all DocModel behaviors

## Decisions Made

- `[ordered]@{}` for Products and Categories ensures deterministic section ordering in HTML/MD rendering (renderers in Phase 2 iterate these in insertion order)
- PolicyName fallback chain (D-13): `displayName -> friendlyName -> name -> policyData.name -> policyData.displayName -> "Policy {id}"` — verified against 194 policies, 0 null names
- Category key dedup (D-11): `secondaryGroup == primaryGroup OR "All" OR empty` collapses to just `primaryGroup`; otherwise `"primaryGroup / secondaryGroup"`
- Assignments: normalized from `policyData.assignments` if present, else `policy.assignments` (Microsoft Graph API uses different shapes for different policy types)
- `Platform` defaults to empty string when null (~96% of policies per D-14); `ScopeTags` defaults to empty string when missing (D-15)

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Pester 5 BeforeAll does not share $script: variables set at discovery time**

- **Found during:** Task 2 (test execution)
- **Issue:** `$script:IntegrationDataAvailable` set outside `BeforeAll` at file-scope (discovery phase) is not accessible inside `BeforeAll` (run phase) in Pester 5. The `if ($script:IntegrationDataAvailable)` guard inside `BeforeAll` always evaluated to empty/null, so `$script:DocModel` was never set. 16 integration tests appeared to "pass" trivially (iterating empty collections), but this was masking the actual failure.
- **Fix:** Re-evaluate file existence checks directly inside `BeforeAll` using local variables. The outer `$script:IntegrationDataAvailable` is still correct for `-Skip:` predicates on `Describe` blocks (evaluated at discovery time).
- **Files modified:** Tests/DocModel.Tests.ps1
- **Committed in:** 304c67b

This is the same pattern identified in the 01-01 SUMMARY for the integration test path evaluation issue.

## Known Stubs

None — all DocModel fields are wired to real data. `Platform` and `ProfileType` empty strings are intentional (per D-14, inforcerPolicyTypeName not present in sample data API responses).

## Next Phase Readiness

- DocModel is the single data contract for Phase 2 renderers
- `Products` is `[ordered]@{}` — iteration order matches insertion order (policy order from API)
- `Settings` rows have `Name`, `Value`, `Indent`, `IsConfigured` matching the 4-property contract from Plan 01
- `Assignments` rows have `Group`, `Filter`, `FilterMode`, `Type` properties for rendering

---
*Phase: 01-data-pipeline-and-normalization*
*Completed: 2026-04-01*
