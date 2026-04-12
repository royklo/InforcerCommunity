---
phase: 07-manual-review-rendering
plan: "02"
subsystem: html-renderer
tags:
  - pester
  - tdd
  - manual-review
  - green-phase
  - bash-highlighting
  - compliance-table
  - duplicate-table
dependency_graph:
  requires:
    - "07-01 (MAN-01 through MAN-05 failing Pester tests)"
  provides:
    - "MAN-01 through MAN-05 rendering features — all GREEN"
  affects:
    - "module/Private/ConvertTo-InforcerComparisonHtml.ps1"
tech_stack:
  added: []
  patterns:
    - "Priority-ordered if/elseif rendering dispatch in PowerShell foreach loop"
    - "ConvertFrom-Json with try/catch graceful degradation for both JSON branches"
    - "Shebang detection via TrimStart() + regex '^#!' for bash vs PowerShell routing"
    - "Ordered hashtable $policyColumns for deterministic duplicate table column order"
    - "$encSValue deferred inside each branch to avoid HTML-encoding corrupting JSON"
key_files:
  created: []
  modified:
    - module/Private/ConvertTo-InforcerComparisonHtml.ps1
decisions:
  - "Deferred $encSValue assignment to inside each branch (not top of loop) to prevent double-encoding corrupting JSON parsing for __DUPLICATE_TABLE__ and rulesContent"
  - "Used $sideCls2 variable name inside dup-table header loop to avoid shadowing the outer $sideCls used for the policy panel side badge"
  - "highlightBash JS tokenizer uses single-regex alternation matching the highlightPS pattern, with bash-specific keyword/command classification"
metrics:
  duration_minutes: 5
  completed_date: "2026-04-13"
  tasks_completed: 2
  tasks_total: 2
  files_modified: 1
---

# Phase 07 Plan 02: Manual Review Rendering — GREEN Implementation Summary

**One-liner:** Bash syntax highlighting (highlightBash JS + sh-* CSS), compliance rules four-column table (ConvertFrom-Json), and duplicate settings horizontal table (dup-table with conflict highlighting) implemented in ConvertTo-InforcerComparisonHtml.ps1 — all 16 MAN tests GREEN, 77/77 full suite pass.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add CSS classes and JS highlightBash function (MAN-01, MAN-02) | 52bc586 | module/Private/ConvertTo-InforcerComparisonHtml.ps1 |
| 2 | Implement rendering loop priority routing (MAN-02, MAN-03, MAN-04, MAN-05) | 05e20ed | module/Private/ConvertTo-InforcerComparisonHtml.ps1 |

## What Was Built

### Task 1 — CSS and JS additions

**CSS classes added** (after `.copy-btn:hover`):
- `.sh-keyword`, `.sh-string`, `.sh-variable`, `.sh-command`, `.sh-comment` — bash syntax token colors matching IntuneLens D-03 spec
- `.code-lang-label` — language label pill rendered above code blocks
- `.compliance-table`, `.compliance-table th`, `.compliance-table td`, `.compliance-table tr:last-child td` — four-column compliance rules table
- `.dup-table-wrap`, `.dup-table`, `.dup-table th`, `.dup-table td`, `.dup-table td.dup-setting-name`, `.dup-table td.dup-conflict` — horizontal duplicate settings table with conflict cell highlighting

**JS additions** (after `highlightPS` closing `}`):
- `highlightBash(code)` function — single-regex tokenizer classifying `#` comments, `"..."/'...'` strings, `$var` variables, bash keywords (if/then/else/fi/for/do/done/while/until/case/esac/function/return/local/export/set/trap/in), and common commands (echo/curl/rm/mkdir/cp/mv/chmod/chown/grep/sed/awk/cat/ls/cd/pwd/source/eval/exec/exit) as `sh-command`
- `document.querySelectorAll('.sh-code code').forEach(highlightBash)` wired inside existing try/catch block

### Task 2 — Rendering loop priority routing

Replaced the 3-branch if/elseif/else block (lines 779-787) with a 6-priority dispatch:

1. **`^__DUPLICATE_TABLE__`** → JSON-parse the suffix, build `$policyColumns` ordered hashtable for deterministic column order, emit `<table class="dup-table">` with `<th>` policy headers (with side badges) and `<td class="dup-conflict">` for conflicting values. Try/catch falls back to default display.

2. **`$s.Name -eq 'rulesContent'`** → JSON-parse, extract `$parsed.Rules` / `$parsed.rules` / `[array]$parsed` (three casing variants), emit `<table class="compliance-table">` with Setting/Operator/Type/Expected Value headers. Each field individually HtmlEncoded. Try/catch + `$rulesRendered` flag falls back to default display.

