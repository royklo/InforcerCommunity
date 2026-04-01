# Phase 3: Public Cmdlet and Module Integration - Research

**Researched:** 2026-04-01
**Domain:** PowerShell public cmdlet authoring, module manifest management, Pester consistency tests, comment-based help
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** `-Format` parameter (module convention: Format first). ValidateSet: `Html`, `Markdown`, `Json`, `Csv`. Accepts multiple values (`[string[]]`). Different ValidateSet than Get-* cmdlets is fine.
- **D-02:** Parameter order: `-Format`, `-TenantId`, `-OutputPath`, `-SettingsCatalogPath`.
- **D-03:** `-TenantId` reuses `Resolve-InforcerTenantId` for numeric/GUID/name resolution. Required parameter.
- **D-04:** `-OutputPath` accepts a directory path. Files auto-named as `{TenantName}-Documentation.{ext}`. When single format + `-OutputPath` has file extension, treat as file path.
- **D-05:** `-SettingsCatalogPath` is optional with auto-discovery default.
- **D-06:** Discovery priority: (1) Explicit `-SettingsCatalogPath`, (2) Bundled `module/data/settings.json`, (3) Sibling repo `../IntuneSettingsCatalogViewer/data/settings.json` relative to module root, (4) Not found — warn and proceed.
- **D-07:** Bundled copy is primary source; sibling repo is dev convenience only.
- **D-08:** If settings.json not found, emit `Write-Warning` and proceed. Settings Catalog policies show raw `settingDefinitionId`. Non-Settings-Catalog policies render normally.
- **D-09:** If not connected, emit `Write-Error` and return — same pattern as all other Get-* cmdlets.
- **D-10:** Add `'Export-InforcerDocumentation'` to `FunctionsToExport` in `.psd1`. Count goes 10 → 11.
- **D-11:** Update `$script:expectedCount` to 11. Add `Export-InforcerDocumentation` to `$script:expectedNames` and `$script:expectedParameters`.
- **D-12:** Add no-silent-failure test: Export-InforcerDocumentation without connection produces error.
- **D-13:** Add parameter binding test: Export-InforcerDocumentation with all key parameters binds correctly.
- **D-14:** Comment-based help: .SYNOPSIS, .DESCRIPTION, .PARAMETER (each), .EXAMPLE (min 3), .OUTPUTS, .LINK.

### Claude's Discretion

- Internal orchestration flow within the cmdlet (call order of Get-InforcerDocData, ConvertTo-InforcerDocModel, renderers)
- File encoding choices for Set-Content
- Warning message wording
- Help documentation exact text

### Deferred Ideas (OUT OF SCOPE)

None — discussion stayed within phase scope.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| MOD-01 | Export-InforcerDocumentation follows module conventions (parameter order, session auth, error handling) | Existing pattern from Get-InforcerTenantPolicies.ps1; Test-InforcerSession + Resolve-InforcerTenantId already reusable |
| MOD-02 | Cmdlet accepts -TenantId (numeric, GUID, or name) consistent with other cmdlets | Resolve-InforcerTenantId already handles all three; same try/catch pattern as other cmdlets |
| MOD-03 | Cmdlet accepts -Format supporting Html, Markdown, Json, Csv (multiple allowed) | [string[]] with ValidateSet; Get-* cmdlets use [string] but Export-* can accept array |
| MOD-04 | Cmdlet accepts -OutputPath for file destination | Directory-or-file detection via System.IO.Path.HasExtension(); Set-Content for writing |
| MOD-05 | Cmdlet accepts -SettingsCatalogPath with auto-discover default | Discovery chain already implemented in Import-InforcerSettingsCatalog; Phase 3 adds sibling-repo tier |
| MOD-06 | Module manifest updated with new cmdlet export | FunctionsToExport array in InforcerCommunity.psd1 — append 'Export-InforcerDocumentation' |
| MOD-07 | Consistency tests updated for new cmdlet | Consistency.Tests.ps1: expectedCount, expectedNames, expectedParameters, no-silent-failure It block, parameter binding It block |
| MOD-08 | Cmdlet help documentation with examples | Comment-based help following existing pattern in Get-InforcerTenantPolicies.ps1 |
</phase_requirements>

