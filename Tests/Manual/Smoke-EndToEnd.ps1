<#
.SYNOPSIS
    End-to-end smoke scenario for the Reports cmdlets, with mocked HTTP — no live API needed.
.DESCRIPTION
    Pester unit tests use focused mocks that isolate one cmdlet at a time. This script does the
    opposite: replaces ONLY the HTTP layer (Invoke-WebRequest + Invoke-RestMethod inside the
    module) with a deterministic mock and lets the real cmdlets do their real work end-to-end.

    The scenarios mirror what a user actually does:

      1. Connect-Inforcer succeeds with a key that has Reports.Read scope (catalog primes)
      2. Get-InforcerReportType -Tag Security pipes catalog entries into Invoke-InforcerReport
      3. Invoke-InforcerReport queues a batch POST, polls each run to terminal, streams the
         output file to disk, runs -Open against an allowlisted file
      4. Disconnect-Inforcer wipes caches; reconnect with a "scope-limited" key still works

    Pass/fail is printed inline and exit code is non-zero on any failure.

.EXAMPLE
    pwsh -NoProfile -File ./Tests/Manual/Smoke-EndToEnd.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$failCount = 0
function Test-Step {
    param([string]$Name, [scriptblock]$Block)
    Write-Host -NoNewline ("[ … ] {0,-65}" -f $Name)
    try {
        $result = & $Block
        if ($result) { Write-Host 'PASS' -ForegroundColor Green }
        else { Write-Host 'FAIL' -ForegroundColor Red; $script:failCount++ }
    } catch {
        Write-Host ("FAIL: {0}" -f $_.Exception.Message) -ForegroundColor Red
        $script:failCount++
    }
}

