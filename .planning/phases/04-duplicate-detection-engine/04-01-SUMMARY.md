---
phase: 04-duplicate-detection-engine
plan: 01
subsystem: Compare-InforcerDocModels
tags: [duplicate-detection, manual-review, tdd, pester]
dependency_graph:
  requires:
    - 03-01 (deprecated settings detection — $scanForDeprecated pattern and ManualReview structure)
    - 02-01 (noise exclusion — $isExcludedSetting reused in duplicate scan)
  provides:
    - $scanForDuplicates scriptblock
    - ManualReview['Duplicate Settings (Different Values)'] populated with structured entries
    - __DUPLICATE_TABLE__ JSON encoding for downstream HTML rendering (phases 7, 8, 10)
  affects:
    - module/Private/Compare-InforcerDocModels.ps1
    - Tests/DocModel.Tests.ps1
tech_stack:
  added: []
  patterns:
    - HashSet[string] for O(1) processedPolicySides tracking
    - Dictionary[string,int] for intra-policy definitionId frequency counting
    - Per-product setting index to prevent cross-platform false positives
    - __DUPLICATE_TABLE__ prefix + ConvertTo-Json -Compress for structured value encoding
key_files:
  created: []
  modified:
    - module/Private/Compare-InforcerDocModels.ps1
    - Tests/DocModel.Tests.ps1
decisions:
  - D-05 category filter uses regex match against 'settings catalog|administrative templates' — Compliance and other categories excluded
  - D-07 dedup key is SettingPath.ToLowerInvariant() — case-insensitive path matching
  - D-08 requires non-empty DefinitionId — avoids false positives from unnamed settings
  - D-09 intra-policy repeats excluded via per-policy Dictionary counter before index build
  - em dash (U+2014) used in ProfileType messages per D-03 spec
  - Test 8 (ENG-02 __DUPLICATE_TABLE__ encoding) simplified to exactly 2-policy scenario so HaveCount 2 assertion holds
metrics:
  duration: ~4 minutes
  completed: "2026-04-12T17:51:00Z"
  tasks_completed: 2
  files_modified: 2
---

# Phase 04 Plan 01: Duplicate Detection Engine Summary

**One-liner:** Cross-policy and cross-tenant duplicate setting detection with `__DUPLICATE_TABLE__` encoding and risk assessment messaging via `$scanForDuplicates` scriptblock.

## What Was Built

`$scanForDuplicates` scriptblock inserted into `Compare-InforcerDocModels.ps1` between the deprecated settings scan and the alignment score computation. It runs after both `$scanForDeprecated` invocations and populates `ManualReview['Duplicate Settings (Different Values)']` with structured entries for downstream HTML rendering.

**Two-phase algorithm:**

- **Phase 1:** Builds a per-product setting index by iterating both `$SourceModel` and `$DestinationModel`. Only `Settings Catalog` and `Administrative Templates` categories are indexed (D-05). Settings without a `DefinitionId` are skipped (D-08). A per-policy `Dictionary[string,int]` tracks `DefinitionId` frequency to exclude intra-policy repeats (D-09). The dedup key is `SettingPath.ToLowerInvariant()` (D-07).

- **Phase 2:** For each path with 2+ entries and 2+ unique values, builds `__DUPLICATE_TABLE__` encoded setting values (JSON array of `@{Policy; Value; Side}`). Creates `ManualReview` entries with `PolicyName`, `Side`, `ProfileType` (risk message with em dash and "also in:" format per D-03), `Settings` list, and `HasDeprecated = $false`. A `$itemLookup` hashtable provides O(1) access for accumulating multiple duplicate settings per policy.

## Tests Written

**ENG-02 (8 tests):**
1. Same definitionId with different values across 2 policies detected as duplicate
2. Same definitionId with identical values NOT flagged
3. Setting without DefinitionId excluded (D-08)
4. Intra-policy repeated definitionId excluded (D-09)
5. Compliance category excluded (D-05)
6. Cross-product (Windows vs macOS) not cross-matched (D-06)
7. ManualReview entry has correct shape (PolicyName, Side, ProfileType, Settings, HasDeprecated)
8. Setting value has `__DUPLICATE_TABLE__` prefix with valid JSON containing Policy, Value, Side

**ENG-04 (4 tests):**
9. Single-tenant duplicate (both policies Source side) detected
10. Cross-tenant duplicate (Source + Destination) detected, both sides in ManualReview
11. policyValues JSON has all 3 entries in 3-policy scenario
12. ProfileType message format: `{N} duplicate settings — also in: {policy (Side), ...}`

## Commits

| Task | Commit | Description |
|------|--------|-------------|
| Task 1 (RED) | 1ba3296 | test(04-01): add failing ENG-02 and ENG-04 Pester tests |
| Task 2 (GREEN) | d017645 | feat(04-01): implement $scanForDuplicates scriptblock |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Test 8 expected count corrected from 2 to actual scenario**
- **Found during:** Task 2 GREEN phase
- **Issue:** Test 8 (ENG-02 `__DUPLICATE_TABLE__` encoding) used a 3-policy setup (2 Source + 1 Destination) but asserted `HaveCount 2`. The implementation correctly produces 3 entries for 3 policies. The assertion `HaveCount 2` was wrong for that scenario.
- **Fix:** Simplified the test to use exactly 2 policies (1 Source, 1 Destination) so `HaveCount 2` is accurate.
- **Files modified:** Tests/DocModel.Tests.ps1
- **Commit:** d017645 (combined with GREEN phase commit)

## Known Stubs

None — all ManualReview entries are fully populated with real data from the DocModel input.

## Self-Check: PASSED

- [x] `module/Private/Compare-InforcerDocModels.ps1` contains `$scanForDuplicates = {`
- [x] `module/Private/Compare-InforcerDocModels.ps1` contains `& $scanForDuplicates`
- [x] `module/Private/Compare-InforcerDocModels.ps1` contains `'Duplicate Settings (Different Values)'` (2 occurrences)
- [x] `module/Private/Compare-InforcerDocModels.ps1` contains `__DUPLICATE_TABLE__` (3 occurrences)
- [x] `module/Private/Compare-InforcerDocModels.ps1` contains `settings catalog|administrative templates`
- [x] `Tests/DocModel.Tests.ps1` contains `Describe 'Compare-InforcerDocModels - ENG-02 duplicate settings' -Tag 'ENG-02'`
- [x] `Tests/DocModel.Tests.ps1` contains `Describe 'Compare-InforcerDocModels - ENG-04 cross-tenant duplicates' -Tag 'ENG-04'`
- [x] Commits 1ba3296 and d017645 exist in git log
- [x] `Invoke-Pester ./Tests/DocModel.Tests.ps1 -Tag 'ENG-02','ENG-04'` — 12 passed, 0 failed
- [x] `Invoke-Pester ./Tests/DocModel.Tests.ps1` — 58 passed, 0 failed, 2 skipped (integration data unavailable)
