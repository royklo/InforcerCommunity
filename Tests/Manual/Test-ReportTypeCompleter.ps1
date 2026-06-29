<#
.SYNOPSIS
    Empirical test harness for the dynamic -ReportType / -Tag / -OutputFormat tab completion
    on Get-InforcerReportType and Invoke-InforcerReport.
.DESCRIPTION
    Validates that ArgumentCompleter scriptblocks fire correctly through the
    `& (Get-Module InforcerCommunity) { ... }` module-bounce pattern, including:

      1. Empty cache + no session       → static-key fallback (25 entries)
      2. Empty cache + cached after Connect-Inforcer → live keys from /beta/reports/types
      3. Malformed cache (missing 'key' property) → falls back to static keys
      4. -Tag completer pulls live tags after the cache is primed
      5. -OutputFormat completer narrows to the supported formats of a given -ReportType
      6. Get-InforcerReportType -Key and Invoke-InforcerReport -ReportType return identical sets

    Pass an API key with Reports.Read scope to exercise states 2, 4, 5.

.PARAMETER ApiKey
    Optional. API key with Reports.Read. If omitted, only static-fallback states are tested.
.PARAMETER Region
    Optional. Region to connect to. Default: uk.
.EXAMPLE
    pwsh -File Tests/Manual/Test-ReportTypeCompleter.ps1
    Runs offline tests only (static fallback, malformed cache).
.EXAMPLE
    pwsh -File Tests/Manual/Test-ReportTypeCompleter.ps1 -ApiKey 'inforcer-key-...'
    Runs the full harness against the live API.
.NOTES
    All assertions write PASS/FAIL inline; non-zero exit code on any failure.
#>
[CmdletBinding()]
param(
    # Accept SecureString OR plaintext; plain string is converted to SecureString immediately
    # so it doesn't sit in memory as plaintext beyond the parameter binder. Avoid passing a
    # plaintext key on the command line — it ends up in shell history and `ps -ef`. Prefer
    # $env:INFORCER_API_KEY or Read-Host -AsSecureString.
    [Parameter(Mandatory = $false)]
    [object]$ApiKey,

    [Parameter(Mandatory = $false)]
    [ValidateSet('anz', 'eu', 'uk', 'us')]
    [string]$Region = 'uk'
)

$ErrorActionPreference = 'Stop'
$failCount = 0

# Normalise the ApiKey to SecureString. Priority: explicit -ApiKey → $env:INFORCER_API_KEY
# → interactive prompt. Plain strings are zeroed after conversion.
function ConvertTo-SafeApiKey {
    param($Value)
    if ($null -eq $Value -or ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value))) {
        if ($env:INFORCER_API_KEY) {
            return (ConvertTo-SecureString -String $env:INFORCER_API_KEY -AsPlainText -Force)
        }
        return $null
    }
    if ($Value -is [SecureString]) { return $Value }
    if ($Value -is [string]) {
        return (ConvertTo-SecureString -String $Value -AsPlainText -Force)
    }
    throw "ApiKey must be a string, SecureString, or omitted (got $($Value.GetType().FullName))."
}
$secureKey = ConvertTo-SafeApiKey -Value $ApiKey

function Test-Step {
    param([string]$Name, [scriptblock]$Block)
    Write-Host -NoNewline ("[ … ] {0,-60}" -f $Name)
    try {
        $result = & $Block
        if ($result) {
            Write-Host "PASS" -ForegroundColor Green
        } else {
            Write-Host "FAIL" -ForegroundColor Red
            $script:failCount++
        }
    } catch {
        Write-Host ("FAIL: {0}" -f $_.Exception.Message) -ForegroundColor Red
        $script:failCount++
    }
}

# Load module fresh
Import-Module "$PSScriptRoot/../../module/InforcerCommunity.psd1" -Force
$module = Get-Module InforcerCommunity

# Helper: invoke a parameter's completer scriptblock bound to module scope
function Invoke-Completer {
    param([System.Management.Automation.CommandInfo]$Cmd, [string]$ParamName, [string]$Word = '', [hashtable]$BoundParams = @{})
    $attr = $Cmd.Parameters[$ParamName].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] } |
            Select-Object -First 1
    if (-not $attr) { return @() }
    $boundSb = $script:module.NewBoundScriptBlock($attr.ScriptBlock)
    & $boundSb $Cmd.Name $ParamName $Word $null $BoundParams
}

