---
phase: 08-table-enhancements
plan: "02"
subsystem: renderer
tags: [TBL, Phase8, css, javascript, pester, tdd, green]
dependency_graph:
  requires: [08-01]
  provides: [TBL-01-impl, TBL-02-impl, TBL-03-impl]
  affects:
    - module/Private/ConvertTo-InforcerComparisonHtml.ps1
    - Tests/Renderers.Tests.ps1
tech_stack:
  added: []
  patterns: [col-resize-handle-iife, duplicate-lookup-hashtable, strongtag-setting-name, unconditional-path-render]
key_files:
  created: []
  modified:
    - module/Private/ConvertTo-InforcerComparisonHtml.ps1
    - Tests/Renderers.Tests.ps1
decisions:
  - "Wrapped setting name in <strong> tag unconditionally — required updating ENG-03 regression test from 'Normal Setting</td>' to '<strong>Normal Setting</strong></td>'"
  - "Column resize JS uses single-quoted PS strings to embed JS single-quoted string literals, avoiding double-quote escaping issues in AppendLine calls"
  - "Duplicate lookup uses SettingPath.ToLowerInvariant() as key with Name fallback — matches Phase 4 D-08 decision preserved across phases"
metrics:
  duration: "~15 minutes"
  completed: "2026-04-13"
  tasks_completed: 2
  files_modified: 2
requirements:
  - TBL-01
  - TBL-02
  - TBL-03
---

# Phase 08 Plan 02: Table Enhancements GREEN Implementation Summary

**One-liner:** Column resize handles (CSS + JS IIFE with defaultWidths/dblclick/drag), amber duplicate badges (lookup from ManualReview `__DUPLICATE_TABLE__` data), and bold setting name with unconditional path render — all TBL tests GREEN.

## What Was Built

Three zones modified in `ConvertTo-InforcerComparisonHtml.ps1`:

### Zone 1: CSS additions (Task 1)

| Class | Purpose |
|-------|---------|
| `th { position: relative }` | Enables absolute-positioned resize handle within header cell |
| `.setting-name strong` | Bold setting name with `font-weight: 600; color: var(--text)` |
| `.col-resize-handle` | Invisible 8px-wide absolute handle at right edge of each `<th>` |
| `.col-resize-handle::after` | Visual indicator bar (transparent by default) |
| `.col-resize-handle:hover::after` | Accent-colored indicator on hover |
| `.col-resize-handle.resizing::after` | Warning-colored wider bar during active drag |
| `.badge-duplicate` | Amber pill badge matching `.badge-deprecated` pattern, `cursor: help` |

### Zone 2: Duplicate lookup map + setting name cell (Task 2)

**Duplicate lookup map** inserted before the `foreach ($row in $allRows)` loop:
- Reads `ManualReview['Duplicate Settings (Different Values)']`
- Parses `__DUPLICATE_TABLE__` JSON values into `$duplicateLookup` hashtable
- Key: `$s.Name.ToLowerInvariant()` (matches Phase 4 D-08)
- Fail-silent on JSON parse errors via `Write-Verbose`

**Setting name cell** replacement:
- `$rowKey` = `SettingPath.ToLowerInvariant()` with `Name` fallback
- `$dupeBadge` populated from lookup with HtmlEncoded tooltip (`Also configured in: ...`)
- Cell order: `<strong>$encName</strong>` + `$deprBadge` + `$dupeBadge` + `$pathHtml`
- Path renders for ANY non-empty `SettingPath` (removed ` > ` condition)

### Zone 3: Column resize JS (Task 2)

IIFE wrapped in `try/catch` added before `</script>`:
- Captures `defaultWidths[]` from `th.offsetWidth` before applying `table-layout: fixed`
- Creates `.col-resize-handle` div per `<th>` via `document.createElement`
- `dblclick` handler resets `th.style.width` to `defaultWidths[i]`
- `mousedown` handler: `e.stopPropagation()` prevents sort, captures `startX`/`startW`, adds `resizing` class
- `mousemove`/`mouseup` document-level handlers; `minWidths` = 40 for col 0, 60 for others

## Verification Results

```
All TBL tests:      Total: 11  Passed: 11  Failed: 0  (GREEN)
Full suite:         Total: 88  Passed: 88  Failed: 0  (zero regressions)
```

