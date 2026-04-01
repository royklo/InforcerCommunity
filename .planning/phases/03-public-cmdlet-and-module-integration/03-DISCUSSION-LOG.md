# Phase 3: Public Cmdlet and Module Integration - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-01
**Phase:** 03-public-cmdlet-and-module-integration
**Areas discussed:** Parameter naming, Settings.json discovery, Multi-format output naming, Graceful degradation
**Mode:** Auto (all decisions auto-selected using recommended defaults)

---

## Parameter Naming

| Option | Description | Selected |
|--------|-------------|----------|
| Keep -Format name | Same parameter name as Get-* cmdlets with different ValidateSet (Html/Markdown/Json/Csv). Natural for different verb (Export- vs Get-). | ✓ |
| Use -OutputFormat | Different name to avoid confusion with existing -Format (Raw/Table). Breaks module convention. | |
| Use -DocumentFormat | Descriptive but verbose. Breaks convention. | |

**User's choice:** [auto] Keep -Format name (recommended default)
**Notes:** Module convention puts Format first. Export- is a different verb so different ValidateSet values are expected and natural.

---

## Settings.json Discovery Chain

| Option | Description | Selected |
|--------|-------------|----------|
| Explicit > Bundled > Sibling | Priority chain: -SettingsCatalogPath first, then module/data/settings.json, then sibling repo, then warn. | ✓ |
| Explicit > Sibling only | No bundled copy, always reference sibling repo. Simpler but less portable. | |
| Explicit only (no auto-discover) | Require user to specify path if not bundled. Less convenient. | |

**User's choice:** [auto] Explicit > Bundled > Sibling (recommended default)
**Notes:** Resolves STATE.md blocker. Bundled copy is primary for portability; sibling repo is dev convenience.

---

## Multi-Format Output File Naming

| Option | Description | Selected |
|--------|-------------|----------|
| -OutputPath as directory, auto-name files | Files named {TenantName}-Documentation.{ext}. Single format + extension treated as file path. | ✓ |
| -OutputPath as file prefix | Append extension: path.html, path.md, etc. Less intuitive for directories. | |
| Separate -OutputPath per format | Multiple parameters like -HtmlPath, -MarkdownPath. Too many parameters. | |

**User's choice:** [auto] -OutputPath as directory, auto-name files (recommended default)
**Notes:** Most intuitive for IT admins. Tenant name in filename makes output self-documenting when shared.

---

## Graceful Degradation

| Option | Description | Selected |
|--------|-------------|----------|
| Warn and produce output with raw IDs | Settings Catalog shows raw settingDefinitionId, other policies normal. Write-Warning emitted. | ✓ |
| Error and halt | Terminate if settings.json not found. Prevents incomplete output. | |
| Silent fallback | Proceed without warning. User might not notice missing resolution. | |

**User's choice:** [auto] Warn and produce output with raw IDs (recommended default)
**Notes:** Consistent with SCAT-04 requirement. Non-Settings-Catalog policies are unaffected.

---

## Claude's Discretion

- Internal orchestration flow within the cmdlet
- File encoding choices
- Warning message wording
- Help documentation exact text

## Deferred Ideas

None — discussion stayed within phase scope
