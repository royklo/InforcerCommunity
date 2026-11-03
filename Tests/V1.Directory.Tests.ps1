# V1.Directory.Tests.ps1
# Users, groups, roles, secure score, policies and audit events on beta (API key) and v1 (client credentials).
# Fixtures are anonymised (zero GUIDs, example names); no network calls.

BeforeAll {
    Remove-Module -Name 'InforcerCommunity' -ErrorAction SilentlyContinue
    Import-Module (Join-Path $PSScriptRoot '../module/InforcerCommunity.psd1') -Force
    $script:M = Get-Module InforcerCommunity

    $script:Tid = '00000000-0000-0000-0000-000000000001'
    $script:G1 = '00000000-0000-0000-0000-0000000000a1'

    function global:New-DirResponse {
        param([string]$Json, [int]$Status = 200)
        [pscustomobject]@{ StatusCode = $Status; Body = ($Json | ConvertFrom-Json -Depth 100); Headers = @{} }
    }

    function global:Set-DirSession {
        param([switch]$Beta)
        & (Get-Module InforcerCommunity) {
            param($Beta)
            $script:InforcerTenantListCache = $null
            if ($Beta) {
                $script:InforcerSession = @{
                    AuthMode = 'ApiKey'; ApiVersion = 'beta'; ApiHost = 'https://api.example.invalid'
                    BaseUrl = 'https://api.example.invalid/api'; Region = 'uk'; ConnectedAt = Get-Date
                    ApiKey = (ConvertTo-SecureString 'beta-test-key-value' -AsPlainText -Force)
                }
            } else {
                $script:InforcerSession = @{
                    AuthMode = 'ClientCredentials'; ApiVersion = 'v1'; ApiHost = 'https://api.example.invalid'
                    BaseUrl = 'https://api.example.invalid'; Region = 'uk'; ConnectedAt = Get-Date
                    ClientId = 'client-id-example'
                    ClientSecret = (ConvertTo-SecureString 'client-secret-example-value' -AsPlainText -Force)
                    AccessToken = (ConvertTo-SecureString 'access-token-example-value' -AsPlainText -Force)
                    TokenExpiresAt = [datetime]::UtcNow.AddMinutes(50)
                }
            }
        } $Beta.IsPresent
    }

    # Routes every request through $global:DirRoute (param Uri, Method, Body) and records it in $global:DirCalls.
    function global:Set-DirRoute {
        param([scriptblock]$Route)
        $global:DirCalls = [System.Collections.Generic.List[object]]::new()
        $global:DirRoute = $Route
        Mock -ModuleName InforcerCommunity Invoke-InforcerHttpRequest {
            $global:DirCalls.Add([pscustomobject]@{ Uri = [string]$Request.Uri; Method = $Request.Method; Body = $Request.Body })
            & $global:DirRoute ([string]$Request.Uri) $Request.Method $Request.Body
        }
    }
}

AfterAll {
    foreach ($f in 'New-DirResponse', 'Set-DirSession', 'Set-DirRoute') { Remove-Item "function:global:$f" -ErrorAction SilentlyContinue }
    Remove-Variable -Name DirCalls, DirRoute -Scope Global -ErrorAction SilentlyContinue
    & (Get-Module InforcerCommunity) { $script:InforcerSession = $null; $script:InforcerTenantListCache = $null }
}

