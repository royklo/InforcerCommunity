# V1.Reports.Tests.ps1
# Assessments and reports on both APIs: request bodies per version, header passing into the assessment
# runspace and the TAB completer, output mapping and the Collated sentinel, tenant-id validation.
# Fixtures are anonymised (zero GUIDs, example names). HTTP is mocked, or served by a loopback listener
# where the code under test calls Invoke-RestMethod from a separate runspace / the caller's scope.

BeforeAll {
    Remove-Module -Name 'InforcerCommunity' -ErrorAction SilentlyContinue
    Import-Module (Join-Path $PSScriptRoot '../module/InforcerCommunity.psd1') -Force
    $script:M = Get-Module InforcerCommunity

    $script:Tid1 = '00000000-0000-0000-0000-000000000001'
    $script:Tid2 = '00000000-0000-0000-0000-000000000002'
    $script:Run1 = '00000000-0000-0000-0000-0000000000a1'

    function global:Set-ReportsTestSession {
        param([ValidateSet('v1', 'beta')][string]$Mode = 'v1', [string]$ApiHost = 'https://api.example.invalid')
        & (Get-Module InforcerCommunity) {
            param($Mode, $ApiHost)
            $script:InforcerTenantListCache = $null
            $script:InforcerAssessmentCache = $null
            $script:InforcerAssessmentCacheDeniedAt = $null
            $script:InforcerReportTypeCache = @(
                [pscustomobject]@{ key = 'ActiveUserCount'; name = 'Active users'; collatable = $true; singleTenantOnly = $false
                    supportedOutputFormats = @('csv', 'json', 'html'); requiredParameters = @(); tags = @('Adoption') }
                [pscustomobject]@{ key = 'CopilotAdoption'; name = 'Copilot adoption'; collatable = $false; singleTenantOnly = $false
                    supportedOutputFormats = @('csv', 'pdf'); tags = @('Adoption')
                    requiredParameters = @([pscustomobject]@{ key = 'report-period'; description = 'days'; options = $null }) }
            )
            $script:InforcerReportTypeCacheStamp = Get-Date
            if ($Mode -eq 'beta') {
                $script:InforcerSession = @{
                    AuthMode = 'ApiKey'; ApiVersion = 'beta'; ApiHost = $ApiHost; BaseUrl = "$ApiHost/api"; Region = 'uk'
                    ConnectedAt = Get-Date; ApiKey = (ConvertTo-SecureString 'beta-test-key-value' -AsPlainText -Force)
                }
            } else {
                $script:InforcerSession = @{
                    AuthMode = 'ClientCredentials'; ApiVersion = 'v1'; ApiHost = $ApiHost; BaseUrl = $ApiHost; Region = 'uk'
                    ConnectedAt = Get-Date; ClientId = 'client-id-example'
                    ClientSecret = (ConvertTo-SecureString 'client-secret-example-value' -AsPlainText -Force)
                    AccessToken = (ConvertTo-SecureString 'access-token-example-value' -AsPlainText -Force)
                    TokenExpiresAt = [datetime]::UtcNow.AddMinutes(50)
                }
            }
        } $Mode $ApiHost
    }

    # Loopback HTTP server that records the headers of the last request. The port is claimed by
    # starting the listener itself (retrying on a collision, no probe-then-release gap); the handler
    # signals when it is ready, and one throwaway request warms Invoke-RestMethod up so the
    # completer's 2 s budget never races JIT/first-use cost.
    function global:Start-ReportsTestServer {
        param([int]$Status = 200, [string]$Json = '{}')
        $listener = $null
        $port = 0
        for ($attempt = 0; $attempt -lt 25 -and -not $listener; $attempt++) {
            $port = Get-Random -Minimum 20000 -Maximum 60000
            $candidate = [System.Net.HttpListener]::new()
            $candidate.Prefixes.Add("http://127.0.0.1:$port/")
            try { $candidate.Start(); $listener = $candidate } catch { $candidate.Close() }
        }
        if (-not $listener) { throw 'Could not start a loopback HttpListener on a free port.' }
        $seen = [hashtable]::Synchronized(@{ Count = 0; Ready = $false })
        $shell = [powershell]::Create()
        $null = $shell.AddScript({
            param($listener, $seen, $status, $json)
            $seen.Ready = $true
            while ($listener.IsListening) {
                try { $ctx = $listener.GetContext() } catch { break }
                $req = $ctx.Request
                $seen.Auth = $req.Headers['Authorization']
                $seen.ApiKey = $req.Headers['Inf-Api-Key']
                $seen.ContentType = $req.ContentType
                $seen.Method = $req.HttpMethod
                $seen.Path = $req.RawUrl
                $seen.Count = $seen.Count + 1
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                $ctx.Response.StatusCode = $status
                $ctx.Response.ContentType = 'application/json'
                $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                $ctx.Response.Close()
            }
        }).AddArgument($listener).AddArgument($seen).AddArgument($Status).AddArgument($Json)
        $null = $shell.BeginInvoke()
        $waited = 0
        while (-not $seen.Ready -and $waited -lt 200) { Start-Sleep -Milliseconds 50; $waited++ }
        $server = [pscustomobject]@{ ApiHost = "http://127.0.0.1:$port"; Seen = $seen; Listener = $listener; Shell = $shell }
        try { $null = Invoke-RestMethod -Uri "$($server.ApiHost)/warmup" -TimeoutSec 30 -ErrorAction Stop } catch { $null }
        $seen.Clear()
        $seen.Count = 0
        $server
    }

    function global:Stop-ReportsTestServer {
        param($Server)
        try { $Server.Listener.Stop(); $Server.Listener.Close() } catch { $null }
        try { $Server.Shell.Stop(); $Server.Shell.Dispose() } catch { $null }
    }

    $attr = (Get-Command Invoke-InforcerReport).Parameters['AssessmentId'].Attributes |
        Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] }
    $script:AssessmentCompleter = $attr.ScriptBlock
}

