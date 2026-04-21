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
/* ── Design tokens (single source, light-dark ready) ─────────────── */
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
    /* Semantic — functional */
    --ok:      oklch(0.55 0.15 155);
    --ok-bg:   oklch(0.55 0.15 155 / 0.08);
    --warn:    oklch(0.60 0.16 70);
    --warn-bg: oklch(0.60 0.16 70 / 0.08);
    --bad:     oklch(0.55 0.20 25);
    --bad-bg:  oklch(0.55 0.20 25 / 0.07);
    --info:    oklch(0.55 0.14 250);
    --info-bg: oklch(0.55 0.14 250 / 0.08);
    --manual:  oklch(0.55 0.15 310);
    --manual-bg: oklch(0.55 0.15 310 / 0.08);
    /* Source = Inforcer blue, Dest = Inforcer purple */
    --source:    oklch(0.55 0.16 240);
    --source-bg: oklch(0.55 0.16 240 / 0.08);
    --dest:      oklch(0.52 0.17 295);
    --dest-bg:   oklch(0.52 0.17 295 / 0.08);
    /* Legacy aliases (used by existing JS/HTML class names) */
    --success: oklch(0.55 0.15 155);
    --success-bg: oklch(0.55 0.15 155 / 0.08);
    --warning: oklch(0.60 0.16 70);
    --warning-bg: oklch(0.60 0.16 70 / 0.08);
    --danger: oklch(0.55 0.20 25);
    --danger-bg: oklch(0.55 0.20 25 / 0.07);
    --muted: oklch(0.55 0.01 250);
    --bg-card: oklch(1.0 0 0);
    --header-bg: oklch(0.94 0.006 250);
    --badge-bg: oklch(0.55 0.14 175 / 0.08);
    --badge-text: oklch(0.55 0.14 175);
    --summary-hover: oklch(0.55 0.14 175 / 0.05);
    /* Spacing scale (4pt) */
    --sp-2: 0.125rem;
    --sp-4: 0.25rem;
    --sp-8: 0.5rem;
    --sp-12: 0.75rem;
    --sp-16: 1rem;
    --sp-24: 1.5rem;
    --sp-32: 2rem;
    --sp-48: 3rem;
    /* Type scale — 6 steps */
    --text-xs:  0.7rem;
    --text-sm:  0.8125rem;
    --text-base: 0.875rem;
    --text-md:  1rem;
    --text-lg:  1.25rem;
    --text-xl:  1.5rem;
    /* Radii */
    --radius:    8px;
    --radius-sm: 5px;
    --radius-xs: 5px;
    /* Shadows — minimal, 2-tier */
    --shadow: 0 1px 3px oklch(0.20 0 0 / 0.06);
    --shadow-md: 0 2px 8px oklch(0.20 0 0 / 0.08);
    --transition: 150ms ease;
    /* Row */
    --row-alt: oklch(0.93 0.025 248);
    --row-hover: oklch(0.52 0.18 250 / 0.08);
}
/* ── Dark theme — Inforcer branded gradient ────────────────────── */
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
    --manual:  oklch(0.72 0.14 310);
    --manual-bg: oklch(0.72 0.14 310 / 0.10);
    --source:    oklch(0.72 0.14 240);
    --source-bg: oklch(0.72 0.14 240 / 0.10);
    --dest:      oklch(0.70 0.14 295);
    --dest-bg:   oklch(0.70 0.14 295 / 0.10);
    /* Legacy aliases */
    --success: oklch(0.72 0.15 155);
    --success-bg: oklch(0.72 0.15 155 / 0.10);
    --warning: oklch(0.75 0.14 70);
    --warning-bg: oklch(0.75 0.14 70 / 0.10);
    --danger: oklch(0.70 0.18 25);
    --danger-bg: oklch(0.70 0.18 25 / 0.08);
    --muted: oklch(0.50 0.015 250);
    --bg-card: oklch(0.18 0.025 255);
    --header-bg: oklch(0.11 0.018 255);
    --badge-bg: oklch(0.68 0.16 250 / 0.12);
    --badge-text: oklch(0.68 0.16 250);
    --summary-hover: oklch(0.68 0.16 250 / 0.07);
    --shadow: 0 1px 3px oklch(0 0 0 / 0.30);
    --shadow-md: 0 2px 8px oklch(0 0 0 / 0.40);
    --row-alt: oklch(0.15 0.025 258);
    --row-hover: oklch(0.68 0.16 250 / 0.08);
}
/* ── Reduced motion ──────────────────────────────────────────────── */
@media (prefers-reduced-motion: reduce) {
    *, *::before, *::after { transition-duration: 0ms !important; animation-duration: 0ms !important; }
}
/* ── Base ─────────────────────────────────────────────────────────── */
*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
@font-face { font-family: 'Report'; src: local('Geist'), local('Inter'), local('Segoe UI'); font-display: swap; }
body {
    font-family: 'Report', system-ui, sans-serif;
    background: var(--bg);
    color: var(--text);
    max-width: 1600px;
    margin: 0 auto;
    padding: var(--sp-24) var(--sp-32) var(--sp-48);
    line-height: 1.5;
    font-size: var(--text-base);
    -webkit-font-smoothing: antialiased;
}
/* Inforcer branded gradient bar — top of page */
.brand-bar {
    position: fixed; top: 0; left: 0; right: 0; height: 4px; z-index: 100;
    background: linear-gradient(90deg, oklch(0.65 0.15 220), oklch(0.52 0.18 250), oklch(0.50 0.18 290));
}
:root.dark .brand-bar {
    background: linear-gradient(90deg, oklch(0.55 0.14 210), oklch(0.45 0.18 255), oklch(0.48 0.16 295));
}
:root.dark body {
    background: linear-gradient(145deg, oklch(0.12 0.04 250) 0%, oklch(0.10 0.05 260) 35%, oklch(0.11 0.06 275) 65%, oklch(0.13 0.07 295) 100%);
    background-attachment: fixed;
    min-height: 100vh;
}
/* ── Theme toggle ────────────────────────────────────────────────── */
.theme-toggle {
    position: fixed; top: var(--sp-12); right: var(--sp-12); z-index: 50;
    width: 32px; height: 32px; border-radius: 50%;
    border: 1px solid var(--border); background: var(--bg-raised);
    color: var(--text); cursor: pointer;
    display: flex; align-items: center; justify-content: center;
    transition: border-color var(--transition), box-shadow var(--transition);
    font-size: var(--text-sm); box-shadow: var(--shadow);
}
.theme-toggle:hover { border-color: var(--accent); }
.theme-toggle:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
/* ── Header — compact, informational ─────────────────────────────── */
.report-header {
    display: flex; align-items: baseline; justify-content: space-between;
    gap: var(--sp-16); flex-wrap: wrap;
    padding-bottom: var(--sp-16);
    border-bottom: 2px solid var(--border);
    margin-bottom: var(--sp-24);
}
.report-header h1 {
    font-size: var(--text-lg); font-weight: 700; letter-spacing: -0.02em;
    display: flex; align-items: baseline; gap: var(--sp-8);
}
.report-header h1 .env-name { color: var(--text); }
.report-header h1 .env-arrow { color: var(--text-muted); font-weight: 400; font-size: var(--text-base); }
.report-meta { font-size: var(--text-xs); color: var(--text-muted); text-align: right; }
/* ── Action bar ─────────────────────────────────────────────────── */
.action-bar {
    display: flex; gap: var(--sp-16); align-items: stretch;
    margin-bottom: var(--sp-24);
}
.action-card {
    flex: 1; padding: var(--sp-16);
    background: var(--bg-raised);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    display: flex; flex-direction: column; gap: var(--sp-4);
}
.action-card:focus-within { border-color: var(--accent); }
.action-card .ac-number {
    font-size: var(--text-xl); font-weight: 700;
    font-variant-numeric: tabular-nums; line-height: 1.1;
}
.action-card .ac-label {
    font-size: var(--text-xs); color: var(--text-secondary);
    font-weight: 500;
}
.action-card .ac-detail {
    font-size: var(--text-xs); color: var(--text-muted);
    margin-top: auto;
}
.action-card.card-bad { border-top: 3px solid var(--bad); }
.action-card.card-bad .ac-number { color: var(--bad); }
.action-card.card-source { border-top: 3px solid var(--source); }
.action-card.card-source .ac-number { color: var(--source); }
.action-card.card-dest { border-top: 3px solid var(--dest); }
.action-card.card-dest .ac-number { color: var(--dest); }
.action-card.card-ok .ac-number { color: var(--ok); }
.action-card.card-ok .ac-detail { color: var(--ok); }
.action-card.card-manual { border-top: 3px solid var(--manual); }
.action-card.card-manual .ac-number { color: var(--manual); }
/* Alignment compact — inline, not hero */
.alignment-inline {
    display: flex; align-items: center; gap: var(--sp-8);
    font-size: var(--text-sm); color: var(--text-secondary);
    margin-bottom: var(--sp-24);
}
.alignment-bar {
    flex: 1; max-width: 300px; height: 6px;
    background: var(--border); border-radius: 99px; overflow: hidden;
}
.alignment-fill { height: 100%; border-radius: 99px; background: var(--ok); transition: width 0.4s ease; }
.alignment-pct { font-weight: 600; font-variant-numeric: tabular-nums; color: var(--text); min-width: 3ch; }
/* ── Tab navigation ──────────────────────────────────────────────── */
.tab-nav {
    display: flex; gap: 0;
    border-bottom: 1px solid var(--border);
    margin-bottom: var(--sp-16);
}
.tab-btn {
    padding: var(--sp-8) var(--sp-16);
    background: none; border: none;
    border-bottom: 2px solid transparent;
    margin-bottom: -1px;
    color: var(--text-muted);
    font-size: var(--text-sm); font-weight: 500;
    cursor: pointer; font-family: inherit;
    transition: color var(--transition), border-color var(--transition);
}
.tab-btn:hover { color: var(--text); }
.tab-btn:focus-visible { outline: 2px solid var(--accent); outline-offset: -2px; }
.tab-btn.active { color: var(--accent); border-bottom-color: var(--accent); }
.tab-btn .count {
    display: inline-flex; align-items: center; justify-content: center;
    min-width: 1.5em; padding: 0 0.4em;
    font-size: var(--text-xs); font-weight: 600;
    border-radius: 99px; margin-left: var(--sp-4);
}
.tab-btn .count-bad { background: var(--bad-bg); color: var(--bad); }
.tab-btn .count-warn { background: var(--warn-bg); color: var(--warn); }
.tab-btn .count-info { background: var(--info-bg); color: var(--info); }
.tab-btn .count-manual { background: var(--manual-bg); color: var(--manual); }
.tab-btn .status-badge { pointer-events:none; }
.tab-content { display: none; }
.tab-content.active { display: block; }
/* ── Filter bar ──────────────────────────────────────────────────── */
.filter-bar {
    display: flex; align-items: center; gap: var(--sp-8);
    padding: var(--sp-8) 0; margin-bottom: var(--sp-12);
    flex-wrap: wrap;
}
.search {
    width: 200px; padding: 5px 10px;
    border: 1px solid var(--border); border-radius: var(--radius-sm);
    background: var(--bg-raised); color: var(--text);
    font-size: var(--text-sm); font-family: inherit; outline: none;
    transition: border-color var(--transition);
}
.search:focus { border-color: var(--accent); }
.search:focus-visible { outline: 2px solid var(--accent); outline-offset: -2px; }
.search-hidden { display: none !important; }
.filter-pill {
    padding: 4px 10px; border: 1px solid var(--border);
    border-radius: var(--radius-sm); background: transparent;
    color: var(--text-muted); font-size: var(--text-xs);
    font-weight: 600; cursor: pointer; font-family: inherit;
    transition: all var(--transition);
}
.filter-pill:hover { border-color: var(--text-secondary); color: var(--text-secondary); }
.filter-pill:focus-visible { outline: 2px solid var(--accent); outline-offset: 1px; }
.filter-pill.active { color: oklch(1 0 0); }
.filter-pill-matched.active   { background: var(--ok); border-color: var(--ok); }
.filter-pill-conflicting.active { background: var(--bad); border-color: var(--bad); }
.filter-pill-source-only.active { background: var(--source); border-color: var(--source); }
.filter-pill-dest-only.active { background: var(--dest); border-color: var(--dest); }
.hidden { display: none !important; }
/* ── Category groups ─────────────────────────────────────────────── */
.category-group { margin-bottom: var(--sp-24); }
.category-header {
    display: flex; align-items: center; gap: var(--sp-8);
    padding: var(--sp-8) 0;
    border-bottom: 1px solid var(--border);
    margin-bottom: var(--sp-8);
    cursor: pointer;
}
.category-header:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
.category-chevron {
    font-size: var(--text-xs); color: var(--text-muted);
    transition: transform var(--transition);
    display: inline-block; width: 1em; text-align: center;
}
.category-group.open .category-chevron { transform: rotate(90deg); }
.category-name {
    font-size: var(--text-sm); font-weight: 600;
    color: var(--text-secondary); text-transform: uppercase;
    letter-spacing: 0.04em;
}
.category-stats {
    display: flex; gap: var(--sp-12); margin-left: auto;
    font-size: var(--text-xs); font-variant-numeric: tabular-nums;
}
.cat-stat { display: flex; align-items: center; gap: 3px; }
.cat-stat-dot { width: 6px; height: 6px; border-radius: 50%; }
.cat-stat-dot.dot-bad { background: var(--bad); }
.cat-stat-dot.dot-ok { background: var(--ok); }
.cat-stat-dot.dot-source { background: var(--source); }
.cat-stat-dot.dot-dest { background: var(--dest); }
.category-body { display: none; }
.category-group.open .category-body { display: block; }
/* ── Table ────────────────────────────────────────────────────────── */
.table-wrap { overflow-x: auto; border: 1px solid var(--border); border-radius: var(--radius); margin-bottom: 0.75rem; }
table { width: 100%; border-collapse: collapse; font-size: var(--text-sm); min-width: 400px; }
thead { position: sticky; top: 0; z-index: 5; }
th {
    background: var(--bg-sunken); text-align: left;
    padding: var(--sp-8) var(--sp-12);
    font-weight: 600; font-size: var(--text-xs);
    text-transform: uppercase; letter-spacing: 0.04em;
    color: var(--text-muted);
    border-bottom: 1px solid var(--border);
    white-space: nowrap; user-select: none; position: relative;
}
th[onclick]:hover { color: var(--text); cursor: pointer; }
th:focus-visible { outline: 2px solid var(--accent); outline-offset: -2px; }
td {
    padding: var(--sp-4) var(--sp-12);
    border-bottom: 1px solid var(--border-subtle);
    vertical-align: top; color: var(--text); word-break: break-word;
}
tr:last-child td { border-bottom: none; }
tr:nth-child(even) td { background: var(--row-alt); }
tr:hover td { background: var(--row-hover); }
/* Status indicators */
.status-badge {
    display: inline-flex; align-items: center; gap: 5px;
    font-size: var(--text-xs); font-weight: 600; white-space: nowrap;
}
.status-dot { width: 8px; height: 8px; border-radius: 50%; display: inline-block; flex-shrink: 0; }
.status-matched { color: var(--ok); }
.status-matched .status-dot { background: var(--ok); }
.status-conflicting { color: var(--bad); }
.status-conflicting .status-dot { background: var(--bad); }
.status-source-only { color: var(--source); }
.status-source-only .status-dot { background: var(--source); }
.status-dest-only { color: var(--dest); }
.status-dest-only .status-dot { background: var(--dest); }
.status-manual { color: var(--manual); }
.status-manual .status-dot { background: var(--manual); }
/* Setting cell */
.setting-name { color: var(--text-secondary); }
.setting-name strong { font-weight: 500; color: var(--text); }
.setting-path {
    display: block; font-size: var(--text-xs); color: var(--text-muted);
    margin-top: 1px; word-break: break-word;
}
/* Value cell */
.value-cell { font-family: 'Cascadia Code', 'Fira Code', 'SF Mono', monospace; font-size: var(--text-xs); word-break: break-word; }
.value-truncate { max-height: 4.5em; overflow: hidden; position: relative; }
.value-truncate.expanded { max-height: none; white-space: pre-wrap; }
.value-toggle-btn {
    display: inline-flex; align-items: center; gap: 0.25rem;
    font-size: var(--text-xs); font-weight: 400; color: var(--warn);
    background: none; border: none; padding: 0; cursor: pointer;
    transition: opacity var(--transition); font-family: inherit;
}
.value-toggle-btn:hover { opacity: 0.75; }
.value-actions { display: flex; align-items: center; gap: 0.5rem; margin-top: 0.25rem; }
.value-copy-btn {
    display: inline-flex; align-items: center; gap: 0.25rem;
    font-size: var(--text-xs); font-weight: 400; color: var(--text-muted);
    background: none; border: none; padding: 0; cursor: pointer;
    opacity: 0; transition: opacity var(--transition), color var(--transition);
    font-family: inherit;
}
.value-copy-btn:hover { color: var(--text); }
.value-copy-btn.copied { color: var(--ok); opacity: 1; }
td.value-cell:hover .value-copy-btn { opacity: 1; }
.value-diff { color: var(--bad); font-weight: 600; }
/* Policy name */
.policy-name { font-weight: 600; font-size: var(--text-xs); }
/* Duplicate badge */
.badge-duplicate {
    font-size: 0.65rem; font-weight: 600; padding: 1px 6px;
    border-radius: var(--radius-sm);
    background: var(--warn-bg); color: var(--warn);
    cursor: help; white-space: nowrap;
}
/* Deprecated badge */
.badge-deprecated {
    font-size: 0.65rem; font-weight: 600; padding: 1px 6px;
    border-radius: var(--radius-sm);
    background: var(--bad-bg); color: var(--bad);
    white-space: nowrap;
}
/* ── Code blocks ──────────────────────────────────────────────────── */
.ps-code { background: #1e1e1e !important; color: #d4d4d4; }
.ps-code-summary { color: #569cd6; border: 1px solid #569cd6; background: rgba(86,156,214,0.1); }
.ps-code-summary:hover { background: #569cd6; color: #1e1e1e; }
.sh-code { background: #0d1117 !important; color: #c9d1d9; }
.sh-code-summary { color: #ff7b72; border: 1px solid #ff7b72; background: rgba(255,123,114,0.1); }
.sh-code-summary:hover { background: #ff7b72; color: #0d1117; }
.json-code { background: #1a1b26 !important; color: #a9b1d6; }
.json-code-summary { color: #7aa2f7; border: 1px solid #7aa2f7; background: rgba(122,162,247,0.1); }
.json-code-summary:hover { background: #7aa2f7; color: #1a1b26; }
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
.ps-code-wrap { position: relative; }
.copy-btn { position: absolute; top: 0.5rem; right: 0.5rem; padding: 0.25rem 0.75rem; font-size: var(--text-xs); background: var(--accent); color: oklch(1 0 0); border: none; border-radius: var(--radius-sm); cursor: pointer; opacity: 0.7; transition: opacity var(--transition); z-index: 1; }
.copy-btn:hover { opacity: 1; }
.sh-keyword { color: #ff7b72; font-weight: 600; }
.sh-string { color: #a5d6ff; }
.sh-variable { color: #ffa657; }
.sh-command { color: #d2a8ff; }
.sh-comment { color: #8b949e; font-style: italic; }
.code-lang-label { display: inline-block; padding: 0.25rem 0.5rem; font-size: var(--text-xs); font-weight: 400; text-transform: uppercase; letter-spacing: 0.06em; color: var(--text-muted); background: var(--bg-raised); border-bottom: 1px solid var(--border); border-radius: var(--radius-sm) var(--radius-sm) 0 0; user-select: none; }
/* ── Manual review ───────────────────────────────────────────────── */
.manual-table td { vertical-align: middle; }
.env-label {
    font-size: var(--text-xs); font-weight: 700; text-transform: uppercase; letter-spacing: 0.08em;
    padding: 0.125rem 0.5rem; border-radius: 4px; display: inline-block; text-align: center; min-width: 3.25rem;
}
.env-source { background: var(--source-bg); color: var(--source); }
.env-dest { background: var(--dest-bg); color: var(--dest); }
.policy-type-badge {
    font-size: var(--text-xs); font-weight: 600; padding: 0.125rem 0.5rem;
    border-radius: 999px; white-space: nowrap; display: inline-block;
}
.type-catalog { background: var(--ok-bg); color: var(--ok); }
.type-admin { background: var(--warn-bg); color: var(--warn); }
.type-other { background: var(--badge-bg); color: var(--badge-text); }
.manual-reason { font-size: var(--text-sm); color: var(--text-secondary); }
/* ── Footer ──────────────────────────────────────────────────────── */
.footer {
    margin-top: var(--sp-48); padding-top: var(--sp-16);
    border-top: 1px solid var(--border);
    font-size: var(--text-xs); color: var(--text-muted);
    display: flex; justify-content: space-between;
}
/* ── Scroll to top ───────────────────────────────────────────────── */
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
/* ── Manual review cards ─────────────────────────────────────────── */
.manual-review-card { background: var(--bg-raised); border: 1px solid var(--border); border-radius: var(--radius); padding: 0; margin-bottom: var(--sp-8); overflow: hidden; }
.manual-review-card summary { padding: var(--sp-12) var(--sp-16); font-size: var(--text-sm); cursor: pointer; list-style: none; display: flex; align-items: center; gap: var(--sp-8); user-select: text; transition: background var(--transition); }
.manual-review-card summary strong { cursor: text; }
.manual-review-card summary::-webkit-details-marker { display: none; }
.manual-review-card summary::before { content: '\25B6'; font-size: var(--text-xs); color: var(--text-muted); transition: transform var(--transition); }
.manual-review-card[open] summary::before { transform: rotate(90deg); }
.manual-review-card[open] summary { border-bottom: 1px solid var(--border-subtle); }
.manual-review-card summary:hover { background: var(--row-hover); }
.manual-review-card .mr-body { padding: var(--sp-16); overflow-x: hidden; overflow-y: visible; }
.manual-review-card .side-badge { display: inline-block; padding: 0.125rem 0.5rem; border-radius: 999px; font-size: var(--text-xs); font-weight: 600; }
.manual-review-card .side-source { background: var(--source-bg); color: var(--source); }
.manual-review-card .side-dest { background: var(--dest-bg); color: var(--dest); }
.mr-split { display: grid; grid-template-columns: 1fr 1fr; gap: var(--sp-16); }
.mr-split-col h4 { font-size: var(--text-sm); margin: 0 0 var(--sp-8); padding: var(--sp-4) var(--sp-8); border-radius: var(--radius-sm); }
.mr-split-col.mr-col-source h4 { background: var(--source-bg); color: var(--source); }
.mr-split-col.mr-col-dest h4 { background: var(--dest-bg); color: var(--dest); }
.mr-split-header { display: grid; grid-template-columns: 1fr 1fr; gap: var(--sp-16); }
.mr-split-row { display: grid; grid-template-columns: 1fr 1fr; gap: var(--sp-16); align-items: start; }
.mr-split-row .mr-split-cell { min-height: 0; min-width: 0; overflow-x: hidden; overflow-y: visible; }
.mr-independent-cols { display: grid; grid-template-columns: 1fr 1fr; gap: var(--sp-16); align-items: start; }
.mr-col-flow { display: flex; flex-direction: column; gap: 0; }
.mr-split-cell .script-collapsible pre, .mr-split-col .script-collapsible pre, .mr-body .script-collapsible pre { max-width: 100%; overflow-x: auto; }
.mr-platform-section { margin-bottom: var(--sp-16); }
.mr-platform-section > summary { font-size: var(--text-md); cursor: pointer; padding: var(--sp-8) 0; border-bottom: 1px solid var(--border-subtle); }
.manual-review-setting { display: grid; grid-template-columns: 1fr 1fr; gap: var(--sp-8); padding: 3px 0; border-bottom: 1px solid var(--border-subtle); font-size: var(--text-sm); }
.manual-review-setting .setting-name { color: var(--text); font-weight: 500; }
.manual-review-setting .setting-value { color: var(--text-secondary); word-break: break-word; font-family: 'Cascadia Code','Fira Code','SF Mono',monospace; font-size: var(--text-xs); }
.setting-value.val-true { font-weight: 600; color: var(--accent); background: var(--accent-soft); padding: 1px 8px; border-radius: 4px; }
.setting-value.val-false { color: var(--text-muted); opacity: 0.6; }
.manual-review-setting:nth-child(even) { background: var(--row-alt); }
.setting-deprecated { background: transparent !important; padding: var(--sp-4) var(--sp-8); margin: 0.1rem 0; }
.setting-deprecated .setting-name { color: var(--bad); font-weight: 600; }
/* ── Assignment display ──────────────────────────────────────────── */
.assign-row { display: flex; flex-direction: column; gap: 2px; min-width: 0; }
.assign-cell-wrap { display: flex; flex-direction: column; gap: 4px; }
.assign-include { font-size: var(--text-xs); color: var(--text); }
.assign-exclude { font-size: var(--text-xs); color: var(--bad); }
.assign-all { font-size: var(--text-xs); color: var(--source); }
.assign-filter { display: block; font-size: var(--text-xs); color: var(--text-muted); white-space: normal; word-break: break-word; }
.assign-empty { font-size: var(--text-xs); color: var(--text-muted); }
table.hide-assignments .col-assign { display: none; }
.col-assign { overflow:hidden; text-overflow:ellipsis; word-wrap:break-word; }
/* ── Category filter dropdown ────────────────────────────────────── */
.cat-multiselect { position:relative; display:inline-block; }
.cat-ms-btn { padding:4px 12px; border:1px solid var(--border); border-radius:var(--radius-sm); background:var(--bg-raised); color:var(--text); font-size:var(--text-xs); font-family:inherit; cursor:pointer; font-weight:600; min-width:140px; text-align:left; transition:all var(--transition); }
.cat-ms-btn:hover { border-color:var(--accent); background:var(--accent-soft); }
.cat-ms-btn .cat-count { display:inline-block; background:var(--accent); color:oklch(1 0 0); font-size:var(--text-xs); padding:1px 6px; border-radius:999px; margin-left:6px; font-weight:700; }
.cat-ms-dropdown { position:absolute; top:calc(100% + 4px); left:0; z-index:100; background:var(--bg-raised); border:1px solid var(--border); border-radius:var(--radius); box-shadow:var(--shadow-md); max-height:0; overflow:hidden; min-width:300px; opacity:0; transition:max-height 0.25s ease, opacity 0.2s ease; }
.cat-ms-dropdown.open { max-height:340px; overflow-y:auto; opacity:1; }
.cat-ms-dropdown .cat-search { width:calc(100% - 16px); margin:8px; padding:4px 8px; border:1px solid var(--border); border-radius:var(--radius-sm); font-size:var(--text-xs); background:var(--bg); color:var(--text); font-family:inherit; outline:none; }
.cat-ms-dropdown .cat-search:focus { border-color:var(--accent); }
.cat-ms-dropdown label { display:flex; align-items:center; gap:8px; padding:6px 12px; font-size:var(--text-xs); cursor:pointer; white-space:nowrap; transition:background 0.15s; border-radius:4px; margin:0 4px; }
.cat-ms-dropdown label:hover { background:var(--accent-soft); }
.cat-ms-dropdown input[type=checkbox] { appearance:none; -webkit-appearance:none; width:16px; height:16px; border:2px solid var(--border); border-radius:4px; cursor:pointer; position:relative; flex-shrink:0; transition:all 0.15s; }
.cat-ms-dropdown input[type=checkbox]:checked { background:var(--accent); border-color:var(--accent); }
.cat-ms-dropdown input[type=checkbox]:checked::after { content:'\2713'; position:absolute; top:-1px; left:2px; color:oklch(1 0 0); font-size:11px; font-weight:700; }
/* ── Toggle switch ───────────────────────────────────────────────── */
.toggle-switch { position:relative; width:34px; height:18px; flex-shrink:0; }
.toggle-switch input { position:absolute; clip:rect(0,0,0,0); width:1px; height:1px; overflow:hidden; }
.toggle-switch .slider { position:absolute; inset:0; background:var(--border); border-radius:999px; cursor:pointer; transition:var(--transition); }
.toggle-switch .slider::before { content:''; position:absolute; left:2px; top:2px; width:14px; height:14px; background:var(--bg-raised); border-radius:50%; transition:var(--transition); }
.toggle-switch input:checked + .slider { background:var(--accent); }
.toggle-switch input:checked + .slider::before { transform:translateX(16px); }
/* ── Advanced filters ────────────────────────────────────────────── */
.adv-filter-wrap { display:inline-block; position:relative; }
.adv-filter-btn { border:1px solid var(--border); border-radius:var(--radius-sm); background:var(--bg-raised); color:var(--text); padding:4px 10px; font-size:var(--text-xs); font-family:inherit; cursor:pointer; transition:var(--transition); }
.adv-filter-btn:hover { border-color:var(--text); }
.adv-filter-menu { position:absolute; top:100%; left:0; z-index:100; background:var(--bg-raised); border:1px solid var(--border); border-radius:var(--radius); box-shadow:var(--shadow-md); min-width:160px; padding:4px 0; display:none; }
.adv-filter-menu.open { display:block; }
.adv-filter-menu button { display:block; width:100%; text-align:left; padding:6px 12px; border:none; background:none; font-size:var(--text-sm); color:var(--text); cursor:pointer; font-family:inherit; }
.adv-filter-menu button:hover:not(:disabled) { background:var(--accent-soft); }
.adv-filter-menu button:disabled { opacity:0.4; cursor:default; }
#active-adv-filters { display:flex; flex-wrap:wrap; gap:0.5rem; padding:0 0.75rem; }
#active-adv-filters:empty { display:none; }
.adv-chip { display:inline-flex; align-items:center; gap:4px; background:var(--accent-soft); border:1px solid var(--accent); border-radius:var(--radius-sm); padding:2px 8px; font-size:var(--text-xs); }
.adv-chip label { font-weight:600; color:var(--accent); }
.adv-chip input { border:1px solid var(--border); border-radius:4px; padding:2px 6px; font-size:var(--text-xs); width:140px; background:var(--bg-raised); color:var(--text); font-family:inherit; }
.adv-chip .adv-chip-remove { cursor:pointer; color:var(--bad); font-weight:bold; margin-left:2px; border:none; background:none; font-size:13px; line-height:1; }
.adv-logic-btn { display:inline-flex; align-items:center; justify-content:center; min-width:36px; height:22px; border-radius:11px; cursor:pointer; margin:0 6px; border:none; font-size:9px; font-weight:700; letter-spacing:0.05em; padding:0 8px; transition:all 0.2s; user-select:none; flex-shrink:0; color:oklch(1 0 0); }
.adv-logic-btn[data-mode="AND"] { background:var(--accent); }
.adv-logic-btn[data-mode="OR"] { background:var(--warn); }
.tag-input-wrap { display:flex; flex-wrap:wrap; align-items:center; gap:3px; border:1px solid var(--border); border-radius:4px; padding:2px 4px; min-width:160px; background:var(--bg-raised); cursor:text; }
.tag-input-wrap:focus-within { border-color:var(--accent); }
.tag-input-wrap .tag { display:inline-flex; align-items:center; gap:2px; background:var(--accent); color:oklch(1 0 0); border-radius:3px; padding:1px 4px; font-size:var(--text-xs); white-space:nowrap; }
.tag-input-wrap .tag button { border:none; background:none; color:oklch(1 0 0); cursor:pointer; font-size:11px; line-height:1; padding:0 1px; opacity:0.8; }
.tag-input-wrap .tag button:hover { opacity:1; }
.tag-input-wrap input { border:none; outline:none; font-size:var(--text-xs); background:transparent; color:var(--text); flex:1; min-width:60px; padding:1px 2px; font-family:inherit; }
.adv-dropdown-wrap { position:relative; display:inline-block; }
.adv-dropdown-btn { border:1px solid var(--border); border-radius:4px; padding:3px 10px; font-size:var(--text-xs); background:var(--bg-raised); color:var(--text); cursor:pointer; min-width:100px; text-align:left; font-family:inherit; white-space:nowrap; }
.adv-dropdown-btn:hover { border-color:var(--accent); }
.adv-dropdown-menu { display:none; position:absolute; top:calc(100% + 2px); left:0; z-index:120; background:var(--bg-raised); border:1px solid var(--border); border-radius:var(--radius); box-shadow:var(--shadow-md); padding:6px 0; min-width:180px; max-height:220px; overflow-y:auto; }
.adv-dropdown-menu.open { display:block; }
.adv-dropdown-menu label { display:flex; align-items:center; gap:8px; padding:6px 12px; font-size:var(--text-xs); color:var(--text); cursor:pointer; white-space:nowrap; }
.adv-dropdown-menu label:hover { background:var(--accent-soft); }
.adv-dropdown-menu input[type=checkbox] { width:14px; height:14px; margin:0; accent-color:var(--accent); flex-shrink:0; cursor:pointer; }
/* ── Script collapsible ──────────────────────────────────────────── */
.script-collapsible summary { cursor:pointer; display:flex; align-items:center; gap:0.5rem; list-style:none; padding:0.35rem 0; }
.script-collapsible summary::-webkit-details-marker { display:none; }
.script-collapsible summary::after { content:''; display:inline-block; width:6px; height:6px; border-right:2px solid var(--text-muted); border-bottom:2px solid var(--text-muted); transform:rotate(-45deg); transition:transform 0.2s ease; margin-left:auto; flex-shrink:0; }
.script-collapsible[open] summary::after { transform:rotate(45deg); }
.script-collapsible pre { max-height:25em; overflow:auto; white-space:pre-wrap; word-break:break-all; font-size:var(--text-xs); line-height:1.5; padding:0.75rem; border-radius:var(--radius-sm); margin:0.5rem 0 0; }
/* ── Column resize ───────────────────────────────────────────────── */
.col-resize-handle { position:absolute; top:0; right:-4px; width:8px; height:100%; cursor:col-resize; z-index:10; display:flex; align-items:center; justify-content:center; user-select:none; }
.col-resize-handle::after { content:''; display:block; width:2px; height:60%; border-radius:2px; background:transparent; transition:background 0.15s, height 0.15s; }
.col-resize-handle:hover::after { background:var(--accent); height:100%; }
.col-resize-handle.resizing::after { background:var(--warn); height:100%; width:3px; }
/* ── Details/summary base ────────────────────────────────────────── */
details { border-radius: var(--radius-sm); }
summary {
    cursor: pointer; padding: 0.5rem 0.625rem; border-radius: var(--radius-sm);
    list-style: none; transition: background var(--transition);
}
summary::-webkit-details-marker { display: none; }
summary:not(.script-collapsible summary):not(.mr-category-section summary):not(.mr-platform-section summary)::before {
    content: ''; display: inline-block; width: 0.375rem; height: 0.375rem;
    border-right: 2px solid var(--text-muted); border-bottom: 2px solid var(--text-muted);
    transform: rotate(-45deg); margin-right: 0.625rem; transition: transform var(--transition); flex-shrink: 0;
}
details:not(.script-collapsible):not(.mr-category-section):not(.mr-platform-section)[open] > summary::before { transform: rotate(45deg); }
.script-collapsible summary::before, .mr-category-section > summary::before, .mr-platform-section > summary::before { content: none !important; }
summary:hover { background: var(--row-hover); }
.mr-category-section > summary::-webkit-details-marker { display:none; }
.mr-category-section[open] .cat-chevron { display:inline-block; transform:rotate(90deg); }
h3 {
    font-size: var(--text-sm); font-weight: 600; text-transform: uppercase; letter-spacing: 0.04em;
    color: var(--text-muted); margin: var(--sp-24) 0 var(--sp-8); padding-bottom: var(--sp-4);
    border-bottom: 1px solid var(--border-subtle);
}
h3:first-child { margin-top: var(--sp-4); }
/* ── Compliance table ────────────────────────────────────────────── */
.compliance-table { width: 100%; border-collapse: collapse; font-size: var(--text-xs); margin: 0.5rem 0; }
.compliance-table th { background: var(--bg-sunken); color: var(--text-muted); font-weight: 600; font-size: var(--text-xs); text-transform: uppercase; letter-spacing: 0.05em; padding: var(--sp-4) var(--sp-8); text-align: left; border-bottom: 1px solid var(--border); white-space: nowrap; }
.compliance-table td { padding: var(--sp-4) var(--sp-8); border-bottom: 1px solid var(--border-subtle); color: var(--text-secondary); word-break: break-word; font-family: 'Cascadia Code','Fira Code','SF Mono',monospace; }
.compliance-table tr:last-child td { border-bottom: none; }
/* ── Inline dup table (in MR cards) ──────────────────────────────── */
.dup-table-wrap { overflow-x: auto; margin: 0.5rem 0; }
.dup-table { border-collapse: collapse; font-size: var(--text-xs); min-width: 100%; }
.dup-table th { background: var(--bg-sunken); color: var(--text-muted); font-weight: 600; font-size: var(--text-xs); text-transform: uppercase; letter-spacing: 0.05em; padding: var(--sp-4) var(--sp-8); text-align: left; border-bottom: 1px solid var(--border); white-space: nowrap; }
.dup-table td { padding: var(--sp-4) var(--sp-8); border-bottom: 1px solid var(--border-subtle); color: var(--text-secondary); word-break: break-word; font-family: 'Cascadia Code','Fira Code','SF Mono',monospace; vertical-align: top; }
.dup-table td.dup-setting-name { font-family: inherit; font-weight: 600; color: var(--text); white-space: nowrap; }
.dup-table td.dup-conflict { color: var(--bad); font-weight: 600; }
/* ── Duplicates tab info banner ──────────────────────────────────── */
.dup-info-banner { display:flex; gap:0.75rem; align-items:flex-start; border:1px solid var(--warn); border-radius:var(--radius); background:var(--warn-bg); padding:var(--sp-16); margin-bottom:var(--sp-16); }
.dup-banner-icon { color:var(--warn); font-size:1.1rem; flex-shrink:0; margin-top:0.1rem; }
.dup-banner-title { font-size:var(--text-sm); font-weight:600; color:var(--text); margin:0 0 var(--sp-4); }
.dup-banner-body { font-size:var(--text-sm); color:var(--text-secondary); margin:0 0 var(--sp-4); }
.dup-banner-note { font-size:var(--text-xs); color:var(--text-muted); font-style:italic; margin:0; }
/* ── Duplicates tab: policy-group layout ── */
.dup-summary-bar { display:flex; align-items:center; justify-content:space-between; margin-bottom:0.75rem; }
.dup-summary-bar .dup-stats { display:flex; gap:var(--sp-16); align-items:center; }
.dup-stat-item { display:flex; align-items:baseline; gap:var(--sp-4); }
.dup-stat-item .dup-stat-num { font-size:var(--text-lg); font-weight:700; letter-spacing:-0.02em; }
.dup-stat-item .dup-stat-label { font-size:var(--text-xs); color:var(--text-muted); text-transform:uppercase; letter-spacing:0.04em; }
.dup-stat-item.dup-stat-conflicts .dup-stat-num { color:var(--warn); }
.dup-stat-item.dup-stat-groups .dup-stat-num { color:var(--text-secondary); }
.dup-stat-item.dup-stat-policies .dup-stat-num { color:var(--text-secondary); }
.dup-group { background:var(--bg-raised); border:1px solid var(--border); border-radius:var(--radius); margin-bottom:var(--sp-12); overflow:hidden; }
.dup-group:hover { border-color:var(--text-secondary); }
.dup-group-header { padding:var(--sp-12) var(--sp-16); cursor:pointer; transition:background var(--transition); }
.dup-group-header:hover { background:var(--row-hover); }
.dup-group-header:focus-visible { outline:2px solid var(--accent); outline-offset:-2px; }
.dup-group-title-row { display:flex; align-items:flex-start; justify-content:space-between; margin-bottom:var(--sp-4); }
.dup-group-title { font-size:var(--text-sm); font-weight:600; color:var(--text); }
.dup-group-category { font-size:var(--text-xs); color:var(--text-muted); margin-top:0.1rem; }
.dup-group-chevron { font-size:var(--text-xs); color:var(--text-muted); transition:transform var(--transition); flex-shrink:0; margin-top:0.1rem; }
.dup-group.open .dup-group-chevron { transform:rotate(90deg); }
.dup-chips { display:flex; gap:var(--sp-4); flex-wrap:wrap; margin-bottom:var(--sp-4); }
.dup-chip { display:flex; flex-direction:column; gap:0.15rem; padding:var(--sp-4) var(--sp-8); border-radius:var(--radius-sm); font-size:var(--text-xs); min-width:120px; }
.dup-chip.dup-chip-source { background:var(--source-bg); border:1px solid var(--source); }
.dup-chip.dup-chip-dest { background:var(--dest-bg); border:1px solid var(--dest); }
.dup-chip-id { font-weight:600; font-family:'SF Mono','Cascadia Code','Consolas',monospace; font-size:var(--text-xs); letter-spacing:0.02em; }
.dup-chip-id.dup-chip-id-source { color:var(--source); }
.dup-chip-id.dup-chip-id-dest { color:var(--dest); }
.dup-chip-meta { display:flex; align-items:center; gap:var(--sp-4); color:var(--text-secondary); font-size:var(--text-xs); }
.dup-group-stats { display:flex; align-items:center; gap:0.75rem; font-size:var(--text-xs); }
.dup-conflict-count { display:flex; align-items:center; gap:var(--sp-4); color:var(--warn); font-weight:600; }
.dup-conflict-count .dup-dot { width:5px; height:5px; border-radius:50%; background:var(--warn); }
.dup-match-count { color:var(--text-muted); font-weight:400; }
.dup-group-body { display:none; border-top:1px solid var(--border); overflow-x:auto; }
.dup-group.open .dup-group-body { display:block; }
.dup-matrix { width:100%; border-collapse:collapse; font-size:var(--text-xs); min-width:max-content; }
.dup-matrix thead th { padding:var(--sp-8) var(--sp-8); text-align:left; font-weight:600; font-size:var(--text-xs); color:var(--text-muted); text-transform:uppercase; letter-spacing:0.04em; background:var(--bg-sunken); border-bottom:1px solid var(--border); position:sticky; top:0; z-index:1; white-space:nowrap; }
.dup-matrix thead th.dup-matrix-pol-col { text-align:center; min-width:80px; max-width:120px; }
.dup-matrix thead th.dup-matrix-pol-col .dup-col-id { font-family:'SF Mono','Cascadia Code','Consolas',monospace; font-size:var(--text-xs); display:block; margin-top:0.1rem; font-weight:400; }
.dup-matrix thead th.dup-matrix-pol-col .dup-col-id.dup-col-id-source { color:var(--source); }
.dup-matrix thead th.dup-matrix-pol-col .dup-col-id.dup-col-id-dest { color:var(--dest); }
.dup-matrix tbody tr { border-bottom:1px solid var(--border-subtle); transition:background 0.1s; }
.dup-matrix tbody tr:hover { background:var(--row-hover); }
.dup-matrix tbody tr.dup-has-conflict { background:var(--bad-bg); }
.dup-matrix tbody tr.dup-has-conflict:hover { background:var(--bad-bg); }
.dup-matrix td { padding:var(--sp-4) var(--sp-8); vertical-align:middle; }
.dup-matrix td.dup-matrix-setting { font-weight:500; min-width:180px; max-width:280px; color:var(--text); position:sticky; left:0; background:inherit; z-index:1; }
.dup-matrix td.dup-matrix-value { text-align:center; font-size:var(--text-xs); font-weight:500; white-space:nowrap; }
.dup-value-pill { display:inline-block; padding:0.15rem 0.45rem; border-radius:3px; font-size:var(--text-xs); font-weight:500; max-width:160px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
.dup-value-pill.dup-pill-match { background:var(--ok-bg); color:var(--ok); }
.dup-value-pill.dup-pill-conflict { background:var(--bad-bg); color:var(--bad); border:1px solid var(--bad-bg); }
.dup-value-pill.dup-pill-neutral { background:var(--row-alt); color:var(--text-secondary); }
.dup-all-match-banner { display:flex; align-items:center; gap:var(--sp-4); padding:var(--sp-8) var(--sp-16); font-size:var(--text-xs); color:var(--ok); background:var(--ok-bg); }
.dup-ungrouped-section { margin-top:var(--sp-16); }
.dup-no-results { display:none; padding:var(--sp-48) 0; text-align:center; color:var(--text-muted); font-size:var(--text-sm); }
.dup-setting-path { display:block; font-size:var(--text-xs); color:var(--text-muted); font-weight:400; margin-top:0.125rem; }
/* ── Flat duplicates table ── */
.dup-flat-table { width:100%; border-collapse:collapse; font-size:var(--text-sm); }
.dup-flat-table thead { position:sticky; top:0; z-index:5; }
.dup-flat-table th { background:var(--bg-sunken); text-align:left; padding:var(--sp-8) var(--sp-12); font-weight:600; font-size:var(--text-xs); text-transform:uppercase; letter-spacing:0.04em; color:var(--text-muted); border-bottom:1px solid var(--border); white-space:nowrap; }
.dup-flat-table td { padding:var(--sp-8) var(--sp-12); border-bottom:1px solid var(--border-subtle); vertical-align:top; }
.dup-flat-table tr:last-child td { border-bottom:none; }
.dup-flat-table tr:nth-child(even) td { background:var(--row-alt); }
.dup-flat-table tr:hover td { background:var(--row-hover); }
/* Policy-value entries */
.dup-pv-list { display:flex; flex-direction:column; gap:var(--sp-4); }
.pv-entry { display:grid; grid-template-columns:auto 1fr auto; gap:var(--sp-8); align-items:baseline; font-size:var(--text-xs); }
.pv-side { font-weight:600; font-size:0.625rem; padding:1px 6px; border-radius:3px; text-transform:uppercase; letter-spacing:0.03em; white-space:nowrap; }
.pv-src { background:var(--source-bg); color:var(--source); }
.pv-dst { background:var(--dest-bg); color:var(--dest); }
.pv-policy { color:var(--text-secondary); font-weight:500; word-break:break-word; }
.pv-val { font-family:'Cascadia Code','SF Mono','Consolas',monospace; font-size:var(--text-xs); text-align:right; word-break:break-word; color:var(--text); }
.pv-val-majority { color:var(--ok); }
.pv-val-outlier { color:var(--bad); font-weight:600; }
.dup-cross-tag { font-size:0.6rem; font-weight:600; padding:1px 5px; border-radius:3px; background:var(--warn-bg); color:var(--warn); white-space:nowrap; vertical-align:middle; margin-left:var(--sp-4); }
/* ── Print ────────────────────────────────────────────────────────── */
@media print {
    .theme-toggle, .fab-top, .fab-group, .filter-bar, .tab-nav, #comparison-filters { display: none !important; }
    .tab-content { display: block !important; page-break-inside: avoid; }
    .category-body { display: block !important; }
    .dup-group-body { display: block !important; }
    .manual-review-card .mr-body { display: block !important; }
    body { max-width: none; padding: 0.5cm; font-size: 9pt; }
    .action-card { break-inside: avoid; }
}
/* ── Responsive ──────────────────────────────────────────────────── */
@media (max-width: 768px) {
    body { padding: var(--sp-16); }
    .action-bar { flex-direction: column; }
    .report-header { flex-direction: column; }
    .report-meta { text-align: left; }
    .mr-split { grid-template-columns: 1fr; }
    .mr-independent-cols { grid-template-columns: 1fr; }
    .mr-split-header { grid-template-columns: 1fr; }
}
'@

    # ── Extract model values ───────────────────────────────────────────────
    $sourceName      = [System.Net.WebUtility]::HtmlEncode($ComparisonModel.SourceName)
    $destName        = [System.Net.WebUtility]::HtmlEncode($ComparisonModel.DestinationName)

    # Append baseline name if present
    $sourceBaselineName = $ComparisonModel.SourceBaselineName
    $destBaselineName   = $ComparisonModel.DestinationBaselineName
    if (-not [string]::IsNullOrEmpty($sourceBaselineName)) {
        $sourceName = "$sourceName ($([System.Net.WebUtility]::HtmlEncode($sourceBaselineName)))"
    }
    if (-not [string]::IsNullOrEmpty($destBaselineName)) {
        $destName = "$destName ($([System.Net.WebUtility]::HtmlEncode($destBaselineName)))"
    }
    $generatedAt     = [System.Net.WebUtility]::HtmlEncode($ComparisonModel.GeneratedAt)
    $alignmentScore  = if ($null -ne $ComparisonModel.AlignmentScore) { $ComparisonModel.AlignmentScore } else { 0 }
    $totalItems      = if ($null -ne $ComparisonModel.TotalItems) { $ComparisonModel.TotalItems } else { 0 }
    $matched         = if ($null -ne $ComparisonModel.Counters.Matched) { $ComparisonModel.Counters.Matched } else { 0 }
    $conflicting     = if ($null -ne $ComparisonModel.Counters.Conflicting) { $ComparisonModel.Counters.Conflicting } else { 0 }
    $sourceOnly      = if ($null -ne $ComparisonModel.Counters.SourceOnly) { $ComparisonModel.Counters.SourceOnly } else { 0 }
    $destOnly        = if ($null -ne $ComparisonModel.Counters.DestOnly) { $ComparisonModel.Counters.DestOnly } else { 0 }
    $products        = $ComparisonModel.Products
    $inclAssignments = $ComparisonModel.IncludingAssignments

    # ── Helper: strip setting name from end of path, return parent path + HTML ──
    $getSettingPathHtml = {
        param([string]$SettingPath, [string]$SettingName, [string]$CssClass)
        if (-not $CssClass) { $CssClass = 'setting-path' }
        $displayPath = $SettingPath
        if (-not [string]::IsNullOrEmpty($SettingPath) -and $SettingPath.Contains(' > ')) {
            $lastSep = $SettingPath.LastIndexOf(' > ')
            if ($SettingPath.Substring($lastSep + 3) -eq $SettingName) {
                $displayPath = $SettingPath.Substring(0, $lastSep)
            }
        }
        $encPath = [System.Net.WebUtility]::HtmlEncode($displayPath)
        if (-not [string]::IsNullOrEmpty($displayPath) -and $displayPath -ne $SettingName) {
            return "<span class=`"$CssClass`">$encPath</span>"
        }
        return ''
    }

    # ── Helper: strip __SCRIPT_CODE__ prefix from a raw value ──
    $stripScriptMarker = {
        param([string]$Val)
        if ($Val -match '^__SCRIPT_CODE__') { return $Val.Substring('__SCRIPT_CODE__'.Length) }
        return $Val
    }

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
    [void]$sb.AppendLine('<div class="brand-bar"></div>')

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

    # ── Theme toggle (top-right) ────────────────────────────────────────────
    [void]$sb.AppendLine('<button class="theme-toggle" id="btn-theme" onclick="toggleTheme()" aria-label="Toggle light/dark theme">&#9681;</button>')

    # ── Header — compact flex row ──────────────────────────────────────────
    [void]$sb.AppendLine('<header class="report-header">')
    [void]$sb.AppendLine('    <h1>')
    [void]$sb.AppendLine("        <span class=`"env-name`">$sourceName</span>")
    [void]$sb.AppendLine('        <span class="env-arrow">&#8594;</span>')
    [void]$sb.AppendLine("        <span class=`"env-name`">$destName</span>")
    [void]$sb.AppendLine('    </h1>')
    [void]$sb.AppendLine("    <div class=`"report-meta`">Generated $generatedAt<br>$totalItems settings compared</div>")
    [void]$sb.AppendLine('</header>')

    # ── Action bar — leads with what needs attention ───────────────────────
    [void]$sb.AppendLine('<div class="action-bar">')
    [void]$sb.AppendLine("    <div class=`"action-card card-bad`"><div class=`"ac-number`" id=`"countConflicting`">$conflicting</div><div class=`"ac-label`">Conflicts to resolve</div></div>")
    [void]$sb.AppendLine("    <div class=`"action-card card-source`"><div class=`"ac-number`" id=`"countSource`">$sourceOnly</div><div class=`"ac-label`">Source only</div><div class=`"ac-detail`">Not in destination</div></div>")
    [void]$sb.AppendLine("    <div class=`"action-card card-dest`"><div class=`"ac-number`" id=`"countDest`">$destOnly</div><div class=`"ac-label`">Destination only</div><div class=`"ac-detail`">Not in source</div></div>")
    [void]$sb.AppendLine("    <div class=`"action-card card-ok`"><div class=`"ac-number`" id=`"countMatched`">$matched</div><div class=`"ac-label`">Matched</div><div class=`"ac-detail`" id=`"scoreDetail`">${alignmentScore}% aligned</div></div>")
    [void]$sb.AppendLine('</div>')

    # ── Alignment — compact inline bar ─────────────────────────────────────
    [void]$sb.AppendLine('<div class="alignment-inline">')
    [void]$sb.AppendLine("    <span class=`"alignment-pct`" id=`"scoreNum`">${alignmentScore}%</span>")
    [void]$sb.AppendLine("    <div class=`"alignment-bar`"><div class=`"alignment-fill`" id=`"scoreBar`" style=`"width:${alignmentScore}%`"></div></div>")
    [void]$sb.AppendLine("    <span>$matched of $totalItems settings aligned</span>")
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
    [void]$sb.AppendLine('    <button id="clear-filters-btn" class="hidden" onclick="clearFilters()" style="color:var(--bad);background:none;border:none;font-size:var(--text-xs);font-weight:600;cursor:pointer;padding:var(--sp-4) var(--sp-8)">Clear filters</button>')
    if ($inclAssignments) {
        [void]$sb.AppendLine('    <label style="margin-left:auto;display:flex;align-items:center;gap:0.5rem;font-size:0.75rem;color:var(--text-secondary);cursor:pointer;user-select:none"><span>Exclude unassigned</span><span class="toggle-switch"><input type="checkbox" id="toggle-exclude-unassigned" onchange="applyFilters()"><span class="slider"></span></span></label>')
        [void]$sb.AppendLine('    <label style="margin-left:0.75rem;display:flex;align-items:center;gap:0.5rem;font-size:0.75rem;color:var(--text-secondary);cursor:pointer;user-select:none"><span>Assignments</span><span class="toggle-switch"><input type="checkbox" id="toggle-assignments" checked onchange="toggleAssignments(this.checked)"><span class="slider"></span></span></label>')
    }
    [void]$sb.AppendLine('</div>')
    [void]$sb.AppendLine('<div id="filter-summary" style="font-size:var(--text-xs);font-weight:600;color:var(--text-muted);padding:var(--sp-4) 0;font-variant-numeric:tabular-nums"></div>')
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
        [void]$sb.AppendLine("    <button class=`"tab-btn`" onclick=`"switchTab('manual-review', event)`">Manual Review <span class=`"count count-manual`">$mrCount</span></button>")
    }
    if ($hasDuplicates) {
        [void]$sb.AppendLine("    <button class=`"tab-btn`" onclick=`"switchTab('duplicates', event)`">Duplicates <span class=`"count count-warn`">$dupCount</span></button>")
    }
    if ($hasDeprecated) {
        [void]$sb.AppendLine("    <button class=`"tab-btn`" onclick=`"switchTab('deprecated', event)`">Deprecated <span class=`"count count-bad`">$deprecatedCount</span></button>")
    }
    [void]$sb.AppendLine('</div>')

    # ── Comparison tab ───────────────────────────────────────────────────
    [void]$sb.AppendLine('<div class="tab-content active" id="tab-comparison">')

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

    # Helper: render a single comparison row as <tr>
    $renderComparisonRow = {
        param($rowWrapper, $sb, $inclAssignments, $duplicateLookup, $getSettingPathHtml, $stripScriptMarker, $formatAssignHtml)
        $row = $rowWrapper.Row
        $status = $row.Status

        # Status badge
        switch ($status) {
            'Matched'     { $statusHtml = '<span class="status-badge status-matched"><span class="status-dot"></span>Match</span>' }
            'Conflicting' { $statusHtml = '<span class="status-badge status-conflicting"><span class="status-dot"></span>Conflict</span>' }
            'SourceOnly'  { $statusHtml = '<span class="status-badge status-source-only"><span class="status-dot"></span>Source&nbsp;Only</span>' }
            'DestOnly'    { $statusHtml = '<span class="status-badge status-dest-only"><span class="status-dot"></span>Dest&nbsp;Only</span>' }
            default       { $statusHtml = [System.Net.WebUtility]::HtmlEncode($status) }
        }

        $encName = [System.Net.WebUtility]::HtmlEncode($row.Name)
        $encCategory = [System.Net.WebUtility]::HtmlEncode($rowWrapper.CompositeCategory)
        $srcValRaw = "$($row.SourceValue)".Trim()
        $dstValRaw = "$($row.DestValue)".Trim()
        $bothEmpty = (([string]::IsNullOrEmpty($srcValRaw) -or $srcValRaw -eq [char]0x2014) -and
                      ([string]::IsNullOrEmpty($dstValRaw) -or $dstValRaw -eq [char]0x2014))
        $emptyAttr = if ($bothEmpty) { ' data-empty="true"' } else { '' }
        $encSrcPol = [System.Net.WebUtility]::HtmlEncode($row.SourcePolicy)
        $encDstPol = [System.Net.WebUtility]::HtmlEncode($row.DestPolicy)
        [void]$sb.Append("<tr data-status=`"$status`" data-category=`"$encCategory`" data-src-policy=`"$encSrcPol`" data-dst-policy=`"$encDstPol`"$emptyAttr><td>")
        [void]$sb.Append($statusHtml)
        [void]$sb.Append('</td>')

        # Duplicate badge lookup
        $rowKey = if ($row.SettingPath) { $row.SettingPath.ToLowerInvariant() } else { $row.Name.ToLowerInvariant() }
        $dupeBadge = ''
        if ($duplicateLookup.ContainsKey($rowKey)) {
            $allPolicies = $duplicateLookup[$rowKey]
            $currentPol  = if ($row.SourcePolicy) { $row.SourcePolicy } else { $row.DestPolicy }
            $others = @($allPolicies | Where-Object { $_.Policy -ne $currentPol } |
                      ForEach-Object { "$($_.Policy) ($($_.Side))" })
            $tooltipText = if ($others.Count -gt 0) { "Also configured in: $($others -join ', ')" } else { 'Duplicate setting — see Duplicate Settings tab' }
            $encTooltip  = [System.Net.WebUtility]::HtmlEncode($tooltipText)
            $dupeBadge   = " <span class=`"badge-duplicate`" title=`"$encTooltip`">Dup</span>"
        }

        # Setting name cell
        $deprBadge = if ($row.IsDeprecated -eq $true) { ' <span class="badge-deprecated">Deprecated</span>' } else { '' }
        $pathHtml = & $getSettingPathHtml "$($row.SettingPath)" $row.Name 'setting-path'
        [void]$sb.Append("<td class=`"setting-name`"><strong>$encName</strong>$deprBadge$dupeBadge$pathHtml</td>")

        # Category column
        [void]$sb.Append("<td style=`"font-size:var(--text-xs);color:var(--text-secondary)`">$encCategory</td>")

        # Source columns
        if ($status -eq 'DestOnly') {
            [void]$sb.Append("<td class=`"policy-name`">$encSrcPol</td><td colspan=`"1`"><span class=`"value-cell`" style=`"font-family:inherit;font-style:italic;color:var(--text-muted)`">Not configured</span></td>")
        } else {
            $encSrcPolicy = [System.Net.WebUtility]::HtmlEncode($row.SourcePolicy)
            $rawSrcValue  = if ($null -ne $row.SourceValue) { & $stripScriptMarker "$($row.SourceValue)" } else { '' }
            $encSrcValue  = [System.Net.WebUtility]::HtmlEncode($rawSrcValue)
            $encSrcValueAttr = [System.Net.WebUtility]::HtmlEncode($rawSrcValue)
            [void]$sb.Append("<td class=`"policy-name`">$encSrcPolicy</td>")
            if ($rawSrcValue.Length -gt 100) {
                [void]$sb.Append("<td class=`"value-cell`"><div class=`"value-wrap`"><div class=`"value-truncate`">$encSrcValue</div><div class=`"value-actions`"><button type=`"button`" class=`"value-toggle-btn`">&#9660; More</button><button type=`"button`" class=`"value-copy-btn`" data-value=`"$encSrcValueAttr`">&#128203; Copy</button></div></div></td>")
            } else {
                [void]$sb.Append("<td class=`"value-cell`"><div class=`"value-wrap`"><span class=`"value-text`">$encSrcValue</span><div class=`"value-actions`"><button type=`"button`" class=`"value-copy-btn`" data-value=`"$encSrcValueAttr`">&#128203; Copy</button></div></div></td>")
            }
        }

        # Dest columns
        if ($status -eq 'SourceOnly') {
            [void]$sb.Append("<td class=`"policy-name`">$encDstPol</td><td colspan=`"1`"><span class=`"value-cell`" style=`"font-family:inherit;font-style:italic;color:var(--text-muted)`">Not configured</span></td>")
        } else {
            $encDstPolicy    = [System.Net.WebUtility]::HtmlEncode($row.DestPolicy)
            $rawDstValue     = if ($null -ne $row.DestValue) { & $stripScriptMarker "$($row.DestValue)" } else { '' }
            $encDstValue     = [System.Net.WebUtility]::HtmlEncode($rawDstValue)
            $encDstValueAttr = [System.Net.WebUtility]::HtmlEncode($rawDstValue)
            $innerCls = if ($status -eq 'Conflicting') { ' value-diff' } else { '' }
            [void]$sb.Append("<td class=`"policy-name`">$encDstPolicy</td>")
            if ($rawDstValue.Length -gt 100) {
                [void]$sb.Append("<td class=`"value-cell`"><div class=`"value-wrap`"><div class=`"value-truncate$innerCls`">$encDstValue</div><div class=`"value-actions`"><button type=`"button`" class=`"value-toggle-btn`">&#9660; More</button><button type=`"button`" class=`"value-copy-btn`" data-value=`"$encDstValueAttr`">&#128203; Copy</button></div></div></td>")
            } else {
                [void]$sb.Append("<td class=`"value-cell`"><div class=`"value-wrap`"><span class=`"value-text$innerCls`">$encDstValue</span><div class=`"value-actions`"><button type=`"button`" class=`"value-copy-btn`" data-value=`"$encDstValueAttr`">&#128203; Copy</button></div></div></td>")
            }
        }

        # Assignment column (single combined)
        if ($inclAssignments) {
            $srcAssignHtml = & $formatAssignHtml $row.SourceAssignment
            $dstAssignHtml = & $formatAssignHtml $row.DestAssignment
            [void]$sb.Append("<td class=`"value-cell col-assign`">$srcAssignHtml</td>")
            [void]$sb.Append("<td class=`"value-cell col-assign`">$dstAssignHtml</td>")
        }

        [void]$sb.AppendLine('</tr>')
    }

    if ($allRows.Count -gt 0) {
        [void]$sb.AppendLine('<div class="table-wrap">')
        [void]$sb.AppendLine('<table class="comparison-table" id="comparison-table" style="table-layout:fixed;width:100%">')
        [void]$sb.AppendLine('<thead><tr>')
        if ($inclAssignments) {
            [void]$sb.Append('<th style="width:5%;cursor:pointer" onclick="sortTable(this,0)">Status</th>')
            [void]$sb.Append('<th style="width:19%;cursor:pointer" onclick="sortTable(this,1)">Setting</th>')
            [void]$sb.Append('<th style="width:10%;cursor:pointer" onclick="sortTable(this,2)">Category</th>')
            [void]$sb.Append("<th style=`"width:11%;cursor:pointer`" onclick=`"sortTable(this,3)`">Source Policy</th>")
            [void]$sb.Append("<th style=`"width:12%;cursor:pointer`" onclick=`"sortTable(this,4)`">Source Value</th>")
            [void]$sb.Append("<th style=`"width:11%;cursor:pointer`" onclick=`"sortTable(this,5)`">Dest Policy</th>")
            [void]$sb.Append("<th style=`"width:12%;cursor:pointer`" onclick=`"sortTable(this,6)`">Dest Value</th>")
            [void]$sb.Append("<th class=`"col-assign`" style=`"width:9%`">Src Assignment</th>")
            [void]$sb.Append("<th class=`"col-assign`" style=`"width:9%`">Dst Assignment</th>")
        } else {
            [void]$sb.Append('<th style="width:5%;cursor:pointer" onclick="sortTable(this,0)">Status</th>')
            [void]$sb.Append('<th style="width:22%;cursor:pointer" onclick="sortTable(this,1)">Setting</th>')
            [void]$sb.Append('<th style="width:12%;cursor:pointer" onclick="sortTable(this,2)">Category</th>')
            [void]$sb.Append("<th style=`"width:14%;cursor:pointer`" onclick=`"sortTable(this,3)`">Source Policy</th>")
            [void]$sb.Append("<th style=`"width:15%;cursor:pointer`" onclick=`"sortTable(this,4)`">Source Value</th>")
            [void]$sb.Append("<th style=`"width:14%;cursor:pointer`" onclick=`"sortTable(this,5)`">Dest Policy</th>")
            [void]$sb.Append("<th style=`"width:15%;cursor:pointer`" onclick=`"sortTable(this,6)`">Dest Value</th>")
        }
        [void]$sb.AppendLine('</tr></thead>')
        [void]$sb.AppendLine('<tbody>')

        foreach ($rowWrapper in $allRows) {
            & $renderComparisonRow $rowWrapper $sb $inclAssignments $duplicateLookup $getSettingPathHtml $stripScriptMarker $formatAssignHtml
        }

        [void]$sb.AppendLine('</tbody></table>')
        [void]$sb.AppendLine('</div>')  # end table-wrap
    }

    [void]$sb.AppendLine('</div>')  # end tab-comparison

    # Deprecated policies are now in ManualReview with HasDeprecated flag — no separate tab

    # ── Manual Review tab ─────────────────────────────────────────────────
    if ($hasManualReview) {
        [void]$sb.AppendLine('<div class="tab-content" id="tab-manual-review">')
        [void]$sb.AppendLine('<div class="dup-info-banner" style="border-color:var(--info);background:var(--info-bg)">')
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
                if ($nonDeprCount -eq 0) { return }
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
                    # Strip __SCRIPT_CODE__ marker — store cleaned value for all rendering paths
                    $sValue = "$($s.Value)"
                    $isSettingDepr = $s.IsDeprecated -eq $true
                    # Skip deprecated settings — they have their own dedicated tab
                    if ($isSettingDepr) { continue }
                    # Priority 1: Duplicate table (D-08, D-09, D-10, D-11)
                    if ($sValue -match '^__DUPLICATE_TABLE__') {
                        $dupJson = $sValue.Substring('__DUPLICATE_TABLE__'.Length)
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
                            $encSValue = [System.Net.WebUtility]::HtmlEncode($sValue)
                            [void]$sb.AppendLine("    <div class=`"manual-review-setting`"><span class=`"setting-name`">$encSName</span><span class=`"setting-value`">$encSValue</span></div>")
                        }
                    }
                    # Priority 2: Compliance rules table (D-05, D-06, D-07)
                    elseif ($s.Name -match '(?i)^rules\s*content$') {
                        $rulesRendered = $false
                        try {
                            $parsed = (& $stripScriptMarker $sValue) | ConvertFrom-Json -Depth 10 -ErrorAction Stop
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
                            $encSValue = [System.Net.WebUtility]::HtmlEncode((& $stripScriptMarker $sValue))
                            [void]$sb.AppendLine("    <div class=`"manual-review-setting`"><span class=`"setting-name`">$encSName</span><span class=`"setting-value`">$encSValue</span></div>")
                        }
                    }
                    # Priority 3 & 4: Script content — bash (shebang) vs PowerShell (D-02, D-04, D-01)
                    elseif ($s.Name -match '(?i)script\s*content|detection\s*script\s*content|remediation\s*script\s*content|scriptContent|detectionScriptContent|remediationScriptContent' -and $sValue.Length -gt 100) {
                        $cleanVal = & $stripScriptMarker $sValue
                        $encSValue = [System.Net.WebUtility]::HtmlEncode($cleanVal)
                        $isBash = $cleanVal.TrimStart() -match '^#!'
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
                            $scriptData = $sValue | ConvertFrom-Json -Depth 5 -ErrorAction Stop
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
                            $encSValue = [System.Net.WebUtility]::HtmlEncode($sValue)
                            [void]$sb.AppendLine("    <div class=`"manual-review-setting`"><span class=`"setting-name`">$encSName</span><span class=`"setting-value`">$encSValue</span></div>")
                        }
                    }
                    # Priority 6: Decoded script content — collapsible code block
                    elseif ($sValue -match '^__SCRIPT_CODE__') {
                        $scriptCode = $sValue.Substring('__SCRIPT_CODE__'.Length)
                        $encCode = [System.Net.WebUtility]::HtmlEncode($scriptCode)
                        $trimmedCode = $scriptCode.TrimStart()
                        if ($trimmedCode -match '^\s*[\{\[]') { $codeClass = 'json-code'; $summaryClass = 'json-code-summary'; $codeLabel = 'View JSON' }
                        elseif ($trimmedCode -match '^\s*#!/') { $codeClass = 'sh-code'; $summaryClass = 'sh-code-summary'; $codeLabel = 'View script' }
                        else { $codeClass = 'ps-code'; $summaryClass = 'ps-code-summary'; $codeLabel = 'View script' }
                        [void]$sb.AppendLine("    <div class=`"manual-review-setting`"><span class=`"setting-name`">$encSName</span></div>")
                        [void]$sb.AppendLine("    <details class=`"script-collapsible`"><summary class=`"$summaryClass`">$codeLabel</summary><pre class=`"$codeClass`">$encCode</pre></details>")
                    }
                    # Priority 8: Default key-value display (with boolean styling)
                    else {
                        $encSValue = [System.Net.WebUtility]::HtmlEncode($sValue)
                        $valClass = 'setting-value'
                        $rawVal = $sValue.Trim()
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

                # Build lookup of destination policies by name for pairing
                $destByName = @{}
                foreach ($dp in $destPolicies) { $destByName[$dp.PolicyName] = $dp }
                $matchedDestNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

                # Partition source into matched and unmatched
                $matchedPairs = [System.Collections.Generic.List[object]]::new()
                $unmatchedSource = [System.Collections.Generic.List[object]]::new()
                foreach ($sp in $sourcePolicies) {
                    if ($destByName.ContainsKey($sp.PolicyName)) {
                        $matchedPairs.Add(@{ Source = $sp; Destination = $destByName[$sp.PolicyName] })
                        [void]$matchedDestNames.Add($sp.PolicyName)
                    } else {
                        $unmatchedSource.Add($sp)
                    }
                }
                $unmatchedDest = @($destPolicies | Where-Object { -not $matchedDestNames.Contains($_.PolicyName) })

                # Sort matched pairs and unmatched alphabetically
                $matchedPairs = @($matchedPairs | Sort-Object { $_.Source.PolicyName })
                $unmatchedSource = @($unmatchedSource | Sort-Object PolicyName)
                $unmatchedDest = @($unmatchedDest | Sort-Object PolicyName)

                # Two independent columns — expanding a card on one side does not affect the other
                [void]$sb.AppendLine('<div class="mr-split-header">')
                [void]$sb.AppendLine('<div class="mr-split-col mr-col-source"><h4>Source</h4></div>')
                [void]$sb.AppendLine('<div class="mr-split-col mr-col-dest"><h4>Destination</h4></div>')
                [void]$sb.AppendLine('</div>')

                # Build ordered source and dest lists (matched first, then unmatched)
                $orderedSource = [System.Collections.Generic.List[object]]::new()
                $orderedDest   = [System.Collections.Generic.List[object]]::new()
                foreach ($pair in $matchedPairs) {
                    [void]$orderedSource.Add($pair.Source)
                    [void]$orderedDest.Add($pair.Destination)
                }
                foreach ($sp in $unmatchedSource) { [void]$orderedSource.Add($sp) }
                foreach ($dp in $unmatchedDest)   { [void]$orderedDest.Add($dp) }

                [void]$sb.AppendLine('<div class="mr-independent-cols">')

                # Source column
                [void]$sb.AppendLine('<div class="mr-col-flow">')
                if ($orderedSource.Count -eq 0) {
                    [void]$sb.AppendLine('<div style="color:var(--muted);font-size:0.8rem;font-style:italic;padding:0.5rem">No source policies</div>')
                } else {
                    foreach ($sp in $orderedSource) { & $renderPolicyCard $sp $sb }
                }
                [void]$sb.AppendLine('</div>')

                # Destination column
                [void]$sb.AppendLine('<div class="mr-col-flow">')
                if ($orderedDest.Count -eq 0) {
                    [void]$sb.AppendLine('<div style="color:var(--muted);font-size:0.8rem;font-style:italic;padding:0.5rem">No destination policies</div>')
                } else {
                    foreach ($dp in $orderedDest) { & $renderPolicyCard $dp $sb }
                }
                [void]$sb.AppendLine('</div>')

                [void]$sb.AppendLine('</div>')
                [void]$sb.AppendLine('</details>')  # end mr-category-section
            }
            [void]$sb.AppendLine('</details>')
        }

        [void]$sb.AppendLine('</div>')  # end tab-manual-review
    }

    # ── Duplicates tab content (policy-group-first layout) ─────────────────
    if ($hasDuplicates) {
        # Count unique policy names across all duplicate rows
        $dupPolicyNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($dr in $dupRows) {
            foreach ($p in $dr.Policies) { [void]$dupPolicyNames.Add($p.Policy) }
        }
        $dupPolicyCount = $dupPolicyNames.Count

        # Resolve policy groups and map dupRows into them
        $dupPolGroups = $ComparisonModel.DuplicatePolicies
        $hasGroups = $null -ne $dupPolGroups -and $dupPolGroups.Count -gt 0

        # Build a lookup: for each group, find the dupRows whose policies overlap with the group's policies
        $groupedDupRowKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $groupData = [System.Collections.Generic.List[hashtable]]::new()
        if ($hasGroups) {
            foreach ($group in $dupPolGroups) {
                # Collect the disambiguated policy names from this group
                $groupPolNames = @($group.Policies | ForEach-Object { $_.Name })
                $groupBaseName = $group.PolicyName

                # Find dupRows where at least one policy matches (by disambiguated name or starts with base name)
                $matchedRows = [System.Collections.Generic.List[hashtable]]::new()
                foreach ($dr in $dupRows) {
                    $isMatch = $false
                    foreach ($drp in $dr.Policies) {
                        $drpName = $drp.Policy
                        foreach ($gpn in $groupPolNames) {
                            if ($drpName -eq $gpn -or $drpName.StartsWith($groupBaseName, [System.StringComparison]::OrdinalIgnoreCase)) {
                                $isMatch = $true
                                break
                            }
                        }
                        if ($isMatch) { break }
                    }
                    if ($isMatch) {
                        [void]$matchedRows.Add($dr)
                        [void]$groupedDupRowKeys.Add($dr.Name.ToLowerInvariant())
                    }
                }

                # Compute conflict / match counts for this group
                $groupConflicts = 0
                $groupMatches = 0
                foreach ($mr in $matchedRows) {
                    $vals = @($mr.Policies | ForEach-Object { "$($_.Value)" } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
                    $uniqueVals = @($vals | Select-Object -Unique)
                    if ($uniqueVals.Count -gt 1) { $groupConflicts++ } else { $groupMatches++ }
                }

                [void]$groupData.Add(@{
                    Group      = $group
                    Rows       = $matchedRows
                    Conflicts  = $groupConflicts
                    Matches    = $groupMatches
                })
            }
        }

        # Ungrouped dupRows = any not claimed by a policy group
        $ungroupedRows = [System.Collections.Generic.List[hashtable]]::new()
        foreach ($dr in $dupRows) {
            if (-not $groupedDupRowKeys.Contains($dr.Name.ToLowerInvariant())) {
                [void]$ungroupedRows.Add($dr)
            }
        }

        # Total conflicts across all groups
        $totalConflicts = ($groupData | ForEach-Object { $_.Conflicts } | Measure-Object -Sum).Sum
        $totalGroupCount = $groupData.Count
        $totalPoliciesAffected = $dupPolicyCount

        [void]$sb.AppendLine('<div class="tab-content" id="tab-duplicates">')

        # Description
        [void]$sb.AppendLine('<p style="font-size:var(--text-sm);color:var(--text-secondary);margin-bottom:var(--sp-16);max-width:80ch">Settings configured in multiple policies. When values conflict, Intune applies the most restrictive &mdash; review and align.</p>')

        # Summary strip
        $totalDupConflicts = 0
        foreach ($dr in $dupRows) {
            $drVals = @($dr.Policies | ForEach-Object { "$($_.Value)" } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
            if ($drVals.Count -gt 1) { $totalDupConflicts++ }
        }
        [void]$sb.AppendLine('<div class="dup-summary-bar">')
        [void]$sb.AppendLine("    <div class=`"dup-stat-item dup-stat-conflicts`"><span class=`"dup-stat-num`">$totalDupConflicts</span><span class=`"dup-stat-label`">conflicts</span></div>")
        [void]$sb.AppendLine("    <div class=`"dup-stat-item dup-stat-groups`"><span class=`"dup-stat-num`">$dupCount</span><span class=`"dup-stat-label`">duplicate settings</span></div>")
        [void]$sb.AppendLine("    <div class=`"dup-stat-item dup-stat-policies`"><span class=`"dup-stat-num`">$totalPoliciesAffected</span><span class=`"dup-stat-label`">policies affected</span></div>")
        [void]$sb.AppendLine('    <input class="search" type="text" placeholder="Search duplicates..." oninput="dupTabSearch(this.value)" style="margin-left:auto">')
        [void]$sb.AppendLine('</div>')
        [void]$sb.AppendLine('<div id="dup-no-results" class="dup-no-results">No duplicate settings match your search.</div>')

        # ── Single unified flat table — all duplicates in one table ──
        # Merge grouped + ungrouped into one sorted list (conflicts first)
        $allDupEntries = [System.Collections.Generic.List[hashtable]]::new()
        foreach ($dr in $dupRows) {
            $drVals = @($dr.Policies | ForEach-Object { "$($_.Value)" } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
            $isConflict = $drVals.Count -gt 1
            # Determine category from setting path or group data
            $firstPol = $dr.Policies | Select-Object -First 1
            $drCategory = ''
            if ($firstPol.Category) { $drCategory = $firstPol.Category }
            elseif ($firstPol.SettingPath -and $firstPol.SettingPath.Contains(' > ')) {
                $drCategory = $firstPol.SettingPath.Substring(0, $firstPol.SettingPath.IndexOf(' > '))
            }
            # Check if cross-category (policies span multiple categories)
            $isCrossCategory = $false
            if ($dr.Policies.Count -gt 1) {
                $cats = @($dr.Policies | ForEach-Object {
                    if ($_.Category) { $_.Category }
                    elseif ($_.SettingPath -and $_.SettingPath.Contains(' > ')) { $_.SettingPath.Substring(0, $_.SettingPath.IndexOf(' > ')) }
                    else { '' }
                } | Where-Object { $_ } | Select-Object -Unique)
                if ($cats.Count -gt 1) { $isCrossCategory = $true }
            }
            [void]$allDupEntries.Add(@{
                Row           = $dr
                IsConflict    = $isConflict
                Category      = $drCategory
                IsCross       = $isCrossCategory
            })
        }
        # Sort: conflicts first, then by setting name
        $allDupEntries = @($allDupEntries | Sort-Object @{Expression={-not $_.IsConflict}}, @{Expression={$_.Row.Name}})

        [void]$sb.AppendLine('<div id="dup-groups-container">')
        [void]$sb.AppendLine('<div class="table-wrap">')
        [void]$sb.AppendLine('<table class="dup-flat-table" id="dup-flat-table">')
        [void]$sb.AppendLine('<thead><tr>')
        [void]$sb.AppendLine('<th style="width:6%">Status</th>')
        [void]$sb.AppendLine('<th style="width:22%">Setting</th>')
        [void]$sb.AppendLine('<th style="width:14%">Category</th>')
        [void]$sb.AppendLine('<th style="width:58%">Policies &amp; Values</th>')
        [void]$sb.AppendLine('</tr></thead>')
        [void]$sb.AppendLine('<tbody>')

        foreach ($entry in $allDupEntries) {
            $dr = $entry.Row
            $isConflict = $entry.IsConflict
            $drCategory = $entry.Category
            $isCrossCategory = $entry.IsCross

            # Setting display name
            $firstPol = $dr.Policies | Select-Object -First 1
            $settingPath = if ($firstPol.SettingPath) { $firstPol.SettingPath } else { '' }
            if (-not [string]::IsNullOrEmpty($settingPath) -and $settingPath.Contains(' > ')) {
                $lastSep = $settingPath.LastIndexOf(' > ')
                $displayName = $settingPath.Substring($lastSep + 3)
            } else {
                $displayName = if (-not [string]::IsNullOrEmpty($settingPath)) { $settingPath }
                               elseif ($firstPol.SettingName) { $firstPol.SettingName }
                               else { $dr.Name }
            }
            $encDisplayName = [System.Net.WebUtility]::HtmlEncode($displayName)
            $pathLine = & $getSettingPathHtml $settingPath $displayName 'dup-setting-path'
            $encCategory = [System.Net.WebUtility]::HtmlEncode($drCategory)
            $crossTag = if ($isCrossCategory) { ' <span class="dup-cross-tag">cross-category</span>' } else { '' }

            # Status cell
            if ($isConflict) {
                $statusHtml = '<span class="status-badge status-conflicting"><span class="status-dot"></span>Conflict</span>'
            } else {
                $statusHtml = '<span class="status-badge status-matched"><span class="status-dot"></span>Match</span>'
            }

            # Majority value for coloring
            $majorityValue = $null
            if ($isConflict) {
                $valCounts = @{}
                foreach ($p in $dr.Policies) {
                    $v = "$($p.Value)"
                    if (-not [string]::IsNullOrWhiteSpace($v)) {
                        if ($valCounts.ContainsKey($v)) { $valCounts[$v]++ } else { $valCounts[$v] = 1 }
                    }
                }
                if ($valCounts.Count -gt 0) {
                    $majorityValue = ($valCounts.GetEnumerator() | Sort-Object -Property Value -Descending | Select-Object -First 1).Key
                }
            }

            [void]$sb.Append('<tr data-dup-row>')
            [void]$sb.Append("<td>$statusHtml</td>")
            [void]$sb.Append("<td><span class=`"setting-name`"><strong>$encDisplayName</strong></span>$crossTag$pathLine</td>")
            [void]$sb.Append("<td style=`"font-size:var(--text-xs);color:var(--text-secondary)`">$encCategory</td>")

            # Policies & Values cell — stacked list
            [void]$sb.Append('<td><div class="dup-pv-list">')
            foreach ($p in $dr.Policies) {
                $sideClass = if ($p.Side -eq 'Source') { 'pv-src' } else { 'pv-dst' }
                $sideLabel = if ($p.Side -eq 'Source') { 'SRC' } else { 'DST' }
                $encPolName = [System.Net.WebUtility]::HtmlEncode($p.Policy)
                $encPolValue = [System.Net.WebUtility]::HtmlEncode("$($p.Value)")

                # Value coloring
                $valClass = 'pv-val'
                if ($isConflict) {
                    if ("$($p.Value)" -eq $majorityValue) {
                        $valClass = 'pv-val pv-val-majority'
                    } else {
                        $valClass = 'pv-val pv-val-outlier'
                    }
                }

                [void]$sb.Append("<div class=`"pv-entry`">")
                [void]$sb.Append("<span class=`"pv-side $sideClass`">$sideLabel</span>")
                [void]$sb.Append("<span class=`"pv-policy`">$encPolName</span>")
                [void]$sb.Append("<span class=`"$valClass`">$encPolValue</span>")
                [void]$sb.Append('</div>')
            }
            [void]$sb.Append('</div></td>')
            [void]$sb.AppendLine('</tr>')
        }

        [void]$sb.AppendLine('</tbody></table>')
        [void]$sb.AppendLine('</div>')  # end table-wrap
        [void]$sb.AppendLine('</div>')  # end dup-groups-container
        [void]$sb.AppendLine('</div>')  # end tab-duplicates
    }

    # ── Deprecated tab content ────────────────────────────────────────────
    if ($hasDeprecated) {
        [void]$sb.AppendLine('<div class="tab-content" id="tab-deprecated">')
        [void]$sb.AppendLine('<div class="dup-info-banner" style="border-color:var(--danger);background:var(--danger-bg)">')
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
                $pathHtml = & $getSettingPathHtml "$($row.SettingPath)" $row.Name 'setting-path'
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
                $pathHtml = & $getSettingPathHtml "$($row.SettingPath)" $row.Name 'setting-path'
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
    [void]$sb.AppendLine('<footer class="footer">')
    [void]$sb.AppendLine('    <span>InforcerCommunity Module &mdash; Created by Roy Klooster</span>')
    [void]$sb.AppendLine('    <span>Powered by Inforcer API &middot; <a href="https://github.com/royklo/InforcerCommunity/issues" target="_blank" rel="noopener" style="color:var(--accent)">Report issue</a></span>')
    [void]$sb.AppendLine('</footer>')

    # ── Scroll to top FAB ──────────────────────────────────────────────────
    [void]$sb.AppendLine('<button class="fab-top" id="btn-top" onclick="window.scrollTo({top:0,behavior:''smooth''})" aria-label="Scroll to top">&#8593;</button>')

    # ── JavaScript ─────────────────────────────────────────────────────────
    [void]$sb.AppendLine('<script>')
    # Theme: follow system preference if no localStorage
    [void]$sb.AppendLine('function toggleTheme() {')
    [void]$sb.AppendLine('    document.documentElement.classList.toggle(''dark'');')
    [void]$sb.AppendLine('    localStorage.setItem(''theme'', document.documentElement.classList.contains(''dark'') ? ''dark'' : ''light'');')
    [void]$sb.AppendLine('}')
    [void]$sb.AppendLine('(function() {')
    [void]$sb.AppendLine('    var s = localStorage.getItem(''theme'');')
    [void]$sb.AppendLine('    if (s === ''dark'') document.documentElement.classList.add(''dark'');')
    [void]$sb.AppendLine('    else if (!s && window.matchMedia(''(prefers-color-scheme: dark)'').matches) document.documentElement.classList.add(''dark'');')
    [void]$sb.AppendLine('})();')
    # Score update (simplified — no animation, values are set server-side in action cards)
    [void]$sb.AppendLine('function updateScore(matched, conflicting, source, dest) {')
    [void]$sb.AppendLine('    var total = matched + conflicting + source + dest;')
    [void]$sb.AppendLine('    var targetPct = total > 0 ? Math.round((matched / total) * 1000) / 10 : 0;')
    [void]$sb.AppendLine('    var elScore = document.getElementById(''scoreNum'');')
    [void]$sb.AppendLine('    var elBar = document.getElementById(''scoreBar'');')
    [void]$sb.AppendLine('    var elDetail = document.getElementById(''scoreDetail'');')
    [void]$sb.AppendLine('    if (elBar) elBar.style.width = targetPct + ''%'';')
    [void]$sb.AppendLine('    if (elScore) elScore.textContent = targetPct + ''%'';')
    [void]$sb.AppendLine('    if (elDetail) elDetail.textContent = targetPct + ''% aligned'';')
    [void]$sb.AppendLine('    var em = document.getElementById(''countMatched'');')
    [void]$sb.AppendLine('    var ec = document.getElementById(''countConflicting'');')
    [void]$sb.AppendLine('    var es = document.getElementById(''countSource'');')
    [void]$sb.AppendLine('    var ed = document.getElementById(''countDest'');')
    [void]$sb.AppendLine('    if (em) em.textContent = matched;')
    [void]$sb.AppendLine('    if (ec) ec.textContent = conflicting;')
    [void]$sb.AppendLine('    if (es) es.textContent = source;')
    [void]$sb.AppendLine('    if (ed) ed.textContent = dest;')
    [void]$sb.AppendLine('}')
    # Scroll to top FAB visibility
    [void]$sb.AppendLine('window.addEventListener(''scroll'', function() {')
    [void]$sb.AppendLine('    var fab = document.getElementById(''btn-top'');')
    [void]$sb.AppendLine('    if (window.scrollY > 200) fab.classList.add(''visible'');')
    [void]$sb.AppendLine('    else fab.classList.remove(''visible'');')
    [void]$sb.AppendLine('});')
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
    [void]$sb.AppendLine('    // Hide category groups where all rows are hidden')
    [void]$sb.AppendLine('    tab.querySelectorAll(".category-group").forEach(function(group) {')
    [void]$sb.AppendLine('        var rows = group.querySelectorAll("tbody tr[data-status]");')
    [void]$sb.AppendLine('        var anyVisible = false;')
    [void]$sb.AppendLine('        rows.forEach(function(r) { if (r.style.display !== "none") anyVisible = true; });')
    [void]$sb.AppendLine('        group.style.display = anyVisible ? "" : "none";')
    [void]$sb.AppendLine('    });')
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
    [void]$sb.AppendLine('    document.querySelectorAll(".comparison-table").forEach(function(tbl) {')
    [void]$sb.AppendLine('        if (show) { tbl.classList.remove("hide-assignments"); } else { tbl.classList.add("hide-assignments"); }')
    [void]$sb.AppendLine('    });')
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
        # dupTabSearch: search across flat duplicates table rows
        [void]$sb.AppendLine('function dupTabSearch(query) {')
        [void]$sb.AppendLine('    var q = query.toLowerCase().trim();')
        [void]$sb.AppendLine('    var table = document.getElementById("dup-flat-table");')
        [void]$sb.AppendLine('    if (!table) return;')
        [void]$sb.AppendLine('    var rows = table.querySelectorAll("tbody tr[data-dup-row]");')
        [void]$sb.AppendLine('    var shown = 0;')
        [void]$sb.AppendLine('    rows.forEach(function(row) {')
        [void]$sb.AppendLine('        if (!q) { row.style.display = ""; shown++; return; }')
        [void]$sb.AppendLine('        var match = row.textContent.toLowerCase().indexOf(q) >= 0;')
        [void]$sb.AppendLine('        row.style.display = match ? "" : "none";')
        [void]$sb.AppendLine('        if (match) shown++;')
        [void]$sb.AppendLine('    });')
        [void]$sb.AppendLine('    var noResults = document.getElementById("dup-no-results");')
        [void]$sb.AppendLine('    if (noResults) noResults.style.display = (shown === 0 && q) ? "" : "none";')
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
    [void]$sb.AppendLine('function highlightJSON(el) {')
    [void]$sb.AppendLine('    var text = el.textContent;')
    [void]$sb.AppendLine('    var tokens = [];')
    [void]$sb.AppendLine('    var re = /("(?:[^"\\]|\\.)*")\s*(:)|("(?:[^"\\]|\\.)*")|\b(true|false|null)\b|(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)/g;')
    [void]$sb.AppendLine('    var lastIdx = 0, m;')
    [void]$sb.AppendLine('    while ((m = re.exec(text)) !== null) {')
    [void]$sb.AppendLine('        if (m.index > lastIdx) tokens.push(escHtml(text.substring(lastIdx, m.index)));')
    [void]$sb.AppendLine('        if (m[1]) { tokens.push(''<span class="json-key">''+escHtml(m[1])+''</span>''+escHtml(m[2])); }')
    [void]$sb.AppendLine('        else if (m[3]) { tokens.push(''<span class="json-string">''+escHtml(m[3])+''</span>''); }')
    [void]$sb.AppendLine('        else if (m[4]) { tokens.push(''<span class="json-bool">''+escHtml(m[4])+''</span>''); }')
    [void]$sb.AppendLine('        else if (m[5]) { tokens.push(''<span class="json-number">''+escHtml(m[5])+''</span>''); }')
    [void]$sb.AppendLine('        lastIdx = m.index + m[0].length;')
    [void]$sb.AppendLine('    }')
    [void]$sb.AppendLine('    if (lastIdx < text.length) tokens.push(escHtml(text.substring(lastIdx)));')
    [void]$sb.AppendLine('    el.innerHTML = tokens.join("");')
    [void]$sb.AppendLine('}')
    [void]$sb.AppendLine('// Apply filters FIRST to hide deprecated rows (must run before any cosmetic JS)')
    [void]$sb.AppendLine('applyFilters();')
    if ($hasDuplicates) {
        [void]$sb.AppendLine('dupTabSearch('''');')
    }
    [void]$sb.AppendLine('// Syntax highlighting and copy buttons (wrapped in try/catch to never block filters)')
    [void]$sb.AppendLine('try {')
    [void]$sb.AppendLine('    document.querySelectorAll(".ps-code code").forEach(highlightPS);')
    [void]$sb.AppendLine('    document.querySelectorAll(".sh-code code").forEach(highlightBash);')
    [void]$sb.AppendLine('    document.querySelectorAll("pre.ps-code").forEach(function(el) { if (!el.querySelector("code")) highlightPS(el); });')
    [void]$sb.AppendLine('    document.querySelectorAll("pre.sh-code").forEach(function(el) { if (!el.querySelector("code")) highlightBash(el); });')
    [void]$sb.AppendLine('    document.querySelectorAll("pre.json-code").forEach(highlightJSON);')
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
    [void]$sb.AppendLine('  document.querySelectorAll(''.comparison-table'').forEach(function(table) {')
    [void]$sb.AppendLine('    var ths = table.querySelectorAll(''thead th'');')
    [void]$sb.AppendLine('    if (!ths.length) return;')
    [void]$sb.AppendLine('    var defaultWidths = [];')
    [void]$sb.AppendLine('    var minWidths = [];')
    [void]$sb.AppendLine('    ths.forEach(function(th, i) {')
    [void]$sb.AppendLine('      defaultWidths[i] = th.offsetWidth;')
    [void]$sb.AppendLine('      minWidths[i] = (i === 0) ? 40 : 60;')
    [void]$sb.AppendLine('    });')
    [void]$sb.AppendLine('    ths.forEach(function(th) { th.style.width = th.offsetWidth + ''px''; });')
    [void]$sb.AppendLine('    table.style.tableLayout = ''fixed'';')
    [void]$sb.AppendLine('    ths.forEach(function(th, i) {')
    [void]$sb.AppendLine('      var handle = document.createElement(''div'');')
    [void]$sb.AppendLine('      handle.className = ''col-resize-handle'';')
    [void]$sb.AppendLine('      th.appendChild(handle);')
    [void]$sb.AppendLine('      handle.addEventListener(''dblclick'', function(e) {')
    [void]$sb.AppendLine('        e.stopPropagation(); e.preventDefault();')
    [void]$sb.AppendLine('        th.style.width = defaultWidths[i] + ''px'';')
    [void]$sb.AppendLine('      });')
    [void]$sb.AppendLine('      var startX, startW;')
    [void]$sb.AppendLine('      handle.addEventListener(''mousedown'', function(e) {')
    [void]$sb.AppendLine('        e.stopPropagation(); e.preventDefault();')
    [void]$sb.AppendLine('        startX = e.pageX; startW = th.offsetWidth;')
    [void]$sb.AppendLine('        handle.classList.add(''resizing'');')
    [void]$sb.AppendLine('        document.body.style.cursor = ''col-resize'';')
    [void]$sb.AppendLine('        document.addEventListener(''mousemove'', onMouseMove);')
    [void]$sb.AppendLine('        document.addEventListener(''mouseup'', onMouseUp);')
    [void]$sb.AppendLine('      });')
    [void]$sb.AppendLine('      function onMouseMove(e) { var w = Math.max(minWidths[i], startW + (e.pageX - startX)); th.style.width = w + ''px''; }')
    [void]$sb.AppendLine('      function onMouseUp() { handle.classList.remove(''resizing''); document.body.style.cursor = ''''; document.removeEventListener(''mousemove'', onMouseMove); document.removeEventListener(''mouseup'', onMouseUp); }')
    [void]$sb.AppendLine('    });')
    [void]$sb.AppendLine('  });')
    [void]$sb.AppendLine('})();')
    [void]$sb.AppendLine('} catch(e) { console.warn(''Column resize error:'', e); }')
    [void]$sb.AppendLine('</script>')

    # ── Close body/html ────────────────────────────────────────────────────
    [void]$sb.AppendLine('</body>')
    [void]$sb.AppendLine('</html>')

    return $sb.ToString()
}