Describe 'Get-InforcerUser' {
    BeforeAll {
        $script:UserRoute = {
            param($Uri, $Method, $Body)
            if ($Uri -match 'continuationToken=tok1') {
                New-DirResponse '{"users":[{"id":"u3","displayName":"User Three","groupCount":0,"roleCount":0}],"userCount":3}'
            } elseif ($Uri -match '/users$|/users\?') {
                New-DirResponse '{"users":[{"id":"u1","displayName":"User One","groupCount":2,"roleCount":1},{"id":"u2","displayName":"User Two","groupCount":0,"roleCount":0}],"userCount":3,"continuationToken":"tok1"}'
            } else { New-DirResponse '{"title":"Not found","status":404}' 404 }
        }
    }

    It 'pages across v1 pages and maps groupCount/roleCount to groups/roles' {
        Set-DirSession
        Set-DirRoute $script:UserRoute
        $u = @(Get-InforcerUser -TenantId $script:Tid)
        $u.Count | Should -Be 3
        $u[0].groups | Should -Be 2
        $u[0].roles | Should -Be 1
        $global:DirCalls.Count | Should -Be 2
        $global:DirCalls[0].Uri | Should -BeLike 'https://api.example.invalid/v1/tenants/*/users'
        $global:DirCalls[1].Uri | Should -BeLike '*continuationToken=tok1'
    }

    It 'returns a JSON array on v1 -OutputType JsonObject (empty-list bug fixed)' {
        Set-DirSession
        Set-DirRoute $script:UserRoute
        $json = Get-InforcerUser -TenantId $script:Tid -OutputType JsonObject
        $json.TrimStart() | Should -BeLike '[[]*'
        @($json | ConvertFrom-Json).Count | Should -Be 3
    }

    It 'returns a JSON array on beta -OutputType JsonObject without throwing' {
        Set-DirSession -Beta
        Set-DirRoute {
            param($Uri, $Method, $Body)
            New-DirResponse '{"success":true,"data":[{"id":"u1","displayName":"User One"},{"id":"u2","displayName":"User Two"}]}'
        }
        $json = Get-InforcerUser -TenantId 5 -OutputType JsonObject
        $json.TrimStart() | Should -BeLike '[[]*'
        @($json | ConvertFrom-Json).Count | Should -Be 2
        $global:DirCalls[0].Uri | Should -BeLike 'https://api.example.invalid/api/beta/tenants/5/users'
    }

    It 'returns [] for an empty user list' {
        Set-DirSession
        Set-DirRoute { param($Uri, $Method, $Body) New-DirResponse '{"users":[],"userCount":0}' }
        (Get-InforcerUser -TenantId $script:Tid -OutputType JsonObject).Trim() | Should -Be '[]'
    }

    It 'stops at MaxResults in the middle of a page without a second request' {
        Set-DirSession
        Set-DirRoute $script:UserRoute
        @(Get-InforcerUser -TenantId $script:Tid -MaxResults 1).Count | Should -Be 1
        $global:DirCalls.Count | Should -Be 1
    }

    It 'stops when the API repeats a continuationToken' {
        Set-DirSession
        Set-DirRoute { param($Uri, $Method, $Body) New-DirResponse '{"users":[{"id":"u1"}],"continuationToken":"same"}' }
        @(Get-InforcerUser -TenantId $script:Tid).Count | Should -Be 2
        $global:DirCalls.Count | Should -Be 2
    }

    It 'sends -Search as a query parameter' {
        Set-DirSession
        Set-DirRoute $script:UserRoute
        $null = Get-InforcerUser -TenantId $script:Tid -Search 'a b' -MaxResults 1
        $global:DirCalls[0].Uri | Should -BeLike '*users?search=a%20b'
    }

    It 'refuses a numeric tenant id on v1 with InvalidTenantId' {
        Set-DirSession
        Set-DirRoute $script:UserRoute
        { Get-InforcerUser -TenantId 5 -ErrorAction Stop } | Should -Throw '*API key*'
        $global:DirCalls.Count | Should -Be 0
    }
}

