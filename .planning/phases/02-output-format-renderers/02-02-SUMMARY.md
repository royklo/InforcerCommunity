---
phase: 02-output-format-renderers
plan: "02"
subsystem: markdown-renderer
tags: [markdown, renderer, gfm, pester, tdd]
dependency_graph:
  requires: [01-02]
  provides: [ConvertTo-InforcerMarkdown]
  affects: [03-01]
tech_stack:
  added: []
  patterns: [StringBuilder, ConvertTo-MarkdownTable helper, ConvertTo-MarkdownAnchor helper, GFM pipe tables, char escape for unicode]
key_files:
  created:
    - module/Private/ConvertTo-InforcerMarkdown.ps1
    - Tests/Renderers.Tests.ps1
  modified: []
decisions:
  - "Use [char]0x2014 and [char]0x21B3 expressions (not literal Unicode) to avoid PSUseBOMForUnicodeEncodedFile ScriptAnalyzer warning"
  - "ConvertTo-MarkdownTable and ConvertTo-MarkdownAnchor defined as file-private helpers (no CmdletBinding) above ConvertTo-InforcerMarkdown in the same file"
  - "Tests/Renderers.Tests.ps1 created fresh (Plan 02-01 had not run); JSON/CSV describe blocks added as -Skip stubs for future plans"
metrics:
  duration: "4 minutes"
  completed: "2026-04-01"
  tasks: 2
  files: 2
---

# Phase 2 Plan 2: Markdown Renderer Summary

GFM Markdown renderer with anchor TOC, per-policy tables, pipe escaping, em dash for nulls, and arrow-marker child setting indentation.

## Tasks Completed

| Task | Description | Commit | Files |
|------|-------------|--------|-------|
| 1 (RED) | Failing Pester tests for ConvertTo-InforcerMarkdown | 9070734 | Tests/Renderers.Tests.ps1 |
| 1 (GREEN) | ConvertTo-InforcerMarkdown + test fix | 3f9e9bb | module/Private/ConvertTo-InforcerMarkdown.ps1, Tests/Renderers.Tests.ps1 |

## What Was Built

### ConvertTo-InforcerMarkdown (`module/Private/ConvertTo-InforcerMarkdown.ps1`)

Private function that accepts `-DocModel [hashtable]` and returns a complete GFM Markdown string. Contains two file-private helper functions:

- **ConvertTo-MarkdownAnchor**: Converts display names to GFM anchor fragments (lowercase, spaces to hyphens, strip non-alphanumeric).
- **ConvertTo-MarkdownTable**: Builds GFM pipe-delimited tables from `-Headers` and `-Rows`. Escapes pipe chars as `\|`, replaces null/empty with em dash (`[char]0x2014`).

Document structure:
1. Header: `# Tenant Documentation: {TenantName}` + generated timestamp + baseline name
2. Two-level TOC: Products with category sub-items as anchor links
3. Per-product `##`, per-category `###`, per-policy `####` headings
4. Basics table (Property/Value, skipping Name since it is the heading)
5. Settings table (only when settings exist; child settings with `[char]0x21B3` arrow prefix per D-08)
6. Assignments table (only when assignments exist)

All assembly uses `[System.Text.StringBuilder]` per module tech stack convention.

### Tests/Renderers.Tests.ps1

Created from scratch (Plan 02-01 had not run yet in this worktree). Contains:
- `Describe 'ConvertTo-InforcerDocJson'` — 1 skipped test (stub for Plan 02-03)
- `Describe 'ConvertTo-InforcerDocCsv'` — 1 skipped test (stub for Plan 02-03)
- `Describe 'ConvertTo-InforcerMarkdown'` with `-Tag 'Markdown'` — 16 tests, all passing

Test coverage: header, timestamp, baseline, TOC product anchors, TOC category sub-items, product/category/policy headings, basics table, settings table, pipe escaping, em dash for nulls, arrow-marker indentation, assignments table, skip-settings-when-empty.

## Verification Results

```
Tests Passed: 16, Failed: 0, Skipped: 0
Module loads OK
No ScriptAnalyzer warnings
```

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed [char]0x2014 in -Match assertion**
- **Found during:** Task 1 TDD GREEN run
- **Issue:** Test used `Should -Match [char]0x2014` — PowerShell passes `[char]0x2014` as a literal regex string pattern, not evaluating the expression. Test failed despite the em dash being present in output.
- **Fix:** Changed to `$emDash = [char]0x2014; Should -Match ([regex]::Escape($emDash))` to pass the actual character to the regex engine.
- **Files modified:** Tests/Renderers.Tests.ps1
- **Commit:** 3f9e9bb

**2. [Rule 2 - Missing correctness] Removed literal non-ASCII from source file**
- **Found during:** ScriptAnalyzer run after GREEN
- **Issue:** Literal em dash `—` in a comment triggered `PSUseBOMForUnicodeEncodedFile` warning. The code itself already used `[char]` expressions correctly, but a comment contained the character.
- **Fix:** Replaced literal em dash in comment with ASCII text. Also replaced the arrow character description in `.DESCRIPTION` with `(U+21B3)`.
- **Files modified:** module/Private/ConvertTo-InforcerMarkdown.ps1
- **Commit:** 3f9e9bb (same commit, included in GREEN)

## Known Stubs

None — the plan's goal (Markdown renderer with full GFM output) is fully implemented and tested.

The JSON/CSV `It -Skip` stubs in `Tests/Renderers.Tests.ps1` are intentional placeholders for Plans 02-03 and are tracked by design.

## Self-Check: PASSED