---

## Summary

Phase 3 is an integration and wiring phase — all the heavy lifting (data pipeline, renderers) is done. The task is to create one public cmdlet file (`Export-InforcerDocumentation.ps1`), update two existing files (`.psd1` manifest and `Consistency.Tests.ps1`), and write help documentation inline with the cmdlet.

The existing module infrastructure is fully understood and fully reusable. The psm1 auto-dots-sources all `.ps1` files in `module/Public/` and `module/Private/` — dropping a new file in the right place is all that's needed for the loader. The manifest needs only one string appended to `FunctionsToExport`. The consistency tests follow an exact pattern for adding new cmdlets.

**Primary recommendation:** Create `module/Public/Export-InforcerDocumentation.ps1` as a thin orchestrator calling the established pipeline (Get-InforcerDocData -> ConvertTo-InforcerDocModel -> renderers). The only net-new logic is: (a) the settings.json discovery chain tier 3 (sibling repo), (b) OutputPath resolution (directory vs. file), and (c) file writing via `Set-Content`.

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `[CmdletBinding()]` + `param()` | PS 7.0+ built-in | Standard advanced function declaration | Module convention — every public cmdlet uses this |
| `Test-InforcerSession` | Module private | Session guard at function entry | Established pattern in all Get-* cmdlets (D-09) |
| `Resolve-InforcerTenantId` | Module private | TenantId resolution | Established pattern; handles int/GUID/name (D-03) |
| `Import-InforcerSettingsCatalog` | Module private | Load settings.json once | Already wired in Get-InforcerDocData — called with optional -Path |
| `Get-InforcerDocData` | Module private | Collect raw API data | Phase 1 output; accepts TenantId + SettingsCatalogPath |
| `ConvertTo-InforcerDocModel` | Module private | Build format-agnostic model | Phase 1 output; accepts DocData hashtable |
| `ConvertTo-InforcerHtml` | Module private | Render HTML string | Phase 2 output; accepts DocModel |
| `ConvertTo-InforcerMarkdown` | Module private | Render Markdown string | Phase 2 output; accepts DocModel |
| `ConvertTo-InforcerDocJson` | Module private | Render JSON string | Phase 2 output; accepts DocModel |
| `ConvertTo-InforcerDocCsv` | Module private | Render CSV string | Phase 2 output; accepts DocModel |
| `Set-Content` | PS 7.0+ built-in | Write output files | Standard PS file writing; `-Encoding UTF8` per module convention |
| `[System.IO.Path]::HasExtension()` | .NET 8 built-in | Detect file vs. directory path | Reliable; no regex needed |

### File Extension Mapping
| Format value | File extension | Renderer function |
|---|---|---|
| `Html` | `.html` | `ConvertTo-InforcerHtml` |
| `Markdown` | `.md` | `ConvertTo-InforcerMarkdown` |
| `Json` | `.json` | `ConvertTo-InforcerDocJson` |
| `Csv` | `.csv` | `ConvertTo-InforcerDocCsv` |

---

## Architecture Patterns

### Recommended Project Structure (Phase 3 additions only)

```
module/
├── Public/
│   └── Export-InforcerDocumentation.ps1    # NEW - public cmdlet
├── InforcerCommunity.psd1                  # EDIT - append to FunctionsToExport
Tests/
└── Consistency.Tests.ps1                   # EDIT - count, names, params, new It blocks
```

### Pattern 1: Standard Public Cmdlet Shell

Every public cmdlet in this module follows exactly this shape (verified from Get-InforcerTenantPolicies.ps1):

```powershell
# Source: module/Public/Get-InforcerTenantPolicies.ps1
function Export-InforcerDocumentation {
[CmdletBinding()]
[OutputType([void])]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Html', 'Markdown', 'Json', 'Csv')]
    [string[]]$Format = @('Html'),

    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [Alias('ClientTenantId')]
    [object]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = '.',

    [Parameter(Mandatory = $false)]
    [string]$SettingsCatalogPath
)

# Session guard (D-09)
if (-not (Test-InforcerSession)) {
    Write-Error -Message 'Not connected yet. Please run Connect-Inforcer first.' `
        -ErrorId 'NotConnected' -Category ConnectionError
    return
}

