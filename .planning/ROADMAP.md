# Roadmap: Compare-InforcerEnvironments Upgrade

## Overview

Upgrading `Compare-InforcerEnvironments` to reach IntuneLens feature parity by porting advanced comparison engine logic into `Compare-InforcerDocModels.ps1` and rendering enhancements into `ConvertTo-InforcerComparisonHtml.ps1`. Work proceeds backend-first (matching, noise, deprecated, duplicates) then frontend (value display, assignments, manual review, table, filtering, duplicate tab). Every phase modifies existing files on `release/next`.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Matching Foundation** - Stable cross-tenant setting matching and path building
- [ ] **Phase 2: Noise Exclusion** - Filter odata metadata, GUIDs, bundleIds, and array counts from comparison output
- [ ] **Phase 3: Deprecated Settings** - Scan and flag deprecated settings with visual indicators
- [ ] **Phase 4: Duplicate Detection Engine** - Cross-policy and cross-tenant duplicate detection with risk assessment
- [ ] **Phase 5: Value Display** - Expand/collapse long values, copy-to-clipboard, bold red conflicts
- [ ] **Phase 6: Assignments Display** - Color-coded include/exclude/All Devices assignments with filter info
- [ ] **Phase 7: Manual Review Rendering** - Syntax highlighting, compliance rules table, duplicate display, side badges
- [ ] **Phase 8: Table Enhancements** - Resizable columns, amber duplicate badge, two-line setting name cell
- [ ] **Phase 9: Filtering and Navigation** - Category dropdown, filter summary, multi-select pills, full-field search
- [ ] **Phase 10: Duplicate Settings Tab** - Dedicated tab with cross-tenant duplicate analysis and search

## Phase Details

### Phase 1: Matching Foundation
**Goal**: The comparison engine reliably identifies the same setting across tenants regardless of policy format
**Depends on**: Nothing (first phase)
**Requirements**: ENG-05, ENG-06
**Success Criteria** (what must be TRUE):
  1. Settings with a settingDefinitionId match on that ID when comparing two tenants, not on display name or position
  2. Legacy profiles without settingDefinitionIds fall back to settingPath for cross-tenant matching without error
  3. Settings with nested/indented structure show a readable "Parent > Child" path label in comparison output
  4. No setting is unmatched solely due to missing definitionId when a valid path fallback exists
**Plans:** 1 plan
Plans:
- [x] 01-01-PLAN.md — definitionId-first lookup keying with ENG-05/ENG-06 tests

### Phase 2: Noise Exclusion
**Goal**: Comparison results show only meaningful differences — odata noise, raw GUIDs, array counts, and tenant-specific identifiers are suppressed
**Depends on**: Phase 1
**Requirements**: ENG-01
**Success Criteria** (what must be TRUE):
  1. odata type/context metadata rows do not appear in comparison output
  2. Standalone GUID values (not part of a meaningful name) are excluded from the diff
  3. Array count rows (e.g., "items: 3") are suppressed from the results table
  4. bundleId and packageId values are filtered so app-specific identifiers don't generate false conflicts
  5. Tenant ID strings are excluded so cross-tenant IDs don't appear as conflicts
**Plans:** 1 plan
Plans:
- [x] 02-01-PLAN.md — TDD value-based noise exclusion with $excludedValuePatterns and extended $isExcludedSetting

### Phase 3: Deprecated Settings
**Goal**: Deprecated settings are visibly flagged in both the comparison table and manual review panels
**Depends on**: Phase 1
**Requirements**: ENG-03
**Success Criteria** (what must be TRUE):
  1. Any setting whose name or value contains "deprecated" shows a visual "Deprecated" badge in the HTML report
  2. Deprecated settings in manual review policies show a deprecated badge alongside the source/destination side badge
  3. Deprecated settings are still included in comparison results (not silently filtered) so the admin can act on them