## Commits

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add CSS classes for col-resize-handle, badge-duplicate, setting-name strong | 40d2166 | module/Private/ConvertTo-InforcerComparisonHtml.ps1 |
| 2 | Implement duplicate lookup map, bold setting name cell, and column resize JS | 13eae3f | module/Private/ConvertTo-InforcerComparisonHtml.ps1, Tests/Renderers.Tests.ps1 |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] ENG-03 test assertion broken by new `<strong>` wrapping**
- **Found during:** Task 2 verification (full suite run)
- **Issue:** Pre-existing ENG-03 test `does not render badge-deprecated span for non-deprecated rows` asserted `Normal Setting</td>` — a pattern that relied on the old unadorned name rendering. The new `<strong>` wrapping changed the HTML to `<strong>Normal Setting</strong></td>`, making the old pattern fail.
- **Fix:** Updated ENG-03 test assertion to `<strong>Normal Setting</strong></td>` — same intent (no deprecated badge), updated pattern.
- **Files modified:** Tests/Renderers.Tests.ps1 (line 434)
- **Commit:** 13eae3f

## Known Stubs

None — all three TBL features fully wired: CSS classes rendered, duplicate lookup reads live ManualReview data, JS IIFE runs on page load.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: T-08-02 mitigated | module/Private/ConvertTo-InforcerComparisonHtml.ps1 | `$tooltipText` HtmlEncoded via `[System.Net.WebUtility]::HtmlEncode($tooltipText)` before embedding in title attribute |
| threat_flag: T-08-03 preserved | module/Private/ConvertTo-InforcerComparisonHtml.ps1 | `$encPath = [System.Net.WebUtility]::HtmlEncode($settingPath)` preserved in new `$pathHtml` construction |
| threat_flag: T-08-04 accepted | module/Private/ConvertTo-InforcerComparisonHtml.ps1 | Resize handle injected via `document.createElement` + `appendChild` — no innerHTML XSS vector |

## Self-Check: PASSED

- [x] module/Private/ConvertTo-InforcerComparisonHtml.ps1 contains `position: relative` in th rule
- [x] module/Private/ConvertTo-InforcerComparisonHtml.ps1 contains `.col-resize-handle`
- [x] module/Private/ConvertTo-InforcerComparisonHtml.ps1 contains `.col-resize-handle::after`
- [x] module/Private/ConvertTo-InforcerComparisonHtml.ps1 contains `.col-resize-handle:hover::after`
- [x] module/Private/ConvertTo-InforcerComparisonHtml.ps1 contains `.col-resize-handle.resizing::after`
- [x] module/Private/ConvertTo-InforcerComparisonHtml.ps1 contains `.badge-duplicate`
- [x] module/Private/ConvertTo-InforcerComparisonHtml.ps1 contains `.setting-name strong`
- [x] module/Private/ConvertTo-InforcerComparisonHtml.ps1 contains `$duplicateLookup = @{}`
- [x] module/Private/ConvertTo-InforcerComparisonHtml.ps1 contains `$dupeCategory = 'Duplicate Settings (Different Values)'`
- [x] module/Private/ConvertTo-InforcerComparisonHtml.ps1 contains `$row.SettingPath.ToLowerInvariant()`
- [x] module/Private/ConvertTo-InforcerComparisonHtml.ps1 contains `<strong>$encName</strong>`
- [x] module/Private/ConvertTo-InforcerComparisonHtml.ps1 contains `Also configured in:`
- [x] module/Private/ConvertTo-InforcerComparisonHtml.ps1 contains `defaultWidths` in JS block
- [x] module/Private/ConvertTo-InforcerComparisonHtml.ps1 contains `dblclick` in JS block
- [x] module/Private/ConvertTo-InforcerComparisonHtml.ps1 contains `col-resize-handle` in JS createElement call
- [x] module/Private/ConvertTo-InforcerComparisonHtml.ps1 contains `e.stopPropagation()` in resize mousedown
- [x] module/Private/ConvertTo-InforcerComparisonHtml.ps1 contains `tableLayout` set to `fixed`
- [x] The `$settingPath -match ' > '` if/else block is REMOVED (replaced by unconditional path rendering)
- [x] Commit 40d2166 exists
- [x] Commit 13eae3f exists
- [x] 88/88 tests pass