Describe 'Get-InforcerGroup' {
    BeforeAll {
        $script:GroupRoute = {
            param($Uri, $Method, $Body)
            if ($Uri -match '/groups/[^/?]+/members') {
                if ($Uri -match 'continuationToken=m1') { New-DirResponse '{"members":[{"id":"m3","displayName":"Member Three","type":"user"}],"memberCount":3}' }
                else { New-DirResponse '{"members":[{"id":"m1","displayName":"Member One","type":"user"},{"id":"m2","displayName":"Member Two","type":"group"}],"memberCount":3,"continuationToken":"m1"}' }
            } elseif ($Uri -match '/groups/[^/?]+$') {
                New-DirResponse '{"id":"00000000-0000-0000-0000-0000000000a1","displayName":"Group One","memberCount":3}'
            } elseif ($Uri -match 'search=') {
                New-DirResponse '{"groups":[{"id":"00000000-0000-0000-0000-0000000000a1","displayName":"Group One"},{"id":"00000000-0000-0000-0000-0000000000a2","displayName":"Group One Extra"}],"groupCount":2}'
            } elseif ($Uri -match 'continuationToken=g1') {
                New-DirResponse '{"groups":[{"id":"g3","displayName":"Finance"}],"groupCount":3}'
            } else {
                New-DirResponse '{"groups":[{"id":"g1","displayName":"Sales"},{"id":"g2","displayName":"Finance EU"}],"groupCount":3,"continuationToken":"g1"}'
            }
        }
    }

    It 'lists groups across v1 pages' {
        Set-DirSession
        Set-DirRoute $script:GroupRoute
        @(Get-InforcerGroup -TenantId $script:Tid).Count | Should -Be 3
    }

    It 'applies -Filter before -MaxResults across pages' {
        Set-DirSession
        Set-DirRoute $script:GroupRoute
        $g = @(Get-InforcerGroup -TenantId $script:Tid -Filter 'Fin*' -MaxResults 2)
        $g.Count | Should -Be 2
        $g[0].displayName | Should -Be 'Finance EU'
        $g[1].displayName | Should -Be 'Finance'
    }

    It 'returns a JSON array for the v1 list' {
        Set-DirSession
        Set-DirRoute $script:GroupRoute
        (Get-InforcerGroup -TenantId $script:Tid -OutputType JsonObject).TrimStart() | Should -BeLike '[[]*'
    }

    It 'keeps beta group list JSON unchanged: one group is a bare object' {
        Set-DirSession -Beta
        Set-DirRoute { param($Uri, $Method, $Body) New-DirResponse '{"success":true,"data":[{"id":"g1","displayName":"Sales"}]}' }
        (Get-InforcerGroup -TenantId 5 -OutputType JsonObject).TrimStart() | Should -BeLike '{*'
    }

    It 'attaches the paged members to a v1 group detail' {
        Set-DirSession
        Set-DirRoute $script:GroupRoute
        $g = Get-InforcerGroup -TenantId $script:Tid -Group $script:G1
        @($g.members).Count | Should -Be 3
        $g.members[2].id | Should -Be 'm3'
        ($global:DirCalls | Where-Object Uri -like '*/v1/tenants/*/groups/*/members*').Count | Should -Be 2
    }

    It 'includes members in the v1 JSON detail' {
        Set-DirSession
        Set-DirRoute $script:GroupRoute
        $o = Get-InforcerGroup -TenantId $script:Tid -Group $script:G1 -OutputType JsonObject | ConvertFrom-Json
        @($o.members).Count | Should -Be 3
    }

    It 'resolves a group name on v1 by exact match' {
        Set-DirSession
        Set-DirRoute $script:GroupRoute
        $g = Get-InforcerGroup -TenantId $script:Tid -Group 'Group One'
        $g.id | Should -Be $script:G1
        $global:DirCalls[0].Uri | Should -BeLike '*groups?search=Group%20One'
    }

    It 'resolves a group name on beta from .data and fetches no members' {
        Set-DirSession -Beta
        Set-DirRoute {
            param($Uri, $Method, $Body)
            if ($Uri -match 'search=') { New-DirResponse '{"success":true,"data":[{"id":"00000000-0000-0000-0000-0000000000a1","displayName":"Group One"}]}' }
            else { New-DirResponse '{"success":true,"data":{"id":"00000000-0000-0000-0000-0000000000a1","displayName":"Group One","members":[{"id":"m1"}]}}' }
        }
        $g = Get-InforcerGroup -TenantId 7 -Group 'Group One'
        $g.id | Should -Be $script:G1
        @($g.members).Count | Should -Be 1
        ($global:DirCalls | Where-Object Uri -like '*/members*').Count | Should -Be 0
        $global:DirCalls[0].Uri | Should -BeLike '*/api/beta/tenants/7/groups?search=*'
    }

    It 'throws a clear error for an unknown group name' {
        Set-DirSession
        Set-DirRoute { param($Uri, $Method, $Body) New-DirResponse '{"groups":[],"groupCount":0}' }
        { Get-InforcerGroup -TenantId $script:Tid -Group 'Nope' -ErrorAction Stop } | Should -Throw '*No group found*'
    }

    It 'v1: leaves members null and warns when the members call fails' {
        Set-DirSession
        $groupRoute = $script:GroupRoute
        Set-DirRoute ({
            param($Uri, $Method, $Body)
            if ($Uri -match '/members') { New-DirResponse '{"title":"Server error","status":500}' 500 }
            else { & $groupRoute $Uri $Method $Body }
        }.GetNewClosure())
        $g = Get-InforcerGroup -TenantId $script:Tid -Group $script:G1 -WarningVariable w -WarningAction SilentlyContinue
        $g.id | Should -Be $script:G1
        $g.PSObject.Properties.Name | Should -Contain 'members'
        $g.members | Should -BeNullOrEmpty
        $null -eq $g.members | Should -BeTrue
        "$($w[0])" | Should -Match 'members'
        "$($w[0])" | Should -Match '500'
        (Get-InforcerGroup -TenantId $script:Tid -Group $script:G1 -OutputType JsonObject -WarningAction SilentlyContinue) | Should -Match '"members":\s*null'
    }

    It '<Name>: a network failure reports the module error, not a binding error' -ForEach @(
        @{ Name = 'beta'; Beta = $true; TenantId = 7 }
        @{ Name = 'v1'; Beta = $false; TenantId = '00000000-0000-0000-0000-000000000001' }
    ) {
        Set-DirSession -Beta:$Beta
        & $script:M { $s = $script:InforcerSession; $s.ApiHost = 'https://127.0.0.1:1'; $s.BaseUrl = if ($s.ApiVersion -eq 'beta') { 'https://127.0.0.1:1/api' } else { 'https://127.0.0.1:1' } }
        $null = Get-InforcerGroup -TenantId $TenantId -Group $script:G1 -ErrorAction SilentlyContinue -ErrorVariable e
        @($e).Count | Should -BeGreaterThan 0
        @($e | Where-Object { "$($_.FullyQualifiedErrorId)" -match 'ParameterBindingFailed|CannotConvertArgument' }).Count | Should -Be 0
        @($e)[-1].FullyQualifiedErrorId | Should -Match '^ApiRequestFailed'
        $err = $null
        try { Get-InforcerGroup -TenantId $TenantId -Group 'Group One' -ErrorAction Stop } catch { $err = $_ }
        $err.Exception.Message | Should -Match "Failed to search for group 'Group One': \S"
    }
}

