function ConvertTo-InforcerAssessmentMatrixHtml {
    <#
    .SYNOPSIS
        Generates a multi-tenant assessment matrix HTML report.
    .PARAMETER AssessmentName
        Display name of the assessment.
    .PARAMETER TenantResults
        Array of tenant result hashtables, each with: TenantName, TenantId, Score, Passed, Failed, TotalChecks, Checks.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string]$AssessmentName,
        [Parameter(Mandatory)] [array]$TenantResults
    )

    $esc = { param([string]$s) [System.Web.HttpUtility]::HtmlEncode($s) }

    # Build unique check list
    $checkIndex = [ordered]@{}
    foreach ($tr in $TenantResults) {
        foreach ($c in $tr.Checks) {
            $key = "$($c.category)|$($c.name)"
            if (-not $checkIndex.Contains($key)) {
                $checkIndex[$key] = @{ name = $c.name; category = $c.category; subCategory = $c.subCategory; importance = $c.importance; key = $c.key; description = $c.description; impact = $c.impact; rationale = $c.rationale }
            }
        }
    }
    $allChecks = @($checkIndex.Values)

    # Build per-tenant lookup
    $tenantCheckMap = [ordered]@{}
    foreach ($tr in $TenantResults) {
        $map = @{}
        foreach ($c in $tr.Checks) { $map["$($c.category)|$($c.name)"] = $c.Status }
        $tenantCheckMap[$tr.TenantName] = $map
    }

    $tenantNames = @($TenantResults | ForEach-Object { $_.TenantName })
    $dateStr = Get-Date -Format 'yyyy-MM-dd'
    $timeStr = Get-Date -Format 'HH:mm'
    $avgScore = if ($TenantResults.Count -gt 0) { [math]::Round(($TenantResults | ForEach-Object { $_.Score } | Measure-Object -Average).Average, 1) } else { 0 }

    $tenantsJson = $TenantResults | ForEach-Object {
        @{ name = $_.TenantName; id = $_.TenantId; score = $_.Score; passed = $_.Passed; failed = $_.Failed; total = $_.TotalChecks }
    } | ConvertTo-Json -Depth 100 -Compress

    $matrixRows = [System.Collections.Generic.List[object]]::new()
    foreach ($ck in $allChecks) {
        $key = "$($ck.category)|$($ck.name)"
        $statuses = [ordered]@{}
        foreach ($tn in $tenantNames) {
            $st = if ($tenantCheckMap[$tn].ContainsKey($key)) { $tenantCheckMap[$tn][$key] } else { 'N/A' }
            $statuses[$tn] = $st
        }
        $desc = if ($ck.description) { ($ck.description -replace "`r?`n", '\n') } else { '' }
        $impact = if ($ck.impact) { ($ck.impact -replace "`r?`n", '\n') } else { '' }
        $rationale = if ($ck.rationale) { ($ck.rationale -replace "`r?`n", '\n') } else { '' }
        [void]$matrixRows.Add(@{ name = $ck.name; category = $ck.category; sub = $ck.subCategory; importance = $ck.importance; statuses = $statuses; desc = $desc; impact = $impact; rationale = $rationale })
    }
    $matrixJson = $matrixRows | ConvertTo-Json -Depth 100 -Compress

    $sb = [System.Text.StringBuilder]::new(48000)
    [void]$sb.Append(@"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>$(& $esc $AssessmentName) - Multi-Tenant Matrix</title>
<style>
@import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700;800&display=swap');
:root{
  --bg:#0c0e14;--bg-2:#13151e;--bg-3:#1a1d2a;--bg-4:#222636;
  --border:#2a2f42;--border-2:#333952;
  --text:#eaecf0;--text-2:#a0a6b8;--text-3:#6b7190;
  --accent:#6366f1;--accent-2:#818cf8;--accent-bg:rgba(99,102,241,0.1);--accent-border:rgba(99,102,241,0.25);
  --green:#22c55e;--green-bg:rgba(34,197,94,0.1);--green-b:rgba(34,197,94,0.25);
  --red:#ef4444;--red-bg:rgba(239,68,68,0.1);--red-b:rgba(239,68,68,0.25);
  --amber:#f59e0b;--amber-bg:rgba(245,158,11,0.1);
  --r:10px;--r-sm:6px;
  --shadow:0 2px 8px rgba(0,0,0,0.4);--shadow-lg:0 12px 40px rgba(0,0,0,0.5);
  --tr:0.2s ease;
}
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:'Inter',system-ui,sans-serif;background:var(--bg);color:var(--text);line-height:1.5;font-size:0.8125rem;-webkit-font-smoothing:antialiased}