AfterAll {
    Remove-Item function:global:Set-ReportsTestSession -ErrorAction SilentlyContinue
    Remove-Item function:global:Start-ReportsTestServer -ErrorAction SilentlyContinue
    Remove-Item function:global:Stop-ReportsTestServer -ErrorAction SilentlyContinue
    & (Get-Module InforcerCommunity) {
        $script:InforcerSession = $null
        $script:InforcerTenantListCache = $null
        $script:InforcerReportTypeCache = $null
        $script:InforcerAssessmentCache = $null
    }
}

Describe 'TenantId aliases' {
    It '<Cmd> accepts -ClientTenantId and -MsTenantId' -ForEach @(
        @{ Cmd = 'Invoke-InforcerReport' }
        @{ Cmd = 'Invoke-InforcerAssessment' }
        @{ Cmd = 'Save-InforcerReportOutput' }
    ) {
        $aliases = (Get-Command $Cmd).Parameters['TenantId'].Aliases
        $aliases | Should -Contain 'ClientTenantId'
        $aliases | Should -Contain 'MsTenantId'
    }
}

Describe 'Invoke-InforcerReport request body' {
    BeforeEach {
        Mock -ModuleName InforcerCommunity Invoke-InforcerApiRequest { [pscustomobject]@{ runId = '00000000-0000-0000-0000-0000000000a1' } }
    }

    It 'v1 posts msTenantIds with GUIDs and the report entries, mapped as ReportRun' {
        Set-ReportsTestSession -Mode v1
        $run = @(Invoke-InforcerReport -ReportType ActiveUserCount -OutputFormat csv -TenantId $script:Tid1 -NoWait)
        $run[0].runId | Should -Be $script:Run1
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerApiRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and $Endpoint -eq '/reports/runs' -and $ObjectType -eq 'ReportRun' -and
            (($Body | ConvertFrom-Json).msTenantIds -contains '00000000-0000-0000-0000-000000000001') -and
            (($Body | ConvertFrom-Json).reports[0].type -eq 'ActiveUserCount') -and
            (($Body | ConvertFrom-Json).reports[0].outputFormat -eq 'csv') -and
            ($Body -notmatch 'includeTenants')
        }
    }

    It 'v1 passes collate and the auto-defaulted report-period parameter' {
        Set-ReportsTestSession -Mode v1
        $null = Invoke-InforcerReport -ReportType CopilotAdoption -OutputFormat csv -TenantId $script:Tid1 -NoWait
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerApiRequest -Times 1 -Exactly -ParameterFilter {
            (($Body | ConvertFrom-Json).reports[0].parameters.'report-period' -eq '30')
        }
        $null = Invoke-InforcerReport -ReportType ActiveUserCount -OutputFormat csv -TenantId $script:Tid1 -Collate -NoWait
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerApiRequest -Times 1 -Exactly -ParameterFilter {
            (($Body | ConvertFrom-Json).reports[0].collate -eq $true)
        }
    }

    It 'beta keeps tenants.includeTenants with numeric Client Tenant IDs' {
        Set-ReportsTestSession -Mode beta
        $null = Invoke-InforcerReport -ReportType ActiveUserCount -OutputFormat csv -TenantId 14436 -NoWait
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerApiRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and $Endpoint -eq '/reports/runs' -and
            (($Body | ConvertFrom-Json).tenants.includeTenants -contains 14436) -and
            ($Body -notmatch 'msTenantIds')
        }
    }

    It 'beta sorts and de-duplicates numeric tenant ids' {
        Set-ReportsTestSession -Mode beta
        $null = Invoke-InforcerReport -ReportType ActiveUserCount -OutputFormat csv -TenantId 20, 10, 20 -NoWait
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerApiRequest -Times 1 -Exactly -ParameterFilter {
            (@(($Body | ConvertFrom-Json).tenants.includeTenants) -join ',') -eq '10,20'
        }
    }

    It 'v1 de-duplicates GUIDs case-insensitively without a tenant list lookup' {
        Set-ReportsTestSession -Mode v1
        Mock -ModuleName InforcerCommunity Get-InforcerTenantList { throw 'tenant list must not be fetched for GUIDs' }
        $null = Invoke-InforcerReport -ReportType ActiveUserCount -OutputFormat csv -TenantId $script:Tid1, $script:Tid1.ToUpperInvariant() -NoWait
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerApiRequest -Times 1 -Exactly -ParameterFilter {
            @(($Body | ConvertFrom-Json).msTenantIds).Count -eq 1
        }
        Should -Invoke -ModuleName InforcerCommunity Get-InforcerTenantList -Times 0 -Exactly
    }

    It 'v1 resolves a tenant name to its Microsoft tenant ID' {
        Set-ReportsTestSession -Mode v1
        Mock -ModuleName InforcerCommunity Get-InforcerTenantList {
            @([pscustomobject]@{ msTenantId = '00000000-0000-0000-0000-000000000002'; tenantFriendlyName = 'Contoso Example'; tenantDnsName = 'contoso.example.invalid' })
        }
        $null = Invoke-InforcerReport -ReportType ActiveUserCount -OutputFormat csv -TenantId 'Contoso Example' -NoWait
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerApiRequest -Times 1 -Exactly -ParameterFilter {
            (($Body | ConvertFrom-Json).msTenantIds -contains '00000000-0000-0000-0000-000000000002')
        }
    }

    It 'v1 refuses a numeric tenant id with the API-key explanation' {
        Set-ReportsTestSession -Mode v1
        { Invoke-InforcerReport -ReportType ActiveUserCount -OutputFormat csv -TenantId 482 -NoWait -ErrorAction Stop } |
            Should -Throw '*only works when you connect with an API key*'
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerApiRequest -Times 0 -Exactly
    }

    It 'beta still rejects a non-positive tenant id' {
        Set-ReportsTestSession -Mode beta
        { Invoke-InforcerReport -ReportType ActiveUserCount -OutputFormat csv -TenantId 0 -NoWait -ErrorAction Stop } |
            Should -Throw '*must be positive integers*'
    }

    It '-WhatIf never posts' {
        Set-ReportsTestSession -Mode v1
        $null = Invoke-InforcerReport -ReportType ActiveUserCount -OutputFormat csv -TenantId $script:Tid1 -WhatIf
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerApiRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'POST' }
    }

    It 'lookup failure hint names the API client permission on v1 and the API scope on beta' {
        Mock -ModuleName InforcerCommunity Get-InforcerTenantList { Write-Error -Message 'denied' -ErrorId 'ApiRequestFailed_403' -Category ConnectionError }
        Set-ReportsTestSession -Mode v1
        Invoke-InforcerReport -ReportType ActiveUserCount -OutputFormat csv -TenantId 'Contoso Example' -NoWait -ErrorVariable v1Err -ErrorAction SilentlyContinue
        ($v1Err | Where-Object { $_.FullyQualifiedErrorId -like 'TenantLookupUnavailable*' } | Select-Object -First 1).Exception.Message |
            Should -BeLike '*API client*Tenants permission*Microsoft tenant ID*'
        Set-ReportsTestSession -Mode beta
        Invoke-InforcerReport -ReportType ActiveUserCount -OutputFormat csv -TenantId 'Contoso Example' -NoWait -ErrorVariable betaErr -ErrorAction SilentlyContinue
        ($betaErr | Where-Object { $_.FullyQualifiedErrorId -like 'TenantLookupUnavailable*' } | Select-Object -First 1).Exception.Message |
            Should -BeLike '*Tenants.Read scope*numeric Client Tenant ID*'
    }
}

