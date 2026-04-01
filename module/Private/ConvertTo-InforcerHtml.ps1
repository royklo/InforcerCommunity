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
        Produces a single self-contained HTML file with modern 2025 admin dashboard styling:
        - Embedded CSS with CSS custom properties for dark/light theming
        - Glassmorphism-inspired cards and toolbar
        - Collapsible TOC per product and category
        - Collapsible product sections in content
        - Sticky toolbar with empty field filter and theme toggle
        - Smooth transitions and hover states
        - StringBuilder assembly (no string concatenation in loops)
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

    $cssBlock = @'
:root {
    --bg: #f8fafc;
    --bg-card: #ffffff;
    --bg-glass: rgba(255,255,255,0.7);
    --text: #0f172a;
    --text-secondary: #475569;
    --border: #e2e8f0;
    --border-subtle: #f1f5f9;
    --row-alt: rgba(248,250,252,0.6);
    --header-bg: rgba(241,245,249,0.8);
    --muted: #94a3b8;
    --accent: #2563eb;
    --accent-hover: #1d4ed8;
    --accent-soft: rgba(37,99,235,0.08);
    --badge-bg: #dbeafe;
    --badge-text: #1e40af;
    --summary-hover: rgba(241,245,249,0.8);
    --shadow-sm: 0 1px 2px rgba(0,0,0,0.04);
    --shadow-md: 0 4px 12px rgba(0,0,0,0.06);
    --shadow-lg: 0 8px 24px rgba(0,0,0,0.08);
    --radius: 12px;
    --radius-sm: 8px;
    --radius-xs: 6px;
    --transition: 200ms cubic-bezier(0.4, 0, 0.2, 1);
    --success: #059669;
    --success-bg: #d1fae5;
}
@media (prefers-color-scheme: dark) {
    :root:not(.light) {
        --bg: #0c0f1a;
        --bg-card: #141825;
        --bg-glass: rgba(20,24,37,0.8);
        --text: #e2e8f0;
        --text-secondary: #94a3b8;
        --border: #1e293b;
        --border-subtle: #1e293b;
        --row-alt: rgba(30,41,59,0.4);
        --header-bg: rgba(30,41,59,0.6);
        --muted: #64748b;
        --accent: #3b82f6;
        --accent-hover: #60a5fa;
        --accent-soft: rgba(59,130,246,0.1);
        --badge-bg: rgba(59,130,246,0.15);
        --badge-text: #93c5fd;
        --summary-hover: rgba(30,41,59,0.6);
        --shadow-sm: 0 1px 2px rgba(0,0,0,0.2);
        --shadow-md: 0 4px 12px rgba(0,0,0,0.3);
        --shadow-lg: 0 8px 24px rgba(0,0,0,0.4);
        --success: #34d399;
        --success-bg: rgba(52,211,153,0.1);
    }
}
:root.dark {
    --bg: #0c0f1a;
    --bg-card: #141825;
    --bg-glass: rgba(20,24,37,0.8);
    --text: #e2e8f0;
    --text-secondary: #94a3b8;
    --border: #1e293b;
    --border-subtle: #1e293b;
    --row-alt: rgba(30,41,59,0.4);
    --header-bg: rgba(30,41,59,0.6);
    --muted: #64748b;
    --accent: #3b82f6;
    --accent-hover: #60a5fa;
    --accent-soft: rgba(59,130,246,0.1);
    --badge-bg: rgba(59,130,246,0.15);
    --badge-text: #93c5fd;
    --summary-hover: rgba(30,41,59,0.6);
    --shadow-sm: 0 1px 2px rgba(0,0,0,0.2);
    --shadow-md: 0 4px 12px rgba(0,0,0,0.3);
    --shadow-lg: 0 8px 24px rgba(0,0,0,0.4);
    --success: #34d399;
    --success-bg: rgba(52,211,153,0.1);
}
:root.light {
    --bg: #f8fafc;
    --bg-card: #ffffff;
    --bg-glass: rgba(255,255,255,0.7);
    --text: #0f172a;
    --text-secondary: #475569;
    --border: #e2e8f0;
    --border-subtle: #f1f5f9;
    --row-alt: rgba(248,250,252,0.6);
    --header-bg: rgba(241,245,249,0.8);
    --muted: #94a3b8;
    --accent: #2563eb;
    --accent-hover: #1d4ed8;
    --accent-soft: rgba(37,99,235,0.08);
    --badge-bg: #dbeafe;
    --badge-text: #1e40af;
    --summary-hover: rgba(241,245,249,0.8);
    --shadow-sm: 0 1px 2px rgba(0,0,0,0.04);
    --shadow-md: 0 4px 12px rgba(0,0,0,0.06);
    --shadow-lg: 0 8px 24px rgba(0,0,0,0.08);
    --success: #059669;
    --success-bg: #d1fae5;
}
@media (prefers-reduced-motion: reduce) {
    * { transition-duration: 0ms !important; }
}
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, Roboto, sans-serif;
    background: var(--bg);
    color: var(--text);
    max-width: 1100px;
    margin: 0 auto;
    padding: 0 1.5rem 3rem;
    line-height: 1.65;
    font-size: 0.9375rem;
    -webkit-font-smoothing: antialiased;
}
/* --- Toolbar (sticky glass) --- */
.toolbar {
    position: sticky;
    top: 0;
    z-index: 100;
    background: var(--bg-glass);
    backdrop-filter: blur(16px);
    -webkit-backdrop-filter: blur(16px);
    border-bottom: 1px solid var(--border);
    padding: 0.625rem 0;
    margin: 0 -1.5rem 1.5rem;
    padding-left: 1.5rem;
    padding-right: 1.5rem;
    display: flex;
    gap: 0.5rem;
    align-items: center;
    flex-wrap: wrap;
}
.toolbar-btn {
    background: var(--bg-card);
    color: var(--text-secondary);
    border: 1px solid var(--border);
    padding: 0.375rem 0.875rem;
    border-radius: var(--radius-xs);
    cursor: pointer;
    font-size: 0.8125rem;
    font-family: inherit;
    font-weight: 500;
    transition: all var(--transition);
    white-space: nowrap;
}
.toolbar-btn:hover { background: var(--accent-soft); color: var(--accent); border-color: var(--accent); }
.toolbar-btn:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
.toolbar-btn.active { background: var(--accent); color: #fff; border-color: var(--accent); }
.toolbar-btn.active:hover { background: var(--accent-hover); }
.toolbar-spacer { flex: 1; }
/* --- Header --- */
.header {
    padding: 2.5rem 0 1.5rem;
}
.header h1 {
    font-size: 1.75rem;
    font-weight: 700;
    letter-spacing: -0.025em;
    margin-bottom: 0.5rem;
}
.header-meta {
    display: flex;
    gap: 1.5rem;
    flex-wrap: wrap;
    font-size: 0.8125rem;
    color: var(--muted);
}
.header-meta span { display: flex; align-items: center; gap: 0.375rem; }
/* --- Cards --- */
.card {
    background: var(--bg-card);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    box-shadow: var(--shadow-sm);
    padding: 1.25rem 1.5rem;
    margin-bottom: 1rem;
    transition: box-shadow var(--transition);
}
.card:hover { box-shadow: var(--shadow-md); }
/* --- TOC --- */
.toc-section { margin-bottom: 1.5rem; }
.toc-section .card { padding: 1rem 1.25rem; }
.toc-title {
    font-size: 0.75rem;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--muted);
    margin-bottom: 0.75rem;
}
.toc-l1 { list-style: none; }
.toc-l1 > li { margin-bottom: 0.25rem; }
.toc-l1 > li > details { border-radius: var(--radius-xs); }
.toc-l1 > li > details > summary {
    padding: 0.5rem 0.625rem;
    border-radius: var(--radius-xs);
    font-weight: 600;
    font-size: 0.875rem;
    color: var(--text);
    display: flex;
    align-items: center;
    gap: 0.5rem;
}
.toc-l2 { list-style: none; padding-left: 1.25rem; margin: 0.125rem 0 0.25rem; }
.toc-l2 > li > details > summary {
    padding: 0.3rem 0.5rem;
    border-radius: var(--radius-xs);
    font-size: 0.8125rem;
    color: var(--text-secondary);
    font-weight: 500;
}
.toc-l3 { list-style: none; padding-left: 1rem; margin: 0.125rem 0; }
.toc-l3 > li { margin: 0.0625rem 0; }
.toc-l3 > li a {
    display: block;
    padding: 0.2rem 0.5rem;
    border-radius: 4px;
    font-size: 0.8rem;
    color: var(--muted);
    transition: all var(--transition);
}
.toc-l3 > li a:hover { color: var(--accent); background: var(--accent-soft); }
.toc-section a { color: inherit; text-decoration: none; }
.toc-section a:hover { color: var(--accent); }
/* --- Badges --- */
.badge {
    display: inline-flex;
    align-items: center;
    background: var(--badge-bg);
    color: var(--badge-text);
    padding: 0.125rem 0.5rem;
    border-radius: 999px;
    font-size: 0.6875rem;
    font-weight: 600;
    letter-spacing: 0.01em;
    white-space: nowrap;
}
.muted { color: var(--muted); font-style: italic; }
/* --- Summary / Details (shared) --- */
details { border-radius: var(--radius-xs); }
summary {
    cursor: pointer;
    padding: 0.5rem 0.625rem;
    border-radius: var(--radius-xs);
    user-select: none;
    list-style: none;
    transition: background var(--transition);
}
summary::-webkit-details-marker { display: none; }
summary::before {
    content: '';
    display: inline-block;
    width: 0.375rem;
    height: 0.375rem;
    border-right: 2px solid var(--muted);
    border-bottom: 2px solid var(--muted);
    transform: rotate(-45deg);
    margin-right: 0.625rem;
    transition: transform var(--transition);
    flex-shrink: 0;
}
details[open] > summary::before { transform: rotate(45deg); }
summary:hover { background: var(--summary-hover); }
/* --- Product sections --- */
.product-section { margin-bottom: 1rem; }
.product-section > summary {
    font-size: 1rem;
    font-weight: 700;
    padding: 0.875rem 1rem;
    background: var(--bg-card);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    box-shadow: var(--shadow-sm);
    display: flex;
    align-items: center;
    gap: 0.5rem;
    margin-bottom: 0.5rem;
}
.product-section > summary:hover { box-shadow: var(--shadow-md); }
.product-section[open] > summary { border-radius: var(--radius) var(--radius) 0 0; margin-bottom: 0; border-bottom-color: transparent; }
.product-content {
    background: var(--bg-card);
    border: 1px solid var(--border);
    border-top: none;
    border-radius: 0 0 var(--radius) var(--radius);
    padding: 1rem 1.25rem;
    box-shadow: var(--shadow-sm);
    margin-bottom: 0.5rem;
}
.product-title { flex: 1; }
/* --- Category headings --- */
h3 {
    font-size: 0.8125rem;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--muted);
    margin: 1.25rem 0 0.625rem;
    padding-bottom: 0.375rem;
    border-bottom: 1px solid var(--border-subtle);
}
/* --- Policy cards --- */
.policy-section {
    background: var(--bg);
    border: 1px solid var(--border-subtle);
    border-radius: var(--radius-sm);
    padding: 1rem;
    margin-bottom: 0.625rem;
    transition: border-color var(--transition), box-shadow var(--transition);
}
.policy-section:hover { border-color: var(--border); box-shadow: var(--shadow-sm); }
h4 {
    font-size: 0.9375rem;
    font-weight: 600;
    margin: 0 0 0.75rem;
    display: flex;
    align-items: center;
    gap: 0.5rem;
    flex-wrap: wrap;
}
/* --- Section labels --- */
.section-label {
    font-weight: 600;
    margin: 0.75rem 0 0.375rem;
    font-size: 0.6875rem;
    color: var(--muted);
    text-transform: uppercase;
    letter-spacing: 0.08em;
}
/* --- Tables --- */
table {
    width: 100%;
    border-collapse: collapse;
    margin-bottom: 0.75rem;
    font-size: 0.8125rem;
    border-radius: var(--radius-xs);
    overflow: hidden;
}
th {
    background: var(--header-bg);
    text-align: left;
    padding: 0.5rem 0.75rem;
    font-weight: 600;
    font-size: 0.75rem;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: var(--text-secondary);
    border-bottom: 1px solid var(--border);
}
td {
    padding: 0.5rem 0.75rem;
    border-bottom: 1px solid var(--border-subtle);
    vertical-align: top;
    color: var(--text);
}
tr:last-child td { border-bottom: none; }
tr:nth-child(even) td { background: var(--row-alt); }
tr:hover td { background: var(--accent-soft); }
/* --- Footer --- */
.footer {
    margin-top: 2rem;
    padding: 1rem 0;
    text-align: center;
    color: var(--muted);
    font-size: 0.75rem;
}
/* --- Filter toggle --- */
.hide-empty .empty-val { display: none; }
.hide-empty tr:has(td > .empty-val:only-child) { display: none; }
/* --- Responsive --- */
@media (max-width: 768px) {
    body { padding: 0 1rem 2rem; font-size: 0.875rem; }
    .toolbar { margin: 0 -1rem 1rem; padding-left: 1rem; padding-right: 1rem; }
    .header h1 { font-size: 1.375rem; }
    .product-section > summary { padding: 0.75rem; font-size: 0.9375rem; }
    .policy-section { padding: 0.75rem; }
    td, th { padding: 0.375rem 0.5rem; }
}
'@

    # -------------------------------------------------------------------------
    # Helper: encode a value for HTML output (null/empty -> muted em dash)
    # -------------------------------------------------------------------------
    function ConvertTo-SafeHtmlValue {
        param([Parameter()][object]$Value)
        if ($null -eq $Value -or ($Value -is [string] -and [string]::IsNullOrEmpty($Value))) {
            return '<span class="muted empty-val">&mdash;</span>'
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

    # Count totals for header
    $totalPolicies = 0
    $totalProducts = $DocModel.Products.Count
    foreach ($prodVal in $DocModel.Products.Values) {
        foreach ($catPols in $prodVal.Categories.Values) { $totalPolicies += @($catPols).Count }
    }

    # --- HTML head ---
    [void]$sb.AppendLine('<!DOCTYPE html>')
    [void]$sb.AppendLine('<html lang="en">')
    [void]$sb.AppendLine('<head>')
    [void]$sb.AppendLine('<meta charset="UTF-8">')
    [void]$sb.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1.0">')
    [void]$sb.AppendLine("<title>$tenantNameEsc - Tenant Documentation</title>")
    [void]$sb.AppendLine('<style>')
    [void]$sb.AppendLine($cssBlock)
    [void]$sb.AppendLine('</style>')
    [void]$sb.AppendLine('</head>')
    [void]$sb.AppendLine('<body>')

    # --- Toolbar ---
    [void]$sb.AppendLine('<div class="toolbar">')
    [void]$sb.AppendLine('<button class="toolbar-btn" id="btn-toggle-empty" onclick="toggleEmpty()">Hide empty fields</button>')
    [void]$sb.AppendLine('<button class="toolbar-btn" id="btn-expand" onclick="toggleExpand()">Expand all</button>')
    [void]$sb.AppendLine('<div class="toolbar-spacer"></div>')
    [void]$sb.AppendLine('<button class="toolbar-btn" id="btn-theme" onclick="toggleTheme()">Dark mode</button>')
    [void]$sb.AppendLine('</div>')

    # --- Header ---
    [void]$sb.AppendLine('<div class="header">')
    [void]$sb.AppendLine("<h1>$tenantNameEsc</h1>")
    [void]$sb.AppendLine('<div class="header-meta">')
    [void]$sb.AppendLine("<span>$generatedAt UTC</span>")
    [void]$sb.AppendLine("<span>$totalProducts products</span>")
    [void]$sb.AppendLine("<span>$totalPolicies policies</span>")
    if ($baselineNameEsc) {
        [void]$sb.AppendLine("<span>$baselineNameEsc</span>")
    }
    [void]$sb.AppendLine('</div>')
    [void]$sb.AppendLine('</div>')

    # --- TOC (collapsible per product and category) ---
    [void]$sb.AppendLine('<div class="toc-section">')
    [void]$sb.AppendLine('<div class="card">')
    [void]$sb.AppendLine('<div class="toc-title">Table of Contents</div>')
    [void]$sb.AppendLine('<ul class="toc-l1">')

    foreach ($prodName in $DocModel.Products.Keys) {
        $prodEsc    = [System.Net.WebUtility]::HtmlEncode($prodName)
        $prodAnchor = ConvertTo-HtmlAnchorId -Text $prodName

        $prodPolicies = 0
        foreach ($cp in $DocModel.Products[$prodName].Categories.Values) { $prodPolicies += @($cp).Count }

        [void]$sb.AppendLine('<li>')
        [void]$sb.AppendLine('<details>')
        [void]$sb.AppendLine("<summary><a href=`"#$prodAnchor`">$prodEsc</a> <span class=`"badge`">$prodPolicies</span></summary>")
        [void]$sb.AppendLine('<ul class="toc-l2">')

        foreach ($catName in $DocModel.Products[$prodName].Categories.Keys) {
            $catEsc    = [System.Net.WebUtility]::HtmlEncode($catName)
            $catAnchor = ConvertTo-HtmlAnchorId -Text "$prodName-$catName"
            $policies  = $DocModel.Products[$prodName].Categories[$catName]

            [void]$sb.AppendLine('<li>')
            [void]$sb.AppendLine('<details>')
            [void]$sb.AppendLine("<summary><a href=`"#$catAnchor`">$catEsc</a></summary>")
            [void]$sb.AppendLine('<ul class="toc-l3">')

            foreach ($policy in @($policies)) {
                $pName   = [System.Net.WebUtility]::HtmlEncode($policy.Basics.Name)
                $pAnchor = ConvertTo-HtmlAnchorId -Text "$prodName-$catName-$($policy.Basics.Name)"
                [void]$sb.AppendLine("<li><a href=`"#$pAnchor`">$pName</a></li>")
            }

            [void]$sb.AppendLine('</ul>')
            [void]$sb.AppendLine('</details>')
            [void]$sb.AppendLine('</li>')
        }

        [void]$sb.AppendLine('</ul>')
        [void]$sb.AppendLine('</details>')
        [void]$sb.AppendLine('</li>')
    }

    [void]$sb.AppendLine('</ul>')
    [void]$sb.AppendLine('</div>')
    [void]$sb.AppendLine('</div>')

    # --- Content sections ---
    foreach ($prodName in $DocModel.Products.Keys) {
        $prodEsc    = [System.Net.WebUtility]::HtmlEncode($prodName)
        $prodAnchor = ConvertTo-HtmlAnchorId -Text $prodName

        $prodPolicyCount = 0
        foreach ($catPolicies in $DocModel.Products[$prodName].Categories.Values) {
            $prodPolicyCount += @($catPolicies).Count
        }

        # Product-level collapsible section
        [void]$sb.AppendLine('<details class="product-section">')
        [void]$sb.AppendLine("<summary id=`"$prodAnchor`"><span class=`"product-title`">$prodEsc</span> <span class=`"badge`">$prodPolicyCount policies</span></summary>")
        [void]$sb.AppendLine('<div class="product-content">')

        foreach ($catName in $DocModel.Products[$prodName].Categories.Keys) {
            $catEsc    = [System.Net.WebUtility]::HtmlEncode($catName)
            $catAnchor = ConvertTo-HtmlAnchorId -Text "$prodName-$catName"
            $policies  = $DocModel.Products[$prodName].Categories[$catName]

            [void]$sb.AppendLine("<h3 id=`"$catAnchor`">$catEsc</h3>")

            foreach ($policy in @($policies)) {
                $policyNameEsc   = [System.Net.WebUtility]::HtmlEncode($policy.Basics.Name)
                $settingsCount   = if ($policy.Settings) { @($policy.Settings).Count } else { 0 }
                $policyAnchor    = ConvertTo-HtmlAnchorId -Text "$prodName-$catName-$($policy.Basics.Name)"

                [void]$sb.AppendLine('<div class="policy-section">')
                [void]$sb.AppendLine("<h4 id=`"$policyAnchor`">$policyNameEsc <span class=`"badge`">$settingsCount settings</span></h4>")

                # --- Basics table (only non-empty fields) ---
                $basicsProps = @('Description', 'ProfileType', 'Platform', 'Created', 'Modified', 'ScopeTags')
                $nonEmptyBasics = @($basicsProps | Where-Object {
                    $val = $policy.Basics[$_]
                    $null -ne $val -and ($val -isnot [string] -or -not [string]::IsNullOrWhiteSpace($val))
                })

                if ($nonEmptyBasics.Count -gt 0) {
                    [void]$sb.AppendLine('<div class="section-label">Basics</div>')
                    [void]$sb.AppendLine('<table>')
                    [void]$sb.AppendLine('<tr><th>Property</th><th>Value</th></tr>')
                    foreach ($propName in $nonEmptyBasics) {
                        $propLabel = [System.Net.WebUtility]::HtmlEncode($propName)
                        $propVal   = ConvertTo-SafeHtmlValue -Value $policy.Basics[$propName]
                        [void]$sb.AppendLine("<tr><td>$propLabel</td><td>$propVal</td></tr>")
                    }
                    [void]$sb.AppendLine('</table>')
                }

                # --- Settings table ---
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

                # --- Assignments table ---
                $assignmentsCount = if ($policy.Assignments) { @($policy.Assignments).Count } else { 0 }
                if ($assignmentsCount -gt 0) {
                    [void]$sb.AppendLine('<div class="section-label">Assignments</div>')
                    [void]$sb.AppendLine('<table>')
                    [void]$sb.AppendLine('<tr><th>Target</th><th>Type</th><th>Filter</th><th>Filter Mode</th></tr>')
                    foreach ($assignment in @($policy.Assignments)) {
                        $targetVal     = ConvertTo-SafeHtmlValue -Value $assignment.Target
                        $typeVal       = ConvertTo-SafeHtmlValue -Value $assignment.Type
                        $filterVal     = ConvertTo-SafeHtmlValue -Value $assignment.Filter
                        $filterModeVal = ConvertTo-SafeHtmlValue -Value $assignment.FilterMode
                        [void]$sb.AppendLine("<tr><td>$targetVal</td><td>$typeVal</td><td>$filterVal</td><td>$filterModeVal</td></tr>")
                    }
                    [void]$sb.AppendLine('</table>')
                }

                [void]$sb.AppendLine('</div>')
            }
        }

        [void]$sb.AppendLine('</div>')
        [void]$sb.AppendLine('</details>')
    }

    # --- Footer ---
    [void]$sb.AppendLine('<div class="footer">')
    [void]$sb.AppendLine("<p>Generated $generatedAt UTC &middot; $tenantNameEsc &middot; $totalPolicies policies across $totalProducts products</p>")
    [void]$sb.AppendLine('</div>')

    # --- JavaScript ---
    $jsBlock = @'
<script>
function toggleEmpty(){var b=document.body,n=document.getElementById('btn-toggle-empty');b.classList.toggle('hide-empty');if(b.classList.contains('hide-empty')){n.textContent='Show empty fields';n.classList.add('active')}else{n.textContent='Hide empty fields';n.classList.remove('active')}}
function toggleExpand(){var all=document.querySelectorAll('details.product-section'),btn=document.getElementById('btn-expand'),open=btn.classList.contains('active');all.forEach(function(d){d.open=!open});var toc=document.querySelectorAll('.toc-section details');toc.forEach(function(d){d.open=!open});if(!open){btn.textContent='Collapse all';btn.classList.add('active')}else{btn.textContent='Expand all';btn.classList.remove('active')}}
function toggleTheme(){var r=document.documentElement,b=document.getElementById('btn-theme');if(r.classList.contains('dark')){r.classList.remove('dark');r.classList.add('light');b.textContent='Dark mode';b.classList.remove('active');localStorage.setItem('theme','light')}else{r.classList.remove('light');r.classList.add('dark');b.textContent='Light mode';b.classList.add('active');localStorage.setItem('theme','dark')}}
(function(){var s=localStorage.getItem('theme'),b=document.getElementById('btn-theme');if(s==='dark'){document.documentElement.classList.add('dark');b.textContent='Light mode';b.classList.add('active')}else if(s==='light'){document.documentElement.classList.add('light')}else if(window.matchMedia&&window.matchMedia('(prefers-color-scheme: dark)').matches){b.textContent='Light mode'}})();
</script>
'@
    [void]$sb.AppendLine($jsBlock)

    [void]$sb.AppendLine('</body>')
    [void]$sb.Append('</html>')

    $sb.ToString()
}
