# V1.UserWrite.Tests.ps1
# New-InforcerUser and Set-InforcerUser (v1 only). Fixtures are anonymised; no network calls.

BeforeAll {
    Remove-Module -Name 'InforcerCommunity' -ErrorAction SilentlyContinue
    Import-Module (Join-Path $PSScriptRoot '../module/InforcerCommunity.psd1') -Force

    $script:Tid = '00000000-0000-0000-0000-000000000001'
    $script:Uid = '00000000-0000-0000-0000-000000000005'
    $script:Pw = ConvertTo-SecureString 'Example-Passw0rd!' -AsPlainText -Force

    function global:New-UwResponse {
        param([string]$Json, [int]$Status = 200)
        $body = if ($Json) { $Json | ConvertFrom-Json -Depth 100 } else { '' }
        [pscustomobject]@{ StatusCode = $Status; Body = $body; Headers = @{} }
    }

    function global:Set-UwSession {
        param([switch]$Beta)
        & (Get-Module InforcerCommunity) {
            param($Beta)
            $script:InforcerTenantListCache = $null
            $script:InforcerSession = @{
                AuthMode = $(if ($Beta) { 'ApiKey' } else { 'ClientCredentials' }); ApiVersion = $(if ($Beta) { 'beta' } else { 'v1' })
                ApiHost = 'https://api.example.invalid'; BaseUrl = 'https://api.example.invalid'; Region = 'uk'; ConnectedAt = Get-Date
                ApiKey = (ConvertTo-SecureString 'beta-test-key-value' -AsPlainText -Force)
                ClientId = 'client-id-example'
                ClientSecret = (ConvertTo-SecureString 'client-secret-example-value' -AsPlainText -Force)
                AccessToken = (ConvertTo-SecureString 'access-token-example-value' -AsPlainText -Force)
                TokenExpiresAt = [datetime]::UtcNow.AddMinutes(50)
            }
        } $Beta.IsPresent
    }

    function global:Set-UwRoute {
        param([scriptblock]$Route)
        $global:UwCalls = [System.Collections.Generic.List[object]]::new()
        $global:UwRoute = $Route
        Mock -ModuleName InforcerCommunity Invoke-InforcerHttpRequest {
            $global:UwCalls.Add([pscustomobject]@{ Uri = [string]$Request.Uri; Method = $Request.Method; Body = $Request.Body })
            & $global:UwRoute ([string]$Request.Uri) $Request.Method $Request.Body
        }
    }
}

AfterAll {
    foreach ($f in 'New-UwResponse', 'Set-UwSession', 'Set-UwRoute') { Remove-Item "function:global:$f" -ErrorAction SilentlyContinue }
    Remove-Variable -Name UwCalls, UwRoute -Scope Global -ErrorAction SilentlyContinue
    & (Get-Module InforcerCommunity) { $script:InforcerSession = $null; $script:InforcerTenantListCache = $null }
}