Describe 'Invoke-InforcerReport outputs' {
    BeforeEach {
        Mock -ModuleName InforcerCommunity Invoke-InforcerApiRequest { [pscustomobject]@{ runId = '00000000-0000-0000-0000-0000000000a1' } }
        Mock -ModuleName InforcerCommunity Invoke-InforcerRawDownload {
            $file = Join-Path $DestinationDirectory ($Endpoint -replace '.*/', '')
            [System.IO.File]::WriteAllText($file, '{}')
            [pscustomobject]@{ FilePath = $file; FileName = [System.IO.Path]::GetFileName($file); FileSize = 2; ContentType = 'application/json'; CorrelationId = 'cor-1' }
        }
    }

    It 'v1 keeps the Microsoft tenant ID per output, uses the Collated sentinel for a null tenant and downloads via the neutral endpoint' {
        Set-ReportsTestSession -Mode v1
        Mock -ModuleName InforcerCommunity Test-InforcerReportRunTerminal {
            [pscustomobject]@{ IsTerminal = $true; Outputs = @(
                [pscustomobject]@{ id = 'out-1'; reportType = 'ActiveUserCount'; tenantId = '00000000-0000-0000-0000-000000000001'; format = 'json'; sizeBytes = 2 }
                [pscustomobject]@{ id = 'out-2'; reportType = 'ActiveUserCount'; tenantId = $null; format = 'json'; sizeBytes = 2 }
            ) }
        }
        $r = @(Invoke-InforcerReport -ReportType ActiveUserCount -OutputFormat json -TenantId $script:Tid1, $script:Tid2 -OutputPath $TestDrive)
        $r.Count | Should -Be 2
        $r[0].TenantId | Should -BeExactly $script:Tid1
        $r[1].TenantId | Should -BeExactly 'Collated'
        $r[0].RunId | Should -Be $script:Run1
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerRawDownload -Times 1 -Exactly -ParameterFilter {
            $Endpoint -eq '/reports/runs/00000000-0000-0000-0000-0000000000a1/outputs/out-1'
        }
    }

    It 'v1 -Collate labels every output Collated' {
        Set-ReportsTestSession -Mode v1
        Mock -ModuleName InforcerCommunity Test-InforcerReportRunTerminal {
            [pscustomobject]@{ IsTerminal = $true; Outputs = @(
                [pscustomobject]@{ id = 'out-1'; reportType = 'ActiveUserCount'; tenantId = $null; format = 'json'; sizeBytes = 2 }) }
        }
        $r = @(Invoke-InforcerReport -ReportType ActiveUserCount -OutputFormat json -TenantId $script:Tid1, $script:Tid2 -Collate -OutputPath $TestDrive)
        $r[0].TenantId | Should -BeExactly 'Collated'
    }

    It 'beta keeps integer tenant ids and maps 0 / null / missing to Collated' {
        Set-ReportsTestSession -Mode beta
        Mock -ModuleName InforcerCommunity Test-InforcerReportRunTerminal {
            [pscustomobject]@{ IsTerminal = $true; Outputs = @(
                [pscustomobject]@{ id = 'out-1'; reportType = 'ActiveUserCount'; tenantId = 14436; format = 'json'; sizeBytes = 2 }
                [pscustomobject]@{ id = 'out-2'; reportType = 'ActiveUserCount'; tenantId = 0; format = 'json'; sizeBytes = 2 }
                [pscustomobject]@{ id = 'out-3'; reportType = 'ActiveUserCount'; format = 'json'; sizeBytes = 2 }
            ) }
        }
        $r = @(Invoke-InforcerReport -ReportType ActiveUserCount -OutputFormat json -TenantId 14436 -OutputPath $TestDrive)
        $r[0].TenantId | Should -BeOfType [int]
        $r[0].TenantId | Should -Be 14436
        $r[1].TenantId | Should -BeExactly 'Collated'
        $r[2].TenantId | Should -BeExactly 'Collated'
    }
}

