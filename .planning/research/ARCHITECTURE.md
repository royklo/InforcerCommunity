# Architecture Patterns

**Domain:** PowerShell documentation export cmdlet within existing InforcerCommunity module
**Researched:** 2026-04-01

---

## Recommended Architecture

The cmdlet follows a four-stage linear pipeline: **Collect → Normalize → Render → Emit**.
Each stage is implemented as one or more private helpers. The public cmdlet (`Export-InforcerDocumentation`) orchestrates the pipeline and owns the parameter interface; it contains no rendering or transformation logic itself.

```
┌──────────────────────────────────────────────────────────────────┐
│  Export-InforcerDocumentation  (Public / Orchestrator)           │
│  Parameters: -TenantId, -OutputFormat, -OutputPath, -BaselineId  │
└────────────────────┬─────────────────────────────────────────────┘
                     │ calls
        ┌────────────▼──────────────┐
        │   STAGE 1: Data Collection │
        │   Get-InforcerDocData      │  ← private helper
        │   (calls 3 public cmdlets) │
        └────────────┬──────────────┘
                     │ returns $DocData hashtable
        ┌────────────▼──────────────┐
        │  STAGE 2: Normalization   │
        │  ConvertTo-InforcerDocModel│  ← private helper
        │  + Resolve-SettingName     │  ← private helper (settings.json lookup)
        └────────────┬──────────────┘
                     │ returns $DocModel (typed PSCustomObject tree)
        ┌────────────▼──────────────┐
        │  STAGE 3: Rendering       │
        │  ConvertTo-InforcerHtml   │  \
        │  ConvertTo-InforcerMarkdown│   ├── private helpers, one per format
        │  (JSON/CSV use built-ins) │  /
        └────────────┬──────────────┘
                     │ returns string (rendered output)
        ┌────────────▼──────────────┐
        │  STAGE 4: Emission        │
        │  Write to -OutputPath     │
        │  or return to pipeline    │
        └───────────────────────────┘
```

---

## Component Boundaries

| Component | File (suggested) | Responsibility | Communicates With |
|-----------|------------------|---------------|-------------------|
| `Export-InforcerDocumentation` | `Public/Export-InforcerDocumentation.ps1` | Parameter validation, session guard, pipeline orchestration, progress reporting | All private helpers below |
| `Get-InforcerDocData` | `Private/Get-InforcerDocData.ps1` | Calls `Get-InforcerTenant`, `Get-InforcerBaseline`, `Get-InforcerTenantPolicies` with `-OutputType JsonObject`; returns raw data bundle | `Get-InforcerTenant`, `Get-InforcerBaseline`, `Get-InforcerTenantPolicies` |
| `Import-InforcerSettingsCatalog` | `Private/Import-InforcerSettingsCatalog.ps1` | Loads and indexes settings.json once per session into `$script:` scope hashtable keyed by `id` | File system / `$script:` scope |
| `Resolve-InforcerSettingName` | `Private/Resolve-InforcerSettingName.ps1` | Maps a `settingDefinitionId` to `displayName` + `description` using the in-memory index; returns fallback label on miss | `$script:InforcerSettingsCatalog` hashtable |
| `ConvertTo-InforcerDocModel` | `Private/ConvertTo-InforcerDocModel.ps1` | Deserializes raw JSON, applies product categorization, calls `Resolve-InforcerSettingName` for each Settings Catalog setting, builds the normalized `$DocModel` tree | `Resolve-InforcerSettingName` |
| `ConvertTo-InforcerHtmlDoc` | `Private/ConvertTo-InforcerHtmlDoc.ps1` | Transforms `$DocModel` into HTML string; owns all HTML/CSS/JS markup; collapsible TOC, product sections, per-policy Basics/Settings/Assignments tables | `$DocModel` (read-only) |
| `ConvertTo-InforcerMarkdownDoc` | `Private/ConvertTo-InforcerMarkdownDoc.ps1` | Transforms `$DocModel` into Markdown string; TOC anchors, GFM tables | `$DocModel` (read-only) |
| JSON output | (no helper needed) | `$DocModel \| ConvertTo-Json -Depth 100` inline in orchestrator | Built-in cmdlet |
| CSV output | `Private/ConvertTo-InforcerCsvRows.ps1` | Flattens `$DocModel` settings into array of flat PSObjects; `Export-Csv` or `ConvertTo-Csv` in orchestrator | `$DocModel` (read-only) |