Describe 'New-InforcerUser' {
    It 'POSTs the required fields, defaults and the password, and returns the new id' {
        Set-UwSession
        Set-UwRoute { param($Uri, $Method, $Body) New-UwResponse ('{"id":"' + $script:Uid + '"}') 201 }
        $u = New-InforcerUser -TenantId $script:Tid -DisplayName 'Jo Bloggs' -UserPrincipalName 'jo.bloggs@contoso.com' -Password $script:Pw -Department 'Sales'
        $global:UwCalls.Count | Should -Be 1
        $global:UwCalls[0].Method | Should -Be 'POST'
        $global:UwCalls[0].Uri | Should -Be "https://api.example.invalid/v1/tenants/$($script:Tid)/users"
        $b = $global:UwCalls[0].Body | ConvertFrom-Json
        $b.displayName | Should -Be 'Jo Bloggs'
        $b.userPrincipalName | Should -Be 'jo.bloggs@contoso.com'
        $b.mailNickname | Should -Be 'jo.bloggs'
        $b.accountEnabled | Should -BeTrue
        $b.department | Should -Be 'Sales'
        $b.passwordProfile.password | Should -Be 'Example-Passw0rd!'
        $b.passwordProfile.forceChangePasswordNextSignIn | Should -BeTrue
        $b.PSObject.Properties.Name | Should -Not -Contain 'outputType'
        $b.PSObject.Properties.Name | Should -Not -Contain 'tenantId'
        $u.id | Should -Be $script:Uid
        $u.TenantId | Should -Be $script:Tid
        $u.userPrincipalName | Should -Be 'jo.bloggs@contoso.com'
        $u.PSObject.TypeNames[0] | Should -Be 'InforcerCommunity.CreatedUser'
    }

    It 'sends -AccountEnabled $false, -MailNickname and -ForceChangePasswordNextSignIn $false as given' {
        Set-UwSession
        Set-UwRoute { param($Uri, $Method, $Body) New-UwResponse '{"id":"x"}' 201 }
        $null = New-InforcerUser -TenantId $script:Tid -DisplayName 'Jo' -UserPrincipalName 'jo@contoso.com' -Password $script:Pw -AccountEnabled $false -MailNickname 'jb' -ForceChangePasswordNextSignIn $false -BusinessPhones '+44 20 0000 0000'
        $b = $global:UwCalls[0].Body | ConvertFrom-Json
        $b.accountEnabled | Should -BeFalse
        $b.mailNickname | Should -Be 'jb'
        $b.passwordProfile.forceChangePasswordNextSignIn | Should -BeFalse
        @($b.businessPhones).Count | Should -Be 1
        $global:UwCalls[0].Body.Contains('"businessPhones":["+44 20 0000 0000"]') | Should -BeTrue
    }

    It 'keeps the password out of verbose output' {
        Set-UwSession
        Set-UwRoute { param($Uri, $Method, $Body) New-UwResponse '{"id":"x"}' 201 }
        $verbose = New-InforcerUser -TenantId $script:Tid -DisplayName 'Jo' -UserPrincipalName 'jo@contoso.com' -Password $script:Pw -Verbose 4>&1 | Where-Object { $_ -is [System.Management.Automation.VerboseRecord] }
        ($verbose | Out-String) | Should -Not -BeLike '*Example-Passw0rd!*'
    }

    It 'makes no request with -WhatIf' {
        Set-UwSession
        Set-UwRoute { param($Uri, $Method, $Body) New-UwResponse '{"id":"x"}' 201 }
        New-InforcerUser -TenantId $script:Tid -DisplayName 'Jo' -UserPrincipalName 'jo@contoso.com' -Password $script:Pw -WhatIf
        $global:UwCalls.Count | Should -Be 0
    }

    It 'refuses an API-key (beta) login with RequiresApiClient and makes no request' {
        Set-UwSession -Beta
        Set-UwRoute { param($Uri, $Method, $Body) New-UwResponse '{"id":"x"}' 201 }
        New-InforcerUser -TenantId 5 -DisplayName 'Jo' -UserPrincipalName 'jo@contoso.com' -Password $script:Pw -ErrorAction SilentlyContinue -ErrorVariable e
        $e[0].FullyQualifiedErrorId | Should -BeLike 'RequiresApiClient*'
        $global:UwCalls.Count | Should -Be 0
    }

    It 'surfaces a 409 conflict with the API reason' {
        Set-UwSession
        Set-UwRoute { param($Uri, $Method, $Body) New-UwResponse '{"title":"Conflict","status":409,"detail":"A user with this userPrincipalName already exists"}' 409 }
        { New-InforcerUser -TenantId $script:Tid -DisplayName 'Jo' -UserPrincipalName 'jo@contoso.com' -Password $script:Pw -ErrorAction Stop } | Should -Throw '*HTTP 409*already exists*'
    }

    It 'returns one JSON array for piped tenants with -OutputType JsonObject' {
        Set-UwSession
        Set-UwRoute { param($Uri, $Method, $Body) New-UwResponse '{"id":"x"}' 201 }
        $json = @([pscustomobject]@{ MsTenantId = $script:Tid }, [pscustomobject]@{ MsTenantId = '00000000-0000-0000-0000-000000000002' }) |
            New-InforcerUser -DisplayName 'Jo' -UserPrincipalName 'jo@contoso.com' -Password $script:Pw -OutputType JsonObject
        @($json).Count | Should -Be 1
        @($json | ConvertFrom-Json).Count | Should -Be 2
    }
}