Describe 'Test-InforcerReportRunTerminal' {
    It 'v1 probes the v1 outputs URI with a bearer header and maps msTenantId to tenantId' {
        Set-ReportsTestSession -Mode v1
        Mock -ModuleName InforcerCommunity Invoke-WebRequest {
            [pscustomobject]@{ StatusCode = 200; Headers = @{ 'x-correlation-id' = 'cor-1' }
                Content = '{"outputs":[{"id":"out-1","reportType":"X","msTenantId":"00000000-0000-0000-0000-000000000001","format":"csv","sizeBytes":4},{"id":"out-2","reportType":"X","msTenantId":null,"format":"csv","sizeBytes":4}]}' }
        }
        $r = & $script:M { Test-InforcerReportRunTerminal -RunId ([guid]'00000000-0000-0000-0000-0000000000a1') }
        $r.IsTerminal | Should -BeTrue
        $r.Outputs.Count | Should -Be 2
        $r.Outputs[0].tenantId | Should -Be $script:Tid1
        $r.Outputs[1].tenantId | Should -BeNullOrEmpty
        $r.Outputs[0].PSObject.Properties['msTenantId'] | Should -BeNullOrEmpty
        Should -Invoke -ModuleName InforcerCommunity Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'https://api.example.invalid/v1/reports/runs/00000000-0000-0000-0000-0000000000a1/outputs' -and
            $Headers['Authorization'] -eq 'Bearer access-token-example-value' -and -not $Headers.ContainsKey('Inf-Api-Key')
        }
    }

    It 'beta probes the beta URI with the API key and unwraps data.outputs' {
        Set-ReportsTestSession -Mode beta
        Mock -ModuleName InforcerCommunity Invoke-WebRequest {
            [pscustomobject]@{ StatusCode = 200; Headers = @{}
                Content = '{"data":{"outputs":[{"id":"out-1","reportType":"X","tenantId":14436,"format":"csv","sizeBytes":4}]},"success":true}' }
        }
        $r = & $script:M { Test-InforcerReportRunTerminal -RunId ([guid]'00000000-0000-0000-0000-0000000000a1') }
        $r.Outputs[0].tenantId | Should -Be 14436
        Should -Invoke -ModuleName InforcerCommunity Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'https://api.example.invalid/api/beta/reports/runs/00000000-0000-0000-0000-0000000000a1/outputs' -and
            $Headers['Inf-Api-Key'] -eq 'beta-test-key-value' -and -not $Headers.ContainsKey('Authorization')
        }
    }

    It 'v1 treats 404 as not terminal yet' {
        Set-ReportsTestSession -Mode v1
        Mock -ModuleName InforcerCommunity Invoke-WebRequest {
            [pscustomobject]@{ StatusCode = 404; Headers = @{}; Content = '{"title":"Not Found","status":404}' }
        }
        $r = & $script:M { Test-InforcerReportRunTerminal -RunId ([guid]'00000000-0000-0000-0000-0000000000a1') }
        $r.IsTerminal | Should -BeFalse
        $r.Outputs | Should -BeNullOrEmpty
    }

    It 'fetches the auth header on every probe so a long wait picks up a renewed v1 token' {
        Set-ReportsTestSession -Mode v1
        Mock -ModuleName InforcerCommunity Get-InforcerAuthHeader { @{ Authorization = 'Bearer renewed-token-example' } }
        Mock -ModuleName InforcerCommunity Invoke-WebRequest { [pscustomobject]@{ StatusCode = 404; Headers = @{}; Content = '{}' } }
        $null = & $script:M { $id = [guid]'00000000-0000-0000-0000-0000000000a1'; Test-InforcerReportRunTerminal -RunId $id; Test-InforcerReportRunTerminal -RunId $id }
        Should -Invoke -ModuleName InforcerCommunity Get-InforcerAuthHeader -Times 2 -Exactly
        Should -Invoke -ModuleName InforcerCommunity Invoke-WebRequest -Times 2 -Exactly -ParameterFilter { $Headers['Authorization'] -eq 'Bearer renewed-token-example' }
    }

    It 'v1 renews the token once after a 401 and retries' {
        Set-ReportsTestSession -Mode v1
        & $script:M { $script:ProbeCalls = 0 }
        Mock -ModuleName InforcerCommunity Get-InforcerAuthHeader { @{ Authorization = 'Bearer token-example' } }
        Mock -ModuleName InforcerCommunity Invoke-WebRequest {
            $script:ProbeCalls++
            if ($script:ProbeCalls -eq 1) { [pscustomobject]@{ StatusCode = 401; Headers = @{}; Content = '{"title":"Unauthorized","status":401}' } }
            else { [pscustomobject]@{ StatusCode = 200; Headers = @{}; Content = '{"outputs":[]}' } }
        }
        $r = & $script:M { Test-InforcerReportRunTerminal -RunId ([guid]'00000000-0000-0000-0000-0000000000a1') }
        $r.IsTerminal | Should -BeTrue
        Should -Invoke -ModuleName InforcerCommunity Get-InforcerAuthHeader -Times 1 -Exactly -ParameterFilter { $ForceRefresh }
        Should -Invoke -ModuleName InforcerCommunity Invoke-WebRequest -Times 2 -Exactly
    }

    It 'surfaces the problem+json title and detail for other errors' {
        Set-ReportsTestSession -Mode v1
        Mock -ModuleName InforcerCommunity Invoke-WebRequest {
            [pscustomobject]@{ StatusCode = 403; Headers = @{}; Content = '{"title":"Forbidden","detail":"Missing reports permission","status":403}' }
        }
        $err = & $script:M {
            Test-InforcerReportRunTerminal -RunId ([guid]'00000000-0000-0000-0000-0000000000a1') -ErrorVariable e -ErrorAction SilentlyContinue
            $e
        }
        "$err" | Should -BeLike '*Forbidden: Missing reports permission*'
    }
}