# TenantId resolution (D-03)
try {
    $clientTenantId = Resolve-InforcerTenantId -TenantId $TenantId
} catch {
    Write-Error -Message $_.Exception.Message -ErrorId 'InvalidTenantId' -Category InvalidArgument
    return
}
# ... orchestration continues
}
```

**Key observations from reading existing cmdlets:**
- `Write-Error -ErrorId 'NotConnected' -Category ConnectionError` — exact string used everywhere
- `return` after `Write-Error` — non-terminating, caller controls `-ErrorAction`
- Parameters declared in order: Format → TenantId → ... per consistency contract
- `[Alias('ClientTenantId')]` on TenantId — present in all tenant-scoped cmdlets

### Pattern 2: OutputPath Resolution

D-04 requires: directory path → auto-name files; single format + file extension in `-OutputPath` → treat as explicit file path.

```powershell
# Determine output file path for a given format
function Resolve-OutputFilePath {
    param([string]$OutputPath, [string]$Format, [string]$TenantName)
    $ext = @{ Html = 'html'; Markdown = 'md'; Json = 'json'; Csv = 'csv' }[$Format]
    if ([System.IO.Path]::HasExtension($OutputPath) -and $Format.Count -eq 1) {
        # Caller gave an explicit file path
        return $OutputPath
    }
    # Directory path — auto-name
    $safeName = $TenantName -replace '[^\w\-]', '-'
    return Join-Path $OutputPath "$safeName-Documentation.$ext"
}
```

Note: this logic lives *inside* `Export-InforcerDocumentation` (not a separate private function — it's 5 lines). For the single-format file-path detection, check `$Format.Count -eq 1` AND `[System.IO.Path]::HasExtension($OutputPath)`.

### Pattern 3: Settings.json Discovery Chain (D-06)

Import-InforcerSettingsCatalog currently handles tiers 1 (explicit path) and 2 (module/data/settings.json). **Tier 3 (sibling repo) must be added in Phase 3** — either by extending `Import-InforcerSettingsCatalog` or by resolving the path in `Export-InforcerDocumentation` before calling it.

Recommended approach: resolve in the public cmdlet, then pass to `Get-InforcerDocData -SettingsCatalogPath`. This keeps `Import-InforcerSettingsCatalog` unaware of project layout conventions.

```powershell
# Discovery chain (D-06)
$resolvedCatalogPath = $SettingsCatalogPath  # tier 1: explicit
if ([string]::IsNullOrEmpty($resolvedCatalogPath)) {
    # tier 2: bundled copy
    $bundled = Join-Path $PSScriptRoot '..' 'data' 'settings.json'
    $bundled = [System.IO.Path]::GetFullPath($bundled)
    if (Test-Path -LiteralPath $bundled) { $resolvedCatalogPath = $bundled }
}
if ([string]::IsNullOrEmpty($resolvedCatalogPath)) {
    # tier 3: sibling repo (dev convenience)
    $sibling = Join-Path $PSScriptRoot '..' '..' '..' 'IntuneSettingsCatalogViewer' 'data' 'settings.json'
    $sibling = [System.IO.Path]::GetFullPath($sibling)
    if (Test-Path -LiteralPath $sibling) { $resolvedCatalogPath = $sibling }
}
if ([string]::IsNullOrEmpty($resolvedCatalogPath)) {
    # tier 4: not found — warn and proceed (D-08)
    Write-Warning 'Settings catalog (settings.json) not found. Settings Catalog policies will show raw settingDefinitionId values.'
}
```

Note: `$PSScriptRoot` in a Public cmdlet file resolves to `module/Public/`. The path to `module/data/` is `Join-Path $PSScriptRoot '..' 'data' 'settings.json'`. The sibling repo path would be three levels up (`Public -> module -> InforcerCommunity -> IntuneSettingsCatalogViewer`).

### Pattern 4: Manifest Update

The `.psd1` `FunctionsToExport` is a simple string array. Add one entry:

```powershell
# Source: module/InforcerCommunity.psd1 (current)
FunctionsToExport = @(
    'Connect-Inforcer'
    'Disconnect-Inforcer'
    'Test-InforcerConnection'
    'Get-InforcerTenant'
    'Get-InforcerBaseline'
    'Get-InforcerTenantPolicies'
    'Get-InforcerAlignmentDetails'
    'Get-InforcerAuditEvent'
    'Get-InforcerSupportedEventType'
    'Get-InforcerUser'
    'Export-InforcerDocumentation'   # ADD
)
```

### Pattern 5: Consistency.Tests.ps1 Update

Three additions needed (D-11, D-12, D-13):

**a) In `BeforeAll` of `Describe 'Consistency contract'`:**

```powershell
$script:expectedCount = 11   # was 10

