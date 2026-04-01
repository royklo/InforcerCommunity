<!-- GSD:project-start source:PROJECT.md -->
## Project

**Inforcer Tenant Documentation Cmdlet**

A PowerShell cmdlet (`Export-InforcerDocumentation`) for the InforcerCommunity module that generates comprehensive, human-readable documentation of an entire M365 tenant's configuration as managed through the Inforcer API. It pulls data from existing cmdlets (Get-InforcerBaseline, Get-InforcerTenant, Get-InforcerTenantPolicies), resolves Intune Settings Catalog settingDefinitionIDs to friendly names using the IntuneSettingsCatalogViewer dataset, and outputs in multiple formats (HTML, Markdown, JSON, CSV). The HTML output features a modern, collapsible table of contents with products and subcategories, clearly displaying settings and their values.

**Core Value:** IT admins can generate a complete, readable snapshot of their tenant's policy configuration across all M365 products in one command — no manual assembly required.

### Constraints

- **Tech stack**: PowerShell 7.0+, no external module dependencies for core formats (HTML/MD/JSON/CSV)
- **Module conventions**: Must follow InforcerCommunity consistency contract (parameter patterns, error handling, type names)
- **Settings data**: IntuneSettingsCatalogViewer settings.json is the lookup source — must handle missing/unknown settingDefinitionIDs gracefully
- **Output quality**: HTML must be modern (not the table-heavy 2026 reference style) with collapsible elements, clear visual hierarchy
<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->
## Technology Stack