**Plans:** 1 plan
Plans:
- [x] 03-01-PLAN.md — TDD deprecated detection (IsDeprecated flag) and comparison table badge rendering

### Phase 4: Duplicate Detection Engine
**Goal**: The engine identifies settings that appear in multiple policies with different values, and produces risk-assessed messaging for cross-tenant scenarios
**Depends on**: Phase 1
**Requirements**: ENG-02, ENG-04
**Success Criteria** (what must be TRUE):
  1. A setting appearing in more than one policy with different values is detected as a duplicate, whether in one tenant or both
  2. Duplicates within a single tenant are distinguished from cross-tenant duplicates in analysis output
  3. Risk assessment messaging correctly identifies majority/minority splits (e.g., "3 of 4 policies agree — 1 outlier")
  4. Cross-tenant outlier scenarios produce a message that describes which tenant is the outlier
  5. Duplicate data is available to downstream HTML phases (value keyed by settingDefinitionId + all policy/value pairs)
**Plans:** 1 plan
Plans:
- [x] 04-01-PLAN.md — TDD duplicate detection engine with $scanForDuplicates scriptblock and ENG-02/ENG-04 tests

### Phase 5: Value Display
**Goal**: Long setting values are readable without cluttering the table, conflicting values are visually prominent, and values can be copied with one click
**Depends on**: Phase 1
**Requirements**: VAL-01, VAL-02, VAL-03, VAL-04
**Success Criteria** (what must be TRUE):
  1. Values longer than 100 characters show truncated text with a "More" toggle; clicking expands the full value
  2. Clicking "Less" collapses the expanded value back to the truncated form
  3. Expanded values render in monospace font with pre-wrap formatting so line breaks are preserved
  4. A copy button appears when hovering a value cell and briefly shows "Copied!" on click
  5. Destination column values that conflict with source display in bold red text
**Plans:** 1 plan
Plans:
- [x] 05-01-PLAN.md — TDD value display: expand/collapse toggle, copy-to-clipboard, bold red conflicts
**UI hint**: yes

### Phase 6: Assignments Display
**Goal**: Assignment groups are color-coded by inclusion type and filter assignments display contextually below their group
**Depends on**: Phase 1
**Requirements**: ASG-01, ASG-02, ASG-03, ASG-04
**Success Criteria** (what must be TRUE):
  1. Include-type group assignments render in the default foreground color with no prefix
  2. Exclude-type group assignments render in red with an "Exclude:" prefix
  3. "All Devices" and "All Users" built-in assignments render in blue
  4. When a filter is attached to an assignment, it displays on a separate muted line directly below the assignment
**Plans:** 1 plan
Plans:
- [x] 06-01-PLAN.md — TDD assignment display: color-coded inline text, filter info on muted line, em dash empty state
**UI hint**: yes

### Phase 7: Manual Review Rendering
**Goal**: Scripts, compliance rules, and manual review panels render with structured formatting and proper visual context (side badges, deprecated indicators, duplicate tables)
**Depends on**: Phase 3, Phase 4
**Requirements**: MAN-01, MAN-02, MAN-03, MAN-04, MAN-05
**Success Criteria** (what must be TRUE):
  1. PowerShell script content in manual review panels shows syntax highlighting for keywords, strings, variables, comments, cmdlets, and types
  2. Bash/shell scripts detected by shebang line (`#!/`) render with basic syntax highlighting distinct from PowerShell
  3. Compliance rules render as a four-column table (Setting | Operator | Type | Expected Value), not as raw text
  4. When a policy appears in the duplicate settings data, its manual review section shows a horizontal table of the setting's values across all policies
  5. Each manual review policy panel displays a Source or Destination side badge, and a Deprecated badge if any setting is deprecated
**Plans:** 2 plans
Plans:
- [x] 07-01-PLAN.md — TDD RED: failing Pester tests for MAN-01 through MAN-05 manual review rendering
- [x] 07-02-PLAN.md — TDD GREEN: CSS, rendering loop, and JS implementation for bash highlighting, compliance table, duplicate table
**UI hint**: yes

