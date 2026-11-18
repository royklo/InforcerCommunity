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
    Remove-Variable -Name UwCalls, UwRoute, UwPolls, UwClock -Scope Global -ErrorAction SilentlyContinue
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

    It 'changes licences after the profile and before the password, in one request' {
        Set-UwSession
        Set-UwRoute { param($Uri, $Method, $Body) New-UwResponse '' 204 }
        $b1 = '00000000-0000-0000-0000-0000000000b1'; $b2 = '00000000-0000-0000-0000-0000000000b2'
        Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -UsageLocation 'GB' -AddLicense $b1, $b1 -RemoveLicense $b2 -Password $script:Pw -ErrorVariable e
        $e | Should -BeNullOrEmpty
        @($global:UwCalls | ForEach-Object { "$($_.Method) $($_.Uri -replace '^.*/users/[^/]+', '')" }) |
            Should -Be @('PATCH ', 'POST /assignLicenses', 'POST /password')
        $global:UwCalls[1].Body | Should -Be ('{"addSkuIds":["' + $b1 + '"],"removeSkuIds":["' + $b2 + '"]}')
    }

    It 'returns the Temporary Access Pass after the MFA reset, even when the sign-out then fails' {
        Set-UwSession
        Set-UwRoute {
            param($Uri, $Method, $Body)
            if ($Uri -like '*/temporaryAccessPasses') { return New-UwResponse '{"id":"tap-1","temporaryAccessPass":"Example-Tap1","startDateTime":"2026-11-15T10:00:00+00:00","lifetimeInMinutes":60,"usableOnce":true}' 201 }
            if ($Uri -like '*/revokeSessions') { return New-UwResponse '{"title":"Bad gateway","status":502}' 502 }
            New-UwResponse '' 204
        }
        $out = Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -ResetMfa -TemporaryAccessPass -TemporaryAccessPassLifetime 60 -TemporaryAccessPassUsableOnce $true -RevokeSessions -ErrorAction SilentlyContinue -ErrorVariable e
        @($global:UwCalls | ForEach-Object { "$($_.Method) $($_.Uri -replace '^.*/users/[^/]+', '')" }) |
            Should -Be @('DELETE /mfa', 'POST /authenticationMethods/temporaryAccessPasses', 'POST /revokeSessions')
        $global:UwCalls[1].Body | Should -Be '{"lifetimeInMinutes":60,"usableOnce":true}'
        $out.temporaryAccessPass | Should -Be 'Example-Tap1'
        $out.userId | Should -Be $script:Uid
        $e[-1].Exception.Message | Should -BeLike '*Could not sign out of every session*Already done: reset MFA; create Temporary Access Pass.*'
    }

    It 'sends an empty body for a Temporary Access Pass without options' {
        Set-UwSession
        Set-UwRoute { param($Uri, $Method, $Body) New-UwResponse '{"id":"tap-1","temporaryAccessPass":"Example-Tap1"}' 201 }
        $out = Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -TemporaryAccessPass
        $global:UwCalls[0].Body | Should -Be '{}'
        $out.id | Should -Be 'tap-1'
    }

    It 'refuses Temporary Access Pass options without -TemporaryAccessPass, without a request' {
        Set-UwSession
        Set-UwRoute { param($Uri, $Method, $Body) New-UwResponse '' 204 }
        Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -RevokeSessions -TemporaryAccessPassLifetime 60 -ErrorAction SilentlyContinue -ErrorVariable e
        $e[-1].FullyQualifiedErrorId | Should -BeLike 'TemporaryAccessPassRequired*'
        $global:UwCalls.Count | Should -Be 0
    }

    It 'hides the mailbox before removing licences and waits until Exchange Online reports it done' {
        Set-UwSession
        Mock -ModuleName InforcerCommunity Start-Sleep {}
        $global:UwPolls = 0
        Set-UwRoute {
            param($Uri, $Method, $Body)
            if ($Uri -like '*/addressListVisibility') { return New-UwResponse '{"actionId":"00000000-0000-0000-0000-0000000000a1"}' 202 }
            if ($Uri -like '*/mailbox/actions/*') {
                $global:UwPolls++
                $status = if ($global:UwPolls -lt 2) { 'running' } else { 'succeeded' }
                return New-UwResponse ('{"actionId":"00000000-0000-0000-0000-0000000000a1","action":"setAddressListVisibility","status":"' + $status + '","queuedBehind":null,"requestedAt":"2026-11-16T10:00:00Z","completedAt":null,"error":null}')
            }
            New-UwResponse '' 204
        }
        $b1 = '00000000-0000-0000-0000-0000000000b1'
        $out = Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -RemoveLicense $b1 -HiddenFromAddressLists $true -RevokeSessions -ErrorVariable e -WarningVariable w
        $e | Should -BeNullOrEmpty
        $w | Should -BeNullOrEmpty
        $out | Should -BeNullOrEmpty
        @($global:UwCalls | ForEach-Object { "$($_.Method) $($_.Uri -replace '^.*/users/[^/]+', '')" }) |
            Should -Be @('PATCH /mailbox/addressListVisibility', 'GET /mailbox/actions/00000000-0000-0000-0000-0000000000a1', 'GET /mailbox/actions/00000000-0000-0000-0000-0000000000a1', 'POST /assignLicenses', 'POST /revokeSessions')
        $global:UwCalls[0].Body | Should -Be '{"hidden":true}'
    }

    It 'sends hidden false to show the mailbox again' {
        Set-UwSession
        Mock -ModuleName InforcerCommunity Start-Sleep {}
        Set-UwRoute {
            param($Uri, $Method, $Body)
            if ($Method -eq 'PATCH') { return New-UwResponse '{"actionId":"00000000-0000-0000-0000-0000000000a1"}' 202 }
            New-UwResponse '{"actionId":"00000000-0000-0000-0000-0000000000a1","status":"succeeded","error":null}'
        }
        Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -HiddenFromAddressLists $false -ErrorVariable e
        $e | Should -BeNullOrEmpty
        $global:UwCalls[0].Body | Should -Be '{"hidden":false}'
    }

    It 'stops the later steps when Exchange Online fails the address list change, with its reason' {
        Set-UwSession
        Mock -ModuleName InforcerCommunity Start-Sleep {}
        Set-UwRoute {
            param($Uri, $Method, $Body)
            if ($Method -eq 'PATCH' -and $Uri -like '*/addressListVisibility') { return New-UwResponse '{"actionId":"00000000-0000-0000-0000-0000000000a1"}' 202 }
            if ($Uri -like '*/mailbox/actions/*') { return New-UwResponse '{"actionId":"00000000-0000-0000-0000-0000000000a1","status":"failed","error":{"code":"WriteNotApplied","message":"The mailbox was not found"}}' }
            New-UwResponse '' 204
        }
        Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -AccountEnabled $false -HiddenFromAddressLists $true -RevokeSessions -ErrorAction SilentlyContinue -ErrorVariable e
        $e[-1].FullyQualifiedErrorId | Should -BeLike 'UserUpdatePartlyApplied*'
        $e[-1].Exception.Message | Should -BeLike '*Could not hide mailbox from address lists*The mailbox was not found (WriteNotApplied)*Already done: update accountEnabled.*Not done: sign out of every session.*'
        @($global:UwCalls | Where-Object Uri -like '*/revokeSessions').Count | Should -Be 0
    }

    It 'gives the failure itself when the address list change is the only step' {
        Set-UwSession
        Mock -ModuleName InforcerCommunity Start-Sleep {}
        Set-UwRoute {
            param($Uri, $Method, $Body)
            if ($Method -eq 'PATCH') { return New-UwResponse '{"actionId":"00000000-0000-0000-0000-0000000000a1"}' 202 }
            New-UwResponse '{"actionId":"00000000-0000-0000-0000-0000000000a1","status":"failed","error":{"code":"NotStarted","message":"Exchange Online could not be reached"}}'
        }
        { Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -HiddenFromAddressLists $true -ErrorAction Stop } |
            Should -Throw '*Exchange Online could not be reached (NotStarted)*'
    }

    It 'warns and carries on when the change is still queued at the deadline' {
        Set-UwSession
        Mock -ModuleName InforcerCommunity Start-Sleep {}
        $global:UwClock = [datetime]'2026-11-16T10:00:00'
        Mock -ModuleName InforcerCommunity Get-Date { $global:UwClock; $global:UwClock = $global:UwClock.AddMinutes(10) }
        Set-UwRoute {
            param($Uri, $Method, $Body)
            if ($Method -eq 'PATCH') { return New-UwResponse '{"actionId":"00000000-0000-0000-0000-0000000000a1"}' 202 }
            New-UwResponse '' 204
        }
        Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -HiddenFromAddressLists $true -RevokeSessions -ErrorVariable e -WarningVariable w -WarningAction SilentlyContinue
        $e | Should -BeNullOrEmpty
        "$w" | Should -BeLike '*still queued*action id 00000000-0000-0000-0000-0000000000a1*'
        @($global:UwCalls | ForEach-Object { $_.Method }) | Should -Be @('PATCH', 'POST')
    }

    It 'offboards in order: profile, mailbox changes one at a time, then the licence removal and the sign-out' {
        Set-UwSession
        Mock -ModuleName InforcerCommunity Start-Sleep {}
        Set-UwRoute {
            param($Uri, $Method, $Body)
            if ($Uri -like '*/mailbox/actions/*') { return New-UwResponse '{"actionId":"00000000-0000-0000-0000-0000000000a1","status":"succeeded","error":null}' }
            if ($Uri -like '*/mailbox/*') { return New-UwResponse '{"actionId":"00000000-0000-0000-0000-0000000000a1"}' 202 }
            New-UwResponse '' 204
        }
        $reply = [ordered]@{ status = 'alwaysEnabled'; externalAudience = 'none'; internalReplyMessage = 'Jo has left.' }
        $manager = '00000000-0000-0000-0000-000000000006'
        Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -AccountEnabled $false -MailboxType Shared -AutoReply $reply -GrantMailboxPermission @{ permission = 'fullAccess'; trusteeId = $manager; automapping = $true } -RemoveLicense '00000000-0000-0000-0000-0000000000b1' -RevokeSessions -ErrorVariable e
        $e | Should -BeNullOrEmpty
        @($global:UwCalls | Where-Object Uri -notlike '*/mailbox/actions/*' | ForEach-Object { "$($_.Method) $($_.Uri -replace '^.*/users/[^/]+', '')" }) |
            Should -Be @('PATCH ', 'PATCH /mailbox/type', 'PATCH /mailbox/autoReply', 'POST /mailbox/permissions', 'POST /assignLicenses', 'POST /revokeSessions')
        @($global:UwCalls | Where-Object Uri -like '*/mailbox/actions/*').Count | Should -Be 3
        $writes = @($global:UwCalls | Where-Object Uri -match '/mailbox/(type|autoReply|permissions)$')
        $writes[0].Body | Should -Be '{"type":"shared"}'
        $writes[1].Body | Should -Be '{"status":"alwaysEnabled","externalAudience":"none","internalReplyMessage":"Jo has left."}'
        $writes[2].Body | Should -Be ('{"trusteeId":"' + $manager + '","permission":"fullAccess","automapping":true}')
    }

    It 'keeps -AddLicense before the mailbox changes, so a new mailbox gets its licence first' {
        Set-UwSession
        Mock -ModuleName InforcerCommunity Start-Sleep {}
        Set-UwRoute {
            param($Uri, $Method, $Body)
            if ($Uri -like '*/mailbox/actions/*') { return New-UwResponse '{"status":"succeeded","error":null}' }
            if ($Uri -like '*/mailbox/*') { return New-UwResponse '{"actionId":"00000000-0000-0000-0000-0000000000a1"}' 202 }
            New-UwResponse '' 204
        }
        Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -AddLicense '00000000-0000-0000-0000-0000000000b1' -HiddenFromAddressLists $true -ErrorVariable e
        $e | Should -BeNullOrEmpty
        @($global:UwCalls | Where-Object Uri -notlike '*/mailbox/actions/*' | ForEach-Object { "$($_.Method) $($_.Uri -replace '^.*/users/[^/]+', '')" }) |
            Should -Be @('POST /assignLicenses', 'PATCH /mailbox/addressListVisibility')
    }

    It 'sends a read automatic reply back without nulls and simplified, and only status when it is disabled' {
        Set-UwSession
        Mock -ModuleName InforcerCommunity Start-Sleep {}
        Set-UwRoute {
            param($Uri, $Method, $Body)
            if ($Uri -like '*/mailbox/actions/*') { return New-UwResponse '{"status":"succeeded","error":null}' }
            New-UwResponse '{"actionId":"00000000-0000-0000-0000-0000000000a1"}' 202
        }
        $read = '{"status":"scheduled","externalAudience":"all","internalReplyMessage":"Away","externalReplyMessage":"Away","scheduledStartDateTime":"2026-12-01T09:00:00+01:00","scheduledEndDateTime":null,"simplified":true}' | ConvertFrom-Json
        Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -AutoReply $read -ErrorVariable e
        $e | Should -BeNullOrEmpty
        $global:UwCalls[0].Body | Should -Be '{"status":"scheduled","externalAudience":"all","internalReplyMessage":"Away","externalReplyMessage":"Away","scheduledStartDateTime":"2026-12-01T08:00:00Z"}'
        $read.status = 'disabled'
        Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -AutoReply $read
        @($global:UwCalls | Where-Object Method -eq 'PATCH')[-1].Body | Should -Be '{"status":"disabled"}'
    }

    It 'forwards to a user id or to an address, and refuses conflicting forwarding options without a request' {
        Set-UwSession
        Mock -ModuleName InforcerCommunity Start-Sleep {}
        Set-UwRoute {
            param($Uri, $Method, $Body)
            if ($Uri -like '*/mailbox/actions/*') { return New-UwResponse '{"status":"succeeded","error":null}' }
            New-UwResponse '{"actionId":"00000000-0000-0000-0000-0000000000a1"}' 202
        }
        Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -ForwardTo '00000000-0000-0000-0000-000000000006' -KeepForwardedCopy
        $global:UwCalls[0].Body | Should -Be '{"recipientUserId":"00000000-0000-0000-0000-000000000006","keepCopy":true}'
        Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -ForwardTo 'sales@contoso.com'
        @($global:UwCalls | Where-Object Method -eq 'PATCH')[-1].Body | Should -Be '{"smtpAddress":"sales@contoso.com","keepCopy":false}'
        Set-UwRoute { param($Uri, $Method, $Body) New-UwResponse '' 204 }
        Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -ForwardTo 'sales@contoso.com' -RemoveForwarding -ErrorAction SilentlyContinue -ErrorVariable e1
        Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -KeepForwardedCopy -RevokeSessions -ErrorAction SilentlyContinue -ErrorVariable e2
        Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -GrantMailboxPermission @{ permission = 'sendAs' } -ErrorAction SilentlyContinue -ErrorVariable e3
        $e1[-1].FullyQualifiedErrorId | Should -BeLike 'ConflictingForwarding*'
        $e2[-1].FullyQualifiedErrorId | Should -BeLike 'ForwardToRequired*'
        $e3[-1].FullyQualifiedErrorId | Should -BeLike 'InvalidMailboxPermission*'
        $global:UwCalls.Count | Should -Be 0
    }

    It 'adds addresses before making one primary and removing the old one, and builds the remove paths' {
        Set-UwSession
        Mock -ModuleName InforcerCommunity Start-Sleep {}
        Set-UwRoute {
            param($Uri, $Method, $Body)
            if ($Uri -like '*/mailbox/actions/*') { return New-UwResponse '{"status":"succeeded","error":null}' }
            New-UwResponse '{"actionId":"00000000-0000-0000-0000-0000000000a1"}' 202
        }
        $g = '00000000-0000-0000-0000-0000000000c1'
        Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -RemoveEmailAddress 'jo@contoso.com' -PrimaryEmailAddress 'jo.bloggs@contoso.com' -AddEmailAddress 'jb@contoso.com' -RemoveForwarding -RemoveMailboxPermission ([pscustomobject]@{ permission = 'sendAs'; trusteeId = '00000000-0000-0000-0000-000000000006'; displayName = 'Sam' }) -AddMailGroup $g -RemoveMailGroup $g -RemoveInboxRule '1234' -RemoveAllInboxRules -ErrorVariable e
        $e | Should -BeNullOrEmpty
        @($global:UwCalls | Where-Object Uri -notlike '*/mailbox/actions/*' | ForEach-Object { "$($_.Method) $($_.Uri -replace '^.*/users/[^/]+/mailbox', '')" }) |
            Should -Be @('POST /emailAddresses', 'POST /emailAddresses', 'DELETE /emailAddresses/jo%40contoso.com', 'DELETE /forwarding',
                'DELETE /permissions/sendAs/00000000-0000-0000-0000-000000000006', "POST /mailGroups", "DELETE /mailGroups/$g", 'DELETE /inboxRules/1234', 'DELETE /inboxRules?all=true')
        $global:UwCalls[0].Body | Should -Be '{"address":"jb@contoso.com"}'
        $global:UwCalls[2].Body | Should -Be '{"address":"jo.bloggs@contoso.com","primary":true}'
        @($global:UwCalls | Where-Object { $_.Uri -like '*/mailGroups' })[0].Body | Should -Be ('{"groupId":"' + $g + '"}')
    }

    It 'shares and unshares the calendar and sets mail apps in one change with the API spelling, after the inbox rules' {
        Set-UwSession
        Mock -ModuleName InforcerCommunity Start-Sleep {}
        Set-UwRoute {
            param($Uri, $Method, $Body)
            if ($Uri -like '*/mailbox/actions/*') { return New-UwResponse '{"status":"succeeded","error":null}' }
            New-UwResponse '{"actionId":"00000000-0000-0000-0000-0000000000a1"}' 202
        }
        $t = '00000000-0000-0000-0000-000000000006'
        Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -BlockMailApp imap, POP -AllowMailApp outlookweb -RemoveAllInboxRules -RemoveCalendarAccess $t -GrantCalendarAccess @{ trusteeId = $t; role = 'Editor' } -ErrorVariable e
        $e | Should -BeNullOrEmpty
        $writes = @($global:UwCalls | Where-Object Uri -notlike '*/mailbox/actions/*')
        @($writes | ForEach-Object { "$($_.Method) $($_.Uri -replace '^.*/users/[^/]+/mailbox', '')" }) |
            Should -Be @('POST /calendarAccess', "DELETE /calendarAccess/$t", 'DELETE /inboxRules?all=true', 'PATCH /mailApps')
        $writes[0].Body | Should -Be ('{"trusteeId":"' + $t + '","role":"editor"}')
        $writes[3].Body | Should -Be '{"outlookWeb":true,"imap":false,"pop":false}'
    }

    It 'refuses a calendar share without a valid role and an app both allowed and blocked, without a request' {
        Set-UwSession
        Set-UwRoute { param($Uri, $Method, $Body) New-UwResponse '' 204 }
        Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -GrantCalendarAccess @{ trusteeId = '00000000-0000-0000-0000-000000000006'; role = 'owner' } -ErrorAction SilentlyContinue -ErrorVariable e1
        Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -AllowMailApp Pop -BlockMailApp pop -ErrorAction SilentlyContinue -ErrorVariable e2
        $e1[-1].FullyQualifiedErrorId | Should -BeLike 'InvalidCalendarAccess*'
        $e2[-1].FullyQualifiedErrorId | Should -BeLike 'ConflictingMailApp*'
        $global:UwCalls.Count | Should -Be 0
    }

    It 'sends userType on create and update' {
        Set-UwSession
        Set-UwRoute { param($Uri, $Method, $Body) New-UwResponse ('{"id":"' + $script:Uid + '"}') 201 }
        $null = New-InforcerUser -TenantId $script:Tid -DisplayName 'Jo' -UserPrincipalName 'jo@contoso.com' -Password $script:Pw -UserType Guest
        $global:UwCalls[0].Body | Should -Match '"userType":"Guest"'
        Set-UwRoute { param($Uri, $Method, $Body) New-UwResponse '' 204 }
        Set-InforcerUser -TenantId $script:Tid -UserId $script:Uid -UserType Member
        $global:UwCalls[0].Body | Should -Be '{"userType":"Member"}'
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

Describe 'Get-InforcerUser -IncludeMailbox' {
    It 'adds the mailbox with its automatic replies, permissions, calendar access, mail groups and inbox rules' {
        Set-UwSession
        Set-UwRoute {
            param($Uri, $Method, $Body)
            switch -Wildcard ($Uri) {
                '*/mailbox' { return New-UwResponse '{"displayName":"Jo Bloggs","type":"user","emailAddresses":[{"address":"jo@contoso.com","primary":true}],"onPremisesSyncEnabled":false,"hiddenFromAddressList":false,"litigationHold":false,"size":null,"archive":null,"forwarding":{"enabled":false,"recipientUserId":null,"recipientDisplayName":null,"smtpAddress":null,"keepCopy":false}}' }
                '*/mailbox/autoReply' { return New-UwResponse '{"status":"disabled","externalAudience":"none","internalReplyMessage":"","externalReplyMessage":"","scheduledStartDateTime":null,"scheduledEndDateTime":null,"simplified":false}' }
                '*/mailbox/permissions' { return New-UwResponse '{"permissions":[{"permission":"fullAccess","trusteeId":"00000000-0000-0000-0000-000000000006","displayName":"Sam","inherited":false}],"unreadPermissions":["sendOnBehalf"]}' }
                '*/mailbox/calendarAccess' { return New-UwResponse '{"calendarAccess":[{"trusteeId":"00000000-0000-0000-0000-000000000006","displayName":"Sam","role":"delegate"}]}' }
                '*/mailbox/mailGroups' { return New-UwResponse '{"mailGroups":[]}' }
                '*/mailbox/inboxRules' { return New-UwResponse '{"inboxRules":[{"id":"1234","name":"Fwd","enabled":true,"description":null,"deletesMessages":false,"hidden":false,"deletable":true,"forwardsExternally":true,"recipients":[]}]}' }
            }
            New-UwResponse ('{"id":"' + $script:Uid + '","displayName":"Jo Bloggs"}')
        }
        $u = Get-InforcerUser -TenantId $script:Tid -UserId $script:Uid -IncludeMailbox -ErrorVariable e
        $e | Should -BeNullOrEmpty
        $global:UwCalls.Count | Should -Be 7
        $u.mailbox.type | Should -Be 'user'
        $u.mailbox.calendarAccess[0].role | Should -Be 'delegate'
        $u.mailbox.autoReply.status | Should -Be 'disabled'
        $u.mailbox.permissions[0].trusteeId | Should -Be '00000000-0000-0000-0000-000000000006'
        @($u.mailbox.unreadPermissions) | Should -Be @('sendOnBehalf')
        @($u.mailbox.mailGroups).Count | Should -Be 0
        $u.mailbox.inboxRules[0].forwardsExternally | Should -BeTrue
        $json = Get-InforcerUser -TenantId $script:Tid -UserId $script:Uid -IncludeMailbox -OutputType JsonObject
        $json | Should -Match '"mailGroups":\s*\[\]'
    }

    It 'sets mailbox to null without an error or more requests when the user has no mailbox' {
        Set-UwSession
        Set-UwRoute {
            param($Uri, $Method, $Body)
            if ($Uri -like '*/mailbox') { return New-UwResponse '{"title":"Mailbox not found","status":404}' 404 }
            New-UwResponse '{"id":"u1"}'
        }
        $u = Get-InforcerUser -TenantId $script:Tid -UserId 'u1' -IncludeMailbox -ErrorAction Stop
        $global:UwCalls.Count | Should -Be 2
        $u.PSObject.Properties['mailbox'] | Should -Not -BeNullOrEmpty
        $u.mailbox | Should -BeNullOrEmpty
    }

    It 'reports any other failure and leaves mailbox out rather than saying there is none' {
        Set-UwSession
        Set-UwRoute {
            param($Uri, $Method, $Body)
            if ($Uri -like '*/mailbox') { return New-UwResponse '{"title":"Bad gateway","status":502}' 502 }
            New-UwResponse '{"id":"u1"}'
        }
        $u = Get-InforcerUser -TenantId $script:Tid -UserId 'u1' -IncludeMailbox -ErrorAction SilentlyContinue -ErrorVariable e
        "$($e[-1])" | Should -BeLike '*502*'
        $u.PSObject.Properties['mailbox'] | Should -BeNullOrEmpty
    }

    It 'refuses an API-key (beta) login with RequiresApiClient and makes no request' {
        Set-UwSession -Beta
        Set-UwRoute { param($Uri, $Method, $Body) New-UwResponse '{"data":{"id":"u1"},"success":true}' }
        Get-InforcerUser -TenantId 5 -UserId 'u1' -IncludeMailbox -ErrorAction SilentlyContinue -ErrorVariable e
        $e[0].FullyQualifiedErrorId | Should -BeLike 'RequiresApiClient*'
        $global:UwCalls.Count | Should -Be 0
    }
}