Describe 'List streaming' {
    It '<Cmdlet> | Select-Object -First 1 requests one page of five on <Name>' -ForEach @(
        @{ Cmdlet = 'Get-InforcerUser'; Name = 'beta'; Beta = $true; TenantId = 5 }
        @{ Cmdlet = 'Get-InforcerGroup'; Name = 'beta'; Beta = $true; TenantId = 5 }
        @{ Cmdlet = 'Get-InforcerUser'; Name = 'v1'; Beta = $false; TenantId = '00000000-0000-0000-0000-000000000001' }
        @{ Cmdlet = 'Get-InforcerGroup'; Name = 'v1'; Beta = $false; TenantId = '00000000-0000-0000-0000-000000000001' }
    ) {
        Set-DirSession -Beta:$Beta
        $collection = if ($Cmdlet -eq 'Get-InforcerUser') { 'users' } else { 'groups' }
        Set-DirRoute ({
            param($Uri, $Method, $Body)
            $n = if ($Uri -match 'continuationToken=p(\d)') { [int]$Matches[1] } else { 1 }
            $items = "[{""id"":""i$n-1"",""displayName"":""Item $n-1""},{""id"":""i$n-2"",""displayName"":""Item $n-2""}]"
            $next = if ($n -lt 5) { ",""continuationToken"":""p$($n + 1)""" } else { '' }
            if ($Beta) { New-DirResponse "{""success"":true,""data"":$items$next}" }
            else { New-DirResponse "{""$collection"":$items$next}" }
        }.GetNewClosure())

        $first = & $Cmdlet -TenantId $TenantId | Select-Object -First 1
        $first.id | Should -Be 'i1-1'
        $global:DirCalls.Count | Should -Be 1

        $global:DirCalls.Clear()
        @(& $Cmdlet -TenantId $TenantId).Count | Should -Be 10
        $global:DirCalls.Count | Should -Be 5
    }

    It 'Get-InforcerGroup -Filter -MaxResults stops paging once enough groups match' {
        Set-DirSession -Beta
        Set-DirRoute {
            param($Uri, $Method, $Body)
            $n = if ($Uri -match 'continuationToken=p(\d)') { [int]$Matches[1] } else { 1 }
            $next = if ($n -lt 5) { ",""continuationToken"":""p$($n + 1)""" } else { '' }
            New-DirResponse "{""success"":true,""data"":[{""id"":""g$n"",""displayName"":""Finance $n""},{""id"":""s$n"",""displayName"":""Sales $n""}]$next}"
        }
        $g = @(Get-InforcerGroup -TenantId 5 -Filter 'Sales*' -MaxResults 2)
        $g.displayName | Should -Be @('Sales 1', 'Sales 2')
        $global:DirCalls.Count | Should -Be 2
        @(Get-InforcerGroup -TenantId 5 -Filter 'Sales*' -MaxResults 2 -OutputType JsonObject | ConvertFrom-Json).Count | Should -Be 2
    }
}

