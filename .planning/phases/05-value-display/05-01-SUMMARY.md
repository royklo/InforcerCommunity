---
phase: 05-value-display
plan: 01
subsystem: ConvertTo-InforcerComparisonHtml
tags: [value-display, html-rendering, css, javascript, pester, tdd]
dependency_graph:
  requires: []
  provides: [VAL-01, VAL-02, VAL-03, VAL-04]
  affects:
    - module/Private/ConvertTo-InforcerComparisonHtml.ps1
    - Tests/Renderers.Tests.ps1
tech_stack:
  added: []
  patterns:
    - value-wrap/value-truncate/value-actions HTML structure for long value cells
    - value-wrap/value-text/value-actions HTML structure for short value cells
    - Event-delegated JS handlers for toggle and copy actions
    - HtmlEncode applied to both display text and data-value attribute
key_files:
  created: []
  modified:
    - Tests/Renderers.Tests.ps1
    - module/Private/ConvertTo-InforcerComparisonHtml.ps1
decisions:
  - "value-diff moves from td to inner span/div — prevents CSS specificity conflicts and matches VAL-04 contract"
  - "Pseudo-element expand UI removed entirely in favor of explicit button — accessible, keyboard-operable"
  - "HtmlEncode applied to data-value attribute to prevent attribute breakout (T-05-02)"
  - "Two separate event-delegated handlers (toggle + copy) replace one combined handler — clear separation of concerns"
metrics:
  duration: ~5 minutes
  completed: 2026-04-12T18:22:25Z
  tasks_completed: 2
  files_modified: 2
---

# Phase 05 Plan 01: Value Display Enhancements Summary

**One-liner:** Expand/collapse toggle buttons, copy-to-clipboard, and inner-element conflict styling for comparison HTML value cells — replaces CSS pseudo-element approach with accessible button-driven UI.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Write failing Pester tests (RED) | `53cdb90` | Tests/Renderers.Tests.ps1 |
| 2 | Implement CSS, HTML rendering, JS handlers (GREEN) | `e8df5db` | module/Private/ConvertTo-InforcerComparisonHtml.ps1 |

## What Was Built

### CSS Changes (ConvertTo-InforcerComparisonHtml.ps1)

- Removed `.value-truncate::after` and `.value-truncate.expanded::after` pseudo-element rules entirely
- Removed `cursor: pointer` from `.value-truncate` (now handled by button)
- Added `.value-truncate.expanded { white-space: pre-wrap }` for formatted display when expanded
- Added `.value-toggle-btn` — inline button styled with `var(--warning)` color
- Added `.value-actions` — flex container for toggle and copy buttons
- Added `.value-copy-btn` — opacity-0 by default, revealed on `td.value-cell:hover`
- Added `.value-copy-btn.copied` — success color state after clipboard write

### HTML Rendering Changes

**Long values (>= 100 chars):**
```html
<td class="value-cell">
  <div class="value-wrap">
    <div class="value-truncate [value-diff]">...encoded value...</div>
    <div class="value-actions">
      <button class="value-toggle-btn">▼ More</button>
      <button class="value-copy-btn" data-value="...encoded...">📋 Copy</button>
    </div>
  </div>
</td>
```

**Short values (< 100 chars):**
```html
<td class="value-cell">
  <div class="value-wrap">
    <span class="value-text [value-diff]">...encoded value...</span>
    <div class="value-actions">
      <button class="value-copy-btn" data-value="...encoded...">📋 Copy</button>
    </div>
  </div>
</td>
```

- `value-diff` class now applied to inner element (`value-truncate` or `value-text`), never to the `td`
- Source column never receives `value-diff` regardless of conflict status

### JS Changes

Replaced single old handler (`closest(".value-truncate")`) with two event-delegated handlers:

1. **Toggle handler** — `closest(".value-toggle-btn")` → navigates to `.value-wrap` → queries `.value-truncate` sibling → toggles `expanded` class → updates button text (▲ Less / ▼ More)
2. **Copy handler** — `closest(".value-copy-btn")` → reads `data-value` attr → `navigator.clipboard.writeText()` → adds `copied` class + "✓ Copied!" text → resets after 1500ms

### Pester Tests (Tests/Renderers.Tests.ps1)

Added `Describe 'ConvertTo-InforcerComparisonHtml - Value Display' -Tag 'VAL', 'Phase5'` with 8 tests:

| Test | Tag | Assertion |
|------|-----|-----------|
| renders value-toggle-btn with More text for long values | VAL-01 | HTML matches `value-toggle-btn.*More` |
| does not render value-toggle-btn for short values row | VAL-01 | Short row does not match `value-toggle-btn` |
| CSS expanded state has white-space pre-wrap | VAL-02 | CSS matches `.value-truncate.expanded.*white-space: pre-wrap` |
| CSS base truncate state does not have pre-wrap | VAL-02 | Base `.value-truncate` rule has no `pre-wrap` |
| renders value-copy-btn with data-value on all value cells | VAL-03 | HTML matches `value-copy-btn.*data-value` |
| JS contains clipboard writeText handler for value-copy-btn | VAL-03 | JS contains `navigator.clipboard.writeText` |
| value-diff class is on inner element not td for conflicting dest | VAL-04 | HTML matches inner span pattern |
| source column does not have value-diff class for conflicting row | VAL-04 | Source value has plain `value-text` class |

**Result:** All 8 VAL tests GREEN. Full 47-test suite GREEN (no regressions).

## Deviations from Plan

None — plan executed exactly as written.

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or schema changes introduced. All values continue to pass through `[System.Net.WebUtility]::HtmlEncode()` for both display text and `data-value` attribute as specified in T-05-01 and T-05-02. T-05-03 accepted: JS clipboard handler uses `data-value` attribute only, no eval or innerHTML with user data.

## Known Stubs

None — all value cells are wired to real comparison model data from the API pipeline.

## Self-Check: PASSED

- [x] `Tests/Renderers.Tests.ps1` — exists and contains all 8 VAL tests
- [x] `module/Private/ConvertTo-InforcerComparisonHtml.ps1` — modified with all new CSS/HTML/JS
- [x] Commit `53cdb90` — RED phase tests
- [x] Commit `e8df5db` — GREEN phase implementation
- [x] `Invoke-Pester -Tag 'VAL'` — 8 passed, 0 failed
- [x] `Invoke-Pester ./Tests/Renderers.Tests.ps1` — 47 passed, 0 failed
