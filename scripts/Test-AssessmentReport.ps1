# Test-AssessmentReport.ps1
# Standalone script to run an assessment and generate an interactive HTML report.
# Usage: pwsh -File scripts/Test-AssessmentReport.ps1
# Prerequisites: Connect-Inforcer must have been run in the current session.

param(
    [Parameter(Mandatory = $false)]
    [object]$TenantId = 646,

    [Parameter(Mandatory = $false)]
    [string]$AssessmentName = 'Copilot Readiness',

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = (Join-Path $PSScriptRoot '..' "assessment-report-$(Get-Date -Format 'yyyy-MM-dd-HHmm').html")
)

$ErrorActionPreference = 'Stop'

# Import module if not loaded
if (-not (Get-Module InforcerCommunity)) {
    $modulePath = Join-Path $PSScriptRoot '..' 'module' 'InforcerCommunity.psd1'
    Import-Module $modulePath -Force
}

# Run assessment
$checks = Invoke-InforcerAssessment -TenantId $TenantId -AssessmentId $AssessmentName
if (-not $checks) {
    Write-Error "No results returned."
    return
}

# Compute summary
$total = $checks.Count
$passed = ($checks | Where-Object Status -eq 'Pass').Count
$failed = $total - $passed
$score = if ($total -gt 0) { [math]::Round(($passed / $total) * 100, 1) } else { 0 }

# Group by category
$categories = $checks | Group-Object -Property category | Sort-Object Name

# Build checks JSON for JS using ConvertTo-Json for safe escaping
$placeholders = @('[Multiple Objects Evaluated]','[unknown name]','[unknown id]')
$dataArray = [System.Collections.Generic.List[object]]::new()
foreach ($check in $checks) {
    $scoresArr = [System.Collections.Generic.List[object]]::new()
    if ($check.Scores) {
        foreach ($s in $check.Scores) {
            $objName = if ($s.objectName -and $s.objectName -notin $placeholders) { $s.objectName } else { 'Tenant check' }
            [void]$scoresArr.Add(@{
                obj   = $objName
                score = $s.score
                p     = @(if ($s.passes) { $s.passes | Where-Object { $_ } } else { @() })
                v     = @(if ($s.violations) { $s.violations | Where-Object { $_ } } else { @() })
                w     = @(if ($s.warnings) { $s.warnings | Where-Object { $_ } } else { @() })
            })
        }
    }
    $desc = if ($check.description) {
        $d = $check.description -replace "`r?`n", ' '
        if ($d.Length -gt 300) { $d.Substring(0, 300) + '...' } else { $d }
    } else { '' }
    [void]$dataArray.Add(@{
        name   = $check.name
        cat    = $check.category
        sub    = $check.subCategory
        imp    = ($check.importance).ToLower()
        status = $check.Status
        msg    = $check.FindingsMessage
        desc   = $desc
        hasRem = [bool]$check.remediation
        scores = @($scoresArr)
    })
}
$dataJson = $dataArray | ConvertTo-Json -Depth 10 -Compress

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>$AssessmentName Report</title>
<style>
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap');

:root {
    --bg: #0f1117; --bg-card: #181b23; --bg-hover: #1e2230; --bg-surface: #232733;
    --border: #2a2e3a; --border-light: #333845;
    --text: #e8eaed; --text-2: #9ca3af; --text-3: #6b7280;
    --accent: #6366f1; --accent-2: #818cf8; --accent-bg: rgba(99,102,241,0.12);
    --green: #10b981; --green-bg: rgba(16,185,129,0.1); --green-b: rgba(16,185,129,0.25);
    --red: #ef4444; --red-bg: rgba(239,68,68,0.1); --red-b: rgba(239,68,68,0.25);
    --amber: #f59e0b; --amber-bg: rgba(245,158,11,0.1); --amber-b: rgba(245,158,11,0.25);
    --r: 12px; --r-sm: 8px; --r-xs: 6px;
    --shadow: 0 2px 8px rgba(0,0,0,0.3);
    --shadow-lg: 0 8px 30px rgba(0,0,0,0.4);
    --transition: 0.2s ease;
}
html.light {
    --bg: #f8f9fb; --bg-card: #ffffff; --bg-hover: #f3f4f6; --bg-surface: #f0f1f4;
    --border: #e2e4e9; --border-light: #ebedf0;
    --text: #111827; --text-2: #6b7280; --text-3: #9ca3af;
    --accent: #4f46e5; --accent-2: #6366f1; --accent-bg: rgba(79,70,229,0.08);
    --green-bg: rgba(16,185,129,0.08); --green-b: rgba(16,185,129,0.2);
    --red-bg: rgba(239,68,68,0.06); --red-b: rgba(239,68,68,0.18);
    --amber-bg: rgba(245,158,11,0.08); --amber-b: rgba(245,158,11,0.2);
    --shadow: 0 1px 3px rgba(0,0,0,0.06); --shadow-lg: 0 4px 16px rgba(0,0,0,0.08);
}

* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: 'Inter', system-ui, sans-serif; background: var(--bg); color: var(--text); line-height: 1.6; min-height: 100vh; transition: background var(--transition), color var(--transition); }

.brand-bar { position: fixed; top: 0; left: 0; right: 0; height: 3px; z-index: 100;
    background: linear-gradient(90deg, #6366f1, #8b5cf6, #ec4899, #6366f1); background-size: 200% 100%;
    animation: shimmer 4s ease infinite; }
@keyframes shimmer { 0%,100% { background-position: 0% 50%; } 50% { background-position: 100% 50%; } }

.container { max-width: 1100px; margin: 0 auto; padding: 2.5rem 2rem 4rem; }

/* Theme + controls bar */
.controls { display: flex; align-items: center; gap: 0.75rem; margin-bottom: 1.75rem; flex-wrap: wrap; }
.search-box {
    flex: 1; min-width: 200px; padding: 0.55rem 1rem 0.55rem 2.4rem; border-radius: 99px;
    background: var(--bg-card); border: 1px solid var(--border); color: var(--text);
    font-size: 0.82rem; outline: none; transition: border var(--transition);
    background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='16' height='16' fill='%236b7280' viewBox='0 0 16 16'%3E%3Cpath d='M11.742 10.344a6.5 6.5 0 10-1.397 1.398h-.001l3.85 3.85a1 1 0 001.415-1.415l-3.85-3.85zm-5.242.156a5 5 0 110-10 5 5 0 010 10z'/%3E%3C/svg%3E");
    background-repeat: no-repeat; background-position: 0.85rem center;
}
.search-box:focus { border-color: var(--accent); }
.search-box::placeholder { color: var(--text-3); }
.filter-btn {
    padding: 0.45rem 0.85rem; border-radius: 99px; border: 1px solid var(--border);
    background: var(--bg-card); color: var(--text-2); font-size: 0.75rem; font-weight: 500;
    cursor: pointer; transition: all var(--transition); user-select: none;
}
.filter-btn:hover { border-color: var(--accent); color: var(--accent); }
.filter-btn.active { background: var(--accent); border-color: var(--accent); color: white; }
.theme-btn {
    width: 36px; height: 36px; border-radius: 50%; border: 1px solid var(--border);
    background: var(--bg-card); color: var(--text-2); cursor: pointer; font-size: 1rem;
    display: flex; align-items: center; justify-content: center; transition: all var(--transition);
}
.theme-btn:hover { border-color: var(--accent); color: var(--accent); }

/* Header */
.header { margin-bottom: 2rem; }
.header h1 { font-size: 1.75rem; font-weight: 800; letter-spacing: -0.04em;
    background: linear-gradient(135deg, var(--text), var(--text-2)); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
.header .meta { font-size: 0.78rem; color: var(--text-3); margin-top: 0.3rem; }

/* Score hero */
.hero { display: flex; align-items: center; gap: 2.5rem; background: var(--bg-card); border: 1px solid var(--border);
    border-radius: var(--r); padding: 2rem 2.5rem; margin-bottom: 2rem; box-shadow: var(--shadow-lg);
    position: relative; overflow: hidden; }
.hero::before { content: ''; position: absolute; top: -50%; right: -20%; width: 300px; height: 300px;
    background: radial-gradient(circle, var(--accent-bg) 0%, transparent 70%); pointer-events: none; }
.ring-wrap { position: relative; width: 130px; height: 130px; flex-shrink: 0; }
.ring-wrap svg { width: 130px; height: 130px; transform: rotate(-90deg); filter: drop-shadow(0 0 12px var(--accent-bg)); }
.ring-bg { fill: none; stroke: var(--bg-surface); stroke-width: 7; }
.ring-fill { fill: none; stroke-width: 7; stroke-linecap: round; transition: stroke-dashoffset 1.2s cubic-bezier(0.4,0,0.2,1); }
.ring-text { position: absolute; inset: 0; display: flex; flex-direction: column; align-items: center; justify-content: center; }
.ring-pct { font-size: 2rem; font-weight: 800; line-height: 1; }
.ring-label { font-size: 0.6rem; color: var(--text-3); text-transform: uppercase; letter-spacing: 0.1em; margin-top: 0.2rem; }
.hero-stats { display: flex; gap: 2.5rem; z-index: 1; }
.hero-stat { text-align: center; }
.hero-stat .val { font-size: 2rem; font-weight: 700; line-height: 1.1; }
.hero-stat .lbl { font-size: 0.65rem; color: var(--text-3); text-transform: uppercase; letter-spacing: 0.1em; margin-top: 0.25rem; }

/* Category nav pills */
.cat-nav { display: flex; gap: 0.4rem; margin-bottom: 1.5rem; flex-wrap: wrap; }
.cat-pill {
    padding: 0.35rem 0.75rem; border-radius: 99px; border: 1px solid var(--border);
    background: var(--bg-card); color: var(--text-2); font-size: 0.72rem; font-weight: 500;
    cursor: pointer; transition: all var(--transition); user-select: none;
}
.cat-pill:hover { border-color: var(--accent); }
.cat-pill.active { background: var(--accent-bg); border-color: var(--accent); color: var(--accent); }
.cat-pill .cnt { background: var(--bg-surface); padding: 0.05rem 0.4rem; border-radius: 99px; font-size: 0.65rem; margin-left: 0.3rem; }

/* Check cards */
.checks { display: flex; flex-direction: column; gap: 0.5rem; }
.check-card {
    background: var(--bg-card); border: 1px solid var(--border); border-radius: var(--r);
    padding: 1rem 1.25rem; transition: all var(--transition); cursor: default;
}
.check-card:hover { border-color: var(--border-light); box-shadow: var(--shadow); }
.check-card.hidden { display: none; }
.check-top { display: flex; align-items: flex-start; gap: 0.75rem; }
.status-icon { width: 30px; height: 30px; border-radius: 50%; flex-shrink: 0;
    display: flex; align-items: center; justify-content: center; font-size: 0.85rem; margin-top: 0.1rem; }
.si-pass { background: var(--green-bg); border: 1px solid var(--green-b); color: var(--green); }
.si-fail { background: var(--red-bg); border: 1px solid var(--red-b); color: var(--red); }
.check-body { flex: 1; min-width: 0; }
.check-title { font-size: 0.88rem; font-weight: 600; margin-bottom: 0.15rem; }
.check-sub { font-size: 0.75rem; color: var(--text-3); }
.check-msg { font-size: 0.78rem; color: var(--text-2); margin-top: 0.4rem; }
.check-pills { display: flex; gap: 0.35rem; flex-shrink: 0; margin-top: 0.1rem; }
.pill { padding: 0.18rem 0.55rem; border-radius: var(--r-xs); font-size: 0.62rem; font-weight: 600;
    text-transform: uppercase; letter-spacing: 0.04em; }
.pill-h { background: var(--red-bg); color: var(--red); border: 1px solid var(--red-b); }
.pill-m { background: var(--amber-bg); color: var(--amber); border: 1px solid var(--amber-b); }
.pill-l { background: var(--bg-surface); color: var(--text-3); border: 1px solid var(--border); }

/* Expandable detail */
.check-detail { margin-top: 0.75rem; }
.detail-toggle {
    display: inline-flex; align-items: center; gap: 0.35rem; font-size: 0.75rem; color: var(--accent);
    cursor: pointer; user-select: none; padding: 0.25rem 0; border: none; background: none;
}
.detail-toggle:hover { color: var(--accent-2); }
.detail-toggle .arrow { font-size: 0.55rem; transition: transform 0.2s ease; display: inline-block; }
.detail-toggle.open .arrow { transform: rotate(90deg); }
.detail-content { display: none; margin-top: 0.5rem; }
.detail-content.open { display: block; }

.score-row {
    display: grid; grid-template-columns: 1fr 80px auto 2fr; gap: 0.75rem; align-items: start;
    padding: 0.65rem 0.85rem; background: var(--bg-surface); border-radius: var(--r-sm);
    font-size: 0.78rem; margin-bottom: 0.3rem;
}
.sr-name { font-weight: 500; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.sr-bar { display: flex; align-items: center; gap: 0.5rem; }
.bar-track { width: 50px; height: 4px; background: var(--border); border-radius: 2px; overflow: hidden; }
.bar-fill { height: 100%; border-radius: 2px; }
.sr-pct { font-weight: 700; font-size: 0.75rem; min-width: 35px; text-align: right; }
.sr-issues { display: flex; flex-direction: column; gap: 0.15rem; }
.si { font-size: 0.72rem; line-height: 1.4; }
.si-v { color: var(--red); }
.si-w { color: var(--amber); }
.si-p { color: var(--green); }

/* Empty state */
.empty { text-align: center; padding: 3rem; color: var(--text-3); font-size: 0.9rem; }

/* Counter badge */
.result-count { font-size: 0.78rem; color: var(--text-3); margin-bottom: 1rem; }
.result-count strong { color: var(--text); }

/* Footer */
.footer { text-align: center; margin-top: 3rem; padding-top: 1.5rem;
    border-top: 1px solid var(--border); font-size: 0.72rem; color: var(--text-3); }
.footer a { color: var(--accent); text-decoration: none; }

/* Print */
@media print { .controls, .cat-nav, .theme-btn, .brand-bar { display: none; } .check-card { break-inside: avoid; } }
</style>
</head>
<body>
<div class="brand-bar"></div>
<div class="container">
    <div style="display:flex;justify-content:space-between;align-items:flex-start;">
        <div class="header">
            <h1>$AssessmentName</h1>
            <div class="meta">Generated $(Get-Date -Format 'dddd, dd MMMM yyyy \a\t HH:mm') &middot; Tenant $TenantId</div>
        </div>
        <button class="theme-btn" onclick="toggleTheme()" title="Toggle theme">&#9681;</button>
    </div>

    <div class="hero">
        <div class="ring-wrap">
            <svg viewBox="0 0 130 130">
                <circle class="ring-bg" cx="65" cy="65" r="56"/>
                <circle class="ring-fill" cx="65" cy="65" r="56" id="scoreRing"
                    stroke="$(if ($score -ge 90) { '#10b981' } elseif ($score -ge 70) { '#f59e0b' } else { '#ef4444' })"
                    stroke-dasharray="$('{0:F1}' -f (2 * [math]::PI * 56))"
                    stroke-dashoffset="$('{0:F1}' -f (2 * [math]::PI * 56 * (1 - $score / 100)))"/>
            </svg>
            <div class="ring-text">
                <div class="ring-pct" style="color:$(if ($score -ge 90) { 'var(--green)' } elseif ($score -ge 70) { 'var(--amber)' } else { 'var(--red)' })">$score%</div>
                <div class="ring-label">Compliance</div>
            </div>
        </div>
        <div class="hero-stats">
            <div class="hero-stat"><div class="val">$total</div><div class="lbl">Total Checks</div></div>
            <div class="hero-stat"><div class="val" style="color:var(--green)">$passed</div><div class="lbl">Passed</div></div>
            <div class="hero-stat"><div class="val" style="color:var(--red)">$failed</div><div class="lbl">Failed</div></div>
        </div>
    </div>

    <div class="controls">
        <input type="text" class="search-box" id="search" placeholder="Search checks, categories, findings..." oninput="applyFilters()">
        <button class="filter-btn active" data-filter="all" onclick="setFilter(this,'all')">All</button>
        <button class="filter-btn" data-filter="fail" onclick="setFilter(this,'fail')">Failed</button>
        <button class="filter-btn" data-filter="pass" onclick="setFilter(this,'pass')">Passed</button>
        <button class="filter-btn" data-filter="high" onclick="setFilter(this,'high')">High</button>
        <button class="filter-btn" data-filter="medium" onclick="setFilter(this,'medium')">Medium</button>
        <button class="filter-btn" data-filter="low" onclick="setFilter(this,'low')">Low</button>
    </div>

    <div class="cat-nav" id="catNav"></div>
    <div class="result-count" id="resultCount"></div>
    <div class="checks" id="checksContainer"></div>

    <div class="footer">
        Generated by <a href="https://github.com/royklo/InforcerCommunity">InforcerCommunity</a> PowerShell Module &middot; $AssessmentName
    </div>
</div>

<script>
var DATA = $dataJson;
var activeFilter = 'all';
var activeCat = 'all';

function toggleTheme() {
    document.documentElement.classList.toggle('light');
    localStorage.setItem('theme', document.documentElement.classList.contains('light') ? 'light' : 'dark');
}
if (localStorage.getItem('theme') === 'light') document.documentElement.classList.add('light');

function esc(s) { var d = document.createElement('div'); d.textContent = s; return d.innerHTML; }

function barColor(score) {
    if (score >= 100) return 'var(--green)';
    if (score >= 75) return '#86efac';
    if (score >= 50) return 'var(--amber)';
    if (score >= 25) return '#fb923c';
    return 'var(--red)';
}
function pctClass(score) {
    if (score >= 100) return 'color:var(--green)';
    if (score >= 75) return 'color:#86efac';
    if (score >= 50) return 'color:var(--amber)';
    if (score >= 25) return 'color:#fb923c';
    return 'color:var(--red)';
}

function buildCatNav() {
    var cats = {}; DATA.forEach(function(c) { cats[c.cat] = (cats[c.cat]||0) + 1; });
    var h = '<span class="cat-pill active" onclick="setCat(this,\'all\')">All <span class="cnt">' + DATA.length + '</span></span>';
    Object.keys(cats).sort().forEach(function(k) {
        h += '<span class="cat-pill" onclick="setCat(this,\'' + esc(k) + '\')">' + esc(k) + ' <span class="cnt">' + cats[k] + '</span></span>';
    });
    document.getElementById('catNav').innerHTML = h;
}

function setCat(el, cat) {
    activeCat = cat;
    document.querySelectorAll('.cat-pill').forEach(function(p) { p.classList.remove('active'); });
    el.classList.add('active');
    applyFilters();
}

function setFilter(el, filter) {
    activeFilter = filter;
    document.querySelectorAll('.filter-btn').forEach(function(b) { b.classList.remove('active'); });
    el.classList.add('active');
    applyFilters();
}

function applyFilters() {
    var q = document.getElementById('search').value.toLowerCase();
    var cards = document.querySelectorAll('.check-card');
    var shown = 0;
    cards.forEach(function(card, i) {
        var c = DATA[i];
        var vis = true;
        if (activeFilter === 'fail' && c.status !== 'Fail') vis = false;
        if (activeFilter === 'pass' && c.status !== 'Pass') vis = false;
        if (activeFilter === 'high' && c.imp !== 'high') vis = false;
        if (activeFilter === 'medium' && c.imp !== 'medium') vis = false;
        if (activeFilter === 'low' && c.imp !== 'low') vis = false;
        if (activeCat !== 'all' && c.cat !== activeCat) vis = false;
        if (q) {
            var hay = (c.name + ' ' + c.cat + ' ' + c.sub + ' ' + c.msg + ' ' + c.desc).toLowerCase();
            c.scores.forEach(function(s) {
                hay += ' ' + s.obj.toLowerCase();
                s.v.forEach(function(v) { hay += ' ' + v.toLowerCase(); });
                s.w.forEach(function(w) { hay += ' ' + w.toLowerCase(); });
                s.p.forEach(function(p) { hay += ' ' + p.toLowerCase(); });
            });
            if (hay.indexOf(q) === -1) vis = false;
        }
        card.classList.toggle('hidden', !vis);
        if (vis) shown++;
    });
    document.getElementById('resultCount').innerHTML = 'Showing <strong>' + shown + '</strong> of <strong>' + DATA.length + '</strong> checks';
}

function toggleDetail(idx) {
    var btn = document.getElementById('toggle-' + idx);
    var content = document.getElementById('detail-' + idx);
    btn.classList.toggle('open');
    content.classList.toggle('open');
}

function renderChecks() {
    var h = '';
    // Sort: failed first, then by importance (high > medium > low), then name
    var impOrder = {high:0, medium:1, low:2};
    var sorted = DATA.map(function(c,i) { return {c:c, i:i}; }).sort(function(a,b) {
        var sa = a.c.status === 'Fail' ? 0 : 1; var sb = b.c.status === 'Fail' ? 0 : 1;
        if (sa !== sb) return sa - sb;
        var ia = impOrder[a.c.imp] || 2; var ib = impOrder[b.c.imp] || 2;
        if (ia !== ib) return ia - ib;
        return a.c.name.localeCompare(b.c.name);
    });

    sorted.forEach(function(item) {
        var c = item.c; var idx = item.i;
        var siClass = c.status === 'Pass' ? 'si-pass' : 'si-fail';
        var siIcon = c.status === 'Pass' ? '\u2713' : '\u2717';
        var pillClass = c.imp === 'high' ? 'pill-h' : (c.imp === 'medium' ? 'pill-m' : 'pill-l');

        h += '<div class="check-card" data-idx="' + idx + '">';
        h += '<div class="check-top">';
        h += '<div class="status-icon ' + siClass + '">' + siIcon + '</div>';
        h += '<div class="check-body">';
        h += '<div class="check-title">' + esc(c.name) + '</div>';
        h += '<div class="check-sub">' + esc(c.cat) + ' &middot; ' + esc(c.sub) + '</div>';
        h += '<div class="check-msg">' + esc(c.msg) + '</div>';

        if (c.scores.length > 0) {
            h += '<div class="check-detail">';
            h += '<button class="detail-toggle" id="toggle-' + idx + '" onclick="toggleDetail(' + idx + ')">';
            h += '<span class="arrow">\u25B6</span> ' + c.scores.length + ' evaluated object' + (c.scores.length !== 1 ? 's' : '') + '</button>';
            h += '<div class="detail-content" id="detail-' + idx + '">';

            var ss = c.scores.slice().sort(function(a,b) { return a.score - b.score; });
            ss.forEach(function(s) {
                h += '<div class="score-row">';
                h += '<div class="sr-name" title="' + esc(s.obj) + '">' + esc(s.obj) + '</div>';
                h += '<div class="sr-bar"><div class="bar-track"><div class="bar-fill" style="width:' + s.score + '%;background:' + barColor(s.score) + '"></div></div></div>';
                h += '<div class="sr-pct" style="' + pctClass(s.score) + '">' + s.score + '%</div>';
                h += '<div class="sr-issues">';
                s.v.forEach(function(v) { h += '<div class="si si-v">\u2717 ' + esc(v) + '</div>'; });
                s.w.forEach(function(w) { h += '<div class="si si-w">\u26A0 ' + esc(w) + '</div>'; });
                if (s.v.length === 0 && s.w.length === 0) {
                    s.p.forEach(function(p) { h += '<div class="si si-p">\u2713 ' + esc(p) + '</div>'; });
                }
                h += '</div></div>';
            });

            h += '</div></div>';
        }

        h += '</div>';
        h += '<div class="check-pills"><span class="pill ' + pillClass + '">' + esc(c.imp) + '</span></div>';
        h += '</div></div>';
    });

    document.getElementById('checksContainer').innerHTML = h || '<div class="empty">No checks to display</div>';
}

buildCatNav();
renderChecks();
applyFilters();
</script>
</body>
</html>
"@

$OutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$html | Set-Content -Path $OutputPath -Encoding UTF8
Write-Host "Report saved to: $OutputPath"

# Open in browser
if ($IsWindows) { Start-Process $OutputPath }
elseif ($IsMacOS) { & open $OutputPath }
elseif ($IsLinux) { & xdg-open $OutputPath }
