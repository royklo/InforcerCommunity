# Phase 1: Data Pipeline and Normalization - Context

**Gathered:** 2026-04-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Build the data collection, Settings Catalog resolution, and normalization pipeline that produces a format-agnostic `$DocModel` from live Inforcer API data. All renderers (Phase 2) consume only this model — no API calls in renderers.

</domain>

<decisions>
## Implementation Decisions

### Settings.json Path Strategy
- **D-01:** Bundle a copy of settings.json inside the module's `data/` folder. This ships with the module — no external dependency.
- **D-02:** Future milestone: automate nightly refresh from IntuneSettingsCatalogViewer repo so the bundled copy stays current. Not in scope for v1.
- **D-03:** Cache loaded settings.json in `$script:InforcerSettingsCatalog` (same pattern as `$script:InforcerSession`). Load once per session, not per invocation.

### Policy Categorization
- **D-04:** API already provides `product`, `primaryGroup`, and `secondaryGroup` fields on every policy. No mapping table needed — use these directly for the 3-level hierarchy.
- **D-05:** Products observed in real data: Entra, Intune, Defender, Exchange, SharePoint, Teams, M365 Admin Center, Purview. Group by `product` → `primaryGroup` as two-level TOC.

### Policy Data Structure Variance
- **D-06:** At least 4 distinct policyData shapes exist based on policyTypeId:
  - **Settings Catalog (type 10):** `settings[]` array with `settingInstance` objects. 4 `@odata.type` variants: ChoiceSettingInstance (678 occurrences), SimpleSettingCollectionInstance (38), SimpleSettingInstance (22), GroupSettingCollectionInstance (7).
  - **Conditional Access (type 1):** Flat JSON with `conditions`, `grantControls`, `sessionControls`.
  - **Compliance (type 3):** Flat key-value pairs like `passwordRequired: false`, `bitLockerEnabled: true`.
  - **Entra/SharePoint settings (type 12, 14):** Nested `data` object with named policy → key-value pairs.
  - **Exchange mail flow (type 25):** Very large flat object with hundreds of rule properties.
  - **Other types:** Various flat structures.
- **D-07:** The normalization layer must handle each shape and flatten to a consistent Name/Value pair model. For Settings Catalog, resolve via settings.json. For all others, use the property name as the setting name and the property value as the value.

### Data Collection Script
- **D-08:** Script already created at `scripts/Collect-InforcerData.ps1`. Captures `tenants.json`, `baselines.json`, `tenant-policies.json` to `scripts/sample-data/`.
- **D-09:** Sample data collected from tenant 142 ("inforcer Blueprint Library") — 194 policies across 8 products.

### DocModel Shape
- **D-10:** Nested tree structure matching the output hierarchy:
  ```
  $DocModel = @{
      TenantName = "..."
      TenantId = "..."
      GeneratedAt = [datetime]
      Products = @{
          "Entra" = @{
              Categories = @{
                  "Conditional Access / Policies" = @(
                      @{
                          Basics = @{ Name; Description; Platform; Created; Modified; ScopeTags; ... }
                          Settings = @( @{ Name; Value; Indent; IsConfigured } )
                          Assignments = @( @{ Group; Filter; FilterMode; Type } )
                      }
                  )
              }
          }
      }
  }
  ```
- **D-11:** Category key is `"primaryGroup / secondaryGroup"` (combined). When secondaryGroup equals primaryGroup or is "All", use just primaryGroup.
- **D-12:** Each setting row has: `Name` (friendly), `Value` (friendly), `Indent` (0 for top-level, 1 for child), `IsConfigured` (whether explicitly set vs default).

### Null/Missing Data Handling
- **D-13:** displayName fallback chain: `displayName → friendlyName → name → policyData.name → policyData.displayName → "Policy {id}"`. Real data shows many `null` displayName values but `friendlyName` is usually populated.
- **D-14:** Platform field is `null` for ~96% of policies. Show as empty, don't fabricate.
- **D-15:** Tags array may be empty or null. Normalize to empty string when missing.

### Claude's Discretion
- Internal data structures and helper function signatures
- Performance optimization strategies for settings.json parsing
- Error handling granularity within the normalization pipeline

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Module Patterns
- `module/Public/Get-InforcerTenantPolicies.ps1` — Shows existing cmdlet pattern, EnrichPolicyObject helper, parameter conventions
- `module/Private/Invoke-InforcerApiRequest.ps1` — API request pattern, OutputType handling
- `module/Private/Add-InforcerPropertyAliases.ps1` — Property aliasing pattern to follow
- `module/Private/Test-InforcerSession.ps1` — Session check pattern

### Data Sources
- `scripts/sample-data/tenant-policies.json` — 194 real policies with all policyData shapes (1.4MB)
- `scripts/sample-data/tenants.json` — Tenant info structure
- `scripts/sample-data/baselines.json` — Baseline structure
- `../IntuneSettingsCatalogViewer/data/settings.json` — Settings Catalog lookup (62.5MB, source for bundled copy)

### Reference Implementation
- `/Users/roy/Downloads/inforcer Blueprint Library-2026-03-26.md` — Prior documentation output showing Basics/Settings/Assignments format per policy

### Project Planning
- `.planning/PROJECT.md` — Core value and constraints
- `.planning/REQUIREMENTS.md` — DATA-*, SCAT-*, NORM-* requirements
- `.planning/research/ARCHITECTURE.md` — Component architecture (Collect → Normalize → Render → Emit)
- `.planning/research/PITFALLS.md` — Performance and correctness pitfalls

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `$script:InforcerSession` pattern — Reuse for `$script:InforcerSettingsCatalog` caching
- `EnrichPolicyObject` in Get-InforcerTenantPolicies.ps1 — Pattern for adding properties to PSObjects
- `Add-InforcerPropertyAliases` — May need extending for documentation-specific aliases
- `Resolve-InforcerTenantId` — Already handles numeric/GUID/name; reuse for -TenantId parameter

### Established Patterns
- All Private helpers go in `module/Private/`
- All JSON uses `-Depth 100`
- Error handling: Write-Error with ErrorId and Category
- Session state: `$script:` scoped variables in module

### Integration Points
- New private functions will be dot-sourced by InforcerCommunity.psm1
- Settings.json bundled copy goes in `module/data/settings.json`
- Data collection script already in `scripts/Collect-InforcerData.ps1`

</code_context>

<specifics>
## Specific Ideas

- User wants the settings.json to eventually be auto-updated nightly (clone from IntuneSettingsCatalogViewer). For v1: bundle a static copy.
- Reference document shows Basics/Settings/Assignments as the per-policy structure — preserve this in the DocModel.
- Real API data has `product/primaryGroup/secondaryGroup` already classified — no custom mapping needed.
- 4 settingInstance types to handle: ChoiceSettingInstance (dominant at 678), SimpleSettingInstance (22), SimpleSettingCollectionInstance (38), GroupSettingCollectionInstance (7).

</specifics>

<deferred>
## Deferred Ideas

- Nightly automation to refresh settings.json from IntuneSettingsCatalogViewer repo
- Category breadcrumbs using categories.json from IntuneSettingsCatalogViewer

None — discussion stayed within phase scope

</deferred>

---

*Phase: 01-data-pipeline-and-normalization*
*Context gathered: 2026-04-01*
