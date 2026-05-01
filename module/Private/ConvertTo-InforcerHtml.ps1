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
/* ══════════════════════════════════════════════════════════════════
   SHARED DESIGN TOKENS — identical between Export & Compare reports
   ══════════════════════════════════════════════════════════════════ */
:root {
    color-scheme: light dark;
    /* Surfaces — Inforcer blue tinted */
    --bg:          oklch(0.95 0.02 248);
    --bg-raised:   oklch(0.98 0.012 248);
    --bg-sunken:   oklch(0.91 0.03 250);
    --bg-overlay:  oklch(0.97 0.015 248 / 0.95);
    /* Text */
    --text:          oklch(0.18 0.03 255);
    --text-secondary: oklch(0.35 0.025 250);
    --text-muted:    oklch(0.50 0.02 248);
    /* Borders — blue tinted */
    --border:        oklch(0.82 0.03 250);
    --border-subtle: oklch(0.88 0.02 250);
    /* Brand — Inforcer blue */
    --accent:       oklch(0.52 0.18 250);
    --accent-hover: oklch(0.45 0.20 250);
    --accent-soft:  oklch(0.52 0.18 250 / 0.10);
    /* Semantic */
    --ok:      oklch(0.55 0.15 155);
    --ok-bg:   oklch(0.55 0.15 155 / 0.08);
    --warn:    oklch(0.60 0.16 70);
    --warn-bg: oklch(0.60 0.16 70 / 0.08);
    --bad:     oklch(0.55 0.20 25);
    --bad-bg:  oklch(0.55 0.20 25 / 0.07);
    --info:    oklch(0.55 0.14 250);
    --info-bg: oklch(0.55 0.14 250 / 0.08);
    /* Spacing scale (4pt) */
    --sp-2: 0.125rem;
    --sp-4: 0.25rem;
    --sp-8: 0.5rem;
    --sp-12: 0.75rem;
    --sp-16: 1rem;
    --sp-24: 1.5rem;
    --sp-32: 2rem;
    --sp-48: 3rem;
    /* Type scale — 6 steps, 1.25 ratio */
    --text-xs:   0.7rem;
    --text-sm:   0.8125rem;
    --text-base: 0.875rem;
    --text-md:   1rem;
    --text-lg:   1.25rem;
    --text-xl:   1.5rem;
    /* Radii */
    --radius:    8px;
    --radius-sm: 5px;
    /* Shadows — minimal, 2-tier */
    --shadow: 0 1px 3px oklch(0.20 0 0 / 0.06);
    --shadow-md: 0 2px 8px oklch(0.20 0 0 / 0.08);
    --transition: 150ms ease;
    /* Row */
    --row-alt: oklch(0.93 0.025 248);
    --row-hover: oklch(0.52 0.18 250 / 0.08);
    /* Sidebar */
    --sidebar-width: 300px;
}
/* ── Dark theme — Inforcer branded gradient ───────────────── */
:root.dark {
    --bg:          oklch(0.13 0.025 260);
    --bg-raised:   oklch(0.17 0.03 258);
    --bg-sunken:   oklch(0.10 0.02 262);
    --bg-overlay:  oklch(0.16 0.02 255 / 0.95);
    --text:          oklch(0.92 0.01 250);
    --text-secondary: oklch(0.72 0.015 250);
    --text-muted:    oklch(0.50 0.015 250);
    --border:        oklch(0.26 0.025 255);
    --border-subtle: oklch(0.22 0.02 255);
    --accent:       oklch(0.68 0.16 250);
    --accent-hover: oklch(0.74 0.14 250);
    --accent-soft:  oklch(0.68 0.16 250 / 0.12);
    --ok:      oklch(0.72 0.15 155);
    --ok-bg:   oklch(0.72 0.15 155 / 0.10);
    --warn:    oklch(0.75 0.14 70);
    --warn-bg: oklch(0.75 0.14 70 / 0.10);
    --bad:     oklch(0.70 0.18 25);
    --bad-bg:  oklch(0.70 0.18 25 / 0.08);
    --info:    oklch(0.70 0.14 250);
    --info-bg: oklch(0.70 0.14 250 / 0.10);
    --shadow: 0 1px 3px oklch(0 0 0 / 0.30);
    --shadow-md: 0 2px 8px oklch(0 0 0 / 0.40);
    --row-alt: oklch(0.15 0.025 258);
    --row-hover: oklch(0.68 0.16 250 / 0.08);
}
/* ── Reduced motion ─────────────────────────────────────────── */
@media (prefers-reduced-motion: reduce) {
    *, *::before, *::after { transition-duration: 0ms !important; animation-duration: 0ms !important; }
}
/* ══════════════════════════════════════════════════════════════
   BASE
   ══════════════════════════════════════════════════════════════ */
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
@font-face { font-family: 'Report'; src: local('Geist'), local('Inter'), local('Segoe UI'); font-display: swap; }
body {
    font-family: 'Report', system-ui, -apple-system, sans-serif;
    background: var(--bg);
    color: var(--text);
    line-height: 1.55;
    font-size: var(--text-base);
    -webkit-font-smoothing: antialiased;
}
:root.dark body {
    background: linear-gradient(145deg, oklch(0.12 0.04 250) 0%, oklch(0.10 0.05 260) 35%, oklch(0.11 0.06 275) 65%, oklch(0.13 0.07 295) 100%);
    background-attachment: fixed;
    min-height: 100vh;
}
/* ══════════════════════════════════════════════════════════════
   SIDEBAR — fixed, always visible on desktop
   ══════════════════════════════════════════════════════════════ */
