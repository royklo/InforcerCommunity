---
phase: 07-manual-review-rendering
plan: "01"
subsystem: test
tags:
  - pester
  - tdd
  - manual-review
  - red-phase
dependency_graph:
  requires:
    - "06-01 (assignments display — Renderers.Tests.ps1 infrastructure)"
  provides:
    - "MAN-01 through MAN-05 Pester test contracts for Plan 02 implementation"
  affects:
    - "Tests/Renderers.Tests.ps1"
tech_stack:
  added: []
  patterns:
    - "InModuleScope with ComparisonModel fixture containing ManualReview ordered hashtable"
    - "Pester -Tag filtering for MAN-XX requirement IDs"
    - "Regex assertions on HTML string output for CSS classes, JS functions, HTML structure"
key_files:
  created: []
  modified:
    - Tests/Renderers.Tests.ps1
decisions:
  - "MAN-04 th-header test uses regex to match dup-table...th pattern to avoid false-pass from raw JSON text containing policy names"
  - "MAN-03 invalid JSON degradation test passes immediately (graceful degradation already works via default display)"
  - "MAN-02 ps-code fallback test passes immediately (existing script detection already routes non-shebang to ps-code)"
metrics:
  duration_minutes: 25
  completed_date: "2026-04-12"
  tasks_completed: 1
  tasks_total: 1
  files_modified: 1
---

# Phase 07 Plan 01: Manual Review Rendering — Failing Tests (RED) Summary

**One-liner:** Pester RED phase tests for MAN-01 through MAN-05 covering PowerShell/bash syntax highlighting, compliance rules table, duplicate settings table, and side/deprecated badge verification in `ConvertTo-InforcerComparisonHtml`.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Write MAN-01 through MAN-05 failing Pester tests | e1e472b | Tests/Renderers.Tests.ps1 |

## What Was Built

Added a new `Describe 'ConvertTo-InforcerComparisonHtml - Manual Review Rendering' -Tag 'MAN', 'Phase7'` block to `Tests/Renderers.Tests.ps1` with 16 `It` blocks across 5 requirement areas.

### Fixture Design

The `BeforeAll` creates a `$CompModelMan` with 7 policies in `ManualReview`:
1. **PS Script Policy** (Source) — `scriptContent` with 100+ char PowerShell script (no shebang) → tests MAN-01 and MAN-02 PS fallback
2. **Bash Script Policy** (Destination) — `detectionScriptContent` with bash shebang script → tests MAN-02 bash detection
3. **Compliance Rules Policy** (Source) — `rulesContent` with valid `{"Rules":[...]}` JSON → tests MAN-03
4. **Duplicate Policy** (Source) — `someSettingDefId` with `__DUPLICATE_TABLE__[...]` prefix → tests MAN-04
5. **Deprecated Source Policy** (Source, HasDeprecated=$true) → tests MAN-05 badge presence
6. **Clean Dest Policy** (Destination, HasDeprecated=$false) → tests MAN-05 badge absence
7. **Invalid Rules Policy** (Destination) — `rulesContent` with `not-valid-json` → tests MAN-03 graceful degradation

### Test Results (RED State Confirmed)

| Requirement | Tests | Passing | Failing | Notes |
|-------------|-------|---------|---------|-------|
| MAN-01 | 2 | 2 | 0 | Already implemented — `highlightPS` and `.ps-keyword` exist |
| MAN-02 | 4 | 1 | 3 | `ps-code` fallback passes; `highlightBash`, `.sh-keyword`, `sh-code` fail |
| MAN-03 | 3 | 1 | 2 | Invalid JSON degradation passes; `compliance-table` and `th` headers fail |
| MAN-04 | 3 | 0 | 3 | All fail — `dup-table`, `th` headers, `dup-conflict` class |
| MAN-05 | 4 | 4 | 0 | Already implemented — badges render correctly |
| **Total** | **16** | **8** | **8** | Expected RED state achieved |

Full suite: 77 tests total, 69 PASS, 8 FAIL (all failures are intentional MAN-02/03/04 RED tests). No regressions in ENG-03, VAL, ASG, Html, Markdown blocks.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] MAN-04 policy-name th test required tighter assertion**
- **Found during:** Task 1 verification
- **Issue:** The naive `Should -Match 'Policy X'` test passed falsely because the raw `__DUPLICATE_TABLE__[{"Policy":"Policy X"...}]` JSON was being rendered as literal text in the HTML output, so "Policy X" appeared but not as a `<th>` element.
- **Fix:** Changed assertion to `Should -Match '(?s)dup-table.*<th>.*Policy X.*</th>'` to require the policy name to appear inside a `<th>` element within the dup-table context.
- **Files modified:** Tests/Renderers.Tests.ps1
- **Commit:** e1e472b (included in task commit)

## Known Stubs

None — this plan adds tests only. No implementation code was written.

## Self-Check: PASSED

- [x] Tests/Renderers.Tests.ps1 modified and committed at e1e472b
- [x] Commit e1e472b exists in git log
- [x] `Describe 'ConvertTo-InforcerComparisonHtml - Manual Review Rendering' -Tag 'MAN', 'Phase7'` present
- [x] MAN-01 tagged It blocks: 2 (PASS)
- [x] MAN-02 tagged It blocks: 4 (3 FAIL / 1 PASS)
- [x] MAN-03 tagged It blocks: 3 (2 FAIL / 1 PASS)
- [x] MAN-04 tagged It blocks: 3 (3 FAIL)
- [x] MAN-05 tagged It blocks: 4 (PASS)
- [x] No regressions: 69 of 69 pre-existing tests still pass
