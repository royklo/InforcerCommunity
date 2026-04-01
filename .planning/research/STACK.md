# Stack Research

**Domain:** PowerShell documentation export cmdlet (HTML, Markdown, JSON, CSV) — no external dependencies
**Researched:** 2026-04-01
**Confidence:** HIGH (core techniques verified against official PS 7.5 docs; CSS patterns verified against MDN/W3C-backed sources)

---

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

No external modules are required or permitted for core formats. All techniques use .NET/PowerShell built-ins.

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

---

## Installation

```powershell
# No installation required — everything is built into PowerShell 7.0+
# and .NET 8 (which PS 7.4+ ships with).

# Verify your PS version:
$PSVersionTable.PSVersion  # Must be 7.0+

# Verify ConvertFrom-Json -AsHashtable is available:
'{}' | ConvertFrom-Json -AsHashtable  # Should return empty OrderedHashtable
```

---

## Technique Details

### HTML Assembly Pattern: StringBuilder + here-string skeleton

**Do this — not `+=` string concatenation and not ConvertTo-Html for the full page:**

```powershell
function Build-HtmlDocument {
    param([hashtable]$Data)

    $sb = [System.Text.StringBuilder]::new()

    # Static shell via single-quoted here-string (no variable expansion risk)
    [void]$sb.Append(@'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
/* Entire CSS block embedded here — no CDN, no external file */
:root {
    --bg: #ffffff; --text: #1a1a1a; --accent: #0078d4;
    --border: #e5e5e5; --row-alt: #f8f9fa;
}
@media (prefers-color-scheme: dark) {
    :root { --bg: #1e1e1e; --text: #d4d4d4; --accent: #4fc3f7; --border: #3a3a3a; --row-alt: #252525; }
}
/* ... full CSS ... */
details > summary { cursor: pointer; padding: 0.5rem 1rem; }
details[open] > summary { font-weight: 600; }
table { border-collapse: collapse; width: 100%; }
th, td { padding: 0.4rem 0.75rem; border: 1px solid var(--border); }
tr:nth-child(even) { background: var(--row-alt); }
</style>
</head>
<body>
'@)

    # Dynamic content injected with AppendLine / AppendFormat
    [void]$sb.AppendLine("<h1>$($Data.TenantName) — Tenant Documentation</h1>")
    [void]$sb.AppendLine("<p>Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm') UTC</p>")

    # Collapsible TOC using native <details>/<summary>
    [void]$sb.AppendLine('<details id="toc"><summary>Table of Contents</summary><nav>')
    foreach ($product in $Data.Products) {
        [void]$sb.AppendLine("<a href=`"#$($product.Anchor)`">$($product.Name)</a>")
    }
    [void]$sb.AppendLine('</nav></details>')

    # Policy sections
    foreach ($product in $Data.Products) {
        [void]$sb.AppendLine("<section id=`"$($product.Anchor)`">")
        [void]$sb.AppendLine("<h2>$($product.Name)</h2>")
        foreach ($policy in $product.Policies) {
            # Each policy is its own <details> — collapsed by default
            [void]$sb.AppendLine("<details><summary>$($policy.Name)</summary>")
            # Settings table via ConvertTo-Html -Fragment on flat PSObject array
            $settingsHtml = $policy.Settings | ConvertTo-Html -Fragment -Property Name, Value, Description
            [void]$sb.Append($settingsHtml)
            [void]$sb.AppendLine('</details>')
        }
        [void]$sb.AppendLine('</section>')
    }

    [void]$sb.Append('</body></html>')
    return $sb.ToString()
}
```

**Why this exact pattern:**
- `[void]$sb.Append(...)` avoids PowerShell capturing the return value of `Append()` into the pipeline, which would pollute output.
- `ConvertTo-Html -Fragment` is used only for flat per-policy settings tables where you want the automatic column headers — not for page-level structure.
- CSS is embedded in the `<style>` block. No external file reference, no CDN. The document is self-contained.

---

### Collapsible Elements: `<details>` / `<summary>` (no JavaScript)

Use HTML5's native disclosure element everywhere you need collapse/expand:

```html
<!-- TOC: collapsed by default (no 'open' attribute) -->
<details id="toc">
  <summary>Table of Contents</summary>
  <nav>...</nav>
</details>

<!-- Policy: also collapsed by default -->
<details>
  <summary>Windows Security Baseline — Policy Name</summary>
  <table>...</table>
</details>
```

**CSS for visual polish (embedded, no CDN):**

```css
details > summary {
    list-style: none;          /* removes default triangle in some browsers */
    cursor: pointer;
    padding: 0.5rem 1rem;
    background: var(--accent-subtle);
    border-radius: 4px;
    user-select: none;
}
details > summary::before {
    content: "▶ ";
    transition: transform 0.15s;
}
details[open] > summary::before {
    content: "▼ ";
}
```

**Why not JavaScript accordions:** No CDN dependency (Bootstrap, jQuery), no CSP issues in security-conscious environments (IT admins often run reports in locked-down browsers), simpler PowerShell code.

---

### JSON Lookup: settings.json as Pre-Built Hashtable

The settings.json file is ~1.4 million lines. Never iterate it per-policy. Build a lookup once:

```powershell
function Get-SettingsLookup {
    param([string]$SettingsJsonPath)

    $raw = Get-Content -Raw -Path $SettingsJsonPath
    # -AsHashtable gives OrderedHashtable; hash table lookup is O(1) vs O(n) PSObject iteration
    $allSettings = $raw | ConvertFrom-Json -AsHashtable -Depth 20

    # Re-key by 'id' for fast lookup
    $lookup = @{}
    foreach ($entry in $allSettings) {
        if ($entry.ContainsKey('id')) {
            $lookup[$entry['id']] = $entry
        }
    }
    return $lookup
}

# Usage:
$lookup = Get-SettingsLookup -SettingsJsonPath $SettingsJsonPath
$friendlyName = $lookup['device_vendor_msft_policy_config_audit_accountlogon']?.displayName ?? 'Unknown'
```

**Why `-AsHashtable` and re-keying:** The JSON array is 1.4M lines. `ConvertFrom-Json` without `-AsHashtable` produces a PSObject per entry — property access is slower than hashtable key lookup. The re-keying loop runs once per cmdlet invocation and gives O(1) resolution for every settingDefinitionID thereafter.

---

### Markdown Generation: Pure Here-String Composition

No external module needed. Markdown is text — compose it directly:

```powershell
function ConvertTo-MarkdownTable {
    param(
        [string[]]$Headers,
        [PSObject[]]$Rows
    )
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('| ' + ($Headers -join ' | ') + ' |')
    [void]$sb.AppendLine('| ' + (($Headers | ForEach-Object { '---' }) -join ' | ') + ' |')
    foreach ($row in $Rows) {
        $cells = $Headers | ForEach-Object {
            # Escape pipe characters in cell values
            ($row.$_ -replace '\|', '\|') -replace "`n", '<br>'
        }
        [void]$sb.AppendLine('| ' + ($cells -join ' | ') + ' |')
    }
    return $sb.ToString()
}
```

For the document structure, use here-strings with `$()` subexpressions for dynamic headings and call `ConvertTo-MarkdownTable` for each section.

---

### CSV Export: Explicit Flat Object Projection

Never pipe raw policy objects to `Export-Csv` — nested objects render as `System.Object[]`. Build a row object explicitly:

```powershell
$csvRows = foreach ($policy in $policies) {
    foreach ($setting in $policy.Settings) {
        [PSCustomObject]@{
            ProductArea     = $policy.ProductArea
            PolicyName      = $policy.PolicyName
            Platform        = $policy.Platform
            SettingId       = $setting.DefinitionId
            SettingName     = $setting.DisplayName
            SettingValue    = $setting.Value
            Assignments     = $policy.Assignments -join '; '
            LastModified    = $policy.LastModifiedDateTime
        }
    }
}
$csvRows | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
```

**Why `-Encoding UTF8` explicitly:** PS 7 defaults to UTF-8 without BOM, which is correct. PS 5.1 defaults to ASCII. Since this module targets PS 7.0+, `UTF8` is sufficient and consistent.

---

## Alternatives Considered

| Recommended | Alternative | When to Use Alternative |
|-------------|-------------|-------------------------|
| StringBuilder + here-string skeleton | `ConvertTo-Html` (full page) | Use ConvertTo-Html full page only if you need a throwaway one-table report with no custom styling. It produces XHTML Strict DOCTYPE and has no mechanism for collapsible sections. |
| `<details>/<summary>` CSS-only accordion | JavaScript-based accordion (Bootstrap, custom) | Use JS accordion only if you need animation (CSS `interpolate-size` achieves this in 2025 without JS) or if you need deep browser compatibility back to IE11 (not relevant for IT admin tools). |
| Embedded `<style>` block | External `.css` file reference | Use external CSS only if you are serving the HTML from a web server and want caching. For single-file documentation exports, embedded CSS is required — the file must be self-contained. |
| `ConvertFrom-Json -AsHashtable` + re-key by `id` | `Where-Object { $_.id -eq $searchId }` per lookup | Use Where-Object only if you resolve fewer than ~10 IDs per run and startup time is irrelevant. For a full tenant export with thousands of settings, per-lookup filtering is O(n*m) and will be noticeably slow. |
| `Export-Csv` with flat PSCustomObject rows | Third-party CSV libraries | There are no third-party CSV libraries that solve a problem `Export-Csv` cannot for this use case. Never add a dependency here. |
| Pure here-string Markdown | PlatyPS | PlatyPS is for cmdlet help file generation. It has no role in generating tenant configuration documentation. Using it here would be a category error. |

---

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

---

## Stack Patterns by Variant

**If output format is HTML:**
- Use StringBuilder for full document assembly
- Embed complete CSS in `<style>` block (no CDN, no external file)
- Use `<details>/<summary>` for TOC and per-policy sections (collapsed by default — omit `open` attribute)
- Use `ConvertTo-Html -Fragment` only for individual flat-data tables within policy sections
- Include `prefers-color-scheme` media query in CSS for automatic dark/light mode

**If output format is Markdown:**
- Use StringBuilder for document assembly
- Implement a private `ConvertTo-MarkdownTable` helper (pipe-delimited, GFM-compatible)
- Use ATX headings (`# ##`) not Setext — more predictable rendering
- Escape pipe characters `|` in cell values (replace with `\|`)
- Render nested settings as sub-tables or indented lists depending on depth