---

## Data Flow: Raw API JSON → Normalized Model → Format Output

### Stage 1: Data Collection

`Get-InforcerDocData` calls all three cmdlets with `-OutputType JsonObject` and returns a single hashtable:

```powershell
$DocData = @{
    TenantJson   = <string>   # from Get-InforcerTenant -TenantId $x -OutputType JsonObject
    BaselineJson = <string>   # from Get-InforcerBaseline -TenantId $x -OutputType JsonObject
    PoliciesJson = <string>   # from Get-InforcerTenantPolicies -TenantId $x -OutputType JsonObject
    CollectedAt  = [datetime]::UtcNow
}
```

Using `-OutputType JsonObject` is the right choice here: it gives depth-100 JSON strings that preserve full nesting (assignments, policyData, settings arrays) without PowerShell's automatic object truncation.

### Stage 2: Normalization — the $DocModel shape

`ConvertTo-InforcerDocModel` deserializes the JSON strings and produces a typed PSCustomObject tree. The model is format-agnostic (no HTML/MD in this layer).

```
$DocModel
├── .Tenant         PSCustomObject   (name, dnsName, id, licences, generatedAt)
├── .Baselines      PSCustomObject[] (id, name, members[])
└── .Products       PSCustomObject[] — one per distinct `product` value in policies
    ├── .ProductName  string
    ├── .PrimaryGroups PSCustomObject[]
    │   ├── .Name    string  (primaryGroup value)
    │   └── .Policies PSCustomObject[]
    │       ├── .PolicyName  string
    │       ├── .PolicyId    string
    │       ├── .Platform    string
    │       ├── .Description string
    │       ├── .Tags        string
    │       ├── .CreatedDateTime / .ModifiedDateTime
    │       ├── .Settings    PSCustomObject[]   ← resolved names
    │       │   ├── .SettingId      string (raw settingDefinitionId)
    │       │   ├── .DisplayName    string (from settings.json or fallback)
    │       │   ├── .Description    string
    │       │   ├── .Value          string/object
    │       │   ├── .ValueLabel     string (option displayName when choice setting)
    │       │   └── .Depth          int    (0=root, 1=child)
    │       └── .Assignments PSCustomObject[]
    │           ├── .GroupId   string
    │           ├── .GroupName string
    │           └── .Intent    string
```

The categorization key is `product` + `primaryGroup` (both already present in the policy API response). No inference needed.

### Stage 2b: Settings Catalog Resolution

The `policyData` blob inside each policy contains settings as `{ settingDefinitionId, settingValue }` pairs. The resolver:

1. On first call, `Import-InforcerSettingsCatalog` reads `settings.json` and builds:
   ```powershell
   $script:InforcerSettingsCatalog = @{}   # keyed by id (lowercased)
   # Each entry: @{ displayName=; description=; options=@{itemId=displayName} }
   ```
   17,785 entries at ~1.5 MB JSON — load once and cache in `$script:` scope (same session lifetime as `$script:InforcerSession`).

2. `Resolve-InforcerSettingName` returns `@{ DisplayName=; Description=; ValueLabel= }`.
   On miss (unknown `settingDefinitionId`), returns `@{ DisplayName=$settingDefinitionId; Description=''; ValueLabel='' }` — never throws.

3. The path to `settings.json` defaults to the module-relative path (bundled) or a caller-supplied `-SettingsCatalogPath` override parameter on `Export-InforcerDocumentation`.

### Stage 3: Rendering

Each renderer receives `$DocModel` and returns a `[string]`. Renderers are pure functions — no I/O, no API calls, no side effects.

**HTML renderer responsibilities:**
- Inline CSS + minimal vanilla JS (no CDN dependency — offline-safe)
- Collapsible `<details>/<summary>` elements for product sections and per-policy blocks
- TOC collapsed by default; product anchors use `id` attributes
- Per-policy three-section layout: Basics table, Settings table, Assignments table

