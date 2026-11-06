# V1.Tenants.Tests.ps1
# Get-InforcerTenant, Get-InforcerBaseline, Get-InforcerAlignmentDetails and Resolve-InforcerBaselineId
# on both logins. Invoke-InforcerHttpRequest is mocked, so the real request, unwrap and v1 mapping run.
# Fixtures are anonymised (zero GUIDs, example names); no network calls.

BeforeAll {
    Remove-Module -Name 'InforcerCommunity' -ErrorAction SilentlyContinue
    Import-Module (Join-Path $PSScriptRoot '../module/InforcerCommunity.psd1') -Force
    $script:M = Get-Module InforcerCommunity

    $script:T1 = '00000000-0000-0000-0000-000000000001'
    $script:T2 = '00000000-0000-0000-0000-000000000002'
    $script:B1 = '00000000-0000-0000-0000-0000000000b1'
    $script:B2 = '00000000-0000-0000-0000-0000000000b2'

    function global:Reset-V1TenantsRoutes {
        $global:V1TenantsRoutes = [ordered]@{
            # v1 (client credentials)
            '/v1/tenants$' = '{"tenants":[{"msTenantId":"00000000-0000-0000-0000-000000000001","name":"Contoso","dnsName":"contoso.onmicrosoft.com","secureScore":50.5,"isBaseline":true,"lastBackupTimestamp":"2026-01-01T00:00:00Z","recentChanges":0,"policyDiff":null,"tags":[{"name":"Production","description":"Live tenants"}],"alignmentSummaries":[],"licenses":[{"sku":"SPE_E5"}]},{"msTenantId":"00000000-0000-0000-0000-000000000002","name":"Fabrikam","dnsName":"fabrikam.onmicrosoft.com","secureScore":40,"isBaseline":false,"lastBackupTimestamp":"2026-01-01T00:00:00Z","recentChanges":1,"policyDiff":null,"tags":[{"name":"Test","description":""}],"alignmentSummaries":[{"alignedBaselineId":"00000000-0000-0000-0000-0000000000b1","alignedBaselineMsTenantId":"00000000-0000-0000-0000-000000000001","alignedBaselineName":"Contoso Baseline","alignmentScore":80.5,"alignedThreshold":90,"semiAlignedThreshold":70,"lastAlignmentTimestamp":"2026-01-02T00:00:00Z"}],"licenses":[{"sku":"SPE_E3"},{"sku":"EMS"}]}]}'
            '/v1/tenants/00000000-0000-0000-0000-000000000001$' = '{"msTenantId":"00000000-0000-0000-0000-000000000001","name":"Contoso","dnsName":"contoso.onmicrosoft.com","secureScore":50.5,"isBaseline":true,"lastBackupTimestamp":"2026-01-01T00:00:00Z","recentChanges":0,"policyDiff":null,"tags":[{"name":"Production","description":"Live tenants"}],"alignmentSummaries":[],"licenses":[{"sku":"SPE_E5"}],"authenticationMode":"Standard"}'
            '/v1/tenants/00000000-0000-0000-0000-000000000002$' = '{"msTenantId":"00000000-0000-0000-0000-000000000002","name":"Fabrikam","dnsName":"fabrikam.onmicrosoft.com","secureScore":40,"isBaseline":false,"lastBackupTimestamp":"2026-01-01T00:00:00Z","recentChanges":1,"policyDiff":null,"tags":[{"name":"Test","description":""}],"alignmentSummaries":[{"alignedBaselineId":"00000000-0000-0000-0000-0000000000b1","alignedBaselineMsTenantId":"00000000-0000-0000-0000-000000000001","alignedBaselineName":"Contoso Baseline","alignmentScore":80.5,"alignedThreshold":90,"semiAlignedThreshold":70,"lastAlignmentTimestamp":"2026-01-02T00:00:00Z"}],"licenses":[{"sku":"SPE_E3"},{"sku":"EMS"}],"authenticationMode":"Standard"}'
            '/v1/baselines$' = '{"baselines":[{"id":"00000000-0000-0000-0000-0000000000b1","name":"Contoso Baseline","description":"","baselineTenant":{"msTenantId":"00000000-0000-0000-0000-000000000001","name":"Contoso","dnsName":"contoso.onmicrosoft.com"},"mode":"Monitor","alignedThreshold":90,"semiAlignedThreshold":70,"autoAddNewPolicies":false,"isComplete":true,"isShared":false,"isSharedCopy":false,"members":[{"msTenantId":"00000000-0000-0000-0000-000000000002","name":"Fabrikam","dnsName":"fabrikam.onmicrosoft.com","lastAlignmentScore":80.5,"lastAlignmentTimestamp":"2026-01-02T00:00:00Z"}],"items":[]},{"id":"00000000-0000-0000-0000-0000000000b2","name":"Other Baseline","description":"","baselineTenant":{"msTenantId":"00000000-0000-0000-0000-000000000003","name":"Northwind","dnsName":"northwind.onmicrosoft.com"},"mode":"Monitor","alignedThreshold":90,"semiAlignedThreshold":70,"autoAddNewPolicies":false,"isComplete":true,"isShared":true,"isSharedCopy":false,"members":[{"msTenantId":"00000000-0000-0000-0000-000000000001","name":"Contoso","dnsName":"contoso.onmicrosoft.com","lastAlignmentScore":100,"lastAlignmentTimestamp":"2026-01-02T00:00:00Z"}],"items":[]}]}'
            '/v1/alignmentScores$' = '{"alignmentScores":[{"msTenantId":"00000000-0000-0000-0000-000000000002","tenantName":"Fabrikam","alignedBaselineId":"00000000-0000-0000-0000-0000000000b1","alignedBaselineName":"Contoso Baseline","alignmentScore":80.5,"lastAlignmentTimestamp":"2026-01-02T00:00:00Z"},{"msTenantId":"00000000-0000-0000-0000-000000000001","tenantName":"Contoso","alignedBaselineId":"00000000-0000-0000-0000-0000000000b2","alignedBaselineName":"Other Baseline","alignmentScore":100,"lastAlignmentTimestamp":"2026-01-02T00:00:00Z"}]}'
            '/v1/tenants/[^/]+/alignmentDetails\?baselineId=' = '{"completedAt":"2026-01-02T00:00:00Z","baseline":{"id":"00000000-0000-0000-0000-0000000000b1","name":"Contoso Baseline"},"baselineDataTimestamp":"2026-01-01T00:00:00Z","tenantDataTimestamp":"2026-01-01T00:00:00Z","alignmentScore":80.5,"metrics":{"totalPolicies":2,"matched":1,"matchedWithAcceptedDeviations":0,"deviated":1,"missingFromTenant":0,"additionalInTenant":0},"policies":{"matched":[{"id":"p1","policyTypeId":1,"policyTypeName":"Settings Catalog","displayName":"Policy A","friendlyName":"Policy A","description":"","readOnly":false,"product":"Intune","primaryGroup":"Devices","secondaryGroup":"Windows","platform":"Windows","tags":[{"name":"Tier1","description":""}],"tenantPolicies":[],"variables":[],"acceptedDeviations":[],"similarPolicies":[]}],"matchedWithAcceptedDeviations":[],"deviated":[{"id":"p2","policyTypeId":1,"policyTypeName":"Settings Catalog","displayName":"Policy B","friendlyName":"Policy B","description":"","readOnly":false,"product":"Intune","primaryGroup":"Devices","secondaryGroup":"Windows","platform":"Windows","tags":[],"tenantPolicies":[],"variables":[],"acceptedDeviations":[],"similarPolicies":[]}],"missingFromTenant":[],"additionalInTenant":[]}}'
            # beta (API key)
            '/beta/tenants$' = '{"success":true,"data":[{"clientTenantId":1,"msTenantId":"00000000-0000-0000-0000-000000000001","tenantFriendlyName":"Contoso","tenantDnsName":"contoso.onmicrosoft.com","licenses":[{"sku":"SPE_E5"}],"secureScore":50.5,"isBaseline":true,"lastBackupTimestamp":"2026-01-01T00:00:00Z","recentChanges":0,"policyDiff":null,"tags":[],"alignmentSummaries":[{"alignedBaselineId":"00000000-0000-0000-0000-0000000000b2","alignedBaselineName":"Other Baseline","alignedBaselineTenantId":3,"alignmentScore":100,"alignedThreshold":90,"semiAlignedThreshold":70,"lastAlignmentDateTime":"2026-01-02T00:00:00Z"}]},{"clientTenantId":2,"msTenantId":"00000000-0000-0000-0000-000000000002","tenantFriendlyName":"Fabrikam","tenantDnsName":"fabrikam.onmicrosoft.com","licenses":[{"sku":"SPE_E3"},{"sku":"EMS"}],"secureScore":40,"isBaseline":false,"lastBackupTimestamp":"2026-01-01T00:00:00Z","recentChanges":1,"policyDiff":null,"tags":[],"alignmentSummaries":[{"alignedBaselineId":"00000000-0000-0000-0000-0000000000b1","alignedBaselineName":"Contoso Baseline","alignedBaselineTenantId":1,"alignmentScore":80.5,"alignedThreshold":90,"semiAlignedThreshold":70,"lastAlignmentDateTime":"2026-01-02T00:00:00Z"}]},{"clientTenantId":2,"msTenantId":"00000000-0000-0000-0000-000000000002","tenantFriendlyName":"Fabrikam","tenantDnsName":"fabrikam.onmicrosoft.com","licenses":[],"secureScore":40,"isBaseline":false,"lastBackupTimestamp":null,"recentChanges":0,"policyDiff":null,"tags":[],"alignmentSummaries":[]}]}'
            '/beta/baselines$' = '{"success":true,"data":[{"id":"00000000-0000-0000-0000-0000000000b1","name":"Contoso Baseline","baselineClientTenantId":1,"baselineMsTenantId":"00000000-0000-0000-0000-000000000001","baselineTenantFriendlyName":"Contoso","baselineTenantDnsName":"contoso.onmicrosoft.com","mode":"Monitor","alignedThreshold":90,"semiAlignedThreshold":70,"autoAddNewPolicies":false,"isComplete":true,"isShared":false,"members":[{"clientTenantId":2,"msTenantId":"00000000-0000-0000-0000-000000000002","tenantFriendlyName":"Fabrikam","tenantDnsName":"fabrikam.onmicrosoft.com"}],"items":[]},{"id":"00000000-0000-0000-0000-0000000000b2","name":"Other Baseline","baselineClientTenantId":3,"baselineMsTenantId":"00000000-0000-0000-0000-000000000003","baselineTenantFriendlyName":"Northwind","baselineTenantDnsName":"northwind.onmicrosoft.com","mode":"Monitor","alignedThreshold":90,"semiAlignedThreshold":70,"autoAddNewPolicies":false,"isComplete":true,"isShared":true,"members":[{"clientTenantId":1,"msTenantId":"00000000-0000-0000-0000-000000000001","tenantFriendlyName":"Contoso","tenantDnsName":"contoso.onmicrosoft.com"}],"items":[]}]}'
            '/beta/alignmentScores$' = '{"success":true,"data":[{"tenantId":2,"tenantFriendlyName":"Fabrikam","score":80.5,"baselineGroupId":"00000000-0000-0000-0000-0000000000b1","baselineGroupName":"Contoso Baseline","lastComparisonDateTime":"2026-01-02T00:00:00Z"},{"tenantId":1,"tenantFriendlyName":"Contoso","score":100,"baselineGroupId":"00000000-0000-0000-0000-0000000000b2","baselineGroupName":"Other Baseline","lastComparisonDateTime":"2026-01-02T00:00:00Z"}]}'
            '/beta/tenants/\d+/alignmentDetails\?customBaselineId=' = '{"success":true,"data":{"metrics":{"totalPolicies":2,"matchedPolicies":1,"matchedWithAcceptedDeviations":0,"deviatedPolicies":1,"recommendedPoliciesFromBaseline":0,"customerOnlyPolicies":0},"completedAt":"2026-01-02T00:00:00Z","alignment":{"alignmentScore":80.5,"matchedPolicies":[{"policyName":"Policy A","product":"Intune","primaryGroup":"Devices","secondaryGroup":"Windows","inforcerPolicyTypeName":"Settings Catalog","policyTags":[{"name":"Tier1"}]}],"matchedWithAcceptedDeviations":[],"deviatedUnaccepted":[{"policyName":"Policy B","product":"Intune","primaryGroup":"Devices","secondaryGroup":"Windows","inforcerPolicyTypeName":"Settings Catalog","policyTags":[]}],"missingFromSubjectUnaccepted":[],"additionalInSubjectUnaccepted":[]}}}'
        }
    }

    function global:Get-V1TenantsResponse([string]$Uri) {
        foreach ($pattern in $global:V1TenantsRoutes.Keys) {
            if ($Uri -notmatch $pattern) { continue }
            $route = $global:V1TenantsRoutes[$pattern]
            $status = 200
            if ($route -is [hashtable]) { $status = $route.Status; $route = $route.Body }
            return [pscustomobject]@{ StatusCode = $status; Body = ($route | ConvertFrom-Json -Depth 100); Headers = @{} }
        }
        [pscustomobject]@{ StatusCode = 404; Body = [pscustomobject]@{ title = 'Not Found'; status = 404 }; Headers = @{} }
    }

    function global:Set-V1TenantsSession {
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
}

AfterAll {
    foreach ($f in 'Reset-V1TenantsRoutes', 'Get-V1TenantsResponse', 'Set-V1TenantsSession') { Remove-Item "function:global:$f" -ErrorAction SilentlyContinue }
    Remove-Variable -Name V1TenantsRoutes -Scope Global -ErrorAction SilentlyContinue
    & (Get-Module InforcerCommunity) { $script:InforcerSession = $null; $script:InforcerTenantListCache = $null }
}

Describe 'Tenants and alignment on both logins' {
BeforeEach {
    Reset-V1TenantsRoutes
    Mock -ModuleName InforcerCommunity Invoke-InforcerHttpRequest { Get-V1TenantsResponse $Request.Uri }
}

Describe 'Get-InforcerTenant' {
    It 'v1: the list holds every field with canonical names and makes no per-tenant calls' {
        Set-V1TenantsSession
        $r = @(Get-InforcerTenant)
        $r.Count | Should -Be 2
        $r[0].TenantFriendlyName | Should -BeExactly 'Contoso'
        $r[0].TenantDnsName | Should -BeExactly 'contoso.onmicrosoft.com'
        $r[0].MsTenantId | Should -Be $script:T1
        $r[0].PSObject.Properties['clientTenantId'] | Should -BeNullOrEmpty
        $r[0].PSObject.Properties['name'] | Should -BeNullOrEmpty
        $r[0].IsBaseline | Should -BeTrue
        $r[0].licenses | Should -BeExactly 'SPE_E5'
        $r[1].licenses | Should -BeExactly 'SPE_E3, EMS'
        $r[0].Tags[0].name | Should -BeExactly 'Production'
        $r[1].alignmentSummaries[0].PSObject.Properties.Name | Should -Contain 'lastAlignmentDateTime'
        $r[0].PSObject.TypeNames[0] | Should -Be 'InforcerCommunity.Tenant'
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 1 -Exactly
    }

    It 'v1: -OutputType JsonObject returns a JSON array with the raw licenses array' {
        Set-V1TenantsSession
        $json = Get-InforcerTenant -OutputType JsonObject
        $json.TrimStart() | Should -BeLike '`[*'
        $parsed = @($json | ConvertFrom-Json -Depth 100)
        $parsed.Count | Should -Be 2
        @($parsed[1].licenses).Count | Should -Be 2
        $parsed[0].tenantFriendlyName | Should -BeExactly 'Contoso'
    }

    It 'v1: -TenantId <name> returns the single detailed tenant' {
        Set-V1TenantsSession
        $r = @(Get-InforcerTenant -TenantId 'Fabrikam')
        $r.Count | Should -Be 1
        $r[0].MsTenantId | Should -Be $script:T2
        $r[0].IsBaseline | Should -BeFalse
        $r[0].PSObject.Properties['isBaseline'] | Should -Not -BeNullOrEmpty
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 1 -Exactly -ParameterFilter { $Request.Uri -match '/v1/tenants/00000000-0000-0000-0000-000000000002$' }
    }

    It 'v1: an unknown GUID is TenantNotFound after one detail call and no list call; a numeric id is InvalidTenantId' {
        Set-V1TenantsSession
        $null = Get-InforcerTenant -TenantId '00000000-0000-0000-0000-000000000009' -ErrorVariable e1 -ErrorAction SilentlyContinue
        @($e1)[-1].FullyQualifiedErrorId | Should -BeLike 'TenantNotFound*'
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 1 -Exactly -ParameterFilter { $Request.Uri -match '/v1/tenants/[0-9a-f-]{36}$' }
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 0 -Exactly -ParameterFilter { $Request.Uri -match '/v1/tenants$' }
        $null = Get-InforcerTenant -TenantId 482 -ErrorVariable e2 -ErrorAction SilentlyContinue
        @($e2 | Where-Object { $_.FullyQualifiedErrorId -like 'InvalidTenantId*' }).Count | Should -Be 1
        $e2[0].Exception.Message | Should -Match 'API key'
    }

    It 'beta: PowerShell output dedupes by ClientTenantId; JSON keeps the API list; -TenantId numeric filters' {
        Set-V1TenantsSession -Beta
        $r = @(Get-InforcerTenant)
        $r.ClientTenantId | Should -Be @(1, 2)
        $r[1].licenses | Should -BeExactly 'SPE_E3, EMS'
        @(Get-InforcerTenant -OutputType JsonObject | ConvertFrom-Json).Count | Should -Be 3
        @(Get-InforcerTenant -TenantId 2).TenantFriendlyName | Should -Be @('Fabrikam')
    }

    It 'never modifies the cached tenant list objects' {
        Set-V1TenantsSession -Beta
        $null = Get-InforcerTenant
        $cached = & $script:M { $script:InforcerTenantListCache.Tenants }
        $cached[0].licenses | Should -Not -BeOfType [string]
        $cached[0].licenses[0].sku | Should -BeExactly 'SPE_E5'
        $cached[0].PSObject.TypeNames | Should -Not -Contain 'InforcerCommunity.Tenant'
    }

}

Describe 'Resolve-InforcerTenantId with the cached tenant list' {
    BeforeAll {
        $script:BetaWithNorthwind = '{"success":true,"data":[{"clientTenantId":1,"msTenantId":"00000000-0000-0000-0000-000000000001","tenantFriendlyName":"Contoso","tenantDnsName":"contoso.onmicrosoft.com"},{"clientTenantId":3,"msTenantId":"00000000-0000-0000-0000-000000000003","tenantFriendlyName":"Northwind","tenantDnsName":"northwind.onmicrosoft.com"}]}'
        $script:V1WithNorthwind = '{"tenants":[{"msTenantId":"00000000-0000-0000-0000-000000000001","name":"Contoso","dnsName":"contoso.onmicrosoft.com"},{"msTenantId":"00000000-0000-0000-0000-000000000003","name":"Northwind","dnsName":"northwind.onmicrosoft.com"}]}'
    }

    It 'beta: finds a tenant onboarded after the list was cached, by <Name>, with one refresh' -ForEach @(
        @{ Name = 'name'; Id = 'Northwind' }
        @{ Name = 'GUID'; Id = '00000000-0000-0000-0000-000000000003' }
    ) {
        Set-V1TenantsSession -Beta
        & $script:M { Resolve-InforcerTenantId -TenantId 'Contoso' } | Should -Be 1
        $global:V1TenantsRoutes['/beta/tenants$'] = $script:BetaWithNorthwind
        & $script:M { param($i) Resolve-InforcerTenantId -TenantId $i } $Id | Should -Be 3
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 2 -Exactly -ParameterFilter { $Request.Uri -match '/beta/tenants$' }
    }

    It 'v1: finds a tenant name onboarded after the list was cached' {
        Set-V1TenantsSession
        & $script:M { Resolve-InforcerTenantId -TenantId 'Contoso' } | Should -Be $script:T1
        $global:V1TenantsRoutes['/v1/tenants$'] = $script:V1WithNorthwind
        & $script:M { Resolve-InforcerTenantId -TenantId 'Northwind' } | Should -BeExactly '00000000-0000-0000-0000-000000000003'
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 2 -Exactly -ParameterFilter { $Request.Uri -match '/v1/tenants$' }
    }

    It 'fetches only once when the list was not cached, and still reports an unknown name' {
        Set-V1TenantsSession -Beta
        { & $script:M { Resolve-InforcerTenantId -TenantId 'Nope' } } | Should -Throw "*No tenant found with name 'Nope'*"
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 1 -Exactly -ParameterFilter { $Request.Uri -match '/beta/tenants$' }
    }

    It 'refreshes at most once for an unknown name on a cached list' {
        Set-V1TenantsSession -Beta
        $null = & $script:M { Resolve-InforcerTenantId -TenantId 'Contoso' }
        { & $script:M { Resolve-InforcerTenantId -TenantId 'Nope' } } | Should -Throw "*No tenant found with name 'Nope'*"
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 2 -Exactly -ParameterFilter { $Request.Uri -match '/beta/tenants$' }
    }

    It 'does not refresh when the caller passes -TenantData' {
        Set-V1TenantsSession -Beta
        $null = & $script:M { Resolve-InforcerTenantId -TenantId 'Contoso' }
        $data = @([pscustomobject]@{ clientTenantId = 1; tenantFriendlyName = 'Contoso' })
        { & $script:M { param($d) Resolve-InforcerTenantId -TenantId 'Nope' -TenantData $d } $data } | Should -Throw '*No tenant found*'
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 1 -Exactly -ParameterFilter { $Request.Uri -match '/beta/tenants$' }
    }
}

Describe 'Pipeline binding of -TenantId (ClientTenantId / MsTenantId aliases)' {
    It 'declares both aliases on every -TenantId parameter in this area' {
        foreach ($name in 'Get-InforcerTenant', 'Get-InforcerBaseline', 'Get-InforcerAlignmentDetails') {
            $aliases = (Get-Command $name).Parameters['TenantId'].Aliases
            $aliases | Should -Contain 'ClientTenantId'
            $aliases | Should -Contain 'MsTenantId'
        }
    }

    It 'beta: an object carrying clientTenantId and msTenantId binds the clientTenantId' {
        Set-V1TenantsSession -Beta
        # clientTenantId 2 is Fabrikam; msTenantId T1 is Contoso. Binding the GUID would return Contoso.
        $r = @([pscustomobject]@{ clientTenantId = 2; msTenantId = $script:T1 } | Get-InforcerTenant)
        $r.TenantFriendlyName | Should -Be @('Fabrikam')
    }

    It 'v1: an object carrying only msTenantId binds it' {
        Set-V1TenantsSession
        $r = @([pscustomobject]@{ msTenantId = $script:T2; tenantFriendlyName = 'Fabrikam' } | Get-InforcerTenant)
        $r.Count | Should -Be 1
        $r[0].MsTenantId | Should -Be $script:T2
        $r[0].IsBaseline | Should -BeFalse
    }

    It 'pipes Get-InforcerTenant output into Get-InforcerBaseline in both modes' {
        Set-V1TenantsSession
        @(Get-InforcerTenant -TenantId 'Fabrikam' | Get-InforcerBaseline).BaselineId | Should -Be @($script:B1)
        Set-V1TenantsSession -Beta
        @(Get-InforcerTenant -TenantId 2 | Get-InforcerBaseline).BaselineId | Should -Be @($script:B1)
    }
}

Describe 'Get-InforcerBaseline' {
    It 'v1: -TenantId -OutputType JsonObject stays a JSON array for one match and for none' {
        Set-V1TenantsSession
        $one = Get-InforcerBaseline -TenantId $script:T2 -OutputType JsonObject
        $one.TrimStart() | Should -BeLike '`[*'
        ($one | ConvertFrom-Json -NoEnumerate).Count | Should -Be 1
        $global:V1TenantsRoutes['/v1/tenants$'] = '{"tenants":[{"msTenantId":"00000000-0000-0000-0000-000000000009","name":"Lonely","dnsName":"lonely.onmicrosoft.com"}]}'
        & $script:M { $script:InforcerTenantListCache = $null }
        $none = Get-InforcerBaseline -TenantId '00000000-0000-0000-0000-000000000009' -OutputType JsonObject
        $none.Trim() | Should -Be '[]'
    }

    It 'v1: maps the owner and members to the module names' {
        Set-V1TenantsSession
        $r = @(Get-InforcerBaseline)
        $r.Count | Should -Be 2
        $r[0].BaselineMsTenantId | Should -Be $script:T1
        $r[0].BaselineTenantFriendlyName | Should -BeExactly 'Contoso'
        $r[0].PSObject.Properties['baselineTenant'] | Should -BeNullOrEmpty
        $r[0].PSObject.Properties['baselineClientTenantId'] | Should -BeNullOrEmpty
        $r[0].members[0].tenantFriendlyName | Should -BeExactly 'Fabrikam'
        $r[0].BaselineName | Should -BeExactly 'Contoso Baseline'
    }

    It 'v1: -TenantId filters on owner and member msTenantId, by GUID and by name' {
        Set-V1TenantsSession
        @(Get-InforcerBaseline -TenantId $script:T2).id | Should -Be @($script:B1)
        @(Get-InforcerBaseline -TenantId 'Contoso').id | Should -Be @($script:B1, $script:B2)
    }

    It 'v1: -TenantId with -OutputType JsonObject returns filtered JSON with module names' {
        Set-V1TenantsSession
        $parsed = @(Get-InforcerBaseline -TenantId $script:T2 -OutputType JsonObject | ConvertFrom-Json -Depth 100)
        $parsed.Count | Should -Be 1
        $parsed[0].baselineTenantFriendlyName | Should -BeExactly 'Contoso'
        $parsed[0].members[0].msTenantId | Should -Be $script:T2
    }

    It 'beta: -TenantId numeric still filters on clientTenantId' {
        Set-V1TenantsSession -Beta
        @(Get-InforcerBaseline -TenantId 2).id | Should -Be @($script:B1)
        @(Get-InforcerBaseline -TenantId 1).id | Should -Be @($script:B1, $script:B2)
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 0 -Exactly -ParameterFilter { $Request.Uri -match '/v1/' }
    }
}

Describe 'Resolve-InforcerBaselineId' {
    It 'v1: resolves a baseline name case-insensitively through the neutral /baselines endpoint' {
        Set-V1TenantsSession
        & $script:M { Resolve-InforcerBaselineId -BaselineId 'contoso baseline' } | Should -Be $script:B1
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 1 -Exactly -ParameterFilter { $Request.Uri -eq 'https://api.example.invalid/v1/baselines' }
    }
}

Describe 'Get-InforcerAlignmentDetails' {
    It 'v1: the scores table carries TargetTenantMsTenantId and no client tenant id' {
        Set-V1TenantsSession
        $r = @(Get-InforcerAlignmentDetails)
        $r.Count | Should -Be 2
        $r[0].PSObject.Properties.Name | Should -Be @('TargetTenantFriendlyName', 'TargetTenantMsTenantId', 'AlignmentScore', 'BaselineName', 'BaselineId', 'LastComparisonDateTime')
        $r[0].TargetTenantMsTenantId | Should -Be $script:T2
        $r[0].AlignmentScore | Should -BeOfType [double]
        $r[0].AlignmentScore | Should -Be 80.5
        $r[0].BaselineId | Should -Be $script:B1
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 1 -Exactly
    }

    It 'beta: the scores table shape is unchanged' {
        Set-V1TenantsSession -Beta
        $r = @(Get-InforcerAlignmentDetails)
        $r.Count | Should -Be 2
        $r[0].PSObject.Properties.Name | Should -Be @('TargetTenantFriendlyName', 'TargetTenantClientTenantId', 'AlignmentScore', 'BaselineName', 'BaselineId', 'LastComparisonDateTime')
        $r[0].TargetTenantClientTenantId | Should -BeOfType [int]
        $r[0].TargetTenantClientTenantId | Should -Be 2
        (Get-InforcerAlignmentDetails -OutputType JsonObject).TrimStart() | Should -BeLike '`[*'
    }

    It '-TenantId of a baseline owner includes the tenants aligned to it, in both modes' {
        Set-V1TenantsSession
        @(Get-InforcerAlignmentDetails -TenantId $script:T1).TargetTenantMsTenantId | Sort-Object | Should -Be @($script:T1, $script:T2)
        @(Get-InforcerAlignmentDetails -TenantId 'Fabrikam').TargetTenantMsTenantId | Should -Be @($script:T2)
        Set-V1TenantsSession -Beta
        @(Get-InforcerAlignmentDetails -TenantId 1).TargetTenantClientTenantId | Sort-Object | Should -Be @(1, 2)
        @(Get-InforcerAlignmentDetails -TenantId 2).TargetTenantClientTenantId | Should -Be @(2)
    }

    It 'v1: -Tag matches the tag name from the tenant list, with no per-tenant calls' {
        Set-V1TenantsSession
        $r = @(Get-InforcerAlignmentDetails -Tag 'prod' -WarningVariable w)
        $r.TargetTenantMsTenantId | Should -Be @($script:T1)
        $w | Should -BeNullOrEmpty
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 0 -Exactly -ParameterFilter { $Request.Uri -match '/v1/tenants/[0-9a-f-]{36}$' }
        @(Get-InforcerAlignmentDetails -Tag 'Test').TargetTenantMsTenantId | Should -Be @('00000000-0000-0000-0000-000000000002')
    }

    It '<Mode>: -Tag that matches no tenant returns no rows and warns' -ForEach @(
        @{ Mode = 'v1'; Beta = $false }
        @{ Mode = 'beta'; Beta = $true }
    ) {
        Set-V1TenantsSession -Beta:$Beta
        @(Get-InforcerAlignmentDetails).Count | Should -BeGreaterThan 0
        $r = @(Get-InforcerAlignmentDetails -Tag 'zz-no-such-tag' -WarningVariable w -WarningAction SilentlyContinue)
        $r.Count | Should -Be 0
        "$($w[0])" | Should -Match "zz-no-such-tag"
    }

    It 'v1: -TenantId plus a -Tag another tenant has returns no rows and no tag warning' {
        Set-V1TenantsSession
        $r = @(Get-InforcerAlignmentDetails -TenantId 'Contoso' -Tag 'Test' -WarningVariable w -WarningAction SilentlyContinue)
        $r.Count | Should -Be 0
        $w | Should -BeNullOrEmpty
    }

    It 'v1: piped tenants that do not exist return no rows, not every row' {
        Set-V1TenantsSession
        $r = @([pscustomobject]@{ MsTenantId = '00000000-0000-0000-0000-000000000009' } | Get-InforcerAlignmentDetails -ErrorAction SilentlyContinue)
        $r.Count | Should -Be 0
    }

    It 'v1: -Format Raw -TenantId filters on msTenantId in both output types' {
        Set-V1TenantsSession
        $r = @(Get-InforcerAlignmentDetails -Format Raw -TenantId $script:T2)
        $r.Count | Should -Be 1
        $r[0].tenantFriendlyName | Should -BeExactly 'Fabrikam'
        $r[0].score | Should -Be 80.5
        $r[0].PSObject.TypeNames[0] | Should -Be 'InforcerCommunity.AlignmentScoreRaw'
        $parsed = @(Get-InforcerAlignmentDetails -Format Raw -TenantId 'Contoso' -OutputType JsonObject | ConvertFrom-Json -Depth 100)
        $parsed.msTenantId | Should -Be @($script:T1)
    }

    It 'v1: -BaselineId <name> without -TenantId queries the first member by msTenantId' {
        Set-V1TenantsSession
        $r = @(Get-InforcerAlignmentDetails -BaselineId 'Contoso Baseline' 6>$null)
        ($r | Sort-Object PolicyName).AlignmentStatus | Should -Be @('Aligned', 'Unaccepted Deviation')
        $r[0].PSObject.TypeNames[0] | Should -Be 'InforcerCommunity.AlignmentDetailPolicy'
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 1 -Exactly -ParameterFilter { $Request.Uri -eq 'https://api.example.invalid/v1/tenants/00000000-0000-0000-0000-000000000002/alignmentDetails?baselineId=00000000-0000-0000-0000-0000000000b1' }
    }

    It 'returns the same detail rows and raw metrics on v1 and beta' {
        Set-V1TenantsSession
        $vRows = @(Get-InforcerAlignmentDetails -TenantId 'Fabrikam' -BaselineId $script:B1 6>$null) | Sort-Object PolicyName | ConvertTo-Json -Depth 5
        $vRaw = Get-InforcerAlignmentDetails -TenantId $script:T2 -BaselineId $script:B1 -Format Raw -OutputType JsonObject | ConvertFrom-Json -Depth 100
        Set-V1TenantsSession -Beta
        $bRows = @(Get-InforcerAlignmentDetails -TenantId 2 -BaselineId $script:B1 6>$null) | Sort-Object PolicyName | ConvertTo-Json -Depth 5
        $bRaw = Get-InforcerAlignmentDetails -TenantId 2 -BaselineId $script:B1 -Format Raw -OutputType JsonObject | ConvertFrom-Json -Depth 100
        $vRows | Should -BeExactly $bRows
        ($vRaw.metrics | ConvertTo-Json -Compress) | Should -BeExactly ($bRaw.metrics | ConvertTo-Json -Compress)
        $vRaw.alignment.matchedPolicies[0].policyName | Should -BeExactly 'Policy A'
        @($vRaw.alignment.deviatedUnaccepted).Count | Should -Be @($bRaw.alignment.deviatedUnaccepted).Count
    }

    It 'v1: a numeric -TenantId with -BaselineId is InvalidTenantId and calls no detail endpoint' {
        Set-V1TenantsSession
        $null = Get-InforcerAlignmentDetails -TenantId 139 -BaselineId $script:B1 -ErrorVariable e -ErrorAction SilentlyContinue 6>$null
        @($e | Where-Object { $_.FullyQualifiedErrorId -like 'InvalidTenantId*' }).Count | Should -Be 1
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 0 -Exactly -ParameterFilter { $Request.Uri -match 'alignmentDetails' }
    }
}

Describe 'Format.ps1xml views' {
    It 'Tenant: beta shows ClientTenantId; v1 shows MsTenantId, and AuthenticationMode only on the -TenantId record' {
        Set-V1TenantsSession -Beta
        $beta = @(Get-InforcerTenant)[0] | Format-List | Out-String
        $beta | Should -Match 'ClientTenantId\s+: 1'
        $beta | Should -Match 'licenses\s+: SPE_E5'
        $beta | Should -Not -Match 'AuthenticationMode'
        Set-V1TenantsSession
        $list = @(Get-InforcerTenant)[0] | Format-List | Out-String
        $list | Should -Not -Match 'ClientTenantId|AuthenticationMode'
        $list | Should -Match 'IsBaseline\s+: True'
        $list | Should -Match "MsTenantId\s+: $($script:T1)"
        $detail = Get-InforcerTenant -TenantId 'Contoso' | Format-List | Out-String
        $detail | Should -Match 'IsBaseline\s+: True'
        $detail | Should -Match 'AuthenticationMode\s+: Standard'
        $detail | Should -Not -Match 'ClientTenantId'
    }

    It 'Baseline: OwnerTenantId and member ids fall back to the Microsoft tenant id on v1' {
        Set-V1TenantsSession -Beta
        $beta = @(Get-InforcerBaseline)[0] | Format-List | Out-String
        $beta | Should -Match 'OwnerTenantId\s+: 1'
        $beta | Should -Match 'Fabrikam \(2\)'
        Set-V1TenantsSession
        $v1 = @(Get-InforcerBaseline)[0] | Format-List | Out-String
        $v1 | Should -Match "OwnerTenantId\s+: $($script:T1)"
        $v1 | Should -Match "Fabrikam \($($script:T2)\)"
        ([regex]::Matches($v1, 'OwnerTenantId')).Count | Should -Be 1
    }

    It 'AlignmentScore: the TenantId row shows the client id on beta and the Microsoft id on v1' {
        Set-V1TenantsSession -Beta
        (@(Get-InforcerAlignmentDetails)[0] | Format-List | Out-String) | Should -Match 'TenantId\s+: 2'
        Set-V1TenantsSession
        $v1 = @(Get-InforcerAlignmentDetails)[0] | Format-List | Out-String
        $v1 | Should -Match "TenantId\s+: $($script:T2)"
        ([regex]::Matches($v1, '(?m)^TenantId')).Count | Should -Be 1
    }
}
}
