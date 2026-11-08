# Fix.Blue.Tests.ps1
# Blue-lane review of the 1.0.0 branch (2026-11-08): a failed request is never shown as an empty or
# complete-looking result. Internal helpers are mocked; no network calls.

BeforeAll {
    Remove-Module -Name 'InforcerCommunity' -ErrorAction SilentlyContinue
    Import-Module (Join-Path $PSScriptRoot '../module/InforcerCommunity.psd1') -Force
    $script:M = Get-Module InforcerCommunity
    $script:T = '00000000-0000-0000-0000-000000000001'
    $script:B = '00000000-0000-0000-0000-0000000000b1'
    function global:Set-BlueSession([string]$Version = 'v1') {
        & (Get-Module InforcerCommunity) {
            param($v)
            $sec = ConvertTo-SecureString 'k' -AsPlainText -Force
            $h = 'https://api.example.invalid'
            $script:InforcerSession = if ($v -eq 'beta') {
                @{ ApiVersion = 'beta'; AuthMode = 'ApiKey'; ApiHost = $h; BaseUrl = "$h/api"; Region = 'uk'; ApiKey = $sec }
            } else {
                @{ ApiVersion = 'v1'; AuthMode = 'ClientCredentials'; ApiHost = $h; BaseUrl = $h; Region = 'uk'; ClientId = 'c'
                   ClientSecret = $sec; AccessToken = $sec; TokenExpiresAt = [datetime]::UtcNow.AddMinutes(50) }
            }
            $script:InforcerTenantListCache = $null
        } $Version
    }
}

AfterAll {
    Remove-Item function:global:Set-BlueSession -ErrorAction SilentlyContinue
    & (Get-Module InforcerCommunity) { $script:InforcerSession = $null }
}

Describe 'A failed by-id or detail request is an error, not silence' {
    It '<Version>: Get-InforcerUser -UserId surfaces an HTTP 500' -ForEach @(@{ Version = 'v1'; Tenant = '00000000-0000-0000-0000-000000000001' }, @{ Version = 'beta'; Tenant = 1 }) {
        Set-BlueSession $Version
        Mock -ModuleName InforcerCommunity Invoke-InforcerApiRequest { Write-Error 'Inforcer API request failed (HTTP 500)' -ErrorId 'ApiRequestFailed_500' -ErrorAction Continue }
        { Get-InforcerUser -TenantId $Tenant -UserId 'u1' -ErrorAction Stop } | Should -Throw '*HTTP 500*'
    }

    It 'Get-InforcerUser -UserId still says "not found" for a 404' {
        Set-BlueSession
        Mock -ModuleName InforcerCommunity Invoke-InforcerApiRequest { Write-Error 'not found' -ErrorId 'ApiRequestFailed_404' -ErrorAction Continue }
        Get-InforcerUser -TenantId $script:T -UserId 'u1' -ErrorAction SilentlyContinue -ErrorVariable e
        $e[-1].FullyQualifiedErrorId | Should -BeLike 'UserNotFound*'
    }

    It 'Get-InforcerAlignmentDetails -BaselineId surfaces an HTTP 500 instead of a warning' {
        Set-BlueSession
        Mock -ModuleName InforcerCommunity Invoke-InforcerApiRequest {
            if ($Endpoint -like '*alignmentDetails*') { Write-Error 'Inforcer API request failed (HTTP 500)' -ErrorId 'ApiRequestFailed_500' -ErrorAction Continue; return }
            if ($Endpoint -like '/tenants*') { return [pscustomobject]@{ msTenantId = '00000000-0000-0000-0000-000000000001'; tenantFriendlyName = 'Contoso' } }
        }
        { Get-InforcerAlignmentDetails -TenantId $script:T -BaselineId $script:B -ErrorAction Stop -WarningAction SilentlyContinue } |
            Should -Throw '*HTTP 500*'
    }
}

Describe 'An empty response body' {
    It '<Version>: is reported as an empty response, not a null-method crash' -ForEach @(@{ Version = 'v1' }, @{ Version = 'beta' }) {
        Set-BlueSession $Version
        Mock -ModuleName InforcerCommunity Invoke-InforcerHttpRequest { [pscustomobject]@{ StatusCode = 200; Headers = @{}; Body = '' } }
        Get-InforcerTenant -ErrorAction SilentlyContinue -ErrorVariable e
        $e[-1].FullyQualifiedErrorId | Should -BeLike 'EmptyResponse*'
    }
}

Describe 'A failed list request returns no JSON' {
    BeforeEach {
        Set-BlueSession
        Mock -ModuleName InforcerCommunity Invoke-InforcerPagedRequest {
            [pscustomobject]@{ id = 'i1'; displayName = 'Page one'; eventType = 'authentication' }
            Write-Error 'page 2 failed' -ErrorId 'ApiRequestFailed_500' -ErrorAction Continue
        }
        Mock -ModuleName InforcerCommunity Invoke-InforcerApiRequest { Write-Error 'boom' -ErrorId 'ApiRequestFailed_500' -ErrorAction Continue }
    }

    It 'Get-InforcerUser' { Get-InforcerUser -TenantId $script:T -OutputType JsonObject -ErrorAction SilentlyContinue | Should -BeNullOrEmpty }
    It 'Get-InforcerGroup' { Get-InforcerGroup -TenantId $script:T -OutputType JsonObject -ErrorAction SilentlyContinue | Should -BeNullOrEmpty }
    It 'Get-InforcerAuditEvent' { Get-InforcerAuditEvent -OutputType JsonObject -ErrorAction SilentlyContinue | Should -BeNullOrEmpty }
    It 'Get-InforcerRole' { Get-InforcerRole -TenantId $script:T -OutputType JsonObject -ErrorAction SilentlyContinue | Should -BeNullOrEmpty }
    It 'Get-InforcerTenantPolicies' { Get-InforcerTenantPolicies -TenantId $script:T -OutputType JsonObject -ErrorAction SilentlyContinue | Should -BeNullOrEmpty }
}