Describe 'Invoke-InforcerRawDownload' {
    It 'v1 downloads from the v1 URI with a bearer header' {
        Set-ReportsTestSession -Mode v1
        Mock -ModuleName InforcerCommunity Invoke-WebRequest {
            [pscustomobject]@{ StatusCode = 200; Headers = @{ 'Content-Disposition' = 'attachment; filename="Report.csv"'; 'Content-Type' = 'text/csv' }
                Content = [System.Text.Encoding]::UTF8.GetBytes('a,b') }
        }
        $r = & $script:M { Invoke-InforcerRawDownload -Endpoint '/reports/runs/r1/outputs/o1' }
        $r.FileName | Should -Be 'Report.csv'
        $r.Bytes.Length | Should -Be 3
        Should -Invoke -ModuleName InforcerCommunity Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'https://api.example.invalid/v1/reports/runs/r1/outputs/o1' -and $Headers['Accept'] -eq '*/*' -and
            $Headers['Authorization'] -eq 'Bearer access-token-example-value' -and -not $Headers.ContainsKey('Inf-Api-Key')
        }
    }

    It 'beta downloads from the beta URI with the API key' {
        Set-ReportsTestSession -Mode beta
        Mock -ModuleName InforcerCommunity Invoke-WebRequest {
            [pscustomobject]@{ StatusCode = 200; Headers = @{}; Content = [System.Text.Encoding]::UTF8.GetBytes('a,b') }
        }
        $null = & $script:M { Invoke-InforcerRawDownload -Endpoint '/reports/runs/r1/outputs/o1' }
        Should -Invoke -ModuleName InforcerCommunity Invoke-WebRequest -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'https://api.example.invalid/api/beta/reports/runs/r1/outputs/o1' -and
            $Headers['Inf-Api-Key'] -eq 'beta-test-key-value' -and -not $Headers.ContainsKey('Authorization')
        }
    }

    It 'v1 reports the problem+json title and detail on a 404' {
        Set-ReportsTestSession -Mode v1
        Mock -ModuleName InforcerCommunity Invoke-WebRequest {
            [pscustomobject]@{ StatusCode = 404; Headers = @{}
                Content = [System.Text.Encoding]::UTF8.GetBytes('{"title":"Not Found","detail":"Output not available","status":404}') }
        }
        $err = & $script:M {
            Invoke-InforcerRawDownload -Endpoint '/reports/runs/r1/outputs/o1' -ErrorVariable e -ErrorAction SilentlyContinue
            $e
        }
        "$err" | Should -BeLike '*HTTP 404*Not Found: Output not available*'
    }

    It 'v1 renews the token and retries once after a 401' {
        Set-ReportsTestSession -Mode v1
        & $script:M { $script:DownloadCalls = 0 }
        Mock -ModuleName InforcerCommunity Get-InforcerAuthHeader { @{ Authorization = 'Bearer token-example' } }
        Mock -ModuleName InforcerCommunity Invoke-WebRequest {
            $script:DownloadCalls++
            if ($script:DownloadCalls -eq 1) { [pscustomobject]@{ StatusCode = 401; Headers = @{}; Content = [System.Text.Encoding]::UTF8.GetBytes('{}') } }
            else { [pscustomobject]@{ StatusCode = 200; Headers = @{}; Content = [System.Text.Encoding]::UTF8.GetBytes('ok') } }
        }
        $r = & $script:M { Invoke-InforcerRawDownload -Endpoint '/reports/runs/r1/outputs/o1' }
        $r.Bytes.Length | Should -Be 2
        Should -Invoke -ModuleName InforcerCommunity Get-InforcerAuthHeader -Times 1 -Exactly -ParameterFilter { $ForceRefresh }
    }
}

