<#
.SYNOPSIS
    Empirical test harness for the dynamic -AssessmentId tab completion on Invoke-InforcerReport.
.DESCRIPTION
    Per REPORTS-CMDLETS-HANDOFF.md Section 5, this is a mandatory post-implementation step.
    The harness drives the completer scriptblock directly (no real TAB press needed) across
    the three permission states and the edge cases:

      1. With an API key that has Assessments.Read  → list of friendly names + GUIDs
      2. With an API key that lacks Assessments.Read → hint completion, denial cached after 403
      3. Without an active session                  → hint completion
      4. Edge cases:
         a. Disconnect-Inforcer clears the cache and re-prompting starts fresh
         b. Completer returns empty when -ReportType ≠ Assessment

    A real API key is required for states 1 and 2. State 3 needs no key.

    Run this script after a `Connect-Inforcer` and observe the latency reports.
.PARAMETER ApiKey
    Optional. The API key to test with. If omitted, only states 3 and 4b are exercised.
.PARAMETER Region
    Inforcer region. Default: uk.
.EXAMPLE
    pwsh -File ./Tests/Manual/Test-AssessmentIdCompleter.ps1
    Runs state 3 + edge case 4b only (no API key required).
.EXAMPLE
    pwsh -File ./Tests/Manual/Test-AssessmentIdCompleter.ps1 -ApiKey $key -Region uk
    Runs every state including a real fetch.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [object]$ApiKey,

    [Parameter(Mandatory = $false)]
    [ValidateSet('anz','eu','uk','us')]
    [string]$Region = 'uk'
)

$ErrorActionPreference = 'Stop'

Push-Location (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
try {
    Import-Module ./module/InforcerCommunity.psd1 -Force
    $module = Get-Module InforcerCommunity

    # --- Helper: invoke the completer scriptblock directly ---
    $cmd = Get-Command Invoke-InforcerReport
    $attr = $cmd.Parameters['AssessmentId'].Attributes.Where({$_ -is [System.Management.Automation.ArgumentCompleterAttribute]}, 'First')[0]
    $completer = $attr.ScriptBlock

    function Invoke-Completer {
        param([string]$Word = '', [hashtable]$Bound = @{ ReportType = @('Assessment') })
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $results = @(& $completer 'Invoke-InforcerReport' 'AssessmentId' $Word $null $Bound)
        $sw.Stop()
        [PSCustomObject]@{
            Word         = $Word
            ElapsedMs    = $sw.ElapsedMilliseconds
            Count        = $results.Count
            Results      = $results
        }
    }

    function Show-Result {
        param([string]$Title, $Result, [string]$Note = '')
        Write-Host ""
        Write-Host "── $Title ──" -ForegroundColor Cyan
        if ($Note) { Write-Host "  $Note" -ForegroundColor DarkGray }
        Write-Host "  latency: $($Result.ElapsedMs) ms"
        Write-Host "  count:   $($Result.Count)"
        foreach ($r in @($Result.Results | Select-Object -First 5)) {
            Write-Host ("    • [{0}] {1}" -f $r.ListItemText, $r.CompletionText) -ForegroundColor DarkGray
        }
        if ($Result.Count -gt 5) { Write-Host "    ... and $($Result.Count - 5) more" -ForegroundColor DarkGray }
    }

    # --- State 3: not connected ---
    Disconnect-Inforcer -ErrorAction SilentlyContinue | Out-Null
    & $module {
        $script:InforcerAssessmentCache         = $null
        $script:InforcerAssessmentCacheDeniedAt = $null
    }
    $r3 = Invoke-Completer
    Show-Result 'State 3: not connected (expect: hint completion)' $r3 `
        'Expected ListItemText: "<Run Connect-Inforcer first>" — count=1'

    # --- Edge case 4b: completer should not fire for ReportType != Assessment ---
    $r4b = Invoke-Completer -Bound @{ ReportType = @('ActiveUserCount') }
    Show-Result 'Edge case 4b: -ReportType ActiveUserCount (expect: 0 completions)' $r4b `
        'Completer should short-circuit; count=0'

    if (-not $ApiKey) {
        Write-Host ""
        Write-Host "States 1, 2, 4a skipped — pass -ApiKey to exercise the live API." -ForegroundColor Yellow
        return
    }

    # --- State 1: connected with Assessments.Read ---
    Write-Host ""
    Write-Host "Connecting (Region=$Region)..." -ForegroundColor DarkGray
    Connect-Inforcer -ApiKey $ApiKey -Region $Region -Confirm:$false | Out-Null

    # First TAB after Connect — should lazy-fetch via the completer's 2s-budget path.
    & $module {
        $script:InforcerAssessmentCache         = $null
        $script:InforcerAssessmentCacheDeniedAt = $null
    }
    $r1a = Invoke-Completer
    Show-Result 'State 1a: first TAB (lazy fetch, ≤2s budget)' $r1a `
        'Expect: assessment list with names+GUIDs; latency <2000ms'

    $r1b = Invoke-Completer -Word ''
    Show-Result 'State 1b: subsequent TAB (cache hit — should be instant)' $r1b `
        'Expect: same count as 1a; latency ≈ single-digit ms'

    # --- Edge case 4a: Disconnect-Inforcer clears the cache ---
    Disconnect-Inforcer | Out-Null
    & $module {
        $cache  = $script:InforcerAssessmentCache
        $denial = $script:InforcerAssessmentCacheDeniedAt
        Write-Host ""
        Write-Host "── Edge case 4a: Disconnect-Inforcer clears caches ──" -ForegroundColor Cyan
        Write-Host "  InforcerAssessmentCache = $(if ($null -eq $cache) { '<null>' } else { '(still populated!)' })"
        Write-Host "  InforcerAssessmentCacheDeniedAt = $(if ($null -eq $denial) { '<null>' } else { $denial })"
    }

    Write-Host ""
    Write-Host "State 2 (denied scope) is best tested with a deliberately scope-restricted key." -ForegroundColor Yellow
    Write-Host "To validate the 403→denial-sentinel path, scope down a key to NOT include" -ForegroundColor Yellow
    Write-Host "Assessments.Read, then re-run this script with that key." -ForegroundColor Yellow

} finally {
    Pop-Location
}