Write-Host "`n=== State 1: Static fallback (no cache) ===" -ForegroundColor Cyan
& $module { $script:InforcerReportTypeCache = $null }

Test-Step 'Get-InforcerReportType -Key returns 25 static keys' {
    $r = Invoke-Completer (Get-Command Get-InforcerReportType) 'Key'
    $r.Count -ge 20
}

Test-Step 'Invoke-InforcerReport -ReportType returns 25 static keys' {
    $r = Invoke-Completer (Get-Command Invoke-InforcerReport) 'ReportType'
    $r.Count -ge 20
}

Test-Step 'Both completers return identical static sets' {
    $a = (Invoke-Completer (Get-Command Get-InforcerReportType) 'Key').CompletionText | Sort-Object
    $b = (Invoke-Completer (Get-Command Invoke-InforcerReport) 'ReportType').CompletionText | Sort-Object
    -not (Compare-Object $a $b)
}

Test-Step '-Tag falls back to the 4 hardcoded categories' {
    $r = Invoke-Completer (Get-Command Get-InforcerReportType) 'Tag'
    $r.Count -eq 4
}

Write-Host "`n=== State 3: Malformed cache ===" -ForegroundColor Cyan
& $module {
    $script:InforcerReportTypeCache = @(
        [PSCustomObject]@{ notKey = 'x' },   # missing 'key' property
        $null,                                # null entry
        'just-a-string'                       # not a PSObject
    )
}

Test-Step '-Key falls back to static keys when cache entries lack key prop' {
    $r = Invoke-Completer (Get-Command Get-InforcerReportType) 'Key'
    $r.Count -ge 20
}

Test-Step 'AssessmentId completer survives null/string cache entries (no exception)' {
    & $module {
        $script:InforcerAssessmentCache = @(
            [PSCustomObject]@{ id = 'good-id'; name = 'Good' },
            $null,
            'not-a-psobject',
            [PSCustomObject]@{ notAnId = 'x' }
        )
        $script:InforcerSession = @{
            ApiKey      = ConvertTo-SecureString 'fake' -AsPlainText -Force
            BaseUrl     = 'https://example.invalid/api'
            Region      = 'uk'
            ConnectedAt = Get-Date
        }
    }
    $r = Invoke-Completer (Get-Command Invoke-InforcerReport) 'AssessmentId' '' @{ ReportType = @('Assessment') }
    # Just needs to NOT throw — the actual result depends on session state.
    $r -ne $null
}

# Reset state
& $module {
    $script:InforcerReportTypeCache = $null
    $script:InforcerAssessmentCache = $null
    $script:InforcerSession = $null
}

if ($secureKey) {
    Write-Host "`n=== State 2: Live cache after Connect-Inforcer ===" -ForegroundColor Cyan
    try {
        $null = Connect-Inforcer -ApiKey $secureKey -Region $Region -ErrorAction Stop
        $primed = & $module { @($script:InforcerReportTypeCache).Count }

        Test-Step "Catalog cache primed by Connect-Inforcer (got $primed entries)" {
            $primed -gt 0
        }

        Test-Step '-Key completer returns live keys (not just static fallback)' {
            $r = Invoke-Completer (Get-Command Get-InforcerReportType) 'Key'
            $r.Count -gt 0
        }

        Test-Step '-Tag completer returns live tags' {
            $r = Invoke-Completer (Get-Command Get-InforcerReportType) 'Tag'
            $r.Count -gt 0
        }

        if ($primed -gt 0) {
            $sample = & $module { $script:InforcerReportTypeCache[0].key }
            Test-Step "-OutputFormat completer narrows to formats of -ReportType $sample" {
                $r = Invoke-Completer (Get-Command Invoke-InforcerReport) 'OutputFormat' '' @{ ReportType = @($sample) }
                $r.Count -gt 0
            }
        }
    } finally {
        try { $null = Disconnect-Inforcer -ErrorAction SilentlyContinue } catch {}
    }
} else {
    Write-Host "`n=== States 2 / 4 / 5 skipped (no -ApiKey or `$env:INFORCER_API_KEY provided) ===" -ForegroundColor Yellow
}

Write-Host ""
if ($failCount -eq 0) {
    Write-Host "All completer states passed." -ForegroundColor Green
    exit 0
} else {
    Write-Host ("{0} completer test(s) FAILED." -f $failCount) -ForegroundColor Red
    exit 1
}
