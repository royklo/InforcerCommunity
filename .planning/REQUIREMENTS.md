# Requirements: Inforcer Tenant Documentation Cmdlet

**Defined:** 2026-04-01
**Core Value:** IT admins can generate a complete, readable snapshot of their tenant's policy configuration across all M365 products in one command

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Data Collection

- [x] **DATA-01**: Cmdlet collects tenant info via Get-InforcerTenant -OutputType JsonObject
- [x] **DATA-02**: Cmdlet collects baseline data via Get-InforcerBaseline -OutputType JsonObject
- [x] **DATA-03**: Cmdlet collects all policies via Get-InforcerTenantPolicies -OutputType JsonObject
- [x] **DATA-04**: Data collection script provided for development/testing that captures raw JSON from all 3 cmdlets

### Settings Catalog Resolution

- [x] **SCAT-01**: Settings Catalog settingDefinitionIDs are resolved to friendly display names using settings.json
- [x] **SCAT-02**: Choice option values are resolved to friendly labels (e.g., "Require multifactor authentication" not raw enum)
- [x] **SCAT-03**: Settings hierarchy is preserved (parent/child relationships shown via indentation)
- [x] **SCAT-04**: Unknown/missing settingDefinitionIDs fall back to raw ID with warning, no error-halt
- [x] **SCAT-05**: settings.json is loaded once and cached in $script: scope for performance (62.5MB file)
- [x] **SCAT-06**: All 5 settingInstance @odata.type variants handled (Choice, Simple, SimpleCollection, ChoiceCollection, GroupSettingCollection)

### Data Normalization

- [x] **NORM-01**: Policies are grouped by M365 product area (Intune, Conditional Access, etc.) using API product/category fields
- [x] **NORM-02**: Two-level hierarchy: Product → Category → Policies
- [x] **NORM-03**: Per-policy data normalized into sections: Basics, Settings, Assignments
- [x] **NORM-04**: Basics section includes: Name, Description, Profile type, Platform, Created/Modified dates, Scope tags
- [x] **NORM-05**: Null/missing displayName handled via fallback chain (displayName → name → friendlyName → "Policy {id}")
- [x] **NORM-06**: Normalized data model ($DocModel) is format-agnostic — renderers receive only the model, no API calls

### HTML Output

- [x] **HTML-01**: Self-contained single HTML file with embedded CSS (no CDN dependencies, no external files)
- [x] **HTML-02**: Collapsible table of contents collapsed by default, showing products and subcategories
- [x] **HTML-03**: Per-policy sections with Basics/Settings/Assignments tables
- [x] **HTML-04**: Settings displayed as clear Name/Value pairs with hierarchical indentation for child settings
- [x] **HTML-05**: Collapsible policy sections using HTML5 details/summary elements
- [x] **HTML-06**: Modern visual styling (clean typography, alternating row colors, visual hierarchy)
- [x] **HTML-07**: Generation timestamp and tenant name in header/footer
- [x] **HTML-08**: Dark/light mode support via CSS prefers-color-scheme
- [x] **HTML-09**: Per-policy setting count badge in collapsed header
- [x] **HTML-10**: HTML generation uses StringBuilder for performance (not string concatenation)

### Markdown Output

- [x] **MD-01**: Structured Markdown with table of contents linking to product/category/policy sections
- [x] **MD-02**: Per-policy sections with Basics/Settings/Assignments as Markdown tables
- [x] **MD-03**: Settings values with pipe characters properly escaped for Markdown table compatibility
- [x] **MD-04**: Generation timestamp and tenant name in document header

### JSON Output

- [x] **JSON-01**: Structured JSON output with full depth (depth 100 per module convention)
- [x] **JSON-02**: Organized by product → category → policy → sections (Basics, Settings, Assignments)

### CSV Output

- [x] **CSV-01**: Flattened rows with context columns: Product, Category, PolicyName, SettingName, Value
- [x] **CSV-02**: One row per setting value for Excel compatibility

### Module Integration