**Markdown renderer responsibilities:**
- GFM table syntax for settings/assignments
- `## Product` / `### Policy` heading hierarchy
- Anchor-compatible heading text for TOC links

**JSON:** inline `$DocModel | ConvertTo-Json -Depth 100` in the orchestrator (no helper needed).

**CSV flattener:** produces one row per setting, with context columns (TenantName, Product, PrimaryGroup, PolicyName, PolicyId, SettingId, DisplayName, Value, ValueLabel). `Export-Csv` / `ConvertTo-Csv` handles quoting.

### Stage 4: Emission

The orchestrator decides:
- `-OutputPath` provided → `Set-Content -Path $OutputPath -Value $rendered -Encoding UTF8`
- No `-OutputPath` → write rendered string to pipeline (caller pipes to file or processes further)
- `-OutputType JsonObject` parameter variant → write `$DocModel | ConvertTo-Json -Depth 100` to pipeline, skip rendering entirely (enables downstream processing without re-parsing)

---

## Suggested Build Order

Dependencies flow bottom-up. Build in this sequence:

```
1. Import-InforcerSettingsCatalog + Resolve-InforcerSettingName
   (no dependencies; can be unit-tested with sample settings.json data)

2. Get-InforcerDocData
   (depends on existing public cmdlets; can be integration-tested against live API)

3. ConvertTo-InforcerDocModel
   (depends on Resolve-InforcerSettingName; pure transformation — testable with fixture JSON)

4. ConvertTo-InforcerHtmlDoc
5. ConvertTo-InforcerMarkdownDoc
6. ConvertTo-InforcerCsvRows
   (all depend only on $DocModel; independently buildable and testable)

7. Export-InforcerDocumentation (public cmdlet)
   (wires everything together; add to FunctionsToExport in .psd1 last)
```

This order means each component is testable before the next is written, and the public surface is the last thing touched — keeping the manifest clean during development.

---

## Patterns to Follow

### Pattern 1: Session guard at the top

Consistent with all existing public cmdlets — guard before any work.

```powershell
if (-not (Test-InforcerSession)) {
    Write-Error -Message 'Not connected yet. Please run Connect-Inforcer first.' -ErrorId 'NotConnected' -Category ConnectionError
    return
}
```

### Pattern 2: Parameter order contract

Must match the InforcerCommunity consistency contract: `Format → TenantId → Tag → OutputType`.

```powershell
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Raw')]
    [string]$Format = 'Raw',

    [Parameter(Mandatory = $true)]
    [object]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$Tag,

    [Parameter(Mandatory = $false)]
    [ValidateSet('HTML', 'Markdown', 'JSON', 'CSV')]
    [string]$OutputFormat = 'HTML',

    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [string]$SettingsCatalogPath
)
```

Note: `-OutputFormat` replaces the standard `-OutputType` here because the values are document formats (HTML/MD/JSON/CSV), not API output modes. This is intentional and should be documented.

### Pattern 3: script-scope caching for heavy resources

```powershell
# In Import-InforcerSettingsCatalog
if ($null -ne $script:InforcerSettingsCatalog) { return }   # already loaded
$script:InforcerSettingsCatalog = @{}
# ... load and index settings.json
```

Mirrors how `$script:InforcerSession` works. Cleared on `Disconnect-Inforcer` (add a line there).

### Pattern 4: pure renderer functions

Renderers receive a model, return a string. They do not call cmdlets, write files, or mutate state. This makes them unit-testable in isolation using Pester without any module load or API connection.

---

## Anti-Patterns to Avoid

### Anti-Pattern 1: Calling Get-* cmdlets inside renderer helpers

**What goes wrong:** Renderer helpers start making API calls to enrich data mid-render.
**Why bad:** Breaks the separation of collect/normalize/render; impossible to unit-test renderers; unpredictable progress reporting.
**Instead:** All data retrieval happens in Stage 1 (`Get-InforcerDocData`). Renderers receive `$DocModel` only.

### Anti-Pattern 2: Loading settings.json inside ConvertTo-InforcerDocModel