Describe 'Set-InforcerUser' {
    It 'PATCHes only the passed fields, and a 204 returns nothing without an error' {
        Set-UwSession
        Set-UwRoute { param($Uri, $Method, $Body) New-UwResponse '' 204 }
        $out = Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -Department 'Sales' -AccountEnabled $false -ErrorVariable e
        $out | Should -BeNullOrEmpty
        $e | Should -BeNullOrEmpty
        $global:UwCalls[0].Method | Should -Be 'PATCH'
        $global:UwCalls[0].Uri | Should -Be "https://api.example.invalid/v1/tenants/$($script:Tid)/users/$($script:Uid)"
        $b = $global:UwCalls[0].Body | ConvertFrom-Json
        @($b.PSObject.Properties.Name) | Sort-Object | Should -Be @('accountEnabled', 'department')
        $b.accountEnabled | Should -BeFalse
    }

    It "sends null for '' and empty arrays, so the fields are cleared" {
        Set-UwSession
        Set-UwRoute { param($Uri, $Method, $Body) New-UwResponse '' 204 }
        Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -JobTitle '' -ManagerId $null -OtherMails @()
        $global:UwCalls[0].Body | Should -Be '{"jobTitle":null,"otherMails":null,"managerId":null}'
    }

    It 'refuses to clear a field the API cannot clear' {
        { Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -DisplayName '' } | Should -Throw
    }

    It 'refuses a call without any change and makes no request' {
        Set-UwSession
        Set-UwRoute { param($Uri, $Method, $Body) New-UwResponse '' 204 }
        Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -ErrorAction SilentlyContinue -ErrorVariable e
        $e[0].FullyQualifiedErrorId | Should -BeLike 'NoChangeSpecified*'
        $global:UwCalls.Count | Should -Be 0
    }

    It 'takes users from the pipeline by id' {
        Set-UwSession
        Set-UwRoute { param($Uri, $Method, $Body) New-UwResponse '' 204 }
        @([pscustomobject]@{ id = 'u1' }, [pscustomobject]@{ id = 'u2' }) | Set-InforcerUser -TenantId $script:Tid -Department 'Sales'
        $global:UwCalls.Count | Should -Be 2
        $global:UwCalls[1].Uri | Should -BeLike '*/users/u2'
    }

    It 'refuses an API-key (beta) login with RequiresApiClient' {
        Set-UwSession -Beta
        Set-UwRoute { param($Uri, $Method, $Body) New-UwResponse '' 204 }
        Set-InforcerUser -TenantId 5 -UserId $script:Uid -Department 'Sales' -ErrorAction SilentlyContinue -ErrorVariable e
        $e[0].FullyQualifiedErrorId | Should -BeLike 'RequiresApiClient*'
        $global:UwCalls.Count | Should -Be 0
    }

    It 'lists each step when the update was only partly applied (502)' {
        Set-UwSession
        Set-UwRoute {
            param($Uri, $Method, $Body)
            New-UwResponse '{"title":"Bad gateway","status":502,"detail":"The manager could not be changed","results":[{"step":"profile","status":"succeeded"},{"step":"manager","status":"failed","title":"Manager not found","statusCode":404}]}' 502
        }
        { Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -Department 'Sales' -ManagerId $script:Tid -ErrorAction Stop } |
            Should -Throw '*HTTP 502*Steps: profile: succeeded; manager: failed (Manager not found)*'
    }
}