**If output format is JSON:**
- Serialize the same structured intermediate object used for HTML/MD (do not re-fetch data)
- Use `ConvertTo-Json -Depth 100` — module convention, already established
- Use `-Compress` only if the caller requests compact output; default to pretty-printed

**If output format is CSV:**
- Build an explicit `[PSCustomObject]` per row — never pipe raw objects with nested arrays
- Project exactly the columns that make sense for flat analysis: ProductArea, PolicyName, SettingId, SettingName, SettingValue, Assignments (joined), dates
- Use `Export-Csv -NoTypeInformation -Encoding UTF8`

**If settings.json lookup is needed:**
- Load once at the start of `Export-InforcerDocumentation` execution
- Store in a `[hashtable]` keyed by `id`
- Pass the lookup table as a parameter to private builder functions — do not re-load per policy
- Handle missing IDs gracefully: return `$DefinitionId` as display name with a `(unresolved)` suffix

---

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

---

## Sources

- [ConvertTo-Html — Microsoft Learn (PS 7.5)](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/convertto-html?view=powershell-7.5) — Parameters, Fragment mode, limitations verified (HIGH confidence)
- [ConvertFrom-Json — Microsoft Learn (PS 7.5)](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/convertfrom-json?view=powershell-7.5) — `-AsHashtable` introduction version (PS 6.0), OrderedHashtable in PS 7.3+ confirmed (HIGH confidence)
- [ConvertTo-Json — PowerShell GitHub Issue #8393](https://github.com/PowerShell/PowerShell/issues/8393) — Max depth 100 confirmed; default-2 truncation pitfall (HIGH confidence)
- [Speeding Up String Manipulation — powershell.one](https://powershell.one/tricks/performance/strings) — StringBuilder 500x+ speedup over `+=` confirmed (MEDIUM confidence — community source, consistent with .NET fundamentals)
- [HTML Details Exclusive Accordions — MDN Blog](https://developer.mozilla.org/en-US/blog/html-details-exclusive-accordions/) — `<details>/<summary>` browser support and `name` attribute for exclusive accordion (HIGH confidence)
- [PSWriteHTML — GitHub (EvotecIT)](https://github.com/EvotecIT/PSWriteHTML) — Reviewed to confirm it is an external dependency, not viable under constraints (HIGH confidence — dismissed)
- [Export-Csv — Microsoft Learn (PS 7.5)](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/export-csv?view=powershell-7.5) — `-NoTypeInformation`, `-Encoding` behavior confirmed (HIGH confidence)

---

*Stack research for: PowerShell documentation export cmdlet (InforcerCommunity — Export-InforcerDocumentation)*
*Researched: 2026-04-01*