## Recommended Stack
### Core Technologies
| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| `[System.Text.StringBuilder]` | .NET 8 (built-in) | HTML document assembly | String concatenation with `+=` degrades exponentially; StringBuilder is 500x faster for 100k+ appends. A tenant doc easily produces thousands of table rows. This is the correct .NET type for this use case. |
| `ConvertTo-Html -Fragment` | PS 7.0+ built-in | Generating HTML table fragments for flat data | When you already control the page shell (styles, TOC), `-Fragment` outputs only `<table>…</table>`. Use it for settings/assignments tables where you have a flat PSObject array. Do NOT use it for the full document skeleton — you lose all styling control. |
| `<details>` / `<summary>` HTML5 | HTML5 (no JS) | Collapsible TOC and policy sections | Native browser element, zero JavaScript required. Fully supported in all modern browsers as of 2025. Use `name="group"` attribute for exclusive-open accordion behavior. Styling via pure CSS `details[open] > summary` selector. This eliminates any JavaScript dependency entirely. |
| `ConvertTo-Json -Depth 100` | PS 7.0+ built-in | JSON export at full depth | Module convention already mandates `-Depth 100`. Max supported depth is 100. No external serializer needed. For the full-document JSON export, serialize the structured result object at depth 100. |
| `ConvertFrom-Json -AsHashtable` | PS 6.0+ built-in | Loading settings.json lookup table | `-AsHashtable` (introduced PS 6.0) converts the 1.4M-line settings.json into an `OrderedHashtable`. Hashtable lookup by `id` key is O(1) vs iterating a PSObject array. **Critical for startup performance** — build a `[hashtable]` keyed on `id` once at load time, not per-policy. |
| `Export-Csv` / `ConvertTo-Csv` | PS 7.0+ built-in | CSV flat export | Native, no external dependency. Limitation: nested objects serialize as `System.Object[]`. Mitigation: build a flat `[PSCustomObject]` per row before piping — project exactly the columns you want (PolicyName, ProductArea, SettingName, SettingValue, etc.). |
| Here-string `@" … "@` | PS 7.0+ built-in | CSS/JS embedding and Markdown templates | Embed the entire CSS block as a here-string in the private helper. Variable interpolation with `$()` lets you inject dynamic values. Use `@' … '@` (single-quoted) for the static CSS/Markdown template skeleton where you don't want variable expansion; use `@" … "@` only where you need `$variable` injection. |
### Supporting Libraries
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `[System.IO.StreamWriter]` | .NET 8 (built-in) | Write large HTML to disk without buffering entire string in memory | Only if HTML output exceeds ~50 MB. For normal tenant docs (1,000–5,000 policies), `Set-Content` with StringBuilder output is fine. Use StreamWriter if profiling shows memory pressure. |
| `[System.Collections.Generic.Dictionary[string,object]]` | .NET 8 (built-in) | Typed lookup structures | Alternative to `[hashtable]` when you need type safety on keys; marginal for this use case. Stick with `[hashtable]` — simpler syntax in PS. |
### Development Tools
| Tool | Purpose | Notes |
|------|---------|-------|
| Pester 5.x | Unit tests for HTML/MD rendering helpers | Already used in this module. Test the private builder functions with known-input/expected-output assertions. |
| VS Code + PowerShell extension | Development environment | Use "Run Selection" to test StringBuilder fragments interactively. |
| `Invoke-ScriptAnalyzer` | Static analysis | Already in module pipeline. Ensure no PSAvoidUsingInvokeExpression, PSUseShouldProcessForStateChangingFunctions warnings slip in. |
## Installation
# No installation required — everything is built into PowerShell 7.0+
# and .NET 8 (which PS 7.4+ ships with).
# Verify your PS version:
# Verify ConvertFrom-Json -AsHashtable is available:
## Technique Details
### HTML Assembly Pattern: StringBuilder + here-string skeleton
- `[void]$sb.Append(...)` avoids PowerShell capturing the return value of `Append()` into the pipeline, which would pollute output.
- `ConvertTo-Html -Fragment` is used only for flat per-policy settings tables where you want the automatic column headers — not for page-level structure.
- CSS is embedded in the `<style>` block. No external file reference, no CDN. The document is self-contained.
### Collapsible Elements: `<details>` / `<summary>` (no JavaScript)
### JSON Lookup: settings.json as Pre-Built Hashtable
# Usage:
### Markdown Generation: Pure Here-String Composition
### CSV Export: Explicit Flat Object Projection
## Alternatives Considered
| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| StringBuilder + here-string skeleton | `ConvertTo-Html` (full page) | Use ConvertTo-Html full page only if you need a throwaway one-table report with no custom styling. It produces XHTML Strict DOCTYPE and has no mechanism for collapsible sections. |
| `<details>/<summary>` CSS-only accordion | JavaScript-based accordion (Bootstrap, custom) | Use JS accordion only if you need animation (CSS `interpolate-size` achieves this in 2025 without JS) or if you need deep browser compatibility back to IE11 (not relevant for IT admin tools). |
| Embedded `<style>` block | External `.css` file reference | Use external CSS only if you are serving the HTML from a web server and want caching. For single-file documentation exports, embedded CSS is required — the file must be self-contained. |
| `ConvertFrom-Json -AsHashtable` + re-key by `id` | `Where-Object { $_.id -eq $searchId }` per lookup | Use Where-Object only if you resolve fewer than ~10 IDs per run and startup time is irrelevant. For a full tenant export with thousands of settings, per-lookup filtering is O(n*m) and will be noticeably slow. |
| `Export-Csv` with flat PSCustomObject rows | Third-party CSV libraries | There are no third-party CSV libraries that solve a problem `Export-Csv` cannot for this use case. Never add a dependency here. |
| Pure here-string Markdown | PlatyPS | PlatyPS is for cmdlet help file generation. It has no role in generating tenant configuration documentation. Using it here would be a category error. |
## What NOT to Use
| Avoid | Why | Use Instead |
|-------|-----|-------------|
| PSWriteHTML (external module) | Introduces an external dependency — violates the hard constraint. Also adds gallery install complexity for users. | StringBuilder + embedded CSS as described above |
| `ConvertTo-Html` for the full document skeleton | Outputs XHTML Strict DOCTYPE; provides no mechanism for injecting `<details>/<summary>` between tables; `-PreContent`/`-PostContent` params accept strings but are awkward for multi-table composite documents | StringBuilder-assembled skeleton with `ConvertTo-Html -Fragment` for table fragments only |
| `$html += "<tr>..."` string concatenation in loops | Each `+=` on a string creates a new string object in memory. For a tenant with 500 policies × 20 settings = 10,000 iterations, this is prohibitively slow (minutes vs seconds). This is a known PowerShell performance pitfall. | `[System.Text.StringBuilder]` with `[void]$sb.AppendLine(...)` |
| CDN-hosted CSS frameworks (Bootstrap, Tailwind via CDN) | IT admin environments frequently run with outbound HTTP blocked or restricted. A report that requires internet access to render styles is unusable in those environments. Also introduces privacy exposure (CDN logs document opens). | Embed the CSS inline in `<style>` — keep it to ~200 lines of purpose-built styles |
| `ConvertTo-Html -CssUri` with a file path | Produces a two-file artifact (HTML + CSS). Users expect a single self-contained file they can email or archive. | Embedded `<style>` block |
| `Write-Output` to collect HTML strings then join | PowerShell pipeline overhead per string emission. In a loop, this is slower than StringBuilder.  | `[void]$sb.AppendLine(...)` |
| External JSON serializer modules | The module requires no external dependencies. `ConvertTo-Json -Depth 100` is the module's existing standard and handles all required depth. | `ConvertTo-Json -Depth 100` (already used everywhere in this module) |
| `Select-Xml` / XML DOM for HTML manipulation | Overkill for generation. HTML is write-once in this context — you build it linearly. XML DOM adds complexity with no benefit. | StringBuilder linear assembly |
## Stack Patterns by Variant
- Use StringBuilder for full document assembly
- Embed complete CSS in `<style>` block (no CDN, no external file)
- Use `<details>/<summary>` for TOC and per-policy sections (collapsed by default — omit `open` attribute)
- Use `ConvertTo-Html -Fragment` only for individual flat-data tables within policy sections
- Include `prefers-color-scheme` media query in CSS for automatic dark/light mode
- Use StringBuilder for document assembly
- Implement a private `ConvertTo-MarkdownTable` helper (pipe-delimited, GFM-compatible)
- Use ATX headings (`# ##`) not Setext — more predictable rendering
- Escape pipe characters `|` in cell values (replace with `\|`)
- Render nested settings as sub-tables or indented lists depending on depth
- Serialize the same structured intermediate object used for HTML/MD (do not re-fetch data)
- Use `ConvertTo-Json -Depth 100` — module convention, already established
- Use `-Compress` only if the caller requests compact output; default to pretty-printed
- Build an explicit `[PSCustomObject]` per row — never pipe raw objects with nested arrays
- Project exactly the columns that make sense for flat analysis: ProductArea, PolicyName, SettingId, SettingName, SettingValue, Assignments (joined), dates
- Use `Export-Csv -NoTypeInformation -Encoding UTF8`
- Load once at the start of `Export-InforcerDocumentation` execution
- Store in a `[hashtable]` keyed by `id`
- Pass the lookup table as a parameter to private builder functions — do not re-load per policy
- Handle missing IDs gracefully: return `$DefinitionId` as display name with a `(unresolved)` suffix
## Version Compatibility
| Feature | Minimum PS Version | Notes |
|---------|--------------------|-------|
| `[System.Text.StringBuilder]` | Any (.NET built-in) | Available in PS 5.1+ |
| `ConvertTo-Html -Fragment` | PS 3.0+ | No version concerns |
| `ConvertFrom-Json -AsHashtable` | PS 6.0 | **PS 7.0+ is the module requirement** — this is safe |
| `ConvertFrom-Json -AsHashtable` returning `OrderedHashtable` | PS 7.3+ | On PS 7.0–7.2 returns regular `Hashtable` (unordered). For a lookup-only use case, this doesn't matter — both support `$lookup[$key]` access. |
| `<details>/<summary>` HTML5 | Browser concern, not PS | Edge 79+, Chrome 12+, Firefox 49+, Safari 6+ — all fully supported. IT admins in 2025/2026 are not on ancient browsers. |
| `Export-Csv -Encoding UTF8` | PS 7.0+ | PS 7 defaults to UTF-8 BOM-less, which is correct. `-Encoding UTF8` is explicit and safe. |
| `ConvertTo-Json -Depth 100` | PS 7.0+ | Max depth 100 is documented; already the module convention. |
| `prefers-color-scheme` CSS media query | Browser CSS feature | Supported in all modern browsers since 2019. No PS version dependency. |
## Sources
- [ConvertTo-Html — Microsoft Learn (PS 7.5)](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/convertto-html?view=powershell-7.5) — Parameters, Fragment mode, limitations verified (HIGH confidence)
- [ConvertFrom-Json — Microsoft Learn (PS 7.5)](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/convertfrom-json?view=powershell-7.5) — `-AsHashtable` introduction version (PS 6.0), OrderedHashtable in PS 7.3+ confirmed (HIGH confidence)
- [ConvertTo-Json — PowerShell GitHub Issue #8393](https://github.com/PowerShell/PowerShell/issues/8393) — Max depth 100 confirmed; default-2 truncation pitfall (HIGH confidence)
- [Speeding Up String Manipulation — powershell.one](https://powershell.one/tricks/performance/strings) — StringBuilder 500x+ speedup over `+=` confirmed (MEDIUM confidence — community source, consistent with .NET fundamentals)
- [HTML Details Exclusive Accordions — MDN Blog](https://developer.mozilla.org/en-US/blog/html-details-exclusive-accordions/) — `<details>/<summary>` browser support and `name` attribute for exclusive accordion (HIGH confidence)
- [PSWriteHTML — GitHub (EvotecIT)](https://github.com/EvotecIT/PSWriteHTML) — Reviewed to confirm it is an external dependency, not viable under constraints (HIGH confidence — dismissed)
- [Export-Csv — Microsoft Learn (PS 7.5)](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/export-csv?view=powershell-7.5) — `-NoTypeInformation`, `-Encoding` behavior confirmed (HIGH confidence)
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd:quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd:debug` for investigation and bug fixing
- `/gsd:execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd:profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