- [x] **MOD-01**: Export-InforcerDocumentation cmdlet follows module conventions (parameter order, session auth, error handling)
- [x] **MOD-02**: Cmdlet accepts -TenantId parameter (numeric, GUID, or name) consistent with other cmdlets
- [x] **MOD-03**: Cmdlet accepts -Format parameter supporting: Html, Markdown, Json, Csv (multiple allowed)
- [x] **MOD-04**: Cmdlet accepts -OutputPath parameter for file destination
- [x] **MOD-05**: Cmdlet accepts -SettingsCatalogPath parameter to specify settings.json location (with auto-discover default)
- [x] **MOD-06**: Module manifest (.psd1) updated with new cmdlet export
- [ ] **MOD-07**: Consistency tests updated for new cmdlet
- [x] **MOD-08**: Cmdlet help documentation with examples

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Enhanced Output

- **DOCX-01**: DOCX output format (requires external library evaluation)
- **PDF-01**: PDF output via headless browser conversion
- **TAG-01**: Tag filtering in HTML output via JavaScript

### Enhanced Data

- **GRP-01**: Group name resolution via -GroupMap parameter (pre-built hashtable)
- **BREAD-01**: Category breadcrumbs for Settings Catalog ("Windows > Security > BitLocker")
- **GRAPH-01**: Graph API reference badges per category

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| DOCX output | Requires external library (PSWriteOffice) or fragile Open XML generator — deferred to v2 |
| PDF output | Depends on Chrome/Edge headless — unreliable in CI environments |
| Tenant diff/comparison | Separate feature/cmdlet — not documentation generation |
| Scheduled automation | Users wrap cmdlet in their own scheduling |
| Real-time Graph API calls for catalog | Latency, auth complexity, rate limiting — use local settings.json |
| Group name resolution via Graph | Requires second auth context beyond Inforcer session |
| YAML output | Not requested; JSON covers structured backup use case |
| Interactive web UI | Out of scope for a PowerShell module |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| DATA-01 | Phase 1 | Complete |
| DATA-02 | Phase 1 | Complete |
| DATA-03 | Phase 1 | Complete |
| DATA-04 | Phase 1 | Complete |
| SCAT-01 | Phase 1 | Complete |
| SCAT-02 | Phase 1 | Complete |
| SCAT-03 | Phase 1 | Complete |
| SCAT-04 | Phase 1 | Complete |
| SCAT-05 | Phase 1 | Complete |
| SCAT-06 | Phase 1 | Complete |
| NORM-01 | Phase 1 | Complete |
| NORM-02 | Phase 1 | Complete |
| NORM-03 | Phase 1 | Complete |
| NORM-04 | Phase 1 | Complete |
| NORM-05 | Phase 1 | Complete |
| NORM-06 | Phase 1 | Complete |
| HTML-01 | Phase 2 | Complete |
| HTML-02 | Phase 2 | Complete |
| HTML-03 | Phase 2 | Complete |
| HTML-04 | Phase 2 | Complete |
| HTML-05 | Phase 2 | Complete |
| HTML-06 | Phase 2 | Complete |
| HTML-07 | Phase 2 | Complete |
| HTML-08 | Phase 2 | Complete |
| HTML-09 | Phase 2 | Complete |
| HTML-10 | Phase 2 | Complete |
| MD-01 | Phase 2 | Complete |
| MD-02 | Phase 2 | Complete |
| MD-03 | Phase 2 | Complete |
| MD-04 | Phase 2 | Complete |
| JSON-01 | Phase 2 | Complete |
| JSON-02 | Phase 2 | Complete |
| CSV-01 | Phase 2 | Complete |
| CSV-02 | Phase 2 | Complete |
| MOD-01 | Phase 3 | Complete |
| MOD-02 | Phase 3 | Complete |
| MOD-03 | Phase 3 | Complete |
| MOD-04 | Phase 3 | Complete |
| MOD-05 | Phase 3 | Complete |
| MOD-06 | Phase 3 | Complete |
| MOD-07 | Phase 3 | Pending |
| MOD-08 | Phase 3 | Complete |

**Coverage:**
- v1 requirements: 40 total
- Mapped to phases: 40
- Unmapped: 0

---
*Requirements defined: 2026-04-01*
*Last updated: 2026-04-01 after roadmap creation*