.sidebar {
    position: fixed; top: 0; left: 0;
    width: var(--sidebar-width); height: 100vh;
    /* Light mode: white top → cyan → blue → purple (matching Inforcer light branding) */
    background: linear-gradient(160deg, oklch(0.97 0.01 240) 0%, oklch(0.82 0.08 220) 25%, oklch(0.65 0.14 245) 55%, oklch(0.55 0.16 280) 80%, oklch(0.50 0.18 295) 100%);
    border-right: none;
    z-index: 50;
    display: flex; flex-direction: column;
    transition: transform 0.25s ease, opacity 0.2s ease;
    color: oklch(0.20 0.02 250);
}
/* Light mode sidebar — very dark text everywhere for maximum readability */
.sidebar, .sidebar * { --sb-text: oklch(0.10 0.04 255); --sb-text-2: oklch(0.18 0.04 250); --sb-text-3: oklch(0.28 0.03 250); --sb-border: oklch(0.15 0.04 250 / 0.25); --sb-hover: oklch(0.10 0.04 250 / 0.08); --sb-active: oklch(0.10 0.04 250 / 0.15); }
/* Dark mode: vibrant cyan bottom-left → deep navy center → purple bottom-right */
:root.dark .sidebar {
    background: linear-gradient(160deg, oklch(0.15 0.06 260) 0%, oklch(0.20 0.10 240) 25%, oklch(0.13 0.06 260) 50%, oklch(0.18 0.12 285) 75%, oklch(0.22 0.14 300) 100%);
    color: oklch(0.90 0.02 250);
}
:root.dark .sidebar, :root.dark .sidebar * { --sb-text: oklch(0.92 0.01 250); --sb-text-2: oklch(0.75 0.04 250); --sb-text-3: oklch(0.60 0.04 260); --sb-border: oklch(0.35 0.06 265); --sb-hover: oklch(0.95 0.08 250 / 0.10); --sb-active: oklch(0.95 0.08 250 / 0.18); }
.main-content {
    margin-left: var(--sidebar-width);
    max-width: 1400px;
    padding: var(--sp-24) var(--sp-32) var(--sp-48);
}
/* Sidebar header */
.sidebar-header {
    padding: var(--sp-24) var(--sp-16) var(--sp-16);
    border-bottom: 1px solid var(--sb-border);
    flex-shrink: 0;
}
.sidebar-header h2 {
    font-size: var(--text-md); font-weight: 700;
    color: var(--sb-text);
}
/* Sidebar controls */
.sidebar-controls {
    padding: var(--sp-12) var(--sp-16);
    border-bottom: 1px solid var(--sb-border);
    display: flex; flex-direction: column; gap: var(--sp-4);
    flex-shrink: 0;
}
.toggle-row {
    display: flex; align-items: center; justify-content: space-between;
    padding: var(--sp-4) 0; font-size: var(--text-xs); color: var(--sb-text-2);
    cursor: pointer;
}
.toggle-row:hover { color: var(--sb-text); }
.sidebar .toggle-switch { position: relative; width: 34px; height: 18px; flex-shrink: 0; }
.sidebar .toggle-switch input { position: absolute; clip: rect(0,0,0,0); width: 1px; height: 1px; overflow: hidden; }
.sidebar .toggle-slider {
    position: absolute; inset: 0; background: var(--sb-border);
    border-radius: 9px; cursor: pointer; transition: background var(--transition);
}
.sidebar .toggle-slider::before {
    content: ''; position: absolute; left: 2px; top: 2px;
    width: 14px; height: 14px; background: oklch(0.95 0.01 250);
    border-radius: 50%; transition: transform var(--transition);
    box-shadow: 0 1px 2px oklch(0 0 0 / 0.3);
}
.sidebar .toggle-switch input:checked + .toggle-slider { background: oklch(0.60 0.16 240); }
.sidebar .toggle-switch input:checked + .toggle-slider::before { transform: translateX(16px); }
.sidebar .toggle-switch input:focus-visible + .toggle-slider { outline: 2px solid oklch(0.65 0.15 240); outline-offset: 2px; }
.sidebar .tooltip-icon { background: var(--sb-border); color: var(--sb-text-2); }
.sidebar .tooltip-icon::after { background: oklch(0.22 0.06 260); color: var(--sb-text); border-color: var(--sb-border); }
/* Search input — in main header */
.search-input {
    width: 100%; max-width: 400px; padding: var(--sp-8) var(--sp-12);
    border: 1px solid var(--border); border-radius: var(--radius);
    background: var(--bg-raised); color: var(--text);
    font-size: var(--text-sm); font-family: inherit; outline: none;
    transition: border-color 150ms ease;
}
.search-input:focus { border-color: var(--accent); }
.search-input:focus-visible { outline: 2px solid var(--accent); outline-offset: -2px; }
.search-result-count {
    font-size: var(--text-xs); color: var(--text-muted);
    margin-top: var(--sp-4); display: none;
}
.search-result-count.visible { display: block; }
/* Tag pills — inside branded sidebar */
.tag-filter {
    padding: var(--sp-8) var(--sp-16);
    border-bottom: 1px solid var(--sb-border);
    flex-shrink: 0;
}
.tag-filter-title {
    font-size: var(--text-xs); font-weight: 600;
    text-transform: uppercase; letter-spacing: 0.04em;
    color: var(--sb-text-3); margin-bottom: var(--sp-4);
}
.tag-pills { display: flex; flex-wrap: wrap; gap: var(--sp-4); }
.tag-pill {
    padding: 2px 8px; border: 1px solid var(--sb-border);
    border-radius: 99px; background: transparent;
    color: var(--sb-text-2); font-size: var(--text-xs);
    cursor: pointer; font-weight: 500; font-family: inherit;
    transition: all var(--transition);
}
.tag-pill:hover { border-color: oklch(0.65 0.15 240); color: oklch(0.80 0.10 240); }
.tag-pill:focus-visible { outline: 2px solid oklch(0.65 0.15 240); outline-offset: 1px; }
.tag-pill.active { background: oklch(0.55 0.16 250); color: oklch(0.98 0 0); border-color: oklch(0.55 0.16 250); }
/* Sidebar TOC — light text on dark branded background */
.sidebar-toc {
    flex: 1; overflow-y: auto;
    padding: var(--sp-8) var(--sp-12);
    scrollbar-width: thin;
    scrollbar-color: var(--sb-border) transparent;
}
.toc-list { list-style: none; }
.toc-product {
    margin-bottom: var(--sp-4);
}
.toc-product-btn {
    display: flex; align-items: center; gap: var(--sp-4);
    width: 100%; padding: var(--sp-4) var(--sp-8);
    background: none; border: none; border-radius: var(--radius-sm);
    color: var(--sb-text); font-size: var(--text-sm); font-weight: 600;
    cursor: pointer; font-family: inherit; text-align: left;
    transition: background var(--transition);
}
.toc-product-btn:hover { background: var(--sb-hover); }
.toc-product-btn:focus-visible { outline: 2px solid oklch(0.65 0.15 240); outline-offset: -2px; }
.toc-chevron {
    font-size: var(--text-xs); color: var(--sb-text-3);
    transition: transform var(--transition);
    display: inline-block; width: 1em; text-align: center;
}
.toc-product.open .toc-chevron { transform: rotate(90deg); }
.toc-count {
    margin-left: auto; font-size: var(--text-xs); font-weight: 600;
    color: oklch(0.20 0.03 255); background: oklch(1 0 0 / 0.85);
    padding: 0 6px; border-radius: 99px;
}
.toc-categories { display: none; list-style: none; padding-left: var(--sp-16); }
.toc-product.open .toc-categories { display: block; }
.toc-cat-link {
    display: block; padding: 3px var(--sp-8);
    border-radius: var(--radius-sm);
    color: var(--sb-text-2); font-size: var(--text-xs);
    text-decoration: none; font-weight: 500;
    transition: all var(--transition);
}
.toc-cat-link:hover { color: oklch(0.80 0.10 240); background: var(--sb-hover); }
.toc-cat-link:focus-visible { outline: 2px solid oklch(0.65 0.15 240); outline-offset: -2px; }
.toc-policies { list-style: none; padding-left: var(--sp-12); }
.toc-pol-link {
    display: block; padding: 2px var(--sp-8);
    border-radius: var(--radius-sm);
    color: var(--sb-text-3); font-size: var(--text-xs);
    text-decoration: none;
    transition: all var(--transition);
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
    max-width: 220px;
}
.toc-pol-link:hover { color: oklch(0.80 0.10 240); background: var(--sb-hover); }
.toc-pol-link:focus-visible { outline: 2px solid oklch(0.65 0.15 240); outline-offset: -2px; }
/* ══════════════════════════════════════════════════════════════
   STICKY BREADCRUMB
   ══════════════════════════════════════════════════════════════ */
.breadcrumb {
    position: sticky; top: 0; z-index: 40;
    background: var(--bg-overlay);
    backdrop-filter: blur(8px);
    -webkit-backdrop-filter: blur(8px);
    padding: var(--sp-8) var(--sp-16);
    border-bottom: 1px solid var(--border);
    font-size: var(--text-xs); color: var(--text-muted);
    display: flex; align-items: center; gap: var(--sp-8);
    opacity: 0; transform: translateY(-100%);
    transition: opacity 0.2s ease, transform 0.2s ease;
    pointer-events: none;
}
.breadcrumb.visible {
    opacity: 1; transform: translateY(0);
    pointer-events: auto;
}
.breadcrumb .bc-tenant { font-weight: 600; color: var(--text-secondary); }
.breadcrumb .bc-sep { color: var(--text-muted); }
.breadcrumb .bc-section { color: var(--accent); font-weight: 500; }
/* ══════════════════════════════════════════════════════════════
   HEADER
   ══════════════════════════════════════════════════════════════ */
.report-header {
    padding-bottom: var(--sp-16);
    border-bottom: 2px solid var(--border);
    margin-bottom: var(--sp-24);
}
.report-header h1 {
    font-size: var(--text-xl); font-weight: 700; letter-spacing: -0.02em;
    margin-bottom: var(--sp-8);
}
.report-meta {
    display: flex; gap: var(--sp-16); flex-wrap: wrap;
    font-size: var(--text-xs); color: var(--text-muted);
}
.report-meta .meta-item { display: flex; align-items: center; gap: var(--sp-4); }
/* ══════════════════════════════════════════════════════════════
   PRODUCT SECTIONS — collapsible
   ══════════════════════════════════════════════════════════════ */