3. **`scriptContent|detectionScriptContent|remediationScriptContent` + length > 100** → Check `$s.Value.TrimStart() -match '^#!'` for shebang. Assign `sh-code` (bash) or `ps-code` (PowerShell) class on `<pre>`. Render `<span class="code-lang-label">` before `<pre>`.

4. **`$isSettingDepr`** → deprecated setting display (unchanged behavior).

5. **else** → default key-value display (unchanged behavior).

## Test Results

| Suite | Before | After |
|-------|--------|-------|
| MAN-01 | 2/2 PASS | 2/2 PASS |
| MAN-02 | 1/4 PASS | 4/4 PASS |
| MAN-03 | 1/3 PASS | 3/3 PASS |
| MAN-04 | 0/3 PASS | 3/3 PASS |
| MAN-05 | 4/4 PASS | 4/4 PASS |
| **Full suite** | **69/77** | **77/77** |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] highlightBash tokens.push had malformed parentheses**
- **Found during:** Task 1 verification (code review of generated JS)
- **Issue:** Initial `tokens.push` line had misplaced parentheses: `tokens.push('<span class="' + cls + '">') + escHtml(t) + ('</span>');` — the `push()` call closed too early, making the expression a no-op concatenation discarded by JS
- **Fix:** Corrected to `tokens.push('<span class="' + cls + '">' + escHtml(t) + '</span>');` matching the highlightPS pattern exactly
- **Files modified:** module/Private/ConvertTo-InforcerComparisonHtml.ps1
- **Commit:** 52bc586

**2. [Rule 1 - Bug] Variable name shadowing — $sideCls in dup-table header loop**
- **Found during:** Task 2 implementation
- **Issue:** The outer loop already used `$sideCls` for the policy panel side badge. Reusing it inside the `$policyColumns` loop would have overwritten the outer value, potentially breaking the `<summary>` side badge on subsequent iterations
- **Fix:** Used `$sideCls2` inside the inner loop for the dup-table column headers
- **Files modified:** module/Private/ConvertTo-InforcerComparisonHtml.ps1
- **Commit:** 05e20ed

## Known Stubs

None — all rendering paths are wired to real data. No placeholders, no hardcoded empty values, no mock data flowing to output.

## Threat Flags

All XSS mitigations per threat model applied:
- T-07-02: `$encSValue = HtmlEncode($s.Value)` computed inside script branch before inserting into `<code>` element
- T-07-03: Each compliance rule field (settingName/operator/dataType/operand) individually HtmlEncoded before `<td>` insertion
- T-07-04: Policy names from `__DUPLICATE_TABLE__` JSON HtmlEncoded before `<th>` insertion
- T-07-05: `$encSName = HtmlEncode($s.Name)` at top of loop, used in all branches
- T-07-06: Both `__DUPLICATE_TABLE__` and `rulesContent` branches wrapped in try/catch with graceful fallback
- T-07-07: JSON parsing uses `$s.Value` (raw); `$encSValue` only computed inside branches that emit HTML output

No new trust boundaries or network endpoints introduced.

## Self-Check: PASSED

- [x] module/Private/ConvertTo-InforcerComparisonHtml.ps1 modified and exists on disk
- [x] Commit 52bc586 exists: `feat(07-02): add bash highlighting CSS classes, compliance/dup-table CSS, highlightBash JS function`
- [x] Commit 05e20ed exists: `feat(07-02): implement rendering loop priority routing for MAN-02 through MAN-04`
- [x] `.sh-keyword` CSS class present in file
- [x] `.sh-comment` CSS class present in file
- [x] `.compliance-table` CSS class present in file
- [x] `.dup-table` CSS class present in file
- [x] `.dup-conflict` CSS class present in file
- [x] `.code-lang-label` CSS class present in file
- [x] `function highlightBash` present in JS block
- [x] `sh-code code` querySelectorAll call present
- [x] `'^__DUPLICATE_TABLE__'` present in rendering loop
- [x] `rulesContent` check present in rendering loop
- [x] `sh-code` class assignment for bash scripts present
- [x] `compliance-table` in rendered output present
- [x] `dup-table` in rendered output present
- [x] `dup-conflict` in rendered output present
- [x] `ConvertFrom-Json` in rulesContent branch present
- [x] All 16 MAN tests pass (0 failures)
- [x] Full suite 77/77 — no regressions in ENG-03, VAL, ASG
