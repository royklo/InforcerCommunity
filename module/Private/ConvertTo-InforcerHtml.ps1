function ConvertTo-HtmlAnchorId {
    <#
    .SYNOPSIS
        Converts a string to a valid HTML anchor ID (lowercase, hyphens, alphanumeric only).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text)
    $id = $Text.ToLowerInvariant()
    $id = $id -replace '[^a-z0-9\s-]', ''
    $id = $id -replace '\s+', '-'
    $id = $id -replace '-{2,}', '-'
    $id = $id.Trim('-')
    $id
}

function ConvertTo-InforcerHtml {
    <#
    .SYNOPSIS
        Renders a DocModel as a self-contained HTML document with embedded CSS.
    .DESCRIPTION
        Produces a single self-contained HTML file with:
        - Embedded CSS (dark/light mode via prefers-color-scheme, no external refs)
        - Collapsible two-level TOC (products > categories), collapsed by default
        - Per-policy collapsible <details>/<summary> sections with setting count badges
        - Settings displayed with CSS padding-left indentation based on Indent level
        - Basics, Settings, and Assignments tables per policy
        - Generation timestamp and tenant name in header and footer
        - HTML entity escaping via [System.Net.WebUtility]::HtmlEncode() for XSS prevention
        - StringBuilder assembly (no string concatenation in loops)

        Per decisions D-01 through D-18 and requirements HTML-01 through HTML-10.
    .PARAMETER DocModel
        Hashtable from ConvertTo-InforcerDocModel containing TenantName, TenantId,
        GeneratedAt, BaselineName, and Products (OrderedDictionary).
    .OUTPUTS
        System.String -- complete HTML document as a single string.
    .EXAMPLE
        $html = ConvertTo-InforcerHtml -DocModel $docModel
        Set-Content -Path '.\tenant-doc.html' -Value $html -Encoding UTF8
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$DocModel
    )

    # -------------------------------------------------------------------------
    # CSS block (embedded, single-quoted here-string -- no variable expansion)
    # Light mode via :root custom properties; dark mode via media query override.
    # -------------------------------------------------------------------------
    $cssBlock = @'
