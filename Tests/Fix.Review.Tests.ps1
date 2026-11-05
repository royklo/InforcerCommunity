# Fix.Review.Tests.ps1
# Copilot review round on PR #48 (2026-11-05): one test per fixed finding. Internal helpers are mocked;
# no network calls. Fixtures use zero GUIDs and example names.

BeforeAll {
    Remove-Module -Name 'InforcerCommunity' -ErrorAction SilentlyContinue
    Import-Module (Join-Path $PSScriptRoot '../module/InforcerCommunity.psd1') -Force
    $script:M = Get-Module InforcerCommunity
    $script:Run = '11111111-2222-3333-4444-555555555555'
    function global:Set-ReviewSession([string]$Version = 'v1') {
        & (Get-Module InforcerCommunity) {
            param($v)
            $script:InforcerSession = @{
                ApiVersion = $v; AuthMode = $(if ($v -eq 'v1') { 'ClientCredentials' } else { 'ApiKey' })
                ApiHost = 'https://api.example.invalid'; Region = 'uk'; ConnectedAt = Get-Date
                BaseUrl = $(if ($v -eq 'v1') { 'https://api.example.invalid' } else { 'https://api.example.invalid/api' })
                ApiKey = (ConvertTo-SecureString 'review-key' -AsPlainText -Force)
                AccessToken = (ConvertTo-SecureString 'review-token' -AsPlainText -Force); TokenExpiresAt = [datetime]::UtcNow.AddMinutes(50)
            }
        } $Version
    }
}

AfterAll {
    Remove-Item function:global:Set-ReviewSession -ErrorAction SilentlyContinue
    & (Get-Module InforcerCommunity) { $script:InforcerSession = $null }
}

Describe 'Resolve-InforcerGroupId' {
    BeforeEach { Mock -ModuleName InforcerCommunity Test-InforcerSession { $true } }
    It 'throws when a later search page fails, even though an earlier page held a match' {
        Set-ReviewSession
        Mock -ModuleName InforcerCommunity Invoke-InforcerPagedRequest {
            [pscustomobject]@{ id = '00000000-0000-0000-0000-0000000000a1'; displayName = 'Admins' }
            Write-Error 'page 2 failed' -ErrorId 'ApiRequestFailed_500'
        }
        { & $script:M { Resolve-InforcerGroupId -GroupId 'Admins' -TenantId '00000000-0000-0000-0000-000000000001' } } |
            Should -Throw '*Failed to search for group*'
    }
}

Describe 'Test-InforcerReportRunTerminal on v1' {
    BeforeEach { Mock -ModuleName InforcerCommunity Test-InforcerSession { $true } }
    It 'waits out a 429 and keeps polling instead of failing' {
        Set-ReviewSession
        $script:calls = 0
        Mock -ModuleName InforcerCommunity Start-Sleep { }
        Mock -ModuleName InforcerCommunity Get-InforcerAuthHeader { @{ Authorization = 'Bearer review-token' } }
        Mock -ModuleName InforcerCommunity Invoke-WebRequest {
            $script:calls++
            if ($script:calls -eq 1) { return [pscustomobject]@{ StatusCode = 429; Headers = @{ 'Retry-After' = '1' }; Content = '{"title":"Too Many Requests"}' } }
            [pscustomobject]@{ StatusCode = 200; Headers = @{}; Content = '{"outputs":[{"id":"o1","msTenantId":null}]}' }
        }
        $r = & $script:M { param($id) Test-InforcerReportRunTerminal -RunId $id } $script:Run
        $r.IsTerminal | Should -BeTrue
        $script:calls | Should -Be 2
        Should -Invoke -ModuleName InforcerCommunity Start-Sleep -Times 1 -Exactly
    }
}

Describe 'Invoke-InforcerAssessment with an empty pipeline' {
    BeforeEach { Mock -ModuleName InforcerCommunity Test-InforcerSession { $true } }
    It 'runs nothing when the pipeline held no tenant, even with -MultiTenant' {
        Set-ReviewSession
        Mock -ModuleName InforcerCommunity Invoke-InforcerAssessmentRun { [pscustomobject]@{ results = @() } }
        Mock -ModuleName InforcerCommunity Invoke-InforcerApiRequest {
            if (($Endpoint -replace '^/(beta|v1)', '') -eq '/tenants') { @([pscustomobject]@{ msTenantId = '00000000-0000-0000-0000-000000000001'; tenantFriendlyName = 'Contoso' }) }
            else { @([pscustomobject]@{ id = 'a1'; name = 'Test Assessment' }) }
        }
        $out = @(@() | Invoke-InforcerAssessment -MultiTenant -AssessmentId 'a1' 6>$null)
        $out.Count | Should -Be 0
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerAssessmentRun -Times 0 -Exactly
    }
}

