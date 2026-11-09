# Fix.Red.Tests.ps1
# Red-lane review of the 1.0.0 branch (2026-11-08): one test per fixed finding. No network calls except
# the debug-stream test, which points at a closed local port so the request fails at once.

BeforeAll {
    Remove-Module -Name 'InforcerCommunity' -ErrorAction SilentlyContinue
    Import-Module (Join-Path $PSScriptRoot '../module/InforcerCommunity.psd1') -Force
    $script:M = Get-Module InforcerCommunity
    function global:Set-RedSession([string]$Version, [string]$Secret, [string]$ApiHost = 'https://api.example.invalid') {
        & (Get-Module InforcerCommunity) {
            param($v, $s, $h)
            $sec = ConvertTo-SecureString $s -AsPlainText -Force
            $script:InforcerSession = if ($v -eq 'beta') {
                @{ ApiVersion = 'beta'; AuthMode = 'ApiKey'; ApiHost = $h; BaseUrl = "$h/api"; Region = 'uk'; ApiKey = $sec }
            } else {
                @{ ApiVersion = 'v1'; AuthMode = 'ClientCredentials'; ApiHost = $h; BaseUrl = $h; Region = 'uk'; ClientId = 'c'
                   ClientSecret = $sec; AccessToken = $sec; TokenExpiresAt = [datetime]::UtcNow.AddMinutes(50) }
            }
            $script:InforcerTenantListCache = $null
        } $Version $Secret $ApiHost
    }
}

AfterAll {
    Remove-Item function:global:Set-RedSession -ErrorAction SilentlyContinue
    & (Get-Module InforcerCommunity) { $script:InforcerSession = $null }
}

Describe 'Credentials stay out of the debug stream' {
    It '<Version>: Save-InforcerReportOutput -Debug does not print the credential' -ForEach @(@{ Version = 'v1' }, @{ Version = 'beta' }) {
        $secret = 'SECRET' + [guid]::NewGuid().ToString('N').Substring(0, 12)
        Set-RedSession -Version $Version -Secret $secret -ApiHost 'https://127.0.0.1:1'
        $out = Save-InforcerReportOutput -RunId ([guid]::Empty) -OutputId 'o1' -OutputPath $TestDrive -Debug `
            -ErrorAction SilentlyContinue 5>&1 6>$null 3>$null | Out-String
        $out | Should -Not -Match $secret
    }

    It 'v1: Get-InforcerReportRun -Wait does not print the token under a global DebugPreference' {
        $secret = 'SECRET' + [guid]::NewGuid().ToString('N').Substring(0, 12)
        Set-RedSession -Version v1 -Secret $secret -ApiHost 'https://127.0.0.1:1'
        $old = $global:DebugPreference
        try {
            $global:DebugPreference = 'Continue'
            $out = Get-InforcerReportRun -RunId ([guid]::Empty) -Wait -TimeoutSeconds 10 -ErrorAction SilentlyContinue `
                5>&1 6>$null 3>$null | Out-String
        } finally { $global:DebugPreference = $old }
        $out | Should -Not -Match $secret
    }
}

Describe 'A non-JSON 200 answer that echoes the request' {
    It '<Version>: the credential is redacted in the error' -ForEach @(@{ Version = 'v1' }, @{ Version = 'beta' }) {
        $secret = 'SECRET' + [guid]::NewGuid().ToString('N').Substring(0, 12)
        Set-RedSession -Version $Version -Secret $secret
        Mock -ModuleName InforcerCommunity Invoke-InforcerHttpRequest {
            $h = $Request.Headers
            $line = if ($h['Inf-Api-Key']) { "Inf-Api-Key: $($h['Inf-Api-Key'])" } else { "Authorization: $($h['Authorization'])" }
            [pscustomobject]@{ StatusCode = 200; Headers = @{}; Body = "<html>Blocked by proxy. $line</html>" }
        }
        Get-InforcerBaseline -ErrorAction SilentlyContinue -ErrorVariable ev
        $ev[-1].Exception.Message | Should -Match 'REDACTED'
        $ev[-1].Exception.Message | Should -Not -Match $secret
    }
}

