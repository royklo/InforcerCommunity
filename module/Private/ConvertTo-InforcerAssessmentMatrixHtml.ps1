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

    # Build unique check list (union of all checks across tenants, ordered by category + name)
    $checkIndex = [ordered]@{}
    foreach ($tr in $TenantResults) {
        foreach ($c in $tr.Checks) {
            $key = "$($c.category)|$($c.name)"
            if (-not $checkIndex.Contains($key)) {
                $checkIndex[$key] = @{ name = $c.name; category = $c.category; subCategory = $c.subCategory; importance = $c.importance; key = $c.key }
            }
        }
    }
    $allChecks = @($checkIndex.Values)

    # Build per-tenant lookup: checkKey -> status
    $tenantCheckMap = [ordered]@{}
    foreach ($tr in $TenantResults) {
        $map = @{}
        foreach ($c in $tr.Checks) {
            $key = "$($c.category)|$($c.name)"
            $map[$key] = $c.Status
        }
        $tenantCheckMap[$tr.TenantName] = $map
    }

    $tenantNames = @($TenantResults | ForEach-Object { $_.TenantName })
    $dateStr = Get-Date -Format 'yyyy-MM-dd'
    $timeStr = Get-Date -Format 'HH:mm'

    # Build tenant data JSON for JS
    $tenantsJson = $TenantResults | ForEach-Object {
        @{ name = $_.TenantName; id = $_.TenantId; score = $_.Score; passed = $_.Passed; failed = $_.Failed; total = $_.TotalChecks }
    } | ConvertTo-Json -Depth 100 -Compress

    # Build matrix data JSON
    $matrixRows = [System.Collections.Generic.List[object]]::new()
    foreach ($ck in $allChecks) {
        $key = "$($ck.category)|$($ck.name)"
        $statuses = [ordered]@{}
        foreach ($tn in $tenantNames) {
            $st = if ($tenantCheckMap[$tn].ContainsKey($key)) { $tenantCheckMap[$tn][$key] } else { 'N/A' }
            $statuses[$tn] = $st
        }
        [void]$matrixRows.Add(@{
            name       = $ck.name
            category   = $ck.category
            sub        = $ck.subCategory
            importance = $ck.importance
            statuses   = $statuses
        })
    }
    $matrixJson = $matrixRows | ConvertTo-Json -Depth 100 -Compress

    $sb = [System.Text.StringBuilder]::new(32000)
    [void]$sb.Append(@"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>$(& $esc $AssessmentName) - Multi-Tenant Matrix</title>
<style>
:root{--navy:rgb(23,27,58);--cyan:rgb(23,139,219);--bg:#f1f5f9;--card:#fff;--border:#d1d5db;--border-light:#e5e7eb;
--text:#171b3a;--text-body:rgb(71,85,105);--text-secondary:rgb(100,116,139);
--pass:#16a34a;--pass-bg:#dcfce7;--fail:#dc2626;--fail-bg:#fee2e2;--warn:#d97706;--warn-bg:#fef3c7;--radius:8px}
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:var(--bg);color:var(--text-body);line-height:1.5;font-size:0.8125rem}
.cover{position:relative;width:100%;overflow:hidden;margin-bottom:1.5rem;background:var(--navy)}
.cover-bg{position:absolute;inset:0;overflow:hidden}
.cover-bg .orb{position:absolute;border-radius:50%;filter:blur(80px);opacity:0.3}
.orb-1{width:400px;height:400px;background:#0025ce;top:-100px;right:-50px}
.orb-2{width:300px;height:300px;background:#00ccff;bottom:-80px;left:10%}
.orb-3{width:250px;height:250px;background:#7300ff;top:50%;left:50%;transform:translate(-50%,-50%)}
.cover-content{position:relative;z-index:1;padding:1.75rem 2.5rem;display:flex;align-items:center;gap:1.5rem}
.cover-icon{font-size:2rem;color:rgba(255,255,255,0.9)}
.cover-divider{width:1px;align-self:stretch;background:rgba(255,255,255,0.18)}
.cover-text{flex:1}
.cover-title{font-size:1.25rem;font-weight:700;color:#fff;letter-spacing:-0.01em}
.cover-sub{font-size:0.75rem;color:rgba(255,255,255,0.55);margin-top:0.15rem}
.cover-meta{display:flex;gap:1.5rem;margin-top:0.5rem}
.cover-meta dt{font-size:0.6rem;text-transform:uppercase;letter-spacing:0.08em;color:rgba(255,255,255,0.35);font-weight:600}
.cover-meta dd{font-size:0.8125rem;color:#fff;font-weight:600}
.cover-accent{position:absolute;bottom:0;left:0;right:0;height:3px;z-index:2;background:linear-gradient(90deg,#0025ce,#00ccff,#3894ff,#7300ff)}
.container{max-width:100%;margin:0 auto;padding:0 1.5rem 2rem}

/* Toolbar */
.toolbar{display:flex;align-items:center;gap:0.75rem;margin-bottom:1rem;flex-wrap:wrap}
.toolbar input{flex:1;min-width:180px;padding:0.45rem 0.85rem;border:1px solid var(--border);border-radius:var(--radius);font-size:0.8125rem;outline:none;background:var(--card)}
.toolbar input:focus{border-color:var(--cyan)}
.filter-btn{padding:0.4rem 0.85rem;border:1px solid var(--border);border-radius:var(--radius);font-size:0.75rem;font-weight:500;background:var(--card);cursor:pointer;transition:all 0.15s;user-select:none}
.filter-btn:hover{background:#eef2ff}.filter-btn.active{background:var(--navy);color:#fff;border-color:var(--navy)}
.tenant-filter-btn{padding:0.4rem 0.85rem;border:1px solid var(--border);border-radius:var(--radius);font-size:0.75rem;background:var(--card);cursor:pointer;position:relative}
.tenant-filter-btn:hover{border-color:var(--cyan)}

/* Tenant dropdown */
.tenant-dropdown{display:none;position:absolute;top:100%;right:0;margin-top:0.35rem;background:var(--card);border:1px solid var(--border);border-radius:var(--radius);box-shadow:0 8px 24px rgba(0,0,0,0.12);z-index:50;min-width:220px;max-height:400px;overflow-y:auto;padding:0.5rem}
.tenant-dropdown.open{display:block}
.tenant-dropdown label{display:flex;align-items:center;gap:0.5rem;padding:0.35rem 0.5rem;border-radius:4px;cursor:pointer;font-size:0.78rem;white-space:nowrap}
.tenant-dropdown label:hover{background:#f1f5f9}
.tenant-dropdown input[type=checkbox]{accent-color:var(--cyan)}
.tenant-actions{display:flex;gap:0.35rem;padding:0.35rem 0.5rem;border-bottom:1px solid var(--border-light);margin-bottom:0.35rem}
.tenant-actions button{font-size:0.7rem;padding:0.2rem 0.5rem;border:1px solid var(--border);border-radius:4px;background:var(--card);cursor:pointer}
.tenant-actions button:hover{background:#f1f5f9}

/* Score cards row */
.scores-row{display:flex;gap:0.75rem;margin-bottom:1.25rem;overflow-x:auto;padding-bottom:0.5rem}
.score-card{min-width:140px;flex-shrink:0;background:var(--card);border:1px solid var(--border);border-radius:var(--radius);padding:0.75rem 1rem;text-align:center;box-shadow:0 1px 3px rgba(0,0,0,0.05)}
.score-card .sc-name{font-size:0.7rem;font-weight:600;color:var(--navy);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.score-card .sc-pct{font-size:1.5rem;font-weight:800;margin:0.15rem 0}
.score-card .sc-detail{font-size:0.65rem;color:var(--text-secondary)}

/* Matrix table */
.matrix-wrap{overflow-x:auto;border:1px solid var(--border);border-radius:var(--radius);background:var(--card);box-shadow:0 1px 3px rgba(0,0,0,0.05)}
.matrix{width:max-content;min-width:100%;border-collapse:separate;border-spacing:0;font-size:0.78rem}
.matrix thead th{position:sticky;top:0;z-index:10;background:#f8fafc;padding:0.6rem 0.75rem;text-align:center;font-size:0.6875rem;font-weight:600;text-transform:uppercase;letter-spacing:0.04em;color:var(--navy);border-bottom:2px solid var(--border);white-space:nowrap}
.matrix thead th:first-child{position:sticky;left:0;z-index:20;text-align:left;min-width:320px;background:#f8fafc}
.matrix thead th.tenant-col{min-width:110px;max-width:140px;writing-mode:horizontal-tb}
.matrix thead th .th-score{font-size:0.65rem;font-weight:400;color:var(--text-secondary);display:block}
.matrix tbody td{padding:0.5rem 0.75rem;border-bottom:1px solid var(--border-light);text-align:center;white-space:nowrap}
.matrix tbody td:first-child{position:sticky;left:0;z-index:5;background:var(--card);text-align:left;font-weight:500;color:var(--navy);white-space:normal;min-width:320px}
.matrix tbody tr:hover td{background:#fafbfc}
.matrix tbody tr:hover td:first-child{background:#f3f4f6}
.check-info{display:flex;flex-direction:column;gap:0.1rem}
.check-name{font-weight:500;color:var(--navy)}
.check-meta{font-size:0.68rem;color:var(--text-secondary)}
.check-imp{font-size:0.6rem;font-weight:600;padding:0.05rem 0.35rem;border-radius:3px;display:inline-block}
.imp-h{background:#fee2e2;color:#991b1b}.imp-m{background:#fef3c7;color:#92400e}.imp-l{background:#f1f5f9;color:var(--text-secondary)}

/* Status cells */
.cell-pass{background:var(--pass-bg);color:#166534;font-weight:600;font-size:0.75rem}
.cell-fail{background:var(--fail-bg);color:#991b1b;font-weight:600;font-size:0.75rem}
.cell-na{background:#f9fafb;color:#d1d5db;font-size:0.7rem}

/* Category separator */
.cat-row td{background:#eef2ff !important;font-weight:700;color:var(--navy);font-size:0.78rem;padding:0.5rem 0.75rem;border-bottom:2px solid var(--border)}
.cat-row td:first-child{background:#eef2ff !important}

.footer{text-align:center;margin-top:2rem;padding:1rem;font-size:0.7rem;color:var(--text-secondary);border-top:1px solid var(--border)}
.footer a{color:var(--cyan);text-decoration:none}
.hidden{display:none}
@media print{.toolbar,.tenant-filter-btn{display:none}.matrix thead th:first-child,.matrix tbody td:first-child{position:static}}
</style>
</head>
<body>
<div class="cover">
  <div class="cover-bg"><div class="orb orb-1"></div><div class="orb orb-2"></div><div class="orb orb-3"></div></div>
  <div class="cover-content">
    <div class="cover-icon">&#x1F6E1;</div>
    <div class="cover-divider"></div>
    <div class="cover-text">
      <div class="cover-title">$(& $esc $AssessmentName)</div>
      <div class="cover-sub">Multi-Tenant Assessment Matrix</div>
      <div class="cover-meta">
        <div><dt>Tenants</dt><dd>$($TenantResults.Count)</dd></div>
        <div><dt>Checks</dt><dd>$($allChecks.Count)</dd></div>
        <div><dt>Date</dt><dd>$dateStr</dd></div>
        <div><dt>Time</dt><dd>$timeStr</dd></div>
      </div>
    </div>
  </div>
  <div class="cover-accent"></div>
</div>
<div class="container">
  <div class="toolbar">
    <input type="text" id="search" placeholder="Search checks..." oninput="applyFilters()">
    <button class="filter-btn active" onclick="setFilter('all',this)">All</button>
    <button class="filter-btn" onclick="setFilter('fail',this)">Has Failures</button>
    <button class="filter-btn" onclick="setFilter('pass',this)">All Passed</button>
    <div style="position:relative">
      <button class="tenant-filter-btn" onclick="toggleTenantDropdown(event)">&#x1F465; Tenants ($($tenantNames.Count))</button>
      <div class="tenant-dropdown" id="tenantDropdown">
        <div class="tenant-actions">
          <button onclick="toggleAllTenants(true)">Select All</button>
          <button onclick="toggleAllTenants(false)">Deselect All</button>
        </div>
        <div id="tenantCheckboxes"></div>
      </div>
    </div>
  </div>
  <div class="scores-row" id="scoresRow"></div>
  <div class="matrix-wrap">
    <table class="matrix" id="matrixTable">
      <thead id="matrixHead"></thead>
      <tbody id="matrixBody"></tbody>
    </table>
  </div>
  <div class="footer">
    Generated by <a href="https://github.com/royklo/InforcerCommunity">InforcerCommunity</a> PowerShell Module &middot; $(& $esc $AssessmentName) &middot; $dateStr
  </div>
</div>
<script>
var TENANTS = $tenantsJson;
var MATRIX = $matrixJson;
var visibleTenants = new Set(TENANTS.map(function(t){return t.name}));
var currentFilter = 'all';

function esc(s){var d=document.createElement('div');d.textContent=s;return d.innerHTML}
function scoreColor(s){return s>=90?'var(--pass)':s>=70?'var(--cyan)':'var(--fail)'}

function buildTenantCheckboxes(){
  var h='';
  TENANTS.forEach(function(t){
    h+='<label><input type="checkbox" checked onchange="toggleTenant(this,\''+esc(t.name)+'\')">' +esc(t.name)+' ('+t.score+'%)</label>';
  });
  document.getElementById('tenantCheckboxes').innerHTML=h;
}

function toggleTenantDropdown(e){
  e.stopPropagation();
  document.getElementById('tenantDropdown').classList.toggle('open');
}
document.addEventListener('click',function(){document.getElementById('tenantDropdown').classList.remove('open')});
document.getElementById('tenantDropdown').addEventListener('click',function(e){e.stopPropagation()});

function toggleTenant(cb,name){
  if(cb.checked)visibleTenants.add(name);else visibleTenants.delete(name);
  render();
}
function toggleAllTenants(on){
  visibleTenants=on?new Set(TENANTS.map(function(t){return t.name})):new Set();
  document.querySelectorAll('#tenantCheckboxes input').forEach(function(cb){cb.checked=on});
  render();
}

function setFilter(f,btn){
  currentFilter=f;
  document.querySelectorAll('.filter-btn').forEach(function(b){b.classList.remove('active')});
  btn.classList.add('active');
  applyFilters();
}

function applyFilters(){
  var q=document.getElementById('search').value.toLowerCase();
  document.querySelectorAll('#matrixBody tr').forEach(function(row){
    if(row.classList.contains('cat-row')){row.style.display='';return}
    var name=row.getAttribute('data-name')||'';
    var cat=row.getAttribute('data-cat')||'';
    var show=true;
    if(q&&(name+' '+cat).toLowerCase().indexOf(q)===-1)show=false;
    if(show&&currentFilter==='fail'){
      var hasF=false;
      var cells=row.querySelectorAll('td.cell-fail');
      if(cells.length===0)show=false;
    }
    if(show&&currentFilter==='pass'){
      var hasF2=row.querySelectorAll('td.cell-fail');
      if(hasF2.length>0)show=false;
    }
    row.style.display=show?'':'none';
  });
  // Hide empty category rows
  var lastCat=null;
  var rows=document.querySelectorAll('#matrixBody tr');
  for(var i=rows.length-1;i>=0;i--){
    if(rows[i].classList.contains('cat-row')){
      var nextVis=false;
      for(var j=i+1;j<rows.length;j++){
        if(rows[j].classList.contains('cat-row'))break;
        if(rows[j].style.display!=='none'){nextVis=true;break}
      }
      rows[i].style.display=nextVis?'':'none';
    }
  }
}

function render(){
  var vt=TENANTS.filter(function(t){return visibleTenants.has(t.name)});

  // Score cards
  var sh='';
  vt.forEach(function(t){
    sh+='<div class="score-card"><div class="sc-name">'+esc(t.name)+'</div>';
    sh+='<div class="sc-pct" style="color:'+scoreColor(t.score)+'">'+t.score+'%</div>';
    sh+='<div class="sc-detail">'+t.passed+'/'+t.total+' passed</div></div>';
  });
  document.getElementById('scoresRow').innerHTML=sh;

  // Table header
  var th='<tr><th>Check</th>';
  vt.forEach(function(t){
    th+='<th class="tenant-col">'+esc(t.name)+'<span class="th-score">'+t.score+'%</span></th>';
  });
  th+='</tr>';
  document.getElementById('matrixHead').innerHTML=th;

  // Table body
  var tb='';var lastCat='';
  MATRIX.forEach(function(row){
    if(row.category!==lastCat){
      lastCat=row.category;
      tb+='<tr class="cat-row"><td colspan="'+(vt.length+1)+'">'+esc(lastCat)+'</td></tr>';
    }
    var impC=row.importance==='High'||row.importance==='high'?'imp-h':(row.importance==='Medium'||row.importance==='medium'?'imp-m':'imp-l');
    tb+='<tr data-name="'+esc(row.name)+'" data-cat="'+esc(row.category)+'">';
    tb+='<td><div class="check-info"><span class="check-name">'+esc(row.name)+'</span>';
    tb+='<span class="check-meta">'+esc(row.sub||'')+' <span class="check-imp '+impC+'">'+esc(row.importance||'')+'</span></span></div></td>';
    vt.forEach(function(t){
      var st=row.statuses[t.name]||'N/A';
      var cls=st==='Pass'?'cell-pass':st==='Fail'?'cell-fail':'cell-na';
      var icon=st==='Pass'?'\u2713':st==='Fail'?'\u2717':'\u2014';
      tb+='<td class="'+cls+'">'+icon+'</td>';
    });
    tb+='</tr>';
  });
  document.getElementById('matrixBody').innerHTML=tb;
  applyFilters();
}

buildTenantCheckboxes();
render();
</script>
</body>
</html>
"@)

    return $sb.ToString()
}