$script:expectedNames = @(
    'Connect-Inforcer', 'Disconnect-Inforcer', 'Test-InforcerConnection',
    'Get-InforcerTenant', 'Get-InforcerBaseline', 'Get-InforcerTenantPolicies',
    'Get-InforcerAlignmentDetails', 'Get-InforcerAuditEvent', 'Get-InforcerSupportedEventType',
    'Get-InforcerUser',
    'Export-InforcerDocumentation'   # ADD
)

$script:expectedParameters = @{
    # ... existing entries unchanged ...
    'Export-InforcerDocumentation' = @('Format', 'TenantId', 'OutputPath', 'SettingsCatalogPath')   # ADD
}
```

**b) In `Describe 'No-silent-failure contract'`** — add one It block:

```powershell
It 'Export-InforcerDocumentation produces an error when not connected' {
    $err = $null
    Export-InforcerDocumentation -TenantId 1 -ErrorVariable err -ErrorAction SilentlyContinue
    $err | Should -Not -BeNullOrEmpty -Because 'should report not connected, not return silence'
}
```

**c) In `Describe 'Parameter binding and behavior'`** — add one It block:

```powershell
It 'Export-InforcerDocumentation with key parameters binds and produces output or error' {
    $out = @(); $err = @()
    $out = Export-InforcerDocumentation -Format Html -TenantId 1 -OutputPath $TestDrive `
        -ErrorVariable err -ErrorAction SilentlyContinue
    $err = @($err)
    $hasOutput = $null -ne $out
    $hasError = $err.Count -gt 0
    ($hasOutput -or $hasError) | Should -BeTrue -Because 'Export-InforcerDocumentation must not silently do nothing'
    if ($hasError -and $err[0].ToString() -match 'Cannot bind|Parameter.*not found|Unknown parameter') {
        Set-ItResult -Inconclusive -Because 'Parameter binding failed; check parameter names'
    }
}
```

Note: `$TestDrive` is a Pester 5 built-in that provides a temp directory — use it for `-OutputPath` to avoid creating real files in CI.

### Pattern 6: Comment-Based Help Structure

Exact structure required by existing `'Every exported cmdlet has complete Get-Help'` test (line 90-115 of Consistency.Tests.ps1):

- `.SYNOPSIS` — must be non-empty
- `.DESCRIPTION` — must be non-empty
- `.PARAMETER <name>` — must exist for EVERY declared parameter (checked by test)
- `.EXAMPLE` — at least one (checked by test)
- `.OUTPUTS`
- `.LINK https://...` — first URI must be HTTPS (checked by test, line 113)

Required `.LINK` pattern (from Get-InforcerTenantPolicies.ps1):
```powershell
.LINK
    https://github.com/royklo/InforcerCommunity/blob/main/docs/CMDLET-REFERENCE.md#export-inforcerdocumentation
.LINK
    Connect-Inforcer
```

The first `.LINK` must be an HTTPS URL. The second `.LINK` with `Connect-Inforcer` is the pattern used by data-collection cmdlets.

**Parameters to document** (from D-02): `Format`, `TenantId`, `OutputPath`, `SettingsCatalogPath`.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| TenantId type resolution | Custom int/GUID/name detection | `Resolve-InforcerTenantId` | Already handles all 3 cases with proper error messages |
| Session validation | `$null -ne $script:InforcerSession` check inline | `Test-InforcerSession` | Encapsulates SecureString length check, BaseUrl check |
| File path sanitization | Custom regex replacement | `$TenantName -replace '[^\w\-]', '-'` | Simple one-liner sufficient; no external sanitizer needed |
| Settings catalog loading | Custom JSON reader | `Import-InforcerSettingsCatalog` (call via `Get-InforcerDocData`) | Already handles caching, error reporting, format |
| HTML/MD/JSON/CSV generation | Any new rendering logic | Phase 2 renderers | All 4 renderers are complete and tested |
| Module auto-loading | Manually update psm1 | psm1 auto-dots-sources all Public/*.ps1 | No loader changes needed at all |

**Key insight:** This phase is almost entirely wiring. The only net-new code is: discovery chain tier 3, OutputPath resolution, file write loop, and the manifest/test file edits.

---

## Common Pitfalls

### Pitfall 1: $PSScriptRoot Resolution in Public Cmdlet
**What goes wrong:** Using `$PSScriptRoot` inside the body of `Export-InforcerDocumentation` resolves to `module/Public/` at dot-source time. The path to `module/data/` is `../data/` from there, not `./data/`.
**Why it happens:** The psm1 dot-sources the file, so `$PSScriptRoot` captures the directory of the `.ps1` file.
**How to avoid:** Use `Join-Path $PSScriptRoot '..' 'data' 'settings.json'` and wrap with `[System.IO.Path]::GetFullPath()` to canonicalize.
**Warning signs:** `Test-Path` returns `$false` for the bundled path even when `module/data/settings.json` exists.

### Pitfall 2: OutputPath Directory Not Existing
**What goes wrong:** `Set-Content` will throw if the parent directory of the output path does not exist.
**Why it happens:** `-OutputPath` is user-supplied; user may provide a new directory.
**How to avoid:** Call `New-Item -ItemType Directory -Force -Path $OutputPath` (or `$OutputPath | Split-Path -Parent`) before writing. `-Force` is idempotent if dir already exists.
**Warning signs:** `Set-Content: Cannot find path` error at runtime.

### Pitfall 3: Format Parameter Collision with Existing Consistency Test
**What goes wrong:** The existing consistency test at line 73-80 (`'Get-* cmdlets that return API data have -Format and -OutputType'`) only checks Get-* cmdlets — Export-InforcerDocumentation is NOT in that list and should NOT be added there. However, `Export-InforcerDocumentation` does have `-Format` (no `-OutputType`). The test is scoped to specific Get-* names, so no conflict exists — but be careful not to add it to that list.
**Why it happens:** Export- verb cmdlets write files; they don't have `-OutputType` (JsonObject/PowerShellObject).
**How to avoid:** Only add to `$expectedNames`, `$expectedParameters`, and the two new It blocks. Do not modify the `'Get-* cmdlets that return API data'` It block.

### Pitfall 4: $TestDrive Scope in Pester 5
**What goes wrong:** `$TestDrive` is a Pester 5 built-in that resolves to a per-test temp directory. It is only available inside `It` blocks (and `BeforeAll`/`BeforeEach` within a Describe). Using it at `Describe` scope level will produce `$null`.
**Why it happens:** Pester 5 injects it at run-time scope.
**How to avoid:** Use `$TestDrive` directly inside the `It` block body for `-OutputPath`. Or use `$env:TEMP` as a fallback if `$TestDrive` is null.

### Pitfall 5: [OutputType] Declaration for File-Writing Cmdlets
**What goes wrong:** Declaring `[OutputType([string])]` when the cmdlet writes files and returns nothing causes misleading type info. The cmdlet should output nothing to the pipeline (or optionally output file paths if `-PassThru` were added — but that's not in scope).
**Why it happens:** Confusion with Get-* cmdlets that do return values.
**How to avoid:** Use `[OutputType([void])]` or omit `[OutputType]` entirely. The consistency test does not check OutputType for Export- cmdlets.

### Pitfall 6: ConvertTo-InforcerDocCsv Returns String, Not File
**What goes wrong:** All 4 renderers return strings (per Phase 2 design). They do NOT write files. File writing is exclusively Phase 3's responsibility.
**Why it happens:** Phase 2 deferred file I/O to Phase 3 by design.
**How to avoid:** The write loop in Export-InforcerDocumentation must call `Set-Content -Path $filePath -Value $renderedString -Encoding UTF8` for each format. Never pipe renderer output directly to disk without `Set-Content`.

### Pitfall 7: Get-InforcerDocData Already Calls Import-InforcerSettingsCatalog Internally
**What goes wrong:** Calling `Import-InforcerSettingsCatalog` in Export-InforcerDocumentation AND having Get-InforcerDocData also call it causes a double-load attempt. The second call is a no-op (cache guard), but the path resolution happens in `Get-InforcerDocData`, not in the public cmdlet.
**Why it happens:** Get-InforcerDocData accepts `$SettingsCatalogPath` and passes it to `Import-InforcerSettingsCatalog`. The public cmdlet should pass the resolved path to `Get-InforcerDocData`, not call the importer directly.
**How to avoid:** Resolve the discovery chain in Export-InforcerDocumentation, pass the resolved path to `Get-InforcerDocData -SettingsCatalogPath $resolvedCatalogPath`. Let Get-InforcerDocData handle the actual import. Only emit `Write-Warning` in the public cmdlet when `$resolvedCatalogPath` is empty (tier 4 fallback).

---

## Code Examples

### File Write Loop (orchestrator body)

```powershell
# Source: Phase 3 design — informed by ConvertTo-InforcerDocJson.ps1 return contract
$extensionMap = @{ Html = 'html'; Markdown = 'md'; Json = 'json'; Csv = 'csv' }

foreach ($fmt in $Format) {
    $ext = $extensionMap[$fmt]

    # Resolve output file path (D-04)
    if ($Format.Count -eq 1 -and [System.IO.Path]::HasExtension($OutputPath)) {
        $filePath = $OutputPath
    } else {
        $safeName = $DocModel.TenantName -replace '[^\w\-]', '-'
        $filePath = Join-Path $OutputPath "$safeName-Documentation.$ext"
    }

    # Ensure parent directory exists
    $parentDir = Split-Path -Parent $filePath
    if (-not [string]::IsNullOrEmpty($parentDir) -and -not (Test-Path -LiteralPath $parentDir)) {
        [void](New-Item -ItemType Directory -Force -Path $parentDir)
    }

    # Render and write
    $content = switch ($fmt) {
        'Html'     { ConvertTo-InforcerHtml     -DocModel $DocModel }
        'Markdown' { ConvertTo-InforcerMarkdown -DocModel $DocModel }
        'Json'     { ConvertTo-InforcerDocJson  -DocModel $DocModel }
        'Csv'      { ConvertTo-InforcerDocCsv   -DocModel $DocModel }
    }

    Set-Content -Path $filePath -Value $content -Encoding UTF8
    Write-Verbose "Wrote $fmt documentation to: $filePath"
}
```

### Comment-Based Help Skeleton (minimum viable for tests)

```powershell
<#
.SYNOPSIS
    Generates comprehensive tenant documentation across all M365 products managed via Inforcer.
.DESCRIPTION
    Collects tenant configuration data from Get-InforcerBaseline, Get-InforcerTenant, and
    Get-InforcerTenantPolicies, normalizes it into a structured DocModel, and renders output
    files in the specified format(s). Settings Catalog settingDefinitionIDs are resolved to
    friendly names using a local settings.json lookup table.

    Requires an active Inforcer session (Connect-Inforcer).
.PARAMETER Format
    Output format(s) to generate. Accepted values: Html, Markdown, Json, Csv.
    Multiple formats can be specified. Defaults to Html.
.PARAMETER TenantId
    Tenant to document. Accepts a numeric ID, GUID, or tenant name.
.PARAMETER OutputPath
    Directory to write output files to. Files are auto-named {TenantName}-Documentation.{ext}.
    When a single format is specified and this path has a file extension, it is treated as
    an explicit output file path. Defaults to the current directory.
.PARAMETER SettingsCatalogPath
    Path to the IntuneSettingsCatalog settings.json file. When omitted, the cmdlet searches:
    1. module/data/settings.json (bundled copy), 2. sibling IntuneSettingsCatalogViewer repo.
    If not found, Settings Catalog policies show raw settingDefinitionId values.
.OUTPUTS
    None. Files are written to OutputPath.
.EXAMPLE
    Export-InforcerDocumentation -TenantId 482 -Format Html
    # Writes Contoso-Documentation.html to the current directory.
.EXAMPLE
    Export-InforcerDocumentation -TenantId 482 -Format Html,Markdown,Json,Csv -OutputPath C:\Reports
    # Writes four documentation files to C:\Reports.
.EXAMPLE
    Export-InforcerDocumentation -TenantId "Contoso" -Format Html -SettingsCatalogPath .\settings.json
    # Uses an explicit settings.json path for Settings Catalog resolution.
.LINK
    https://github.com/royklo/InforcerCommunity/blob/main/docs/CMDLET-REFERENCE.md#export-inforcerdocumentation
.LINK
    Connect-Inforcer
#>
```

---

## Runtime State Inventory

Step 2.5: SKIPPED — this is a greenfield additive phase, not a rename/refactor/migration.

---

## Environment Availability

Step 2.6: SKIPPED — this phase has no external dependencies. All required components are PowerShell built-ins and module-internal private functions already present in the repository.

---

## Validation Architecture

`workflow.nyquist_validation` is explicitly `false` in `.planning/config.json`. This section is skipped.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `FunctionsToExport = '*'` (wildcard) | Explicit function name list | Module maturity | Consistency test validates count == 11 exactly; wildcards would break this |
| Per-cmdlet file writing in renderer | Renderers return strings; public cmdlet writes | Phase 2 design decision | Clean separation of concerns; renderers are unit-testable without disk I/O |

---

## Open Questions

1. **OutputPath default behavior when path doesn't exist and multiple formats**
   - What we know: `New-Item -Force -ItemType Directory` is idempotent and safe
   - What's unclear: Should the cmdlet auto-create nested directories (e.g., `C:\Reports\2026\April`) or only single-level?
   - Recommendation: Use `-Force` which handles any depth; document in help that the directory is created if absent. No user decision needed — standard PS behavior.

2. **Verbose output for multi-format runs**
   - What we know: Existing cmdlets use `Write-Verbose` sparingly
   - What's unclear: Whether to emit a `Write-Host` summary of files written (some cmdlets do, some don't)
   - Recommendation: Use `Write-Verbose` only (no `Write-Host`). IT admins can use `-Verbose` to see file paths. This is Claude's discretion per CONTEXT.md.

---

## Sources

### Primary (HIGH confidence)
- `module/Public/Get-InforcerTenantPolicies.ps1` — public cmdlet parameter pattern, session guard, error handling, comment-based help structure verified by direct read
- `module/InforcerCommunity.psd1` — current FunctionsToExport array (10 entries) verified by direct read
- `Tests/Consistency.Tests.ps1` — exact test structure, assertion patterns for count/names/params/help verified by direct read
- `module/Private/Get-InforcerDocData.ps1` — accepts SettingsCatalogPath, calls Import-InforcerSettingsCatalog internally, verified by direct read
- `module/Private/Import-InforcerSettingsCatalog.ps1` — default path uses `$PSScriptRoot` relative to Private/, verified by direct read
- `module/Private/ConvertTo-InforcerHtml.ps1`, `ConvertTo-InforcerMarkdown.ps1`, `ConvertTo-InforcerDocJson.ps1`, `ConvertTo-InforcerDocCsv.ps1` — all return strings, accept `[hashtable]$DocModel`, verified by direct read
- `module/InforcerCommunity.psm1` — auto-dot-sources all Public/*.ps1 and Private/*.ps1, verified by direct read

### Secondary (MEDIUM confidence)
- `.planning/phases/03-public-cmdlet-and-module-integration/03-CONTEXT.md` — locked decisions D-01 through D-14
- `.planning/REQUIREMENTS.md` — MOD-01 through MOD-08 requirement text
- `CLAUDE.md` (project root + InforcerCommunity/) — stack conventions, consistency contract

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all components verified by direct file reads; no external dependencies
- Architecture patterns: HIGH — all patterns derived from existing code in repository
- Pitfalls: HIGH — pitfalls derived from reading actual implementation files and test assertions
- Manifest update: HIGH — current state verified, change is additive (one string)
- Test update: HIGH — test structure fully read; exact BeforeAll vars, It block patterns confirmed

**Research date:** 2026-04-01
**Valid until:** 2026-05-01 (stable codebase, no fast-moving dependencies)