Describe 'A piped object without a tenant id does not lift the tenant filter' {
    BeforeAll {
        $script:A = '00000000-0000-0000-0000-0000000000a1'; $script:B = '00000000-0000-0000-0000-0000000000b2'
    }
    BeforeEach {
        Set-RedSession -Version v1 -Secret 'k'
        Mock -ModuleName InforcerCommunity Invoke-InforcerHttpRequest {
            $a = '00000000-0000-0000-0000-0000000000a1'; $b = '00000000-0000-0000-0000-0000000000b2'
            $body = switch -Regex ($Request.Uri) {
                '/alignmentScores$' { [pscustomobject]@{ alignmentScores = @(
                    [pscustomobject]@{ msTenantId = $a; tenantName = 'Contoso'; alignmentScore = 90 },
                    [pscustomobject]@{ msTenantId = $b; tenantName = 'Fabrikam'; alignmentScore = 40 }) } }
                '/tenants$' { [pscustomobject]@{ tenants = @([pscustomobject]@{ msTenantId = $a; name = 'Contoso' }, [pscustomobject]@{ msTenantId = $b; name = 'Fabrikam' }) } }
                '/baselines$' { [pscustomobject]@{ baselines = @(
                    [pscustomobject]@{ id = 'b1'; name = 'Contoso BL'; baselineTenant = [pscustomobject]@{ msTenantId = $a }; members = @() },
                    [pscustomobject]@{ id = 'b2'; name = 'Fabrikam BL'; baselineTenant = [pscustomobject]@{ msTenantId = $b }; members = @() }) } }
            }
            [pscustomobject]@{ StatusCode = 200; Headers = @{}; Body = $body }
        }
    }

    It 'Get-InforcerAlignmentDetails -Format Raw' {
        $r = @(@([pscustomobject]@{ MsTenantId = $script:A }, [pscustomobject]@{ TenantId = $null }) | Get-InforcerAlignmentDetails -Format Raw)
        @($r.tenantFriendlyName) | Should -Be @('Contoso')
    }

    It 'Get-InforcerBaseline' {
        $r = @(@([pscustomobject]@{ MsTenantId = $script:A }, [pscustomobject]@{ TenantId = $null }) | Get-InforcerBaseline)
        @($r.name) | Should -Be @('Contoso BL')
    }
}

Describe 'Assessment matrix with two tenants of the same name' {
    It 'keeps each tenant''s own result' {
        $chk = { param($s) [pscustomobject]@{ name = 'MFA required'; category = 'Identity'; subCategory = ''; importance = 'High'; Status = $s } }
        $tr = @(
            @{ TenantName = 'Contoso'; TenantId = '00000000-0000-0000-0000-000000000001'; Score = 0; Passed = 0; Failed = 1; NotAssessed = 0; TotalChecks = 1; Checks = @(& $chk 'Fail') }
            @{ TenantName = 'CONTOSO'; TenantId = '00000000-0000-0000-0000-000000000002'; Score = 100; Passed = 1; Failed = 0; NotAssessed = 0; TotalChecks = 1; Checks = @(& $chk 'Pass') }
        )
        $html = & $script:M { param($t) ConvertTo-InforcerAssessmentMatrixHtml -AssessmentName 'A' -TenantResults $t } $tr
        $rows = [regex]::Match($html, 'M=(\[.*?\]);').Groups[1].Value | ConvertFrom-Json
        $rows[0].statuses.'00000000-0000-0000-0000-000000000001' | Should -Be 'Fail'
        $rows[0].statuses.'00000000-0000-0000-0000-000000000002' | Should -Be 'Pass'
        # The tenant checkboxes toggle by id too, so each same-named column hides on its own.
        $html | Should -Match ([regex]::Escape('vis.has(String(t.id))'))
        $html | Should -Not -Match 'vis\.has\(t\.name\)|return t\.name\}'
    }
}

Describe 'Markdown export escapes every API-provided name' {
    It 'baseline, product and category names are not raw HTML' {
        $model = @{
            TenantName = 'T'; TenantId = 1; GeneratedAt = [datetime]'2026-01-15'
            FilterBaseline = '<img src=x onerror=alert(1)>'
            Products = [ordered]@{
                '<iframe src=//example.invalid>' = @{ Categories = [ordered]@{
                    '<a href=javascript:alert(2)>c</a>' = [System.Collections.Generic.List[object]]@(
                        @{ Basics = @{ Name = 'P' }; Settings = @(); Assignments = @() }) } }
            }
        }
        $md = & $script:M { param($m) ConvertTo-InforcerMarkdown -DocModel $m } $model
        $md | Should -Not -Match '<img|<iframe|<a href'
        $md | Should -Match '&lt;img'
    }
}
