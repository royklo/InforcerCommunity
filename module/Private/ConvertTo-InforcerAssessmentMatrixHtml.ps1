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
:root{
  --navy:rgb(23,27,58);--cyan:rgb(23,139,219);--bg:#f1f5f9;--card:#fff;
  --border:#d1d5db;--border-light:#e5e7eb;--text:#171b3a;--text-body:rgb(71,85,105);
  --text-secondary:rgb(100,116,139);--pass:#16a34a;--pass-bg:#dcfce7;
  --fail:#dc2626;--fail-bg:#fee2e2;--warn:#d97706;--warn-bg:#fef3c7;
  --accent:#178BDB;--accent-2:#4338ca;--r:8px;--r-sm:6px;
  --shadow:0 1px 3px rgba(0,0,0,0.05);--shadow-lg:0 8px 24px rgba(0,0,0,0.12);
  --tr:0.2s ease;
}
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:var(--bg);color:var(--text-body);line-height:1.5;font-size:0.8125rem;overflow:hidden;height:100vh;display:flex;flex-direction:column}

/* Cover — matches single-tenant report */
.report-cover{position:relative;width:100%;overflow:hidden;margin-bottom:1.5rem;background:var(--navy)}
.cover-bg{position:absolute;inset:0;overflow:hidden}
.cover-bg .orb{position:absolute;border-radius:50%;filter:blur(80px);opacity:0.3}
.orb-1{width:400px;height:400px;background:#0025ce;top:-100px;right:-50px}
.orb-2{width:300px;height:300px;background:#00ccff;bottom:-80px;left:10%}
.orb-3{width:250px;height:250px;background:#7300ff;top:50%;left:50%;transform:translate(-50%,-50%)}
.orb-4{width:200px;height:200px;background:#3894ff;bottom:-40px;right:20%}
.cover-content{position:relative;z-index:1;padding:2rem 3rem;display:flex;align-items:center;gap:2rem}
.cover-icon{font-size:2.5rem;color:rgba(255,255,255,0.9);flex-shrink:0}
.cover-divider{width:1px;align-self:stretch;background:rgba(255,255,255,0.18);margin:0 0.25rem}
.cover-text{flex:1}
.cover-title{font-size:1.375rem;font-weight:700;color:#fff;line-height:1.25;letter-spacing:-0.01em}
.cover-subtitle{font-size:0.8125rem;color:rgba(255,255,255,0.6);margin-top:0.2rem}
.cover-meta{display:flex;gap:2rem;margin-top:0.75rem}
.cover-meta-item{display:flex;flex-direction:column}
.cover-meta-item dt{font-size:0.625rem;text-transform:uppercase;letter-spacing:0.08em;color:rgba(255,255,255,0.4);font-weight:600}
.cover-meta-item dd{font-size:0.875rem;color:#fff;font-weight:600}
.cover-accent{position:absolute;bottom:0;left:0;right:0;height:3px;z-index:2;background:linear-gradient(90deg,#0025ce,#00ccff,#3894ff,#7300ff,#cf86ff)}

.container{max-width:100%;margin:0 auto;padding:0 1.5rem 0;flex:1;display:flex;flex-direction:column;min-height:0}

/* Toolbar */
.toolbar{display:flex;align-items:center;gap:0.6rem;margin-bottom:1rem;flex-wrap:wrap}
.search{flex:1;min-width:180px;padding:0.5rem 1rem;border-radius:var(--r);background:var(--card);border:1px solid var(--border);color:var(--text);font-size:0.8125rem;outline:none;transition:border var(--tr)}
.search:focus{border-color:var(--cyan)}
.pill-btn{padding:0.45rem 0.9rem;border:1px solid var(--border);border-radius:var(--r);font-size:0.78rem;font-weight:500;background:var(--card);cursor:pointer;transition:all 0.15s;user-select:none}
.pill-btn:hover{background:#f8fafc}.pill-btn.active{background:var(--navy);color:#fff;border-color:var(--navy)}
.tenant-wrap{position:relative}
.tenant-btn{padding:0.45rem 1rem;border:2px solid var(--cyan);border-radius:var(--r);font-size:0.78rem;font-weight:600;background:var(--card);color:var(--cyan);cursor:pointer;display:flex;align-items:center;gap:0.4rem;transition:all var(--tr)}
.tenant-btn:hover{background:var(--cyan);color:#fff}

/* Tenant dropdown */
.t-drop{display:none;position:absolute;top:calc(100% + 6px);right:0;background:var(--card);border:1px solid var(--border);border-radius:var(--r);box-shadow:var(--shadow-lg);z-index:100;min-width:260px;max-height:420px;overflow-y:auto;padding:0.5rem 0}
.t-drop.open{display:block}
.t-drop-actions{display:flex;gap:0.35rem;padding:0.4rem 0.75rem;border-bottom:1px solid var(--border-light);margin-bottom:0.25rem}
.t-drop-actions button{font-size:0.7rem;padding:0.2rem 0.6rem;border:1px solid var(--border);border-radius:var(--r-sm);background:var(--card);cursor:pointer;transition:all var(--tr)}
.t-drop-actions button:hover{border-color:var(--cyan)}
.t-drop label{display:flex;align-items:center;gap:0.6rem;padding:0.35rem 0.75rem;cursor:pointer;font-size:0.78rem;color:var(--text-body);transition:background var(--tr)}
.t-drop label:hover{background:#f8fafc}
.t-drop input[type=checkbox]{accent-color:var(--cyan);width:14px;height:14px}
.t-drop .t-score{margin-left:auto;font-size:0.72rem;font-weight:600;font-variant-numeric:tabular-nums}

/* Column header detail */
thead th .th-detail{display:block;font-size:0.58rem;font-weight:400;color:var(--text-secondary);margin-top:0.1rem}

/* Matrix */
.matrix-wrap{border:1px solid var(--border);border-radius:var(--r);overflow:auto;background:var(--card);box-shadow:var(--shadow);flex:1;min-height:0}
table{width:max-content;min-width:100%;border-collapse:separate;border-spacing:0}
thead th{position:sticky;top:0;z-index:10;background:#f8fafc;padding:0.65rem 0.6rem;text-align:center;font-size:0.6875rem;font-weight:600;text-transform:uppercase;letter-spacing:0.04em;color:var(--navy);border-bottom:2px solid var(--border);white-space:nowrap}
thead th:first-child{position:sticky;left:0;z-index:20;text-align:left;min-width:340px;background:#f8fafc}
thead th.tc{min-width:100px;max-width:130px}
thead th .th-s{display:block;font-size:0.6rem;font-weight:700;margin-top:0.15rem;font-variant-numeric:tabular-nums}
tbody td{padding:0.5rem 0.6rem;border-bottom:1px solid var(--border-light);text-align:center;vertical-align:middle;font-size:0.78rem}
tbody td:first-child{position:sticky;left:0;z-index:5;background:var(--card);text-align:left;min-width:340px;border-right:1px solid var(--border)}
tbody tr:hover td{background:#f8fafc}
tbody tr:hover td:first-child{background:#f3f4f6}

/* Check info in first col */
.ck{display:flex;flex-direction:column;gap:0.1rem}
.ck-name{font-weight:500;color:var(--navy);font-size:0.8125rem}
.ck-meta{font-size:0.6875rem;color:var(--text-secondary);display:flex;align-items:center;gap:0.4rem}
.ck-imp{font-size:0.6rem;font-weight:600;padding:0.1rem 0.35rem;border-radius:3px;text-transform:uppercase;letter-spacing:0.03em}
.ck-h{background:var(--fail-bg);color:#991b1b}.ck-m{background:var(--warn-bg);color:#92400e}.ck-l{background:#f1f5f9;color:var(--text-secondary)}

/* Status cells */
.st{display:inline-flex;align-items:center;justify-content:center;width:28px;height:28px;border-radius:50%;font-size:0.78rem;font-weight:700}
.st-p{background:var(--pass-bg);color:#166534;border:1px solid rgba(22,163,74,0.2)}
.st-f{background:var(--fail-bg);color:#991b1b;border:1px solid rgba(220,38,38,0.2)}
.st-n{color:#d1d5db;font-size:0.65rem}

/* Category row */
.cat-row td{background:#eef2ff !important;font-weight:700;color:var(--navy);font-size:0.78rem;padding:0.5rem 0.75rem;border-bottom:2px solid var(--border);letter-spacing:0.02em}
.cat-row td:first-child{background:#eef2ff !important}

/* Details button */
.ck-toggle{display:inline-flex;align-items:center;gap:0.25rem;font-size:0.65rem;color:var(--cyan);cursor:pointer;margin-top:0.2rem;border:none;background:none;padding:0}
.ck-toggle:hover{color:var(--accent-2)}

/* Slide-out panel */
.panel-overlay{position:fixed;inset:0;background:rgba(0,0,0,0.35);z-index:300;opacity:0;pointer-events:none;transition:opacity 0.25s ease;backdrop-filter:blur(2px)}
.panel-overlay.open{opacity:1;pointer-events:auto}
.panel{position:fixed;top:0;right:-500px;width:500px;max-width:90vw;height:100vh;background:var(--card);border-left:1px solid var(--border);z-index:310;transition:right 0.3s cubic-bezier(0.4,0,0.2,1);display:flex;flex-direction:column;box-shadow:-4px 0 20px rgba(0,0,0,0.1)}
.panel.open{right:0}
.panel-header{padding:1.25rem 1.5rem;border-bottom:1px solid var(--border-light);display:flex;align-items:flex-start;justify-content:space-between;gap:1rem;flex-shrink:0;background:#f8fafc}
.panel-title{font-size:1rem;font-weight:700;color:var(--navy);line-height:1.3}
.panel-sub{font-size:0.75rem;color:var(--text-secondary);margin-top:0.25rem;display:flex;align-items:center;gap:0.5rem}
.panel-close{width:32px;height:32px;border-radius:50%;border:1px solid var(--border);background:var(--card);color:var(--text-secondary);cursor:pointer;display:flex;align-items:center;justify-content:center;font-size:1.1rem;flex-shrink:0;transition:all var(--tr)}
.panel-close:hover{border-color:var(--fail);color:var(--fail);background:var(--fail-bg)}
.panel-body{flex:1;overflow-y:auto;padding:1.25rem 1.5rem}
.panel-section{margin-bottom:1.25rem}
.panel-section-title{font-size:0.6875rem;font-weight:600;text-transform:uppercase;letter-spacing:0.05em;color:var(--cyan);margin-bottom:0.5rem;padding-bottom:0.35rem;border-bottom:1px solid var(--border-light)}
.panel-section p{font-size:0.8125rem;color:var(--text-body);line-height:1.7;white-space:pre-wrap}

.footer{text-align:center;padding:0.6rem 1rem;font-size:0.68rem;color:var(--text-secondary);border-top:1px solid var(--border);flex-shrink:0}
.footer a{color:var(--cyan);text-decoration:none}
.hidden{display:none}
@keyframes fadeIn{from{opacity:0;transform:translateY(10px)}to{opacity:1;transform:translateY(0)}}
.animate-in{opacity:0;animation:fadeIn 0.5s ease forwards}
@media print{.toolbar,.tenant-wrap{display:none}thead th:first-child,tbody td:first-child{position:static}.matrix-wrap{max-height:none;overflow:visible}.report-cover{print-color-adjust:exact;-webkit-print-color-adjust:exact}}
</style>
</head>
<body>
<div class="report-cover animate-in">
  <div class="cover-bg"><div class="orb orb-1"></div><div class="orb orb-2"></div><div class="orb orb-3"></div><div class="orb orb-4"></div></div>
  <div class="cover-content">
    <div class="cover-icon">&#x1F6E1;</div>
    <div class="cover-divider"></div>
    <div class="cover-text">
      <div class="cover-title">$(& $esc $AssessmentName)</div>
      <div class="cover-subtitle">Multi-Tenant Compliance Matrix</div>
      <div class="cover-meta">
        <div class="cover-meta-item"><dt>Tenants</dt><dd>$($TenantResults.Count)</dd></div>
        <div class="cover-meta-item"><dt>Checks</dt><dd>$($allChecks.Count)</dd></div>
        <div class="cover-meta-item"><dt>Avg Score</dt><dd>$avgScore%</dd></div>
        <div class="cover-meta-item"><dt>Date</dt><dd>$dateStr</dd></div>
        <div class="cover-meta-item"><dt>Time</dt><dd>$timeStr</dd></div>
      </div>
    </div>
  </div>
  <div class="cover-accent"></div>
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
  <div class="matrix-wrap animate-in" style="animation-delay:0.2s">
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
function sCol(s){return s>=90?'var(--pass)':s>=70?'var(--cyan)':'var(--fail)'}
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
  // Head with score + passed/total
  var th='<tr><th>Check</th>';
  vt.forEach(function(t){
    var c=sCol(t.score);
    th+='<th class="tc">'+esc(t.name)+'<span class="th-s" style="color:'+c+'">'+t.score+'%</span><span class="th-detail">'+t.passed+' / '+t.total+' passed</span></th>';
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