Describe 'Get-InforcerRole, Get-InforcerSecureScore, Get-InforcerSupportedEventType' {
    It 'reads v1 roles from /directoryRoles' {
        Set-DirSession
        Set-DirRoute { param($Uri, $Method, $Body) New-DirResponse '{"roles":[{"id":"r1","displayName":"Role One","isPrivileged":true},{"id":"r2","displayName":"Role Two","isPrivileged":false}]}' }
        $r = @(Get-InforcerRole -TenantId $script:Tid)
        $r.Count | Should -Be 2
        $global:DirCalls[0].Uri | Should -BeLike '*/v1/tenants/*/directoryRoles'
    }

    It 'reads beta roles from /beta/.../roles' {
        Set-DirSession -Beta
        Set-DirRoute { param($Uri, $Method, $Body) New-DirResponse '{"success":true,"data":[{"id":"r1","displayName":"Role One"},{"id":"r2","displayName":"Role Two"}]}' }
        @(Get-InforcerRole -TenantId 5).Count | Should -Be 2
        $global:DirCalls[0].Uri | Should -BeLike '*/api/beta/tenants/5/roles'
    }

    It 'returns the whole v1 secure score object' {
        Set-DirSession
        Set-DirRoute { param($Uri, $Method, $Body) New-DirResponse '{"currentScore":42,"maxScore":100,"scores":[{"date":"2000-01-01","score":40}],"controlProfiles":[{"id":"c1"}]}' }
        $s = Get-InforcerSecureScore -TenantId $script:Tid
        $s.currentScore | Should -Be 42
        @($s.scores).Count | Should -Be 1
        $s.PSObject.TypeNames[0] | Should -Be 'InforcerCommunity.SecureScore'
    }

    It 'reads v1 event types from /auditEvents/types' {
        Set-DirSession
        $saved = $global:InforcerCachedEventTypes
        try {
            Set-DirRoute { param($Uri, $Method, $Body) New-DirResponse '{"eventTypes":[{"name":"authentication"},{"name":"userCreate"}]}' }
            (@(Get-InforcerSupportedEventType) -join ',') | Should -Be 'authentication,userCreate'
            $global:DirCalls[0].Uri | Should -BeLike '*/v1/auditEvents/types'
        } finally { $global:InforcerCachedEventTypes = $saved }
    }
}