### Phase 8: Table Enhancements
**Goal**: The comparison table columns are user-resizable, duplicate settings are badged with context, and setting names show both name and path in a single readable cell
**Depends on**: Phase 4
**Requirements**: TBL-01, TBL-02, TBL-03
**Success Criteria** (what must be TRUE):
  1. The user can drag column borders left or right to resize columns; double-clicking a border resets that column to its default width
  2. Settings identified as duplicates show an amber badge in the setting name cell; hovering the badge reveals a tooltip listing the other policies containing the same setting
  3. The setting name cell displays the bold setting name on the first line and the muted setting path on the second line
**Plans:** 2 plans
Plans:
- [x] 08-01-PLAN.md — TDD RED: failing Pester tests for TBL-01 through TBL-03 table enhancements
- [x] 08-02-PLAN.md — TDD GREEN: CSS, duplicate lookup, setting name cell, and column resize JS implementation
**UI hint**: yes

### Phase 9: Filtering and Navigation
**Goal**: The admin can filter the comparison table by category, status, and free-text search, with a live count showing how many results are visible
**Depends on**: Phase 1
**Requirements**: FLT-01, FLT-02, FLT-03, FLT-04
**Success Criteria** (what must be TRUE):
  1. A category dropdown is populated from all unique product/category combinations in the report and filters the table when a selection is made
  2. A filter summary line reads "Showing X settings across Y policies" and updates whenever any filter changes
  3. Status pills (Conflicting, Source Only, Dest Only, Matched) support multi-select — clicking one toggles it without clearing others
  4. The search field filters rows matching input against setting name, setting path, both value columns, policy names, and category
**Plans:** 2 plans
Plans:
- [x] 09-01-PLAN.md — TDD RED: failing Pester tests for FLT-01 through FLT-04 filtering and navigation
- [x] 09-02-PLAN.md — TDD GREEN: CSS, HTML rendering, and JS implementation for category composites, status pill colors, clear filters
**UI hint**: yes

### Phase 10: Duplicate Settings Tab
**Goal**: A dedicated Duplicates tab gives the admin a focused view of all cross-policy/cross-tenant conflicts with smart analysis and its own search
**Depends on**: Phase 4, Phase 7
**Requirements**: DUP-01, DUP-02, DUP-03, DUP-04
**Success Criteria** (what must be TRUE):
  1. The report has a Duplicates tab that lists every setting appearing in more than one policy with differing values
  2. Each duplicate entry shows the setting name followed by a row per policy with Source/Destination badge and the policy's value for that setting
  3. Analysis messaging under each entry describes the scenario accurately (same-tenant conflict, cross-tenant match, majority vs outlier)
  4. A search field within the Duplicates tab filters entries by setting name or policy name in real time
**Plans:** 2 plans
Plans:
- [ ] 10-01-PLAN.md — TDD RED: failing Pester tests for DUP-01 through DUP-04 duplicates tab
- [ ] 10-02-PLAN.md — TDD GREEN: CSS, HTML rendering, analyzeDuplicate() JS, and dupTabSearch() JS implementation
**UI hint**: yes

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 -> 8 -> 9 -> 10

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Matching Foundation | 1/1 | Complete | - |
| 2. Noise Exclusion | 1/1 | Complete | - |
| 3. Deprecated Settings | 1/1 | Complete | - |
| 4. Duplicate Detection Engine | 1/1 | Complete | - |
| 5. Value Display | 1/1 | Complete | - |
| 6. Assignments Display | 1/1 | Complete | - |
| 7. Manual Review Rendering | 2/2 | Complete | - |
| 8. Table Enhancements | 2/2 | Complete | - |
| 9. Filtering and Navigation | 0/2 | Not started | - |
| 10. Duplicate Settings Tab | 0/2 | Not started | - |