**What goes wrong:** Model builder loads the 17,785-entry settings.json every call.
**Why bad:** Adds ~200-400ms per call (JSON parse time for a 1.5 MB file). On a tenant with 200 policies this becomes the bottleneck.
**Instead:** `Import-InforcerSettingsCatalog` loads once to `$script:` scope. `ConvertTo-InforcerDocModel` only calls `Resolve-InforcerSettingName`, which reads from the in-memory hashtable.

### Anti-Pattern 3: Putting HTML/CSS in the DocModel layer

**What goes wrong:** The normalization step emits HTML strings into `$DocModel.Products[0].ProductName`.
**Why bad:** Model is no longer reusable for Markdown or CSV; unit testing the model requires HTML parsing.
**Instead:** `$DocModel` contains only plain strings and arrays. Renderers own all markup.

### Anti-Pattern 4: Using ConvertFrom-Json on the full policies array without depth consideration

**What goes wrong:** `ConvertFrom-Json` without `-Depth 100` silently truncates deeply nested `policyData` objects in PowerShell 7.
**Why bad:** Settings Catalog policies can have 5+ levels of nesting in `settingInstances`.
**Instead:** Always use `ConvertFrom-Json -Depth 100`. The `-OutputType JsonObject` output from existing cmdlets already uses Depth 100 for the serialization side.

---

## Module Integration Points

### Files to create

```
module/Public/Export-InforcerDocumentation.ps1
module/Private/Get-InforcerDocData.ps1
module/Private/Import-InforcerSettingsCatalog.ps1
module/Private/Resolve-InforcerSettingName.ps1
module/Private/ConvertTo-InforcerDocModel.ps1
module/Private/ConvertTo-InforcerHtmlDoc.ps1
module/Private/ConvertTo-InforcerMarkdownDoc.ps1
module/Private/ConvertTo-InforcerCsvRows.ps1
```

### Files to modify

| File | Change |
|------|--------|
| `module/InforcerCommunity.psd1` | Add `'Export-InforcerDocumentation'` to `FunctionsToExport` |
| `module/Private/Disconnect-Inforcer.ps1` or session cleanup | Add `$script:InforcerSettingsCatalog = $null` |
| `docs/CMDLET-REFERENCE.md` | Add entry for new cmdlet |

### settings.json placement decision (unresolved)

Two options — must be decided before Phase 1 begins:

| Option | Path | Pros | Cons |
|--------|------|------|------|
| **Bundle with module** | `module/data/settings.json` | Self-contained, works offline, no sibling repo required | Adds ~5 MB to module package; needs update process |
| **Reference sibling repo** | `../IntuneSettingsCatalogViewer/data/settings.json` (default path, user-overridable) | Always current, smaller module | Requires sibling repo present; fails cleanly with `-SettingsCatalogPath` fallback |

Recommendation: support both via `-SettingsCatalogPath` parameter with default pointing to sibling repo. If the default path does not exist, emit a `Write-Warning` and continue with ID-as-name fallback. Bundle can be added in a later phase when the data update workflow is clear.

---

## Scalability Considerations

| Concern | For a typical tenant (50-200 policies) | For a large tenant (500+ policies) |
|---------|---------------------------------------|-------------------------------------|
| settings.json load time | ~100-300ms first call, ~0ms subsequent | Same — cached in `$script:` |
| HTML render time | <1s | May reach 3-5s; consider `Write-Progress` |
| API data volume | ~1-5 MB JSON from 3 API calls | ~20 MB; `-OutputType JsonObject` avoids double-parse overhead |
| Memory | Low (<50 MB) | Moderate (~100-200 MB for very large tenants) |

No architectural changes needed for large tenants — the pipeline handles any size. Add `Write-Progress` calls in the orchestrator between stages for user feedback.

---

## Sources

- InforcerCommunity module source (`module/Public/`, `module/Private/`): examined directly — HIGH confidence
- API schema: `docs/api-schema-snapshot.json` — HIGH confidence
- IntuneSettingsCatalogViewer `data/settings.json`: 17,785 entries, inspected structure — HIGH confidence
- PowerShell 7.0 `ConvertFrom-Json -Depth` parameter: [official docs](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/convertfrom-json) — MEDIUM confidence (verified behavior, not version)
- Module convention patterns: derived from existing cmdlet implementations — HIGH confidence
