# Fix.Pipeline.Tests.ps1
# Fix wave 1.5.9b: piped tenants (shared data once, TenantId on results, one JSON array), the baseline list
# cache, Get-InforcerTenant lookups, v1 JSON arrays, the assessment run transport, CSV neutralising and
# one beta audit search. Invoke-InforcerHttpRequest is mocked; fixtures are anonymised; no network calls.

Describe 'Fix 1.5.9b: pipeline, TenantId, caching' {
    BeforeAll {
        Remove-Module -Name 'InforcerCommunity' -ErrorAction SilentlyContinue
        Import-Module (Join-Path $PSScriptRoot '../module/InforcerCommunity.psd1') -Force
        $script:M = Get-Module InforcerCommunity

        $script:T1 = '00000000-0000-0000-0000-000000000001'
        $script:T2 = '00000000-0000-0000-0000-000000000002'
        $script:B1 = '00000000-0000-0000-0000-0000000000b1'
        $script:B2 = '00000000-0000-0000-0000-0000000000b2'

        function global:Reset-FixPipeRoutes {
            $global:FixPipeRoutes = [ordered]@{
                # v1 (client credentials)
                '/v1/tenants$' = '{"tenants":[{"msTenantId":"00000000-0000-0000-0000-000000000001","name":"Contoso","dnsName":"contoso.example.invalid","isBaseline":true,"tags":[{"name":"Production","description":""}],"alignmentSummaries":[],"licenses":[]},{"msTenantId":"00000000-0000-0000-0000-000000000002","name":"Fabrikam","dnsName":"fabrikam.example.invalid","isBaseline":false,"tags":[{"name":"Test","description":""}],"alignmentSummaries":[{"alignedBaselineId":"00000000-0000-0000-0000-0000000000b1","alignedBaselineMsTenantId":"00000000-0000-0000-0000-000000000001","alignedBaselineName":"Contoso Baseline","alignmentScore":80.5}],"licenses":[]}]}'
                '/v1/tenants/00000000-0000-0000-0000-000000000001$' = '{"msTenantId":"00000000-0000-0000-0000-000000000001","name":"Contoso","dnsName":"contoso.example.invalid","isBaseline":true,"tags":[{"name":"Production","description":""}],"alignmentSummaries":[],"licenses":[]}'
                '/v1/tenants/00000000-0000-0000-0000-000000000002$' = '{"msTenantId":"00000000-0000-0000-0000-000000000002","name":"Fabrikam","dnsName":"fabrikam.example.invalid","isBaseline":false,"tags":[{"name":"Test","description":""}],"alignmentSummaries":[],"licenses":[]}'
                '/v1/baselines$' = '{"baselines":[{"id":"00000000-0000-0000-0000-0000000000b1","name":"Contoso Baseline","description":"","baselineTenant":{"msTenantId":"00000000-0000-0000-0000-000000000001","name":"Contoso","dnsName":"contoso.example.invalid"},"mode":"Monitor","alignedThreshold":90,"semiAlignedThreshold":70,"members":[{"msTenantId":"00000000-0000-0000-0000-000000000002","name":"Fabrikam","dnsName":"fabrikam.example.invalid"}],"items":[]},{"id":"00000000-0000-0000-0000-0000000000b2","name":"Other Baseline","description":"","baselineTenant":{"msTenantId":"00000000-0000-0000-0000-000000000003","name":"Northwind","dnsName":"northwind.example.invalid"},"mode":"Monitor","alignedThreshold":90,"semiAlignedThreshold":70,"members":[{"msTenantId":"00000000-0000-0000-0000-000000000001","name":"Contoso","dnsName":"contoso.example.invalid"}],"items":[]}]}'
                '/v1/alignmentScores$' = '{"alignmentScores":[{"msTenantId":"00000000-0000-0000-0000-000000000002","tenantName":"Fabrikam","alignedBaselineId":"00000000-0000-0000-0000-0000000000b1","alignedBaselineName":"Contoso Baseline","alignmentScore":80.5,"lastAlignmentTimestamp":"2026-01-02T00:00:00Z"},{"msTenantId":"00000000-0000-0000-0000-000000000001","tenantName":"Contoso","alignedBaselineId":"00000000-0000-0000-0000-0000000000b2","alignedBaselineName":"Other Baseline","alignmentScore":100,"lastAlignmentTimestamp":"2026-01-02T00:00:00Z"}]}'
                '/v1/tenants/[^/]+/alignmentDetails\?baselineId=' = '{"completedAt":"2026-01-02T00:00:00Z","baseline":{"id":"00000000-0000-0000-0000-0000000000b1","name":"Contoso Baseline"},"alignmentScore":80.5,"metrics":{"totalPolicies":1,"matched":1,"matchedWithAcceptedDeviations":0,"deviated":0,"missingFromTenant":0,"additionalInTenant":0},"policies":{"matched":[{"id":"p1","policyTypeId":1,"policyTypeName":"Settings Catalog","displayName":"Policy A","friendlyName":"Policy A","description":"","readOnly":false,"product":"Intune","primaryGroup":"Devices","secondaryGroup":"Windows","platform":"Windows","tags":[],"tenantPolicies":[],"variables":[],"acceptedDeviations":[],"similarPolicies":[]}],"matchedWithAcceptedDeviations":[],"deviated":[],"missingFromTenant":[],"additionalInTenant":[]}}'
                '/v1/tenants/[^/]+/policies$' = '{"policies":[{"id":"p1","displayName":"Policy One","product":"Intune"}],"failedPolicyTypes":{}}'
                '/v1/tenants/[^/]+/users$' = '{"users":[{"id":"u1","displayName":"User One","groupCount":0,"roleCount":0}],"userCount":1}'
                '/v1/tenants/[^/]+/groups$' = '{"groups":[{"id":"g1","displayName":"Group One"}],"groupCount":1}'
                '/v1/tenants/[^/]+/directoryRoles$' = '{"roles":[{"id":"r1","displayName":"Role One"}]}'
                '/v1/tenants/[^/]+/secureScores$' = '{"currentScore":42,"maxScore":100,"scores":[],"controlProfiles":[]}'
                # beta (API key)
                '/beta/tenants$' = '{"success":true,"data":[{"clientTenantId":1,"msTenantId":"00000000-0000-0000-0000-000000000001","tenantFriendlyName":"Contoso","tenantDnsName":"contoso.example.invalid","tags":[],"alignmentSummaries":[{"alignedBaselineId":"00000000-0000-0000-0000-0000000000b2","alignedBaselineName":"Other Baseline","alignedBaselineTenantId":3,"alignmentScore":100}]},{"clientTenantId":2,"msTenantId":"00000000-0000-0000-0000-000000000002","tenantFriendlyName":"Fabrikam","tenantDnsName":"fabrikam.example.invalid","tags":[],"alignmentSummaries":[{"alignedBaselineId":"00000000-0000-0000-0000-0000000000b1","alignedBaselineName":"Contoso Baseline","alignedBaselineTenantId":1,"alignmentScore":80.5}]}]}'
                '/beta/baselines$' = '{"success":true,"data":[{"id":"00000000-0000-0000-0000-0000000000b1","name":"Contoso Baseline","baselineClientTenantId":1,"baselineMsTenantId":"00000000-0000-0000-0000-000000000001","members":[{"clientTenantId":2,"msTenantId":"00000000-0000-0000-0000-000000000002","tenantFriendlyName":"Fabrikam"}],"items":[]},{"id":"00000000-0000-0000-0000-0000000000b2","name":"Other Baseline","baselineClientTenantId":3,"baselineMsTenantId":"00000000-0000-0000-0000-000000000003","members":[{"clientTenantId":1,"msTenantId":"00000000-0000-0000-0000-000000000001","tenantFriendlyName":"Contoso"}],"items":[]}]}'
                '/beta/alignmentScores$' = '{"success":true,"data":[{"tenantId":2,"tenantFriendlyName":"Fabrikam","score":80.5,"baselineGroupId":"00000000-0000-0000-0000-0000000000b1","baselineGroupName":"Contoso Baseline","lastComparisonDateTime":"2026-01-02T00:00:00Z"},{"tenantId":1,"tenantFriendlyName":"Contoso","score":100,"baselineGroupId":"00000000-0000-0000-0000-0000000000b2","baselineGroupName":"Other Baseline","lastComparisonDateTime":"2026-01-02T00:00:00Z"}]}'
                '/beta/tenants/\d+/alignmentDetails\?customBaselineId=' = '{"success":true,"data":{"metrics":{"totalPolicies":1,"matchedPolicies":1},"completedAt":"2026-01-02T00:00:00Z","alignment":{"alignmentScore":80.5,"matchedPolicies":[{"policyName":"Policy A","product":"Intune","primaryGroup":"Devices","secondaryGroup":"Windows","inforcerPolicyTypeName":"Settings Catalog","policyTags":[]}],"matchedWithAcceptedDeviations":[],"deviatedUnaccepted":[],"missingFromSubjectUnaccepted":[],"additionalInSubjectUnaccepted":[]}}}'
                '/beta/tenants/\d+/policies$' = '{"success":true,"data":[{"id":"p1","displayName":"Policy One","product":"Intune"}]}'
                '/beta/tenants/\d+/roles$' = '{"success":true,"data":[{"id":"r1","displayName":"Role One"}]}'
                '/beta/auditEvents/search$' = '{"success":true,"data":{"items":[{"id":"e1","eventType":"authentication"}],"continuationToken":null}}'
                '/beta/auditEvents/eventTypes$' = '{"success":true,"data":[{"name":"authentication"}]}'
            }
        }

        function global:Get-FixPipeResponse([string]$Uri) {
            foreach ($pattern in $global:FixPipeRoutes.Keys) {
                if ($Uri -notmatch $pattern) { continue }
                $route = $global:FixPipeRoutes[$pattern]
                $status = 200
                if ($route -is [hashtable]) { $status = $route.Status; $route = $route.Body }
                return [pscustomobject]@{ StatusCode = $status; Body = ($route | ConvertFrom-Json -Depth 100); Headers = @{} }
            }
            [pscustomobject]@{ StatusCode = 404; Body = [pscustomobject]@{ title = 'Not Found'; status = 404 }; Headers = @{} }
        }

        function global:Set-FixPipeSession {
            param([switch]$Beta)
            & (Get-Module InforcerCommunity) {
                param($Beta)
                $script:InforcerTenantListCache = $null
                $script:InforcerBaselineListCache = $null
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

        # Piped tenant objects as Get-InforcerTenant emits them, per login.
        function global:Get-FixPipeTenants {
            param([switch]$Beta, [int[]]$Index = @(1, 2))
            foreach ($i in $Index) {
                if ($Beta) { [pscustomobject]@{ ClientTenantId = $i } }
                else { [pscustomobject]@{ MsTenantId = "00000000-0000-0000-0000-00000000000$i" } }
            }
        }
    }

    AfterAll {
        foreach ($f in 'Reset-FixPipeRoutes', 'Get-FixPipeResponse', 'Set-FixPipeSession', 'Get-FixPipeTenants') { Remove-Item "function:global:$f" -ErrorAction SilentlyContinue }
        Remove-Variable -Name FixPipeRoutes -Scope Global -ErrorAction SilentlyContinue
        & (Get-Module InforcerCommunity) { $script:InforcerSession = $null; $script:InforcerTenantListCache = $null; $script:InforcerBaselineListCache = $null }
    }

    BeforeEach {
        Reset-FixPipeRoutes
        Mock -ModuleName InforcerCommunity Invoke-InforcerHttpRequest { Get-FixPipeResponse $Request.Uri }
    }

    Describe 'Get-InforcerBaseline with piped tenants' {
        It '<Mode>: fetches /baselines once and returns each (tenant, baseline) once with TenantId' -ForEach @(
            @{ Mode = 'beta'; Beta = $true; Id1 = 1; Id2 = 2 }
            @{ Mode = 'v1'; Beta = $false; Id1 = '00000000-0000-0000-0000-000000000001'; Id2 = '00000000-0000-0000-0000-000000000002' }
        ) {
            Set-FixPipeSession -Beta:$Beta
            $r = @(Get-FixPipeTenants -Beta:$Beta -Index 1, 2, 1 | Get-InforcerBaseline)
            @($r | ForEach-Object { "$($_.TenantId)|$($_.id)" }) | Should -Be @("$Id1|$script:B1", "$Id1|$script:B2", "$Id2|$script:B1")
            $r[0].TenantId | Should -Be $Id1
            $r[0].PSObject.TypeNames[0] | Should -Be 'InforcerCommunity.Baseline'
            Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 1 -Exactly -ParameterFilter { $Request.Uri -match '/baselines$' }
        }

        It '<Mode>: -OutputType JsonObject returns one JSON array for all piped tenants' -ForEach @(
            @{ Mode = 'beta'; Beta = $true }
            @{ Mode = 'v1'; Beta = $false }
        ) {
            Set-FixPipeSession -Beta:$Beta
            $json = @(Get-FixPipeTenants -Beta:$Beta | Get-InforcerBaseline -OutputType JsonObject)
            $json.Count | Should -Be 1
            $json[0].TrimStart() | Should -BeLike '`[*'
            $parsed = @($json[0] | ConvertFrom-Json -Depth 100)
            $parsed.Count | Should -Be 3
            @($parsed | Where-Object { $null -eq $_.TenantId }).Count | Should -Be 0
            $json[0] | Should -Not -CMatch '"BaselineId"'
        }

        It 'keeps non-piped output unchanged: no TenantId, beta single match is a bare JSON object' {
            Set-FixPipeSession -Beta
            $r = @(Get-InforcerBaseline -TenantId 2)
            $r.Count | Should -Be 1
            $r[0].PSObject.Properties['TenantId'] | Should -BeNullOrEmpty
            (Get-InforcerBaseline -TenantId 2 -OutputType JsonObject).TrimStart() | Should -BeLike '{*'
        }

        It 'never decorates the cached baseline objects' {
            Set-FixPipeSession -Beta
            $null = Get-InforcerBaseline
            $cached = & $script:M { $script:InforcerBaselineListCache.Baselines }
            $cached[0].PSObject.Properties['BaselineId'] | Should -BeNullOrEmpty
            $cached[0].PSObject.TypeNames | Should -Not -Contain 'InforcerCommunity.Baseline'
        }
    }

    Describe 'Get-InforcerAlignmentDetails with piped tenants' {
        It '<Mode>: table fetches the scores once and lists each row once with TenantId' -ForEach @(
            @{ Mode = 'beta'; Beta = $true; IdProp = 'TargetTenantClientTenantId' }
            @{ Mode = 'v1'; Beta = $false; IdProp = 'TargetTenantMsTenantId' }
        ) {
            Set-FixPipeSession -Beta:$Beta
            # Tenant 1 owns a baseline that tenant 2 is aligned to, so tenant 1 alone already selects both rows.
            $r = @(Get-FixPipeTenants -Beta:$Beta | Get-InforcerAlignmentDetails)
            $r.Count | Should -Be 2
            foreach ($row in $r) { $row.TenantId | Should -Be $row.$IdProp }
            Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 1 -Exactly -ParameterFilter { $Request.Uri -match '/alignmentScores$' }
            $json = @(Get-FixPipeTenants -Beta:$Beta | Get-InforcerAlignmentDetails -OutputType JsonObject)
            $json.Count | Should -Be 1
            @($json[0] | ConvertFrom-Json).Count | Should -Be 2
        }

        It 'v1: -Tag reads the tenant list once for the whole pipeline, with no per-tenant calls' {
            Set-FixPipeSession
            $r = @(Get-FixPipeTenants | Get-InforcerAlignmentDetails -Tag 'Prod')
            @($r.TargetTenantMsTenantId | Sort-Object) | Should -Be @($script:T1, $script:T2)
            Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 0 -Exactly -ParameterFilter { $Request.Uri -match '/v1/tenants/[0-9a-f-]{36}$' }
            Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 1 -Exactly -ParameterFilter { $Request.Uri -match '/v1/tenants$' }
            Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 0 -Exactly -ParameterFilter { $Request.Uri -match '/v1/baselines$' }
        }

        It '<Mode>: -BaselineId queries each piped tenant once; rows and JSON carry TenantId' -ForEach @(
            @{ Mode = 'beta'; Beta = $true; Id2 = 2 }
            @{ Mode = 'v1'; Beta = $false; Id2 = '00000000-0000-0000-0000-000000000002' }
        ) {
            Set-FixPipeSession -Beta:$Beta
            $r = @(Get-FixPipeTenants -Beta:$Beta -Index 1, 2, 2 | Get-InforcerAlignmentDetails -BaselineId $script:B1 6>$null)
            $r.Count | Should -Be 2
            $r[1].TenantId | Should -Be $Id2
            Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 2 -Exactly -ParameterFilter { $Request.Uri -match 'alignmentDetails' }
            $json = @(Get-FixPipeTenants -Beta:$Beta | Get-InforcerAlignmentDetails -BaselineId $script:B1 -OutputType JsonObject 6>$null)
            $json.Count | Should -Be 1
            $parsed = @($json[0] | ConvertFrom-Json -Depth 100)
            $parsed.Count | Should -Be 2
            $parsed[1].TenantId | Should -Be $Id2
        }

        It 'v1: -Format Raw fetches the scores once; items carry their tenant and JSON is one array' {
            Set-FixPipeSession
            $r = @(Get-FixPipeTenants | Get-InforcerAlignmentDetails -Format Raw)
            $r.Count | Should -Be 2
            foreach ($item in $r) { $item.TenantId | Should -Be $item.msTenantId }
            $json = @(Get-FixPipeTenants | Get-InforcerAlignmentDetails -Format Raw -OutputType JsonObject)
            $json.Count | Should -Be 1
            Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 2 -Exactly -ParameterFilter { $Request.Uri -match '/alignmentScores$' }
        }

        It 'keeps non-piped rows without TenantId; a one-row table is a JSON array on v1 and a bare object on beta' {
            Set-FixPipeSession
            $r = @(Get-InforcerAlignmentDetails -TenantId $script:T2)
            $r.Count | Should -Be 1
            $r[0].PSObject.Properties['TenantId'] | Should -BeNullOrEmpty
            (Get-InforcerAlignmentDetails -TenantId $script:T2 -OutputType JsonObject).TrimStart() | Should -BeLike '`[*'
            Set-FixPipeSession -Beta
            (Get-InforcerAlignmentDetails -TenantId 2 -OutputType JsonObject).TrimStart() | Should -BeLike '{*'
        }
    }

    Describe 'Get-InforcerTenantPolicies with piped tenants' {
        It '<Mode>: each policy carries TenantId and JSON is one array' -ForEach @(
            @{ Mode = 'beta'; Beta = $true; Ids = @(1, 2) }
            @{ Mode = 'v1'; Beta = $false; Ids = @('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002') }
        ) {
            Set-FixPipeSession -Beta:$Beta
            $p = @(Get-FixPipeTenants -Beta:$Beta | Get-InforcerTenantPolicies)
            @($p.TenantId) | Should -Be $Ids
            $p[0].PolicyName | Should -Be 'Policy One'
            $json = @(Get-FixPipeTenants -Beta:$Beta | Get-InforcerTenantPolicies -OutputType JsonObject)
            $json.Count | Should -Be 1
            $parsed = @($json[0] | ConvertFrom-Json)
            @($parsed.TenantId) | Should -Be $Ids
            $json[0] | Should -Not -CMatch '"PolicyName"'
        }

        It 'keeps non-piped policies without TenantId' {
            Set-FixPipeSession -Beta
            @(Get-InforcerTenantPolicies -TenantId 1)[0].PSObject.Properties['TenantId'] | Should -BeNullOrEmpty
        }
    }

    Describe 'Directory cmdlets with piped tenants' {
        It '<Name>: piped results carry TenantId and JSON is one array' -ForEach @(
            @{ Name = 'Get-InforcerUser' }
            @{ Name = 'Get-InforcerGroup' }
            @{ Name = 'Get-InforcerRole' }
            @{ Name = 'Get-InforcerSecureScore' }
        ) {
            Set-FixPipeSession
            $r = @(Get-FixPipeTenants | & $Name)
            @($r.TenantId) | Should -Be @($script:T1, $script:T2)
            $json = @(Get-FixPipeTenants | & $Name -OutputType JsonObject)
            $json.Count | Should -Be 1
            @(($json[0] | ConvertFrom-Json).TenantId) | Should -Be @($script:T1, $script:T2)
            @(& $Name -TenantId $script:T1)[0].PSObject.Properties['TenantId'] | Should -BeNullOrEmpty
        }

        It 'beta Get-InforcerRole: piped roles carry the numeric TenantId' {
            Set-FixPipeSession -Beta
            @((Get-FixPipeTenants -Beta | Get-InforcerRole).TenantId) | Should -Be @(1, 2)
        }
    }

    Describe 'v1 JSON arrays (Role, Tenant)' {
        It 'v1 Get-InforcerRole returns an array for one role and [] for none; beta keeps a bare object' {
            Set-FixPipeSession
            (Get-InforcerRole -TenantId $script:T1 -OutputType JsonObject).TrimStart() | Should -BeLike '`[*'
            $global:FixPipeRoutes['/v1/tenants/[^/]+/directoryRoles$'] = '{"roles":[]}'
            (Get-InforcerRole -TenantId $script:T1 -OutputType JsonObject).Trim() | Should -Be '[]'
            Set-FixPipeSession -Beta
            (Get-InforcerRole -TenantId 1 -OutputType JsonObject).TrimStart() | Should -BeLike '{*'
        }

        It 'v1 Get-InforcerTenant -TenantId returns a JSON array' {
            Set-FixPipeSession
            (Get-InforcerTenant -TenantId $script:T2 -OutputType JsonObject).TrimStart() | Should -BeLike '`[*'
        }
    }

    Describe 'Get-InforcerTenant lookups' {
        It 'v1: -TenantId <GUID> makes only the detail call' {
            Set-FixPipeSession
            $r = @(Get-InforcerTenant -TenantId $script:T2)
            $r[0].MsTenantId | Should -Be $script:T2
            Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 1 -Exactly
        }

        It 'beta: -TenantId fetches the list fresh once per call (never a stale record)' {
            Set-FixPipeSession -Beta
            $null = Get-InforcerTenant -TenantId 1
            @(Get-InforcerTenant -TenantId 2).TenantFriendlyName | Should -Be @('Fabrikam')
            Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 2 -Exactly -ParameterFilter { $Request.Uri -match '/beta/tenants$' }
        }

        It 'beta: piped -TenantId values share one fresh list call' {
            Set-FixPipeSession -Beta
            $null = @(1, 2 | ForEach-Object { [pscustomobject]@{ ClientTenantId = $_ } } | Get-InforcerTenant)
            Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 1 -Exactly -ParameterFilter { $Request.Uri -match '/beta/tenants$' }
        }

        It 'beta: an unknown id reports TenantNotFound' {
            Set-FixPipeSession -Beta
            $null = Get-InforcerTenant -TenantId 9 -ErrorVariable e -ErrorAction SilentlyContinue
            @($e)[-1].FullyQualifiedErrorId | Should -BeLike 'TenantNotFound*'
        }
    }

    Describe 'Get-InforcerBaselineList cache' {
        It 'fetches once per session, again with -Refresh, and Disconnect-Inforcer clears it' {
            Set-FixPipeSession
            $a = @(& $script:M { Get-InforcerBaselineList })
            $null = & $script:M { Get-InforcerBaselineList }
            $a.Count | Should -Be 2
            Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 1 -Exactly -ParameterFilter { $Request.Uri -match '/v1/baselines$' }
            $null = & $script:M { Get-InforcerBaselineList -Refresh }
            Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 2 -Exactly -ParameterFilter { $Request.Uri -match '/v1/baselines$' }
            $null = Disconnect-Inforcer 6>$null
            & $script:M { $script:InforcerBaselineListCache } | Should -BeNullOrEmpty
        }

        It 'does not cache a failed request' {
            Set-FixPipeSession
            $global:FixPipeRoutes['/v1/baselines$'] = @{ Status = 500; Body = '{"title":"Server error","status":500}' }
            $null = & $script:M { Get-InforcerBaselineList -ErrorAction SilentlyContinue }
            & $script:M { $script:InforcerBaselineListCache } | Should -BeNullOrEmpty
        }

        It 'Select-InforcerBaselinePolicies resolves a baseline name from DocData without calling /baselines' {
            Set-FixPipeSession -Beta
            $docData = @{ TenantId = 2; Policies = @(); Baselines = @([pscustomobject]@{ id = $script:B1; name = 'Contoso Baseline' }) }
            $name = & $script:M { param($d) Select-InforcerBaselinePolicies -DocData $d -BaselineId 'Contoso Baseline' 6>$null 3>$null } $docData
            $name | Should -Be 'Contoso Baseline'
            Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 0 -Exactly -ParameterFilter { $Request.Uri -match '/baselines$' }
        }
    }

    Describe 'Get-InforcerAuditEvent on beta' {
        It 'searches once without an event-type filter and without the event-type lookup' {
            Set-FixPipeSession -Beta
            $e = @(Get-InforcerAuditEvent -DateFrom ([datetime]'2000-01-01') -DateTo ([datetime]'2000-01-02'))
            $e.Count | Should -Be 1
            Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 1 -Exactly
            Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 0 -Exactly -ParameterFilter { $Request.Uri -match 'eventTypes' -or $Request.Body -match 'eventTypes' }
        }

        It 'sends many -EventType values in one search' {
            Set-FixPipeSession -Beta
            $types = 1..12 | ForEach-Object { "type$_" }
            $null = Get-InforcerAuditEvent -EventType $types -DateFrom ([datetime]'2000-01-01') -DateTo ([datetime]'2000-01-02')
            Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 1 -Exactly
            Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 1 -Exactly -ParameterFilter { @(($Request.Body | ConvertFrom-Json).eventTypes).Count -eq 12 }
        }
    }

    Describe 'Get-InforcerUser output metadata' {
        It 'declares [OutputType] and documents .OUTPUTS' {
            @((Get-Command Get-InforcerUser).OutputType.Name) | Should -Contain 'System.String'
            (Get-Help Get-InforcerUser -Full).returnValues | Should -Not -BeNullOrEmpty
        }
    }

    Describe 'Invoke-InforcerAssessmentRun transport' {
        BeforeEach {
            $script:runCalls = 0
            Mock -ModuleName InforcerCommunity Get-InforcerAuthHeader { @{ Authorization = 'Bearer example' } }
            Mock -ModuleName InforcerCommunity Start-Sleep { }
        }

        It 'v1: renews the token once on 401 and retries' {
            Set-FixPipeSession
            Mock -ModuleName InforcerCommunity Invoke-InforcerAssessmentRunRequest {
                $script:runCalls++
                $reply = if ($script:runCalls -eq 1) { [pscustomobject]@{ StatusCode = 401; Body = $null; Headers = @{} } }
                         else { [pscustomobject]@{ StatusCode = 200; Body = [pscustomobject]@{ assessmentId = 'a1'; results = @() }; Headers = @{} } }
                [pscustomobject]@{ Output = @($reply); StreamErrors = @(); Failure = $null }
            }
            $r = & $script:M { Invoke-InforcerAssessmentRun -TenantId '00000000-0000-0000-0000-000000000001' -ResolvedAssessmentId 'a1' -TenantDisplayName 'Contoso' -AssessmentDisplayName 'Example' 6>$null }
            $r.assessment | Should -Be 'a1'
            Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerAssessmentRunRequest -Times 2 -Exactly
            Should -Invoke -ModuleName InforcerCommunity Get-InforcerAuthHeader -Times 1 -Exactly -ParameterFilter { $ForceRefresh }
        }

        It 'v1: a second 401 is reported once, without another renewal' {
            Set-FixPipeSession
            Mock -ModuleName InforcerCommunity Invoke-InforcerAssessmentRunRequest {
                [pscustomobject]@{ Output = @([pscustomobject]@{ StatusCode = 401; Body = $null; Headers = @{} }); StreamErrors = @(); Failure = $null }
            }
            $r = & $script:M { $null = Invoke-InforcerAssessmentRun -TenantId '00000000-0000-0000-0000-000000000001' -ResolvedAssessmentId 'a1' -TenantDisplayName 'Contoso' -AssessmentDisplayName 'Example' -ErrorVariable e -ErrorAction SilentlyContinue 6>$null; $e }
            @($r).Count | Should -Be 1
            "$(@($r)[0])" | Should -Match '401'
            Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerAssessmentRunRequest -Times 2 -Exactly
        }

        It 'v1: waits Retry-After on 429 and retries' {
            Set-FixPipeSession
            Mock -ModuleName InforcerCommunity Invoke-InforcerAssessmentRunRequest {
                $script:runCalls++
                $reply = if ($script:runCalls -eq 1) { [pscustomobject]@{ StatusCode = 429; Body = $null; Headers = @{ 'Retry-After' = @('7') } } }
                         else { [pscustomobject]@{ StatusCode = 200; Body = [pscustomobject]@{ assessmentId = 'a1'; results = @() }; Headers = @{} } }
                [pscustomobject]@{ Output = @($reply); StreamErrors = @(); Failure = $null }
            }
            $r = & $script:M { Invoke-InforcerAssessmentRun -TenantId '00000000-0000-0000-0000-000000000001' -ResolvedAssessmentId 'a1' -TenantDisplayName 'Contoso' -AssessmentDisplayName 'Example' 6>$null }
            $r.assessment | Should -Be 'a1'
            Should -Invoke -ModuleName InforcerCommunity Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 7 }
        }

        It 'beta: a 429 or 401 fails at once, without retry or renewal' -ForEach @(@{ Status = 429 }, @{ Status = 401 }) {
            Set-FixPipeSession -Beta
            $script:runStatus = $Status
            Mock -ModuleName InforcerCommunity Invoke-InforcerAssessmentRunRequest {
                [pscustomobject]@{ Output = @([pscustomobject]@{ StatusCode = $script:runStatus; Body = $null; Headers = @{ 'Retry-After' = @('7') } }); StreamErrors = @(); Failure = $null }
            }
            $r = & $script:M { $null = Invoke-InforcerAssessmentRun -TenantId 1 -ResolvedAssessmentId 'a1' -TenantDisplayName 'Contoso' -AssessmentDisplayName 'Example' -ErrorVariable e -ErrorAction SilentlyContinue 6>$null; $e }
            "$(@($r)[0])" | Should -Match "$Status"
            Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerAssessmentRunRequest -Times 1 -Exactly
            Should -Invoke -ModuleName InforcerCommunity Start-Sleep -Times 0 -Exactly
            Should -Invoke -ModuleName InforcerCommunity Get-InforcerAuthHeader -Times 0 -Exactly -ParameterFilter { $ForceRefresh }
        }

        It '<Mode>: a redirect is reported, not followed' -ForEach @(@{ Mode = 'beta'; Beta = $true; Tid = '1' }, @{ Mode = 'v1'; Beta = $false; Tid = '00000000-0000-0000-0000-000000000001' }) {
            Set-FixPipeSession -Beta:$Beta
            Mock -ModuleName InforcerCommunity Invoke-InforcerAssessmentRunRequest {
                [pscustomobject]@{ Output = @([pscustomobject]@{ StatusCode = 307; Body = $null; Headers = @{ Location = @('https://elsewhere.example.invalid/') } }); StreamErrors = @(); Failure = $null }
            }
            $r = & $script:M { param($t) $null = Invoke-InforcerAssessmentRun -TenantId $t -ResolvedAssessmentId 'a1' -TenantDisplayName 'Contoso' -AssessmentDisplayName 'Example' -ErrorVariable e -ErrorAction SilentlyContinue 6>$null; $e } $Tid
            "$(@($r)[0])" | Should -BeLike '*redirect (HTTP 307)*never sent to another address*'
            Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerAssessmentRunRequest -Times 1 -Exactly
        }

        It 'the runspace call never follows redirects and waits on the run handle' {
            $src = Get-Content (Join-Path $PSScriptRoot '../module/Private/Invoke-InforcerAssessmentRun.ps1') -Raw
            $src | Should -Match 'Invoke-RestMethod[^\r\n]*-MaximumRedirection 0[^\r\n]*-SkipHttpErrorCheck[^\r\n]*-ErrorAction Ignore'
            $src | Should -Match 'AsyncWaitHandle\.WaitOne'
            $src | Should -Not -Match 'Start-Sleep -Milliseconds'
        }
    }

    Describe 'Invoke-InforcerAssessment' {
        BeforeEach {
            Mock -ModuleName InforcerCommunity Invoke-InforcerApiRequest { @([pscustomobject]@{ id = 'a1'; name = 'Example Assessment' }) }
            Mock -ModuleName InforcerCommunity Invoke-InforcerAssessmentRun {
                [pscustomobject]@{ assessment = 'a1'; results = @([pscustomobject]@{ name = '=HYPERLINK("http://example.invalid")'; category = '+cat'; subCategory = '@sub'; importance = 'High'; findings = [pscustomobject]@{ compliant = $true; status = 'pass'; message = '-1+1'; scores = @() } }) }
            }
        }

        It '<Mode>: two piped tenants run as one multi-tenant call with TenantId on every check' -ForEach @(
            @{ Mode = 'beta'; Beta = $true; Ids = @(1, 2) }
            @{ Mode = 'v1'; Beta = $false; Ids = @('00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000002') }
        ) {
            Set-FixPipeSession -Beta:$Beta
            $checks = @(Get-FixPipeTenants -Beta:$Beta | Invoke-InforcerAssessment -AssessmentId 'a1' 6>$null)
            @($checks.TenantId) | Should -Be $Ids
            $json = @(Get-FixPipeTenants -Beta:$Beta | Invoke-InforcerAssessment -AssessmentId 'a1' -OutputType JsonObject 6>$null)
            $json.Count | Should -Be 1
            @(($json[0] | ConvertFrom-Json).TenantId) | Should -Be $Ids
            Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerAssessmentRun -Times 4 -Exactly
        }

        It '<Mode>: one piped tenant adds TenantId to its checks; a non-piped call does not' -ForEach @(
            @{ Mode = 'beta'; Beta = $true; Id = 1 }
            @{ Mode = 'v1'; Beta = $false; Id = '00000000-0000-0000-0000-000000000001' }
        ) {
            Set-FixPipeSession -Beta:$Beta
            $checks = @(Get-FixPipeTenants -Beta:$Beta -Index 1 | Invoke-InforcerAssessment -AssessmentId 'a1' 6>$null)
            $checks[0].TenantId | Should -Be $Id
            @(Invoke-InforcerAssessment -TenantId $Id -AssessmentId 'a1' 6>$null)[0].PSObject.Properties['TenantId'] | Should -BeNullOrEmpty
        }

        It 'neutralises formula-leading CSV values in <Mode> CSV' -ForEach @(
            @{ Mode = 'single-tenant'; TenantIds = @(1) }
            @{ Mode = 'multi-tenant'; TenantIds = @(1, 2) }
        ) {
            Set-FixPipeSession -Beta
            $path = Join-Path $TestDrive "report-$Mode.csv"
            $null = Invoke-InforcerAssessment -TenantId $TenantIds -AssessmentId 'a1' -OutputPath $path 6>$null
            $rows = @(Import-Csv $path)
            $rows[0].Name | Should -BeExactly "'=HYPERLINK(""http://example.invalid"")"
            $rows[0].Category | Should -BeExactly "'+cat"
            $rows[0].SubCategory | Should -BeExactly "'@sub"
            $rows[0].FindingsMessage | Should -BeExactly "'-1+1"
            $rows[0].Importance | Should -BeExactly 'High'
        }

        It 'looks tenant names up in a map, not by scanning the list per tenant' {
            $src = Get-Content (Join-Path $PSScriptRoot '../module/Public/Invoke-InforcerAssessment.ps1') -Raw
            $src | Should -Match '\$tenantNames\.ContainsKey'
            $src | Should -Not -Match 'param\(\$cid, \[array\]\$data\)'
        }
    }
}
