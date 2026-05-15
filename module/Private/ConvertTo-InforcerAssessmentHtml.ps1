function ConvertTo-InforcerAssessmentHtml {
    <#
    .SYNOPSIS
        Converts assessment check results into a self-contained HTML report.
    .PARAMETER AssessmentName
        Display name of the assessment.
    .PARAMETER TenantName
        Display name of the tenant.
    .PARAMETER Checks
        Array of processed check objects (with Status, Scores, Violations, etc.).
    .PARAMETER Score
        Compliance percentage.
    .PARAMETER TotalChecks
        Total number of checks.
    .PARAMETER Passed
        Number of passed checks.
    .PARAMETER Failed
        Number of failed checks.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)] [string]$AssessmentName,
        [Parameter(Mandatory)] [string]$TenantName,
        [Parameter(Mandatory)] [array]$Checks,
        [Parameter(Mandatory)] [double]$Score,
        [Parameter(Mandatory)] [int]$TotalChecks,
        [Parameter(Mandatory)] [int]$Passed,
        [Parameter(Mandatory)] [int]$Failed
    )

    $placeholders = @('[Multiple Objects Evaluated]', '[unknown name]', '[unknown id]')
    $esc = { param([string]$s) [System.Web.HttpUtility]::HtmlEncode($s) }
    $sb = [System.Text.StringBuilder]::new(64000)

    $scoreColor = if ($Score -ge 90) { '#16a34a' } elseif ($Score -ge 70) { '#178BDB' } else { '#dc2626' }
    $circumference = [math]::Round(2 * [math]::PI * 60, 1)
    $dashOffset = [math]::Round($circumference * (1 - $Score / 100), 1)
    $passBarPct = if ($TotalChecks -gt 0) { [math]::Round($Passed / $TotalChecks * 100) } else { 0 }
    $failBarPct = if ($TotalChecks -gt 0) { [math]::Round($Failed / $TotalChecks * 100) } else { 0 }
    $dateStr = Get-Date -Format 'yyyy-MM-dd'
    $timeStr = Get-Date -Format 'HH:mm'

    # Group checks by category
    $categories = [ordered]@{}
    foreach ($c in $Checks) {
        $cat = if ($c.category) { $c.category } else { 'Other' }
        if (-not $categories.Contains($cat)) { $categories[$cat] = [System.Collections.Generic.List[object]]::new() }
        [void]$categories[$cat].Add($c)
    }

    [void]$sb.Append(@"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>$(& $esc $AssessmentName) - $(& $esc $TenantName)</title>
<style>
:root{--navy:rgb(23,27,58);--cyan:rgb(23,139,219);--bg:#f1f5f9;--card:#fff;--border:#d1d5db;--border-light:#e5e7eb;--text:#171b3a;--text-body:rgb(71,85,105);--text-secondary:rgb(100,116,139);--pass:#16a34a;--pass-bg:#dcfce7;--fail:#dc2626;--fail-bg:#fee2e2;--warn:#d97706;--warn-bg:#fef3c7;--radius:8px}
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:var(--bg);color:var(--text-body);line-height:1.625;font-size:0.875rem}
.container{max-width:1440px;margin:0 auto;padding:1.5rem}
.report-cover{position:relative;width:100%;overflow:hidden;margin-bottom:1.5rem;background:var(--navy)}
.cover-bg{position:absolute;inset:0;overflow:hidden}
.cover-bg .orb{position:absolute;border-radius:50%;filter:blur(80px);opacity:0.3}
.orb-1{width:400px;height:400px;background:#0025ce;top:-100px;right:-50px}
.orb-2{width:300px;height:300px;background:#00ccff;bottom:-80px;left:10%}
.orb-3{width:250px;height:250px;background:#7300ff;top:50%;left:50%;transform:translate(-50%,-50%)}
.orb-4{width:200px;height:200px;background:#3894ff;bottom:-40px;right:20%}
.cover-content{position:relative;z-index:1;padding:2rem 3rem;display:flex;align-items:center;gap:2rem}
.cover-divider{width:1px;align-self:stretch;background:rgba(255,255,255,0.18);margin:0 0.25rem}
.cover-text{flex:1}
.cover-title{font-size:1.375rem;font-weight:700;color:#fff;line-height:1.25;letter-spacing:-0.01em}
.cover-subtitle{font-size:0.8125rem;color:rgba(255,255,255,0.6);margin-top:0.2rem}
.cover-meta{display:flex;gap:2rem;margin-top:0.75rem}
.cover-meta-item{display:flex;flex-direction:column}
.cover-meta-item dt{font-size:0.625rem;text-transform:uppercase;letter-spacing:0.08em;color:rgba(255,255,255,0.4);font-weight:600}
.cover-meta-item dd{font-size:0.875rem;color:#fff;font-weight:600}
.cover-accent{position:absolute;bottom:0;left:0;right:0;height:3px;z-index:2;background:linear-gradient(90deg,#0025ce,#00ccff,#3894ff,#7300ff,#cf86ff)}
.cover-icon{font-size:2.5rem;color:rgba(255,255,255,0.9);flex-shrink:0}
.score-section{display:grid;grid-template-columns:200px 1fr;gap:1.5rem;margin-bottom:1.5rem}
.score-ring-card{background:var(--card);border:1px solid var(--border);border-radius:var(--radius);padding:1.25rem;display:flex;flex-direction:column;align-items:center;justify-content:center;box-shadow:0 1px 3px rgba(0,0,0,0.05)}
.score-ring-wrap{position:relative;width:130px;height:130px}
.score-ring-wrap svg{transform:rotate(-90deg)}
.score-ring-bg{fill:none;stroke:#e2e8f0;stroke-width:10}
.score-ring-fg{fill:none;stroke-width:10;stroke-linecap:round;stroke-dasharray:$circumference;stroke-dashoffset:$dashOffset;transition:stroke-dashoffset 2s cubic-bezier(0.4,0,0.2,1)}
.score-ring-text{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center}
.score-ring-text .pct{font-size:2rem;font-weight:800;line-height:1;color:var(--navy)}
.score-ring-text .label{font-size:0.6875rem;color:var(--text-secondary);margin-top:0.2rem}
.stats-grid{display:grid;grid-template-columns:1fr 1fr;gap:1rem}
.stat-card{background:var(--card);border:1px solid var(--border);border-radius:var(--radius);padding:1.25rem;display:flex;flex-direction:column;box-shadow:0 1px 3px rgba(0,0,0,0.05)}
.stat-card .stat-label{font-size:0.6875rem;color:var(--text-secondary);font-weight:600;text-transform:uppercase;letter-spacing:0.05em}
.stat-card .stat-value{font-size:1.75rem;font-weight:700;margin:0.25rem 0}
.stat-card .stat-sub{font-size:0.75rem;color:var(--text-secondary)}
.stat-card .stat-bar{height:6px;border-radius:3px;background:#e2e8f0;margin-top:auto;overflow:hidden}
.stat-card .stat-bar-fill{height:100%;border-radius:3px;transition:width 1.8s cubic-bezier(0.4,0,0.2,1)}
.stat-pass .stat-value{color:var(--pass)}.stat-pass .stat-bar-fill{background:var(--pass)}
.stat-fail .stat-value{color:var(--fail)}.stat-fail .stat-bar-fill{background:var(--fail)}
.filter-bar{display:flex;align-items:center;gap:0.75rem;margin-bottom:1rem;flex-wrap:wrap}
.filter-bar input{flex:1;min-width:200px;padding:0.5rem 1rem;border:1px solid var(--border);border-radius:var(--radius);font-size:0.875rem;outline:none;background:var(--card);transition:border-color 0.2s}
.filter-bar input:focus{border-color:var(--cyan)}
.filter-btn{padding:0.5rem 1rem;border:1px solid var(--border);border-radius:var(--radius);font-size:0.8125rem;font-weight:500;background:var(--card);cursor:pointer;transition:all 0.15s;user-select:none}
.filter-btn:hover{background:#f1f5f9}.filter-btn.active{background:var(--navy);color:white;border-color:var(--navy)}
.section-toolbar{display:flex;align-items:center;justify-content:space-between;margin-bottom:1rem}
.section-toolbar h2{font-size:1.125rem;font-weight:700;color:var(--navy)}
.toolbar-actions{display:flex;gap:0.5rem}
.toolbar-btn{font-size:0.75rem;font-weight:500;padding:0.35rem 0.75rem;border:1px solid var(--border);border-radius:6px;background:var(--card);cursor:pointer;transition:all 0.15s}
.toolbar-btn:hover{background:#f1f5f9}
.subcategory{background:var(--card);border:1px solid var(--border);border-radius:var(--radius);margin-bottom:0.5rem;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,0.05)}
.subcat-header{display:flex;align-items:center;justify-content:space-between;padding:0.875rem 1.25rem;cursor:pointer;user-select:none;transition:background 0.15s}
.subcat-header:hover{background:#f8fafc}
.subcat-left{display:flex;align-items:center;gap:0.75rem}
.subcat-chevron{font-size:0.65rem;color:var(--text-secondary);transition:transform 0.25s;display:inline-block}
.subcategory.open .subcat-chevron{transform:rotate(90deg)}
.subcat-name{font-weight:600;font-size:0.9375rem;color:var(--navy)}
.subcat-count{font-size:0.75rem;color:var(--text-secondary);background:#f1f5f9;padding:0.125rem 0.5rem;border-radius:999px}
.subcat-right{display:flex;align-items:center;gap:0.75rem;flex-shrink:0}
.subcat-bar-container{width:140px;height:6px;background:#e2e8f0;border-radius:3px;overflow:hidden;flex-shrink:0}
.subcat-bar{height:100%;border-radius:3px;background:var(--cyan);transition:width 1.5s cubic-bezier(0.4,0,0.2,1)}
.subcat-pct{font-size:0.8125rem;font-weight:600;width:40px;text-align:right;color:var(--navy);flex-shrink:0;font-variant-numeric:tabular-nums}
.subcat-badge{font-size:0.75rem;font-weight:600;padding:0.15rem 0.6rem;border-radius:999px;min-width:52px;text-align:center;flex-shrink:0}
.badge-pass{background:var(--pass-bg);color:#166534}.badge-fail{background:var(--fail-bg);color:#991b1b}.badge-warn{background:var(--warn-bg);color:#92400e}
.subcat-body{max-height:0;overflow:hidden;transition:max-height 0.4s cubic-bezier(0.4,0,0.2,1)}
.subcategory.open .subcat-body{max-height:10000px;transition:max-height 0.6s cubic-bezier(0.4,0,0.2,1)}
.control-item{border-top:1px solid var(--border-light)}
.control-header{display:flex;align-items:center;justify-content:space-between;padding:0.75rem 1.25rem 0.75rem 2.5rem;cursor:pointer;transition:background 0.15s;gap:1rem}
.control-header:hover{background:#fafbfc}
.control-left{display:flex;align-items:center;gap:0.5rem;min-width:0;flex:1}
.control-name{font-size:0.8125rem;color:var(--navy);white-space:nowrap;overflow:hidden;text-overflow:ellipsis;font-weight:500}
.control-imp{font-size:0.6875rem;font-weight:600;padding:0.1rem 0.4rem;border-radius:4px;white-space:nowrap}
.imp-high{background:#fee2e2;color:#991b1b}.imp-medium{background:#fef3c7;color:#92400e}.imp-low{background:#f1f5f9;color:var(--text-secondary)}
.control-right{display:flex;align-items:center;gap:0.75rem;flex-shrink:0}
.control-badge{font-size:0.6875rem;font-weight:600;padding:0.2rem 0.6rem;border-radius:999px;white-space:nowrap}
.chevron{font-size:0.5rem;color:var(--text-secondary);transition:transform 0.2s}
.control-item.expanded .chevron{transform:rotate(180deg)}
.control-detail{max-height:0;overflow:hidden;transition:max-height 0.35s cubic-bezier(0.4,0,0.2,1)}
.control-item.expanded .control-detail{max-height:5000px}
.detail-grid{padding:0.75rem 2.5rem 1.25rem;display:flex;gap:2rem;background:#f8fafc;border-top:1px solid var(--border-light)}
.detail-col-left{flex:3;display:flex;flex-direction:column;gap:0.5rem}
.detail-col-right{flex:2;display:flex;flex-direction:column;gap:0.5rem}
.detail-label{font-size:0.6875rem;font-weight:600;text-transform:uppercase;letter-spacing:0.05em;color:var(--text-secondary);margin-bottom:0.35rem}
.detail-text{font-size:0.8125rem;color:var(--text-body);line-height:1.625}
.findings-list{display:flex;flex-direction:column;gap:0.35rem}
.finding-pass{font-size:0.8125rem;color:#166534;display:flex;align-items:flex-start;gap:0.4rem}
.finding-fail{font-size:0.8125rem;color:#991b1b;display:flex;align-items:flex-start;gap:0.4rem}
.finding-warn{font-size:0.8125rem;color:#92400e;display:flex;align-items:flex-start;gap:0.4rem}
.finding-icon{flex-shrink:0;font-weight:700}
.obj-cards{display:flex;flex-direction:column;gap:0.5rem;margin-top:0.5rem}
.obj-card{border:1px solid var(--border);border-radius:var(--radius);overflow:hidden}
.obj-card-header{display:flex;align-items:center;justify-content:space-between;padding:0.65rem 1rem;cursor:pointer;transition:background 0.15s;user-select:none}
.obj-card-header:hover{background:#f8fafc}
.obj-card-left{display:flex;align-items:center;gap:0.5rem;min-width:0;flex:1}
.obj-card-chevron{font-size:0.55rem;color:var(--text-secondary);transition:transform 0.25s;display:inline-block}
.obj-card.open .obj-card-chevron{transform:rotate(90deg)}
.obj-card-name{font-size:0.8125rem;font-weight:600;color:var(--navy);overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.obj-card-score{font-size:0.75rem;color:var(--text-secondary)}
.obj-card-badge{font-size:0.65rem;font-weight:600;padding:0.15rem 0.5rem;border-radius:999px;flex-shrink:0}
.obj-badge-pass{background:var(--pass-bg);color:#166534}
.obj-badge-fail{background:var(--fail-bg);color:#991b1b}
.obj-card-body{max-height:0;overflow:hidden;transition:max-height 0.35s cubic-bezier(0.4,0,0.2,1);background:#f8fafc;border-top:1px solid var(--border-light)}
.obj-card.open .obj-card-body{max-height:5000px}
.obj-card-content{padding:0.75rem 1rem}
.obj-section-label{font-size:0.6875rem;font-weight:600;text-transform:uppercase;letter-spacing:0.05em;margin-bottom:0.35rem;margin-top:0.5rem}
.obj-section-label:first-child{margin-top:0}
.viol-label{color:var(--fail)}.pass-label{color:var(--pass)}.warn-label{color:var(--warn)}
.obj-finding{font-size:0.8125rem;padding:0.4rem 0.75rem;border-radius:6px;margin-bottom:0.3rem;display:flex;align-items:flex-start;gap:0.4rem}
.obj-finding-fail{background:var(--fail-bg);color:#991b1b}
.obj-finding-pass{background:var(--pass-bg);color:#166534}
.obj-finding-warn{background:var(--warn-bg);color:#92400e}
.footer{text-align:center;margin-top:2rem;padding:1rem;font-size:0.72rem;color:var(--text-secondary);border-top:1px solid var(--border)}
.footer a{color:var(--cyan);text-decoration:none}
@keyframes fadeIn{from{opacity:0;transform:translateY(10px)}to{opacity:1;transform:translateY(0)}}
.animate-in{opacity:0;animation:fadeIn 0.5s ease forwards}
@media print{body{background:white}.filter-bar,.toolbar-actions{display:none}.subcategory{break-inside:avoid}.subcat-body{max-height:none!important}.control-detail{max-height:none!important}}
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
      <div class="cover-subtitle">Assessment Report</div>
      <div class="cover-meta">
        <div class="cover-meta-item"><dt>Tenant</dt><dd>$(& $esc $TenantName)</dd></div>
        <div class="cover-meta-item"><dt>Date</dt><dd>$dateStr</dd></div>
        <div class="cover-meta-item"><dt>Time</dt><dd>$timeStr</dd></div>
        <div class="cover-meta-item"><dt>Checks</dt><dd>$TotalChecks</dd></div>
      </div>
    </div>
  </div>
  <div class="cover-accent"></div>
</div>
<div class="container">
  <div class="score-section animate-in" style="animation-delay:0.1s">
    <div class="score-ring-card">
      <div class="score-ring-wrap">
        <svg viewBox="0 0 130 130" width="130" height="130">
          <circle class="score-ring-bg" cx="65" cy="65" r="60"></circle>
          <circle class="score-ring-fg" cx="65" cy="65" r="60" stroke="$scoreColor"></circle>
        </svg>
        <div class="score-ring-text">
          <span class="pct">$Score%</span>
          <span class="label">Compliance</span>
        </div>
      </div>
    </div>
    <div class="stats-grid">
      <div class="stat-card stat-pass animate-in" style="animation-delay:0.2s">
        <span class="stat-label">Passed</span><span class="stat-value">$Passed</span>
        <span class="stat-sub">of $TotalChecks checks</span>
        <div class="stat-bar"><div class="stat-bar-fill" style="width:${passBarPct}%"></div></div>
      </div>
      <div class="stat-card stat-fail animate-in" style="animation-delay:0.3s">
        <span class="stat-label">Failed</span><span class="stat-value">$Failed</span>
        <span class="stat-sub">require remediation</span>
        <div class="stat-bar"><div class="stat-bar-fill" style="width:${failBarPct}%"></div></div>
      </div>
    </div>
  </div>
  <div class="filter-bar animate-in" style="animation-delay:0.4s">
    <input type="text" id="searchInput" placeholder="Search checks..." oninput="filterControls()">
    <button class="filter-btn active" onclick="setFilter('all',this)">All ($TotalChecks)</button>
    <button class="filter-btn" onclick="setFilter('pass',this)">Passed ($Passed)</button>
    <button class="filter-btn" onclick="setFilter('fail',this)">Failed ($Failed)</button>
  </div>
  <div class="section-toolbar animate-in" style="animation-delay:0.4s">
    <h2>Results by Category</h2>
    <div class="toolbar-actions">
      <button class="toolbar-btn" onclick="expandAll()">Expand All</button>
      <button class="toolbar-btn" onclick="collapseAll()">Collapse All</button>
    </div>
  </div>
"@)

    $catIdx = 0
    foreach ($catName in $categories.Keys) {
        $catChecks = $categories[$catName]
        $catPassed = 0; foreach ($c in $catChecks) { if ($c.Status -eq 'Pass') { $catPassed++ } }
        $catPct = if ($catChecks.Count -gt 0) { [math]::Round($catPassed / $catChecks.Count * 100) } else { 0 }
        $badgeClass = if ($catPassed -eq $catChecks.Count) { 'badge-pass' } elseif ($catPassed -ge $catChecks.Count / 2) { 'badge-warn' } else { 'badge-fail' }

        [void]$sb.Append(@"

  <div class="subcategory" data-cat="$(& $esc $catName)">
    <div class="subcat-header" onclick="toggleSubcat(this)">
      <div class="subcat-left">
        <span class="subcat-chevron">&#9654;</span>
        <span class="subcat-name">$(& $esc $catName)</span>
        <span class="subcat-count">$($catChecks.Count) check$(if ($catChecks.Count -ne 1) { 's' })</span>
      </div>
      <div class="subcat-right">
        <div class="subcat-bar-container"><div class="subcat-bar" style="width:${catPct}%"></div></div>
        <span class="subcat-pct">${catPct}%</span>
        <span class="subcat-badge $badgeClass">$catPassed/$($catChecks.Count)</span>
      </div>
    </div>
    <div class="subcat-body">
"@)

        # Sort: failed first, then by importance
        $sorted = $catChecks | Sort-Object { if ($_.Status -eq 'Fail') { 0 } else { 1 } }, { switch (($_.importance).ToLower()) { 'high' { 0 } 'medium' { 1 } default { 2 } } }, name
        foreach ($check in $sorted) {
            $itemClass = if ($check.Status -eq 'Pass') { 'item-pass' } else { 'item-fail' }
            $badgeStyle = if ($check.Status -eq 'Pass') { 'background:#dcfce7;color:#166534' } else { 'background:#fee2e2;color:#991b1b' }
            $badgeText = if ($check.Status -eq 'Pass') { 'Compliant' } else { 'Non-Compliant' }
            $impLower = ($check.importance).ToLower()
            $impClass = switch ($impLower) { 'high' { 'imp-high' } 'medium' { 'imp-medium' } default { 'imp-low' } }

            [void]$sb.Append(@"

      <div class="control-item $itemClass" data-name="$(& $esc $check.name)" data-status="$($check.Status)" onclick="toggleControl(this)">
        <div class="control-header">
          <div class="control-left">
            <span class="control-imp $impClass">$(& $esc $check.importance)</span>
            <span class="control-name">$(& $esc $check.name)</span>
          </div>
          <div class="control-right">
            <span class="control-badge" style="$badgeStyle">$badgeText</span>
            <span class="chevron">&#9660;</span>
          </div>
        </div>
        <div class="control-detail">
          <div class="detail-grid">
            <div class="detail-col-left">
              <div class="detail-section"><div class="detail-label">Description</div><div class="detail-text">$(& $esc $check.description)</div></div>
"@)
            if ($check.remediation) {
                [void]$sb.Append("<div class=`"detail-section`"><div class=`"detail-label`">Remediation</div><div class=`"detail-text`">$(& $esc $check.remediation)</div></div>")
            }
            [void]$sb.Append(@"

            </div>
            <div class="detail-col-right">
              <div class="detail-section"><div class="detail-label">Detailed Checks</div>
                <div class="detail-text" style="font-size:0.78rem;color:var(--text-secondary);margin-bottom:0.5rem">$(& $esc $check.FindingsMessage)</div>
                <div class="obj-cards">
"@)
            if ($check.Scores) {
                foreach ($s in $check.Scores) {
                    $objName = if ($s.objectName -and $s.objectName -notin $placeholders) { $s.objectName } else { 'Tenant check' }
                    $objScore = if ($null -ne $s.score) { $s.score } else { 0 }
                    $vCount = if ($s.violations) { @($s.violations | Where-Object { $_ }).Count } else { 0 }
                    $wCount = if ($s.warnings) { @($s.warnings | Where-Object { $_ }).Count } else { 0 }
                    $pCount = if ($s.passes) { @($s.passes | Where-Object { $_ }).Count } else { 0 }
                    $objBadgeClass = if ($vCount -eq 0 -and $wCount -eq 0) { 'obj-badge-pass' } else { 'obj-badge-fail' }
                    $objBadgeText = if ($vCount -eq 0 -and $wCount -eq 0) { 'Passed' } else { 'Failed' }

                    [void]$sb.Append(@"
<div class="obj-card">
  <div class="obj-card-header">
    <div class="obj-card-left">
      <span class="obj-card-chevron">&#9654;</span>
      <span class="obj-card-name">$(& $esc $objName)</span>
      <span class="obj-card-score">Score: ${objScore}%</span>
    </div>
    <span class="obj-card-badge $objBadgeClass">$objBadgeText</span>
  </div>
  <div class="obj-card-body"><div class="obj-card-content">
"@)
                    if ($vCount -gt 0) {
                        [void]$sb.Append("<div class=`"obj-section-label viol-label`">VIOLATIONS ($vCount)</div>")
                        foreach ($v in $s.violations) {
                            if ($v) { [void]$sb.Append("<div class=`"obj-finding obj-finding-fail`"><span class=`"finding-icon`">&#10007;</span> $(& $esc $v)</div>") }
                        }
                    }
                    if ($wCount -gt 0) {
                        [void]$sb.Append("<div class=`"obj-section-label warn-label`">WARNINGS ($wCount)</div>")
                        foreach ($w in $s.warnings) {
                            if ($w) { [void]$sb.Append("<div class=`"obj-finding obj-finding-warn`"><span class=`"finding-icon`">&#9888;</span> $(& $esc $w)</div>") }
                        }
                    }
                    if ($pCount -gt 0) {
                        [void]$sb.Append("<div class=`"obj-section-label pass-label`">PASSED CHECKS ($pCount)</div>")
                        foreach ($p in $s.passes) {
                            if ($p) { [void]$sb.Append("<div class=`"obj-finding obj-finding-pass`"><span class=`"finding-icon`">&#10003;</span> $(& $esc $p)</div>") }
                        }
                    }
                    [void]$sb.Append("</div></div></div>")
                }
            }

            [void]$sb.Append(@"
</div>
              </div>
            </div>
          </div>
        </div>
      </div>
"@)
        }

        [void]$sb.Append(@"

    </div>
  </div>
"@)
        $catIdx++
    }

    [void]$sb.Append(@"

  <div class="footer">
    Generated by <a href="https://github.com/royklo/InforcerCommunity">InforcerCommunity</a> PowerShell Module &middot; $(& $esc $AssessmentName) &middot; $dateStr
  </div>
</div>
<script>
function toggleSubcat(el){el.closest('.subcategory').classList.toggle('open')}
function toggleControl(el){if(!el.classList.contains('control-item'))el=el.closest('.control-item');if(el)el.classList.toggle('expanded')}
function expandAll(){document.querySelectorAll('.subcategory').forEach(function(s){s.classList.add('open')});document.querySelectorAll('.control-item').forEach(function(c){c.classList.add('expanded')})}
function collapseAll(){document.querySelectorAll('.subcategory').forEach(function(s){s.classList.remove('open')});document.querySelectorAll('.control-item').forEach(function(c){c.classList.remove('expanded')})}
document.addEventListener('click',function(e){var oc=e.target.closest('.obj-card');if(oc){e.stopPropagation();oc.classList.toggle('open')}});
var currentFilter='all';
function setFilter(f,btn){
  currentFilter=f;
  document.querySelectorAll('.filter-btn').forEach(function(b){b.classList.remove('active')});
  btn.classList.add('active');
  filterControls();
}
function filterControls(){
  var q=document.getElementById('searchInput').value.toLowerCase();
  document.querySelectorAll('.control-item').forEach(function(item){
    var name=item.getAttribute('data-name').toLowerCase();
    var status=item.getAttribute('data-status');
    var text=item.textContent.toLowerCase();
    var show=true;
    if(currentFilter==='pass'&&status!=='Pass')show=false;
    if(currentFilter==='fail'&&status!=='Fail')show=false;
    if(q&&text.indexOf(q)===-1)show=false;
    item.style.display=show?'':'none';
  });
  document.querySelectorAll('.subcategory').forEach(function(sc){
    var visible=sc.querySelectorAll('.control-item[style=""],.control-item:not([style])').length;
    sc.style.display=visible>0?'':'none';
  });
}
document.querySelectorAll('.subcategory').forEach(function(s){s.classList.add('open')});
</script>
</body>
</html>
"@)

    return $sb.ToString()
}
