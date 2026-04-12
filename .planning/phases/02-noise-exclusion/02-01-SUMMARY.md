---
phase: 02-noise-exclusion
plan: 01
subsystem: compare-engine
tags: [noise-exclusion, tdd, pester, intunelens-parity]
dependency_graph:
  requires: []
  provides: [value-based-noise-exclusion, ENG-01-tests]
  affects: [Compare-InforcerDocModels, Compare-InforcerEnvironments output]
tech_stack:
  added: []
  patterns: [TDD red-green, IntuneLens pattern port, PowerShell scriptblock closure]
key_files:
  created: []
  modified:
    - module/Private/Compare-InforcerDocModels.ps1
    - Tests/DocModel.Tests.ps1
decisions:
  - Pre-initialize category structure in matched-policy path so ComparisonRows is always an empty List (not null) when all settings are filtered, enabling null-safe Should -HaveCount 0 assertions
  - Use -match (not -cmatch) for GUID regex to handle both uppercase and lowercase GUIDs case-insensitively, matching IntuneLens behavior
  - Structural noise check (^\d+ items$) folded into $isExcludedSetting rather than kept as separate inline guard — eliminates Pitfall 1 (duplicate check anti-pattern)
metrics:
  duration_minutes: 25
  completed_date: "2026-04-12"
  tasks_completed: 2
  files_modified: 2
---

# Phase 02 Plan 01: Value-Based Noise Exclusion Summary

**One-liner:** Value-based noise exclusion ported from IntuneLens — standalone GUIDs, Top Level Setting Group Collection, and structural array counts are now filtered by `$isExcludedSetting` via extended `$Value` parameter.

## What Was Built

Extended the `$isExcludedSetting` scriptblock in `Compare-InforcerDocModels.ps1` to accept a `$Value` parameter alongside `$Name`, enabling value-based noise filtering at the same site as name-based filtering. Added `$excludedValuePatterns` array with 2 patterns ported directly from IntuneLens `EXCLUDED_VALUE_PATTERNS`. Consolidated the previously inline structural noise check into the scriptblock. Updated both call sites in `$buildSettingLookup`.

## Tasks

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Write ENG-01 Pester tests (RED) | 1da2376 | Tests/DocModel.Tests.ps1 |
| 2 | Implement value-based noise exclusion (GREEN) | 613e45c | module/Private/Compare-InforcerDocModels.ps1 |

## Changes Made

### module/Private/Compare-InforcerDocModels.ps1

**1. Added `$excludedValuePatterns` array** (after `$appIdSettingPatterns`, before `$ensureProductCategory`):
```powershell
$excludedValuePatterns = @(
    '^Top Level Setting Group Collection$'
    '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
)
```

**2. Extended `$isExcludedSetting` signature:**
- Changed `param([string]$Name)` → `param([string]$Name, [string]$Value = '')`
- Added structural noise check inside the scriptblock: `if ($Value -match '^\d+ items$') { return $true }`
- Added foreach loop over `$excludedValuePatterns`

**3. Updated call sites in `$buildSettingLookup`:**
- `& $isExcludedSetting $p.Name` → `& $isExcludedSetting $p.Name $p.Value`
- `& $isExcludedSetting $key` → `& $isExcludedSetting $key ''`
- Removed duplicate inline `if ($p.Value -match '^\d+ items$') { continue }`

**4. Pre-initialized category structure** in matched-policy path:
- Added `& $ensureProductCategory $productName $categoryName` before setting comparison loop
- Ensures `ComparisonRows` is always a `List[object]` (not `$null`) when all settings are filtered

### Tests/DocModel.Tests.ps1

Added `Describe 'Compare-InforcerDocModels - ENG-01 noise exclusion' -Tag 'ENG-01'` with 8 tests:

| Test | Input | Expected |
|------|-------|----------|
| excludes standalone GUID values | Value = 'a0b1c2d3-e4f5-...' | 0 rows |
| excludes uppercase GUID values | Value = 'A0B1C2D3-E4F5-...' | 0 rows |
| excludes Top Level Setting Group Collection | Value = 'Top Level Setting Group Collection' | 0 rows |
| excludes structural noise (multi-digit) | Value = '40 items' | 0 rows |
| excludes structural noise (single-digit) | Value = '3 items' | 0 rows |
| excludes odata.type names (regression) | Name = '@odata.type' | 0 rows |
| does not exclude legitimate values | Value = 'Enabled' | 1 row |
| does not exclude non-standalone GUID text | Value = 'some-guid-embedded-in-text abc123' | 1 row |

## Verification Results

```
ENG-01 tagged tests:  Passed: 8  Failed: 0
Full DocModel suite:  Passed: 24 Failed: 0  Skipped: 19 (integration data not available)
```

Grep for duplicate structural noise check in `$buildSettingLookup`: zero matches (consolidated into `$isExcludedSetting`).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Pre-initialize category structure for null-safe ComparisonRows access**
- **Found during:** Task 2 GREEN verification
- **Issue:** When all settings in a policy are excluded by noise filters, `$addRow` is never called, so `$ensureProductCategory` is never called for that product/category. This leaves `$products['Windows']` absent, making `$result.Products.Windows.Categories.'Settings Catalog'.ComparisonRows` return `$null`. In Pester 5, `$null | Should -HaveCount 0` evaluates `@($null)` with count 1, causing test failure.
- **Fix:** Added `& $ensureProductCategory $productName $categoryName` at the start of the matched-policy comparison block so the category structure is always initialized before filtering. This is correct behavior — the category exists in both models, so its ComparisonRows list should exist (empty) in the result.
- **Files modified:** module/Private/Compare-InforcerDocModels.ps1
- **Commit:** 613e45c

## Known Stubs

None — all filtering logic is fully wired.

## Threat Flags

No new threat surface introduced. All changes are internal filtering logic within a private PowerShell function with no network, auth, or I/O involvement.

## Self-Check: PASSED

- SUMMARY.md: FOUND at `.planning/phases/02-noise-exclusion/02-01-SUMMARY.md`
- Commit 1da2376 (RED tests): FOUND
- Commit 613e45c (GREEN implementation): FOUND
- `$excludedValuePatterns`: present in module file
- `param([string]$Name, [string]$Value = '')`: present in `$isExcludedSetting`
- Call site `& $isExcludedSetting $p.Name $p.Value`: present
- Call site `& $isExcludedSetting $key ''`: present
- Inline `^\d+ items$` NOT in `$buildSettingLookup`: confirmed
- ENG-01 tests: 8/8 passed
- Full DocModel suite: 24/24 passed