/* Brand bar */
.brand-bar{position:fixed;top:0;left:0;right:0;height:3px;z-index:200;
  background:linear-gradient(90deg,#6366f1,#8b5cf6,#ec4899,#6366f1);background-size:200% 100%;
  animation:shimmer 4s ease infinite}
@keyframes shimmer{0%,100%{background-position:0% 50%}50%{background-position:100% 50%}}

/* Header */
.header{padding:2.5rem 2rem 1.75rem;border-bottom:1px solid var(--border);background:var(--bg-2);margin-bottom:1.5rem}
.header-inner{max-width:1800px;margin:0 auto;display:flex;align-items:center;justify-content:space-between;gap:2rem;flex-wrap:wrap}
.header-left{display:flex;align-items:center;gap:1.25rem}
.header-icon{width:44px;height:44px;border-radius:var(--r);background:var(--accent-bg);border:1px solid var(--accent-border);display:flex;align-items:center;justify-content:center;font-size:1.4rem}
.header h1{font-size:1.35rem;font-weight:700;letter-spacing:-0.03em;color:var(--text)}
.header .sub{font-size:0.78rem;color:var(--text-3);margin-top:0.1rem}
.header-stats{display:flex;gap:1.75rem}
.hstat{text-align:center}
.hstat .val{font-size:1.5rem;font-weight:800;line-height:1.1}
.hstat .lbl{font-size:0.6rem;color:var(--text-3);text-transform:uppercase;letter-spacing:0.1em;margin-top:0.1rem}

.container{max-width:1800px;margin:0 auto;padding:0 2rem 3rem}

/* Toolbar */
.toolbar{display:flex;align-items:center;gap:0.6rem;margin-bottom:1.25rem;flex-wrap:wrap}
.search{flex:1;min-width:180px;padding:0.5rem 1rem 0.5rem 2.25rem;border-radius:99px;background:var(--bg-3);border:1px solid var(--border);color:var(--text);font-size:0.78rem;outline:none;transition:border var(--tr);
  background-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='14' height='14' fill='%236b7190' viewBox='0 0 16 16'%3E%3Cpath d='M11.742 10.344a6.5 6.5 0 10-1.397 1.398h-.001l3.85 3.85a1 1 0 001.415-1.415l-3.85-3.85zm-5.242.156a5 5 0 110-10 5 5 0 010 10z'/%3E%3C/svg%3E");
  background-repeat:no-repeat;background-position:0.75rem center}
.search:focus{border-color:var(--accent)}
.search::placeholder{color:var(--text-3)}
.pill-btn{padding:0.4rem 0.85rem;border-radius:99px;border:1px solid var(--border);background:var(--bg-3);color:var(--text-2);font-size:0.72rem;font-weight:500;cursor:pointer;transition:all var(--tr);user-select:none}
.pill-btn:hover{border-color:var(--accent);color:var(--accent)}
.pill-btn.active{background:var(--accent);border-color:var(--accent);color:#fff}
.tenant-wrap{position:relative}
.tenant-btn{padding:0.4rem 0.85rem;border-radius:99px;border:1px solid var(--border);background:var(--bg-3);color:var(--text-2);font-size:0.72rem;cursor:pointer;display:flex;align-items:center;gap:0.35rem;transition:all var(--tr)}
.tenant-btn:hover{border-color:var(--accent)}

/* Tenant dropdown */
.t-drop{display:none;position:absolute;top:calc(100% + 6px);right:0;background:var(--bg-3);border:1px solid var(--border);border-radius:var(--r);box-shadow:var(--shadow-lg);z-index:100;min-width:260px;max-height:420px;overflow-y:auto;padding:0.5rem 0}
.t-drop.open{display:block}
.t-drop-actions{display:flex;gap:0.35rem;padding:0.4rem 0.75rem;border-bottom:1px solid var(--border);margin-bottom:0.25rem}
.t-drop-actions button{font-size:0.68rem;padding:0.2rem 0.6rem;border:1px solid var(--border);border-radius:var(--r-sm);background:var(--bg-4);color:var(--text-2);cursor:pointer;transition:all var(--tr)}
.t-drop-actions button:hover{border-color:var(--accent);color:var(--accent)}
.t-drop label{display:flex;align-items:center;gap:0.6rem;padding:0.35rem 0.75rem;cursor:pointer;font-size:0.75rem;color:var(--text-2);transition:background var(--tr)}
.t-drop label:hover{background:var(--bg-4)}
.t-drop input[type=checkbox]{accent-color:var(--accent);width:14px;height:14px}
.t-drop .t-score{margin-left:auto;font-size:0.68rem;font-weight:600;font-variant-numeric:tabular-nums}

/* Score cards */
.scores{display:flex;gap:0.6rem;margin-bottom:1.5rem;overflow-x:auto;padding-bottom:0.5rem;scrollbar-width:thin}
.scores::-webkit-scrollbar{height:4px}.scores::-webkit-scrollbar-thumb{background:var(--border);border-radius:2px}
.sc{min-width:150px;flex-shrink:0;background:var(--bg-2);border:1px solid var(--border);border-radius:var(--r);padding:0.85rem 1rem;text-align:center;transition:border var(--tr);position:relative;overflow:hidden}
.sc:hover{border-color:var(--accent-border)}
.sc::before{content:'';position:absolute;top:0;left:0;right:0;height:3px}
.sc-g::before{background:var(--green)}.sc-a::before{background:var(--amber)}.sc-r::before{background:var(--red)}
.sc .name{font-size:0.7rem;font-weight:600;color:var(--text);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.sc .pct{font-size:1.6rem;font-weight:800;margin:0.2rem 0;font-variant-numeric:tabular-nums}
.sc .detail{font-size:0.62rem;color:var(--text-3)}
.sc .bar{height:3px;background:var(--bg-4);border-radius:2px;margin-top:0.5rem;overflow:hidden}
.sc .bar-fill{height:100%;border-radius:2px;transition:width 1s ease}

/* Matrix */
.matrix-wrap{border:1px solid var(--border);border-radius:var(--r);overflow:auto;background:var(--bg-2);box-shadow:var(--shadow);max-height:calc(100vh - 300px)}
.matrix-wrap::-webkit-scrollbar{width:6px;height:6px}
.matrix-wrap::-webkit-scrollbar-thumb{background:var(--border-2);border-radius:3px}
.matrix-wrap::-webkit-scrollbar-corner{background:var(--bg-2)}
table{width:max-content;min-width:100%;border-collapse:separate;border-spacing:0}
thead th{position:sticky;top:0;z-index:10;background:var(--bg-3);padding:0.65rem 0.6rem;text-align:center;font-size:0.65rem;font-weight:600;text-transform:uppercase;letter-spacing:0.05em;color:var(--text-2);border-bottom:1px solid var(--border);white-space:nowrap}
thead th:first-child{position:sticky;left:0;z-index:20;text-align:left;min-width:340px;background:var(--bg-3)}
thead th.tc{min-width:100px;max-width:130px}
thead th .th-s{display:block;font-size:0.6rem;font-weight:700;margin-top:0.15rem;font-variant-numeric:tabular-nums}
tbody td{padding:0.45rem 0.6rem;border-bottom:1px solid rgba(42,47,66,0.5);text-align:center;vertical-align:middle;font-size:0.75rem}
tbody td:first-child{position:sticky;left:0;z-index:5;background:var(--bg-2);text-align:left;min-width:340px;border-right:1px solid var(--border)}
tbody tr:hover td{background:var(--bg-3)}
tbody tr:hover td:first-child{background:var(--bg-4)}

/* Check info in first col */
.ck{display:flex;flex-direction:column;gap:0.1rem}
.ck-name{font-weight:500;color:var(--text);font-size:0.78rem}
.ck-meta{font-size:0.65rem;color:var(--text-3);display:flex;align-items:center;gap:0.4rem}
.ck-imp{font-size:0.58rem;font-weight:600;padding:0.1rem 0.35rem;border-radius:3px;text-transform:uppercase;letter-spacing:0.03em}
.ck-h{background:var(--red-bg);color:var(--red)}.ck-m{background:var(--amber-bg);color:var(--amber)}.ck-l{background:rgba(107,113,144,0.15);color:var(--text-3)}

/* Status cells */
.st{display:inline-flex;align-items:center;justify-content:center;width:28px;height:28px;border-radius:50%;font-size:0.75rem;font-weight:700}
.st-p{background:var(--green-bg);color:var(--green);border:1px solid var(--green-b)}
.st-f{background:var(--red-bg);color:var(--red);border:1px solid var(--red-b)}
.st-n{color:var(--text-3);font-size:0.65rem}

/* Category row */
/* Category row */
.cat-row td{background:var(--bg-4) !important;font-weight:700;color:var(--accent-2);font-size:0.72rem;padding:0.45rem 0.75rem;border-bottom:1px solid var(--border);letter-spacing:0.02em}
.cat-row td:first-child{background:var(--bg-4) !important}

/* Details button in check name */
.ck-toggle{display:inline-flex;align-items:center;gap:0.25rem;font-size:0.6rem;color:var(--accent);cursor:pointer;margin-top:0.2rem;border:none;background:none;padding:0}
.ck-toggle:hover{color:var(--accent-2)}

/* Slide-out panel */
.panel-overlay{position:fixed;inset:0;background:rgba(0,0,0,0.5);z-index:300;opacity:0;pointer-events:none;transition:opacity 0.25s ease;backdrop-filter:blur(2px)}
.panel-overlay.open{opacity:1;pointer-events:auto}
.panel{position:fixed;top:0;right:-480px;width:480px;max-width:90vw;height:100vh;background:var(--bg-2);border-left:1px solid var(--border);z-index:310;transition:right 0.3s cubic-bezier(0.4,0,0.2,1);display:flex;flex-direction:column;box-shadow:-8px 0 30px rgba(0,0,0,0.4)}
.panel.open{right:0}
.panel-header{padding:1.25rem 1.5rem;border-bottom:1px solid var(--border);display:flex;align-items:flex-start;justify-content:space-between;gap:1rem;flex-shrink:0}
.panel-title{font-size:1rem;font-weight:700;color:var(--text);line-height:1.3}
.panel-sub{font-size:0.72rem;color:var(--text-3);margin-top:0.25rem;display:flex;align-items:center;gap:0.5rem}
.panel-close{width:32px;height:32px;border-radius:50%;border:1px solid var(--border);background:var(--bg-3);color:var(--text-2);cursor:pointer;display:flex;align-items:center;justify-content:center;font-size:1rem;flex-shrink:0;transition:all var(--tr)}
.panel-close:hover{border-color:var(--red);color:var(--red);background:var(--red-bg)}
.panel-body{flex:1;overflow-y:auto;padding:1.25rem 1.5rem}
.panel-section{margin-bottom:1.25rem}
.panel-section-title{font-size:0.68rem;font-weight:600;text-transform:uppercase;letter-spacing:0.06em;color:var(--accent-2);margin-bottom:0.5rem;padding-bottom:0.35rem;border-bottom:1px solid var(--border)}
.panel-section p{font-size:0.8rem;color:var(--text-2);line-height:1.7;white-space:pre-wrap}

.footer{text-align:center;margin-top:2.5rem;padding:1.25rem;font-size:0.68rem;color:var(--text-3);border-top:1px solid var(--border)}
.footer a{color:var(--accent);text-decoration:none}
.footer a:hover{text-decoration:underline}
.hidden{display:none}
@keyframes fadeIn{from{opacity:0;transform:translateY(8px)}to{opacity:1;transform:translateY(0)}}
.fade{animation:fadeIn 0.4s ease forwards}
@media print{.toolbar,.tenant-wrap,.brand-bar{display:none}thead th:first-child,tbody td:first-child{position:static}.matrix-wrap{max-height:none;overflow:visible}}
</style>
</head>
<body>
<div class="brand-bar"></div>
<div class="header fade">
  <div class="header-inner">
    <div class="header-left">
      <div class="header-icon">&#x1F6E1;</div>
      <div>
        <h1>$(& $esc $AssessmentName)</h1>
        <div class="sub">Multi-Tenant Compliance Matrix &middot; $dateStr $timeStr</div>
      </div>
    </div>
    <div class="header-stats">
      <div class="hstat"><div class="val" style="color:var(--text)">$($TenantResults.Count)</div><div class="lbl">Tenants</div></div>
      <div class="hstat"><div class="val" style="color:var(--text)">$($allChecks.Count)</div><div class="lbl">Checks</div></div>
      <div class="hstat"><div class="val" style="color:$(if ($avgScore -ge 90) { 'var(--green)' } elseif ($avgScore -ge 70) { 'var(--amber)' } else { 'var(--red)' })">$avgScore%</div><div class="lbl">Avg Score</div></div>
    </div>
  </div>
</div>
<div class="container">
  <div class="toolbar fade">
    <input class="search" type="text" id="search" placeholder="Search checks, categories..." oninput="applyFilters()">
    <button class="pill-btn active" onclick="setFilter('all',this)">All</button>
    <button class="pill-btn" onclick="setFilter('fail',this)">Has Failures</button>
    <button class="pill-btn" onclick="setFilter('pass',this)">All Passed</button>
    <div class="tenant-wrap">
      <button class="tenant-btn" onclick="toggleDrop(event)">&#x1F465; Tenants <span style="opacity:0.5">($($tenantNames.Count))</span></button>
      <div class="t-drop" id="tDrop">
        <div class="t-drop-actions">
          <button onclick="togAll(true)">Select All</button>
          <button onclick="togAll(false)">Deselect All</button>
        </div>
        <div id="tCbs"></div>
      </div>
    </div>
  </div>
  <div class="scores fade" id="scores"></div>
  <div class="matrix-wrap fade">
    <table>
      <thead id="mHead"></thead>
      <tbody id="mBody"></tbody>
    </table>
  </div>
  <div class="panel-overlay" id="panelOverlay" onclick="closePanel()"></div>
  <div class="panel" id="panel">
    <div class="panel-header">
      <div><div class="panel-title" id="panelTitle"></div><div class="panel-sub" id="panelSub"></div></div>
      <button class="panel-close" onclick="closePanel()">&times;</button>
    </div>
    <div class="panel-body" id="panelBody"></div>
  </div>
  <div class="footer">
    Generated by <a href="https://github.com/royklo/InforcerCommunity">InforcerCommunity</a> PowerShell Module &middot; $(& $esc $AssessmentName) &middot; $dateStr
  </div>
</div>
<script>
var T=$tenantsJson,M=$matrixJson;
var vis=new Set(T.map(function(t){return t.name}));
var filt='all';

function esc(s){var d=document.createElement('div');d.textContent=s;return d.innerHTML}
function sCol(s){return s>=90?'var(--green)':s>=70?'var(--amber)':'var(--red)'}
function sClass(s){return s>=90?'sc-g':s>=70?'sc-a':'sc-r'}

function buildCbs(){
  var h='';T.forEach(function(t){
    var c=sCol(t.score);
    h+='<label><input type=checkbox checked onchange="togT(this,\''+esc(t.name).replace(/'/g,"\\'")+'\')">'+esc(t.name)+'<span class="t-score" style="color:'+c+'">'+t.score+'%</span></label>';
  });
  document.getElementById('tCbs').innerHTML=h;
}
function toggleDrop(e){e.stopPropagation();document.getElementById('tDrop').classList.toggle('open')}
document.addEventListener('click',function(){document.getElementById('tDrop').classList.remove('open')});
document.getElementById('tDrop').addEventListener('click',function(e){e.stopPropagation()});
function togT(cb,n){if(cb.checked)vis.add(n);else vis.delete(n);render()}
function togAll(on){vis=on?new Set(T.map(function(t){return t.name})):new Set();document.querySelectorAll('#tCbs input').forEach(function(c){c.checked=on});render()}
function setFilter(f,btn){filt=f;document.querySelectorAll('.pill-btn').forEach(function(b){b.classList.remove('active')});btn.classList.add('active');applyFilters()}

function applyFilters(){
  var q=document.getElementById('search').value.toLowerCase();
  var rows=document.querySelectorAll('#mBody tr');
  rows.forEach(function(row){
    if(row.classList.contains('cat-row')){row.style.display='';return}
    var n=(row.getAttribute('data-n')||'').toLowerCase();
    var c=(row.getAttribute('data-c')||'').toLowerCase();
    var show=true;
    if(q&&(n+' '+c).indexOf(q)===-1)show=false;
    if(show&&filt==='fail'){if(!row.querySelector('.st-f'))show=false}
    if(show&&filt==='pass'){if(row.querySelector('.st-f'))show=false}
    row.style.display=show?'':'none';
  });
  // Hide empty categories
  for(var i=rows.length-1;i>=0;i--){
    if(!rows[i].classList.contains('cat-row'))continue;
    var nxt=false;
    for(var j=i+1;j<rows.length;j++){
      if(rows[j].classList.contains('cat-row'))break;
      if(rows[j].style.display!=='none'){nxt=true;break}
    }
    rows[i].style.display=nxt?'':'none';
  }
}

function render(){
  var vt=T.filter(function(t){return vis.has(t.name)});
  // Scores
  var sh='';vt.forEach(function(t){
    var c=sCol(t.score),cl=sClass(t.score),bc=c;
    sh+='<div class="sc '+cl+'"><div class="name">'+esc(t.name)+'</div>';
    sh+='<div class="pct" style="color:'+c+'">'+t.score+'%</div>';
    sh+='<div class="detail">'+t.passed+' / '+t.total+' passed</div>';
    sh+='<div class="bar"><div class="bar-fill" style="width:'+t.score+'%;background:'+bc+'"></div></div></div>';
  });
  document.getElementById('scores').innerHTML=sh;
  // Head
  var th='<tr><th>Check</th>';
  vt.forEach(function(t){
    var c=sCol(t.score);
    th+='<th class="tc">'+esc(t.name)+'<span class="th-s" style="color:'+c+'">'+t.score+'%</span></th>';
  });
  th+='</tr>';document.getElementById('mHead').innerHTML=th;
  // Body
  var tb='',lc='',idx=0;
  M.forEach(function(r){
    if(r.category!==lc){lc=r.category;tb+='<tr class="cat-row"><td colspan="'+(vt.length+1)+'">'+esc(lc)+'</td></tr>'}
    var imp=String(r.importance||'').toLowerCase();
    var ic=imp==='high'?'ck-h':imp==='medium'?'ck-m':'ck-l';
    tb+='<tr data-n="'+esc(r.name)+'" data-c="'+esc(r.category)+'">';
    var hasDetail=r.desc||r.impact||r.rationale;
    tb+='<td><div class="ck"><span class="ck-name">'+esc(r.name)+'</span>';
    tb+='<span class="ck-meta">'+(r.sub?esc(r.sub)+' ':'')+'<span class="ck-imp '+ic+'">'+esc(r.importance||'')+'</span></span>';
    if(hasDetail)tb+='<button class="ck-toggle" onclick="event.stopPropagation();openPanel('+idx+')">&#x2139; Details</button>';
    tb+='</div></td>';
    vt.forEach(function(t){
      var st=r.statuses[t.name]||'N/A';
      if(st==='Pass')tb+='<td><span class="st st-p">\u2713</span></td>';
      else if(st==='Fail')tb+='<td><span class="st st-f">\u2717</span></td>';
      else tb+='<td><span class="st st-n">\u2014</span></td>';
    });
    tb+='</tr>';
    idx++;
  });
  document.getElementById('mBody').innerHTML=tb;
  applyFilters();
}
function openPanel(idx){
  var r=M[idx];if(!r)return;
  document.getElementById('panelTitle').textContent=r.name;
  var impC=String(r.importance||'').toLowerCase();
  var ic=impC==='high'?'ck-h':impC==='medium'?'ck-m':'ck-l';
  document.getElementById('panelSub').innerHTML=(r.sub?esc(r.sub)+' &middot; ':'')+
    '<span class="ck-imp '+ic+'" style="font-size:0.65rem">'+esc(r.importance||'')+'</span>'+
    ' &middot; '+esc(r.category);
  var h='';
  if(r.desc){h+='<div class="panel-section"><div class="panel-section-title">Description</div><p>'+r.desc.replace(/\\n/g,'\n')+'</p></div>'}
  if(r.impact){h+='<div class="panel-section"><div class="panel-section-title">Impact</div><p>'+r.impact.replace(/\\n/g,'\n')+'</p></div>'}
  if(r.rationale){h+='<div class="panel-section"><div class="panel-section-title">Rationale</div><p>'+r.rationale.replace(/\\n/g,'\n')+'</p></div>'}
  document.getElementById('panelBody').innerHTML=h;
  document.getElementById('panelOverlay').classList.add('open');
  document.getElementById('panel').classList.add('open');
}
function closePanel(){
  document.getElementById('panelOverlay').classList.remove('open');
  document.getElementById('panel').classList.remove('open');
}
document.addEventListener('keydown',function(e){if(e.key==='Escape')closePanel()});
buildCbs();render();
</script>
</body>
</html>
"@)

    return $sb.ToString()
}
