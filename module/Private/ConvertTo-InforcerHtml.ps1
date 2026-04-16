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
    margin-left: 340px;
    line-height: 1.65;
    font-size: 0.9375rem;
    -webkit-font-smoothing: antialiased;
}
/* (toolbar removed -- controls are now in the sidebar panel) */
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
.tag-badge { background: #dbeafe !important; color: #1e40af !important; border: 1px solid #93c5fd; }
:root.dark .tag-badge { background: rgba(59,130,246,0.2) !important; color: #93c5fd !important; border-color: rgba(59,130,246,0.4); }
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
    padding: 0.25rem 1.25rem 1rem;
    box-shadow: var(--shadow-sm);
    margin-bottom: 0.5rem;
}
.product-content > h3:first-child { margin-top: 0.375rem; }
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
.table-wrap { overflow-x: auto; margin-bottom: 0.75rem; border-radius: var(--radius-xs); }
table {
    width: 100%;
    border-collapse: collapse;
    font-size: 0.8125rem;
    min-width: 400px;
}
/* 2-column tables (Basics, Settings): fixed layout with 40/60 split */
table.t2 { table-layout: fixed; }
table.t2 th:first-child, table.t2 td:first-child { width: 40%; }
table.t2 th:last-child, table.t2 td:last-child { width: 60%; }
/* 4-column tables (Assignments): auto layout, even columns */
table.t4 { table-layout: auto; }
table.t4 th, table.t4 td { white-space: nowrap; }
table.t4 th:first-child, table.t4 td:first-child { white-space: normal; width: 35%; }
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
    word-break: break-word;
    max-width: 500px;
}
.long-val { display: block; max-height: 12em; overflow: hidden; position: relative; word-break: break-all; }
.long-val.expanded { max-height: none; }
.long-val-btn {
    display: inline-block; margin-top: 0.25rem; padding: 0.125rem 0.5rem;
    background: var(--accent-soft); color: var(--accent); border: 1px solid var(--accent);
    border-radius: var(--radius-xs); font-size: 0.6875rem; font-weight: 600;
    cursor: pointer; transition: all var(--transition);
}
.long-val-btn:hover { background: var(--accent); color: #fff; }
.script-collapsible { margin: 0.25rem 0; }
.script-collapsible summary { cursor: pointer; font-size: 0.75rem; font-weight: 600; user-select: none; list-style: none; display: inline-flex; align-items: center; gap: 0.25rem; padding: 0.2rem 0.6rem; border-radius: var(--radius-xs); transition: all var(--transition); }
.script-collapsible summary::after { content: '\25B6'; font-size: 0.55rem; transition: transform 0.2s; }
.script-collapsible[open] summary::after { transform: rotate(90deg); }
.script-collapsible summary::-webkit-details-marker { display: none; }
.script-collapsible pre { margin: 0.5rem 0 0; padding: 1rem; border-radius: var(--radius-xs); font-size: 0.75rem; line-height: 1.5; overflow-x: auto; white-space: pre-wrap; word-break: break-all; max-height: 30em; }
.ps-code { background: #1e1e1e !important; color: #d4d4d4; }
.ps-code-summary { color: #569cd6; border: 1px solid #569cd6; background: rgba(86,156,214,0.1); }
.ps-code-summary:hover { background: #569cd6; color: #1e1e1e; }
.sh-code { background: #0d1117 !important; color: #c9d1d9; }
.sh-code-summary { color: #ff7b72; border: 1px solid #ff7b72; background: rgba(255,123,114,0.1); }
.sh-code-summary:hover { background: #ff7b72; color: #0d1117; }
.json-code { background: #1a1b26 !important; color: #a9b1d6; }
.json-code-summary { color: #7aa2f7; border: 1px solid #7aa2f7; background: rgba(122,162,247,0.1); }
.json-code-summary:hover { background: #7aa2f7; color: #1a1b26; }
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
.json-key { color: #7aa2f7; }
.json-string { color: #9ece6a; }
.json-bool { color: #ff9e64; font-weight: 600; }
.json-number { color: #e0af68; }
tr:last-child td { border-bottom: none; }
tr:nth-child(even) td { background: var(--row-alt); }
tr:hover td { background: var(--accent-soft); }
/* --- Metadata rows (hidden by default, shown via toggle) --- */
.metadata-row { display: none; }
.show-metadata .metadata-row { display: table-row; }
/* --- Multi-value list display --- */
.mv-list { list-style: none; margin: 0; padding: 0; }
.mv-list li { padding: 0.125rem 0; }
.mv-list li + li { border-top: 1px solid var(--border-subtle); }
.mv-hidden { display: none; }
.mv-btn {
    display: inline-block; font-size: 0.6875rem; font-weight: 600;
    padding: 0.125rem 0.5rem; border-radius: var(--radius-xs);
    background: var(--badge-bg); color: var(--badge-text);
    cursor: pointer; margin-top: 0.25rem; user-select: none;
    border: none; transition: background var(--transition);
}
.mv-btn:hover { background: var(--accent); color: #fff; }
/* --- Tooltip icon --- */
.tooltip-icon {
    display: inline-flex; align-items: center; justify-content: center;
    width: 16px; height: 16px; border-radius: 50%;
    background: var(--border); color: var(--text-secondary);
    font-size: 0.625rem; font-weight: 700; cursor: help;
    position: relative; margin-left: 0.375rem; flex-shrink: 0;
}
.tooltip-icon::after {
    content: attr(data-tip);
    position: absolute; left: 50%; bottom: 130%; transform: translateX(-50%);
    background: var(--bg-card); color: var(--text); border: 1px solid var(--border);
    border-radius: var(--radius-xs); padding: 0.375rem 0.625rem;
    font-size: 0.6875rem; font-weight: 400; white-space: nowrap;
    box-shadow: var(--shadow-md); pointer-events: none;
    opacity: 0; transition: opacity var(--transition);
    z-index: 10;
}
.tooltip-icon:hover::after { opacity: 1; }
/* --- Footer --- */
.footer {
    margin-top: 2rem;
    padding: 1rem 0;
    text-align: center;
    color: var(--muted);
    font-size: 0.75rem;
}
/* --- Filter toggle (only hide rows where the VALUE column is empty, not any column) --- */
/* Only hide empty rows in 2-column tables (Basics/Settings), never in assignments (t4) */
.hide-empty table.t2 tr:has(td:last-child > .empty-val:only-child):not(:has(td:first-child > .empty-val)) { display: none; }
/* --- Search --- */
.search-hidden { display: none !important; }
.tag-hidden { display: none !important; }
.search-highlight { background: rgba(250,204,21,0.3); border-radius: 2px; }
/* --- Notch warning bar --- */
.notch-bar {
    position: fixed; top: 0; left: 50%; transform: translateX(-50%); z-index: 1000;
    background: var(--accent); color: #fff; font-size: 0.75rem; font-weight: 600;
    padding: 0.25rem 1.5rem 0.3rem;
    border-radius: 0 0 var(--radius) var(--radius);
    box-shadow: var(--shadow-md);
    white-space: nowrap; letter-spacing: 0.02em;
    pointer-events: none;
}
.notch-bar .notch-warn { font-weight: 400; opacity: 0.85; margin-left: 0.75rem; font-size: 0.6875rem; }
/* --- Tag filter pills in sidebar --- */
.tag-filter { padding: 0 1.25rem 0.75rem; border-bottom: 1px solid var(--border); flex-shrink: 0; }
.tag-filter-title { font-size: 0.6875rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.08em; color: var(--muted); margin-bottom: 0.375rem; }
.tag-pills { display: flex; flex-wrap: wrap; gap: 0.25rem; }
.tag-pill {
    background: var(--bg); border: 1px solid var(--border); color: var(--text-secondary);
    padding: 0.2rem 0.5rem; border-radius: 999px; font-size: 0.6875rem; cursor: pointer;
    transition: all var(--transition); user-select: none; font-weight: 500;
}
.tag-pill:hover { border-color: var(--accent); color: var(--accent); }
.tag-pill.active { background: var(--accent); color: #fff; border-color: var(--accent); }
/* --- Sidebar panel (always visible on desktop, slide-out on mobile) --- */
.sidebar-backdrop {
    position: fixed; inset: 0; background: rgba(0,0,0,0.3); z-index: 998;
    opacity: 0; pointer-events: none; transition: opacity var(--transition);
    display: none;
}
.sidebar-backdrop.open { opacity: 1; pointer-events: auto; }
.sidebar {
    position: fixed; top: 0; left: 0; width: 320px; height: 100vh;
    background: var(--bg-card); border-right: 1px solid var(--border);
    z-index: 999;
    display: flex; flex-direction: column;
    overflow: hidden;
}
.sidebar-header {
    display: flex; align-items: center; justify-content: space-between;
    padding: 1rem 1.25rem; border-bottom: 1px solid var(--border);
    flex-shrink: 0;
}
.sidebar-header h2 { font-size: 0.875rem; font-weight: 700; }
.sidebar-close {
    background: none; border: none; cursor: pointer; color: var(--muted);
    font-size: 1.25rem; line-height: 1; padding: 0.25rem;
    transition: color var(--transition);
}
.sidebar-close:hover { color: var(--text); }
/* --- Sidebar controls --- */
.sidebar-controls {
    padding: 0.75rem 1.25rem; border-bottom: 1px solid var(--border);
    display: flex; flex-direction: column; gap: 0.5rem; flex-shrink: 0;
}
.toggle-row {
    display: flex; align-items: center; justify-content: space-between;
    padding: 0.5rem 0; font-size: 0.8125rem; color: var(--text-secondary);
    cursor: pointer; user-select: none;
}
.toggle-row:hover { color: var(--text); }
.toggle-row > span:first-child { font-weight: 500; }
.toggle-switch {
    position: relative; width: 40px; height: 22px; flex-shrink: 0;
}
.toggle-switch input { opacity: 0; width: 0; height: 0; }
.toggle-slider {
    position: absolute; inset: 0; background: var(--border);
    border-radius: 11px; cursor: pointer; transition: background var(--transition);
}
.toggle-slider::before {
    content: ''; position: absolute; left: 3px; top: 3px;
    width: 16px; height: 16px; background: #fff;
    border-radius: 50%; transition: transform var(--transition);
    box-shadow: 0 1px 3px rgba(0,0,0,0.2);
}
.toggle-switch input:checked + .toggle-slider { background: var(--accent); }
.toggle-switch input:checked + .toggle-slider::before { transform: translateX(18px); }
.toggle-switch input:focus-visible + .toggle-slider { outline: 2px solid var(--accent); outline-offset: 2px; }
/* --- Sidebar TOC --- */
.sidebar-toc {
    flex: 1; overflow-y: auto; padding: 0.75rem 1rem;
    scrollbar-width: thin; scrollbar-color: var(--border) transparent;
}
.sidebar-toc::-webkit-scrollbar { width: 4px; }
.sidebar-toc::-webkit-scrollbar-thumb { background: var(--border); border-radius: 2px; }
/* --- Floating buttons --- */
.fab-group {
    position: fixed; bottom: 1.5rem; right: 1.5rem;
    display: flex; flex-direction: column; gap: 0.5rem; z-index: 200;
}
.fab {
    width: 44px; height: 44px; border-radius: 50%;
    background: var(--accent); color: #fff; border: none;
    cursor: pointer; display: flex; align-items: center; justify-content: center;
    box-shadow: var(--shadow-md);
    transition: all var(--transition);
    font-size: 1.125rem;
}
.fab:hover { background: var(--accent-hover); box-shadow: var(--shadow-lg); transform: scale(1.05); }
.fab:focus-visible { outline: 2px solid var(--accent); outline-offset: 3px; }
.fab-top { opacity: 0; pointer-events: none; transform: translateY(8px); }
.fab-top.visible { opacity: 1; pointer-events: auto; transform: translateY(0); }
/* --- Responsive --- */
@media (max-width: 1024px) {
    body { margin-left: 0; }
    .sidebar {
        left: -320px; width: 300px; max-width: 85vw;
        box-shadow: var(--shadow-lg);
        transition: left 300ms cubic-bezier(0.4, 0, 0.2, 1);
    }
    .sidebar.open { left: 0; }
    .sidebar-backdrop { display: block; }
    .fab-sidebar { display: flex; }
}
@media (min-width: 1025px) {
    .fab-sidebar { display: none; }
    .sidebar-close { display: none; }
}
@media (max-width: 768px) {
    body { padding: 0 1rem 2rem; font-size: 0.875rem; }
    .header h1 { font-size: 1.375rem; }
    .product-section > summary { padding: 0.75rem; font-size: 0.9375rem; }
    .policy-section { padding: 0.75rem; }
    td, th { padding: 0.375rem 0.5rem; }
    .fab-group { bottom: 1rem; right: 1rem; }
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
        $str = $Value.ToString()
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

    # --- Header ---
    [void]$sb.AppendLine('<div id="top"></div>')
    [void]$sb.AppendLine('<div class="header">')
    [void]$sb.AppendLine("<h1>$tenantNameEsc</h1>")
    [void]$sb.AppendLine('<div class="header-meta">')
    [void]$sb.AppendLine("<span>$generatedAt UTC</span>")
    [void]$sb.AppendLine("<span>$totalProducts products</span>")
    [void]$sb.AppendLine("<span>$totalPolicies policies</span>")
    if ($baselineNames.Count -gt 0) {
        [void]$sb.AppendLine("<span>$($baselineNames.Count) baselines</span>")
    }
    # Show active filters
    if ($DocModel.FilterBaseline) {
        $filterBaselineEsc = [System.Net.WebUtility]::HtmlEncode($DocModel.FilterBaseline)
        [void]$sb.AppendLine("<span style=`"color:var(--accent);font-weight:600`">Baseline: $filterBaselineEsc</span>")
    }
    if ($DocModel.FilterTag) {
        $filterTagEsc = [System.Net.WebUtility]::HtmlEncode($DocModel.FilterTag)
        [void]$sb.AppendLine("<span style=`"color:var(--accent);font-weight:600`">Tag: $filterTagEsc</span>")
    }
    [void]$sb.AppendLine('</div>')

    # --- Search bar ---
    [void]$sb.AppendLine('<div style="margin-top:0.75rem"><input type="text" id="search-input" placeholder="Search policies, settings, values..." style="width:100%;padding:0.5rem 0.75rem;border:1px solid var(--border);border-radius:var(--radius-xs);background:var(--bg-card);color:var(--text);font-size:0.875rem;font-family:inherit;outline:none" oninput="searchPolicies(this.value)"></div>')
    [void]$sb.AppendLine('</div>')

    # --- Notch warning bar ---
    $notchLabel = if ($DocModel.FilterBaseline) {
        [System.Net.WebUtility]::HtmlEncode($DocModel.FilterBaseline)
    } else {
        $tenantNameEsc
    }
    [void]$sb.AppendLine("<div class=`"notch-bar`">$notchLabel &middot; $totalPolicies policies<span class=`"notch-warn`">API coverage may be limited for some policy types</span></div>")

    # --- Sidebar backdrop + panel ---
    [void]$sb.AppendLine('<div class="sidebar-backdrop" id="sidebar-backdrop" onclick="closeSidebar()"></div>')
    [void]$sb.AppendLine('<aside class="sidebar" id="sidebar">')

    # Sidebar header
    [void]$sb.AppendLine('<div class="sidebar-header">')
    [void]$sb.AppendLine('<h2>Navigation</h2>')
    [void]$sb.AppendLine('<button class="sidebar-close" onclick="closeSidebar()" aria-label="Close">&times;</button>')
    [void]$sb.AppendLine('</div>')

    # Sidebar controls
    [void]$sb.AppendLine('<div class="sidebar-controls">')
    [void]$sb.AppendLine('<label class="toggle-row"><span>Hide empty fields</span><span class="toggle-switch"><input type="checkbox" id="chk-empty" checked onchange="toggleEmpty()"><span class="toggle-slider"></span></span></label>')
    [void]$sb.AppendLine('<label class="toggle-row"><span>Expand all sections</span><span class="toggle-switch"><input type="checkbox" id="chk-expand" onchange="toggleExpand()"><span class="toggle-slider"></span></span></label>')
    [void]$sb.AppendLine('<label class="toggle-row"><span>Dark mode</span><span class="toggle-switch"><input type="checkbox" id="chk-theme" onchange="toggleTheme()"><span class="toggle-slider"></span></span></label>')
    [void]$sb.AppendLine('<label class="toggle-row"><span>Show metadata<span class="tooltip-icon" data-tip="Show @odata.type and other metadata properties in settings tables">i</span></span><span class="toggle-switch"><input type="checkbox" id="chk-meta" onchange="toggleMeta()"><span class="toggle-slider"></span></span></label>')
    [void]$sb.AppendLine('</div>')

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
        [void]$sb.AppendLine('<div class="tag-filter-title">Filter by Tag</div>')
        [void]$sb.AppendLine('<div class="tag-pills">')
        foreach ($tagName in $allTags) {
            $tagEsc = [System.Net.WebUtility]::HtmlEncode($tagName)
            $tagSafe = $tagName -replace '[^a-zA-Z0-9 \-]', ''
            [void]$sb.AppendLine("<span class=`"tag-pill`" data-tag=`"$tagSafe`" onclick=`"toggleTagFilter(this,this.getAttribute('data-tag'))`">$tagEsc</span>")
        }
        [void]$sb.AppendLine('</div>')
        [void]$sb.AppendLine('</div>')
    }

    # Sidebar TOC
    [void]$sb.AppendLine('<div class="sidebar-toc toc-section">')
    [void]$sb.AppendLine('<ul class="toc-l1">')

    foreach ($prodName in $DocModel.Products.Keys) {
        $prodEsc    = [System.Net.WebUtility]::HtmlEncode($prodName)
        $prodAnchor = ConvertTo-HtmlAnchorId -Text $prodName

        $prodPolicies = 0
        foreach ($cp in $DocModel.Products[$prodName].Categories.Values) { $prodPolicies += @($cp).Count }

        [void]$sb.AppendLine('<li>')
        [void]$sb.AppendLine('<details>')
        [void]$sb.AppendLine("<summary><a href=`"#$prodAnchor`" onclick=`"navClick(event,'$prodAnchor')`">$prodEsc</a> <span class=`"badge`">$prodPolicies</span></summary>")
        [void]$sb.AppendLine('<ul class="toc-l2">')

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
                # Single category with no subcategory — show directly with policies
                $catName = $groupEntries[0].CatName
                $catAnchor = ConvertTo-HtmlAnchorId -Text "$prodName-$catName"
                $catPolicies = @($DocModel.Products[$prodName].Categories[$catName])

                [void]$sb.AppendLine('<li>')
                [void]$sb.AppendLine('<details>')
                [void]$sb.AppendLine("<summary><a href=`"#$catAnchor`" onclick=`"navClick(event,'$catAnchor')`" style=`"font-size:0.8rem;color:var(--muted)`">$groupEsc</a></summary>")
                [void]$sb.AppendLine('<ul class="toc-l3">')
                foreach ($pol in $catPolicies) {
                    $polNameEsc = [System.Net.WebUtility]::HtmlEncode($pol.Basics.Name)
                    $polAnchor  = ConvertTo-HtmlAnchorId -Text "$prodName-$catName-$($pol.Basics.Name)"
                    [void]$sb.AppendLine("<li><a href=`"#$polAnchor`" onclick=`"navClick(event,'$polAnchor')`">$polNameEsc</a></li>")
                }
                [void]$sb.AppendLine('</ul>')
                [void]$sb.AppendLine('</details>')
                [void]$sb.AppendLine('</li>')
            } else {
                # Group with subcategories — nest them
                [void]$sb.AppendLine('<li>')
                [void]$sb.AppendLine('<details>')
                $firstCatAnchor = ConvertTo-HtmlAnchorId -Text "$prodName-$($groupEntries[0].CatName)"
                [void]$sb.AppendLine("<summary><a href=`"#$firstCatAnchor`" onclick=`"navClick(event,'$firstCatAnchor')`" style=`"font-size:0.8rem;color:var(--muted)`">$groupEsc</a></summary>")
                [void]$sb.AppendLine('<ul class="toc-l3">')

                foreach ($entry in $groupEntries) {
                    $catName = $entry.CatName
                    $subDisplay = if ($entry.SubName) { $entry.SubName } else { $groupName }
                    $subEsc = [System.Net.WebUtility]::HtmlEncode($subDisplay)
                    $catAnchor = ConvertTo-HtmlAnchorId -Text "$prodName-$catName"
                    [void]$sb.AppendLine("<li><a href=`"#$catAnchor`" onclick=`"navClick(event,'$catAnchor')`"><strong>$subEsc</strong></a></li>")

                    # Show policies under each subcategory
                    foreach ($pol in @($DocModel.Products[$prodName].Categories[$catName])) {
                        $polNameEsc = [System.Net.WebUtility]::HtmlEncode($pol.Basics.Name)
                        $polAnchor  = ConvertTo-HtmlAnchorId -Text "$prodName-$catName-$($pol.Basics.Name)"
                        [void]$sb.AppendLine("<li style=`"padding-left:0.75rem`"><a href=`"#$polAnchor`" onclick=`"navClick(event,'$polAnchor')`">$polNameEsc</a></li>")
                    }
                }

                [void]$sb.AppendLine('</ul>')
                [void]$sb.AppendLine('</details>')
                [void]$sb.AppendLine('</li>')
            }
        }

        [void]$sb.AppendLine('</ul>')
        [void]$sb.AppendLine('</details>')
        [void]$sb.AppendLine('</li>')
    }

    [void]$sb.AppendLine('</ul>')
    [void]$sb.AppendLine('</div>')
    [void]$sb.AppendLine('</aside>')

    # --- Floating action buttons ---
    [void]$sb.AppendLine('<div class="fab-group">')
    [void]$sb.AppendLine('<button class="fab fab-top" id="btn-top" onclick="scrollToTop()" aria-label="Back to top">')
    # SVG arrow up (inline, no CDN)
    [void]$sb.AppendLine('<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M18 15l-6-6-6 6"/></svg>')
    [void]$sb.AppendLine('</button>')
    [void]$sb.AppendLine('<button class="fab fab-sidebar" id="btn-sidebar" onclick="openSidebar()" aria-label="Open navigation">')
    # SVG menu/list icon
    [void]$sb.AppendLine('<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M3 12h18M3 6h18M3 18h18"/></svg>')
    [void]$sb.AppendLine('</button>')
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

        foreach ($catName in ($DocModel.Products[$prodName].Categories.Keys | Sort-Object)) {
            $catDisplayName = $catName -replace '^All / ', ''
            $catEsc    = [System.Net.WebUtility]::HtmlEncode($catDisplayName)
            $catAnchor = ConvertTo-HtmlAnchorId -Text "$prodName-$catName"
            $policies  = $DocModel.Products[$prodName].Categories[$catName]

            [void]$sb.AppendLine("<h3 id=`"$catAnchor`">$catEsc</h3>")

            foreach ($policy in @($policies)) {
                $policyNameEsc   = [System.Net.WebUtility]::HtmlEncode($policy.Basics.Name)
                $settingsCount   = if ($policy.Settings) { @($policy.Settings).Count } else { 0 }
                $policyAnchor    = ConvertTo-HtmlAnchorId -Text "$prodName-$catName-$($policy.Basics.Name)"

                $tagsAttr = ''
                $tagsVal = $policy.Basics['Tags']
                if (-not [string]::IsNullOrWhiteSpace($tagsVal)) {
                    $tagsAttr = " data-tags=`"$([System.Net.WebUtility]::HtmlEncode($tagsVal))`""
                }
                [void]$sb.AppendLine("<div class=`"policy-section`"$tagsAttr>")

                # Build tag badges HTML inline with the policy title
                $tagBadgesHtml = ''
                if (-not [string]::IsNullOrWhiteSpace($tagsVal)) {
                    foreach ($tagName in ($tagsVal -split ',\s*')) {
                        $tagEsc = [System.Net.WebUtility]::HtmlEncode($tagName.Trim())
                        $tagBadgesHtml += " <span class=`"badge tag-badge`">$tagEsc</span>"
                    }
                }
                [void]$sb.AppendLine("<h4 id=`"$policyAnchor`">$policyNameEsc <span class=`"badge`">$settingsCount settings</span>$tagBadgesHtml</h4>")

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
                    [void]$sb.AppendLine('<p class="muted" style="font-size:0.8125rem;margin:0.25rem 0">None</p>')
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
    [void]$sb.AppendLine('<p>Notice a bug or missing information? <a href="https://github.com/royklo/InforcerCommunity/issues" target="_blank" rel="noopener" style="color:var(--accent)">Report it on GitHub</a></p>')
    [void]$sb.AppendLine('</div>')

    # --- JavaScript ---
    $jsBlock = @'
<script>
function openSidebar(){document.getElementById('sidebar').classList.add('open');document.getElementById('sidebar-backdrop').classList.add('open')}
function closeSidebar(){document.getElementById('sidebar').classList.remove('open');document.getElementById('sidebar-backdrop').classList.remove('open')}
function scrollToTop(){window.scrollTo({top:0,behavior:'smooth'})}
function toggleMeta(){document.body.classList.toggle('show-metadata')}
var _activeTags=[];
function searchPolicies(q){var prods=document.querySelectorAll('.product-section');q=q.toLowerCase().trim();prods.forEach(function(pr){pr.querySelectorAll('mark.search-highlight').forEach(function(h){var p=h.parentNode;p.replaceChild(document.createTextNode(h.textContent),h);p.normalize()});var vis=0;pr.querySelectorAll('.policy-section').forEach(function(p){if(p.classList.contains('tag-hidden')){return}var txt=p.textContent.toLowerCase();if(!q||txt.indexOf(q)>=0){p.classList.remove('search-hidden');vis++}else{p.classList.add('search-hidden')}});if(q){if(vis>0){pr.open=true;pr.style.display=''}else{pr.open=false;pr.style.display='none'}}else{pr.style.display='';pr.open=false}});document.querySelectorAll('h3').forEach(function(h){if(!q){h.style.display='';return}var next=h.nextElementSibling;var hasVis=false;while(next&&next.tagName!=='H3'){if(next.classList&&next.classList.contains('policy-section')&&!next.classList.contains('search-hidden')&&!next.classList.contains('tag-hidden')){hasVis=true;break}next=next.nextElementSibling}h.style.display=hasVis?'':'none'});prods.forEach(function(pr){if(!q){pr.style.display='';return}var anyH3=false;pr.querySelectorAll('h3').forEach(function(h){if(h.style.display!=='none')anyH3=true});if(!anyH3){var anyPol=pr.querySelectorAll('.policy-section:not(.search-hidden):not(.tag-hidden)').length>0;if(!anyPol){pr.style.display='none';pr.open=false}}});if(!q)return;var re=new RegExp('('+q.replace(/[.*+?^${}()|[\]\\]/g,'\\$&')+')','gi');prods.forEach(function(pr){pr.querySelectorAll('.policy-section:not(.search-hidden):not(.tag-hidden) td, .policy-section:not(.search-hidden):not(.tag-hidden) h4').forEach(function(el){el.childNodes.forEach(function(n){if(n.nodeType===3&&re.test(n.textContent)){var s=document.createElement('span');s.innerHTML=n.textContent.replace(re,'<mark class="search-highlight">$1</mark>');n.parentNode.replaceChild(s,n)}})})})}
function toggleTagFilter(el,tag){var isActive=!el.classList.contains('active');var i=_activeTags.indexOf(tag);if(isActive&&i<0)_activeTags.push(tag);else if(!isActive&&i>=0)_activeTags.splice(i,1);document.querySelectorAll('.tag-pill[data-tag="'+tag+'"]').forEach(function(p){if(isActive)p.classList.add('active');else p.classList.remove('active')});applyTagFilter()}
function applyTagFilter(){document.querySelectorAll('.policy-section').forEach(function(p){if(_activeTags.length===0){p.classList.remove('tag-hidden');return}var t=p.getAttribute('data-tags')||'';var found=_activeTags.some(function(tag){return t.toLowerCase().indexOf(tag.toLowerCase())>=0});if(found)p.classList.remove('tag-hidden');else p.classList.add('tag-hidden')});document.querySelectorAll('.product-section').forEach(function(pr){var vis=pr.querySelectorAll('.policy-section:not(.tag-hidden)').length;if(_activeTags.length>0&&vis>0)pr.open=true});var si=document.getElementById('search-input');if(si.value)searchPolicies(si.value)}
function navClick(e,targetId){if(e)e.preventDefault();document.getElementById('search-input').value='';searchPolicies('');closeSidebar();var el=document.getElementById(targetId);if(el){var prod=el.closest('details.product-section');if(prod)prod.open=true;el.scrollIntoView({behavior:'smooth',block:'start'})}}
function toggleEmpty(){document.body.classList.toggle('hide-empty')}
function toggleExpand(){var c=document.getElementById('chk-expand').checked;document.querySelectorAll('details.product-section').forEach(function(d){d.open=c});document.querySelectorAll('.sidebar-toc details').forEach(function(d){d.open=c})}
function toggleTheme(){var r=document.documentElement,c=document.getElementById('chk-theme');if(c.checked){r.classList.remove('light');r.classList.add('dark');localStorage.setItem('theme','dark')}else{r.classList.remove('dark');r.classList.add('light');localStorage.setItem('theme','light')}}
(function(){var s=localStorage.getItem('theme'),ct=document.getElementById('chk-theme');if(s==='dark'){document.documentElement.classList.add('dark');ct.checked=true}else if(s==='light'){document.documentElement.classList.add('light')}else if(window.matchMedia&&window.matchMedia('(prefers-color-scheme: dark)').matches){ct.checked=true;document.documentElement.classList.add('dark')}
window.addEventListener('scroll',function(){var b=document.getElementById('btn-top');if(window.scrollY>400){b.classList.add('visible')}else{b.classList.remove('visible')}})})();
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
    [void]$sb.AppendLine('</script>')

    [void]$sb.AppendLine('</body>')
    [void]$sb.Append('</html>')

    $sb.ToString()
}
