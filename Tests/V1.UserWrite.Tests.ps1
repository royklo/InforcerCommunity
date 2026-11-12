# V1.UserWrite.Tests.ps1
# New-InforcerUser, Set-InforcerUser and Get-InforcerUser -IncludeAuthenticationMethods (v1 only). Fixtures are anonymised; no network calls.

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

    It 'leaves no readable password in the retained request after a transport failure' {
        Set-UwSession
        $global:UwSent = $null
        Mock -ModuleName InforcerCommunity Invoke-InforcerHttpRequest {
            # What a failed Invoke-RestMethod leaves: the disposed request as the ErrorRecord's TargetObject.
            $msg = [System.Net.Http.HttpRequestMessage]::new('POST', [string]$Request.Uri)
            $msg.Content = [System.Net.Http.StringContent]::new($Request.Body)
            $msg.Dispose()
            $global:UwSent = $msg
            throw [System.Management.Automation.ErrorRecord]::new([System.Net.Http.HttpRequestException]::new('No such host is known.'), 'WebCmdletWebResponseException', 'ConnectionError', $msg)
        }
        New-InforcerUser -TenantId $script:Tid -DisplayName 'Jo' -UserPrincipalName 'jo@contoso.com' -Password $script:Pw -ErrorAction SilentlyContinue -ErrorVariable e
        ($e | Out-String) | Should -Not -BeLike '*Example-Passw0rd!*'
        $field = [System.Net.Http.ByteArrayContent].GetField('_content', [System.Reflection.BindingFlags]'NonPublic, Instance')
        $field | Should -Not -BeNullOrEmpty -Because 'the cleanup relies on this field; a runtime without it needs another approach'
        [System.Text.Encoding]::UTF8.GetString($field.GetValue($global:UwSent.Content)) | Should -Not -BeLike '*Example-Passw0rd!*'
        Remove-Variable -Name UwSent -Scope Global
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
    It 'resets the password and signs the user out, after the profile update, in that order' {
        Set-UwSession
        Set-UwRoute { param($Uri, $Method, $Body) New-UwResponse '' 204 }
        $out = Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -AccountEnabled $false -Password $script:Pw -RevokeSessions -ErrorVariable e
        $out | Should -BeNullOrEmpty
        $e | Should -BeNullOrEmpty
        @($global:UwCalls | ForEach-Object { "$($_.Method) $($_.Uri -replace '^.*/users/[^/]+', '')" }) |
            Should -Be @('PATCH ', 'POST /password', 'POST /revokeSessions')
        $global:UwCalls[1].Body | Should -Be '{"password":"Example-Passw0rd!","forceChangePasswordNextSignIn":true}'
        $global:UwCalls[2].Body | Should -BeNullOrEmpty
    }

    It 'sends -ForceChangePasswordNextSignIn $false and no PATCH when only the password changes' {
        Set-UwSession
        Set-UwRoute { param($Uri, $Method, $Body) New-UwResponse '' 204 }
        Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -Password $script:Pw -ForceChangePasswordNextSignIn $false
        $global:UwCalls.Count | Should -Be 1
        $global:UwCalls[0].Uri | Should -Be "https://api.example.invalid/v1/tenants/$($script:Tid)/users/$($script:Uid)/password"
        ($global:UwCalls[0].Body | ConvertFrom-Json).forceChangePasswordNextSignIn | Should -BeFalse
    }

    It 'refuses -ForceChangePasswordNextSignIn without -Password and makes no request' {
        Set-UwSession
        Set-UwRoute { param($Uri, $Method, $Body) New-UwResponse '' 204 }
        Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -ForceChangePasswordNextSignIn $false -ErrorAction SilentlyContinue -ErrorVariable e
        $e[0].FullyQualifiedErrorId | Should -BeLike 'PasswordRequired*'
        $global:UwCalls.Count | Should -Be 0
    }

    It 'keeps the new password out of verbose output and errors' {
        Set-UwSession
        Set-UwRoute { param($Uri, $Method, $Body) New-UwResponse '{"title":"The request is invalid","status":400,"errors":{"password":["The password does not meet the tenant policy"]}}' 400 }
        $all = Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -Password $script:Pw -Verbose -ErrorAction SilentlyContinue -ErrorVariable e 4>&1
        ($all | Out-String) + ($e | Out-String) | Should -Not -BeLike '*Example-Passw0rd!*'
        @($e).Count | Should -Be 1
        $e[0].Exception.Message | Should -BeLike '*HTTP 400*'
    }

    It 'stops at the failing step and says what was already done and what was skipped' {
        Set-UwSession
        Set-UwRoute {
            param($Uri, $Method, $Body)
            if ($Uri -like '*/password') { return New-UwResponse '{"title":"The request is invalid","status":400,"errors":{"password":["The password does not meet the tenant policy"]}}' 400 }
            New-UwResponse '' 204
        }
        Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -Department 'Sales' -Password $script:Pw -RevokeSessions -ErrorAction SilentlyContinue -ErrorVariable e
        $global:UwCalls.Count | Should -Be 2
        $e[-1].FullyQualifiedErrorId | Should -BeLike 'UserUpdatePartlyApplied*'
        $e[-1].Exception.Message | Should -BeLike '*Could not reset password*HTTP 400*Already done: update department.*Not done: sign out of every session.*'
    }

    It 'makes no request with -WhatIf for a password reset or sign-out' {
        Set-UwSession
        Set-UwRoute { param($Uri, $Method, $Body) New-UwResponse '' 204 }
        Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -Password $script:Pw -RevokeSessions -WhatIf
        $global:UwCalls.Count | Should -Be 0
    }

    It 'removes sign-in methods after the password reset and before the sign-out, one DELETE per id' {
        Set-UwSession
        Set-UwRoute { param($Uri, $Method, $Body) New-UwResponse '' 204 }
        Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -Password $script:Pw -RemoveAuthenticationMethod 'm1', 'pass/key+1', 'm1' -RevokeSessions -ErrorVariable e
        $e | Should -BeNullOrEmpty
        @($global:UwCalls | ForEach-Object { "$($_.Method) $($_.Uri -replace '^.*/users/[^/]+', '')" }) |
            Should -Be @('POST /password', 'DELETE /authenticationMethods/m1', 'DELETE /authenticationMethods/pass%2Fkey%2B1', 'POST /revokeSessions')
    }

    It 'stops at a refused sign-in method and names the methods not removed' {
        Set-UwSession
        Set-UwRoute {
            param($Uri, $Method, $Body)
            if ($Uri -like '*/m1') { return New-UwResponse '{"title":"The request is invalid","status":400,"detail":"The default method cannot be deleted while another phone remains"}' 400 }
            New-UwResponse '' 204
        }
        Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -RemoveAuthenticationMethod 'm1', 'm2' -RevokeSessions -ErrorAction SilentlyContinue -ErrorVariable e
        $global:UwCalls.Count | Should -Be 1
        $e[-1].Exception.Message | Should -BeLike '*Could not remove authentication method m1*HTTP 400*default method*Not done: remove authentication method m2; sign out of every session.*'
    }

    It 'resets MFA with one DELETE after the password reset and before the sign-out' {
        Set-UwSession
        Set-UwRoute { param($Uri, $Method, $Body) New-UwResponse '' 204 }
        Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -Password $script:Pw -ResetMfa -RevokeSessions -ErrorVariable e
        $e | Should -BeNullOrEmpty
        @($global:UwCalls | ForEach-Object { "$($_.Method) $($_.Uri -replace '^.*/users/[^/]+', '')" }) |
            Should -Be @('POST /password', 'DELETE /mfa', 'POST /revokeSessions')
    }

    It 'names each method and its outcome when Microsoft Entra refuses one during an MFA reset' {
        Set-UwSession
        Set-UwRoute { param($Uri, $Method, $Body) New-UwResponse '{"title":"Not every method was deleted","status":400,"results":[{"step":"phone","id":"m1","status":"succeeded"},{"step":"fido2","id":"pk/1","status":"failed","title":"Method is in use"}]}' 400 }
        { Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -ResetMfa -ErrorAction Stop } |
            Should -Throw '*HTTP 400*Steps: phone m1: succeeded; fido2 pk/1: failed (Method is in use)*'
    }

    It 'surfaces a 404 from a sign-out alone with the original error' {
        Set-UwSession
        Set-UwRoute { param($Uri, $Method, $Body) New-UwResponse '{"title":"User not found","status":404}' 404 }
        { Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -RevokeSessions -ErrorAction Stop } | Should -Throw '*HTTP 404*User not found*'
    }
}