Describe 'Get-InforcerAuditEvent' {
    BeforeAll {
        $script:AuditRoute = {
            param($Uri, $Method, $Body)
            $b = $Body | ConvertFrom-Json
            if ($b.continuationToken -eq 'a1') {
                New-DirResponse '{"auditEvents":[{"id":"e3","eventType":"authentication","correlationId":"c1"}]}'
            } else {
                New-DirResponse '{"auditEvents":[{"id":"e1","eventType":"authentication","metadata":{"nameLookup":{"user:username:1":"user@example.invalid","user:displayName:1":"Example User"}}},{"id":"e2","eventType":"authentication"}],"continuationToken":"a1"}'
            }
        }
    }

    It 'posts whole-second dates on v1, pages via the body token and reads auditEvents' {
        Set-DirSession
        Set-DirRoute $script:AuditRoute
        $e = @(Get-InforcerAuditEvent -EventType authentication -DateFrom ([datetime]'2000-01-01') -DateTo ([datetime]'2000-01-02'))
        $e.Count | Should -Be 3
        $global:DirCalls.Count | Should -Be 2
        $global:DirCalls[0].Method | Should -Be 'POST'
        $global:DirCalls[0].Uri | Should -BeLike '*/v1/auditEvents/search'
        $global:DirCalls[0].Body | Should -Match '"dateTo":"\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ"'
        ($global:DirCalls[1].Body | ConvertFrom-Json).continuationToken | Should -Be 'a1'
    }

    It 'enriches v1 events with and without metadata' {
        Set-DirSession
        Set-DirRoute $script:AuditRoute
        $e = @(Get-InforcerAuditEvent -EventType authentication -DateFrom ([datetime]'2000-01-01') -DateTo ([datetime]'2000-01-02'))
        $e[0].UserName | Should -Be 'user@example.invalid'
        $e[0].UserDisplayName | Should -Be 'Example User'
        $e[1].PSObject.Properties['UserName'] | Should -BeNullOrEmpty
    }

    It 'keeps milliseconds in the beta dateTo and reads items from .data' {
        Set-DirSession -Beta
        Set-DirRoute { param($Uri, $Method, $Body) New-DirResponse '{"success":true,"data":{"items":[{"id":"e1","eventType":"authentication"}],"continuationToken":null}}' }
        $e = @(Get-InforcerAuditEvent -EventType authentication -DateFrom ([datetime]'2000-01-01') -DateTo ([datetime]'2000-01-02'))
        $e.Count | Should -Be 1
        $global:DirCalls[0].Uri | Should -BeLike '*/api/beta/auditEvents/search'
        $global:DirCalls[0].Body | Should -Match '"dateTo":"[^"]*\.\d{3}Z"'
    }

    It 'honours MaxResults and returns a JSON array' {
        Set-DirSession
        Set-DirRoute $script:AuditRoute
        $json = Get-InforcerAuditEvent -EventType authentication -MaxResults 1 -OutputType JsonObject
        $json.TrimStart() | Should -BeLike '[[]*'
        @($json | ConvertFrom-Json).Count | Should -Be 1
        $global:DirCalls.Count | Should -Be 1
    }

    It 'omits eventTypes on v1 when -EventType is not given and makes no event-type lookup' {
        Set-DirSession
        Set-DirRoute $script:AuditRoute
        $null = Get-InforcerAuditEvent -DateFrom ([datetime]'2000-01-01') -DateTo ([datetime]'2000-01-02')
        $global:DirCalls.Count | Should -Be 2
        $global:DirCalls[0].Uri | Should -BeLike '*/v1/auditEvents/search'
        $global:DirCalls[0].Body | Should -Not -Match 'eventTypes'
    }

    It 'keeps beta JSON output unchanged: one event is a bare object' {
        Set-DirSession -Beta
        Set-DirRoute { param($Uri, $Method, $Body) New-DirResponse '{"success":true,"data":{"items":[{"id":"e1","eventType":"authentication"}]}}' }
        $json = Get-InforcerAuditEvent -EventType authentication -OutputType JsonObject
        $json.TrimStart() | Should -BeLike '{*'
    }

    It 'filters by -CorrelationId client-side' {
        Set-DirSession
        Set-DirRoute $script:AuditRoute
        $e = @(Get-InforcerAuditEvent -EventType authentication -CorrelationId c1)
        $e.Count | Should -Be 1
        $e[0].id | Should -Be 'e3'
    }
}