:root {
    --bg: #ffffff;
    --text: #1e293b;
    --border: #e2e8f0;
    --row-alt: #f8fafc;
    --header-bg: #f1f5f9;
    --muted: #94a3b8;
    --accent: #3b82f6;
    --badge-bg: #e0f2fe;
    --badge-text: #0369a1;
    --summary-hover: #f1f5f9;
}
@media (prefers-color-scheme: dark) {
    :root {
        --bg: #0f172a;
        --text: #e2e8f0;
        --border: #334155;
        --row-alt: #1e293b;
        --header-bg: #1e293b;
        --muted: #64748b;
        --accent: #60a5fa;
        --badge-bg: #1e3a5f;
        --badge-text: #93c5fd;
        --summary-hover: #1e293b;
    }
}
*, *::before, *::after { box-sizing: border-box; }
body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    background: var(--bg);
    color: var(--text);
    max-width: 1200px;
    margin: 0 auto;
    padding: 2rem;
    line-height: 1.6;
}
h1 { font-size: 1.75rem; margin-bottom: 0.25rem; }
h2 { font-size: 1.35rem; margin-top: 2rem; margin-bottom: 0.5rem; border-bottom: 2px solid var(--border); padding-bottom: 0.25rem; }
h3 { font-size: 1.1rem; margin-top: 1.5rem; margin-bottom: 0.5rem; color: var(--text); }
table { width: 100%; border-collapse: collapse; margin-bottom: 1rem; font-size: 0.9rem; }
th {
    background: var(--header-bg);
    text-align: left;
    padding: 0.5rem 0.75rem;
    border-bottom: 2px solid var(--border);
    font-weight: 600;
}
td { padding: 0.5rem 0.75rem; border-bottom: 1px solid var(--border); vertical-align: top; }
tr:nth-child(even) td { background: var(--row-alt); }
details { margin-bottom: 0.5rem; }
summary {
    cursor: pointer;
    padding: 0.4rem 0.5rem;
    border-radius: 4px;
    user-select: none;
    list-style: none;
}
summary::-webkit-details-marker { display: none; }
summary::before { content: '\25B6  '; font-size: 0.7rem; color: var(--muted); }
details[open] > summary::before { content: '\25BC  '; }
summary:hover { background: var(--summary-hover); }
.badge {
    display: inline-block;
    background: var(--badge-bg);
    color: var(--badge-text);
    padding: 0.125rem 0.5rem;
    border-radius: 999px;
    font-size: 0.75rem;
    margin-left: 0.5rem;
    font-weight: 600;
}
.muted { color: var(--muted); font-style: italic; }
.toc-section { margin-bottom: 2rem; }
.toc-section h2 { margin-top: 0; }
.toc-section ul { margin: 0.25rem 0 0.5rem 1.5rem; padding: 0; }
.toc-section li { margin: 0.2rem 0; }
.toc-section a { color: var(--accent); text-decoration: none; }
.toc-section a:hover { text-decoration: underline; }
.header { margin-bottom: 2rem; }
.header p { margin: 0.25rem 0; color: var(--muted); font-size: 0.9rem; }
.footer { margin-top: 3rem; padding-top: 1rem; border-top: 1px solid var(--border); color: var(--muted); font-size: 0.875rem; }
.policy-section { margin-left: 0.5rem; margin-bottom: 0.25rem; }
.section-label {
    font-weight: 600;
    margin: 0.75rem 0 0.25rem;
    font-size: 0.8rem;
    color: var(--muted);
    text-transform: uppercase;
    letter-spacing: 0.06em;
}
'@

    # -------------------------------------------------------------------------
    # Helper: encode a value for HTML output (null/empty -> muted em dash)
    # -------------------------------------------------------------------------
    function ConvertTo-SafeHtmlValue {
        param([Parameter()][object]$Value)
        if ($null -eq $Value -or ($Value -is [string] -and [string]::IsNullOrEmpty($Value))) {
            return '<span class="muted">&mdash;</span>'
        }
        return [System.Net.WebUtility]::HtmlEncode($Value.ToString())
    }

    # -------------------------------------------------------------------------
    # StringBuilder assembly
    # -------------------------------------------------------------------------
    $sb = [System.Text.StringBuilder]::new(65536)

    $tenantNameEsc    = [System.Net.WebUtility]::HtmlEncode($DocModel.TenantName)
    $baselineNameEsc  = if ($DocModel.BaselineName) { [System.Net.WebUtility]::HtmlEncode($DocModel.BaselineName) } else { '' }
    $generatedAt      = if ($DocModel.GeneratedAt -is [datetime]) { $DocModel.GeneratedAt.ToString('yyyy-MM-dd HH:mm:ss') } else { [string]$DocModel.GeneratedAt }

    # --- HTML head ---
    [void]$sb.AppendLine('<!DOCTYPE html>')
    [void]$sb.AppendLine('<html lang="en">')
    [void]$sb.AppendLine('<head>')
    [void]$sb.AppendLine('<meta charset="UTF-8">')
    [void]$sb.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1.0">')
    [void]$sb.AppendLine("<title>Tenant Documentation - $tenantNameEsc</title>")
    [void]$sb.AppendLine('<style>')
    [void]$sb.AppendLine($cssBlock)
    [void]$sb.AppendLine('</style>')
    [void]$sb.AppendLine('</head>')
    [void]$sb.AppendLine('<body>')

    # --- Header ---
    [void]$sb.AppendLine('<div class="header">')
    [void]$sb.AppendLine("<h1>Tenant Documentation: $tenantNameEsc</h1>")
    [void]$sb.AppendLine("<p>Generated: $generatedAt UTC</p>")
    if ($baselineNameEsc) {
        [void]$sb.AppendLine("<p>Baseline: $baselineNameEsc</p>")
    }
    [void]$sb.AppendLine('</div>')

    # --- TOC ---
    [void]$sb.AppendLine('<nav class="toc-section">')
    [void]$sb.AppendLine('<h2>Table of Contents</h2>')

    foreach ($prodName in $DocModel.Products.Keys) {
        $prodEsc    = [System.Net.WebUtility]::HtmlEncode($prodName)
        $prodAnchor = ConvertTo-HtmlAnchorId -Text $prodName

        [void]$sb.AppendLine('<details>')
        [void]$sb.AppendLine("<summary>$prodEsc</summary>")
        [void]$sb.AppendLine('<ul>')

        foreach ($catName in $DocModel.Products[$prodName].Categories.Keys) {
            $catEsc    = [System.Net.WebUtility]::HtmlEncode($catName)
            $catAnchor = ConvertTo-HtmlAnchorId -Text "$prodName-$catName"
            [void]$sb.AppendLine("<li><a href=`"#$catAnchor`">$catEsc</a></li>")
        }

        [void]$sb.AppendLine('</ul>')
        [void]$sb.AppendLine('</details>')
    }

    [void]$sb.AppendLine('</nav>')

    # --- Content sections ---
    foreach ($prodName in $DocModel.Products.Keys) {
        $prodEsc    = [System.Net.WebUtility]::HtmlEncode($prodName)
        $prodAnchor = ConvertTo-HtmlAnchorId -Text $prodName

        [void]$sb.AppendLine("<h2 id=`"$prodAnchor`">$prodEsc</h2>")

        foreach ($catName in $DocModel.Products[$prodName].Categories.Keys) {
            $catEsc    = [System.Net.WebUtility]::HtmlEncode($catName)
            $catAnchor = ConvertTo-HtmlAnchorId -Text "$prodName-$catName"
            $policies  = $DocModel.Products[$prodName].Categories[$catName]

            [void]$sb.AppendLine("<h3 id=`"$catAnchor`">$catEsc</h3>")

            foreach ($policy in @($policies)) {
                $policyNameEsc   = [System.Net.WebUtility]::HtmlEncode($policy.Basics.Name)
                $settingsCount   = if ($policy.Settings) { @($policy.Settings).Count } else { 0 }

                # Per-policy collapsible section (collapsed by default -- no 'open' attribute per D-06)
                [void]$sb.AppendLine('<details class="policy-section">')
                [void]$sb.AppendLine("<summary>$policyNameEsc <span class=`"badge`">$settingsCount settings</span></summary>")

                # --- Basics table ---
                [void]$sb.AppendLine('<div class="section-label">Basics</div>')
                [void]$sb.AppendLine('<table>')
                [void]$sb.AppendLine('<tr><th>Property</th><th>Value</th></tr>')

                $basicsProps = @('Description', 'ProfileType', 'Platform', 'Created', 'Modified', 'ScopeTags')
                foreach ($propName in $basicsProps) {
                    $propLabel = [System.Net.WebUtility]::HtmlEncode($propName)
                    $propVal   = ConvertTo-SafeHtmlValue -Value $policy.Basics[$propName]
                    [void]$sb.AppendLine("<tr><td>$propLabel</td><td>$propVal</td></tr>")
                }

                [void]$sb.AppendLine('</table>')

                # --- Settings table (only if count > 0) ---
                if ($settingsCount -gt 0) {
                    [void]$sb.AppendLine('<div class="section-label">Settings</div>')
                    [void]$sb.AppendLine('<table>')
                    [void]$sb.AppendLine('<tr><th>Setting</th><th>Value</th></tr>')

                    foreach ($setting in @($policy.Settings)) {
                        $settingNameEsc = [System.Net.WebUtility]::HtmlEncode($setting.Name)
                        $settingVal     = ConvertTo-SafeHtmlValue -Value $setting.Value
                        $indentLevel    = if ($null -ne $setting.Indent) { [int]$setting.Indent } else { 0 }
                        $paddingRem     = $indentLevel * 1.5

                        if ($indentLevel -gt 0) {
                            $paddingStr = $paddingRem.ToString('0.#', [System.Globalization.CultureInfo]::InvariantCulture)
                            [void]$sb.AppendLine("<tr><td style=`"padding-left: $($paddingStr)rem`">$settingNameEsc</td><td>$settingVal</td></tr>")
                        } else {
                            [void]$sb.AppendLine("<tr><td>$settingNameEsc</td><td>$settingVal</td></tr>")
                        }
                    }

                    [void]$sb.AppendLine('</table>')
                }

                # --- Assignments table (only if count > 0) ---
                $assignmentsCount = if ($policy.Assignments) { @($policy.Assignments).Count } else { 0 }
                if ($assignmentsCount -gt 0) {
                    [void]$sb.AppendLine('<div class="section-label">Assignments</div>')
                    [void]$sb.AppendLine('<table>')
                    [void]$sb.AppendLine('<tr><th>Group</th><th>Filter</th><th>Filter Mode</th><th>Type</th></tr>')

                    foreach ($assignment in @($policy.Assignments)) {
                        $grpVal        = ConvertTo-SafeHtmlValue -Value $assignment.Group
                        $filterVal     = ConvertTo-SafeHtmlValue -Value $assignment.Filter
                        $filterModeVal = ConvertTo-SafeHtmlValue -Value $assignment.FilterMode
                        $typeVal       = ConvertTo-SafeHtmlValue -Value $assignment.Type
                        [void]$sb.AppendLine("<tr><td>$grpVal</td><td>$filterVal</td><td>$filterModeVal</td><td>$typeVal</td></tr>")
                    }

                    [void]$sb.AppendLine('</table>')
                }

                [void]$sb.AppendLine('</details>')
            }
        }
    }

    # --- Footer ---
    [void]$sb.AppendLine('<div class="footer">')
    [void]$sb.AppendLine("<p>Generated: $generatedAt UTC | Tenant: $tenantNameEsc</p>")
    [void]$sb.AppendLine('</div>')

    [void]$sb.AppendLine('</body>')
    [void]$sb.Append('</html>')

    $sb.ToString()
}