Describe 'Select-InforcerBaselinePolicies on v1' {
    BeforeEach { Mock -ModuleName InforcerCommunity Test-InforcerSession { $true } }
    It 'does not report a baseline policy as missing when the tenant copy matched by id under another name' {
        Set-ReviewSession
        Mock -ModuleName InforcerCommunity Invoke-InforcerApiRequest {
            [pscustomobject]@{ alignment = [pscustomobject]@{
                matchedPolicies = @([pscustomobject]@{ policyName = 'Baseline Name'; id = 'b-1'; matchingSubjectPolicies = @([pscustomobject]@{ id = 't-1' }, [pscustomobject]@{ id = 't-2' }) })
                matchedWithAcceptedDeviations = @(); deviatedUnaccepted = @(); missingFromSubjectUnaccepted = @()
            } }
        }
        $doc = @{ TenantId = '00000000-0000-0000-0000-000000000001'; Policies = @(
            [pscustomobject]@{ displayName = 'Tenant Copy'; id = 't-1' }
            [pscustomobject]@{ displayName = 'Unrelated'; id = 'x-9' }
        ) }
        $null = & $script:M { param($d) Select-InforcerBaselinePolicies -DocData $d -BaselineId '00000000-0000-0000-0000-0000000000b1' -WarningVariable w 6>$null; $script:reviewWarnings = $w } $doc
        @($doc.Policies).Count | Should -Be 1
        & $script:M { $script:reviewWarnings } | Should -BeNullOrEmpty
    }

    It 'still lists a baseline policy the tenant has under neither its name nor an id' {
        Set-ReviewSession
        Mock -ModuleName InforcerCommunity Invoke-InforcerApiRequest {
            [pscustomobject]@{ alignment = [pscustomobject]@{
                matchedPolicies = @([pscustomobject]@{ policyName = 'Present'; id = 'b-1'; matchingSubjectPolicies = @() })
                matchedWithAcceptedDeviations = @(); deviatedUnaccepted = @()
                missingFromSubjectUnaccepted = @([pscustomobject]@{ policyName = 'Missing One'; id = 'b-2'; matchingSubjectPolicies = @() })
            } }
        }
        $doc = @{ TenantId = '00000000-0000-0000-0000-000000000001'; Policies = @([pscustomobject]@{ displayName = 'Present'; id = 'p-1' }) }
        $null = & $script:M { param($d) Select-InforcerBaselinePolicies -DocData $d -BaselineId '00000000-0000-0000-0000-0000000000b1' -WarningVariable w 6>$null; $script:reviewWarnings = $w } $doc
        $text = (& $script:M { $script:reviewWarnings }) -join "`n"
        $text | Should -Match '1 baseline policies not found'
        $text | Should -Match 'Missing One'
        $text | Should -Not -Match 'Present'
    }
}

Describe 'v1 JSON is always an array' {
    BeforeEach { Mock -ModuleName InforcerCommunity Test-InforcerSession { $true } }
    It 'Get-InforcerReportRun returns an array for one run and [] for none (<Case>)' -ForEach @(
        @{ Case = 'one run'; Runs = 1; Expect = 1 }
        @{ Case = 'no runs'; Runs = 0; Expect = 0 }
    ) {
        Set-ReviewSession
        $script:runCount = $Runs
        Mock -ModuleName InforcerCommunity Invoke-InforcerApiRequest {
            if ($script:runCount) { [pscustomobject]@{ runId = '11111111-2222-3333-4444-555555555555'; status = 'completed' } }
        }
        $json = Get-InforcerReportRun -OutputType JsonObject
        "$json".TrimStart() | Should -BeLike '`[*'
        ($json | ConvertFrom-Json -NoEnumerate).Count | Should -Be $Expect
    }

    It 'Get-InforcerReportRun returns nothing when the list request fails' {
        Set-ReviewSession
        Mock -ModuleName InforcerCommunity Invoke-InforcerApiRequest { Write-Error 'boom' -ErrorId 'ApiRequestFailed_500' }
        $json = Get-InforcerReportRun -OutputType JsonObject -ErrorAction SilentlyContinue
        $json | Should -BeNullOrEmpty
    }

    It 'beta: Get-InforcerReportRun keeps the 0.8.0 bare object for one run' {
        Set-ReviewSession -Version beta
        Mock -ModuleName InforcerCommunity Invoke-InforcerApiRequest { [pscustomobject]@{ runId = '11111111-2222-3333-4444-555555555555'; status = 'completed' } }
        (Get-InforcerReportRun -OutputType JsonObject).TrimStart() | Should -BeLike '{*'
    }
}
