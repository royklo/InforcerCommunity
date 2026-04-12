---
phase: 08-table-enhancements
plan: "01"
subsystem: test
tags: [TBL, Phase8, pester, tdd, red]
dependency_graph:
  requires: []
  provides: [TBL-01-tests, TBL-02-tests, TBL-03-tests]
  affects: [Tests/Renderers.Tests.ps1]
tech_stack:
  added: []
  patterns: [pester-5x, inmodulescope-fixture, tag-based-test-organization]
key_files:
  created: []
  modified:
    - Tests/Renderers.Tests.ps1
decisions:
  - "Used ManualReview fixture with 'Duplicate Settings (Different Values)' key and __DUPLICATE_TABLE__ encoded value to drive TBL-02 duplicate lookup test; lookup key = SettingPath.ToLowerInvariant() matching Phase 4 D-08"
  - "TBL-03 empty-path test uses exact pattern '<strong>Bluetooth Enabled</strong></td>' — relies on Plan 02 rendering td closing immediately after strong tag when path is empty"
  - "One TBL-02 test (does NOT render badge-duplicate for non-duplicate rows) passes in RED state because badge-duplicate class does not exist at all yet — this is correct RED behavior"
metrics:
  duration: "~10 minutes"
  completed: "2026-04-13"
  tasks_completed: 1
  files_modified: 1
requirements:
  - TBL-01
  - TBL-02
  - TBL-03
---

# Phase 08 Plan 01: Table Enhancements RED Tests Summary

**One-liner:** Failing Pester RED tests for TBL-01 column resize (JS + CSS), TBL-02 amber duplicate badge (lookup + tooltip), and TBL-03 bold name / always-visible path cell layout.

## What Was Built

Appended a new `Describe 'ConvertTo-InforcerComparisonHtml - Table Enhancements' -Tag 'TBL', 'Phase8'` block to `Tests/Renderers.Tests.ps1` containing 10 failing tests across three requirement contexts.

### Test Coverage

| Context | Tag | Tests | Behavior Asserted |
|---------|-----|-------|-------------------|
| TBL-01: Column resize | TBL-01 | 4 | col-resize-handle CSS, th position:relative, defaultWidths JS array, dblclick reset |
| TBL-02: Duplicate badge | TBL-02 | 3 | badge-duplicate for matching rows, title tooltip "Also configured in:", no badge on non-duplicate |
| TBL-03: Setting name cell | TBL-03 | 3 | strong tag for name, setting-path renders without > separator, empty path omits span |

### Fixture Design

- **Row 1 (Firewall Mode):** deprecated=true, SettingPath='Security > Firewall', matching ManualReview duplicate entry (lookup key: 'security > firewall') — exercises all three features simultaneously
- **Row 2 (WiFi Standard):** SettingPath='SimpleWiFiPath' (no ` > ` separator) — exercises TBL-03 always-render-path
- **Row 3 (Bluetooth Enabled):** SettingPath='' (empty) — exercises TBL-03 omit-path-when-empty
- **ManualReview:** `'Duplicate Settings (Different Values)'` category with `__DUPLICATE_TABLE__[...]` encoded setting for Row 1 duplicate lookup

## Verification Results

```
TBL-tagged tests:   Total: 88  Passed: 1  Failed: 10  (RED state confirmed)
Non-TBL tests:      Total: 88  Passed: 77 Failed: 0   (zero regressions)
```

Failed tests (RED — expected):
1. renders col-resize-handle CSS class in style block
2. adds position:relative to th rule
3. includes defaultWidths array in JS block
4. includes dblclick event for column reset
5. renders badge-duplicate for rows matching duplicate lookup
6. badge-duplicate has title with Also configured in
7. wraps setting name in strong tag
8. renders setting-path for non-empty path without > separator
9. does not render setting-path span for empty SettingPath
10. renders cell elements in order: strong name, deprecated badge, duplicate badge, setting-path

Passing test (correct RED behavior):
- "does NOT render badge-duplicate for non-duplicate rows" — passes because `badge-duplicate` class does not exist in output at all yet; the negative match is vacuously satisfied. This remains a valid gate for Plan 02.

## Commits

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Write TBL-01 through TBL-03 failing Pester tests | 517bfbd | Tests/Renderers.Tests.ps1 |

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None — test-only file with hardcoded fixture data. No data sources to wire.

## Threat Flags

None — test file only; no network endpoints, auth paths, or schema changes introduced.

## Self-Check: PASSED

- [x] Tests/Renderers.Tests.ps1 contains `Describe 'ConvertTo-InforcerComparisonHtml - Table Enhancements' -Tag 'TBL', 'Phase8'`
- [x] Contains `It 'renders col-resize-handle CSS class in style block' -Tag 'TBL-01'`
- [x] Contains `It 'renders badge-duplicate for rows matching duplicate lookup' -Tag 'TBL-02'`
- [x] Contains `It 'wraps setting name in strong tag' -Tag 'TBL-03'`
- [x] Contains `It 'renders setting-path for non-empty path without > separator' -Tag 'TBL-03'`
- [x] Contains `It 'renders cell elements in order: strong name, deprecated badge, duplicate badge, setting-path' -Tag 'TBL-03'`
- [x] Commit 517bfbd exists
- [x] 10 TBL tests fail (RED), 77 existing tests pass (zero regressions)
