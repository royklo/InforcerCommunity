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
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", system-ui, Roboto, sans-serif;
    background: var(--bg);
    color: var(--text);
    max-width: 1600px;
    margin: 0 auto;
    padding: 0 1.5rem 3rem;
    line-height: 1.65;
    font-size: 0.9375rem;
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
.score-bar-fill.green { background: linear-gradient(90deg, #059669, #34d399); }
.score-bar-fill.yellow { background: linear-gradient(90deg, #d97706, #fbbf24); }
.score-bar-fill.red { background: linear-gradient(90deg, #dc2626, #f87171); }
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
.search-bar { margin-bottom: 1rem; }
.search-bar input {
    width: 100%; padding: 0.625rem 0.875rem; border: 1px solid var(--border); border-radius: var(--radius-xs);
    background: var(--bg-card); color: var(--text); font-size: 0.875rem; font-family: inherit; outline: none;
    transition: border-color var(--transition), box-shadow var(--transition);
}
.search-bar input:focus { border-color: var(--accent); box-shadow: 0 0 0 3px var(--accent-soft); }
.search-hidden { display: none !important; }
.filter-bar { display: flex; align-items: center; gap: 0.5rem; margin-bottom: 1rem; flex-wrap: wrap; }
.filter-label { font-size: 0.75rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.06em; color: var(--muted); }
.filter-pill {
    background: var(--bg-card); border: 1px solid var(--border); color: var(--text-secondary);
    padding: 0.3rem 0.75rem; border-radius: 999px; font-size: 0.75rem; cursor: pointer;
    transition: all var(--transition); font-family: inherit; font-weight: 500;
}
.filter-pill:hover { border-color: var(--accent); color: var(--accent); }
.filter-pill.active { background: var(--accent); color: #fff; border-color: var(--accent); }
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
    display: inline-flex; align-items: center; gap: 0.375rem; padding: 0.25rem 0.75rem;
    border-radius: var(--radius-xs); font-size: 0.75rem; font-weight: 600; white-space: nowrap;
}
.status-matched { background: var(--success-bg); color: var(--success); }
.status-conflicting { background: var(--danger-bg); color: var(--danger); }
.status-source-only { background: var(--warning-bg); color: var(--warning); }
.status-dest-only { background: var(--info-bg); color: var(--info); }
.status-manual { background: var(--manual-bg); color: var(--manual); }
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
summary::before {
    content: ''; display: inline-block; width: 0.375rem; height: 0.375rem;
    border-right: 2px solid var(--muted); border-bottom: 2px solid var(--muted);
    transform: rotate(-45deg); margin-right: 0.625rem; transition: transform var(--transition); flex-shrink: 0;
}
details[open] > summary::before { transform: rotate(45deg); }
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
table { width: 100%; border-collapse: collapse; font-size: 0.8125rem; min-width: 400px; }
.table-wrap { overflow-x: auto; margin-bottom: 0.75rem; border-radius: var(--radius-xs); }
th {
    background: var(--header-bg); text-align: left; padding: 0.5rem 0.75rem; font-weight: 600;
    font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.04em; color: var(--text-secondary);
    border-bottom: 1px solid var(--border); user-select: none;
}
th[onclick]:hover { background: var(--accent-soft); color: var(--accent); }
td { padding: 0.5rem 0.75rem; border-bottom: 1px solid var(--border-subtle); vertical-align: top; color: var(--text); word-break: break-word; }
tr:last-child td { border-bottom: none; }
tr:nth-child(even) td { background: var(--row-alt); }
tr:hover td { background: var(--accent-soft); }
.policy-name { font-weight: 600; }
.setting-name { color: var(--text-secondary); }
.setting-path {
    display: block;
    font-size: 0.7rem;
    color: var(--muted);
    margin-top: 2px;
}
.value-cell { font-family: "SF Mono", "Cascadia Code", "Consolas", monospace; font-size: 0.75rem; }
.value-long { max-height: 1.4em; overflow: hidden; position: relative; cursor: pointer; white-space: nowrap; text-overflow: ellipsis; }
.value-long::after { content: ' ▸ expand'; position: absolute; bottom: 0; right: 0; padding: 0 0.25rem; background: var(--bg-card); font-size: 0.65rem; color: var(--accent); font-style: italic; }
.value-long.expanded { max-height: none; white-space: normal; text-overflow: unset; }
.value-long.expanded::after { content: ' ▾ collapse'; }
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
.fab-theme { background: var(--bg-card); color: var(--text); border: 1px solid var(--border); }
.fab-theme:hover { background: var(--bg-card); border-color: var(--accent); color: var(--accent); box-shadow: var(--shadow-lg); }
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
.manual-review-card summary { padding: 0.75rem 1rem; font-size: 0.875rem; cursor: pointer; list-style: none; display: flex; align-items: center; gap: 0.5rem; }
.manual-review-card summary::-webkit-details-marker { display: none; }
.manual-review-card summary::before { content: '\25B6'; font-size: 0.65rem; color: var(--muted); transition: transform var(--transition); }
.manual-review-card[open] summary::before { transform: rotate(90deg); }
.manual-review-card[open] summary { border-bottom: 1px solid var(--border-subtle); }
.manual-review-card .mr-body { padding: 0.75rem 1rem; }
.manual-review-card .side-badge { display: inline-block; padding: 0.125rem 0.5rem; border-radius: 999px; font-size: 0.7rem; font-weight: 600; }
.manual-review-card .side-source { background: var(--info-bg); color: var(--info); }
.manual-review-card .side-dest { background: var(--warning-bg); color: var(--warning); }
.badge-deprecated { display: inline-block; padding: 0.15rem 0.6rem; border-radius: 999px; font-size: 0.7rem; font-weight: 700; background: var(--danger-bg); color: var(--danger); animation: pulse-deprecated 1.5s ease-in-out infinite; }
@keyframes pulse-deprecated { 0%,100% { opacity: 1; } 50% { opacity: 0.5; } }
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
.manual-review-setting .setting-name { color: var(--text); flex: 1; }
.manual-review-setting .setting-value { color: var(--text-secondary); max-width: 40%; text-align: right; word-break: break-word; font-family: "SF Mono","Cascadia Code","Consolas",monospace; font-size: 0.75rem; }
.manual-review-setting:nth-child(even) { background: var(--row-alt); }
.setting-deprecated { background: transparent !important; padding: 0.25rem 0.5rem; margin: 0.1rem 0; }
.setting-deprecated .setting-name { color: var(--danger); font-weight: 600; }
'@

    # ── Extract model values ───────────────────────────────────────────────
    $sourceName      = [System.Net.WebUtility]::HtmlEncode($ComparisonModel.SourceName)
    $destName        = [System.Net.WebUtility]::HtmlEncode($ComparisonModel.DestinationName)
    $generatedAt     = [System.Net.WebUtility]::HtmlEncode($ComparisonModel.GeneratedAt)
    $alignmentScore  = $ComparisonModel.AlignmentScore
    $totalItems      = $ComparisonModel.TotalItems
    $matched         = $ComparisonModel.Counters.Matched
    $conflicting     = $ComparisonModel.Counters.Conflicting
    $sourceOnly      = $ComparisonModel.Counters.SourceOnly
    $destOnly        = $ComparisonModel.Counters.DestOnly
    $products        = $ComparisonModel.Products
    $inclAssignments = $ComparisonModel.IncludingAssignments

    # Bar color class
    $barColor = if ($alignmentScore -ge 70) { 'green' }
                elseif ($alignmentScore -ge 40) { 'yellow' }
                else { 'red' }

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
    [void]$sb.AppendLine("    <div class=`"score-bar-track`"><div class=`"score-bar-fill $barColor`" id=`"scoreBar`"></div></div>")
    [void]$sb.AppendLine('</div>')

    # ── Summary tiles ──────────────────────────────────────────────────────
    [void]$sb.AppendLine('<div class="summary-grid">')
    [void]$sb.AppendLine('    <div class="summary-tile matched"><div class="count" id="countMatched">0</div><div class="label">Matched</div></div>')
    [void]$sb.AppendLine('    <div class="summary-tile conflicting"><div class="count" id="countConflicting">0</div><div class="label">Conflicting</div></div>')
    [void]$sb.AppendLine('    <div class="summary-tile source-only"><div class="count" id="countSource">0</div><div class="label">Source Only</div></div>')
    [void]$sb.AppendLine('    <div class="summary-tile dest-only"><div class="count" id="countDest">0</div><div class="label">Destination Only</div></div>')
    [void]$sb.AppendLine('</div>')

    # ── Search bar ─────────────────────────────────────────────────────────
    [void]$sb.AppendLine('<div class="search-bar">')
    [void]$sb.AppendLine('    <input type="text" id="search-input" placeholder="Search policies, settings, values..." oninput="searchAll(this.value)">')
    [void]$sb.AppendLine('</div>')

    # ── Collect all unique categories for the filter dropdown (Fix 5: before rendering) ──
    $allCategories = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($productName in $products.Keys) {
        $productData = $products[$productName]
        foreach ($categoryName in $productData.Categories.Keys) {
            $categoryData = $productData.Categories[$categoryName]
            foreach ($r in $categoryData.ComparisonRows) {
                $cat = if ($r.Category) { $r.Category } else { $categoryName }
                # Strip product prefix for display (e.g., "Intune / Windows / Settings Catalog" → "Windows / Settings Catalog")
                if ($cat -match '^[^/]+\s*/\s*(.+)$') { $cat = $Matches[1] }
                if (-not [string]::IsNullOrWhiteSpace($cat)) { [void]$allCategories.Add($cat) }
            }
        }
    }

    # ── Filter pills ──────────────────────────────────────────────────────
    [void]$sb.AppendLine('<div class="filter-bar">')
    [void]$sb.AppendLine('    <span class="filter-label">Filter:</span>')
    [void]$sb.AppendLine('    <button class="filter-pill active" onclick="filterByStatus(this,''All'')">All</button>')
    [void]$sb.AppendLine('    <button class="filter-pill" onclick="filterByStatus(this,''Matched'')">Matched</button>')
    [void]$sb.AppendLine('    <button class="filter-pill" onclick="filterByStatus(this,''Conflicting'')">Conflicting</button>')
    [void]$sb.AppendLine('    <button class="filter-pill" onclick="filterByStatus(this,''SourceOnly'')">Source Only</button>')
    [void]$sb.AppendLine('    <button class="filter-pill" onclick="filterByStatus(this,''DestOnly'')">Dest Only</button>')
    # Category filter dropdown
    [void]$sb.Append('    <select id="category-filter" onchange="applyFilters()" style="margin-left:0.75rem;padding:0.3rem 0.5rem;border:1px solid var(--border);border-radius:var(--radius-xs);background:var(--bg-card);color:var(--text);font-size:0.75rem;font-family:inherit;cursor:pointer">')
    [void]$sb.Append('<option value="All">All categories</option>')
    foreach ($catName in $allCategories) {
        $encCat = [System.Net.WebUtility]::HtmlEncode($catName)
        [void]$sb.Append("<option value=`"$encCat`">$encCat</option>")
    }
    [void]$sb.AppendLine('</select>')
    [void]$sb.AppendLine('</div>')
    [void]$sb.AppendLine('<div id="filter-summary" style="font-size:0.9rem;font-weight:600;color:var(--accent);padding:0.5rem 0.75rem;margin:0.5rem 0;background:var(--accent-soft);border-radius:var(--radius-xs);"></div>')

    # ── Tab navigation ──────────────────────────────────────────────────
    $manualReview = $ComparisonModel.ManualReview
    $hasManualReview = $null -ne $manualReview -and $manualReview.Count -gt 0
    $mrCount = if ($hasManualReview) { ($manualReview.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum } else { 0 }

    [void]$sb.AppendLine('<div class="tab-nav">')
    [void]$sb.AppendLine('    <button class="tab-btn active" onclick="switchTab(''comparison'')">Comparison</button>')
    if ($hasManualReview) {
        [void]$sb.AppendLine("    <button class=`"tab-btn`" onclick=`"switchTab('manual-review')`">Manual Review <span class=`"status-badge`" style=`"margin-left:0.5rem;font-size:0.7rem`">$mrCount</span></button>")
    }
    [void]$sb.AppendLine('</div>')

    # ── Comparison tab ───────────────────────────────────────────────────
    [void]$sb.AppendLine('<div class="tab-content active" id="tab-comparison">')

    # Collect ALL comparison rows into a single flat list
    $allRows = [System.Collections.Generic.List[object]]::new()
    foreach ($productName in $products.Keys) {
        $productData = $products[$productName]
        foreach ($categoryName in $productData.Categories.Keys) {
            foreach ($r in $productData.Categories[$categoryName].ComparisonRows) {
                [void]$allRows.Add($r)
            }
        }
    }
    $allRows = @($allRows | Sort-Object { $_.Name })

    # Deprecated policies are in ManualReview with HasDeprecated flag

    if ($allRows.Count -gt 0) {
        [void]$sb.AppendLine('    <div class="table-wrap">')
        [void]$sb.AppendLine('    <table id="comparison-table">')
        [void]$sb.AppendLine('        <thead><tr>')
        [void]$sb.Append('            <th style="width:4%;cursor:pointer" onclick="sortTable(this,0)">Status &#x25B4;&#x25BE;</th>')
        [void]$sb.Append('<th style="width:20%;cursor:pointer" onclick="sortTable(this,1)">Setting &#x25B4;&#x25BE;</th>')
        [void]$sb.Append('<th style="width:14%;cursor:pointer" onclick="sortTable(this,2)">Category &#x25B4;&#x25BE;</th>')
        [void]$sb.Append('<th style="width:15%;cursor:pointer" onclick="sortTable(this,3)">Source Policy &#x25B4;&#x25BE;</th>')
        [void]$sb.Append('<th style="width:15%;cursor:pointer" onclick="sortTable(this,4)">Source Value &#x25B4;&#x25BE;</th>')
        [void]$sb.Append('<th style="width:15%;cursor:pointer" onclick="sortTable(this,5)">Dest Policy &#x25B4;&#x25BE;</th>')
        [void]$sb.Append('<th style="width:15%;cursor:pointer" onclick="sortTable(this,6)">Dest Value &#x25B4;&#x25BE;</th>')
        if ($inclAssignments) {
            [void]$sb.Append('<th>Source Assignment</th>')
            [void]$sb.Append('<th>Dest Assignment</th>')
        }
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('        </tr></thead>')
        [void]$sb.AppendLine('        <tbody>')

            foreach ($row in $allRows) {
                $status = $row.Status

                # Status badge
                switch ($status) {
                    'Matched'     { $statusHtml = '<span class="status-badge status-matched">&#10003;</span>' }
                    'Conflicting' { $statusHtml = '<span class="status-badge status-conflicting">&#10007;</span>' }
                    'SourceOnly'  { $statusHtml = '<span class="status-badge status-source-only">Source Only</span>' }
                    'DestOnly'    { $statusHtml = '<span class="status-badge status-dest-only">Dest Only</span>' }
                    default       { $statusHtml = [System.Net.WebUtility]::HtmlEncode($status) }
                }

                $encName = [System.Net.WebUtility]::HtmlEncode($row.Name)
                # Strip product prefix from category for display and filtering
                $strippedCategory = $row.Category
                if ($strippedCategory -match '^[^/]+\s*/\s*(.+)$') { $strippedCategory = $Matches[1] }
                $encCategory = [System.Net.WebUtility]::HtmlEncode($strippedCategory)
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
                $settingPath = "$($row.SettingPath)"
                $encPath = [System.Net.WebUtility]::HtmlEncode($settingPath)
                if ($settingPath -match ' > ') {
                    [void]$sb.Append("<td class=`"setting-name`">$encName<span class=`"setting-path`">$encPath</span></td>")
                } else {
                    [void]$sb.Append("<td class=`"setting-name`">$encName</td>")
                }

                # Category column (already stripped of product prefix)
                [void]$sb.Append("<td style=`"font-size:0.75rem;color:var(--text-secondary)`">$encCategory</td>")

                # Source columns
                if ($status -eq 'DestOnly') {
                    [void]$sb.Append('<td colspan="2" style="color: var(--muted); font-style: italic;">Not configured</td>')
                } else {
                    $encSrcPolicy = [System.Net.WebUtility]::HtmlEncode($row.SourcePolicy)
                    $encSrcValue  = [System.Net.WebUtility]::HtmlEncode($row.SourceValue)
                    $srcLong = if ($row.SourceValue.Length -gt 100) { ' value-long' } else { '' }
                    [void]$sb.Append("<td>$encSrcPolicy</td>")
                    [void]$sb.Append("<td class=`"value-cell$srcLong`">$encSrcValue</td>")
                }

                # Dest columns
                if ($status -eq 'SourceOnly') {
                    [void]$sb.Append('<td colspan="2" style="color: var(--muted); font-style: italic;">Not configured</td>')
                } else {
                    $encDstPolicy = [System.Net.WebUtility]::HtmlEncode($row.DestPolicy)
                    $encDstValue  = [System.Net.WebUtility]::HtmlEncode($row.DestValue)
                    $valueCls = if ($status -eq 'Conflicting') { 'value-cell value-diff' } else { 'value-cell' }
                    $dstLong = if ($row.DestValue.Length -gt 100) { ' value-long' } else { '' }
                    [void]$sb.Append("<td>$encDstPolicy</td>")
                    [void]$sb.Append("<td class=`"$valueCls$dstLong`">$encDstValue</td>")
                }

                # Assignment columns
                if ($inclAssignments) {
                    $encSrcAssign = [System.Net.WebUtility]::HtmlEncode($row.SourceAssignment)
                    $encDstAssign = [System.Net.WebUtility]::HtmlEncode($row.DestAssignment)
                    [void]$sb.Append("<td class=`"value-cell`">$encSrcAssign</td>")
                    [void]$sb.Append("<td class=`"value-cell`">$encDstAssign</td>")
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
        [void]$sb.AppendLine('<div style="padding:1rem 0 0.5rem;color:var(--text-secondary);font-size:0.85rem">')
        [void]$sb.AppendLine('    These are non-Settings Catalog policies (Administrative Templates, legacy profiles) that cannot be reliably auto-compared with Settings Catalog equivalents. Review them manually to check if both environments configure the same areas differently.')
        [void]$sb.AppendLine('</div>')

        foreach ($catLabel in $manualReview.Keys) {
            $policies = $manualReview[$catLabel]
            $encCatLabel = [System.Net.WebUtility]::HtmlEncode($catLabel)
            [void]$sb.AppendLine("<h3 style=`"font-size:0.95rem;margin:1.5rem 0 0.75rem;color:var(--text)`">$encCatLabel</h3>")

            foreach ($policy in $policies) {
                $encPolicyName = [System.Net.WebUtility]::HtmlEncode($policy.PolicyName)
                $encProfileType = [System.Net.WebUtility]::HtmlEncode($policy.ProfileType)
                $sideCls = if ($policy.Side -eq 'Source') { 'side-source' } else { 'side-dest' }
                $sideLabel = [System.Net.WebUtility]::HtmlEncode($policy.Side)

                $hasDepr = $policy.HasDeprecated -eq $true
                $deprBadge = if ($hasDepr) { ' <span class="badge-deprecated">&#x26A0; contains deprecated settings</span>' } else { '' }
                [void]$sb.AppendLine('<details class="manual-review-card">')
                [void]$sb.AppendLine("    <summary><strong>$encPolicyName</strong> <span class=`"side-badge $sideCls`">$sideLabel</span>$deprBadge</summary>")
                [void]$sb.AppendLine('    <div class="mr-body">')
                if (-not [string]::IsNullOrWhiteSpace($encProfileType)) {
                    [void]$sb.AppendLine("    <div style=`"font-size:0.75rem;color:var(--muted);margin-bottom:0.5rem`">$encProfileType</div>")
                }

                if ($policy.Settings.Count -gt 0) {
                    foreach ($s in $policy.Settings) {
                        $encSName = [System.Net.WebUtility]::HtmlEncode($s.Name)
                        $encSValue = [System.Net.WebUtility]::HtmlEncode($s.Value)
                        $isSettingDepr = $s.IsDeprecated -eq $true
                        # Script content gets a code block, regular settings get inline display
                        if ($s.Name -match 'scriptContent|detectionScriptContent|remediationScriptContent' -and $s.Value.Length -gt 100) {
                            [void]$sb.AppendLine("    <div style=`"margin:0.5rem 0`"><strong style=`"font-size:0.8rem`">$encSName</strong></div>")
                            [void]$sb.AppendLine("    <div class=`"ps-code-wrap`"><pre class=`"ps-code`" style=`"background:var(--bg);border:1px solid var(--border);border-radius:var(--radius-xs);padding:0.75rem;font-size:0.75rem;overflow-x:auto;max-height:400px;overflow-y:auto;margin:0`"><code>$encSValue</code></pre></div>")
                        } elseif ($isSettingDepr) {
                            [void]$sb.AppendLine("    <div class=`"manual-review-setting setting-deprecated`"><span class=`"setting-name`">&#x26A0; $encSName</span><span class=`"setting-value`">$encSValue</span></div>")
                        } else {
                            [void]$sb.AppendLine("    <div class=`"manual-review-setting`"><span class=`"setting-name`">$encSName</span><span class=`"setting-value`">$encSValue</span></div>")
                        }
                    }
                } else {
                    [void]$sb.AppendLine('    <div style="color:var(--muted);font-size:0.8rem;font-style:italic">No configured settings</div>')
                }
                [void]$sb.AppendLine('    </div>')

                [void]$sb.AppendLine('</details>')
            }
        }

        [void]$sb.AppendLine('</div>')  # end tab-manual-review
    }

    # ── Footer ─────────────────────────────────────────────────────────────
    [void]$sb.AppendLine('<div class="footer">')
    [void]$sb.AppendLine('    InforcerCommunity Module &middot; Created by Roy Klooster')
    [void]$sb.AppendLine('</div>')

    # ── Floating buttons ───────────────────────────────────────────────────
    [void]$sb.AppendLine('<div class="fab-group">')
    [void]$sb.AppendLine('    <button class="fab fab-top" id="btn-top" onclick="scrollToTop()" aria-label="Back to top">')
    [void]$sb.AppendLine('        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M18 15l-6-6-6 6"/></svg>')
    [void]$sb.AppendLine('    </button>')
    [void]$sb.AppendLine('    <button class="fab fab-theme" id="btn-theme" onclick="toggleTheme()" aria-label="Toggle dark/light mode">')
    [void]$sb.AppendLine('        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="5"/><line x1="12" y1="1" x2="12" y2="3"/><line x1="12" y1="21" x2="12" y2="23"/><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/><line x1="1" y1="12" x2="3" y2="12"/><line x1="21" y1="12" x2="23" y2="12"/><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/></svg>')
    [void]$sb.AppendLine('    </button>')
    [void]$sb.AppendLine('</div>')

    # ── JavaScript ─────────────────────────────────────────────────────────
    [void]$sb.AppendLine('<script>')
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
    [void]$sb.AppendLine('    setTimeout(function() {')
    [void]$sb.AppendLine('        var timer = setInterval(function() {')
    [void]$sb.AppendLine('            step++;')
    [void]$sb.AppendLine('            var progress = ease(Math.min(step / steps, 1));')
    [void]$sb.AppendLine('            var pct = TARGET * progress;')
    [void]$sb.AppendLine('            elScore.textContent = Math.round(pct * 10) / 10 + ''%'';')
    [void]$sb.AppendLine('            elBar.style.width = pct + ''%'';')
    [void]$sb.AppendLine('            elDetail.textContent = Math.round(MATCHED * progress) + '' of '' + TOTAL + '' settings matched'';')
    [void]$sb.AppendLine('            elMatched.textContent = Math.round(MATCHED * progress);')
    [void]$sb.AppendLine('            elConflicting.textContent = Math.round(CONFLICTING * progress);')
    [void]$sb.AppendLine('            elSource.textContent = Math.round(SOURCE * progress);')
    [void]$sb.AppendLine('            elDest.textContent = Math.round(DEST * progress);')
    [void]$sb.AppendLine('            if (step >= steps) {')
    [void]$sb.AppendLine('                clearInterval(timer);')
    [void]$sb.AppendLine('                elScore.textContent = TARGET + ''%'';')
    [void]$sb.AppendLine('                elBar.style.width = TARGET + ''%'';')
    [void]$sb.AppendLine('                elDetail.textContent = MATCHED + '' of '' + TOTAL + '' settings matched'';')
    [void]$sb.AppendLine('                elMatched.textContent = MATCHED;')
    [void]$sb.AppendLine('                elConflicting.textContent = CONFLICTING;')
    [void]$sb.AppendLine('                elSource.textContent = SOURCE;')
    [void]$sb.AppendLine('                elDest.textContent = DEST;')
    [void]$sb.AppendLine('            }')
    [void]$sb.AppendLine('        }, INTERVAL);')
    [void]$sb.AppendLine('    }, 300);')
    [void]$sb.AppendLine('})();')
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
    [void]$sb.AppendLine('var activeFilters = new Set();')
    [void]$sb.AppendLine('function applyFilters() {')
    [void]$sb.AppendLine('    var q = (document.getElementById("search-input").value || "").toLowerCase().trim();')
    [void]$sb.AppendLine('    var showAll = activeFilters.size === 0 || activeFilters.has("All");')
    [void]$sb.AppendLine('    // Deprecated settings are in their own tab — no toggle logic needed')
    [void]$sb.AppendLine('    var catFilter = document.getElementById("category-filter");')
    [void]$sb.AppendLine('    var selectedCat = catFilter ? catFilter.value : "All";')
    [void]$sb.AppendLine('    var tab = document.getElementById("tab-comparison");')
    [void]$sb.AppendLine('    if (!tab) return;')
    [void]$sb.AppendLine('    // Filter individual rows by search + status + category + deprecated')
    [void]$sb.AppendLine('    tab.querySelectorAll("tbody tr[data-status]").forEach(function(tr) {')
    [void]$sb.AppendLine('        var matchesSearch = !q || tr.textContent.toLowerCase().indexOf(q) >= 0;')
    [void]$sb.AppendLine('        var matchesFilter = showAll || activeFilters.has(tr.getAttribute("data-status"));')
    [void]$sb.AppendLine('        var matchesCategory = selectedCat === "All" || tr.getAttribute("data-category") === selectedCat;')
    [void]$sb.AppendLine('        var hidden = !matchesSearch || !matchesFilter || !matchesCategory;')
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
    [void]$sb.AppendLine('    // Update filter summary')
    [void]$sb.AppendLine('    var summary = document.getElementById("filter-summary");')
    [void]$sb.AppendLine("    if (summary) { summary.textContent = 'Showing ' + visibleCount + ' settings across ' + policySet.size + ' policies'; }")
    [void]$sb.AppendLine('    // Also filter Manual Review tab by search')
    [void]$sb.AppendLine('    var mrTab = document.getElementById("tab-manual-review");')
    [void]$sb.AppendLine('    if (mrTab) {')
    [void]$sb.AppendLine('        mrTab.querySelectorAll(".manual-review-card").forEach(function(card) {')
    [void]$sb.AppendLine('            if (!q) { card.style.display = ""; return; }')
    [void]$sb.AppendLine('            card.style.display = card.textContent.toLowerCase().indexOf(q) >= 0 ? "" : "none";')
    [void]$sb.AppendLine('        });')
    [void]$sb.AppendLine('    }')
    [void]$sb.AppendLine('}')
    [void]$sb.AppendLine('function searchAll() { applyFilters(); }')
    [void]$sb.AppendLine('// Click to expand long values')
    [void]$sb.AppendLine('document.addEventListener("click", function(e) {')
    [void]$sb.AppendLine('    var el = e.target.closest(".value-long");')
    [void]$sb.AppendLine('    if (el) el.classList.toggle("expanded");')
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
    [void]$sb.AppendLine('    var allBtn = document.querySelector(".filter-pill[onclick*=\"All\"]");')
    [void]$sb.AppendLine('    if (status === "All") {')
    [void]$sb.AppendLine('        activeFilters.clear();')
    [void]$sb.AppendLine('        document.querySelectorAll(".filter-pill").forEach(function(p) { p.classList.remove("active"); });')
    [void]$sb.AppendLine('        btn.classList.add("active");')
    [void]$sb.AppendLine('    } else {')
    [void]$sb.AppendLine('        activeFilters.delete("All");')
    [void]$sb.AppendLine('        if (allBtn) allBtn.classList.remove("active");')
    [void]$sb.AppendLine('        if (activeFilters.has(status)) {')
    [void]$sb.AppendLine('            activeFilters.delete(status);')
    [void]$sb.AppendLine('            btn.classList.remove("active");')
    [void]$sb.AppendLine('        } else {')
    [void]$sb.AppendLine('            activeFilters.add(status);')
    [void]$sb.AppendLine('            btn.classList.add("active");')
    [void]$sb.AppendLine('        }')
    [void]$sb.AppendLine('        if (activeFilters.size === 0 && allBtn) { allBtn.classList.add("active"); }')
    [void]$sb.AppendLine('    }')
    [void]$sb.AppendLine('    applyFilters();')
    [void]$sb.AppendLine('}')
    [void]$sb.AppendLine('function switchTab(tabId) {')
    [void]$sb.AppendLine('    document.querySelectorAll(".tab-content").forEach(function(t) { t.classList.remove("active"); });')
    [void]$sb.AppendLine('    document.querySelectorAll(".tab-btn").forEach(function(b) { b.classList.remove("active"); });')
    [void]$sb.AppendLine('    var tab = document.getElementById("tab-" + tabId);')
    [void]$sb.AppendLine('    if (tab) tab.classList.add("active");')
    [void]$sb.AppendLine('    event.target.classList.add("active");')
    [void]$sb.AppendLine('}')
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
    [void]$sb.AppendLine('// Apply filters FIRST to hide deprecated rows (must run before any cosmetic JS)')
    [void]$sb.AppendLine('applyFilters();')
    [void]$sb.AppendLine('// Syntax highlighting and copy buttons (wrapped in try/catch to never block filters)')
    [void]$sb.AppendLine('try {')
    [void]$sb.AppendLine('    document.querySelectorAll(".ps-code code").forEach(highlightPS);')
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
    [void]$sb.AppendLine('</script>')

    # ── Close body/html ────────────────────────────────────────────────────
    [void]$sb.AppendLine('</body>')
    [void]$sb.AppendLine('</html>')

    return $sb.ToString()
}