Describe 'Invoke-InforcerAssessmentRun runspace' {
    BeforeEach { $script:Server = $null }
    AfterEach { if ($script:Server) { Stop-ReportsTestServer $script:Server } }

    It 'v1 hands the runspace a bearer header and the v1 URI, sends no Content-Type, and maps assessmentId' {
        $script:Server = Start-ReportsTestServer -Json '{"assessmentId":"a1","name":"Example Assessment","results":[]}'
        Set-ReportsTestSession -Mode v1 -ApiHost $script:Server.ApiHost
        $r = & $script:M {
            param($t)
            Invoke-InforcerAssessmentRun -TenantId $t -ResolvedAssessmentId 'a1' -TenantDisplayName 'Contoso Example' -AssessmentDisplayName 'Example Assessment' 6>$null
        } $script:Tid1
        $script:Server.Seen.Method | Should -Be 'POST'
        $script:Server.Seen.Path | Should -Be "/v1/tenants/$($script:Tid1)/assessments/a1/runs"
        $script:Server.Seen.Auth | Should -BeExactly 'Bearer access-token-example-value'
        $script:Server.Seen.ApiKey | Should -BeNullOrEmpty
        $script:Server.Seen.ContentType | Should -BeNullOrEmpty
        $r.assessment | Should -Be 'a1'
        $r.PSObject.Properties['assessmentId'] | Should -BeNullOrEmpty
    }

    It 'beta hands the runspace the API key and the beta URI and returns .data' {
        $script:Server = Start-ReportsTestServer -Json '{"data":{"assessment":"a1","results":[]},"success":true}'
        Set-ReportsTestSession -Mode beta -ApiHost $script:Server.ApiHost
        $r = & $script:M {
            Invoke-InforcerAssessmentRun -TenantId 14436 -ResolvedAssessmentId 'a1' -TenantDisplayName 'Contoso Example' -AssessmentDisplayName 'Example Assessment' 6>$null
        }
        $script:Server.Seen.Path | Should -Be '/api/beta/tenants/14436/assessments/a1/runs'
        $script:Server.Seen.ApiKey | Should -BeExactly 'beta-test-key-value'
        $script:Server.Seen.Auth | Should -BeNullOrEmpty
        $script:Server.Seen.ContentType | Should -BeNullOrEmpty
        $r.assessment | Should -Be 'a1'
    }

    It 'v1 shows the problem+json title and detail when the run is rejected' {
        $script:Server = Start-ReportsTestServer -Status 409 -Json '{"title":"Conflict","detail":"Assessment already running","status":409}'
        Set-ReportsTestSession -Mode v1 -ApiHost $script:Server.ApiHost
        $err = & $script:M {
            param($t)
            $null = Invoke-InforcerAssessmentRun -TenantId $t -ResolvedAssessmentId 'a1' -TenantDisplayName 'Contoso Example' -AssessmentDisplayName 'Example Assessment' -ErrorVariable e -ErrorAction SilentlyContinue 6>$null
            $e
        } $script:Tid1
        ($err | ForEach-Object { "$_" }) -join ' ' | Should -BeLike '*Conflict: Assessment already running*'
    }
}

Describe 'AssessmentId completer' {
    BeforeEach { $script:Server = $null }
    AfterEach { if ($script:Server) { Stop-ReportsTestServer $script:Server } }

    It 'v1 fetches /v1/assessments with a bearer header built inside the module and caches the list' {
        $script:Server = Start-ReportsTestServer -Json '{"assessments":[{"id":"a1","name":"Copilot Readiness Example"}]}'
        Set-ReportsTestSession -Mode v1 -ApiHost $script:Server.ApiHost
        $res = @(& $script:AssessmentCompleter 'Invoke-InforcerReport' 'AssessmentId' '' $null @{ ReportType = 'Assessment' })
        $res.Count | Should -Be 1
        $res[0].CompletionText | Should -Be 'a1'
        $res[0].ListItemText | Should -Be 'Copilot Readiness Example'
        $script:Server.Seen.Path | Should -Be '/v1/assessments'
        $script:Server.Seen.Auth | Should -BeExactly 'Bearer access-token-example-value'
        (& $script:M { @($script:InforcerAssessmentCache).Count }) | Should -Be 1
    }

    It 'beta fetches the beta endpoint with the API key and reads data' {
        $script:Server = Start-ReportsTestServer -Json '{"data":[{"id":"b1","name":"Beta Example"}],"success":true}'
        Set-ReportsTestSession -Mode beta -ApiHost $script:Server.ApiHost
        $res = @(& $script:AssessmentCompleter 'Invoke-InforcerReport' 'AssessmentId' 'b' $null @{ ReportType = 'Assessment' })
        $res[0].CompletionText | Should -Be 'b1'
        $script:Server.Seen.Path | Should -Be '/api/beta/assessments'
        $script:Server.Seen.ApiKey | Should -BeExactly 'beta-test-key-value'
        $script:Server.Seen.Auth | Should -BeNullOrEmpty
    }

    It 'v1 403 caches a denial labelled with the API client permission' {
        $script:Server = Start-ReportsTestServer -Status 403 -Json '{"title":"Forbidden","status":403}'
        Set-ReportsTestSession -Mode v1 -ApiHost $script:Server.ApiHost
        $res = @(& $script:AssessmentCompleter 'Invoke-InforcerReport' 'AssessmentId' '' $null @{ ReportType = 'Assessment' })
        $res[0].ListItemText | Should -Be '<Tenant Assessment permission required>'
        (& $script:M { [bool]$script:InforcerAssessmentCacheDeniedAt }) | Should -BeTrue
    }

    It 'v1 serves the cache without any request' {
        Set-ReportsTestSession -Mode v1
        & $script:M { $script:InforcerAssessmentCache = @([pscustomobject]@{ id = 'a9'; name = 'Cached Example' }) }
        $res = @(& $script:AssessmentCompleter 'Invoke-InforcerReport' 'AssessmentId' 'cach' $null @{ ReportType = 'Assessment' })
        $res[0].CompletionText | Should -Be 'a9'
    }

    It 'offers nothing when another report type is bound, and assessments while -ReportType is still unbound' {
        Set-ReportsTestSession -Mode v1
        & $script:M { $script:InforcerAssessmentCache = @([pscustomobject]@{ id = 'a9'; name = 'Cached Example' }) }
        @(& $script:AssessmentCompleter 'Invoke-InforcerReport' 'AssessmentId' '' $null @{ ReportType = 'ActiveUserCount' }).Count | Should -Be 0
        @(& $script:AssessmentCompleter 'Invoke-InforcerReport' 'AssessmentId' '' $null @{})[0].CompletionText | Should -Be 'a9'
    }

    It 'offers a connect hint when there is no session' {
        & $script:M { $script:InforcerSession = $null }
        $res = @(& $script:AssessmentCompleter 'Invoke-InforcerReport' 'AssessmentId' '' $null @{ ReportType = 'Assessment' })
        $res[0].ListItemText | Should -Be '<Run Connect-Inforcer first>'
    }
}

