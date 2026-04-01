# Roadmap: Export-InforcerDocumentation

## Overview

Three phases deliver a collect-normalize-render pipeline. Phase 1 builds the private data infrastructure — data collection from existing cmdlets, Settings Catalog resolution, and format-agnostic normalization into a $DocModel. Phase 2 consumes that model to produce all four output formats (HTML, Markdown, JSON, CSV) as pure renderer functions. Phase 3 wires everything together via the public cmdlet, updates the module manifest, and validates consistency-contract compliance.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Data Pipeline and Normalization** - Collect raw API data, resolve Settings Catalog IDs to friendly names, and build a validated format-agnostic $DocModel
- [ ] **Phase 2: Output Format Renderers** - Build all four pure renderer functions (HTML, Markdown, JSON, CSV) that consume $DocModel and produce output
- [ ] **Phase 3: Public Cmdlet and Module Integration** - Wire the pipeline via Export-InforcerDocumentation, update the module manifest, add tests, and write help docs

## Phase Details

### Phase 1: Data Pipeline and Normalization
**Goal**: A validated, format-agnostic $DocModel is produced from any connected tenant, with all Settings Catalog IDs resolved to friendly names and policies grouped by product/category
**Depends on**: Nothing (first phase)
**Requirements**: DATA-01, DATA-02, DATA-03, DATA-04, SCAT-01, SCAT-02, SCAT-03, SCAT-04, SCAT-05, SCAT-06, NORM-01, NORM-02, NORM-03, NORM-04, NORM-05, NORM-06
**Success Criteria** (what must be TRUE):
  1. Running the data collection script produces a raw JSON bundle from all 3 existing cmdlets without errors
  2. A Settings Catalog policy's settingDefinitionIDs are resolved to their human-readable display names, including choice option labels (e.g., "Require multifactor authentication")
  3. An unknown settingDefinitionID produces a warning but does not halt execution — the raw ID appears in the output
  4. The settings.json file (62.5 MB) is loaded only once per session; a second invocation does not reload it
  5. Policies in $DocModel are organized as Product -> Category -> Policies, and each policy has Basics, Settings, and Assignments sections populated
**Plans**: TBD

### Phase 2: Output Format Renderers
**Goal**: All four output formats are produced as pure functions that accept $DocModel and return formatted output, with no API calls or file I/O inside the renderers
**Depends on**: Phase 1
**Requirements**: HTML-01, HTML-02, HTML-03, HTML-04, HTML-05, HTML-06, HTML-07, HTML-08, HTML-09, HTML-10, MD-01, MD-02, MD-03, MD-04, JSON-01, JSON-02, CSV-01, CSV-02
**Success Criteria** (what must be TRUE):
  1. The HTML output is a single self-contained file that opens in a browser with no network requests, has a collapsible TOC collapsed by default, and respects the OS dark/light mode preference
  2. Each policy in the HTML output shows a setting count badge in its collapsed header and displays Basics/Settings/Assignments tables when expanded
  3. The Markdown output has an anchor TOC, per-policy tables with pipe characters properly escaped, and a generation timestamp header
  4. The JSON output is structured by product -> category -> policy -> sections at full depth (depth 100) with no truncated arrays
  5. The CSV output produces one row per setting value with Product, Category, PolicyName, SettingName, and Value columns — importable directly into Excel
**Plans**: TBD
**UI hint**: yes

### Phase 3: Public Cmdlet and Module Integration
**Goal**: Export-InforcerDocumentation is a public cmdlet that passes all consistency tests, accepts all required parameters, and ships with help documentation and an updated module manifest
**Depends on**: Phase 2
**Requirements**: MOD-01, MOD-02, MOD-03, MOD-04, MOD-05, MOD-06, MOD-07, MOD-08
**Success Criteria** (what must be TRUE):
  1. Running Export-InforcerDocumentation -TenantId <id> -Format Html,Markdown,Json,Csv -OutputPath <dir> produces four output files without errors against a connected session
  2. The cmdlet follows the module parameter order convention (Format -> TenantId -> Tag -> OutputType) and passes Invoke-Pester ./Tests/Consistency.Tests.ps1 with no failures
  3. The -SettingsCatalogPath parameter auto-discovers the sibling IntuneSettingsCatalogViewer repo when not specified; when the file is absent, the cmdlet degrades gracefully rather than throwing
  4. The module manifest (.psd1) exports Export-InforcerDocumentation and Get-Module InforcerCommunity lists it in ExportedCommands
**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Data Pipeline and Normalization | 0/TBD | Not started | - |
| 2. Output Format Renderers | 0/TBD | Not started | - |
| 3. Public Cmdlet and Module Integration | 0/TBD | Not started | - |