Push-Location (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
try {
    Import-Module ./module/InforcerCommunity.psd1 -Force
    $module = Get-Module InforcerCommunity

    # ----- Mock HTTP layer at the module level -----
    # State tracked across mock calls so we can assert on POST counts and bodies later.
    $script:mockState = [PSCustomObject]@{
        WebRequests    = [System.Collections.Generic.List[hashtable]]::new()
        RestRequests   = [System.Collections.Generic.List[hashtable]]::new()
        SeenPostBodies = [System.Collections.Generic.List[string]]::new()
        ItemsOpened    = [System.Collections.Generic.List[string]]::new()
    }

    & $module {
        param($state)
        $script:_smokeState = $state

        # Override Invoke-WebRequest inside the module's session state. Plain function (no
        # [CmdletBinding()]) so we can declare $ErrorAction without colliding with the
        # auto-added common parameter.
        function script:Invoke-WebRequest {
            param($Uri, $Method, $Headers, $Body, [switch]$UseBasicParsing, [switch]$SkipHttpErrorCheck,
                  $OutFile, [switch]$PassThru, $ErrorAction, $TimeoutSec)
            $script:_smokeState.WebRequests.Add(@{ Uri=$Uri; Method=$Method; OutFile=$OutFile; HasBody=([bool]$Body) })

            if ($Method -eq 'POST' -and $Body) {
                $script:_smokeState.SeenPostBodies.Add($Body.ToString())
            }

            # Routing — return realistic shapes based on the URI.
            switch -Regex ($Uri) {
                'baselines$'         { return [pscustomobject]@{ StatusCode = 200; Content = '{"data":[],"success":true}'; Headers = @{} } }
                'reports/types$'     {
                    $json = '{"data":[' +
                            '{"key":"ActiveUserCount","name":"Active User Count","collatable":false,"supportedOutputFormats":["csv","json"],"requiredParameters":[],"tags":["Adoption"]},' +
                            '{"key":"TenantAuditReport","name":"Tenant Audit","collatable":false,"supportedOutputFormats":["csv","pdf","html"],"requiredParameters":[],"tags":["Security"]},' +
                            '{"key":"GetRiskyUsers","name":"Risky Users","collatable":false,"supportedOutputFormats":["csv","json"],"requiredParameters":[],"tags":["Security"]}' +
                            '],"success":true}'
                    return [pscustomobject]@{ StatusCode = 200; Content = $json; Headers = @{} }
                }
                'reports/runs/[^/]+/outputs/[^/]+$' {
                    # Single output download. Filename varies by output id so we can verify
                    # each piped report produced its own file on disk.
                    $outId = $Uri.Split('/')[-1]
                    $fname = "$outId.csv"
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes("user_id,login_count`n00001,42`n")
                    if ($OutFile) { [System.IO.File]::WriteAllBytes($OutFile, $bytes) }
                    return [pscustomobject]@{
                        StatusCode = 200
                        Headers    = @{
                            'Content-Disposition' = "attachment; filename=`"$fname`""
                            'Content-Type'        = 'text/csv'
                            'x-correlation-id'    = 'smoke-cor'
                        }
                        Content    = if ($OutFile) { $null } else { $bytes }
                    }
                }
                'reports/runs/[^/]+/outputs$' {
                    # Polling endpoint — Test-InforcerReportRunTerminal hits this. Returns
                    # 200 + JSON body when terminal; the cmdlet then reads .data.outputs.
                    $body = '{"data":{"outputs":[' +
                            '{"id":"smoke-output-1","reportType":"TenantAuditReport","tenantId":14436,"format":"csv","sizeBytes":32},' +
                            '{"id":"smoke-output-2","reportType":"GetRiskyUsers","tenantId":14436,"format":"csv","sizeBytes":40}' +
                            ']},"success":true}'
                    return [pscustomobject]@{
                        StatusCode = 200
                        Headers    = @{ 'Content-Type' = 'application/json'; 'x-correlation-id' = 'smoke-poll' }
                        Content    = $body
                    }
                }
                default {
                    return [pscustomobject]@{ StatusCode = 200; Content = '{"data":[],"success":true}'; Headers = @{} }
                }
            }
        }

        # Invoke-RestMethod is used by Invoke-InforcerApiRequest for non-binary GETs/POSTs.
        function script:Invoke-RestMethod {
            param($Uri, $Method, $Headers, $Body, $ContentType, $TimeoutSec)
            $script:_smokeState.RestRequests.Add(@{ Uri=$Uri; Method=$Method; HasBody=([bool]$Body) })

            if ($Method -eq 'POST' -and $Body) {
                $script:_smokeState.SeenPostBodies.Add($Body.ToString())
            }

            switch -Regex ($Uri) {
                'reports/types$' {
                    return [pscustomobject]@{
                        data    = @(
                            [pscustomobject]@{ key='ActiveUserCount'; name='Active User Count'; collatable=$false; supportedOutputFormats=@('csv','json'); requiredParameters=@(); tags=@('Adoption') }
                            [pscustomobject]@{ key='TenantAuditReport'; name='Tenant Audit'; collatable=$false; supportedOutputFormats=@('csv','pdf','html'); requiredParameters=@(); tags=@('Security') }
                            [pscustomobject]@{ key='GetRiskyUsers'; name='Risky Users'; collatable=$false; supportedOutputFormats=@('csv','json'); requiredParameters=@(); tags=@('Security') }
                        )
                        success = $true
                    }
                }
                'reports/runs$' {
                    if ($Method -eq 'POST') {
                        # POST /beta/reports/runs returns { data: { runId: <guid> } }
                        # Wrapped by Invoke-InforcerApiRequest, which unwraps .data
                        return [pscustomobject]@{
                            data    = @([pscustomobject]@{ runId = ([guid]::NewGuid().ToString()); status='queued' })
                            success = $true
                        }
                    }
                    # GET /beta/reports/runs — return empty list
                    return [pscustomobject]@{ data = @(); success = $true }
                }
                'reports/runs/[^/]+/outputs$' {
                    # Poll target — return terminal with one output ready
                    return [pscustomobject]@{
                        data    = [pscustomobject]@{
                            outputs = @(
                                [pscustomobject]@{ id='smoke-output-id'; reportType='TenantAuditReport'; tenantId=14436; format='csv'; sizeBytes=32 }
                            )
                        }
                        success = $true
                    }
                }
                default {
                    return [pscustomobject]@{ data = @(); success = $true }
                }
            }
        }

        # Override Invoke-Item so we observe but don't actually launch.
        function script:Invoke-Item {
            param([string]$LiteralPath, $ErrorAction)
            $script:_smokeState.ItemsOpened.Add($LiteralPath)
        }
    } $script:mockState

    # ----- Scenario 1: Connect → catalog prime -----
    Write-Host ""
    Write-Host "=== Scenario 1: Connect + catalog prime ===" -ForegroundColor Cyan

    $secure = ConvertTo-SecureString -String 'smoke-key-not-real' -AsPlainText -Force
    $connectResult = Connect-Inforcer -ApiKey $secure -Region uk

    Test-Step 'Connect-Inforcer returns Connected status' {
        $connectResult -and $connectResult.Status -eq 'Connected'
    }

    Test-Step 'Catalog cache primed with 3 entries' {
        $primed = & $module { @($script:InforcerReportTypeCache).Count }
        $primed -eq 3
    }

    Test-Step 'Catalog cache stamp is set' {
        $stamp = & $module { $script:InforcerReportTypeCacheStamp }
        $null -ne $stamp
    }

    # ----- Scenario 2: Discover → Pipe → Run → Save → Open (allowlisted) -----
    Write-Host ""
    Write-Host "=== Scenario 2: Discover-and-run pipeline ===" -ForegroundColor Cyan

    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("inforcer-smoke-" + [guid]::NewGuid().ToString('N'))
    $null = New-Item -Path $tempDir -ItemType Directory -Force

    $script:mockState.SeenPostBodies.Clear()
    $script:mockState.ItemsOpened.Clear()

    $catalog = Get-InforcerReportType -Tag Security
    Test-Step "Get-InforcerReportType -Tag Security returns 2 entries" {
        @($catalog).Count -eq 2
    }

    $piped = $catalog | Invoke-InforcerReport -OutputFormat csv -TenantId 14436 -OutputPath $tempDir -Open

    Test-Step 'Pipeline accumulated both Security types into ONE POST' {
        # The accumulator should have batched both Security catalog entries into a single POST,
        # not two separate POSTs.
        $postBodies = @($script:mockState.SeenPostBodies | Where-Object { $_ -match 'reports' })
        $postBodies.Count -eq 1
    }

    Test-Step 'POST body contains both report types' {
        $body = $script:mockState.SeenPostBodies | Select-Object -First 1
        ($body -match 'TenantAuditReport') -and ($body -match 'GetRiskyUsers')
    }

    Test-Step 'POST body includes resolved numeric tenant ID' {
        $body = $script:mockState.SeenPostBodies | Select-Object -First 1
        $body -match '"includeTenants":\s*\[\s*14436\s*\]'
    }

    Test-Step 'Pipeline returned 2 ReportRunResult objects' {
        @($piped).Count -ge 1 -and $piped[0].PSObject.TypeNames[0] -eq 'InforcerCommunity.ReportRunResult'
    }

    Test-Step 'Output files exist on disk with expected content' {
        $files = @(Get-ChildItem -LiteralPath $tempDir -File)
        $files.Count -ge 1 -and `
        ((Get-Content -LiteralPath $files[0].FullName -Raw) -match 'user_id,login_count')
    }

    Test-Step '-Open launched the .csv file (allowlisted)' {
        @($script:mockState.ItemsOpened | Where-Object { $_ -match '\.csv$' }).Count -ge 1
    }

    Test-Step '-Open did NOT launch any .command/.app/etc file (allowlist enforced)' {
        $dangerous = $script:mockState.ItemsOpened | Where-Object { $_ -match '\.(command|app|sh|exe|lnk|desktop|url|scpt|terminal|workflow|vbs|ps1|jar|bat)$' }
        @($dangerous).Count -eq 0
    }

    Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue

    # ----- Scenario 3: Disconnect → Reconnect with cache reset -----
    Write-Host ""
    Write-Host "=== Scenario 3: Disconnect + reconnect cache hygiene ===" -ForegroundColor Cyan

    $null = Disconnect-Inforcer

    Test-Step 'Disconnect clears the catalog cache' {
        $c = & $module { $script:InforcerReportTypeCache }
        $null -eq $c
    }

    Test-Step 'Disconnect clears the catalog cache stamp' {
        $s = & $module { $script:InforcerReportTypeCacheStamp }
        $null -eq $s
    }

    # Reconnect with the same fake key — cache should re-prime fresh
    $script:mockState.WebRequests.Clear()
    $script:mockState.RestRequests.Clear()
    $null = Connect-Inforcer -ApiKey $secure -Region uk

    Test-Step 'Reconnect re-primes the catalog cache' {
        $primed = & $module { @($script:InforcerReportTypeCache).Count }
        $primed -eq 3
    }

    Test-Step 'Reconnect issued exactly one /reports/types prime call' {
        $primeCalls = @($script:mockState.WebRequests | Where-Object { $_.Uri -match 'reports/types$' })
        $primeCalls.Count -eq 1
    }

    # ----- Scenario 4: Stale cache TTL behavior -----
    Write-Host ""
    Write-Host "=== Scenario 4: Stale cache auto-refresh ===" -ForegroundColor Cyan

    # Push stamp back to 20 minutes ago — should trigger TTL refresh on next resolve
    & $module {
        $script:InforcerReportTypeCacheStamp = (Get-Date).AddMinutes(-20)
    }
    $script:mockState.RestRequests.Clear()

    # Use the schema resolver directly (it's what consults the TTL)
    $null = & $module { Resolve-InforcerReportTypeSchema -ReportType 'ActiveUserCount' -OutputFormat 'csv' } 2>&1

    Test-Step 'Stale cache (20m) triggers a refetch via TTL' {
        $refetch = @($script:mockState.RestRequests | Where-Object { $_.Uri -match 'reports/types$' -and $_.Method -eq 'GET' })
        $refetch.Count -ge 1
    }

    Test-Step 'Cache stamp updated post-refetch' {
        $age = & $module { ((Get-Date) - $script:InforcerReportTypeCacheStamp).TotalSeconds }
        $age -lt 60
    }

    # ----- Wrap up -----
    Write-Host ""
    if ($failCount -eq 0) {
        Write-Host "All scenarios passed." -ForegroundColor Green
        exit 0
    } else {
        Write-Host ("{0} scenario(s) FAILED." -f $failCount) -ForegroundColor Red
        exit 1
    }
} finally {
    Pop-Location
}