Describe 'Assessment and report listings on v1' {
    It 'Get-InforcerAssessment reads GET /v1/assessments' {
        Set-ReportsTestSession -Mode v1
        Mock -ModuleName InforcerCommunity Invoke-RestMethod {
            [pscustomobject]@{ assessments = @([pscustomobject]@{ id = 'a1'; name = 'Copilot Readiness Example'; assessmentType = 'platform' }) }
        }
        $r = @(Get-InforcerAssessment)
        $r.Count | Should -Be 1
        $r[0].id | Should -Be 'a1'
        $r[0].PSObject.TypeNames[0] | Should -Be 'InforcerCommunity.Assessment'
        Should -Invoke -ModuleName InforcerCommunity Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Uri -eq 'https://api.example.invalid/v1/assessments' }
    }

    It 'Get-InforcerAssessment -OutputType JsonObject stays a JSON array for one assessment' {
        Set-ReportsTestSession -Mode v1
        Mock -ModuleName InforcerCommunity Invoke-RestMethod { [pscustomobject]@{ assessments = @([pscustomobject]@{ id = 'a1'; name = 'Example' }) } }
        (Get-InforcerAssessment -OutputType JsonObject).TrimStart() | Should -Match '^\['
    }

    It 'Resolve-InforcerAssessmentId resolves a name through the v1 list' {
        Set-ReportsTestSession -Mode v1
        Mock -ModuleName InforcerCommunity Invoke-RestMethod { [pscustomobject]@{ assessments = @([pscustomobject]@{ id = 'a1'; name = 'Copilot Readiness Example' }) } }
        (& $script:M { Resolve-InforcerAssessmentId -AssessmentId 'copilot readiness example' }) | Should -Be 'a1'
    }

    It 'Get-InforcerReportType reads GET /v1/reports/types, keeps singleTenantOnly and primes the cache' {
        Set-ReportsTestSession -Mode v1
        Mock -ModuleName InforcerCommunity Invoke-RestMethod {
            [pscustomobject]@{ reportTypes = @([pscustomobject]@{ key = 'ActiveUserCount'; name = 'Active users'; collatable = $true; singleTenantOnly = $false
                supportedOutputFormats = @('csv', 'json'); tags = @('Adoption'); requiredParameters = @() }) }
        }
        $r = @(Get-InforcerReportType -Force)
        $r.Count | Should -Be 1
        $r[0].key | Should -Be 'ActiveUserCount'
        $r[0].singleTenantOnly | Should -BeFalse
        @(Get-InforcerReportType -OutputFormat csv).Count | Should -Be 1
        @(Get-InforcerReportType -OutputFormat pdf).Count | Should -Be 0
        Should -Invoke -ModuleName InforcerCommunity Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Uri -eq 'https://api.example.invalid/v1/reports/types' }
    }

    It 'Get-InforcerReportRun maps reportRunId to runId and filters by -RunId' {
        Set-ReportsTestSession -Mode v1
        Mock -ModuleName InforcerCommunity Invoke-RestMethod {
            [pscustomobject]@{ reportRuns = @(
                [pscustomobject]@{ reportRunId = '00000000-0000-0000-0000-0000000000a1'; status = 'completed' }
                [pscustomobject]@{ reportRunId = '00000000-0000-0000-0000-0000000000a2'; status = 'running' }) }
        }
        @(Get-InforcerReportRun).Count | Should -Be 2
        $one = @(Get-InforcerReportRun -RunId $script:Run1)
        $one.Count | Should -Be 1
        $one[0].runId | Should -Be $script:Run1
        $one[0].Id | Should -Be $script:Run1
        $one[0].PSObject.Properties['reportRunId'] | Should -BeNullOrEmpty
        Should -Invoke -ModuleName InforcerCommunity Invoke-RestMethod -ParameterFilter { $Uri -eq 'https://api.example.invalid/v1/reports/runs' }
    }

    It 'Get-InforcerReportRun -IncludeOutputs embeds the mapped outputs' {
        Set-ReportsTestSession -Mode v1
        Mock -ModuleName InforcerCommunity Invoke-RestMethod { [pscustomobject]@{ reportRuns = @([pscustomobject]@{ reportRunId = '00000000-0000-0000-0000-0000000000a1'; status = 'completed' }) } }
        Mock -ModuleName InforcerCommunity Test-InforcerReportRunTerminal {
            [pscustomobject]@{ IsTerminal = $true; Outputs = @([pscustomobject]@{ id = 'out-1'; tenantId = $null; format = 'csv' }) }
        }
        $r = @(Get-InforcerReportRun -IncludeOutputs)
        $r[0].outputs.Count | Should -Be 1
        $r[0].outputs[0].id | Should -Be 'out-1'
    }
}

