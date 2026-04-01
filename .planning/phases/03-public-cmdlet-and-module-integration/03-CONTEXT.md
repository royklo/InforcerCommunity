# Phase 3: Public Cmdlet and Module Integration - Context

**Gathered:** 2026-04-01
**Status:** Ready for planning

<domain>
## Phase Boundary

Wire the data pipeline (Phase 1) and renderers (Phase 2) into a public `Export-InforcerDocumentation` cmdlet. Update the module manifest to export it, add consistency tests covering the new cmdlet, and write comment-based help documentation with examples. This is the final integration phase that makes the feature user-facing.

</domain>

<decisions>
## Implementation Decisions

### Parameter Design
- **D-01:** Keep `-Format` as the parameter name (module convention: Format first). ValidateSet: `Html`, `Markdown`, `Json`, `Csv`. Accepts multiple values (`[string[]]`). Different ValidateSet than Get-* cmdlets is fine — Export- is a different verb.
- **D-02:** Parameter order follows module convention: `-Format`, `-TenantId`, `-Tag` (future), `-OutputType` (not applicable here — this cmdlet writes files, not pipeline objects). Actual order: `-Format`, `-TenantId`, `-OutputPath`, `-SettingsCatalogPath`.
- **D-03:** `-TenantId` reuses existing `Resolve-InforcerTenantId` for numeric/GUID/name resolution. Required parameter.
- **D-04:** `-OutputPath` accepts a directory path. Files are auto-named as `{TenantName}-Documentation.{ext}` (e.g., `Contoso-Documentation.html`). When a single format is specified and `-OutputPath` has a file extension, treat as a file path.
- **D-05:** `-SettingsCatalogPath` is optional with auto-discovery default.

### Settings.json Discovery Chain
- **D-06:** Discovery priority: (1) Explicit `-SettingsCatalogPath` parameter, (2) Bundled `module/data/settings.json`, (3) Sibling repo `../IntuneSettingsCatalogViewer/data/settings.json` relative to module root, (4) Not found — warn and proceed without Settings Catalog resolution.
- **D-07:** This resolves the STATE.md blocker about settings.json path strategy. The bundled copy is the primary source; sibling repo is dev convenience only.

### Graceful Degradation
- **D-08:** If settings.json is not found, emit `Write-Warning` and proceed. Settings Catalog policies show raw `settingDefinitionId` values. Non-Settings-Catalog policies render normally. Matches existing SCAT-04 requirement behavior.
- **D-09:** If not connected (no `$script:InforcerSession`), emit `Write-Error` and return — same pattern as all other Get-* cmdlets.

### Module Manifest Update
- **D-10:** Add `'Export-InforcerDocumentation'` to `FunctionsToExport` array in `.psd1`. This increases the expected cmdlet count from 10 to 11.

### Consistency Test Updates
- **D-11:** Update `$script:expectedCount` from 10 to 11. Add `Export-InforcerDocumentation` to `$script:expectedNames` and `$script:expectedParameters` with its parameter list.
- **D-12:** Add no-silent-failure test: Export-InforcerDocumentation without connection produces error.
- **D-13:** Add parameter binding test: Export-InforcerDocumentation with all key parameters binds correctly.

### Help Documentation
- **D-14:** Comment-based help following existing cmdlet patterns: .SYNOPSIS, .DESCRIPTION, .PARAMETER (for each), .EXAMPLE (at least 3: basic HTML, multiple formats, custom settings path), .OUTPUTS, .LINK (online URI).

### Claude's Discretion
- Internal orchestration flow within the cmdlet (call order of Get-InforcerDocData, ConvertTo-InforcerDocModel, renderers)
- File encoding choices for Set-Content
- Warning message wording
- Help documentation exact text

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Module Patterns
- `module/Public/Get-InforcerTenantPolicies.ps1` — Existing public cmdlet pattern, parameter conventions, CmdletBinding, session check
- `module/InforcerCommunity.psd1` — Module manifest to update with new export
- `module/InforcerCommunity.psm1` — Module loader, dot-sourcing pattern

### Phase 1 Pipeline Functions
- `module/Private/Get-InforcerDocData.ps1` — Data collection function (input to DocModel builder)
- `module/Private/ConvertTo-InforcerDocModel.ps1` — Builds format-agnostic $DocModel
- `module/Private/Import-InforcerSettingsCatalog.ps1` — Settings.json loader with caching

### Phase 2 Renderer Functions
- `module/Private/ConvertTo-InforcerHtml.ps1` — HTML renderer
- `module/Private/ConvertTo-InforcerMarkdown.ps1` — Markdown renderer
- `module/Private/ConvertTo-InforcerDocJson.ps1` — JSON renderer
- `module/Private/ConvertTo-InforcerDocCsv.ps1` — CSV renderer

### Tests
- `Tests/Consistency.Tests.ps1` — Must be updated for new cmdlet (expectedCount, expectedNames, expectedParameters)

### Requirements
- `.planning/REQUIREMENTS.md` — MOD-01..08

### Prior Phase Context
- `.planning/phases/01-data-pipeline-and-normalization/01-CONTEXT.md` — DocModel shape, settings.json caching, discovery chain decided here
- `.planning/phases/02-output-format-renderers/02-CONTEXT.md` — Renderer signatures, return types, file I/O deferred to Phase 3

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Resolve-InforcerTenantId` — Already handles numeric/GUID/name resolution for -TenantId
- `Test-InforcerSession` — Session validation pattern to reuse
- `Import-InforcerSettingsCatalog` — Settings.json loader with $script: caching
- `Get-InforcerDocData` — Collects all data from 3 cmdlets
- `ConvertTo-InforcerDocModel` — Builds the DocModel
- All 4 renderers — Accept DocModel, return strings

### Established Patterns
- Public cmdlets in `module/Public/` with CmdletBinding and comment-based help
- Session check via `Test-InforcerSession` at start of each cmdlet
- Error handling: `Write-Error -ErrorId -Category` for non-terminating errors
- All existing Get-* cmdlets follow Format → TenantId → ... → OutputType parameter order
- Consistency tests hardcode expected count (currently 10) and expected parameter names

### Integration Points
- New `Export-InforcerDocumentation.ps1` goes in `module/Public/`
- Auto dot-sourced by `.psm1` (no loader changes needed)
- Must be added to `.psd1` FunctionsToExport array
- Consistency tests must be updated (count, names, parameters)

</code_context>

<specifics>
## Specific Ideas

- The cmdlet is the user-facing entry point — it should be a clean, simple orchestrator that calls the pipeline functions and writes files
- IT admins will primarily use `-Format Html` for shareable reports and `-Format Json` for automation
- The settings.json discovery chain resolves the last open blocker from STATE.md
- File naming with tenant name makes output files self-documenting when shared

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope

</deferred>

---

*Phase: 03-public-cmdlet-and-module-integration*
*Context gathered: 2026-04-01*
