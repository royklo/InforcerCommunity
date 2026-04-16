function ConvertTo-InforcerComparisonHtml {
    <#
    .SYNOPSIS
        Renders a ComparisonModel as a self-contained HTML document.
    .DESCRIPTION
        Stage 3 of the Compare-InforcerEnvironments pipeline. Receives the structured
        ComparisonModel hashtable from Compare-InforcerDocModels and produces
        a complete, self-contained HTML string with embedded CSS and JavaScript.

        Features:
        - Modern admin dashboard styling matching Export-InforcerTenantDocumentation
        - Dark/light theme toggle with localStorage persistence
        - Animated alignment score card with counter tiles
        - Collapsible product sections with status badges
        - Settings Catalog rows (6-column layout)
        - Search filter, scroll-to-top, responsive layout
        - No external dependencies (CSS/JS fully embedded)
    .PARAMETER ComparisonModel
        Hashtable from ConvertTo-InforcerComparisonModel containing: SourceName,
        DestinationName, GeneratedAt, AlignmentScore,
        TotalItems, Counters, Products, IncludingAssignments.
    .OUTPUTS
        System.String -- complete HTML document as a single string.
    .EXAMPLE
        $html = ConvertTo-InforcerComparisonHtml -ComparisonModel $model
        Set-Content -Path '.\comparison.html' -Value $html -Encoding UTF8
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ComparisonModel
    )

    # ── CSS block (single-quoted here-string, no variable expansion) ───────
    $cssBlock = @'