Describe 'Save-InforcerReportOutput' {
    It 'downloads through the neutral endpoint and carries the tenant given via -MsTenantId' {
        Set-ReportsTestSession -Mode v1
        Mock -ModuleName InforcerCommunity Invoke-InforcerRawDownload {
            $file = Join-Path $DestinationDirectory 'x.csv'
            [System.IO.File]::WriteAllText($file, 'a')
            [pscustomobject]@{ FilePath = $file; FileName = 'x.csv'; FileSize = 1; ContentType = 'text/csv'; CorrelationId = 'cor-1' }
        }
        $r = Save-InforcerReportOutput -RunId $script:Run1 -OutputId 'out-1' -MsTenantId $script:Tid1 -OutputPath $TestDrive -Confirm:$false
        $r.TenantId | Should -Be $script:Tid1
        $r.RunId | Should -Be $script:Run1
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerRawDownload -Times 1 -Exactly -ParameterFilter {
            $Endpoint -eq '/reports/runs/00000000-0000-0000-0000-0000000000a1/outputs/out-1'
        }
    }
}

Describe 'Invoke-InforcerAssessment tenant handling' {
    BeforeEach {
        Mock -ModuleName InforcerCommunity Invoke-InforcerApiRequest { @([pscustomobject]@{ id = 'a1'; name = 'Example Assessment' }) }
        Mock -ModuleName InforcerCommunity Invoke-InforcerAssessmentRun { [pscustomobject]@{ assessment = 'a1'; results = @() } }
    }

    It 'v1 -MultiTenant finds the tenants through Get-InforcerTenantList and runs against their Microsoft tenant IDs' {
        Set-ReportsTestSession -Mode v1
        Mock -ModuleName InforcerCommunity Get-InforcerTenantList {
            @([pscustomobject]@{ msTenantId = '00000000-0000-0000-0000-000000000001'; tenantFriendlyName = 'Contoso Example'; tenantDnsName = 'contoso.example.invalid' }
              [pscustomobject]@{ msTenantId = '00000000-0000-0000-0000-000000000002'; tenantFriendlyName = 'Fabrikam Example'; tenantDnsName = 'fabrikam.example.invalid' })
        }
        $json = Invoke-InforcerAssessment -AssessmentId 'a1' -MultiTenant -OutputType JsonObject 6>$null | ConvertFrom-Json
        @($json).Count | Should -Be 2
        $json[0].TenantId | Should -Be $script:Tid1
        $json[0].TenantName | Should -Be 'Contoso Example'
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerAssessmentRun -Times 1 -Exactly -ParameterFilter { $TenantId -eq '00000000-0000-0000-0000-000000000001' }
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerAssessmentRun -Times 1 -Exactly -ParameterFilter { $TenantId -eq '00000000-0000-0000-0000-000000000002' }
    }

    It 'v1 resolves tenant names for a subset run' {
        Set-ReportsTestSession -Mode v1
        Mock -ModuleName InforcerCommunity Get-InforcerTenantList {
            @([pscustomobject]@{ msTenantId = '00000000-0000-0000-0000-000000000001'; tenantFriendlyName = 'Contoso Example'; tenantDnsName = 'contoso.example.invalid' }
              [pscustomobject]@{ msTenantId = '00000000-0000-0000-0000-000000000002'; tenantFriendlyName = 'Fabrikam Example'; tenantDnsName = 'fabrikam.example.invalid' })
        }
        $null = Invoke-InforcerAssessment -TenantId 'Fabrikam Example', 'Contoso Example' -AssessmentId 'a1' -OutputType JsonObject 6>$null
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerAssessmentRun -Times 1 -Exactly -ParameterFilter { $TenantId -eq '00000000-0000-0000-0000-000000000002' }
    }

    It 'v1 accepts a GUID for a single tenant and refuses a numeric id' {
        Set-ReportsTestSession -Mode v1
        Mock -ModuleName InforcerCommunity Get-InforcerTenantList {
            @([pscustomobject]@{ msTenantId = '00000000-0000-0000-0000-000000000001'; tenantFriendlyName = 'Contoso Example'; tenantDnsName = 'contoso.example.invalid' })
        }
        $null = Invoke-InforcerAssessment -TenantId $script:Tid1 -AssessmentId 'a1' -OutputType JsonObject 6>$null
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerAssessmentRun -Times 1 -Exactly -ParameterFilter { $TenantId -eq '00000000-0000-0000-0000-000000000001' }
        { Invoke-InforcerAssessment -TenantId 482 -AssessmentId 'a1' -ErrorAction Stop 6>$null } | Should -Throw '*only works when you connect with an API key*'
    }

    It 'beta -MultiTenant still uses numeric Client Tenant IDs' {
        Set-ReportsTestSession -Mode beta
        Mock -ModuleName InforcerCommunity Get-InforcerTenantList {
            @([pscustomobject]@{ clientTenantId = 1; tenantFriendlyName = 'Contoso Example'; tenantDnsName = 'contoso.example.invalid' }
              [pscustomobject]@{ clientTenantId = 2; tenantFriendlyName = 'Fabrikam Example'; tenantDnsName = 'fabrikam.example.invalid' })
        }
        $json = Invoke-InforcerAssessment -AssessmentId 'a1' -MultiTenant -OutputType JsonObject 6>$null | ConvertFrom-Json
        $json[1].TenantId | Should -Be 2
        $json[1].TenantName | Should -Be 'Fabrikam Example'
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerAssessmentRun -Times 1 -Exactly -ParameterFilter { $TenantId -eq '1' }
    }
}