.product-section { margin-bottom: var(--sp-24); }
.product-header {
    display: flex; align-items: center; gap: var(--sp-8);
    padding: var(--sp-12) var(--sp-16);
    background: var(--bg-raised); border: 1px solid var(--border);
    border-radius: var(--radius);
    cursor: pointer;
    transition: box-shadow var(--transition);
}
.product-header:hover { box-shadow: var(--shadow); }
.product-header:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
.product-chevron {
    font-size: var(--text-xs); color: var(--text-muted);
    transition: transform var(--transition);
    display: inline-block;
}
.product-section.open .product-chevron { transform: rotate(90deg); }
.product-name { font-size: var(--text-md); font-weight: 700; flex: 1; }
.product-count {
    font-size: var(--text-xs); color: var(--text-muted);
    background: var(--bg-sunken); padding: 2px 10px;
    border-radius: 99px; font-weight: 500;
}
.product-body {
    display: none;
    padding: var(--sp-16) 0 0;
}
.product-section.open .product-body { display: block; }
/* ══════════════════════════════════════════════════════════════
   CATEGORY HEADINGS — stronger landmark
   ══════════════════════════════════════════════════════════════ */
.category-heading {
    font-size: var(--text-sm); font-weight: 600;
    color: var(--text-secondary);
    text-transform: uppercase; letter-spacing: 0.04em;
    padding: var(--sp-8) var(--sp-12);
    margin: var(--sp-24) 0 var(--sp-12);
    background: var(--bg-sunken);
    border-radius: var(--radius-sm);
    border-left: none;
}
.category-heading:first-child { margin-top: var(--sp-8); }
/* ══════════════════════════════════════════════════════════════
   POLICY CARDS
   ══════════════════════════════════════════════════════════════ */
.policy-card {
    background: var(--bg-raised);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    padding: var(--sp-16);
    margin-bottom: var(--sp-8);
    transition: border-color var(--transition);
}
.policy-card:hover { border-color: var(--text-muted); }
.policy-name-row {
    display: flex; align-items: baseline; gap: var(--sp-8);
    flex-wrap: wrap; margin-bottom: var(--sp-12);
}
.policy-title { font-size: var(--text-base); font-weight: 600; }
.badge {
    display: inline-flex; align-items: center;
    padding: 1px 8px; border-radius: 99px;
    font-size: var(--text-xs); font-weight: 500;
    background: var(--accent-soft); color: var(--accent);
}
.badge-tag {
    background: var(--info-bg); color: var(--info);
    border: 1px solid oklch(0.55 0.14 250 / 0.2);
}
/* Section labels within policy cards */
.section-label {
    font-size: var(--text-xs); font-weight: 600;
    color: var(--text-muted); text-transform: uppercase;
    letter-spacing: 0.04em;
    margin: var(--sp-12) 0 var(--sp-4);
}
.section-label:first-child { margin-top: 0; }
/* ══════════════════════════════════════════════════════════════
   TABLES
   ══════════════════════════════════════════════════════════════ */