Describe 'Get-InforcerUser -IncludeAuthenticationMethods' {
    It 'adds the authentication methods to the user with one extra request' {
        Set-UwSession
        Set-UwRoute {
            param($Uri, $Method, $Body)
            if ($Uri -like '*/authenticationMethods') {
                return New-UwResponse '{"authenticationMethods":[{"id":"00000000-0000-0000-0000-0000000000a1","type":"password","displayName":null,"createdDateTime":null,"deletable":false,"phoneNumber":null,"phoneType":null,"emailAddress":null},{"id":"00000000-0000-0000-0000-0000000000a2","type":"phone","displayName":null,"createdDateTime":null,"deletable":true,"phoneNumber":"+44 7700 900000","phoneType":"mobile","emailAddress":null}]}'
            }
            New-UwResponse ('{"id":"' + $script:Uid + '","displayName":"Jo Bloggs"}')
        }
        $u = Get-InforcerUser -TenantId $script:Tid -UserId $script:Uid -IncludeAuthenticationMethods
        $global:UwCalls.Count | Should -Be 2
        $global:UwCalls[1].Uri | Should -Be "https://api.example.invalid/v1/tenants/$($script:Tid)/users/$($script:Uid)/authenticationMethods"
        @($u.authenticationMethods).Count | Should -Be 2
        $u.authenticationMethods[1].phoneType | Should -Be 'mobile'
    }

    It 'keeps a single method as an array in JSON output' {
        Set-UwSession
        Set-UwRoute {
            param($Uri, $Method, $Body)
            if ($Uri -like '*/authenticationMethods') { return New-UwResponse '{"authenticationMethods":[{"id":"m1","type":"password"}]}' }
            New-UwResponse '{"id":"u1"}'
        }
        $json = Get-InforcerUser -TenantId $script:Tid -UserId 'u1' -IncludeAuthenticationMethods -OutputType JsonObject
        $json | Should -Match '"authenticationMethods":\s*\['
    }

    It 'makes no extra request without the switch' {
        Set-UwSession
        Set-UwRoute { param($Uri, $Method, $Body) New-UwResponse '{"id":"u1"}' }
        $null = Get-InforcerUser -TenantId $script:Tid -UserId 'u1'
        $global:UwCalls.Count | Should -Be 1
    }

    It 'refuses an API-key (beta) login with RequiresApiClient and makes no request' {
        Set-UwSession -Beta
        Set-UwRoute { param($Uri, $Method, $Body) New-UwResponse '{"data":{"id":"u1"},"success":true}' }
        Get-InforcerUser -TenantId 5 -UserId 'u1' -IncludeAuthenticationMethods -ErrorAction SilentlyContinue -ErrorVariable e
        $e[0].FullyQualifiedErrorId | Should -BeLike 'RequiresApiClient*'
        $global:UwCalls.Count | Should -Be 0
    }
}
