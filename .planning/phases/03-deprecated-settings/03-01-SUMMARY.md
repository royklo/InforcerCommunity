---
phase: 03-deprecated-settings
plan: "01"
subsystem: comparison-engine
tags: [tdd, deprecated-detection, badge-rendering, eng-03]
dependency_graph:
  requires: []
  provides: [ENG-03-deprecated-detection, ENG-03-badge-rendering]
  affects: [module/Private/Compare-InforcerDocModels.ps1, module/Private/ConvertTo-InforcerComparisonHtml.ps1]
tech_stack:
  added: []
  patterns: [tdd-red-green, inline-scriptblock-helper, html-badge-injection]
key_files:
  created: []
  modified:
    - Tests/DocModel.Tests.ps1
    - Tests/Renderers.Tests.ps1
    - module/Private/Compare-InforcerDocModels.ps1
    - module/Private/ConvertTo-InforcerComparisonHtml.ps1
decisions:
  - "Extracted $isSettingDeprecated as a dedicated helper scriptblock rather than inlining logic in each row block — DRY and testable"
  - "Added IsDeprecated at $buildSettingPaths result.Add level so all downstream row blocks simply read from lookup — single source of truth"
  - "Used -eq $true pattern on all row IsDeprecated assignments to guarantee $true/$false, never $null"
  - "Kept $scanForDeprecated (manual review deprecated scan) untouched per D-04 — comparison row detection is a separate concern"
metrics:
  duration: "~15 minutes"
  completed: "2026-04-12"
  tasks_completed: 2
  files_modified: 4
---

# Phase 03 Plan 01: Deprecated Settings Detection and Badge Rendering Summary

**One-liner:** TDD implementation of `IsDeprecated` flag on comparison rows and `badge-deprecated` HTML span in the comparison table setting-name cell, covering name/value/catalog detection per ENG-03.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Write ENG-03 Pester tests (RED) | `6e90aa1` | Tests/DocModel.Tests.ps1, Tests/Renderers.Tests.ps1 |
| 2 | Implement deprecated detection and badge rendering (GREEN) | `00c991c` | module/Private/Compare-InforcerDocModels.ps1, module/Private/ConvertTo-InforcerComparisonHtml.ps1 |

## What Was Built

### Engine (Compare-InforcerDocModels.ps1)

- Added `$isSettingDeprecated` helper scriptblock that checks deprecated in setting name, value, and catalog DisplayName (with null-guard on catalog per RESEARCH Pitfall 1)
- Added `IsDeprecated = (& $isSettingDeprecated $name $value $defId)` to `$buildSettingPaths` result.Add — detection happens at entry creation, not per-row
- Added `IsDeprecated` property to all three comparison row blocks:
  - Matched pair rows: reads from `$srcLookup` or `$dstLookup` depending on which side is present
  - Source-only rows: reads from `$srcLookup`
  - Dest-only rows: reads from `$dstLookup`
- All assignments use `-eq $true` to guarantee boolean, never `$null`

### Renderer (ConvertTo-InforcerComparisonHtml.ps1)

- Added `$deprBadge` variable before the setting-name cell: empty string when `IsDeprecated` is not `$true`, otherwise `' <span class="badge-deprecated">&#x26A0; Deprecated</span>'`
- Badge injected after `$encName` in both the `setting-path` branch and the plain branch
- Existing `.badge-deprecated` CSS class (line 407) used — no CSS changes needed
- Manual review deprecated rendering (separate `$scanForDeprecated` pipeline) left untouched per D-04

## Test Results

```
DocModel ENG-03:   5 passed, 0 failed
Renderers ENG-03:  2 passed, 0 failed
Full DocModel suite: 46 passed, 0 failed, 2 skipped (pre-existing)
```

## Verification

- `grep -c 'IsDeprecated' module/Private/Compare-InforcerDocModels.ps1` → **5** (helper + result.Add + 3 row blocks)
- `grep 'deprBadge' module/Private/ConvertTo-InforcerComparisonHtml.ps1` → badge assignment + both if/else branches confirmed
- Manual review lines 700+ unchanged — `$scanForDeprecated` untouched

## Decisions Made

1. **$isSettingDeprecated as extracted helper** — Rather than duplicating the three-check pattern in each of the three row blocks, a single `$isSettingDeprecated` scriptblock is defined once and called at the `$buildSettingPaths` level. This follows the existing pattern of helper scriptblocks (`$isExcludedSetting`, `$getCategoryName`) in the function.

2. **Detection at entry creation** — `IsDeprecated` is computed when the entry is added to `$result` inside `$buildSettingPaths`, not at comparison time. This keeps the row construction blocks clean and ensures the flag travels through the lookup without re-computation.

3. **-eq $true boolean guarantee** — All three row block assignments use `$srcLookup[$settingKey].IsDeprecated -eq $true` rather than direct assignment, ensuring the value is always `$true` or `$false` even if the lookup entry has `$null` for IsDeprecated.

4. **$scanForDeprecated preserved** — The existing manual review deprecated scan remains unchanged. It serves a different purpose (policy-level deprecated reporting in ManualReview) vs. the new row-level flagging.

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None — all rows carry a boolean `IsDeprecated` value and the badge renders conditionally on that value.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| (none) | — | Setting name (`$encName`) already HtmlEncoded before badge injection; badge content is static HTML with no user input |

## Self-Check

- Tests/DocModel.Tests.ps1 exists and contains `Describe 'Compare-InforcerDocModels - ENG-03 deprecated settings' -Tag 'ENG-03'`
- Tests/Renderers.Tests.ps1 exists and contains `Describe 'ConvertTo-InforcerComparisonHtml - ENG-03 deprecated badge' -Tag 'ENG-03'`
- module/Private/Compare-InforcerDocModels.ps1 contains `$isSettingDeprecated = {`
- module/Private/ConvertTo-InforcerComparisonHtml.ps1 contains `$deprBadge`
- Commits `6e90aa1` (RED) and `00c991c` (GREEN) exist

## Self-Check: PASSED