.table-wrap { overflow-x: auto; border: 1px solid var(--border); border-radius: var(--radius-sm); margin-bottom: var(--sp-8); overflow: hidden; }
table { width: 100%; border-collapse: collapse; font-size: var(--text-sm); }
table.t2 { table-layout: fixed; }
table.t2 th:first-child, table.t2 td:first-child { width: 50%; }
table.t2 th:last-child, table.t2 td:last-child { width: 50%; }
table.t4 { table-layout: auto; }
th {
    background: oklch(0.42 0.14 250); text-align: left;
    padding: var(--sp-8) var(--sp-12);
    font-weight: 600; font-size: var(--text-xs);
    text-transform: uppercase; letter-spacing: 0.04em;
    color: oklch(0.95 0.01 250);
    border-bottom: none;
}
:root.dark th {
    background: oklch(0.24 0.06 258);
    color: oklch(0.82 0.02 250);
}
td {
    padding: 3px var(--sp-8);
    border-bottom: 1px solid var(--border-subtle);
    vertical-align: top; color: var(--text);
    word-break: break-word; font-size: var(--text-sm); line-height: 1.4;
}
td:first-child { font-weight: 500; color: var(--text-secondary); }
tr:last-child td { border-bottom: none; }
tr:hover td { background: var(--row-hover); }
.muted { color: var(--text-muted); font-style: italic; }
.value-cell { font-family: 'Cascadia Code', 'Fira Code', 'SF Mono', monospace; font-size: var(--text-xs); }
/* Long value truncation */
.long-val { display: block; max-height: 12em; overflow: hidden; position: relative; word-break: break-all; }
.long-val.expanded { max-height: none; }
.long-val-btn {
    display: inline-block; margin-top: var(--sp-4); padding: 1px 8px;
    background: var(--accent-soft); color: var(--accent); border: 1px solid var(--accent);
    border-radius: var(--radius-sm); font-size: var(--text-xs); font-weight: 600;
    cursor: pointer; transition: all var(--transition); font-family: inherit;
}
.long-val-btn:hover { background: var(--accent); color: oklch(1 0 0); }
.long-val-btn:focus-visible { outline: 2px solid var(--accent); outline-offset: 1px; }
/* Multi-value list display */
.mv-list { list-style: none; margin: 0; padding: 0; }
.mv-list li { padding: 0.125rem 0; }
.mv-list li + li { border-top: 1px solid var(--border-subtle); }
.mv-hidden { display: none; }
.mv-btn {
    display: inline-block; font-size: var(--text-xs); font-weight: 600;
    padding: 1px 8px; border-radius: var(--radius-sm);
    background: var(--accent-soft); color: var(--accent);
    cursor: pointer; margin-top: var(--sp-4); user-select: none;
    border: none; transition: background var(--transition); font-family: inherit;
}
.mv-btn:hover { background: var(--accent); color: oklch(1 0 0); }
.mv-btn:focus-visible { outline: 2px solid var(--accent); outline-offset: 1px; }
/* Script code blocks */
.script-collapsible { margin: 0.25rem 0; }
.script-collapsible summary {
    cursor: pointer; font-size: var(--text-xs); font-weight: 600;
    user-select: none; list-style: none;
    display: inline-flex; align-items: center; gap: var(--sp-4);
    padding: 3px 10px; border-radius: var(--radius-sm);
    transition: all var(--transition); font-family: inherit;
}
.script-collapsible summary::before { content: none !important; }
.script-collapsible summary::after { content: '\25B6'; font-size: 0.55rem; transition: transform 0.2s; }
.script-collapsible[open] summary::after { transform: rotate(90deg); }
.script-collapsible summary::-webkit-details-marker { display: none; }
.script-collapsible summary:focus-visible { outline: 2px solid var(--accent); outline-offset: 1px; }
.script-collapsible pre {
    margin: var(--sp-8) 0 0; padding: var(--sp-12);
    border-radius: var(--radius-sm); font-size: var(--text-xs);
    line-height: 1.5; overflow-x: auto;
    white-space: pre-wrap; word-break: break-all; max-height: 25em;
}
.ps-code { background: oklch(0.15 0.01 250) !important; color: oklch(0.85 0.01 250); }
.ps-code-summary { color: oklch(0.60 0.10 250); border: 1px solid oklch(0.60 0.10 250 / 0.3); background: oklch(0.60 0.10 250 / 0.1); }
.ps-code-summary:hover { background: oklch(0.60 0.10 250 / 0.2); }
.sh-code { background: oklch(0.12 0.01 250) !important; color: oklch(0.80 0.01 250); }
.sh-code-summary { color: oklch(0.65 0.15 25); border: 1px solid oklch(0.65 0.15 25 / 0.3); background: oklch(0.65 0.15 25 / 0.1); }
.sh-code-summary:hover { background: oklch(0.65 0.15 25 / 0.2); }
.json-code { background: oklch(0.13 0.02 260) !important; color: oklch(0.80 0.02 250); }
.json-code-summary { color: oklch(0.60 0.10 260); border: 1px solid oklch(0.60 0.10 260 / 0.3); background: oklch(0.60 0.10 260 / 0.1); }
.json-code-summary:hover { background: oklch(0.60 0.10 260 / 0.2); }
.json-key { color: #7aa2f7; }
.json-string { color: #9ece6a; }
.json-bool { color: #ff9e64; font-weight: 600; }
.json-number { color: #e0af68; }
.ps-keyword { color: #569cd6; font-weight: 600; }
.ps-string { color: #ce9178; }
.ps-variable { color: #9cdcfe; }
.ps-comment { color: #6a9955; font-style: italic; }
.ps-cmdlet { color: #dcdcaa; }
.ps-type { color: #4ec9b0; }
.sh-keyword { color: #ff7b72; font-weight: 600; }
.sh-string { color: #a5d6ff; }
.sh-variable { color: #ffa657; }
.sh-command { color: #d2a8ff; }
.sh-comment { color: #8b949e; font-style: italic; }
/* Metadata rows (hidden by default, shown via toggle) */
.metadata-row { display: none; }
.show-metadata .metadata-row { display: table-row; }
/* Tooltip icon */
.tooltip-icon {
    display: inline-flex; align-items: center; justify-content: center;
    width: 16px; height: 16px; border-radius: 50%;
    background: var(--border); color: var(--text-secondary);
    font-size: 0.625rem; font-weight: 700; cursor: help;
    position: relative; margin-left: var(--sp-4); flex-shrink: 0;
}
.tooltip-icon::after {
    content: attr(data-tip);
    position: absolute; left: 50%; bottom: 130%; transform: translateX(-50%);
    background: var(--bg-raised); color: var(--text); border: 1px solid var(--border);
    border-radius: var(--radius-sm); padding: var(--sp-4) var(--sp-8);
    font-size: var(--text-xs); font-weight: 400; white-space: nowrap;
    box-shadow: var(--shadow-md); pointer-events: none;
    opacity: 0; transition: opacity var(--transition);
    z-index: 10;
}
.tooltip-icon:hover::after { opacity: 1; }
/* Filter toggle — hide empty rows in 2-column tables only */
.hide-empty table.t2 tr:has(td:last-child > .empty-val:only-child):not(:has(td:first-child > .empty-val)) { display: none; }
/* Search */
.search-hidden { display: none !important; }
.tag-hidden { display: none !important; }
.search-highlight { background: oklch(0.85 0.12 85 / 0.3); border-radius: 2px; }
/* ══════════════════════════════════════════════════════════════
   THEME TOGGLE — small fixed button
   ══════════════════════════════════════════════════════════════ */
.theme-toggle {
    position: fixed; top: var(--sp-12); right: var(--sp-12); z-index: 50;
    width: 32px; height: 32px; border-radius: 50%;
    border: 1px solid var(--border); background: var(--bg-raised);
    color: var(--text); cursor: pointer;
    display: flex; align-items: center; justify-content: center;
    transition: border-color var(--transition);
    font-size: var(--text-sm);
}
.theme-toggle:hover { border-color: var(--accent); }
.theme-toggle:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
/* ══════════════════════════════════════════════════════════════
   SCROLL TO TOP + MOBILE SIDEBAR FAB
   ══════════════════════════════════════════════════════════════ */
.fab-top {
    position: fixed; bottom: var(--sp-24); right: var(--sp-24); z-index: 50;
    width: 36px; height: 36px; border-radius: 50%;
    background: var(--accent); color: oklch(1 0 0);
    border: none; cursor: pointer;
    display: flex; align-items: center; justify-content: center;
    box-shadow: var(--shadow-md);
    opacity: 0; pointer-events: none;
    transition: opacity var(--transition), transform var(--transition);
    font-size: var(--text-md);
}
.fab-top.visible { opacity: 1; pointer-events: auto; }
.fab-top:hover { transform: scale(1.08); }
.fab-top:focus-visible { outline: 2px solid var(--accent); outline-offset: 3px; }
.fab-sidebar {
    position: fixed; bottom: var(--sp-24); left: var(--sp-24); z-index: 50;
    width: 36px; height: 36px; border-radius: 50%;
    background: var(--accent); color: oklch(1 0 0);
    border: none; cursor: pointer;
    display: none; align-items: center; justify-content: center;
    box-shadow: var(--shadow-md);
    font-size: var(--text-md);
    transition: transform var(--transition);
}
.fab-sidebar:hover { transform: scale(1.08); }
.fab-sidebar:focus-visible { outline: 2px solid var(--accent); outline-offset: 3px; }
/* ══════════════════════════════════════════════════════════════
   FOOTER
   ══════════════════════════════════════════════════════════════ */
.report-footer {
    margin-top: var(--sp-48); padding-top: var(--sp-16);
    border-top: 1px solid var(--border);
    font-size: var(--text-xs); color: var(--text-muted);
    display: flex; flex-direction: column; gap: var(--sp-4);
}
.report-footer a { color: var(--accent); text-decoration: none; }
.report-footer a:hover { text-decoration: underline; }
.footer-warning { font-style: italic; }
/* ══════════════════════════════════════════════════════════════
   PRINT
   ══════════════════════════════════════════════════════════════ */
@media print {
    .sidebar, .theme-toggle, .fab-top, .fab-sidebar, .breadcrumb { display: none !important; }
    .main-content { margin-left: 0 !important; max-width: none; padding: 0.5cm; font-size: 9pt; }
    .product-body { display: block !important; }
    .policy-card { break-inside: avoid; }
    .code-block, .script-collapsible pre { display: block !important; }
}
/* ══════════════════════════════════════════════════════════════
   RESPONSIVE
   ══════════════════════════════════════════════════════════════ */
@media (max-width: 1024px) {
    .sidebar { transform: translateX(calc(-1 * var(--sidebar-width))); opacity: 0; pointer-events: none; }
    .sidebar.mobile-open { transform: translateX(0); opacity: 1; pointer-events: auto; }
    .main-content { margin-left: 0; padding: var(--sp-16); }
    .fab-sidebar { display: flex; }
}
'@

    # -------------------------------------------------------------------------
    # Helper: encode a value for HTML output (null/empty -> muted em dash)
    # -------------------------------------------------------------------------
    function ConvertTo-SafeHtmlValue {
        param(
            [Parameter()][object]$Value,
            [Parameter()][switch]$AllowMultiValue
        )
        if ($null -eq $Value -or ($Value -is [string] -and [string]::IsNullOrEmpty($Value))) {
            return '<span class="muted empty-val">&mdash;</span>'
        }
        # Handle arrays — join string/value elements instead of returning "System.Object[]"
        if ($Value -is [array]) {
            $joined = @($Value | ForEach-Object {
                if ($_ -is [string] -or $_ -is [ValueType]) { $_.ToString() }
                else { $_.ToString() }
            }) -join ', '
            $str = if ([string]::IsNullOrWhiteSpace($joined) -and $Value.Count -gt 0) { "$($Value.Count) items" } else { $joined }
        } else {
            $str = $Value.ToString()
        }
        # Multi-value comma-separated list — render as vertical list (only for setting values, not prose)
        if ($AllowMultiValue -and $str -match ',') {
            $items = $str -split ',\s*' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
            if ($items.Count -ge 2) {
                $mvId = "mv$(Get-Random)"
                $sb2 = [System.Text.StringBuilder]::new()
                [void]$sb2.Append('<ul class="mv-list">')
                $i = 0
                foreach ($item in $items) {
                    $encItem = [System.Net.WebUtility]::HtmlEncode($item)
                    if ($items.Count -gt 10 -and $i -ge 10) {
                        [void]$sb2.Append("<li class=`"mv-hidden $mvId`">$encItem</li>")
                    } else {
                        [void]$sb2.Append("<li>$encItem</li>")
                    }
                    $i++
                }
                [void]$sb2.Append('</ul>')
                if ($items.Count -gt 10) {
                    $remaining = $items.Count - 10
                    [void]$sb2.Append("<span class=`"mv-btn`" onclick=`"var h=this.closest('td').querySelectorAll('.$mvId');var show=h[0].style.display!=='list-item';h.forEach(function(e){e.style.display=show?'list-item':'none'});this.textContent=show?'Collapse':'+ $remaining more'`">+ $remaining more</span>")
                }
                return $sb2.ToString()
            }
        }
        $str = [System.Net.WebUtility]::HtmlEncode($str)
        # Wrap long values (>200 chars) in a collapsible block with ellipsis button
        if ($str.Length -gt 200) {
            return "<span class=`"long-val`" id=`"lv$(Get-Random)`">$str</span><span class=`"long-val-btn`" onclick=`"var v=this.previousElementSibling;v.classList.toggle('expanded');this.textContent=v.classList.contains('expanded')?'Collapse':'Expand'`">Expand</span>"
        }
        return $str
    }

    # -------------------------------------------------------------------------
    # Helper: determine if a setting name is a metadata field
    # -------------------------------------------------------------------------
    function Test-MetadataSetting {
        param([Parameter()][string]$Name)
        if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
        if ($Name -match '@odata') { return $true }
        if ($Name -eq 'policyGuid') { return $true }
        return $false
    }

    # -------------------------------------------------------------------------
    # StringBuilder assembly
    # -------------------------------------------------------------------------
    $sb = [System.Text.StringBuilder]::new(65536)

    $tenantNameEsc    = [System.Net.WebUtility]::HtmlEncode($DocModel.TenantName)
    $baselineNames    = if ($DocModel.Baselines) { $DocModel.Baselines } else { @() }
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
    [void]$sb.AppendLine('<body class="hide-empty">')

    # --- Sidebar ---
    [void]$sb.AppendLine('<aside class="sidebar" id="sidebar">')

    # Sidebar header — show tenant name
    [void]$sb.AppendLine('<div class="sidebar-header">')
    [void]$sb.AppendLine("<h2>$tenantNameEsc</h2>")
    [void]$sb.AppendLine('</div>')

    # Sidebar controls (hide-empty, expand-all, show-metadata — dark mode moved to fixed button)
    [void]$sb.AppendLine('<div class="sidebar-controls">')
    [void]$sb.AppendLine('<label class="toggle-row"><span>Hide empty fields</span><span class="toggle-switch"><input type="checkbox" id="chk-empty" checked onchange="toggleEmpty()"><span class="toggle-slider"></span></span></label>')
    [void]$sb.AppendLine('<label class="toggle-row"><span>Expand all sections</span><span class="toggle-switch"><input type="checkbox" id="chk-expand" onchange="toggleExpand()"><span class="toggle-slider"></span></span></label>')
    [void]$sb.AppendLine('<label class="toggle-row"><span>Show metadata<span class="tooltip-icon" data-tip="Show @odata.type and other metadata properties in settings tables">i</span></span><span class="toggle-switch"><input type="checkbox" id="chk-meta" onchange="toggleMeta()"><span class="toggle-slider"></span></span></label>')
    [void]$sb.AppendLine('</div>')

    # Search moved to main header area

    # Sidebar tag filter pills (collect all unique tags from policies)
    $allTags = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($prodVal in $DocModel.Products.Values) {
        foreach ($catPols in $prodVal.Categories.Values) {
            foreach ($pol in @($catPols)) {
                $t = $pol.Basics['Tags']
                if (-not [string]::IsNullOrWhiteSpace($t)) {
                    foreach ($tagName in ($t -split ',\s*')) {
                        if (-not [string]::IsNullOrWhiteSpace($tagName)) { [void]$allTags.Add($tagName.Trim()) }
                    }
                }
            }
        }
    }
    if ($allTags.Count -gt 0) {
        [void]$sb.AppendLine('<div class="tag-filter">')
        [void]$sb.AppendLine('<div class="tag-filter-title">Tags</div>')
        [void]$sb.AppendLine('<div class="tag-pills">')
        foreach ($tagName in $allTags) {
            $tagEsc = [System.Net.WebUtility]::HtmlEncode($tagName)
            $tagSafe = $tagName -replace '[^a-zA-Z0-9 \-]', ''
            [void]$sb.AppendLine("<button class=`"tag-pill`" data-tag=`"$tagSafe`" onclick=`"toggleTagFilter(this,this.getAttribute('data-tag'))`">$tagEsc</button>")
        }
        [void]$sb.AppendLine('</div>')
        [void]$sb.AppendLine('</div>')
    }

    # Sidebar TOC — new toc-product / toc-categories / toc-policies structure
    [void]$sb.AppendLine('<nav class="sidebar-toc">')
    [void]$sb.AppendLine('<ul class="toc-list">')

    foreach ($prodName in $DocModel.Products.Keys) {
        $prodEsc    = [System.Net.WebUtility]::HtmlEncode($prodName)
        $prodAnchor = ConvertTo-HtmlAnchorId -Text $prodName

        $prodPolicies = 0
        foreach ($cp in $DocModel.Products[$prodName].Categories.Values) { $prodPolicies += @($cp).Count }

        [void]$sb.AppendLine('<li class="toc-product">')
        [void]$sb.AppendLine("<button class=`"toc-product-btn`" onclick=`"this.parentElement.classList.toggle('open');navClick(null,'$prodAnchor')`">")
        [void]$sb.AppendLine('<span class="toc-chevron">&#9654;</span>')
        [void]$sb.AppendLine("$prodEsc")
        [void]$sb.AppendLine("<span class=`"toc-count`">$prodPolicies</span>")
        [void]$sb.AppendLine('</button>')
        [void]$sb.AppendLine('<ul class="toc-categories">')

        # Group categories by their first part (before " / ") for nested display
        $catGroups = [ordered]@{}
        foreach ($catName in ($DocModel.Products[$prodName].Categories.Keys | Sort-Object)) {
            if ($catName -match '^(.+?) / (.+)$') {
                $groupName = $Matches[1]
                if ($groupName -eq 'All') { $groupName = $Matches[2]; $subName = $null }
                else { $subName = $Matches[2] }
            } else {
                $groupName = $catName; $subName = $null
            }
            if (-not $catGroups.Contains($groupName)) { $catGroups[$groupName] = [System.Collections.Generic.List[object]]::new() }
            [void]$catGroups[$groupName].Add(@{ CatName = $catName; SubName = $subName })
        }

        foreach ($groupName in $catGroups.Keys) {
            $groupEntries = $catGroups[$groupName]
            $groupEsc = [System.Net.WebUtility]::HtmlEncode($groupName)

            if ($groupEntries.Count -eq 1 -and $null -eq $groupEntries[0].SubName) {
                # Single category — show category link with policy children
                $catName = $groupEntries[0].CatName
                $catAnchor = ConvertTo-HtmlAnchorId -Text "$prodName-$catName"
                $catPolicies = @($DocModel.Products[$prodName].Categories[$catName])

                [void]$sb.AppendLine('<li>')
                [void]$sb.AppendLine("<a class=`"toc-cat-link`" href=`"#$catAnchor`" onclick=`"navClick(event,'$catAnchor')`">$groupEsc</a>")
                [void]$sb.AppendLine('<ul class="toc-policies">')
                foreach ($pol in $catPolicies) {
                    $polNameEsc = [System.Net.WebUtility]::HtmlEncode($pol.Basics.Name)
                    $polAnchor  = ConvertTo-HtmlAnchorId -Text "$prodName-$catName-$($pol.Basics.Name)"
                    [void]$sb.AppendLine("<li><a class=`"toc-pol-link`" href=`"#$polAnchor`" onclick=`"navClick(event,'$polAnchor')`">$polNameEsc</a></li>")
                }
                [void]$sb.AppendLine('</ul>')
                [void]$sb.AppendLine('</li>')
            } else {
                # Group with subcategories
                foreach ($entry in $groupEntries) {
                    $catName = $entry.CatName
                    $subDisplay = if ($entry.SubName) { "$groupEsc / $($entry.SubName)" } else { $groupEsc }
                    $subEsc = [System.Net.WebUtility]::HtmlEncode($subDisplay)
                    $catAnchor = ConvertTo-HtmlAnchorId -Text "$prodName-$catName"

                    [void]$sb.AppendLine('<li>')
                    [void]$sb.AppendLine("<a class=`"toc-cat-link`" href=`"#$catAnchor`" onclick=`"navClick(event,'$catAnchor')`">$subEsc</a>")
                    [void]$sb.AppendLine('<ul class="toc-policies">')
                    foreach ($pol in @($DocModel.Products[$prodName].Categories[$catName])) {
                        $polNameEsc = [System.Net.WebUtility]::HtmlEncode($pol.Basics.Name)
                        $polAnchor  = ConvertTo-HtmlAnchorId -Text "$prodName-$catName-$($pol.Basics.Name)"
                        [void]$sb.AppendLine("<li><a class=`"toc-pol-link`" href=`"#$polAnchor`" onclick=`"navClick(event,'$polAnchor')`">$polNameEsc</a></li>")
                    }
                    [void]$sb.AppendLine('</ul>')
                    [void]$sb.AppendLine('</li>')
                }
            }
        }

        [void]$sb.AppendLine('</ul>')
        [void]$sb.AppendLine('</li>')
    }

    [void]$sb.AppendLine('</ul>')
    [void]$sb.AppendLine('</nav>')
    [void]$sb.AppendLine('</aside>')

    # --- Theme toggle button (fixed, top-right) ---
    [void]$sb.AppendLine('<button class="theme-toggle" id="btn-theme" onclick="toggleTheme()" aria-label="Toggle theme">&#9681;</button>')

    # --- Scroll to top FAB ---
    [void]$sb.AppendLine('<button class="fab-top" id="btn-top" onclick="window.scrollTo({top:0,behavior:''smooth''})" aria-label="Scroll to top">&#8593;</button>')

    # --- Mobile sidebar FAB ---
    [void]$sb.AppendLine('<button class="fab-sidebar" id="btn-sidebar" onclick="document.getElementById(''sidebar'').classList.toggle(''mobile-open'')" aria-label="Open navigation">&#9776;</button>')

    # --- Main content wrapper ---
    [void]$sb.AppendLine('<div class="main-content">')

    # --- Sticky breadcrumb ---
    [void]$sb.AppendLine('<div class="breadcrumb" id="breadcrumb">')
    [void]$sb.AppendLine("<span class=`"bc-tenant`">$tenantNameEsc</span>")
    [void]$sb.AppendLine('<span class="bc-sep">/</span>')
    [void]$sb.AppendLine('<span class="bc-section" id="bc-section"></span>')
    [void]$sb.AppendLine('</div>')

    # --- Header ---
    [void]$sb.AppendLine('<header class="report-header">')
    [void]$sb.AppendLine("<h1>$tenantNameEsc</h1>")
    [void]$sb.AppendLine('<div class="report-meta">')
    [void]$sb.AppendLine("<span class=`"meta-item`">$generatedAt UTC</span>")
    [void]$sb.AppendLine("<span class=`"meta-item`">$totalProducts products</span>")
    [void]$sb.AppendLine("<span class=`"meta-item`">$totalPolicies policies</span>")
    if ($baselineNames.Count -gt 0) {
        [void]$sb.AppendLine("<span class=`"meta-item`">$($baselineNames.Count) baselines</span>")
    }
    if ($DocModel.FilterBaseline) {
        $filterBaselineEsc = [System.Net.WebUtility]::HtmlEncode($DocModel.FilterBaseline)
        [void]$sb.AppendLine("<span class=`"meta-item`" style=`"color:var(--accent);font-weight:600`">Baseline: $filterBaselineEsc</span>")
    }
    if ($DocModel.FilterTag) {
        $filterTagEsc = [System.Net.WebUtility]::HtmlEncode($DocModel.FilterTag)
        [void]$sb.AppendLine("<span class=`"meta-item`" style=`"color:var(--accent);font-weight:600`">Tag: $filterTagEsc</span>")
    }
    [void]$sb.AppendLine('</div>')
    [void]$sb.AppendLine('<div class="search-bar" style="margin-top:var(--sp-12)">')
    [void]$sb.AppendLine('<input class="search-input" type="text" id="search-input" placeholder="Search policies, settings, values..." aria-label="Search" oninput="searchPolicies(this.value)">')
    [void]$sb.AppendLine('<div class="search-result-count" id="search-count"></div>')
    [void]$sb.AppendLine('</div>')
    [void]$sb.AppendLine('</header>')

    # --- Content sections ---
    $isFirstProduct = $true
    foreach ($prodName in $DocModel.Products.Keys) {
        $prodEsc    = [System.Net.WebUtility]::HtmlEncode($prodName)
        $prodAnchor = ConvertTo-HtmlAnchorId -Text $prodName

        $prodPolicyCount = 0
        foreach ($catPolicies in $DocModel.Products[$prodName].Categories.Values) {
            $prodPolicyCount += @($catPolicies).Count
        }

        # Product-level collapsible section (first product open by default)
        $openClass = if ($isFirstProduct) { ' open' } else { '' }
        $ariaExpanded = if ($isFirstProduct) { 'true' } else { 'false' }
        [void]$sb.AppendLine("<div class=`"product-section$openClass`" id=`"product-$prodAnchor`">")
        [void]$sb.AppendLine("<div class=`"product-header`" onclick=`"this.parentElement.classList.toggle('open')`" tabindex=`"0`" role=`"button`" aria-expanded=`"$ariaExpanded`">")
        [void]$sb.AppendLine('<span class="product-chevron">&#9654;</span>')
        [void]$sb.AppendLine("<span class=`"product-name`">$prodEsc</span>")
        [void]$sb.AppendLine("<span class=`"product-count`">$prodPolicyCount policies</span>")
        [void]$sb.AppendLine('</div>')
        [void]$sb.AppendLine('<div class="product-body">')

        foreach ($catName in ($DocModel.Products[$prodName].Categories.Keys | Sort-Object)) {
            $catDisplayName = $catName -replace '^All / ', ''
            $catEsc    = [System.Net.WebUtility]::HtmlEncode($catDisplayName)
            $catAnchor = ConvertTo-HtmlAnchorId -Text "$prodName-$catName"
            $policies  = $DocModel.Products[$prodName].Categories[$catName]

            [void]$sb.AppendLine("<div class=`"category-heading`" id=`"$catAnchor`">$catEsc</div>")

            foreach ($policy in @($policies)) {
                $policyNameEsc   = [System.Net.WebUtility]::HtmlEncode($policy.Basics.Name)
                $settingsCount   = if ($policy.Settings) { @($policy.Settings).Count } else { 0 }
                $policyAnchor    = ConvertTo-HtmlAnchorId -Text "$prodName-$catName-$($policy.Basics.Name)"

                $tagsAttr = ''
                $tagsVal = $policy.Basics['Tags']
                if (-not [string]::IsNullOrWhiteSpace($tagsVal)) {
                    $tagsAttr = " data-tags=`"$([System.Net.WebUtility]::HtmlEncode($tagsVal))`""
                }
                [void]$sb.AppendLine("<div class=`"policy-card`" id=`"$policyAnchor`"$tagsAttr>")

                # Policy name row with badges
                [void]$sb.AppendLine('<div class="policy-name-row">')
                [void]$sb.AppendLine("<span class=`"policy-title`">$policyNameEsc</span>")
                [void]$sb.AppendLine("<span class=`"badge`">$settingsCount settings</span>")
                if (-not [string]::IsNullOrWhiteSpace($tagsVal)) {
                    foreach ($tagName in ($tagsVal -split ',\s*')) {
                        $tagEsc = [System.Net.WebUtility]::HtmlEncode($tagName.Trim())
                        [void]$sb.AppendLine("<span class=`"badge badge-tag`">$tagEsc</span>")
                    }
                }
                [void]$sb.AppendLine('</div>')

                # --- Basics table (only non-empty fields) ---
                $basicsProps = @('Description', 'ProfileType', 'Platform', 'Created', 'Modified', 'ScopeTags')
                $nonEmptyBasics = @($basicsProps | Where-Object {
                    $val = $policy.Basics[$_]
                    $null -ne $val -and ($val -isnot [string] -or -not [string]::IsNullOrWhiteSpace($val))
                })

                if ($nonEmptyBasics.Count -gt 0) {
                    [void]$sb.AppendLine('<div class="section-label">Basics</div>')
                    [void]$sb.AppendLine('<div class="table-wrap"><table class="t2">')
                    [void]$sb.AppendLine('<tr><th>Property</th><th>Value</th></tr>')
                    foreach ($propName in $nonEmptyBasics) {
                        $propLabel = [System.Net.WebUtility]::HtmlEncode($propName)
                        $propVal   = ConvertTo-SafeHtmlValue -Value $policy.Basics[$propName]
                        [void]$sb.AppendLine("<tr><td>$propLabel</td><td>$propVal</td></tr>")
                    }
                    [void]$sb.AppendLine('</table></div>')
                }

                # --- Settings table ---
                if ($settingsCount -gt 0) {
                    [void]$sb.AppendLine('<div class="section-label">Settings</div>')
                    [void]$sb.AppendLine('<div class="table-wrap"><table class="t2">')
                    [void]$sb.AppendLine('<tr><th>Setting</th><th>Value</th></tr>')
                    foreach ($setting in @($policy.Settings)) {
                        $settingNameEsc = [System.Net.WebUtility]::HtmlEncode($setting.Name)
                        $indentLevel    = if ($null -ne $setting.Indent) { [int]$setting.Indent } else { 0 }
                        $paddingRem     = $indentLevel * 1.5

                        # Script code blocks — render as collapsible <details> with syntax highlighting
                        if ("$($setting.Value)" -match '^__SCRIPT_CODE__') {
                            $scriptCode = "$($setting.Value)".Substring('__SCRIPT_CODE__'.Length)
                            $encCode = [System.Net.WebUtility]::HtmlEncode($scriptCode)
                            $trimmed = $scriptCode.TrimStart()
                            if ($trimmed -match '^\s*[\{\[]') { $codeClass = 'json-code'; $summaryClass = 'json-code-summary'; $label = 'View JSON' }
                            elseif ($trimmed -match '^\s*#!/') { $codeClass = 'sh-code'; $summaryClass = 'sh-code-summary'; $label = 'View script' }
                            else { $codeClass = 'ps-code'; $summaryClass = 'ps-code-summary'; $label = 'View script' }
                            $settingVal = "<details class=`"script-collapsible`"><summary class=`"$summaryClass`">$label</summary><pre class=`"$codeClass`">$encCode</pre></details>"
                        } else {
                            $settingVal = ConvertTo-SafeHtmlValue -Value $setting.Value -AllowMultiValue
                        }

                        # Determine if this is a metadata row
                        $metaClass = ''
                        if (Test-MetadataSetting -Name $setting.Name) {
                            $metaClass = ' class="metadata-row"'
                        }

                        if ($indentLevel -gt 0) {
                            $paddingStr = $paddingRem.ToString('0.#', [System.Globalization.CultureInfo]::InvariantCulture)
                            [void]$sb.AppendLine("<tr$metaClass><td style=`"padding-left: $($paddingStr)rem`">$settingNameEsc</td><td>$settingVal</td></tr>")
                        } else {
                            [void]$sb.AppendLine("<tr$metaClass><td>$settingNameEsc</td><td>$settingVal</td></tr>")
                        }
                    }
                    [void]$sb.AppendLine('</table></div>')
                }

                # --- Assignments ---
                $assignmentsCount = if ($policy.Assignments) { @($policy.Assignments).Count } else { 0 }
                [void]$sb.AppendLine('<div class="section-label">Assignments</div>')
                if ($assignmentsCount -gt 0) {
                    [void]$sb.AppendLine('<div class="table-wrap"><table class="t4">')
                    [void]$sb.AppendLine('<tr><th>Target</th><th>Type</th><th>Filter</th><th>Filter Mode</th></tr>')
                    foreach ($assignment in @($policy.Assignments)) {
                        $targetVal     = ConvertTo-SafeHtmlValue -Value $assignment.Target
                        $typeVal       = ConvertTo-SafeHtmlValue -Value $assignment.Type
                        $filterVal     = ConvertTo-SafeHtmlValue -Value $assignment.Filter
                        $filterModeVal = ConvertTo-SafeHtmlValue -Value $assignment.FilterMode
                        [void]$sb.AppendLine("<tr><td>$targetVal</td><td>$typeVal</td><td>$filterVal</td><td>$filterModeVal</td></tr>")
                    }
                    [void]$sb.AppendLine('</table></div>')
                } else {
                    [void]$sb.AppendLine('<p class="muted" style="font-size:var(--text-sm);margin:var(--sp-4) 0">None</p>')
                }

                [void]$sb.AppendLine('</div>')
            }
        }

        [void]$sb.AppendLine('</div>')
        [void]$sb.AppendLine('</div>')
        $isFirstProduct = $false
    }

    # --- Footer ---
    [void]$sb.AppendLine('<footer class="report-footer">')
    [void]$sb.AppendLine("<span>Generated $generatedAt UTC &middot; $tenantNameEsc &middot; $totalPolicies policies across $totalProducts products</span>")
    [void]$sb.AppendLine('<span class="footer-warning">API coverage may be limited for some policy types</span>')
    [void]$sb.AppendLine('<span>Notice a bug? <a href="https://github.com/royklo/InforcerCommunity/issues" target="_blank" rel="noopener">Report it on GitHub</a></span>')
    [void]$sb.AppendLine('</footer>')
    [void]$sb.AppendLine('</div>')

    # --- JavaScript ---
    $jsBlock = @'
<script>
/* Theme toggle — small fixed button, follows system preference if no localStorage */
function toggleTheme(){
    document.documentElement.classList.toggle('dark');
    localStorage.setItem('theme',document.documentElement.classList.contains('dark')?'dark':'light');
}
(function(){
    var s=localStorage.getItem('theme');
    if(s==='dark') document.documentElement.classList.add('dark');
    else if(!s&&window.matchMedia&&window.matchMedia('(prefers-color-scheme: dark)').matches) document.documentElement.classList.add('dark');
})();

/* Scroll to top FAB */
window.addEventListener('scroll',function(){
    var fab=document.getElementById('btn-top');
    if(window.scrollY>200) fab.classList.add('visible');
    else fab.classList.remove('visible');
});

/* Sticky breadcrumb */
(function(){
    var bc=document.getElementById('breadcrumb');
    var bcSection=document.getElementById('bc-section');
    var headers=document.querySelectorAll('.category-heading,.product-header');
    window.addEventListener('scroll',function(){
        if(window.scrollY>200){bc.classList.add('visible')}else{bc.classList.remove('visible');return}
        var current='';
        headers.forEach(function(h){
            var rect=h.getBoundingClientRect();
            if(rect.top<80){current=h.textContent.trim().replace(/^\u25B6\s*/,'').replace(/\d+ policies$/,'').trim()}
        });
        if(current&&bcSection.textContent!==current) bcSection.textContent=current;
    });
})();

/* Toggle helpers */
function toggleEmpty(){document.body.classList.toggle('hide-empty')}
function toggleMeta(){document.body.classList.toggle('show-metadata')}
function toggleExpand(){
    var c=document.getElementById('chk-expand').checked;
    document.querySelectorAll('.product-section').forEach(function(s){
        if(c) s.classList.add('open'); else s.classList.remove('open');
    });
    document.querySelectorAll('.toc-product').forEach(function(t){
        if(c) t.classList.add('open'); else t.classList.remove('open');
    });
}

/* Search with result count */
var _activeTags=[];
function searchPolicies(q){
    var prods=document.querySelectorAll('.product-section');
    q=q.toLowerCase().trim();
    var totalVis=0;
    /* Clear highlights */
    document.querySelectorAll('mark.search-highlight').forEach(function(h){
        var p=h.parentNode;p.replaceChild(document.createTextNode(h.textContent),h);p.normalize();
    });
    prods.forEach(function(pr){
        var vis=0;
        pr.querySelectorAll('.policy-card').forEach(function(p){
            if(p.classList.contains('tag-hidden')){return}
            var txt=p.textContent.toLowerCase();
            if(!q||txt.indexOf(q)>=0){p.classList.remove('search-hidden');vis++}
            else{p.classList.add('search-hidden')}
        });
        totalVis+=vis;
        if(q){
            if(vis>0){pr.classList.add('open');pr.style.display=''}
            else{pr.classList.remove('open');pr.style.display='none'}
        }else{pr.style.display=''}
    });
    /* Hide empty category headings */
    document.querySelectorAll('.category-heading').forEach(function(h){
        if(!q){h.style.display='';return}
        var next=h.nextElementSibling;var hasVis=false;
        while(next&&!next.classList.contains('category-heading')){
            if(next.classList&&next.classList.contains('policy-card')&&!next.classList.contains('search-hidden')&&!next.classList.contains('tag-hidden')){hasVis=true;break}
            next=next.nextElementSibling;
        }
        h.style.display=hasVis?'':'none';
    });
    /* Update search count */
    var sc=document.getElementById('search-count');
    if(q){sc.textContent=totalVis+' polic'+(totalVis===1?'y':'ies')+' match';sc.classList.add('visible')}
    else{sc.classList.remove('visible')}
    /* Highlight matches */
    if(!q)return;
    var re=new RegExp('('+q.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')+')','gi');
    prods.forEach(function(pr){
        pr.querySelectorAll('.policy-card:not(.search-hidden):not(.tag-hidden) td, .policy-card:not(.search-hidden):not(.tag-hidden) .policy-title').forEach(function(el){
            el.childNodes.forEach(function(n){
                if(n.nodeType===3&&re.test(n.textContent)){
                    var s=document.createElement('span');
                    s.innerHTML=n.textContent.replace(re,'<mark class="search-highlight">$1</mark>');
                    n.parentNode.replaceChild(s,n);
                }
            });
        });
    });
}

/* Tag filter */
function toggleTagFilter(el,tag){
    var isActive=!el.classList.contains('active');
    var i=_activeTags.indexOf(tag);
    if(isActive&&i<0)_activeTags.push(tag);
    else if(!isActive&&i>=0)_activeTags.splice(i,1);
    document.querySelectorAll('.tag-pill[data-tag="'+tag+'"]').forEach(function(p){
        if(isActive)p.classList.add('active');else p.classList.remove('active');
    });
    applyTagFilter();
}
function applyTagFilter(){
    document.querySelectorAll('.policy-card').forEach(function(p){
        if(_activeTags.length===0){p.classList.remove('tag-hidden');return}
        var t=p.getAttribute('data-tags')||'';
        var found=_activeTags.some(function(tag){return t.toLowerCase().indexOf(tag.toLowerCase())>=0});
        if(found)p.classList.remove('tag-hidden');else p.classList.add('tag-hidden');
    });
    document.querySelectorAll('.product-section').forEach(function(pr){
        var vis=pr.querySelectorAll('.policy-card:not(.tag-hidden)').length;
        if(_activeTags.length>0&&vis>0) pr.classList.add('open');
    });
    var si=document.getElementById('search-input');
    if(si.value)searchPolicies(si.value);
}

/* Navigation click */
function navClick(e,targetId){
    if(e)e.preventDefault();
    document.getElementById('search-input').value='';searchPolicies('');
    /* Close mobile sidebar */
    document.getElementById('sidebar').classList.remove('mobile-open');
    var el=document.getElementById(targetId);
    if(!el){
        /* Try product-prefixed id */
        el=document.getElementById('product-'+targetId);
    }
    if(el){
        var prod=el.closest('.product-section');
        if(prod) prod.classList.add('open');
        el.scrollIntoView({behavior:'smooth',block:'start'});
    }
}
</script>
'@
    [void]$sb.AppendLine($jsBlock)

    # --- Syntax highlighting for collapsible code blocks ---
    [void]$sb.AppendLine('<script>')
    [void]$sb.AppendLine('function escHtml(s){return s.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;")}')
    [void]$sb.AppendLine('function highlightPS(el){var t=el.textContent,tokens=[],re=/(#[^\n]*|<#[\s\S]*?#>|"[^"]*"|''[^'']*''|\$[\w:]+|\[[\w.]+\]|\b(?:if|else|elseif|foreach|for|while|do|switch|try|catch|finally|throw|return|function|param|begin|process|end|filter|class|enum|using|trap|break|continue|exit)\b|\b[A-Z][a-z]+(?:-[A-Z][a-zA-Z]+)+\b)/gi,last=0,m;while((m=re.exec(t))!==null){if(m.index>last)tokens.push(escHtml(t.substring(last,m.index)));var s=m[0],c="";if(s[0]==="#"||s.startsWith("<#"))c="ps-comment";else if(s[0]==="\""||s[0]==="''")c="ps-string";else if(s[0]==="$")c="ps-variable";else if(s[0]==="[")c="ps-type";else if(s.indexOf("-")>0&&s[0]===s[0].toUpperCase())c="ps-cmdlet";else c="ps-keyword";tokens.push(''<span class="''+c+''">''+escHtml(s)+''</span>'');last=m.index+s.length}if(last<t.length)tokens.push(escHtml(t.substring(last)));el.innerHTML=tokens.join("")}')
    [void]$sb.AppendLine('function highlightBash(el){var t=el.textContent,tokens=[],re=/(#[^\n]*|"(?:[^"\\]|\\.)*"|''[^'']*''|\$\{[\w]+\}|\$[\w]+|\b(?:if|then|else|elif|fi|for|do|done|while|until|case|esac|function|return|local|export|set|trap|in)\b|\b(?:echo|curl|rm|mkdir|cp|mv|chmod|chown|grep|sed|awk|cat|ls|cd|pwd|source|eval|exec|exit)\b)/g,last=0,m;while((m=re.exec(t))!==null){if(m.index>last)tokens.push(escHtml(t.substring(last,m.index)));var s=m[0],c="";if(s[0]==="#")c="sh-comment";else if(s[0]==="\""||s[0]==="''")c="sh-string";else if(s[0]==="$")c="sh-variable";else if(/^(if|then|else|elif|fi|for|do|done|while|until|case|esac|function|return|local|export|set|trap|in)$/.test(s))c="sh-keyword";else c="sh-command";tokens.push(''<span class="''+c+''">''+escHtml(s)+''</span>'');last=m.index+s.length}if(last<t.length)tokens.push(escHtml(t.substring(last)));el.innerHTML=tokens.join("")}')
    [void]$sb.AppendLine('function highlightJSON(el){var t=el.textContent,tokens=[],re=/("(?:[^"\\]|\\.)*")\s*(:)|("(?:[^"\\]|\\.)*")|\b(true|false|null)\b|(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)/g,last=0,m;while((m=re.exec(t))!==null){if(m.index>last)tokens.push(escHtml(t.substring(last,m.index)));if(m[1])tokens.push(''<span class="json-key">''+escHtml(m[1])+''</span>''+escHtml(m[2]));else if(m[3])tokens.push(''<span class="json-string">''+escHtml(m[3])+''</span>'');else if(m[4])tokens.push(''<span class="json-bool">''+escHtml(m[4])+''</span>'');else if(m[5])tokens.push(''<span class="json-number">''+escHtml(m[5])+''</span>'');last=m.index+m[0].length}if(last<t.length)tokens.push(escHtml(t.substring(last)));el.innerHTML=tokens.join("")}')
    [void]$sb.AppendLine('document.querySelectorAll("pre.ps-code").forEach(highlightPS);')
    [void]$sb.AppendLine('document.querySelectorAll("pre.sh-code").forEach(highlightBash);')
    [void]$sb.AppendLine('document.querySelectorAll("pre.json-code").forEach(highlightJSON);')
    # Hide Expand buttons when content doesn't actually overflow
    [void]$sb.AppendLine('document.querySelectorAll(".long-val").forEach(function(el){')
    [void]$sb.AppendLine('    if(el.scrollHeight<=el.clientHeight){')
    [void]$sb.AppendLine('        var btn=el.nextElementSibling;')
    [void]$sb.AppendLine('        if(btn&&btn.classList.contains("long-val-btn"))btn.style.display="none";')
    [void]$sb.AppendLine('    }')
    [void]$sb.AppendLine('});')
    [void]$sb.AppendLine('</script>')

    [void]$sb.AppendLine('</body>')
    [void]$sb.Append('</html>')

    $sb.ToString()
}