Describe 'Get-InforcerTenantPolicies' {
    It 'processes every piped tenant, not only the last' {
        Set-DirSession
        Set-DirRoute { param($Uri, $Method, $Body) $n = if ($Uri -match '0{11}(\d)/policies') { $Matches[1] }; New-DirResponse ('{"policies":[{"id":"p' + $n + '","displayName":"P","product":"Intune"}],"failedPolicyTypes":{}}') }
        $p = @([pscustomobject]@{ MsTenantId = $script:Tid }, [pscustomobject]@{ MsTenantId = '00000000-0000-0000-0000-000000000002' } | Get-InforcerTenantPolicies)
        @($p.id) | Should -Be @('p1', 'p2')
    }

    It 'warns once on v1 when no Intune policies are returned' {
        Set-DirSession
        Set-DirRoute { param($Uri, $Method, $Body) New-DirResponse '{"policies":[{"id":"p1","displayName":"Policy One","product":"Entra","policyTypeName":"Conditional Access"}],"failedPolicyTypes":{}}' }
        $p = @(Get-InforcerTenantPolicies -TenantId $script:Tid -WarningVariable w -WarningAction SilentlyContinue)
        $p.Count | Should -Be 1
        @($w).Count | Should -Be 1
        "$($w[0])" | Should -BeLike '*Intune*known gap*inforcer*'
        $p[0].PolicyName | Should -Be 'Policy One'
    }

    It 'does not warn on v1 when an Intune policy is present' {
        Set-DirSession
        Set-DirRoute { param($Uri, $Method, $Body) New-DirResponse '{"policies":[{"id":"p1","displayName":"Policy One","product":"Intune"}],"failedPolicyTypes":{}}' }
        $null = Get-InforcerTenantPolicies -TenantId $script:Tid -WarningVariable w -WarningAction SilentlyContinue
        @($w).Count | Should -Be 0
    }

    It 'returns a JSON array on v1, also for a single policy, and still warns' {
        Set-DirSession
        Set-DirRoute { param($Uri, $Method, $Body) New-DirResponse '{"policies":[{"id":"p1","displayName":"Policy One","product":"Entra"}],"failedPolicyTypes":{}}' }
        $json = Get-InforcerTenantPolicies -TenantId $script:Tid -OutputType JsonObject -WarningVariable w -WarningAction SilentlyContinue
        $json.TrimStart() | Should -BeLike '[[]*'
        @($w).Count | Should -Be 1
    }

    It 'leaves beta output and warnings unchanged' {
        Set-DirSession -Beta
        Set-DirRoute { param($Uri, $Method, $Body) New-DirResponse '{"success":true,"data":[{"id":"p1","displayName":"Policy One","product":"Entra"},{"id":"p2","name":"Policy Two","product":"Entra"}]}' }
        $p = @(Get-InforcerTenantPolicies -TenantId 5 -WarningVariable w -WarningAction SilentlyContinue)
        $p.Count | Should -Be 2
        @($w).Count | Should -Be 0
        $global:DirCalls[0].Uri | Should -BeLike '*/api/beta/tenants/5/policies'
    }
}

Describe 'MsTenantId alias' {
    It 'is defined next to ClientTenantId on every -TenantId parameter' -ForEach @(
        @{ Name = 'Get-InforcerUser' }, @{ Name = 'Get-InforcerGroup' }, @{ Name = 'Get-InforcerRole' },
        @{ Name = 'Get-InforcerSecureScore' }, @{ Name = 'Get-InforcerTenantPolicies' }
    ) {
        $aliases = (Get-Command $Name).Parameters['TenantId'].Aliases
        $aliases | Should -Contain 'ClientTenantId'
        $aliases | Should -Contain 'MsTenantId'
    }
}