:root {
    --bg: #f1f5f9;
    --bg-card: #f8fafc;
    --bg-glass: rgba(248,250,252,0.9);
    --text: #0f172a;
    --text-secondary: #334155;
    --border: #cbd5e1;
    --border-subtle: #e2e8f0;
    --row-alt: rgba(241,245,249,0.6);
    --header-bg: rgba(226,232,240,0.8);
    --muted: #64748b;
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
    --warning: #d97706;
    --warning-bg: #fef3c7;
    --danger: #dc2626;
    --danger-bg: #fee2e2;
    --info: #2563eb;
    --info-bg: #dbeafe;
    --manual: #7c3aed;
    --manual-bg: #ede9fe;
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
        --warning: #fbbf24;
        --warning-bg: rgba(251,191,36,0.1);
        --danger: #f87171;
        --danger-bg: rgba(248,113,113,0.1);
        --info: #60a5fa;
        --info-bg: rgba(96,165,250,0.1);
        --manual: #a78bfa;
        --manual-bg: rgba(167,139,250,0.1);
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
    --warning: #fbbf24;
    --warning-bg: rgba(251,191,36,0.1);
    --danger: #f87171;
    --danger-bg: rgba(248,113,113,0.1);
    --info: #60a5fa;
    --info-bg: rgba(96,165,250,0.1);
    --manual: #a78bfa;
    --manual-bg: rgba(167,139,250,0.1);
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
    --warning: #d97706;
    --warning-bg: #fef3c7;
    --danger: #dc2626;
    --danger-bg: #fee2e2;
    --info: #2563eb;
    --info-bg: #dbeafe;
    --manual: #7c3aed;
    --manual-bg: #ede9fe;
}
@media (prefers-reduced-motion: reduce) {
    * { transition-duration: 0ms !important; animation-duration: 0ms !important; }
}
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
body {
    font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
    background: var(--bg);
    color: var(--text);
    max-width: 1800px;
    margin: 0 auto;
    padding: 0 20px 3rem;
    line-height: 1.5;
    font-size: 12px;
    -webkit-font-smoothing: antialiased;
}
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
.header {
    padding: 2.5rem 0 1.5rem;
    text-align: center;
}
.header h1 { font-size: 1.75rem; font-weight: 700; letter-spacing: -0.025em; margin-bottom: 0.75rem; }
.header-meta { display: flex; flex-direction: column; align-items: center; gap: 0.25rem; font-size: 0.8125rem; color: var(--muted); }
.header-meta .env-row { display: flex; align-items: center; gap: 0.5rem; font-size: 0.875rem; color: var(--text-secondary); }
.header-meta .env-row strong { color: var(--text); font-weight: 600; }
.header-meta .env-arrow { color: var(--muted); font-size: 1rem; }
.header-meta .generated { font-size: 0.75rem; color: var(--muted); margin-top: 0.25rem; }
.score-card {
    background: var(--bg-card); border: 1px solid var(--border); border-radius: var(--radius);
    box-shadow: var(--shadow-md); padding: 2rem; margin-bottom: 1.5rem; text-align: center;
}
.score-value { font-size: 3.5rem; font-weight: 800; letter-spacing: -0.03em; margin-bottom: 0.5rem; font-variant-numeric: tabular-nums; }
.score-label { font-size: 0.875rem; color: var(--muted); margin-bottom: 1.25rem; font-weight: 500; }
.score-bar-track { width: 100%; max-width: 500px; height: 12px; background: var(--border); border-radius: 999px; margin: 0 auto; overflow: hidden; }
.score-bar-fill { height: 100%; border-radius: 999px; width: 0%; }
.summary-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 1rem; margin-bottom: 1rem; }
.summary-tile {
    background: var(--bg-card); border: 1px solid var(--border); border-radius: var(--radius);
    padding: 1.25rem; text-align: center; box-shadow: var(--shadow-sm); transition: box-shadow var(--transition);
}
.summary-tile:hover { box-shadow: var(--shadow-md); }
.summary-tile .count { font-size: 2rem; font-weight: 700; font-variant-numeric: tabular-nums; }
.summary-tile .label { font-size: 0.7rem; color: var(--muted); text-transform: uppercase; letter-spacing: 0.06em; font-weight: 600; margin-top: 0.25rem; }
.summary-tile.matched .count { color: var(--success); }
.summary-tile.conflicting .count { color: var(--danger); }
.summary-tile.source-only .count { color: var(--warning); }
.summary-tile.dest-only .count { color: var(--info); }
.summary-tile.manual .count { color: var(--manual); }
.search {
    width: 220px; padding: 6px 12px; border: 1px solid var(--border); border-radius: 8px;
    background: var(--bg-card); color: var(--text); font-size: 12px; font-family: inherit; outline: none;
    transition: border-color var(--transition);
}
.search:focus { border-color: var(--accent); }
.search-hidden { display: none !important; }
.filter-bar { display: flex; align-items: center; gap: 8px; padding: 12px 0; flex-wrap: wrap; }
.filter-label { display: none; }
.filter-pill {
    background: transparent; border: 1px solid var(--border); color: var(--muted);
    padding: 4px 12px; border-radius: 8px; font-size: 11px; cursor: pointer;
    transition: all .15s; font-family: inherit; font-weight: 600;
}
.filter-pill:hover { border-color: var(--text); color: var(--text); }
.filter-pill.active { color: #fff; }
.filter-pill-matched.active   { background: #16a34a; border-color: #16a34a; }
.filter-pill-conflicting.active { background: #dc2626; border-color: #dc2626; }
.filter-pill-source-only.active { background: #3b82f6; border-color: #3b82f6; }
.filter-pill-dest-only.active { background: #d97706; border-color: #d97706; }
.hidden { display: none !important; }
.status-hidden { display: none !important; }
/* Toggle CSS removed — deprecated settings now in their own tab */
.manual-item {
    background: var(--bg);
    border: 1px solid var(--border-subtle);
    border-radius: var(--radius-sm);
    padding: 1rem;
    margin-bottom: 0.75rem;
}
.tabs { display: flex; gap: 0; border-bottom: 2px solid var(--border); margin-bottom: 1.5rem; }
.tab {
    padding: 0.75rem 1.5rem; font-size: 0.875rem; font-weight: 600; color: var(--muted);
    cursor: pointer; border: none; border-bottom: 2px solid transparent; margin-bottom: -2px;
    transition: all var(--transition); background: none; font-family: inherit;
}
.tab:hover { color: var(--text); }
.tab.active { color: var(--accent); border-bottom-color: var(--accent); }
.tab .badge { margin-left: 0.375rem; }
.tab-content { display: none; }
.tab-content.active { display: block; }
.status-badge {
    display: inline-flex; align-items: center; gap: 5px; font-size: 10px; font-weight: 600; white-space: nowrap;
}
.status-dot { width: 7px; height: 7px; border-radius: 50%; display: inline-block; flex-shrink: 0; }
.status-matched { color: var(--success); }
.status-matched .status-dot { background: var(--success); }
.status-conflicting { color: var(--danger); }
.status-conflicting .status-dot { background: var(--danger); }
.status-source-only { color: var(--info); }
.status-source-only .status-dot { background: var(--info); }
.status-dest-only { color: var(--warning); }
.status-dest-only .status-dot { background: var(--warning); }
.status-manual { color: var(--manual); }
.status-manual .status-dot { background: var(--manual); }
.card {
    background: var(--bg-card); border: 1px solid var(--border); border-radius: var(--radius);
    box-shadow: var(--shadow-sm); padding: 1.25rem 1.5rem; margin-bottom: 1rem; transition: box-shadow var(--transition);
}
.card:hover { box-shadow: var(--shadow-md); }
.badge {
    display: inline-flex; align-items: center; background: var(--badge-bg); color: var(--badge-text);
    padding: 0.125rem 0.5rem; border-radius: 999px; font-size: 0.6875rem; font-weight: 600;
    letter-spacing: 0.01em; white-space: nowrap;
}
details { border-radius: var(--radius-xs); }
summary {
    cursor: pointer; padding: 0.5rem 0.625rem; border-radius: var(--radius-xs);
    user-select: none; list-style: none; transition: background var(--transition);
}
summary::-webkit-details-marker { display: none; }
summary:not(.script-collapsible summary):not(.mr-category-section summary):not(.mr-platform-section summary)::before {
    content: ''; display: inline-block; width: 0.375rem; height: 0.375rem;
    border-right: 2px solid var(--muted); border-bottom: 2px solid var(--muted);
    transform: rotate(-45deg); margin-right: 0.625rem; transition: transform var(--transition); flex-shrink: 0;
}
details:not(.script-collapsible):not(.mr-category-section):not(.mr-platform-section)[open] > summary::before { transform: rotate(45deg); }
.script-collapsible summary::before, .mr-category-section > summary::before, .mr-platform-section > summary::before { content: none !important; }
summary:hover { background: var(--summary-hover); }
.product-section { margin-bottom: 1rem; }
.product-section > summary {
    font-size: 1rem; font-weight: 700; padding: 0.875rem 1rem;
    background: var(--bg-card); border: 1px solid var(--border); border-radius: var(--radius);
    box-shadow: var(--shadow-sm); display: flex; align-items: center; gap: 0.5rem;
    margin-bottom: 0.5rem; flex-wrap: wrap;
}
.product-section > summary:hover { box-shadow: var(--shadow-md); }
.product-section[open] > summary { border-radius: var(--radius) var(--radius) 0 0; margin-bottom: 0; border-bottom-color: transparent; }
.product-content {
    background: var(--bg-card); border: 1px solid var(--border); border-top: none;
    border-radius: 0 0 var(--radius) var(--radius); padding: 0.75rem 1.25rem 1rem;
    box-shadow: var(--shadow-sm); margin-bottom: 0.5rem;
}
.product-title { flex: 1; }
h3 {
    font-size: 0.8125rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.06em;
    color: var(--muted); margin: 1.25rem 0 0.625rem; padding-bottom: 0.375rem;
    border-bottom: 1px solid var(--border-subtle);
}
h3:first-child { margin-top: 0.375rem; }
table { width: 100%; border-collapse: collapse; font-size: 11px; min-width: 400px; }
.table-wrap { overflow-x: auto; margin-bottom: 0.75rem; border-radius: var(--radius-xs); }
th {
    background: var(--bg-card); text-align: left; padding: 8px 10px; font-weight: 600;
    font-size: 9px; text-transform: uppercase; letter-spacing: 0.06em; color: var(--muted);
    border-bottom: 1px solid var(--border); user-select: none; position: relative; white-space: nowrap;
}
th[onclick]:hover { color: var(--text); }
td { padding: 6px 10px; border-bottom: 1px solid var(--border); vertical-align: top; color: var(--text); word-break: break-word; }
tr:last-child td { border-bottom: none; }
tr:nth-child(even) td { background: var(--row-alt); }
tr:hover td { background: var(--accent-soft); }
.policy-name { font-weight: 600; }
.setting-name { color: var(--text-secondary); }
.setting-path {
    display: block;
    font-size: 9px;
    color: var(--muted);
    margin-top: 1px;
    word-break: break-word;
}
.setting-name strong { font-weight: 500; font-size: 11px; color: var(--text); }
.value-cell { font-family: 'Cascadia Code', 'Fira Code', monospace; font-size: 10px; word-break: break-word; }
.value-truncate { max-height: 4.5em; overflow: hidden; position: relative; }
.value-truncate.expanded { max-height: none; white-space: pre-wrap; }
.value-toggle-btn {
    display: inline-flex; align-items: center; gap: 0.25rem;
    font-size: 0.625rem; font-weight: 400; color: var(--warning);
    background: none; border: none; padding: 0; cursor: pointer;
    transition: opacity var(--transition); font-family: inherit;
}
.value-toggle-btn:hover { opacity: 0.75; }
.value-actions { display: flex; align-items: center; gap: 0.5rem; margin-top: 0.25rem; }
.value-copy-btn {
    display: inline-flex; align-items: center; gap: 0.25rem;
    font-size: 0.625rem; font-weight: 400; color: var(--muted);
    background: none; border: none; padding: 0; cursor: pointer;
    opacity: 0; transition: opacity var(--transition), color var(--transition);
    font-family: inherit;
}
.value-copy-btn:hover { color: var(--text); }
.value-copy-btn.copied { color: var(--success); opacity: 1; }
td.value-cell:hover .value-copy-btn { opacity: 1; }
.ps-code { background: #1e1e1e !important; color: #d4d4d4; }
.value-diff { color: var(--danger); font-weight: 600; }
.manual-table td { vertical-align: middle; }
.policy-detail-row td { padding: 0.25rem 0.75rem; border-bottom: 1px solid var(--border-subtle); }
.policy-detail-row:hover td { background: transparent; }
.policy-detail-row .settings-table { font-size: 0.8rem; margin: 0.5rem 0; }
.policy-detail-row .settings-table th { font-size: 0.7rem; }
.policy-detail-row .settings-table td { font-size: 0.8rem; }
.policy-detail-row .settings-table .value-diff { color: var(--danger); font-weight: 600; }
.env-label {
    font-size: 0.6875rem; font-weight: 700; text-transform: uppercase; letter-spacing: 0.08em;
    padding: 0.125rem 0.5rem; border-radius: 4px; display: inline-block; text-align: center; min-width: 3.25rem;
}
.env-source { background: var(--warning-bg); color: var(--warning); }
.env-dest { background: var(--info-bg); color: var(--info); }
.policy-type-badge {
    font-size: 0.6875rem; font-weight: 600; padding: 0.125rem 0.5rem;
    border-radius: 999px; white-space: nowrap; display: inline-block;
}
.type-catalog { background: var(--success-bg); color: var(--success); }
.type-admin { background: var(--warning-bg); color: var(--warning); }
.type-other { background: var(--badge-bg); color: var(--badge-text); }
.manual-reason { font-size: 0.8125rem; color: var(--text-secondary); }
.footer { margin-top: 2rem; padding: 1rem 0; text-align: center; color: var(--muted); font-size: 0.75rem; }
.fab-group { position: fixed; bottom: 1.5rem; right: 1.5rem; display: flex; flex-direction: column; gap: 0.5rem; z-index: 200; }
.fab {
    width: 44px; height: 44px; border-radius: 50%; background: var(--accent); color: #fff; border: none;
    cursor: pointer; display: flex; align-items: center; justify-content: center;
    box-shadow: var(--shadow-md); transition: all var(--transition); font-size: 1.125rem;
}
.fab:hover { background: var(--accent-hover); box-shadow: var(--shadow-lg); transform: scale(1.05); }
.fab:focus-visible { outline: 2px solid var(--accent); outline-offset: 3px; }
.fab-top { opacity: 0; pointer-events: none; transform: translateY(8px); }
.fab-top.visible { opacity: 1; pointer-events: auto; transform: translateY(0); }
.theme-toggle { position:fixed; top:1rem; right:1rem; z-index:100; width:36px; height:36px; border-radius:50%; border:1px solid var(--border); background:var(--bg-card); color:var(--text); cursor:pointer; display:flex; align-items:center; justify-content:center; box-shadow:var(--shadow); transition:var(--transition); }
.theme-toggle:hover { border-color:var(--accent); color:var(--accent); box-shadow:var(--shadow-lg); }
@media (max-width: 768px) {
    body { padding: 0 1rem 2rem; font-size: 0.875rem; }
    .header h1 { font-size: 1.375rem; }
    .summary-grid { grid-template-columns: repeat(3, 1fr); }
    .product-section > summary { padding: 0.75rem; font-size: 0.9375rem; }
    td, th { padding: 0.375rem 0.5rem; }
    .fab-group { bottom: 1rem; right: 1rem; }
}
@media (max-width: 480px) { .summary-grid { grid-template-columns: repeat(2, 1fr); } }
.tab-nav { display: flex; gap: 0; margin-bottom: 1.5rem; border-bottom: 2px solid var(--border); }
.tab-btn { padding: 0.75rem 1.5rem; background: none; border: none; border-bottom: 2px solid transparent; margin-bottom: -2px; color: var(--text-secondary); font-size: 0.875rem; font-weight: 500; cursor: pointer; transition: all var(--transition); font-family: inherit; }
.tab-btn:hover { color: var(--text); background: var(--accent-soft); }
.tab-btn.active { color: var(--accent); border-bottom-color: var(--accent); }
.manual-review-card { background: var(--bg-card); border: 1px solid var(--border); border-radius: var(--radius-sm); padding: 0; margin-bottom: 0.75rem; }
.manual-review-card summary { padding: 0.75rem 1rem; font-size: 0.875rem; cursor: pointer; list-style: none; display: flex; align-items: center; gap: 0.5rem; user-select: text; }
.manual-review-card summary strong { cursor: text; }
.manual-review-card summary::-webkit-details-marker { display: none; }
.manual-review-card summary::before { content: '\25B6'; font-size: 0.65rem; color: var(--muted); transition: transform var(--transition); }
.manual-review-card[open] summary::before { transform: rotate(90deg); }
.manual-review-card[open] summary { border-bottom: 1px solid var(--border-subtle); }
.manual-review-card .mr-body { padding: 0.75rem 1rem; }
.manual-review-card .side-badge { display: inline-block; padding: 0.125rem 0.5rem; border-radius: 999px; font-size: 0.7rem; font-weight: 600; }
.manual-review-card .side-source { background: var(--info-bg); color: var(--info); }
.manual-review-card .side-dest { background: var(--warning-bg); color: var(--warning); }
.mr-split { display: grid; grid-template-columns: 1fr 1fr; gap: 1rem; }
.mr-split-col h4 { font-size: 0.8rem; margin: 0 0 0.5rem; padding: 0.25rem 0.5rem; border-radius: var(--radius-xs); }
.mr-split-col.mr-col-source h4 { background: var(--info-bg); color: var(--info); }
.mr-split-col.mr-col-dest h4 { background: var(--warning-bg); color: var(--warning); }
.mr-platform-section { margin-bottom: 1rem; }
.mr-platform-section > summary { font-size: 1rem; cursor: pointer; padding: 0.5rem 0; border-bottom: 1px solid var(--border-subtle); user-select: none; }
/* Assignment display — inline text, no badge backgrounds (D-04) */
.assign-row { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
.assign-cell-wrap { display: flex; flex-direction: column; gap: 4px; }
.assign-include { font-size: 0.75rem; color: var(--text); }
.assign-exclude { font-size: 0.75rem; color: var(--danger); }
.assign-all { font-size: 0.75rem; color: var(--info); }
.assign-filter { display: block; font-size: 0.625rem; color: var(--muted); white-space: normal; word-break: break-word; }
.assign-empty { font-size: 0.75rem; color: var(--muted); }
table.hide-assignments .col-assign { display: none; }
.cat-multiselect { position:relative; display:inline-block; }
.cat-ms-btn { padding:4px 12px; border:1px solid var(--border); border-radius:8px; background:var(--bg-card); color:var(--text); font-size:11px; font-family:inherit; cursor:pointer; font-weight:600; min-width:140px; text-align:left; transition:all var(--transition); }
.cat-ms-btn:hover { border-color:var(--accent); background:var(--accent-soft); }
.cat-ms-btn .cat-count { display:inline-block; background:var(--accent); color:#fff; font-size:9px; padding:1px 6px; border-radius:999px; margin-left:6px; font-weight:700; }
.cat-ms-dropdown { position:absolute; top:calc(100% + 4px); left:0; z-index:100; background:var(--bg-card); border:1px solid var(--border); border-radius:var(--radius-sm); box-shadow:var(--shadow-lg); max-height:0; overflow:hidden; min-width:300px; opacity:0; transition:max-height 0.25s ease, opacity 0.2s ease; }
.cat-ms-dropdown.open { max-height:340px; overflow-y:auto; opacity:1; }
.cat-ms-dropdown .cat-search { width:calc(100% - 16px); margin:8px; padding:4px 8px; border:1px solid var(--border); border-radius:6px; font-size:11px; background:var(--bg); color:var(--text); font-family:inherit; outline:none; }
.cat-ms-dropdown .cat-search:focus { border-color:var(--accent); }
.cat-ms-dropdown label { display:flex; align-items:center; gap:8px; padding:6px 12px; font-size:11px; cursor:pointer; white-space:nowrap; transition:background 0.15s; border-radius:4px; margin:0 4px; }
.cat-ms-dropdown label:hover { background:var(--accent-soft); }
.cat-ms-dropdown input[type=checkbox] { appearance:none; -webkit-appearance:none; width:16px; height:16px; border:2px solid var(--border); border-radius:4px; cursor:pointer; position:relative; flex-shrink:0; transition:all 0.15s; }
.cat-ms-dropdown input[type=checkbox]:checked { background:var(--accent); border-color:var(--accent); }
.cat-ms-dropdown input[type=checkbox]:checked::after { content:'\2713'; position:absolute; top:-1px; left:2px; color:#fff; font-size:11px; font-weight:700; }
.col-assign { overflow:hidden; text-overflow:ellipsis; word-wrap:break-word; }
.toggle-switch { position:relative; width:34px; height:18px; flex-shrink:0; }
.toggle-switch input { opacity:0; width:0; height:0; }
.toggle-switch .slider { position:absolute; inset:0; background:var(--border); border-radius:999px; cursor:pointer; transition:var(--transition); }
.toggle-switch .slider::before { content:''; position:absolute; left:2px; top:2px; width:14px; height:14px; background:var(--bg-card); border-radius:50%; transition:var(--transition); }
.toggle-switch input:checked + .slider { background:var(--accent); }
.toggle-switch input:checked + .slider::before { transform:translateX(16px); }
.adv-filter-wrap { display:inline-block; position:relative; }
.adv-filter-btn { border:1px solid var(--border); border-radius:8px; background:var(--bg-card); color:var(--text); padding:4px 10px; font-size:11px; font-family:inherit; cursor:pointer; transition:var(--transition); }
.adv-filter-btn:hover { border-color:var(--text); }
.adv-filter-menu { position:absolute; top:100%; left:0; z-index:100; background:var(--bg-card); border:1px solid var(--border); border-radius:8px; box-shadow:0 4px 12px rgba(0,0,0,0.15); min-width:160px; padding:4px 0; display:none; }
.adv-filter-menu.open { display:block; }
.adv-filter-menu button { display:block; width:100%; text-align:left; padding:6px 12px; border:none; background:none; font-size:12px; color:var(--text); cursor:pointer; font-family:inherit; }
.adv-filter-menu button:hover:not(:disabled) { background:var(--accent-soft); }
.adv-filter-menu button:disabled { opacity:0.4; cursor:default; }
#active-adv-filters { display:flex; flex-wrap:wrap; gap:0.5rem; padding:0 0.75rem; }
#active-adv-filters:empty { display:none; }
.adv-chip { display:inline-flex; align-items:center; gap:4px; background:var(--accent-soft); border:1px solid var(--accent); border-radius:6px; padding:2px 8px; font-size:11px; }
.adv-chip label { font-weight:600; color:var(--accent); }
.adv-chip input { border:1px solid var(--border); border-radius:4px; padding:2px 6px; font-size:11px; width:140px; background:var(--bg-card); color:var(--text); font-family:inherit; }
.adv-chip .adv-chip-remove { cursor:pointer; color:var(--danger); font-weight:bold; margin-left:2px; border:none; background:none; font-size:13px; line-height:1; }
.adv-logic-btn { display:inline-flex; align-items:center; justify-content:center; min-width:36px; height:22px; border-radius:11px; cursor:pointer; margin:0 6px; border:none; font-size:9px; font-weight:700; letter-spacing:0.05em; padding:0 8px; transition:all 0.2s; user-select:none; flex-shrink:0; color:#fff; }
.adv-logic-btn[data-mode="AND"] { background:var(--accent); }
.adv-logic-btn[data-mode="OR"] { background:var(--warning); }
.tag-input-wrap { display:flex; flex-wrap:wrap; align-items:center; gap:3px; border:1px solid var(--border); border-radius:4px; padding:2px 4px; min-width:160px; background:var(--bg-card); cursor:text; }
.tag-input-wrap:focus-within { border-color:var(--accent); }
.tag-input-wrap .tag { display:inline-flex; align-items:center; gap:2px; background:var(--accent); color:#fff; border-radius:3px; padding:1px 4px; font-size:10px; white-space:nowrap; }
.tag-input-wrap .tag button { border:none; background:none; color:#fff; cursor:pointer; font-size:11px; line-height:1; padding:0 1px; opacity:0.8; }
.tag-input-wrap .tag button:hover { opacity:1; }
.tag-input-wrap input { border:none; outline:none; font-size:11px; background:transparent; color:var(--text); flex:1; min-width:60px; padding:1px 2px; font-family:inherit; }
.adv-dropdown-wrap { position:relative; display:inline-block; }
.adv-dropdown-btn { border:1px solid var(--border); border-radius:4px; padding:3px 10px; font-size:11px; background:var(--bg-card); color:var(--text); cursor:pointer; min-width:100px; text-align:left; font-family:inherit; white-space:nowrap; }
.adv-dropdown-btn:hover { border-color:var(--accent); }
.adv-dropdown-menu { display:none; position:absolute; top:calc(100% + 2px); left:0; z-index:120; background:var(--bg-card); border:1px solid var(--border); border-radius:8px; box-shadow:0 4px 16px rgba(0,0,0,0.18); padding:6px 0; min-width:180px; max-height:220px; overflow-y:auto; }
.adv-dropdown-menu.open { display:block; }
.adv-dropdown-menu label { display:flex; align-items:center; gap:8px; padding:6px 12px; font-size:11px; color:var(--text); cursor:pointer; white-space:nowrap; }
.adv-dropdown-menu label:hover { background:var(--accent-soft); }
.adv-dropdown-menu input[type=checkbox] { width:14px; height:14px; margin:0; accent-color:var(--accent); flex-shrink:0; cursor:pointer; }
.score-bar-fill { transition:width 0.5s cubic-bezier(0.4,0,0.2,1), background-color 0.5s ease; }
.mr-category-section > summary::-webkit-details-marker { display:none; }
.mr-category-section[open] .cat-chevron { display:inline-block; transform:rotate(90deg); }
.script-collapsible summary { cursor:pointer; display:flex; align-items:center; gap:0.5rem; list-style:none; padding:0.35rem 0; }
.script-collapsible summary::-webkit-details-marker { display:none; }
.script-collapsible summary::after { content:''; display:inline-block; width:6px; height:6px; border-right:2px solid var(--muted); border-bottom:2px solid var(--muted); transform:rotate(-45deg); transition:transform 0.2s ease; margin-left:auto; flex-shrink:0; }
.script-collapsible[open] summary::after { transform:rotate(45deg); }
.badge-deprecated { display: inline-block; padding: 0.15rem 0.6rem; border-radius: 999px; font-size: 0.7rem; font-weight: 700; background: var(--danger-bg); color: var(--danger); animation: pulse-deprecated 1.5s ease-in-out infinite; }
@keyframes pulse-deprecated { 0%,100% { opacity: 1; } 50% { opacity: 0.5; } }
.col-resize-handle { position: absolute; top: 0; right: -4px; width: 8px; height: 100%; cursor: col-resize; z-index: 10; display: flex; align-items: center; justify-content: center; user-select: none; }
.col-resize-handle::after { content: ''; display: block; width: 2px; height: 60%; border-radius: 2px; background: transparent; transition: background 0.15s, height 0.15s; }
.col-resize-handle:hover::after { background: var(--accent); height: 100%; }
.col-resize-handle.resizing::after { background: var(--warning); height: 100%; width: 3px; }
.badge-duplicate { display: inline-block; padding: 0.15rem 0.6rem; border-radius: 999px; font-size: 0.7rem; font-weight: 600; background: var(--warning-bg); color: var(--warning); cursor: help; }
/* .setting-deprecated defined below with manual-review-setting styles */
.manual-review-setting { display: flex; justify-content: space-between; padding: 0.25rem 0; border-bottom: 1px solid var(--border-subtle); font-size: 0.8rem; }
.ps-keyword { color: #569cd6; font-weight: 600; }
.ps-string { color: #ce9178; }
.ps-variable { color: #9cdcfe; }
.ps-comment { color: #6a9955; font-style: italic; }
.ps-cmdlet { color: #dcdcaa; }
.ps-operator { color: #d4d4d4; }
.ps-type { color: #4ec9b0; }
.ps-code-wrap { position: relative; }
.copy-btn { position: absolute; top: 0.5rem; right: 0.5rem; padding: 0.25rem 0.75rem; font-size: 0.7rem; background: var(--accent); color: #fff; border: none; border-radius: var(--radius-xs); cursor: pointer; opacity: 0.7; transition: opacity var(--transition); z-index: 1; }
.copy-btn:hover { opacity: 1; }
.sh-keyword { color: #ff7b72; font-weight: 600; }
.sh-string { color: #a5d6ff; }
.sh-variable { color: #ffa657; }
.sh-command { color: #d2a8ff; }
.sh-comment { color: #8b949e; font-style: italic; }
.code-lang-label { display: inline-block; padding: 0.25rem 0.5rem; font-size: 0.625rem; font-weight: 400; text-transform: uppercase; letter-spacing: 0.06em; color: var(--muted); background: var(--bg-card); border-bottom: 1px solid var(--border); border-radius: var(--radius-xs) var(--radius-xs) 0 0; user-select: none; }
.compliance-table { width: 100%; border-collapse: collapse; font-size: 0.75rem; margin: 0.5rem 0; }
.compliance-table th { background: var(--header-bg); color: var(--muted); font-weight: 600; font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.05em; padding: 0.25rem 0.5rem; text-align: left; border-bottom: 1px solid var(--border); white-space: nowrap; }
.compliance-table td { padding: 0.25rem 0.5rem; border-bottom: 1px solid var(--border-subtle); color: var(--text-secondary); word-break: break-word; font-family: "SF Mono","Cascadia Code","Consolas",monospace; }
.compliance-table tr:last-child td { border-bottom: none; }
.dup-table-wrap { overflow-x: auto; margin: 0.5rem 0; }
.dup-table { border-collapse: collapse; font-size: 0.75rem; min-width: 100%; }
.dup-table th { background: var(--header-bg); color: var(--muted); font-weight: 600; font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.05em; padding: 0.25rem 0.5rem; text-align: left; border-bottom: 1px solid var(--border); white-space: nowrap; }
.dup-table td { padding: 0.25rem 0.5rem; border-bottom: 1px solid var(--border-subtle); color: var(--text-secondary); word-break: break-word; font-family: "SF Mono","Cascadia Code","Consolas",monospace; vertical-align: top; }
.dup-table td.dup-setting-name { font-family: inherit; font-weight: 600; color: var(--text); white-space: nowrap; }
.dup-table td.dup-conflict { background: var(--warning-bg); color: var(--warning); font-weight: 600; }
.manual-review-setting .setting-name { color: var(--text); flex: 1; }
.manual-review-setting .setting-value { color: var(--text-secondary); max-width: 40%; text-align: right; word-break: break-word; font-family: "SF Mono","Cascadia Code","Consolas",monospace; font-size: 0.75rem; }
.setting-value.val-true { font-weight: 600; color: var(--accent); background: var(--accent-soft); padding: 1px 8px; border-radius: 4px; }
.setting-value.val-false { color: var(--muted); opacity: 0.6; }
.manual-review-setting:nth-child(even) { background: var(--row-alt); }
.setting-deprecated { background: transparent !important; padding: 0.25rem 0.5rem; margin: 0.1rem 0; }
.setting-deprecated .setting-name { color: var(--danger); font-weight: 600; }
.dup-info-banner { display:flex; gap:0.75rem; align-items:flex-start; border:1px solid var(--warning); border-left:4px solid var(--warning); border-radius:var(--radius-sm); background:var(--warning-bg); padding:1rem; margin-bottom:1rem; }
.dup-banner-icon { color:var(--warning); font-size:1.1rem; flex-shrink:0; margin-top:0.1rem; }
.dup-banner-title { font-size:0.875rem; font-weight:600; color:var(--text); margin:0 0 0.25rem; }
.dup-banner-body { font-size:0.8125rem; color:var(--text-secondary); margin:0 0 0.25rem; }
.dup-banner-note { font-size:0.75rem; color:var(--muted); font-style:italic; margin:0; }
.dup-tab-table { width:100%; border-collapse:collapse; font-size:0.8125rem; }
.dup-tab-table thead { position:sticky; top:0; z-index:10; }
.dup-tab-table th { text-align:left; padding:0.5rem 0.75rem; font-size:0.6875rem; font-weight:600; text-transform:uppercase; letter-spacing:0.06em; color:var(--muted); border-bottom:1px solid var(--border); background:var(--bg-card); }
.dup-tab-table td { padding:0.5rem 0.75rem; vertical-align:top; border-bottom:1px solid var(--border-subtle); }
.dup-tab-table tbody tr:nth-child(even) { background:var(--row-alt); }
.dup-tab-table tbody tr:hover { background:var(--accent-soft); }
.dup-tab-setting { font-weight:600; color:var(--text); width:30%; }
.dup-tab-policies { width:35%; }
.dup-tab-analysis-col { width:35%; }
.dup-policy-entry { margin-bottom:0.5rem; }
.dup-policy-entry:last-child { margin-bottom:0; }
.dup-policy-entry .side-badge { display:inline-block; padding:0.125rem 0.5rem; border-radius:999px; font-size:0.7rem; font-weight:600; }
.dup-policy-entry .side-source { background:var(--info-bg); color:var(--info); }
.dup-policy-entry .side-dest { background:var(--warning-bg); color:var(--warning); }
.dup-setting-path { display:block; font-size:0.6875rem; color:var(--muted); font-weight:400; margin-top:0.125rem; }
.dup-policy-value { font-family:"SF Mono","Cascadia Code","Consolas",monospace; font-size:0.75rem; color:var(--warning); word-break:break-word; display:block; margin-top:0.25rem; }
.dup-analysis-text { font-size:0.6875rem; color:var(--muted); line-height:1.6; margin:0; }
.dup-table-scroll { border:1px solid var(--border); border-radius:var(--radius-sm); overflow:hidden; }
.dup-table-scroll-inner { overflow-y:auto; max-height:calc(100vh - 400px); }
.dup-summary { font-size:0.75rem; color:var(--muted); margin:0.5rem 0 1rem; }
.dup-no-results { display:none; padding:3rem 0; text-align:center; color:var(--muted); font-size:0.875rem; }
.tab-btn .status-badge { pointer-events:none; }
'@

    # ── Extract model values ───────────────────────────────────────────────
    $sourceName      = [System.Net.WebUtility]::HtmlEncode($ComparisonModel.SourceName)
    $destName        = [System.Net.WebUtility]::HtmlEncode($ComparisonModel.DestinationName)
    $generatedAt     = [System.Net.WebUtility]::HtmlEncode($ComparisonModel.GeneratedAt)
    $alignmentScore  = if ($null -ne $ComparisonModel.AlignmentScore) { $ComparisonModel.AlignmentScore } else { 0 }
    $totalItems      = if ($null -ne $ComparisonModel.TotalItems) { $ComparisonModel.TotalItems } else { 0 }
    $matched         = if ($null -ne $ComparisonModel.Counters.Matched) { $ComparisonModel.Counters.Matched } else { 0 }
    $conflicting     = if ($null -ne $ComparisonModel.Counters.Conflicting) { $ComparisonModel.Counters.Conflicting } else { 0 }
    $sourceOnly      = if ($null -ne $ComparisonModel.Counters.SourceOnly) { $ComparisonModel.Counters.SourceOnly } else { 0 }
    $destOnly        = if ($null -ne $ComparisonModel.Counters.DestOnly) { $ComparisonModel.Counters.DestOnly } else { 0 }
    $products        = $ComparisonModel.Products
    $inclAssignments = $ComparisonModel.IncludingAssignments

    # Bar color is set dynamically by JS based on current animated percentage

    # ── StringBuilder ──────────────────────────────────────────────────────
    $sb = [System.Text.StringBuilder]::new(65536)

    # ── DOCTYPE, head, style ───────────────────────────────────────────────
    [void]$sb.AppendLine('<!DOCTYPE html>')
    [void]$sb.AppendLine('<html lang="en">')
    [void]$sb.AppendLine('<head>')
    [void]$sb.AppendLine('<meta charset="UTF-8">')
    [void]$sb.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1.0">')
    [void]$sb.AppendLine("<title>Intune Configuration Comparison &#8212; $sourceName vs $destName</title>")
    [void]$sb.AppendLine('<style>')
    [void]$sb.AppendLine($cssBlock)
    [void]$sb.AppendLine('</style>')
    [void]$sb.AppendLine('</head>')
    [void]$sb.AppendLine('<body>')
    [void]$sb.AppendLine('<div id="top"></div>')

    # ── Notch bar ──────────────────────────────────────────────────────────
    $notchDetail = "$totalItems settings compared"
    [void]$sb.AppendLine("<div class=`"notch-bar`">Intune Comparison<span class=`"notch-warn`">$notchDetail</span></div>")

    # ── Header ─────────────────────────────────────────────────────────────
    [void]$sb.AppendLine('<div class="header">')
    [void]$sb.AppendLine('    <h1>Intune Configuration Comparison Report</h1>')
    [void]$sb.AppendLine('    <div class="header-meta">')
    [void]$sb.AppendLine("        <div class=`"env-row`"><strong>$sourceName</strong><span class=`"env-arrow`">&#10132;</span><strong>$destName</strong></div>")
    [void]$sb.AppendLine("        <div class=`"generated`">Generated $generatedAt</div>")
    [void]$sb.AppendLine('    </div>')
    [void]$sb.AppendLine('</div>')

    # ── Score card ─────────────────────────────────────────────────────────
    [void]$sb.AppendLine('<div class="score-card">')
    [void]$sb.AppendLine('    <div class="score-value" id="scoreNum">0%</div>')
    [void]$sb.AppendLine("    <div class=`"score-label`">Overall Alignment &mdash; <span id=`"scoreDetail`">0 of $totalItems settings matched</span></div>")
    [void]$sb.AppendLine("    <div class=`"score-bar-track`"><div class=`"score-bar-fill`" id=`"scoreBar`"></div></div>")
    [void]$sb.AppendLine('</div>')

    # Helper: simplify composite category to last meaningful segment
    # "Defender / All / Antivirus" -> "Antivirus", "Intune / Windows / Settings Catalog" -> "Settings Catalog"
    $simplifyCategory = {
        param([string]$Category)
        if ([string]::IsNullOrEmpty($Category)) { return $Category }
        $parts = $Category -split ' / '
        $meaningful = @($parts | Where-Object { $_ -ne 'All' -and -not [string]::IsNullOrWhiteSpace($_) })
        if ($meaningful.Count -eq 0) { return $Category }
        return $meaningful[-1]
    }

    # ── Summary tiles ──────────────────────────────────────────────────────
    [void]$sb.AppendLine('<div class="summary-grid">')
    [void]$sb.AppendLine('    <div class="summary-tile matched"><div class="count" id="countMatched">0</div><div class="label">Matched</div></div>')
    [void]$sb.AppendLine('    <div class="summary-tile conflicting"><div class="count" id="countConflicting">0</div><div class="label">Conflicting</div></div>')
    [void]$sb.AppendLine("    <div class=`"summary-tile source-only`"><div class=`"count`" id=`"countSource`">0</div><div class=`"label`">$sourceName Only</div></div>")
    [void]$sb.AppendLine("    <div class=`"summary-tile dest-only`"><div class=`"count`" id=`"countDest`">0</div><div class=`"label`">$destName Only</div></div>")
    [void]$sb.AppendLine('</div>')

    # ── Filters (wrapped in comparison-filters container for tab toggling) ──
    [void]$sb.AppendLine('<div id="comparison-filters">')

    # ── Collect all unique categories for the filter dropdown (Fix 5: before rendering) ──
    # D-01/D-02: Use "$productName / $categoryName" composite from outer loop keys, not $row.Category
    $allCategories = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($productName in $products.Keys) {
        $productData = $products[$productName]
        foreach ($categoryName in $productData.Categories.Keys) {
            $categoryData = $productData.Categories[$categoryName]
            foreach ($r in $categoryData.ComparisonRows) {
                $cat = & $simplifyCategory "$productName / $categoryName"
                if (-not [string]::IsNullOrWhiteSpace($cat)) { [void]$allCategories.Add($cat) }
            }
        }
    }

    # ── Filter pills ──────────────────────────────────────────────────────
    [void]$sb.AppendLine('<div class="filter-bar">')
    [void]$sb.AppendLine('    <input class="search" id="search-input" type="text" placeholder="Quick search..." oninput="applyFilters()">')
    [void]$sb.AppendLine('    <button class="filter-pill filter-pill-matched" onclick="filterByStatus(this,''Matched'')">Matched</button>')
    [void]$sb.AppendLine('    <button class="filter-pill filter-pill-conflicting" onclick="filterByStatus(this,''Conflicting'')">Conflicting</button>')
    [void]$sb.AppendLine("    <button class=`"filter-pill filter-pill-source-only`" onclick=`"filterByStatus(this,'SourceOnly')`">$sourceName Only</button>")
    [void]$sb.AppendLine("    <button class=`"filter-pill filter-pill-dest-only`" onclick=`"filterByStatus(this,'DestOnly')`">$destName Only</button>")
    # Category filter dropdown (multi-select with checkboxes)
    [void]$sb.Append('    <div class="cat-multiselect" id="cat-multiselect"><button class="cat-ms-btn" onclick="toggleCatDropdown()">All categories</button><div class="cat-ms-dropdown" id="cat-ms-dropdown"><input type="text" class="cat-search" placeholder="Search categories..." oninput="filterCatDropdown(this.value)">')
    foreach ($catName in $allCategories) {
        $encCat = [System.Net.WebUtility]::HtmlEncode($catName)
        [void]$sb.Append("<label><input type=`"checkbox`" value=`"$encCat`" onchange=`"applyFilters()`"> $encCat</label>")
    }
    [void]$sb.AppendLine('</div></div>')
    [void]$sb.AppendLine('    <span class="adv-filter-wrap"><button class="adv-filter-btn" onclick="toggleAdvMenu()" title="Add column filter">+ Filter</button><div class="adv-filter-menu" id="adv-filter-menu"><button onclick="addAdvFilter(''status'',''Status'',0)">Status</button><button onclick="addAdvFilter(''setting'',''Setting Name'',1)">Setting Name</button><button onclick="addAdvFilter(''category'',''Category'',2)">Category</button><button onclick="addAdvFilter(''policy'',''Policy Name'',3)">Policy Name</button><button onclick="addAdvFilter(''value'',''Value'',4)">Value</button><button onclick="addAdvFilter(''assignment'',''Assignment'',7)">Assignment</button></div></span>')
    # Per-chip AND/OR connectors are inserted dynamically by addAdvFilter()
    [void]$sb.AppendLine('    <button id="clear-filters-btn" class="hidden" onclick="clearFilters()" style="color:var(--danger);background:none;border:none;font-size:0.75rem;font-weight:600;cursor:pointer;padding:0.25rem 0.5rem">Clear filters</button>')
    if ($inclAssignments) {
        [void]$sb.AppendLine('    <label style="margin-left:auto;display:flex;align-items:center;gap:0.5rem;font-size:0.75rem;color:var(--text-secondary);cursor:pointer;user-select:none"><span>Exclude unassigned</span><span class="toggle-switch"><input type="checkbox" id="toggle-exclude-unassigned" onchange="applyFilters()"><span class="slider"></span></span></label>')
        [void]$sb.AppendLine('    <label style="margin-left:0.75rem;display:flex;align-items:center;gap:0.5rem;font-size:0.75rem;color:var(--text-secondary);cursor:pointer;user-select:none"><span>Assignments</span><span class="toggle-switch"><input type="checkbox" id="toggle-assignments" checked onchange="toggleAssignments(this.checked)"><span class="slider"></span></span></label>')
    }
    [void]$sb.AppendLine('</div>')
    [void]$sb.AppendLine('<div id="filter-summary" style="font-size:0.75rem;font-weight:600;color:var(--accent);padding:0.5rem 0.75rem;margin:0.5rem 0;background:var(--accent-soft);border-radius:var(--radius-xs);"></div>')
    [void]$sb.AppendLine('<div id="active-adv-filters"></div>')
    [void]$sb.AppendLine('</div>')  # end comparison-filters

    # ── Tab navigation ──────────────────────────────────────────────────
    $manualReview = $ComparisonModel.ManualReview
    $hasManualReview = $null -ne $manualReview -and $manualReview.Count -gt 0
    # Exclude duplicate category from MR count — duplicates have their own tab (Phase 10)
    $mrCount = if ($hasManualReview) {
        $dupeKey = 'Duplicate Settings (Different Values)'
        ($manualReview.Keys | Where-Object { $_ -ne $dupeKey } | ForEach-Object { $manualReview[$_].Count } | Measure-Object -Sum).Sum
    } else { 0 }
    $hasManualReview = $mrCount -gt 0

    # ── Duplicate data collection (must be before tab nav so $hasDuplicates is ready) ──
    $duplicateLookup = @{}
    $dupRows = [System.Collections.Generic.List[hashtable]]::new()
    $dupSeen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $dupeCategory = 'Duplicate Settings (Different Values)'
    if ($ComparisonModel.ManualReview -and $ComparisonModel.ManualReview.Contains($dupeCategory)) {
        foreach ($item in $ComparisonModel.ManualReview[$dupeCategory]) {
            foreach ($s in $item.Settings) {
                if ($s.Value -match '^__DUPLICATE_TABLE__') {
                    $jsonPart = $s.Value -replace '^__DUPLICATE_TABLE__', ''
                    try {
                        $pairs = $jsonPart | ConvertFrom-Json -Depth 10
                        $dupeKey = $s.Name.ToLowerInvariant()
                        if (-not $duplicateLookup.ContainsKey($dupeKey)) {
                            $duplicateLookup[$dupeKey] = $pairs
                        }
                        if ($dupSeen.Add($dupeKey)) {
                            $dupRows.Add(@{ Name = $s.Name; Policies = $pairs })
                        }
                    } catch {
                        Write-Verbose "Failed to parse duplicate table JSON for '$($s.Name)': $_"
                    }
                }
            }
        }
    }
    $dupCount = $dupRows.Count
    $hasDuplicates = $dupCount -gt 0

    # ── Build allRows FIRST (needed for deprecated tab detection before tab nav) ──

    # Collect ALL comparison rows into a single flat list with composite category
    # D-01/D-02: composite = "$productName / $categoryName" (outer loop keys, not $row.Category)
    $allRows = [System.Collections.Generic.List[object]]::new()
    foreach ($productName in $products.Keys) {
        $productData = $products[$productName]
        foreach ($categoryName in $productData.Categories.Keys) {
            $compositeCategory = & $simplifyCategory "$productName / $categoryName"
            foreach ($r in $productData.Categories[$categoryName].ComparisonRows) {
                [void]$allRows.Add([PSCustomObject]@{ Row = $r; CompositeCategory = $compositeCategory })
            }
        }
    }
    $allRows = @($allRows | Sort-Object { $_.Row.Name })

    # ── Collect deprecated settings for dedicated tab ──
    $deprecatedRows = [System.Collections.Generic.List[object]]::new()
    foreach ($entry in $allRows) {
        $r = $entry.Row
        $isDepr = $false
        if ($r -is [hashtable]) {
            if ($r.ContainsKey('IsDeprecated') -and $r['IsDeprecated'] -eq $true) { $isDepr = $true }
        } else {
            if ($r.PSObject.Properties['IsDeprecated'] -and $r.IsDeprecated -eq $true) { $isDepr = $true }
        }
        # Fallback: check name for "deprecated" (catalog flags these in display name)
        if (-not $isDepr) {
            $rowName = if ($r -is [hashtable]) { $r['Name'] } else { $r.Name }
            if ($rowName -match '(?i)deprecated') { $isDepr = $true }
        }
        if ($isDepr) { [void]$deprecatedRows.Add($entry) }
    }
    $deprecatedCount = $deprecatedRows.Count
    $hasDeprecated = $deprecatedCount -gt 0
    Write-Host "  Deprecated settings: $deprecatedCount" -ForegroundColor $(if ($hasDeprecated) { 'Yellow' } else { 'Gray' })

    # ── Tab navigation (rendered after allRows + deprecated collection) ──
    [void]$sb.AppendLine('<div class="tab-nav">')
    [void]$sb.AppendLine('    <button class="tab-btn active" onclick="switchTab(''comparison'', event)">Comparison</button>')
    if ($hasManualReview) {
        [void]$sb.AppendLine("    <button class=`"tab-btn`" onclick=`"switchTab('manual-review', event)`">Manual Review <span class=`"status-badge`" style=`"margin-left:0.5rem;font-size:0.7rem`">$mrCount</span></button>")
    }
    if ($hasDuplicates) {
        [void]$sb.AppendLine("    <button class=`"tab-btn`" onclick=`"switchTab('duplicates', event)`">Duplicates <span class=`"status-badge`" style=`"margin-left:0.5rem;font-size:0.7rem`">$dupCount</span></button>")
    }
    if ($hasDeprecated) {
        [void]$sb.AppendLine("    <button class=`"tab-btn`" onclick=`"switchTab('deprecated', event)`">Deprecated <span class=`"status-badge`" style=`"margin-left:0.5rem;font-size:0.7rem;background:var(--danger-bg);color:var(--danger)`">$deprecatedCount</span></button>")
    }
    [void]$sb.AppendLine('</div>')

    # ── Comparison tab ───────────────────────────────────────────────────
    [void]$sb.AppendLine('<div class="tab-content active" id="tab-comparison">')

    if ($allRows.Count -gt 0) {
        [void]$sb.AppendLine('    <div class="table-wrap">')
        [void]$sb.AppendLine('    <table id="comparison-table" style="table-layout:fixed;width:100%">')
        [void]$sb.AppendLine('        <thead><tr>')
        if ($inclAssignments) {
            # Narrower widths to accommodate 2 assignment columns (9 cols total)
            [void]$sb.Append('            <th style="width:5%;cursor:pointer" onclick="sortTable(this,0)">Status &#x25B4;&#x25BE;</th>')
            [void]$sb.Append('<th style="width:19%;cursor:pointer" onclick="sortTable(this,1)">Setting &#x25B4;&#x25BE;</th>')
            [void]$sb.Append('<th style="width:10%;cursor:pointer" onclick="sortTable(this,2)">Category &#x25B4;&#x25BE;</th>')
            [void]$sb.Append("<th style=`"width:12%;cursor:pointer`" onclick=`"sortTable(this,3)`">$sourceName Policy &#x25B4;&#x25BE;</th>")
            [void]$sb.Append("<th style=`"width:12%;cursor:pointer`" onclick=`"sortTable(this,4)`">$sourceName Value &#x25B4;&#x25BE;</th>")
            [void]$sb.Append("<th style=`"width:12%;cursor:pointer`" onclick=`"sortTable(this,5)`">$destName Policy &#x25B4;&#x25BE;</th>")
            [void]$sb.Append("<th style=`"width:12%;cursor:pointer`" onclick=`"sortTable(this,6)`">$destName Value &#x25B4;&#x25BE;</th>")
            [void]$sb.Append("<th class=`"col-assign`" style=`"width:9%`">$sourceName Assignment</th>")
            [void]$sb.Append("<th class=`"col-assign`" style=`"width:9%`">$destName Assignment</th>")
        } else {
            # Standard widths for 7-column layout
            [void]$sb.Append('            <th style="width:6%;cursor:pointer" onclick="sortTable(this,0)">Status &#x25B4;&#x25BE;</th>')
            [void]$sb.Append('<th style="width:22%;cursor:pointer" onclick="sortTable(this,1)">Setting &#x25B4;&#x25BE;</th>')
            [void]$sb.Append('<th style="width:12%;cursor:pointer" onclick="sortTable(this,2)">Category &#x25B4;&#x25BE;</th>')
            [void]$sb.Append("<th style=`"width:15%;cursor:pointer`" onclick=`"sortTable(this,3)`">$sourceName Policy &#x25B4;&#x25BE;</th>")
            [void]$sb.Append("<th style=`"width:15%;cursor:pointer`" onclick=`"sortTable(this,4)`">$sourceName Value &#x25B4;&#x25BE;</th>")
            [void]$sb.Append("<th style=`"width:15%;cursor:pointer`" onclick=`"sortTable(this,5)`">$destName Policy &#x25B4;&#x25BE;</th>")
            [void]$sb.Append("<th style=`"width:15%;cursor:pointer`" onclick=`"sortTable(this,6)`">$destName Value &#x25B4;&#x25BE;</th>")
        }
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('        </tr></thead>')
        [void]$sb.AppendLine('        <tbody>')

            # Helper: convert assignment string to inline colored HTML (D-01 through D-07)
            $formatAssignHtml = {
                param([string]$AssignStr)
                if ([string]::IsNullOrWhiteSpace($AssignStr)) {
                    return '<span class="assign-empty">&mdash;</span>'
                }
                $html = [System.Text.StringBuilder]::new()
                [void]$html.Append('<div class="assign-cell-wrap">')
                foreach ($part in ($AssignStr -split ';\s*')) {
                    $part = $part.Trim()
                    if ([string]::IsNullOrWhiteSpace($part)) { continue }

                    # Filter extraction (D-07)
                    $mainText   = $part
                    $filterText = ''
                    if ($part -match '^(.+?)(\s*\((?:include|exclude):.+\))$') {
                        $mainText   = $Matches[1].Trim()
                        $filterText = $Matches[2].Trim()
                    }

                    $encMain   = [System.Net.WebUtility]::HtmlEncode($mainText)
                    $encFilter = [System.Net.WebUtility]::HtmlEncode($filterText)

                    [void]$html.Append('<div class="assign-row">')

                    # Type detection (mirrors AssignmentTags.tsx getType)
                    $lc = $mainText.ToLower()
                    if ($lc -match 'all devices') {
                        [void]$html.Append("<span class=`"assign-all`">$encMain</span>")
                    } elseif ($lc -match 'all users') {
                        [void]$html.Append("<span class=`"assign-all`">$encMain</span>")
                    } elseif ($mainText -match '^Exclude:\s*') {
                        [void]$html.Append("<span class=`"assign-exclude`">$encMain</span>")
                    } else {
                        [void]$html.Append("<span class=`"assign-include`">$encMain</span>")
                    }

                    if ($filterText) {
                        [void]$html.Append("<span class=`"assign-filter`">$encFilter</span>")
                    }
                    [void]$html.Append('</div>')
                }
                [void]$html.Append('</div>')
                return $html.ToString()
            }

            # $duplicateLookup already populated above (before tab nav), reused here for TBL-02 badges

            foreach ($rowWrapper in $allRows) {
                # Unpack wrapper: $row is the actual data row, $compositeCategory is "$productName / $categoryName"
                $row = $rowWrapper.Row
                $status = $row.Status

                # Status badge
                switch ($status) {
                    'Matched'     { $statusHtml = '<span class="status-badge status-matched"><span class="status-dot"></span>Match</span>' }
                    'Conflicting' { $statusHtml = '<span class="status-badge status-conflicting"><span class="status-dot"></span>Conflict</span>' }
                    'SourceOnly'  { $statusHtml = '<span class="status-badge status-source-only"><span class="status-dot"></span>Source Only</span>' }
                    'DestOnly'    { $statusHtml = '<span class="status-badge status-dest-only"><span class="status-dot"></span>Dest Only</span>' }
                    default       { $statusHtml = [System.Net.WebUtility]::HtmlEncode($status) }
                }

                $encName = [System.Net.WebUtility]::HtmlEncode($row.Name)
                # D-01/D-02: use composite "$productName / $categoryName" from outer loop, not $row.Category
                $encCategory = [System.Net.WebUtility]::HtmlEncode($rowWrapper.CompositeCategory)
                # Determine if both source and dest values are empty
                $srcValRaw = "$($row.SourceValue)".Trim()
                $dstValRaw = "$($row.DestValue)".Trim()
                $bothEmpty = (([string]::IsNullOrEmpty($srcValRaw) -or $srcValRaw -eq [char]0x2014) -and
                              ([string]::IsNullOrEmpty($dstValRaw) -or $dstValRaw -eq [char]0x2014))
                $emptyAttr = if ($bothEmpty) { ' data-empty="true"' } else { '' }
                $encSrcPol = [System.Net.WebUtility]::HtmlEncode($row.SourcePolicy)
                $encDstPol = [System.Net.WebUtility]::HtmlEncode($row.DestPolicy)
                [void]$sb.Append("                <tr data-status=`"$status`" data-category=`"$encCategory`" data-src-policy=`"$encSrcPol`" data-dst-policy=`"$encDstPol`"$emptyAttr><td>")
                [void]$sb.Append($statusHtml)
                [void]$sb.Append('</td>')

                # Setting/Policy name
                # Duplicate badge lookup (per D-05 through D-08)
                $rowKey = if ($row.SettingPath) { $row.SettingPath.ToLowerInvariant() } else { $row.Name.ToLowerInvariant() }
                $dupeBadge = ''
                if ($duplicateLookup.ContainsKey($rowKey)) {
                    $allPolicies = $duplicateLookup[$rowKey]
                    $currentPol  = if ($row.SourcePolicy) { $row.SourcePolicy } else { $row.DestPolicy }
                    $others = @($allPolicies | Where-Object { $_.Policy -ne $currentPol } |
                              ForEach-Object { "$($_.Policy) ($($_.Side))" })
                    $tooltipText = if ($others.Count -gt 0) { "Also configured in: $($others -join ', ')" } else { 'Duplicate setting — see Duplicate Settings tab' }
                    $encTooltip  = [System.Net.WebUtility]::HtmlEncode($tooltipText)
                    $dupeBadge   = " <span class=`"badge-duplicate`" title=`"$encTooltip`">&#x26A0; Duplicate</span>"
                }

                # Setting name cell (per D-09 through D-11: bold name, deprecated badge, duplicate badge, path)
                $deprBadge = if ($row.IsDeprecated -eq $true) { ' <span class="badge-deprecated">&#x26A0; Deprecated</span>' } else { '' }
                $settingPath = "$($row.SettingPath)"
                # Strip the setting name from the end of the path (already shown above)
                $displayPath = $settingPath
                if (-not [string]::IsNullOrEmpty($settingPath) -and $settingPath.Contains(' > ')) {
                    $lastSep = $settingPath.LastIndexOf(' > ')
                    $lastSegment = $settingPath.Substring($lastSep + 3)
                    if ($lastSegment -eq $row.Name) {
                        $displayPath = $settingPath.Substring(0, $lastSep)
                    }
                }
                $encPath = [System.Net.WebUtility]::HtmlEncode($displayPath)
                $pathHtml = if (-not [string]::IsNullOrEmpty($displayPath) -and $displayPath -ne $row.Name) { "<span class=`"setting-path`">$encPath</span>" } else { '' }
                [void]$sb.Append("<td class=`"setting-name`"><strong>$encName</strong>$deprBadge$dupeBadge$pathHtml</td>")

                # Category column (already stripped of product prefix)
                [void]$sb.Append("<td style=`"font-size:0.75rem;color:var(--text-secondary)`">$encCategory</td>")

                # Source columns
                if ($status -eq 'DestOnly') {
                    [void]$sb.Append('<td colspan="2" style="color: var(--muted); font-style: italic;">Not configured</td>')
                } else {
                    $encSrcPolicy = [System.Net.WebUtility]::HtmlEncode($row.SourcePolicy)
                    $rawSrcValue  = if ($null -ne $row.SourceValue) { "$($row.SourceValue)" } else { '' }
                    $encSrcValue  = [System.Net.WebUtility]::HtmlEncode($rawSrcValue)
                    $encSrcValueAttr = [System.Net.WebUtility]::HtmlEncode($rawSrcValue)
                    [void]$sb.Append("<td>$encSrcPolicy</td>")
                    if ($rawSrcValue.Length -gt 100) {
                        [void]$sb.Append("<td class=`"value-cell`"><div class=`"value-wrap`"><div class=`"value-truncate`">$encSrcValue</div><div class=`"value-actions`"><button type=`"button`" class=`"value-toggle-btn`">&#9660; More</button><button type=`"button`" class=`"value-copy-btn`" data-value=`"$encSrcValueAttr`">&#128203; Copy</button></div></div></td>")
                    } else {
                        [void]$sb.Append("<td class=`"value-cell`"><div class=`"value-wrap`"><span class=`"value-text`">$encSrcValue</span><div class=`"value-actions`"><button type=`"button`" class=`"value-copy-btn`" data-value=`"$encSrcValueAttr`">&#128203; Copy</button></div></div></td>")
                    }
                }

                # Dest columns
                if ($status -eq 'SourceOnly') {
                    [void]$sb.Append('<td colspan="2" style="color: var(--muted); font-style: italic;">Not configured</td>')
                } else {
                    $encDstPolicy    = [System.Net.WebUtility]::HtmlEncode($row.DestPolicy)
                    $rawDstValue     = if ($null -ne $row.DestValue) { "$($row.DestValue)" } else { '' }
                    $encDstValue     = [System.Net.WebUtility]::HtmlEncode($rawDstValue)
                    $encDstValueAttr = [System.Net.WebUtility]::HtmlEncode($rawDstValue)
                    $innerCls = if ($status -eq 'Conflicting') { ' value-diff' } else { '' }
                    [void]$sb.Append("<td>$encDstPolicy</td>")
                    if ($rawDstValue.Length -gt 100) {
                        [void]$sb.Append("<td class=`"value-cell`"><div class=`"value-wrap`"><div class=`"value-truncate$innerCls`">$encDstValue</div><div class=`"value-actions`"><button type=`"button`" class=`"value-toggle-btn`">&#9660; More</button><button type=`"button`" class=`"value-copy-btn`" data-value=`"$encDstValueAttr`">&#128203; Copy</button></div></div></td>")
                    } else {
                        [void]$sb.Append("<td class=`"value-cell`"><div class=`"value-wrap`"><span class=`"value-text$innerCls`">$encDstValue</span><div class=`"value-actions`"><button type=`"button`" class=`"value-copy-btn`" data-value=`"$encDstValueAttr`">&#128203; Copy</button></div></div></td>")
                    }
                }

                # Assignment columns
                if ($inclAssignments) {
                    $srcAssignHtml = & $formatAssignHtml $row.SourceAssignment
                    $dstAssignHtml = & $formatAssignHtml $row.DestAssignment
                    [void]$sb.Append("<td class=`"value-cell col-assign`">$srcAssignHtml</td>")
                    [void]$sb.Append("<td class=`"value-cell col-assign`">$dstAssignHtml</td>")
                }

                [void]$sb.AppendLine('</tr>')
            }

        [void]$sb.AppendLine('        </tbody>')
        [void]$sb.AppendLine('    </table>')
        [void]$sb.AppendLine('    </div>')
    }

    [void]$sb.AppendLine('</div>')  # end tab-comparison

    # Deprecated policies are now in ManualReview with HasDeprecated flag — no separate tab

    # ── Manual Review tab ─────────────────────────────────────────────────
    if ($hasManualReview) {
        [void]$sb.AppendLine('<div class="tab-content" id="tab-manual-review">')
        [void]$sb.AppendLine('<div class="dup-info-banner" style="border-color:var(--info);border-left-color:var(--info);background:var(--info-bg)">')
        [void]$sb.AppendLine('    <span class="dup-banner-icon" style="color:var(--info)">&#x2139;</span>')
        [void]$sb.AppendLine('    <div>')
        [void]$sb.AppendLine('        <p class="dup-banner-title" style="color:var(--info)">Manual Review Required</p>')
        [void]$sb.AppendLine('        <p class="dup-banner-body">These policies contain scripts, compliance rules, or other configurations that cannot be compared automatically. Review each policy to verify both environments are aligned.</p>')
        [void]$sb.AppendLine('    </div>')
        [void]$sb.AppendLine('</div>')
        [void]$sb.AppendLine('<div style="display:flex;justify-content:flex-end;margin:0.25rem 0 0.5rem">')
        [void]$sb.AppendLine('    <button type="button" id="mr-expand-all-btn" onclick="toggleAllManualReview()" style="font-size:0.75rem;font-weight:600;padding:0.35rem 0.75rem;border:1px solid var(--border);border-radius:var(--radius-xs);background:var(--bg-card);color:var(--text-secondary);cursor:pointer;transition:all 0.15s ease">Expand All</button>')
        [void]$sb.AppendLine('</div>')

        # ── Render policy card helper (reused for source/dest columns) ──
        $renderPolicyCard = {
            param($policy, $sb)
            $encPolicyName = [System.Net.WebUtility]::HtmlEncode($policy.PolicyName)
            $encProfileType = [System.Net.WebUtility]::HtmlEncode($policy.ProfileType)

            $hasDepr = $policy.HasDeprecated -eq $true
            # Skip policies where ALL settings are deprecated (they're in the Deprecated tab)
            if ($hasDepr) {
                $nonDeprCount = @($policy.Settings | Where-Object { $_.IsDeprecated -ne $true }).Count
                if ($nonDeprCount -eq 0) { continue }
            }
            $deprBadge = ''
            [void]$sb.AppendLine('<details class="manual-review-card">')
            [void]$sb.AppendLine("    <summary><strong>$encPolicyName</strong>$deprBadge</summary>")
            [void]$sb.AppendLine('    <div class="mr-body">')
            if (-not [string]::IsNullOrWhiteSpace($encProfileType)) {
                [void]$sb.AppendLine("    <div style=`"font-size:0.75rem;color:var(--muted);margin-bottom:0.5rem`">$encProfileType</div>")
            }

            if ($policy.Settings.Count -gt 0) {
                foreach ($s in $policy.Settings) {
                    $encSName = [System.Net.WebUtility]::HtmlEncode($s.Name)
                    $isSettingDepr = $s.IsDeprecated -eq $true
                    # Skip deprecated settings — they have their own dedicated tab
                    if ($isSettingDepr) { continue }
                    # Priority 1: Duplicate table (D-08, D-09, D-10, D-11)
                    if ($s.Value -match '^__DUPLICATE_TABLE__') {
                        $dupJson = $s.Value.Substring('__DUPLICATE_TABLE__'.Length)
                        try {
                            $dupEntries = $dupJson | ConvertFrom-Json -ErrorAction Stop
                            $policyColumns = [ordered]@{}
                            foreach ($entry in $dupEntries) {
                                $colKey = "$($entry.Policy)|$($entry.Side)"
                                if (-not $policyColumns.Contains($colKey)) {
                                    $policyColumns[$colKey] = @{ Policy = $entry.Policy; Side = $entry.Side }
                                }
                            }
                            $uniqueValues = @($dupEntries | ForEach-Object { $_.Value } | Select-Object -Unique)
                            $hasConflict = $uniqueValues.Count -gt 1

                            [void]$sb.AppendLine('    <div style="margin:0.5rem 0"><strong style="font-size:0.8rem">Duplicate Settings</strong></div>')
                            [void]$sb.AppendLine('    <div class="dup-table-wrap"><table class="dup-table">')
                            $headerCells = '<th>Setting</th>'
                            foreach ($colKey in $policyColumns.Keys) {
                                $col = $policyColumns[$colKey]
                                $encPolicy = [System.Net.WebUtility]::HtmlEncode($col.Policy)
                                $colSideCls = if ($col.Side -eq 'Source') { 'side-source' } else { 'side-dest' }
                                $encSide = [System.Net.WebUtility]::HtmlEncode($col.Side)
                                $headerCells += "<th><span class=`"side-badge $colSideCls`">$encSide</span> $encPolicy</th>"
                            }
                            [void]$sb.AppendLine("    <thead><tr>$headerCells</tr></thead>")
                            $bodyCells = "<td class=`"dup-setting-name`">$encSName</td>"
                            foreach ($colKey in $policyColumns.Keys) {
                                $matchEntry = $dupEntries | Where-Object { "$($_.Policy)|$($_.Side)" -eq $colKey } | Select-Object -First 1
                                $cellValue = if ($null -ne $matchEntry) { [System.Net.WebUtility]::HtmlEncode($matchEntry.Value) } else { '&mdash;' }
                                $conflictCls = if ($hasConflict -and $null -ne $matchEntry) { ' class="dup-conflict"' } else { '' }
                                $bodyCells += "<td$conflictCls>$cellValue</td>"
                            }
                            [void]$sb.AppendLine("    <tbody><tr>$bodyCells</tr></tbody>")
                            [void]$sb.AppendLine('    </table></div>')
                        } catch {
                            $encSValue = [System.Net.WebUtility]::HtmlEncode($s.Value)
                            [void]$sb.AppendLine("    <div class=`"manual-review-setting`"><span class=`"setting-name`">$encSName</span><span class=`"setting-value`">$encSValue</span></div>")
                        }
                    }
                    # Priority 2: Compliance rules table (D-05, D-06, D-07)
                    elseif ($s.Name -match '(?i)^rules\s*content$') {
                        $rulesRendered = $false
                        try {
                            $parsed = $s.Value | ConvertFrom-Json -Depth 10 -ErrorAction Stop
                            $rules = if ($null -ne $parsed.Rules) { $parsed.Rules }
                                     elseif ($null -ne $parsed.rules) { $parsed.rules }
                                     elseif ($parsed -is [array]) { $parsed }
                                     else { $null }
                            if ($null -ne $rules -and @($rules).Count -gt 0) {
                                [void]$sb.AppendLine('    <div style="margin:0.5rem 0"><strong style="font-size:0.8rem">Compliance Rules</strong></div>')
                                [void]$sb.AppendLine('    <table class="compliance-table">')
                                [void]$sb.AppendLine('    <thead><tr><th>Setting</th><th>Operator</th><th>Type</th><th>Expected Value</th></tr></thead>')
                                [void]$sb.AppendLine('    <tbody>')
                                foreach ($rule in @($rules)) {
                                    $rName = [System.Net.WebUtility]::HtmlEncode(($rule.settingName, $rule.SettingName, '' | Where-Object { $_ } | Select-Object -First 1))
                                    $rOp   = [System.Net.WebUtility]::HtmlEncode(($rule.operator, $rule.Operator, '' | Where-Object { $_ } | Select-Object -First 1))
                                    $rType = [System.Net.WebUtility]::HtmlEncode(($rule.dataType, $rule.DataType, '' | Where-Object { $_ } | Select-Object -First 1))
                                    $rVal  = [System.Net.WebUtility]::HtmlEncode(($rule.operand, $rule.Operand, '' | Where-Object { $_ } | Select-Object -First 1))
                                    [void]$sb.AppendLine("    <tr><td>$rName</td><td>$rOp</td><td>$rType</td><td>$rVal</td></tr>")
                                }
                                [void]$sb.AppendLine('    </tbody></table>')
                                $rulesRendered = $true
                            }
                        } catch {
                            Write-Verbose "Failed to parse compliance rules JSON for '$($s.Name)': $_"
                        }
                        if (-not $rulesRendered) {
                            $encSValue = [System.Net.WebUtility]::HtmlEncode($s.Value)
                            [void]$sb.AppendLine("    <div class=`"manual-review-setting`"><span class=`"setting-name`">$encSName</span><span class=`"setting-value`">$encSValue</span></div>")
                        }
                    }
                    # Priority 3 & 4: Script content — bash (shebang) vs PowerShell (D-02, D-04, D-01)
                    elseif ($s.Name -match '(?i)script\s*content|detection\s*script\s*content|remediation\s*script\s*content|scriptContent|detectionScriptContent|remediationScriptContent' -and $s.Value.Length -gt 100) {
                        $encSValue = [System.Net.WebUtility]::HtmlEncode($s.Value)
                        $isBash = $s.Value.TrimStart() -match '^#!'
                        $preClass = if ($isBash) { 'sh-code' } else { 'ps-code' }
                        $langLabel = if ($isBash) { 'Bash' } else { 'PowerShell' }
                        [void]$sb.AppendLine("    <details class=`"script-collapsible`" style=`"margin:0.5rem 0`">")
                        [void]$sb.AppendLine("    <summary style=`"font-size:0.8rem;font-weight:600;cursor:pointer`">$encSName ($langLabel)</summary>")
                        [void]$sb.AppendLine("    <div class=`"ps-code-wrap`"><span class=`"code-lang-label`">$langLabel</span><pre class=`"$preClass`" style=`"background:var(--bg);border:1px solid var(--border);border-radius:var(--radius-xs);padding:0.75rem;font-size:0.75rem;overflow-x:auto;max-height:400px;overflow-y:auto;margin:0`"><code>$encSValue</code></pre></div>")
                        [void]$sb.AppendLine("    </details>")
                    }
                    # Priority 5: Linked compliance script (collapsible section with script content)
                    elseif ($s.Name -match '(?i)^linked\s*compliance\s*script$') {
                        try {
                            $scriptData = $s.Value | ConvertFrom-Json -Depth 5 -ErrorAction Stop
                            $encScriptName = [System.Net.WebUtility]::HtmlEncode($scriptData.scriptName)
                            [void]$sb.AppendLine("    <details class=`"script-collapsible`" style=`"margin:0.75rem 0`">")
                            [void]$sb.AppendLine("    <summary><strong style=`"font-size:0.8rem`">Linked Discovery Script: $encScriptName</strong></summary>")
                            [void]$sb.AppendLine("    <div style=`"padding:0.5rem 0`">")
                            # Show script metadata
                            foreach ($key in @('runAsAccount','enforceSignatureCheck','runAs32Bit','publisher')) {
                                $kval = $scriptData.$key
                                if ($null -ne $kval) {
                                    $encKey = [System.Net.WebUtility]::HtmlEncode((ConvertTo-FriendlySettingName -Name $key))
                                    $encVal = [System.Net.WebUtility]::HtmlEncode("$kval")
                                    [void]$sb.AppendLine("    <div class=`"manual-review-setting`"><span class=`"setting-name`">$encKey</span><span class=`"setting-value`">$encVal</span></div>")
                                }
                            }
                            # Show script content if present
                            $scriptContent = $scriptData.detectionScriptContent
                            if (-not $scriptContent) { $scriptContent = $scriptData.scriptContent }
                            if ($scriptContent -and $scriptContent.Length -gt 10) {
                                $encContent = [System.Net.WebUtility]::HtmlEncode($scriptContent)
                                $isBash = $scriptContent.TrimStart() -match '^#!'
                                $preClass = if ($isBash) { 'sh-code' } else { 'ps-code' }
                                $langLabel = if ($isBash) { 'Bash' } else { 'PowerShell' }
                                [void]$sb.AppendLine("    <details class=`"script-collapsible`" style=`"margin:0.5rem 0`">")
                                [void]$sb.AppendLine("    <summary style=`"font-size:0.8rem;font-weight:600;cursor:pointer`">Detection Script ($langLabel)</summary>")
                                [void]$sb.AppendLine("    <div class=`"ps-code-wrap`"><span class=`"code-lang-label`">$langLabel</span><pre class=`"$preClass`" style=`"background:var(--bg);border:1px solid var(--border);border-radius:var(--radius-xs);padding:0.75rem;font-size:0.75rem;overflow-x:auto;max-height:400px;overflow-y:auto;margin:0`"><code>$encContent</code></pre></div>")
                                [void]$sb.AppendLine("    </details>")
                            }
                            [void]$sb.AppendLine("    </div>")
                            [void]$sb.AppendLine("    </details>")
                        } catch {
                            # Fallback to default display
                            $encSValue = [System.Net.WebUtility]::HtmlEncode($s.Value)
                            [void]$sb.AppendLine("    <div class=`"manual-review-setting`"><span class=`"setting-name`">$encSName</span><span class=`"setting-value`">$encSValue</span></div>")
                        }
                    }
                    # Priority 6: Deprecated setting
                    elseif ($isSettingDepr) {
                        $encSValue = [System.Net.WebUtility]::HtmlEncode($s.Value)
                        [void]$sb.AppendLine("    <div class=`"manual-review-setting setting-deprecated`"><span class=`"setting-name`">&#x26A0; $encSName</span><span class=`"setting-value`">$encSValue</span></div>")
                    }
                    # Priority 7: Default key-value display (with boolean styling)
                    else {
                        $encSValue = [System.Net.WebUtility]::HtmlEncode($s.Value)
                        $valClass = 'setting-value'
                        $rawVal = "$($s.Value)".Trim()
                        if ($rawVal -eq 'True' -or $rawVal -eq 'true') { $valClass = 'setting-value val-true' }
                        elseif ($rawVal -eq 'False' -or $rawVal -eq 'false') { $valClass = 'setting-value val-false' }
                        [void]$sb.AppendLine("    <div class=`"manual-review-setting`"><span class=`"setting-name`">$encSName</span><span class=`"$valClass`">$encSValue</span></div>")
                    }
                }
            } else {
                [void]$sb.AppendLine('    <div style="color:var(--muted);font-size:0.8rem;font-style:italic">No configured settings</div>')
            }
            [void]$sb.AppendLine('    </div>')
            [void]$sb.AppendLine('</details>')
        }

        # ── Build platform-grouped structure ──
        $platformGroups = [ordered]@{}
        foreach ($catLabel in $manualReview.Keys) {
            if ($catLabel -eq 'Duplicate Settings (Different Values)') { continue }
            $segments = $catLabel -split '\s*/\s*'
            $platform = if ($segments.Count -ge 3) { $segments[1].Trim() } else { 'Other' }
            if ($platform -eq 'All') { $platform = 'Windows' }
            if (-not $platformGroups.Contains($platform)) {
                $platformGroups[$platform] = [ordered]@{}
            }
            $platformGroups[$platform][$catLabel] = $manualReview[$catLabel]
        }

        # ── Render platform sections with 50/50 source/dest split ──
        foreach ($platform in $platformGroups.Keys) {
            # Pre-count non-deprecated policies for this platform
            $platformVisibleCount = 0
            foreach ($catPols in $platformGroups[$platform].Values) {
                $platformVisibleCount += @($catPols | Where-Object {
                    if ($_.HasDeprecated -ne $true) { return $true }
                    return @($_.Settings | Where-Object { $_.IsDeprecated -ne $true }).Count -gt 0
                }).Count
            }
            if ($platformVisibleCount -eq 0) { continue }  # Skip empty platforms
            $encPlatform = [System.Net.WebUtility]::HtmlEncode($platform)
            [void]$sb.AppendLine("<details class=`"mr-platform-section`" open>")
            [void]$sb.AppendLine("    <summary><strong>$encPlatform</strong> <span class=`"status-badge`" style=`"font-size:0.7rem`">$platformVisibleCount</span></summary>")

            foreach ($catLabel in $platformGroups[$platform].Keys) {
                $allPolicies = $platformGroups[$platform][$catLabel]
                # Filter out deprecated-only policies (they have their own tab)
                $policies = @($allPolicies | Where-Object {
                    if ($_.HasDeprecated -ne $true) { return $true }
                    $nonDepr = @($_.Settings | Where-Object { $_.IsDeprecated -ne $true })
                    return $nonDepr.Count -gt 0
                })
                if ($policies.Count -eq 0) { continue }  # Skip empty categories
                $encCatLabel = [System.Net.WebUtility]::HtmlEncode((& $simplifyCategory $catLabel))
                $catPolicyCount = $policies.Count
                [void]$sb.AppendLine("<details class=`"mr-category-section`" open>")
                [void]$sb.AppendLine("<summary style=`"font-size:0.95rem;font-weight:600;margin:1rem 0 0.5rem;color:var(--text);cursor:pointer;list-style:none;display:flex;align-items:center;gap:0.5rem`"><span style=`"font-size:0.6rem;color:var(--muted);transition:transform 0.2s`" class=`"cat-chevron`">&#x25B6;</span>$encCatLabel <span class=`"status-badge`" style=`"font-size:0.65rem`">$catPolicyCount</span></summary>")

                $sourcePolicies = @($policies | Where-Object { $_.Side -eq 'Source' })
                $destPolicies = @($policies | Where-Object { $_.Side -eq 'Destination' })

                [void]$sb.AppendLine('<div class="mr-split">')
                [void]$sb.AppendLine('<div class="mr-split-col mr-col-source">')
                [void]$sb.AppendLine('<h4>Source</h4>')
                foreach ($policy in $sourcePolicies) {
                    & $renderPolicyCard $policy $sb
                }
                if ($sourcePolicies.Count -eq 0) {
                    [void]$sb.AppendLine('<div style="color:var(--muted);font-size:0.8rem;padding:0.5rem">No policies</div>')
                }
                [void]$sb.AppendLine('</div>')
                [void]$sb.AppendLine('<div class="mr-split-col mr-col-dest">')
                [void]$sb.AppendLine('<h4>Destination</h4>')
                foreach ($policy in $destPolicies) {
                    & $renderPolicyCard $policy $sb
                }
                if ($destPolicies.Count -eq 0) {
                    [void]$sb.AppendLine('<div style="color:var(--muted);font-size:0.8rem;padding:0.5rem">No policies</div>')
                }
                [void]$sb.AppendLine('</div>')
                [void]$sb.AppendLine('</div>')
                [void]$sb.AppendLine('</details>')  # end mr-category-section
            }
            [void]$sb.AppendLine('</details>')
        }

        [void]$sb.AppendLine('</div>')  # end tab-manual-review
    }

    # ── Duplicates tab content ──────────────────────────────────────────────
    if ($hasDuplicates) {
        # Count unique policy names across all duplicate rows
        $dupPolicyNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($dr in $dupRows) {
            foreach ($p in $dr.Policies) { [void]$dupPolicyNames.Add($p.Policy) }
        }
        $dupPolicyCount = $dupPolicyNames.Count

        [void]$sb.AppendLine('<div class="tab-content" id="tab-duplicates">')

        # Amber info banner (per D-03, UI-SPEC copywriting)
        [void]$sb.AppendLine('<div class="dup-info-banner">')
        [void]$sb.AppendLine('    <span class="dup-banner-icon">&#9888;</span>')
        [void]$sb.AppendLine('    <div>')
        [void]$sb.AppendLine('        <p class="dup-banner-title">Duplicate Settings Detected</p>')
        [void]$sb.AppendLine('        <p class="dup-banner-body">These settings appear in multiple policies with conflicting values. Review each entry to ensure your policies are aligned.</p>')
        [void]$sb.AppendLine('    </div>')
        [void]$sb.AppendLine('</div>')

        # Search bar (per D-10, using .search CSS class for consistent styling)
        [void]$sb.AppendLine('    <input class="search" type="text" placeholder="Search settings or policies..." oninput="dupTabSearch(this.value)" style="margin-bottom:0.75rem">')

        # Summary line (per D-12)
        [void]$sb.AppendLine("<div class=`"dup-summary`" id=`"dup-summary`">Showing <strong>$dupCount</strong> of <strong>$dupCount</strong> duplicate settings across <strong>$dupPolicyCount</strong> policies</div>")

        # No-results message
        [void]$sb.AppendLine('<div id="dup-no-results" class="dup-no-results">No duplicate settings match your search.</div>')

        # Three-column table (per D-04)
        [void]$sb.AppendLine('<div class="dup-table-scroll">')
        [void]$sb.AppendLine('<div class="dup-table-scroll-inner">')
        [void]$sb.AppendLine('<table class="dup-tab-table">')
        [void]$sb.AppendLine('<thead><tr><th>Setting</th><th>Policies &amp; Values</th><th>Analysis</th></tr></thead>')
        [void]$sb.AppendLine('<tbody id="dup-table-body">')

        foreach ($dupRow in $dupRows) {
            $encSettingName = [System.Net.WebUtility]::HtmlEncode($dupRow.Name)
            # data-policies attribute for text search (per D-11)
            $policiesText = ($dupRow.Policies | ForEach-Object { "$($_.Policy) $($_.Value)" }) -join ' '
            $encPoliciesAttr = [System.Net.WebUtility]::HtmlEncode($policiesText)
            # data-policies-json for analyzeDuplicate() — base64-encoded to avoid HTML parser issues with CDATA/angle brackets in values
            $policiesJson = ($dupRow.Policies | ConvertTo-Json -Depth 5 -Compress)
            $encPoliciesJson = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($policiesJson))

            [void]$sb.Append("<tr data-setting=`"$encSettingName`" data-policies=`"$encPoliciesAttr`" data-policies-json=`"$encPoliciesJson`">")

            # Column 1: Setting name + path below
            # Use SettingPath for both display name (last segment) and path (full path)
            $firstPolicy = $dupRow.Policies | Select-Object -First 1
            $settingPath = if ($firstPolicy.SettingPath) { $firstPolicy.SettingPath } else { '' }
            # Extract last segment of path as the display name (human-readable resolved name)
            if (-not [string]::IsNullOrEmpty($settingPath) -and $settingPath.Contains(' > ')) {
                $lastSep = $settingPath.LastIndexOf(' > ')
                $displayName = $settingPath.Substring($lastSep + 3)
            } else {
                $displayName = if (-not [string]::IsNullOrEmpty($settingPath)) { $settingPath }
                               elseif ($firstPolicy.SettingName) { $firstPolicy.SettingName }
                               else { $dupRow.Name }
            }
            $encDisplayName = [System.Net.WebUtility]::HtmlEncode($displayName)
            # Strip the display name from end of path to show only parent path
            $parentPath = $settingPath
            if (-not [string]::IsNullOrEmpty($settingPath) -and $settingPath.Contains(' > ')) {
                $lastSep2 = $settingPath.LastIndexOf(' > ')
                $lastSeg2 = $settingPath.Substring($lastSep2 + 3)
                if ($lastSeg2 -eq $displayName) {
                    $parentPath = $settingPath.Substring(0, $lastSep2)
                }
            }
            $encPath = [System.Net.WebUtility]::HtmlEncode($parentPath)
            $pathLine = if (-not [string]::IsNullOrEmpty($parentPath) -and $parentPath -ne $displayName) {
                "<span class=`"dup-setting-path`">$encPath</span>"
            } else { '' }
            [void]$sb.Append("<td class=`"dup-tab-setting`"><strong>$encDisplayName</strong>$pathLine</td>")

            # Column 2: Policies & Values (per D-05)
            [void]$sb.Append('<td class="dup-tab-policies">')
            foreach ($p in $dupRow.Policies) {
                $encPol = [System.Net.WebUtility]::HtmlEncode($p.Policy)
                $rawVal = "$($p.Value)"
                $encVal = if ([string]::IsNullOrWhiteSpace($rawVal)) {
                    '<span style="color:var(--muted);font-style:italic">Not configured</span>'
                } else {
                    [System.Net.WebUtility]::HtmlEncode($rawVal)
                }
                $sideCls = if ($p.Side -eq 'Source') { 'side-source' } else { 'side-dest' }
                $sideLabel = [System.Net.WebUtility]::HtmlEncode($p.Side)
                [void]$sb.Append('<div class="dup-policy-entry">')
                [void]$sb.Append("<div><strong>$encPol</strong> <span class=`"side-badge $sideCls`">$sideLabel</span></div>")
                [void]$sb.Append("<div class=`"dup-policy-value`">$encVal</div>")
                [void]$sb.Append('</div>')
            }
            [void]$sb.Append('</td>')

            # Column 3: Analysis — populated by JS on DOMContentLoaded (per D-07)
            [void]$sb.Append('<td class="dup-tab-analysis-col"><p class="dup-analysis-text"></p></td>')
            [void]$sb.AppendLine('</tr>')
        }

        [void]$sb.AppendLine('</tbody></table>')
        [void]$sb.AppendLine('</div></div>')  # close dup-table-scroll-inner and dup-table-scroll

        [void]$sb.AppendLine('</div>')  # end tab-duplicates
    }

    # ── Deprecated tab content ────────────────────────────────────────────
    if ($hasDeprecated) {
        [void]$sb.AppendLine('<div class="tab-content" id="tab-deprecated">')
        [void]$sb.AppendLine('<div class="dup-info-banner" style="border-color:var(--danger);border-left-color:var(--danger);background:var(--danger-bg)">')
        [void]$sb.AppendLine('    <span class="dup-banner-icon" style="color:var(--danger)">&#x26A0;</span>')
        [void]$sb.AppendLine('    <div>')
        [void]$sb.AppendLine('        <p class="dup-banner-title" style="color:var(--danger)">Deprecated Settings Detected</p>')
        [void]$sb.AppendLine('        <p class="dup-banner-body">These settings are deprecated by Microsoft and may stop working in a future update, or have already been replaced by a newer alternative. Review each setting and migrate to the recommended replacement to avoid unexpected behavior or policy enforcement failures.</p>')
        [void]$sb.AppendLine('    </div>')
        [void]$sb.AppendLine('</div>')
        # Group deprecated by policy+side for 50/50 layout
        $deprByPolicy = [ordered]@{}
        foreach ($entry in $deprecatedRows) {
            $row = $entry.Row
            $srcPol = $row.SourcePolicy
            $dstPol = $row.DestPolicy
            if (-not [string]::IsNullOrWhiteSpace($srcPol)) {
                $key = "Source|$srcPol"
                if (-not $deprByPolicy.Contains($key)) { $deprByPolicy[$key] = @{ Side = 'Source'; Policy = $srcPol; Settings = [System.Collections.Generic.List[object]]::new() } }
                [void]$deprByPolicy[$key].Settings.Add($entry)
            }
            if (-not [string]::IsNullOrWhiteSpace($dstPol)) {
                $key = "Destination|$dstPol"
                if (-not $deprByPolicy.Contains($key)) { $deprByPolicy[$key] = @{ Side = 'Destination'; Policy = $dstPol; Settings = [System.Collections.Generic.List[object]]::new() } }
                [void]$deprByPolicy[$key].Settings.Add($entry)
            }
        }
        $deprSource = @($deprByPolicy.Values | Where-Object { $_.Side -eq 'Source' })
        $deprDest = @($deprByPolicy.Values | Where-Object { $_.Side -eq 'Destination' })
        [void]$sb.AppendLine('<div class="mr-split">')
        # Source column
        [void]$sb.AppendLine('<div class="mr-split-col mr-col-source">')
        [void]$sb.AppendLine("<h4>$sourceName</h4>")
        foreach ($group in $deprSource) {
            $encPol = [System.Net.WebUtility]::HtmlEncode($group.Policy)
            [void]$sb.AppendLine("<details class=`"manual-review-card`" open>")
            [void]$sb.AppendLine("    <summary><strong>$encPol</strong> <span class=`"status-badge`" style=`"font-size:0.65rem`">$($group.Settings.Count)</span></summary>")
            [void]$sb.AppendLine('    <div class="mr-body">')
            foreach ($entry in $group.Settings) {
                $row = $entry.Row
                $encName = [System.Net.WebUtility]::HtmlEncode($row.Name)
                $settingPath = "$($row.SettingPath)"
                $displayPath = $settingPath
                if (-not [string]::IsNullOrEmpty($settingPath) -and $settingPath.Contains(' > ')) {
                    $lastSep = $settingPath.LastIndexOf(' > ')
                    if ($settingPath.Substring($lastSep + 3) -eq $row.Name) { $displayPath = $settingPath.Substring(0, $lastSep) }
                }
                $encPath = [System.Net.WebUtility]::HtmlEncode($displayPath)
                $pathHtml = if (-not [string]::IsNullOrEmpty($displayPath) -and $displayPath -ne $row.Name) { "<span class=`"setting-path`">$encPath</span>" } else { '' }
                [void]$sb.AppendLine("    <div class=`"manual-review-setting`"><span class=`"setting-name`"><strong>$encName</strong>$pathHtml</span></div>")
            }
            [void]$sb.AppendLine('    </div>')
            [void]$sb.AppendLine('</details>')
        }
        if ($deprSource.Count -eq 0) { [void]$sb.AppendLine('<div style="color:var(--muted);font-size:0.8rem;padding:0.5rem">No deprecated settings</div>') }
        [void]$sb.AppendLine('</div>')
        # Destination column
        [void]$sb.AppendLine('<div class="mr-split-col mr-col-dest">')
        [void]$sb.AppendLine("<h4>$destName</h4>")
        foreach ($group in $deprDest) {
            $encPol = [System.Net.WebUtility]::HtmlEncode($group.Policy)
            [void]$sb.AppendLine("<details class=`"manual-review-card`" open>")
            [void]$sb.AppendLine("    <summary><strong>$encPol</strong> <span class=`"status-badge`" style=`"font-size:0.65rem`">$($group.Settings.Count)</span></summary>")
            [void]$sb.AppendLine('    <div class="mr-body">')
            foreach ($entry in $group.Settings) {
                $row = $entry.Row
                $encName = [System.Net.WebUtility]::HtmlEncode($row.Name)
                $settingPath = "$($row.SettingPath)"
                $displayPath = $settingPath
                if (-not [string]::IsNullOrEmpty($settingPath) -and $settingPath.Contains(' > ')) {
                    $lastSep = $settingPath.LastIndexOf(' > ')
                    if ($settingPath.Substring($lastSep + 3) -eq $row.Name) { $displayPath = $settingPath.Substring(0, $lastSep) }
                }
                $encPath = [System.Net.WebUtility]::HtmlEncode($displayPath)
                $pathHtml = if (-not [string]::IsNullOrEmpty($displayPath) -and $displayPath -ne $row.Name) { "<span class=`"setting-path`">$encPath</span>" } else { '' }
                [void]$sb.AppendLine("    <div class=`"manual-review-setting`"><span class=`"setting-name`"><strong>$encName</strong>$pathHtml</span></div>")
            }
            [void]$sb.AppendLine('    </div>')
            [void]$sb.AppendLine('</details>')
        }
        if ($deprDest.Count -eq 0) { [void]$sb.AppendLine('<div style="color:var(--muted);font-size:0.8rem;padding:0.5rem">No deprecated settings</div>') }
        [void]$sb.AppendLine('</div>')
        [void]$sb.AppendLine('</div>')  # end mr-split
        [void]$sb.AppendLine('</div>')  # end tab-deprecated
    }

    # ── Footer ─────────────────────────────────────────────────────────────
    [void]$sb.AppendLine('<div class="footer">')
    [void]$sb.AppendLine('    InforcerCommunity Module &middot; Created by Roy Klooster')
    [void]$sb.AppendLine('</div>')

    # ── Theme toggle (top-right) ────────────────────────────────────────────
    [void]$sb.AppendLine('<button class="theme-toggle" id="btn-theme" onclick="toggleTheme()" aria-label="Toggle dark/light mode">')
    [void]$sb.AppendLine('    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="5"/><line x1="12" y1="1" x2="12" y2="3"/><line x1="12" y1="21" x2="12" y2="23"/><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/><line x1="1" y1="12" x2="3" y2="12"/><line x1="21" y1="12" x2="23" y2="12"/><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/></svg>')
    [void]$sb.AppendLine('</button>')

    # ── Floating buttons ───────────────────────────────────────────────────
    [void]$sb.AppendLine('<div class="fab-group">')
    [void]$sb.AppendLine('    <button class="fab fab-top" id="btn-top" onclick="scrollToTop()" aria-label="Back to top">')
    [void]$sb.AppendLine('        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M18 15l-6-6-6 6"/></svg>')
    [void]$sb.AppendLine('    </button>')
    [void]$sb.AppendLine('</div>')

    # ── JavaScript ─────────────────────────────────────────────────────────
    [void]$sb.AppendLine('<script>')
    [void]$sb.AppendLine('function barColor(pct) {')
    [void]$sb.AppendLine('    if (pct < 10) return "#7f1d1d";')
    [void]$sb.AppendLine('    if (pct < 20) return "#dc2626";')
    [void]$sb.AppendLine('    if (pct < 30) return "#ef4444";')
    [void]$sb.AppendLine('    if (pct < 40) return "#f97316";')
    [void]$sb.AppendLine('    if (pct < 50) return "#d97706";')
    [void]$sb.AppendLine('    if (pct < 60) return "#eab308";')
    [void]$sb.AppendLine('    if (pct < 70) return "#ca8a04";')
    [void]$sb.AppendLine('    if (pct < 80) return "#65a30d";')
    [void]$sb.AppendLine('    if (pct < 90) return "#16a34a";')
    [void]$sb.AppendLine('    return "#059669";')
    [void]$sb.AppendLine('}')
    [void]$sb.AppendLine('var _scoreAnim = null;')
    [void]$sb.AppendLine('function updateScore(matched, conflicting, source, dest) {')
    [void]$sb.AppendLine('    var total = matched + conflicting + source + dest;')
    [void]$sb.AppendLine('    var targetPct = total > 0 ? Math.round((matched / total) * 1000) / 10 : 0;')
    [void]$sb.AppendLine('    var elScore = document.getElementById(''scoreNum'');')
    [void]$sb.AppendLine('    var elBar = document.getElementById(''scoreBar'');')
    [void]$sb.AppendLine('    var elDetail = document.getElementById(''scoreDetail'');')
    [void]$sb.AppendLine('    // Bar uses CSS transition (smooth via .score-bar-fill class)')
    [void]$sb.AppendLine('    if (elBar) { elBar.style.width = targetPct + ''%''; elBar.style.backgroundColor = barColor(targetPct); }')
    [void]$sb.AppendLine('    if (elDetail) elDetail.textContent = matched + '' of '' + total + '' settings matched'';')
    [void]$sb.AppendLine('    // Animate score number smoothly')
    [void]$sb.AppendLine('    if (_scoreAnim) cancelAnimationFrame(_scoreAnim);')
    [void]$sb.AppendLine('    var currentPct = parseFloat(elScore ? elScore.textContent : ''0'') || 0;')
    [void]$sb.AppendLine('    var startTime = null;')
    [void]$sb.AppendLine('    var duration = 400;')
    [void]$sb.AppendLine('    function animateNum(ts) {')
    [void]$sb.AppendLine('        if (!startTime) startTime = ts;')
    [void]$sb.AppendLine('        var progress = Math.min((ts - startTime) / duration, 1);')
    [void]$sb.AppendLine('        var ease = progress < 0.5 ? 2*progress*progress : -1+(4-2*progress)*progress;')
    [void]$sb.AppendLine('        var val = currentPct + (targetPct - currentPct) * ease;')
    [void]$sb.AppendLine('        if (elScore) elScore.textContent = (Math.round(val * 10) / 10) + ''%'';')
    [void]$sb.AppendLine('        if (progress < 1) { _scoreAnim = requestAnimationFrame(animateNum); }')
    [void]$sb.AppendLine('        else { if (elScore) elScore.textContent = targetPct + ''%''; _scoreAnim = null; }')
    [void]$sb.AppendLine('    }')
    [void]$sb.AppendLine('    _scoreAnim = requestAnimationFrame(animateNum);')
    [void]$sb.AppendLine('    var em = document.getElementById(''countMatched'');')
    [void]$sb.AppendLine('    var ec = document.getElementById(''countConflicting'');')
    [void]$sb.AppendLine('    var es = document.getElementById(''countSource'');')
    [void]$sb.AppendLine('    var ed = document.getElementById(''countDest'');')
    [void]$sb.AppendLine('    if (em) em.textContent = matched;')
    [void]$sb.AppendLine('    if (ec) ec.textContent = conflicting;')
    [void]$sb.AppendLine('    if (es) es.textContent = source;')
    [void]$sb.AppendLine('    if (ed) ed.textContent = dest;')
    [void]$sb.AppendLine('}')
    [void]$sb.AppendLine('(function() {')
    [void]$sb.AppendLine("    var TARGET = $alignmentScore;")
    [void]$sb.AppendLine("    var MATCHED = $matched, CONFLICTING = $conflicting, SOURCE = $sourceOnly, DEST = $destOnly;")
    [void]$sb.AppendLine("    var TOTAL = $totalItems;")
    [void]$sb.AppendLine('    var DURATION = 1500, INTERVAL = 16;')
    [void]$sb.AppendLine('    var steps = Math.ceil(DURATION / INTERVAL), step = 0;')
    [void]$sb.AppendLine('    var elScore = document.getElementById(''scoreNum'');')
    [void]$sb.AppendLine('    var elBar = document.getElementById(''scoreBar'');')
    [void]$sb.AppendLine('    var elDetail = document.getElementById(''scoreDetail'');')
    [void]$sb.AppendLine('    var elMatched = document.getElementById(''countMatched'');')
    [void]$sb.AppendLine('    var elConflicting = document.getElementById(''countConflicting'');')
    [void]$sb.AppendLine('    var elSource = document.getElementById(''countSource'');')
    [void]$sb.AppendLine('    var elDest = document.getElementById(''countDest'');')
    [void]$sb.AppendLine('    function ease(t) { return t < 0.5 ? 2*t*t : -1+(4-2*t)*t; }')
    [void]$sb.AppendLine('    elBar.style.backgroundColor = "#dc2626";')
    [void]$sb.AppendLine('    elBar.style.transition = "none";')  # Disable CSS transition during initial animation
    [void]$sb.AppendLine('    setTimeout(function() {')
    [void]$sb.AppendLine('        var timer = setInterval(function() {')
    [void]$sb.AppendLine('            step++;')
    [void]$sb.AppendLine('            var progress = ease(Math.min(step / steps, 1));')
    [void]$sb.AppendLine('            var pct = TARGET * progress;')
    [void]$sb.AppendLine('            elScore.textContent = Math.round(pct * 10) / 10 + ''%'';')
    [void]$sb.AppendLine('            elBar.style.width = pct + ''%'';')
    [void]$sb.AppendLine('            elBar.style.backgroundColor = barColor(pct);')
    [void]$sb.AppendLine('            elDetail.textContent = Math.round(MATCHED * progress) + '' of '' + TOTAL + '' settings matched'';')
    [void]$sb.AppendLine('            elMatched.textContent = Math.round(MATCHED * progress);')
    [void]$sb.AppendLine('            elConflicting.textContent = Math.round(CONFLICTING * progress);')
    [void]$sb.AppendLine('            elSource.textContent = Math.round(SOURCE * progress);')
    [void]$sb.AppendLine('            elDest.textContent = Math.round(DEST * progress);')
    [void]$sb.AppendLine('            if (step >= steps) {')
    [void]$sb.AppendLine('                clearInterval(timer);')
    [void]$sb.AppendLine('                elScore.textContent = TARGET + ''%'';')
    [void]$sb.AppendLine('                elBar.style.width = TARGET + ''%'';')
    [void]$sb.AppendLine('                elBar.style.backgroundColor = barColor(TARGET);')
    [void]$sb.AppendLine('                elDetail.textContent = MATCHED + '' of '' + TOTAL + '' settings matched'';')
    [void]$sb.AppendLine('                elMatched.textContent = MATCHED;')
    [void]$sb.AppendLine('                elConflicting.textContent = CONFLICTING;')
    [void]$sb.AppendLine('                elSource.textContent = SOURCE;')
    [void]$sb.AppendLine('                elDest.textContent = DEST;')
    [void]$sb.AppendLine('                if (TARGET === 100) { fireConfetti(); }')
    [void]$sb.AppendLine('                elBar.style.transition = "";')  # Re-enable CSS transition for filter updates
    [void]$sb.AppendLine('            }')
    [void]$sb.AppendLine('        }, INTERVAL);')
    [void]$sb.AppendLine('    }, 300);')
    [void]$sb.AppendLine('})();')
    [void]$sb.AppendLine('function fireConfetti() {')
    [void]$sb.AppendLine('    var colors = ["#059669","#34d399","#fbbf24","#3b82f6","#8b5cf6","#ec4899","#f97316","#06b6d4","#10b981","#a855f7"];')
    [void]$sb.AppendLine('    var canvas = document.createElement("canvas");')
    [void]$sb.AppendLine('    canvas.style.cssText = "position:fixed;top:0;left:0;width:100%;height:100%;pointer-events:none;z-index:9999";')
    [void]$sb.AppendLine('    canvas.width = window.innerWidth; canvas.height = window.innerHeight;')
    [void]$sb.AppendLine('    document.body.appendChild(canvas);')
    [void]$sb.AppendLine('    var ctx = canvas.getContext("2d");')
    [void]$sb.AppendLine('    var pieces = [];')
    [void]$sb.AppendLine('    for (var i = 0; i < 300; i++) {')
    [void]$sb.AppendLine('        var side = i < 150 ? 0 : 1;')
    [void]$sb.AppendLine('        pieces.push({')
    [void]$sb.AppendLine('            x: side === 0 ? -10 : canvas.width + 10,')
    [void]$sb.AppendLine('            y: canvas.height * (0.3 + Math.random() * 0.4),')
    [void]$sb.AppendLine('            vx: (side === 0 ? 1 : -1) * (Math.random() * 18 + 4),')
    [void]$sb.AppendLine('            vy: -(Math.random() * 22 + 5),')
    [void]$sb.AppendLine('            color: colors[Math.floor(Math.random() * colors.length)],')
    [void]$sb.AppendLine('            size: Math.random() * 10 + 4,')
    [void]$sb.AppendLine('            rotation: Math.random() * 360,')
    [void]$sb.AppendLine('            rotSpeed: (Math.random() - 0.5) * 20,')
    [void]$sb.AppendLine('            gravity: 0.35,')
    [void]$sb.AppendLine('            opacity: 1,')
    [void]$sb.AppendLine('            shape: ["rect","circle","star"][Math.floor(Math.random()*3)]')
    [void]$sb.AppendLine('        });')
    [void]$sb.AppendLine('    }')
    [void]$sb.AppendLine('    // APPROVED stamp')
    [void]$sb.AppendLine('    var stamp = document.createElement("div");')
    [void]$sb.AppendLine('    stamp.textContent = "APPROVED!";')
    [void]$sb.AppendLine('    stamp.style.cssText = "position:fixed;top:50%;left:50%;transform:translate(-50%,-50%) rotate(-12deg) scale(0);font-size:6rem;font-weight:900;color:#059669;text-shadow:0 0 40px rgba(5,150,105,0.4);letter-spacing:0.1em;z-index:10000;pointer-events:none;opacity:0;transition:transform 0.5s cubic-bezier(0.175,0.885,0.32,1.275),opacity 0.5s ease;font-family:Impact,sans-serif;border:8px solid #059669;border-radius:16px;padding:0.2em 0.6em;";')
    [void]$sb.AppendLine('    document.body.appendChild(stamp);')
    [void]$sb.AppendLine('    setTimeout(function() { stamp.style.transform = "translate(-50%,-50%) rotate(-12deg) scale(1)"; stamp.style.opacity = "0.9"; }, 100);')
    [void]$sb.AppendLine('    setTimeout(function() { stamp.style.opacity = "0"; setTimeout(function() { stamp.remove(); }, 600); }, 3000);')
    [void]$sb.AppendLine('    function draw() {')
    [void]$sb.AppendLine('        ctx.clearRect(0, 0, canvas.width, canvas.height);')
    [void]$sb.AppendLine('        var alive = false;')
    [void]$sb.AppendLine('        pieces.forEach(function(p) {')
    [void]$sb.AppendLine('            p.vy += p.gravity;')
    [void]$sb.AppendLine('            p.x += p.vx;')
    [void]$sb.AppendLine('            p.y += p.vy;')
    [void]$sb.AppendLine('            p.rotation += p.rotSpeed;')
    [void]$sb.AppendLine('            p.vx *= 0.985;')
    [void]$sb.AppendLine('            if (p.y > canvas.height * 0.75) p.opacity -= 0.015;')
    [void]$sb.AppendLine('            if (p.opacity <= 0) return;')
    [void]$sb.AppendLine('            alive = true;')
    [void]$sb.AppendLine('            ctx.save();')
    [void]$sb.AppendLine('            ctx.globalAlpha = Math.max(0, p.opacity);')
    [void]$sb.AppendLine('            ctx.translate(p.x, p.y);')
    [void]$sb.AppendLine('            ctx.rotate(p.rotation * Math.PI / 180);')
    [void]$sb.AppendLine('            ctx.fillStyle = p.color;')
    [void]$sb.AppendLine('            if (p.shape === "rect") { ctx.fillRect(-p.size/2, -p.size/3, p.size, p.size*0.6); }')
    [void]$sb.AppendLine('            else if (p.shape === "circle") { ctx.beginPath(); ctx.arc(0, 0, p.size/2, 0, Math.PI*2); ctx.fill(); }')
    [void]$sb.AppendLine('            else { ctx.beginPath(); for(var s=0;s<5;s++){ctx.lineTo(Math.cos((s*4*Math.PI/5)-Math.PI/2)*p.size/2,Math.sin((s*4*Math.PI/5)-Math.PI/2)*p.size/2);} ctx.closePath(); ctx.fill(); }')
    [void]$sb.AppendLine('            ctx.restore();')
    [void]$sb.AppendLine('        });')
    [void]$sb.AppendLine('        if (alive) requestAnimationFrame(draw);')
    [void]$sb.AppendLine('        else { canvas.remove(); }')
    [void]$sb.AppendLine('    }')
    [void]$sb.AppendLine('    requestAnimationFrame(draw);')
    [void]$sb.AppendLine('}')
    [void]$sb.AppendLine('function scrollToTop() { document.getElementById(''top'').scrollIntoView({ behavior: ''smooth'' }); }')
    [void]$sb.AppendLine('window.addEventListener(''scroll'', function() {')
    [void]$sb.AppendLine('    var btn = document.getElementById(''btn-top'');')
    [void]$sb.AppendLine('    if (window.scrollY > 300) { btn.classList.add(''visible''); } else { btn.classList.remove(''visible''); }')
    [void]$sb.AppendLine('});')
    [void]$sb.AppendLine('function toggleTheme() {')
    [void]$sb.AppendLine('    var r = document.documentElement;')
    [void]$sb.AppendLine('    if (r.classList.contains(''dark'')) { r.classList.remove(''dark''); r.classList.add(''light''); localStorage.setItem(''theme'',''light''); }')
    [void]$sb.AppendLine('    else { r.classList.remove(''light''); r.classList.add(''dark''); localStorage.setItem(''theme'',''dark''); }')
    [void]$sb.AppendLine('}')
    [void]$sb.AppendLine('(function() { var s = localStorage.getItem(''theme''); if (s===''dark'') document.documentElement.classList.add(''dark''); else if (s===''light'') document.documentElement.classList.add(''light''); })();')
    [void]$sb.AppendLine('function toggleCatDropdown() { var dd = document.getElementById("cat-ms-dropdown"); dd.classList.toggle("open"); }')
    [void]$sb.AppendLine('function filterCatDropdown(q) {')
    [void]$sb.AppendLine('    q = q.toLowerCase();')
    [void]$sb.AppendLine('    var dd = document.getElementById("cat-ms-dropdown");')
    [void]$sb.AppendLine('    dd.querySelectorAll("label").forEach(function(lbl) {')
    [void]$sb.AppendLine('        lbl.style.display = lbl.textContent.toLowerCase().indexOf(q) >= 0 ? "" : "none";')
    [void]$sb.AppendLine('    });')
    [void]$sb.AppendLine('}')
    [void]$sb.AppendLine('document.addEventListener("click", function(e) { var wrap = document.getElementById("cat-multiselect"); if (wrap && !wrap.contains(e.target)) { document.getElementById("cat-ms-dropdown").classList.remove("open"); } });')
    [void]$sb.AppendLine('var activeFilters = new Set();')
    [void]$sb.AppendLine('function evaluateChip(chip, tr) {')
    [void]$sb.AppendLine('    var col = parseInt(chip.getAttribute("data-col"), 10);')
    [void]$sb.AppendLine('    var cells = tr.querySelectorAll("td");')
    [void]$sb.AppendLine('    var colsToCheck = [col];')
    [void]$sb.AppendLine('    if (col === 3) colsToCheck.push(5);')
    [void]$sb.AppendLine('    if (col === 4) colsToCheck.push(6);')
    [void]$sb.AppendLine('    if (col === 7) colsToCheck.push(8);')
    [void]$sb.AppendLine('    var dtype = chip.getAttribute("data-type");')
    [void]$sb.AppendLine('    if (dtype === "dropdown") {')
    [void]$sb.AppendLine('        var checked = [];')
    [void]$sb.AppendLine('        chip.querySelectorAll(".adv-dropdown-menu input[type=checkbox]:checked").forEach(function(cb) { checked.push(cb.value.toLowerCase()); });')
    [void]$sb.AppendLine('        if (checked.length === 0) return true;')
    [void]$sb.AppendLine('        var found = false;')
    [void]$sb.AppendLine('        colsToCheck.forEach(function(c) {')
    [void]$sb.AppendLine('            var cellText = cells[c] ? cells[c].textContent.toLowerCase() : "";')
    [void]$sb.AppendLine('            checked.forEach(function(v) { if (cellText.indexOf(v) >= 0) found = true; });')
    [void]$sb.AppendLine('        });')
    [void]$sb.AppendLine('        return found;')
    [void]$sb.AppendLine('    }')
    [void]$sb.AppendLine('    var tagWrap = chip.querySelector(".tag-input-wrap");')
    [void]$sb.AppendLine('    if (tagWrap) {')
    [void]$sb.AppendLine('        var tags = tagWrap.querySelectorAll(".tag");')
    [void]$sb.AppendLine('        var inp = tagWrap.querySelector("input");')
    [void]$sb.AppendLine('        var vals = [];')
    [void]$sb.AppendLine('        tags.forEach(function(t) { vals.push(t.getAttribute("data-value").toLowerCase()); });')
    [void]$sb.AppendLine('        if (inp && inp.value.trim()) vals.push(inp.value.trim().toLowerCase());')
    [void]$sb.AppendLine('        if (vals.length === 0) return true;')
    [void]$sb.AppendLine('        var found = false;')
    [void]$sb.AppendLine('        colsToCheck.forEach(function(c) {')
    [void]$sb.AppendLine('            var cellText = cells[c] ? cells[c].textContent.toLowerCase() : "";')
    [void]$sb.AppendLine('            vals.forEach(function(v) { if (cellText.indexOf(v) >= 0) found = true; });')
    [void]$sb.AppendLine('        });')
    [void]$sb.AppendLine('        return found;')
    [void]$sb.AppendLine('    }')
    [void]$sb.AppendLine('    var rawVal = chip.querySelector("input") ? chip.querySelector("input").value.toLowerCase().trim() : "";')
    [void]$sb.AppendLine('    if (!rawVal) return true;')
    [void]$sb.AppendLine('    var vals2 = rawVal.split(",").map(function(v) { return v.trim(); }).filter(function(v) { return v; });')
    [void]$sb.AppendLine('    if (vals2.length === 0) return true;')
    [void]$sb.AppendLine('    var found2 = false;')
    [void]$sb.AppendLine('    colsToCheck.forEach(function(c) {')
    [void]$sb.AppendLine('        var cellText = cells[c] ? cells[c].textContent.toLowerCase() : "";')
    [void]$sb.AppendLine('        vals2.forEach(function(v) { if (cellText.indexOf(v) >= 0) found2 = true; });')
    [void]$sb.AppendLine('    });')
    [void]$sb.AppendLine('    return found2;')
    [void]$sb.AppendLine('}')
    [void]$sb.AppendLine('function applyFilters() {')
    [void]$sb.AppendLine('    var q = (document.getElementById("search-input").value || "").toLowerCase().trim();')
    [void]$sb.AppendLine('    var showAll = activeFilters.size === 0;')
    [void]$sb.AppendLine('    // Deprecated settings are in their own tab — no toggle logic needed')
    [void]$sb.AppendLine('    var catChecked = [];')
    [void]$sb.AppendLine('    var catWrap = document.getElementById("cat-multiselect");')
    [void]$sb.AppendLine('    if (catWrap) { catWrap.querySelectorAll("input[type=checkbox]:checked").forEach(function(cb) { catChecked.push(cb.value); }); }')
    [void]$sb.AppendLine('    var filterByCategory = catChecked.length > 0;')
    [void]$sb.AppendLine('    var excludeUnassigned = false;')
    [void]$sb.AppendLine('    var euToggle = document.getElementById("toggle-exclude-unassigned");')
    [void]$sb.AppendLine('    if (euToggle) excludeUnassigned = euToggle.checked;')
    [void]$sb.AppendLine('    var tab = document.getElementById("tab-comparison");')
    [void]$sb.AppendLine('    if (!tab) return;')
    [void]$sb.AppendLine('    // Filter individual rows by search + status + category + deprecated')
    [void]$sb.AppendLine('    tab.querySelectorAll("tbody tr[data-status]").forEach(function(tr) {')
    [void]$sb.AppendLine('        var matchesSearch = !q || tr.textContent.toLowerCase().indexOf(q) >= 0;')
    [void]$sb.AppendLine('        var matchesFilter = showAll || activeFilters.has(tr.getAttribute("data-status"));')
    [void]$sb.AppendLine('        var matchesCategory = !filterByCategory || catChecked.indexOf(tr.getAttribute("data-category")) >= 0;')
    [void]$sb.AppendLine('        var matchesAssigned = true;')
    [void]$sb.AppendLine('        if (excludeUnassigned) {')
    [void]$sb.AppendLine('            var cells = tr.querySelectorAll("td.col-assign");')
    [void]$sb.AppendLine('            if (cells.length === 2) {')
    [void]$sb.AppendLine('                var bothEmpty = true;')
    [void]$sb.AppendLine('                cells.forEach(function(c) { if (!c.querySelector(".assign-empty")) bothEmpty = false; });')
    [void]$sb.AppendLine('                if (bothEmpty) matchesAssigned = false;')
    [void]$sb.AppendLine('            }')
    [void]$sb.AppendLine('        }')
    [void]$sb.AppendLine('        var advChips = Array.from(document.querySelectorAll("#active-adv-filters .adv-chip"));')
    [void]$sb.AppendLine('        var matchesAdv = true;')
    [void]$sb.AppendLine('        if (advChips.length > 0) {')
    [void]$sb.AppendLine('            matchesAdv = evaluateChip(advChips[0], tr);')
    [void]$sb.AppendLine('            for (var ci = 1; ci < advChips.length; ci++) {')
    [void]$sb.AppendLine('                var connector = advChips[ci].previousElementSibling;')
    [void]$sb.AppendLine('                var isOr = connector && connector.textContent === "OR";')
    [void]$sb.AppendLine('                var chipResult = evaluateChip(advChips[ci], tr);')
    [void]$sb.AppendLine('                if (isOr) { matchesAdv = matchesAdv || chipResult; }')
    [void]$sb.AppendLine('                else { matchesAdv = matchesAdv && chipResult; }')
    [void]$sb.AppendLine('            }')
    [void]$sb.AppendLine('        }')
    [void]$sb.AppendLine('        var hidden = !matchesSearch || !matchesFilter || !matchesCategory || !matchesAssigned || !matchesAdv;')
    [void]$sb.AppendLine('        tr.style.display = hidden ? "none" : "";')
    [void]$sb.AppendLine('    });')
    [void]$sb.AppendLine('    // Hide product sections where all rows are hidden + count visible settings/policies')
    [void]$sb.AppendLine('    var visibleCount = 0;')
    [void]$sb.AppendLine('    var policySet = new Set();')
    [void]$sb.AppendLine('    tab.querySelectorAll("tbody tr[data-status]").forEach(function(tr) {')
    [void]$sb.AppendLine('        if (tr.style.display !== "none") {')
    [void]$sb.AppendLine('            visibleCount++;')
    [void]$sb.AppendLine('            var sp = tr.getAttribute("data-src-policy");')
    [void]$sb.AppendLine('            var dp = tr.getAttribute("data-dst-policy");')
    [void]$sb.AppendLine('            if (sp) policySet.add(sp);')
    [void]$sb.AppendLine('            if (dp) policySet.add(dp);')
    [void]$sb.AppendLine('        }')
    [void]$sb.AppendLine('    });')
    [void]$sb.AppendLine('    // No product sections to toggle — flat table')
    [void]$sb.AppendLine('    var catBtn = catWrap && catWrap.querySelector(".cat-ms-btn");')
    [void]$sb.AppendLine('    if (catBtn) { catBtn.innerHTML = filterByCategory ? catChecked.length + '' selected <span class="cat-count">'' + catChecked.length + ''</span>'' : "All categories"; }')
    [void]$sb.AppendLine('    // Update filter summary')
    [void]$sb.AppendLine('    var summary = document.getElementById("filter-summary");')
    [void]$sb.AppendLine("    if (summary) { summary.textContent = 'Showing ' + visibleCount + ' settings across ' + policySet.size + ' policies'; }")
    [void]$sb.AppendLine('    var clearBtn = document.getElementById("clear-filters-btn");')
    [void]$sb.AppendLine('    if (clearBtn) {')
    [void]$sb.AppendLine('        var hasAdvFilters = document.querySelectorAll("#active-adv-filters .adv-chip").length > 0;')
    [void]$sb.AppendLine('        var hasActive = activeFilters.size > 0 || q !== "" || (document.querySelectorAll("#cat-multiselect input[type=checkbox]:checked").length > 0) || excludeUnassigned || hasAdvFilters;')
    [void]$sb.AppendLine('        clearBtn.classList.toggle("hidden", !hasActive);')
    [void]$sb.AppendLine('    }')
    [void]$sb.AppendLine('    // Also filter Manual Review tab by search')
    [void]$sb.AppendLine('    var mrTab = document.getElementById("tab-manual-review");')
    [void]$sb.AppendLine('    if (mrTab) {')
    [void]$sb.AppendLine('        mrTab.querySelectorAll(".manual-review-card").forEach(function(card) {')
    [void]$sb.AppendLine('            if (!q) { card.style.display = ""; return; }')
    [void]$sb.AppendLine('            card.style.display = card.textContent.toLowerCase().indexOf(q) >= 0 ? "" : "none";')
    [void]$sb.AppendLine('        });')
    [void]$sb.AppendLine('    }')
    [void]$sb.AppendLine('    var vm = 0, vc = 0, vs = 0, vd = 0;')
    [void]$sb.AppendLine('    tab.querySelectorAll(''tbody tr[data-status]'').forEach(function(tr) {')
    [void]$sb.AppendLine('        if (tr.style.display === ''none'') return;')
    [void]$sb.AppendLine('        var st = tr.getAttribute(''data-status'');')
    [void]$sb.AppendLine('        if (st === ''Matched'') vm++;')
    [void]$sb.AppendLine('        else if (st === ''Conflicting'') vc++;')
    [void]$sb.AppendLine('        else if (st === ''SourceOnly'') vs++;')
    [void]$sb.AppendLine('        else if (st === ''DestOnly'') vd++;')
    [void]$sb.AppendLine('    });')
    [void]$sb.AppendLine('    updateScore(vm, vc, vs, vd);')
    [void]$sb.AppendLine('}')
    [void]$sb.AppendLine('function updateDropdownLabel(cb) {')
    [void]$sb.AppendLine('    var menu = cb.closest(".adv-dropdown-menu");')
    [void]$sb.AppendLine('    var btn = menu ? menu.previousElementSibling : null;')
    [void]$sb.AppendLine('    if (!btn) return;')
    [void]$sb.AppendLine('    var checked = menu.querySelectorAll("input[type=checkbox]:checked");')
    [void]$sb.AppendLine('    if (checked.length === 0) { btn.textContent = "Select..."; return; }')
    [void]$sb.AppendLine('    var names = [];')
    [void]$sb.AppendLine('    checked.forEach(function(c) { names.push(c.parentElement.textContent.trim()); });')
    [void]$sb.AppendLine('    btn.textContent = names.length <= 2 ? names.join(", ") : names.length + " selected";')
    [void]$sb.AppendLine('}')
    [void]$sb.AppendLine('// Expand/collapse long values via More/Less toggle buttons')
    [void]$sb.AppendLine('document.addEventListener("click", function(e) {')
    [void]$sb.AppendLine('    var btn = e.target.closest(".value-toggle-btn");')
    [void]$sb.AppendLine('    if (!btn) return;')
    [void]$sb.AppendLine('    var wrap = btn.closest(".value-wrap");')
    [void]$sb.AppendLine('    var truncEl = wrap && wrap.querySelector(".value-truncate");')
    [void]$sb.AppendLine('    if (!truncEl) return;')
    [void]$sb.AppendLine('    var expanded = truncEl.classList.toggle("expanded");')
    [void]$sb.AppendLine('    btn.innerHTML = expanded ? "\u25B2 Less" : "\u25BC More";')
    [void]$sb.AppendLine('});')
    [void]$sb.AppendLine('// Copy value to clipboard on value-copy-btn click')
    [void]$sb.AppendLine('document.addEventListener("click", function(e) {')
    [void]$sb.AppendLine('    var btn = e.target.closest(".value-copy-btn");')
    [void]$sb.AppendLine('    if (!btn) return;')
    [void]$sb.AppendLine('    var val = btn.getAttribute("data-value");')
    [void]$sb.AppendLine('    if (!val) return;')
    [void]$sb.AppendLine('    if (navigator.clipboard && navigator.clipboard.writeText) {')
    [void]$sb.AppendLine('        navigator.clipboard.writeText(val).then(function() {')
    [void]$sb.AppendLine('            btn.classList.add("copied");')
    [void]$sb.AppendLine('            btn.innerHTML = "\u2713 Copied!";')
    [void]$sb.AppendLine('            setTimeout(function() {')
    [void]$sb.AppendLine('                btn.classList.remove("copied");')
    [void]$sb.AppendLine('                btn.innerHTML = "\uD83D\uDCCB Copy";')
    [void]$sb.AppendLine('            }, 1500);')
    [void]$sb.AppendLine('        });')
    [void]$sb.AppendLine('    }')
    [void]$sb.AppendLine('});')
    [void]$sb.AppendLine('var sortState = {};')
    [void]$sb.AppendLine('function sortTable(th, colIdx) {')
    [void]$sb.AppendLine('    var table = th.closest("table");')
    [void]$sb.AppendLine('    if (!table) return;')
    [void]$sb.AppendLine('    var tbody = table.querySelector("tbody");')
    [void]$sb.AppendLine('    if (!tbody) return;')
    [void]$sb.AppendLine('    var rows = Array.from(tbody.querySelectorAll("tr"));')
    [void]$sb.AppendLine('    var key = table.id || "t" + colIdx;')
    [void]$sb.AppendLine('    var asc = sortState[key + colIdx] !== "asc";')
    [void]$sb.AppendLine('    sortState[key + colIdx] = asc ? "asc" : "desc";')
    [void]$sb.AppendLine('    rows.sort(function(a, b) {')
    [void]$sb.AppendLine('        var aText = (a.cells[colIdx] ? a.cells[colIdx].textContent : "").trim().toLowerCase();')
    [void]$sb.AppendLine('        var bText = (b.cells[colIdx] ? b.cells[colIdx].textContent : "").trim().toLowerCase();')
    [void]$sb.AppendLine('        if (aText < bText) return asc ? -1 : 1;')
    [void]$sb.AppendLine('        if (aText > bText) return asc ? 1 : -1;')
    [void]$sb.AppendLine('        return 0;')
    [void]$sb.AppendLine('    });')
    [void]$sb.AppendLine('    rows.forEach(function(r) { tbody.appendChild(r); });')
    [void]$sb.AppendLine('}')
    [void]$sb.AppendLine('function filterByStatus(btn, status) {')
    [void]$sb.AppendLine('    if (activeFilters.has(status)) {')
    [void]$sb.AppendLine('        activeFilters.delete(status);')
    [void]$sb.AppendLine('        btn.classList.remove("active");')
    [void]$sb.AppendLine('    } else {')
    [void]$sb.AppendLine('        activeFilters.add(status);')
    [void]$sb.AppendLine('        btn.classList.add("active");')
    [void]$sb.AppendLine('    }')
    [void]$sb.AppendLine('    applyFilters();')
    [void]$sb.AppendLine('}')
    [void]$sb.AppendLine('function clearFilters() {')
    [void]$sb.AppendLine('    activeFilters.clear();')
    [void]$sb.AppendLine('    document.querySelectorAll(".filter-pill").forEach(function(p) { p.classList.remove("active"); });')
    [void]$sb.AppendLine('    document.getElementById("search-input").value = "";')
    [void]$sb.AppendLine('    var catWrap = document.getElementById("cat-multiselect");')
    [void]$sb.AppendLine('    if (catWrap) { catWrap.querySelectorAll("input[type=checkbox]").forEach(function(cb) { cb.checked = false; }); var catBtn = catWrap.querySelector(".cat-ms-btn"); if (catBtn) catBtn.innerHTML = "All categories"; }')
    [void]$sb.AppendLine('    var euToggle = document.getElementById("toggle-exclude-unassigned");')
    [void]$sb.AppendLine('    if (euToggle) euToggle.checked = false;')
    [void]$sb.AppendLine('    var advContainer = document.getElementById("active-adv-filters");')
    [void]$sb.AppendLine('    if (advContainer) advContainer.innerHTML = "";')
    [void]$sb.AppendLine('    var advMenu = document.getElementById("adv-filter-menu");')
    [void]$sb.AppendLine('    if (advMenu) advMenu.querySelectorAll("button").forEach(function(b) { b.disabled = false; });')
    # Logic connector buttons are cleared when advContainer.innerHTML is set to ""
    [void]$sb.AppendLine('    applyFilters();')
    [void]$sb.AppendLine('}')
    [void]$sb.AppendLine('function toggleAssignments(show) {')
    [void]$sb.AppendLine('    var tbl = document.getElementById("comparison-table");')
    [void]$sb.AppendLine('    if (!tbl) return;')
    [void]$sb.AppendLine('    if (show) { tbl.classList.remove("hide-assignments"); } else { tbl.classList.add("hide-assignments"); }')
    [void]$sb.AppendLine('}')
    [void]$sb.AppendLine('function switchTab(tabId, evt) {')
    [void]$sb.AppendLine('    document.querySelectorAll(".tab-content").forEach(function(t) { t.classList.remove("active"); });')
    [void]$sb.AppendLine('    document.querySelectorAll(".tab-btn").forEach(function(b) { b.classList.remove("active"); });')
    [void]$sb.AppendLine('    var tab = document.getElementById("tab-" + tabId);')
    [void]$sb.AppendLine('    if (tab) tab.classList.add("active");')
    [void]$sb.AppendLine('    var src = evt ? (evt.currentTarget || evt.target) : null;')
    [void]$sb.AppendLine('    if (src) src.classList.add("active");')
    [void]$sb.AppendLine('    var cf = document.getElementById("comparison-filters");')
    [void]$sb.AppendLine('    if (cf) cf.style.display = (tabId === "comparison") ? "" : "none";')
    [void]$sb.AppendLine('}')
    [void]$sb.AppendLine('function toggleAllManualReview() {')
    [void]$sb.AppendLine('    var btn = document.getElementById("mr-expand-all-btn");')
    [void]$sb.AppendLine('    var cards = document.querySelectorAll(".manual-review-card");')
    [void]$sb.AppendLine('    var allOpen = true;')
    [void]$sb.AppendLine('    cards.forEach(function(d) { if (!d.open) allOpen = false; });')
    [void]$sb.AppendLine('    cards.forEach(function(d) { d.open = !allOpen; });')
    [void]$sb.AppendLine('    btn.textContent = allOpen ? "Expand All" : "Collapse All";')
    [void]$sb.AppendLine('}')
    [void]$sb.AppendLine('function toggleAdvMenu() {')
    [void]$sb.AppendLine('    var menu = document.getElementById("adv-filter-menu");')
    [void]$sb.AppendLine('    menu.classList.toggle("open");')
    [void]$sb.AppendLine('}')
    [void]$sb.AppendLine('document.addEventListener("click", function(e) {')
    [void]$sb.AppendLine('    var wrap = document.querySelector(".adv-filter-wrap");')
    [void]$sb.AppendLine('    if (wrap && !wrap.contains(e.target)) {')
    [void]$sb.AppendLine('        document.getElementById("adv-filter-menu").classList.remove("open");')
    [void]$sb.AppendLine('    }')
    [void]$sb.AppendLine('    document.querySelectorAll(".adv-dropdown-menu.open").forEach(function(m) {')
    [void]$sb.AppendLine('        if (!m.parentElement.contains(e.target)) m.classList.remove("open");')
    [void]$sb.AppendLine('    });')
    [void]$sb.AppendLine('});')
    [void]$sb.AppendLine('function addAdvFilter(key, label, colIdx) {')
    [void]$sb.AppendLine('    var container = document.getElementById("active-adv-filters");')
    [void]$sb.AppendLine('    if (document.getElementById("adv-chip-" + key)) return;')
    [void]$sb.AppendLine('    var chip = document.createElement("span");')
    [void]$sb.AppendLine('    chip.className = "adv-chip";')
    [void]$sb.AppendLine('    chip.id = "adv-chip-" + key;')
    [void]$sb.AppendLine('    chip.setAttribute("data-col", colIdx);')
    [void]$sb.AppendLine('    var isDropdown = (key === "status" || key === "category" || key === "os");')
    [void]$sb.AppendLine('    if (isDropdown) {')
    [void]$sb.AppendLine('        chip.setAttribute("data-type", "dropdown");')
    [void]$sb.AppendLine('        var options = [];')
    [void]$sb.AppendLine('        if (key === "status") { options = [{v:"Match",t:"Match"},{v:"Conflict",t:"Conflict"},{v:"Source Only",t:"Source Only"},{v:"Dest Only",t:"Dest Only"}]; }')
    [void]$sb.AppendLine('        else if (key === "os") { options = [{v:"Windows",t:"Windows"},{v:"macOS",t:"macOS"},{v:"Android",t:"Android"},{v:"iOS",t:"iOS/iPadOS"}]; }')
    [void]$sb.AppendLine('        else if (key === "category") {')
    [void]$sb.AppendLine('            var catSet = new Set();')
    [void]$sb.AppendLine('            document.querySelectorAll("#tab-comparison tbody tr[data-category]").forEach(function(r) {')
    [void]$sb.AppendLine('                var c = r.getAttribute("data-category"); if (c) catSet.add(c);')
    [void]$sb.AppendLine('            });')
    [void]$sb.AppendLine('            Array.from(catSet).sort().forEach(function(c) { options.push({v:c,t:c}); });')
    [void]$sb.AppendLine('        }')
    [void]$sb.AppendLine('        var optHtml = "";')
    [void]$sb.AppendLine('        options.forEach(function(o) {')
    [void]$sb.AppendLine('            optHtml += ''<label><input type="checkbox" value="'' + o.v + ''" onchange="updateDropdownLabel(this);applyFilters()"> '' + o.t + ''</label>'';')
    [void]$sb.AppendLine('        });')
    [void]$sb.AppendLine('        chip.innerHTML = ''<label>'' + label + '':</label>'' +')
    [void]$sb.AppendLine('            ''<div class="adv-dropdown-wrap"><button class="adv-dropdown-btn" type="button">Select...</button>'' +')
    [void]$sb.AppendLine('            ''<div class="adv-dropdown-menu">'' + optHtml + ''</div></div>'' +')
    [void]$sb.AppendLine('            ''<button class="adv-chip-remove" onclick="removeAdvFilter(\x27'' + key + ''\x27)">&times;</button>'';')
    [void]$sb.AppendLine('        chip.querySelector(".adv-dropdown-btn").addEventListener("click", function(e) {')
    [void]$sb.AppendLine('            e.stopPropagation();')
    [void]$sb.AppendLine('            this.nextElementSibling.classList.toggle("open");')
    [void]$sb.AppendLine('        });')
    [void]$sb.AppendLine('    } else {')
    [void]$sb.AppendLine('        chip.setAttribute("data-type", "tag");')
    [void]$sb.AppendLine('        chip.innerHTML = ''<label>'' + label + '':</label>'' +')
    [void]$sb.AppendLine('            ''<div class="tag-input-wrap"><input type="text" placeholder="type &amp; Enter"></div>'' +')
    [void]$sb.AppendLine('            ''<button class="adv-chip-remove" onclick="removeAdvFilter(\x27'' + key + ''\x27)">&times;</button>'';')
    [void]$sb.AppendLine('        var tagInput = chip.querySelector(".tag-input-wrap input");')
    [void]$sb.AppendLine('        tagInput.addEventListener("keydown", function(e) {')
    [void]$sb.AppendLine('            if ((e.key === "Enter" || e.key === "Tab") && this.value.trim()) {')
    [void]$sb.AppendLine('                e.preventDefault();')
    [void]$sb.AppendLine('                var wrap = this.closest(".tag-input-wrap");')
    [void]$sb.AppendLine('                var tag = document.createElement("span");')
    [void]$sb.AppendLine('                tag.className = "tag";')
    [void]$sb.AppendLine('                tag.setAttribute("data-value", this.value.trim());')
    [void]$sb.AppendLine('                tag.innerHTML = this.value.trim() + '' <button type="button">&times;</button>'';')
    [void]$sb.AppendLine('                tag.querySelector("button").addEventListener("click", function() {')
    [void]$sb.AppendLine('                    tag.remove(); applyFilters();')
    [void]$sb.AppendLine('                });')
    [void]$sb.AppendLine('                wrap.insertBefore(tag, this);')
    [void]$sb.AppendLine('                this.value = "";')
    [void]$sb.AppendLine('                applyFilters();')
    [void]$sb.AppendLine('            } else if (e.key === "Backspace" && !this.value) {')
    [void]$sb.AppendLine('                var wrap = this.closest(".tag-input-wrap");')
    [void]$sb.AppendLine('                var tags = wrap.querySelectorAll(".tag");')
    [void]$sb.AppendLine('                if (tags.length > 0) { tags[tags.length - 1].remove(); applyFilters(); }')
    [void]$sb.AppendLine('            }')
    [void]$sb.AppendLine('        });')
    [void]$sb.AppendLine('    }')
    [void]$sb.AppendLine('    var existing = container.querySelectorAll(".adv-chip");')
    [void]$sb.AppendLine('    if (existing.length > 0) {')
    [void]$sb.AppendLine('        var logicBtn = document.createElement("button");')
    [void]$sb.AppendLine('        logicBtn.className = "adv-logic-btn";')
    [void]$sb.AppendLine('        logicBtn.textContent = "AND";')
    [void]$sb.AppendLine('        logicBtn.setAttribute("data-mode", "AND"); logicBtn.onclick = function() { var m = this.getAttribute("data-mode") === "AND" ? "OR" : "AND"; this.setAttribute("data-mode", m); this.textContent = m; applyFilters(); };')
    [void]$sb.AppendLine('        container.appendChild(logicBtn);')
    [void]$sb.AppendLine('    }')
    [void]$sb.AppendLine('    container.appendChild(chip);')
    [void]$sb.AppendLine('    var menu = document.getElementById("adv-filter-menu");')
    [void]$sb.AppendLine('    menu.querySelectorAll("button").forEach(function(b) {')
    [void]$sb.AppendLine('        if (b.textContent === label) b.disabled = true;')
    [void]$sb.AppendLine('    });')
    [void]$sb.AppendLine('    menu.classList.remove("open");')
    [void]$sb.AppendLine('    var focusEl = chip.querySelector(".tag-input-wrap input");')
    [void]$sb.AppendLine('    if (focusEl) focusEl.focus();')
    [void]$sb.AppendLine('    applyFilters();')
    [void]$sb.AppendLine('}')
    [void]$sb.AppendLine('function removeAdvFilter(key) {')
    [void]$sb.AppendLine('    var chip = document.getElementById("adv-chip-" + key);')
    [void]$sb.AppendLine('    if (!chip) return;')
    [void]$sb.AppendLine('    var label = chip.querySelector("label").textContent.replace(":", "");')
    [void]$sb.AppendLine('    chip.remove();')
    [void]$sb.AppendLine('    var container = document.getElementById("active-adv-filters");')
    [void]$sb.AppendLine('    container.querySelectorAll(".adv-logic-btn").forEach(function(b) { b.remove(); });')
    [void]$sb.AppendLine('    var remaining = container.querySelectorAll(".adv-chip");')
    [void]$sb.AppendLine('    for (var i = 1; i < remaining.length; i++) {')
    [void]$sb.AppendLine('        var lb = document.createElement("button");')
    [void]$sb.AppendLine('        lb.className = "adv-logic-btn";')
    [void]$sb.AppendLine('        lb.textContent = "AND";')
    [void]$sb.AppendLine('        lb.onclick = function() { this.textContent = this.textContent === "AND" ? "OR" : "AND"; applyFilters(); };')
    [void]$sb.AppendLine('        container.insertBefore(lb, remaining[i]);')
    [void]$sb.AppendLine('    }')
    [void]$sb.AppendLine('    var menu = document.getElementById("adv-filter-menu");')
    [void]$sb.AppendLine('    menu.querySelectorAll("button").forEach(function(b) {')
    [void]$sb.AppendLine('        if (b.textContent === label) b.disabled = false;')
    [void]$sb.AppendLine('    });')
    [void]$sb.AppendLine('    applyFilters();')
    [void]$sb.AppendLine('}')
    if ($hasDuplicates) {
        [void]$sb.AppendLine("var dupPolicyCount = $dupPolicyCount;")
        [void]$sb.AppendLine('function analyzeDuplicate(policies) {')
        [void]$sb.AppendLine('    var uniqueValues = new Set(policies.map(function(p) { return p.Value; }));')
        [void]$sb.AppendLine('    var srcEntries = policies.filter(function(p) { return p.Side === ''Source''; });')
        [void]$sb.AppendLine('    var dstEntries = policies.filter(function(p) { return p.Side === ''Destination''; });')
        [void]$sb.AppendLine('    var hasBothSides = srcEntries.length > 0 && dstEntries.length > 0;')
        [void]$sb.AppendLine('    var srcNames = new Set(srcEntries.map(function(p) { return p.Policy.toLowerCase(); }));')
        [void]$sb.AppendLine('    var matchedPairs = dstEntries.filter(function(d) { return srcNames.has(d.Policy.toLowerCase()); });')
        [void]$sb.AppendLine('    var crossTenantMatch = matchedPairs.length > 0 && matchedPairs.some(function(d) {')
        [void]$sb.AppendLine('        var src = srcEntries.find(function(s) { return s.Policy.toLowerCase() === d.Policy.toLowerCase(); });')
        [void]$sb.AppendLine('        return src && src.Value === d.Value;')
        [void]$sb.AppendLine('    });')
        [void]$sb.AppendLine('    var valueCounts = new Map();')
        [void]$sb.AppendLine('    for (var i = 0; i < policies.length; i++) {')
        [void]$sb.AppendLine('        var v = policies[i].Value;')
        [void]$sb.AppendLine('        valueCounts.set(v, (valueCounts.get(v) || 0) + 1);')
        [void]$sb.AppendLine('    }')
        [void]$sb.AppendLine('    var majorityEntry = null;')
        [void]$sb.AppendLine('    valueCounts.forEach(function(count, val) {')
        [void]$sb.AppendLine('        if (!majorityEntry || count > majorityEntry[1]) majorityEntry = [val, count];')
        [void]$sb.AppendLine('    });')
        [void]$sb.AppendLine('    var majorityValue = majorityEntry ? majorityEntry[0] : null;')
        [void]$sb.AppendLine('    var outliers = policies.filter(function(p) { return p.Value !== majorityValue; });')
        [void]$sb.AppendLine('    if (!hasBothSides) {')
        [void]$sb.AppendLine('        if (outliers.length > 0) {')
        [void]$sb.AppendLine('            var outlierNames = outliers.map(function(p) { return p.Policy; }).join('', '');')
        [void]$sb.AppendLine('            return policies.length + '' policies in the same tenant configure this setting with different values. "'' + outlierNames + ''" differs from the others. If assignments overlap, Intune will report a conflict and the setting may not apply until the conflict is resolved.'';')
        [void]$sb.AppendLine('        }')
        [void]$sb.AppendLine('        return policies.length + '' policies configure this setting differently within the same tenant. If assignments overlap, Intune will report a conflict and the setting may not apply until resolved.'';')
        [void]$sb.AppendLine('    }')
        [void]$sb.AppendLine('    if (crossTenantMatch && outliers.length > 0) {')
        [void]$sb.AppendLine('        var outlierNames2 = outliers.map(function(p) { return p.Policy + '' ('' + p.Side + '')''; }).join('', '');')
        [void]$sb.AppendLine('        return ''The cross-tenant comparison matches, but '' + outlierNames2 + '' has a different value. If its assignments overlap with the matching policies, Intune will report a conflict and the setting may not apply until resolved.'';')
        [void]$sb.AppendLine('    }')
        [void]$sb.AppendLine('    if (uniqueValues.size === policies.length) {')
        [void]$sb.AppendLine('        return ''Every policy has a unique value for this setting. Review which value should be the standard across both tenants.'';')
        [void]$sb.AppendLine('    }')
        [void]$sb.AppendLine('    return ''This setting is configured in '' + policies.length + '' policies across both tenants with '' + uniqueValues.size + '' different values. Review to ensure consistency.'';')
        [void]$sb.AppendLine('}')
        [void]$sb.AppendLine('function dupTabSearch(query) {')
        [void]$sb.AppendLine('    var q = query.toLowerCase();')
        [void]$sb.AppendLine('    var rows = document.querySelectorAll(''#dup-table-body tr'');')
        [void]$sb.AppendLine('    var shown = 0;')
        [void]$sb.AppendLine('    rows.forEach(function(row) {')
        [void]$sb.AppendLine('        var setting = (row.getAttribute(''data-setting'') || '''').toLowerCase();')
        [void]$sb.AppendLine('        var policies = (row.getAttribute(''data-policies'') || '''').toLowerCase();')
        [void]$sb.AppendLine('        var match = !q || setting.indexOf(q) >= 0 || policies.indexOf(q) >= 0;')
        [void]$sb.AppendLine('        row.style.display = match ? '''' : ''none'';')
        [void]$sb.AppendLine('        if (match) shown++;')
        [void]$sb.AppendLine('    });')
        [void]$sb.AppendLine('    var summary = document.getElementById(''dup-summary'');')
        [void]$sb.AppendLine('    if (summary) {')
        [void]$sb.AppendLine('        summary.innerHTML = ''Showing <strong>'' + shown + ''</strong> of <strong>'' + rows.length + ''</strong> duplicate settings across <strong>'' + dupPolicyCount + ''</strong> policies'';')
        [void]$sb.AppendLine('    }')
        [void]$sb.AppendLine('    var noResults = document.getElementById(''dup-no-results'');')
        [void]$sb.AppendLine('    if (noResults) noResults.style.display = (shown === 0 && q) ? '''' : ''none'';')
        [void]$sb.AppendLine('}')
    }
    [void]$sb.AppendLine('// PowerShell syntax highlighting — works on textContent to avoid entity issues')
    [void]$sb.AppendLine('function escHtml(s) { return s.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;"); }')
    [void]$sb.AppendLine('function highlightPS(code) {')
    [void]$sb.AppendLine('    var text = code.textContent;')
    [void]$sb.AppendLine('    var tokens = [];')
    [void]$sb.AppendLine('    // Tokenize: comments, strings, then everything else')
    [void]$sb.AppendLine('    var re = /(#[^\n]*|<#[\s\S]*?#>|"[^"]*"|''[^'']*''|\$[\w:]+|\[[\w.]+\]|\b(?:if|else|elseif|foreach|for|while|do|switch|try|catch|finally|throw|return|function|param|begin|process|end|filter|class|enum|using|trap|break|continue|exit)\b|\b[A-Z][a-z]+(?:-[A-Z][a-zA-Z]+)+\b)/gi;')
    [void]$sb.AppendLine('    var lastIdx = 0, m;')
    [void]$sb.AppendLine('    while ((m = re.exec(text)) !== null) {')
    [void]$sb.AppendLine('        if (m.index > lastIdx) tokens.push(escHtml(text.substring(lastIdx, m.index)));')
    [void]$sb.AppendLine('        var t = m[0], cls = "";')
    [void]$sb.AppendLine('        if (t[0]==="#"||t.startsWith("<#")) cls="ps-comment";')
    [void]$sb.AppendLine('        else if (t[0]===''"''||t[0]==="''") cls="ps-string";')
    [void]$sb.AppendLine('        else if (t[0]==="$") cls="ps-variable";')
    [void]$sb.AppendLine('        else if (t[0]==="[") cls="ps-type";')
    [void]$sb.AppendLine('        else if (t.indexOf("-")>0&&t[0]===t[0].toUpperCase()) cls="ps-cmdlet";')
    [void]$sb.AppendLine('        else cls="ps-keyword";')
    [void]$sb.AppendLine('        tokens.push(''<span class="''+cls+''">''+escHtml(t)+''</span>'');')
    [void]$sb.AppendLine('        lastIdx = m.index + t.length;')
    [void]$sb.AppendLine('    }')
    [void]$sb.AppendLine('    if (lastIdx < text.length) tokens.push(escHtml(text.substring(lastIdx)));')
    [void]$sb.AppendLine('    code.innerHTML = tokens.join("");')
    [void]$sb.AppendLine('}')
    [void]$sb.AppendLine('function highlightBash(code) {')
    [void]$sb.AppendLine('    var text = code.textContent;')
    [void]$sb.AppendLine('    var tokens = [];')
    [void]$sb.AppendLine('    var re = /(#[^\n]*|"(?:[^"\\]|\\.)*"|''[^'']*''|\$\{[\w]+\}|\$[\w]+|\b(?:if|then|else|elif|fi|for|do|done|while|until|case|esac|function|return|local|export|set|trap|in)\b|\b(?:echo|curl|rm|mkdir|cp|mv|chmod|chown|grep|sed|awk|cat|ls|cd|pwd|source|eval|exec|exit)\b)/g;')
    [void]$sb.AppendLine('    var lastIdx = 0, m;')
    [void]$sb.AppendLine('    while ((m = re.exec(text)) !== null) {')
    [void]$sb.AppendLine('        if (m.index > lastIdx) tokens.push(escHtml(text.substring(lastIdx, m.index)));')
    [void]$sb.AppendLine('        var t = m[0], cls = "";')
    [void]$sb.AppendLine('        if (t[0] === "#") cls = "sh-comment";')
    [void]$sb.AppendLine('        else if (t[0] === "\"" || t[0] === "''") cls = "sh-string";')
    [void]$sb.AppendLine('        else if (t[0] === "$") cls = "sh-variable";')
    [void]$sb.AppendLine('        else if (/^(if|then|else|elif|fi|for|do|done|while|until|case|esac|function|return|local|export|set|trap|in)$/.test(t)) cls = "sh-keyword";')
    [void]$sb.AppendLine('        else cls = "sh-command";')
    [void]$sb.AppendLine('        tokens.push(''<span class="'' + cls + ''">''+escHtml(t)+''</span>'');')
    [void]$sb.AppendLine('        lastIdx = m.index + t.length;')
    [void]$sb.AppendLine('    }')
    [void]$sb.AppendLine('    if (lastIdx < text.length) tokens.push(escHtml(text.substring(lastIdx)));')
    [void]$sb.AppendLine('    code.innerHTML = tokens.join("");')
    [void]$sb.AppendLine('}')
    [void]$sb.AppendLine('// Apply filters FIRST to hide deprecated rows (must run before any cosmetic JS)')
    [void]$sb.AppendLine('applyFilters();')
    if ($hasDuplicates) {
        [void]$sb.AppendLine('// Populate analyzeDuplicate() analysis text for each duplicate row')
        [void]$sb.AppendLine('document.querySelectorAll(''#dup-table-body tr'').forEach(function(row) {')
        [void]$sb.AppendLine('    var jsonAttr = row.getAttribute(''data-policies-json'');')
        [void]$sb.AppendLine('    if (!jsonAttr) return;')
        [void]$sb.AppendLine('    try {')
        [void]$sb.AppendLine('        var policies = JSON.parse(atob(jsonAttr));')
        [void]$sb.AppendLine('        var cell = row.querySelector(''.dup-analysis-text'');')
        [void]$sb.AppendLine('        if (cell) cell.textContent = analyzeDuplicate(policies);')
        [void]$sb.AppendLine('    } catch(e) { /* skip malformed JSON */ }')
        [void]$sb.AppendLine('});')
        [void]$sb.AppendLine('dupTabSearch('''');')
    }
    [void]$sb.AppendLine('// Syntax highlighting and copy buttons (wrapped in try/catch to never block filters)')
    [void]$sb.AppendLine('try {')
    [void]$sb.AppendLine('    document.querySelectorAll(".ps-code code").forEach(highlightPS);')
    [void]$sb.AppendLine('    document.querySelectorAll(".sh-code code").forEach(highlightBash);')
    [void]$sb.AppendLine('    document.querySelectorAll(".ps-code-wrap").forEach(function(wrap) {')
    [void]$sb.AppendLine('        var btn = document.createElement("button");')
    [void]$sb.AppendLine('        btn.textContent = "Copy";')
    [void]$sb.AppendLine('        btn.className = "copy-btn";')
    [void]$sb.AppendLine('        btn.onclick = function() {')
    [void]$sb.AppendLine('            var code = wrap.querySelector("code");')
    [void]$sb.AppendLine('            navigator.clipboard.writeText(code.textContent).then(function() {')
    [void]$sb.AppendLine('                btn.textContent = "Copied!";')
    [void]$sb.AppendLine('                setTimeout(function() { btn.textContent = "Copy"; }, 2000);')
    [void]$sb.AppendLine('            });')
    [void]$sb.AppendLine('        };')
    [void]$sb.AppendLine('        wrap.appendChild(btn);')
    [void]$sb.AppendLine('    });')
    [void]$sb.AppendLine('} catch(e) { console.warn("Syntax highlighting error:", e); }')
    [void]$sb.AppendLine('// Column resize (Phase 8 TBL-01, per D-01 through D-04)')
    [void]$sb.AppendLine('try {')
    [void]$sb.AppendLine('(function() {')
    [void]$sb.AppendLine('  var table = document.getElementById(''comparison-table'');')
    [void]$sb.AppendLine('  if (!table) return;')
    [void]$sb.AppendLine('  var ths = table.querySelectorAll(''thead th'');')
    [void]$sb.AppendLine('  var defaultWidths = [];')
    [void]$sb.AppendLine('  var minWidths = [];')
    [void]$sb.AppendLine('  // Capture default widths after layout (per D-03)')
    [void]$sb.AppendLine('  ths.forEach(function(th, i) {')
    [void]$sb.AppendLine('    defaultWidths[i] = th.offsetWidth;')
    [void]$sb.AppendLine('    minWidths[i] = (i === 0) ? 40 : 60;')
    [void]$sb.AppendLine('  });')
    [void]$sb.AppendLine('  // Set table-layout: fixed after capturing widths (Pitfall 1)')
    [void]$sb.AppendLine('  ths.forEach(function(th) { th.style.width = th.offsetWidth + ''px''; });')
    [void]$sb.AppendLine('  table.style.tableLayout = ''fixed'';')
    [void]$sb.AppendLine('  ths.forEach(function(th, i) {')
    [void]$sb.AppendLine('    var handle = document.createElement(''div'');')
    [void]$sb.AppendLine('    handle.className = ''col-resize-handle'';')
    [void]$sb.AppendLine('    th.appendChild(handle);')
    [void]$sb.AppendLine('    // Double-click resets to default width (per D-03)')
    [void]$sb.AppendLine('    handle.addEventListener(''dblclick'', function(e) {')
    [void]$sb.AppendLine('      e.stopPropagation();')
    [void]$sb.AppendLine('      e.preventDefault();')
    [void]$sb.AppendLine('      th.style.width = defaultWidths[i] + ''px'';')
    [void]$sb.AppendLine('    });')
    [void]$sb.AppendLine('    var startX, startW;')
    [void]$sb.AppendLine('    handle.addEventListener(''mousedown'', function(e) {')
    [void]$sb.AppendLine('      e.stopPropagation();')
    [void]$sb.AppendLine('      e.preventDefault();')
    [void]$sb.AppendLine('      startX = e.pageX;')
    [void]$sb.AppendLine('      startW = th.offsetWidth;')
    [void]$sb.AppendLine('      handle.classList.add(''resizing'');')
    [void]$sb.AppendLine('      document.body.style.cursor = ''col-resize'';')
    [void]$sb.AppendLine('      document.addEventListener(''mousemove'', onMouseMove);')
    [void]$sb.AppendLine('      document.addEventListener(''mouseup'', onMouseUp);')
    [void]$sb.AppendLine('    });')
    [void]$sb.AppendLine('    function onMouseMove(e) {')
    [void]$sb.AppendLine('      var w = Math.max(minWidths[i], startW + (e.pageX - startX));')
    [void]$sb.AppendLine('      th.style.width = w + ''px'';')
    [void]$sb.AppendLine('    }')
    [void]$sb.AppendLine('    function onMouseUp() {')
    [void]$sb.AppendLine('      handle.classList.remove(''resizing'');')
    [void]$sb.AppendLine('      document.body.style.cursor = '''';')
    [void]$sb.AppendLine('      document.removeEventListener(''mousemove'', onMouseMove);')
    [void]$sb.AppendLine('      document.removeEventListener(''mouseup'', onMouseUp);')
    [void]$sb.AppendLine('    }')
    [void]$sb.AppendLine('  });')
    [void]$sb.AppendLine('})();')
    [void]$sb.AppendLine('} catch(e) { console.warn(''Column resize error:'', e); }')
    [void]$sb.AppendLine('</script>')

    # ── Close body/html ────────────────────────────────────────────────────
    [void]$sb.AppendLine('</body>')
    [void]$sb.AppendLine('</html>')

    return $sb.ToString()
}
