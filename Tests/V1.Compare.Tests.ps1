# V1.Compare.Tests.ps1
# Export-InforcerTenantDocumentation, Compare-InforcerEnvironments and their private pipeline
# (Get-InforcerDocData, Select-InforcerBaselinePolicies, ConvertTo-InforcerDocModel) on both logins
# and with mixed sessions. Invoke-InforcerHttpRequest is mocked, so the real request, unwrap and v1
# mapping run. Fixtures are anonymised (zero GUIDs, example names); no network calls.

BeforeAll {
    Remove-Module -Name 'InforcerCommunity' -ErrorAction SilentlyContinue
    Import-Module (Join-Path $PSScriptRoot '../module/InforcerCommunity.psd1') -Force

    $script:T1 = '00000000-0000-0000-0000-000000000001'
    $script:T2 = '00000000-0000-0000-0000-000000000002'
    $script:B1 = '00000000-0000-0000-0000-0000000000b1'

    function global:Reset-V1CompareRoutes {
        $global:V1CompareCalls = [System.Collections.Generic.List[string]]::new()
        $global:V1CompareRoutes = [ordered]@{
            # v1 (client credentials)
            '/v1/tenants$' = '{"tenants":[{"msTenantId":"00000000-0000-0000-0000-000000000001","name":"Contoso","dnsName":"contoso.onmicrosoft.com"},{"msTenantId":"00000000-0000-0000-0000-000000000002","name":"Fabrikam","dnsName":"fabrikam.onmicrosoft.com"}]}'
            '/v1/tenants/00000000-0000-0000-0000-000000000001$' = '{"msTenantId":"00000000-0000-0000-0000-000000000001","name":"Contoso","dnsName":"contoso.onmicrosoft.com","secureScore":50,"isBaseline":true,"tags":[],"alignmentSummaries":[],"licenses":[],"authenticationMode":"Standard"}'
            '/v1/tenants/00000000-0000-0000-0000-000000000002$' = '{"msTenantId":"00000000-0000-0000-0000-000000000002","name":"Fabrikam","dnsName":"fabrikam.onmicrosoft.com","secureScore":40,"isBaseline":false,"tags":[],"alignmentSummaries":[],"licenses":[],"authenticationMode":"Standard"}'
            '/v1/baselines$' = '{"baselines":[{"id":"00000000-0000-0000-0000-0000000000b1","name":"Contoso Baseline","description":"","baselineTenant":{"msTenantId":"00000000-0000-0000-0000-000000000001","name":"Contoso","dnsName":"contoso.onmicrosoft.com"},"mode":"Monitor","isShared":false,"isSharedCopy":false,"members":[{"msTenantId":"00000000-0000-0000-0000-000000000002","name":"Fabrikam","dnsName":"fabrikam.onmicrosoft.com"}],"items":[]}]}'
            '/v1/tenants/[0-9a-f-]{36}/policies$' = '{"policies":[{"id":"00000000-0000-0000-0000-0000000000d1","policyTypeId":30,"policyTypeName":"Antivirus Exclusions","name":null,"displayName":"Contoso AV exclusions","friendlyName":null,"description":"","readOnly":false,"product":"Defender","primaryGroup":"Endpoint security","secondaryGroup":"Antivirus","platform":"Windows","tags":[],"policyData":{"id":"00000000-0000-0000-0000-0000000000d1","displayName":"Contoso AV exclusions","excludedExtensions":"tmp"}},{"id":"00000000-0000-0000-0000-0000000000e1","policyTypeId":1,"policyTypeName":"Conditional Access","name":null,"displayName":"Block legacy auth (tenant copy)","friendlyName":null,"description":"","readOnly":false,"product":"Entra","primaryGroup":"Conditional Access","secondaryGroup":null,"platform":null,"tags":[],"policyData":{"id":"00000000-0000-0000-0000-0000000000e1","displayName":"Block legacy auth (tenant copy)","state":"enabled"}},{"id":"00000000-0000-0000-0000-0000000000e2","policyTypeId":1,"policyTypeName":"Conditional Access","name":null,"displayName":"Require MFA","friendlyName":null,"description":"","readOnly":false,"product":"Entra","primaryGroup":"Conditional Access","secondaryGroup":null,"platform":null,"tags":[],"policyData":{"id":"00000000-0000-0000-0000-0000000000e2","displayName":"Require MFA","state":"enabled"}}],"failedPolicyTypes":{}}'
            '/v1/tenants/[0-9a-f-]{36}/alignmentDetails\?baselineId=' = '{"completedAt":"2026-01-02T00:00:00Z","baseline":{"id":"00000000-0000-0000-0000-0000000000b1","name":"Contoso Baseline"},"baselineDataTimestamp":"2026-01-01T00:00:00Z","tenantDataTimestamp":"2026-01-01T00:00:00Z","alignmentScore":50,"metrics":{"totalPolicies":2,"matched":1,"matchedWithAcceptedDeviations":0,"deviated":0,"missingFromTenant":1,"additionalInTenant":0},"policies":{"matched":[{"id":"00000000-0000-0000-0000-0000000000f1","policyTypeId":1,"policyTypeName":"Conditional Access","displayName":"Block legacy auth","friendlyName":null,"description":"","readOnly":false,"product":"Entra","primaryGroup":"Conditional Access","secondaryGroup":null,"platform":null,"tags":[],"tenantPolicies":[{"id":"00000000-0000-0000-0000-0000000000e1","policyDataDiff":[],"policyAssignmentsDiff":[],"tags":[],"acceptedDeviations":[]}],"variables":[],"acceptedDeviations":[],"similarPolicies":[]}],"matchedWithAcceptedDeviations":[],"deviated":[],"missingFromTenant":[{"id":"00000000-0000-0000-0000-0000000000f2","policyTypeId":1,"policyTypeName":"Conditional Access","displayName":"Block risky sign-ins","friendlyName":null,"description":"","readOnly":false,"product":"Entra","primaryGroup":"Conditional Access","secondaryGroup":null,"platform":null,"tags":[],"tenantPolicies":[],"variables":[],"acceptedDeviations":[],"similarPolicies":[]}],"additionalInTenant":[]}}'
            # beta (API key)
            '/beta/tenants$' = '{"success":true,"data":[{"clientTenantId":1,"msTenantId":"00000000-0000-0000-0000-000000000001","tenantFriendlyName":"Contoso","tenantDnsName":"contoso.onmicrosoft.com","licenses":[],"secureScore":50,"isBaseline":true,"tags":[],"alignmentSummaries":[]},{"clientTenantId":2,"msTenantId":"00000000-0000-0000-0000-000000000002","tenantFriendlyName":"Fabrikam","tenantDnsName":"fabrikam.onmicrosoft.com","licenses":[],"secureScore":40,"isBaseline":false,"tags":[],"alignmentSummaries":[]}]}'
            '/beta/baselines$' = '{"success":true,"data":[{"id":"00000000-0000-0000-0000-0000000000b1","name":"Contoso Baseline","baselineClientTenantId":1,"baselineMsTenantId":"00000000-0000-0000-0000-000000000001","baselineTenantFriendlyName":"Contoso","baselineTenantDnsName":"contoso.onmicrosoft.com","mode":"Monitor","isShared":false,"members":[{"clientTenantId":2,"msTenantId":"00000000-0000-0000-0000-000000000002","tenantFriendlyName":"Fabrikam","tenantDnsName":"fabrikam.onmicrosoft.com"}],"items":[]}]}'
            '/beta/tenants/\d+/policies$' = '{"success":true,"data":[{"id":"1001","policyTypeId":2,"name":null,"displayName":"Windows restrictions","friendlyName":null,"description":"","readOnly":false,"product":"Intune","primaryGroup":"Devices","secondaryGroup":"Windows","platform":"Windows","policyCategoryId":7,"tags":[],"policyData":{"id":"00000000-0000-0000-0000-0000000000a1","displayName":"Windows restrictions","@odata.type":"#microsoft.graph.windows10GeneralConfiguration","passwordRequired":true}},{"id":"1002","policyTypeId":1,"name":null,"displayName":"Block legacy auth","friendlyName":null,"description":"","readOnly":false,"product":"Entra","primaryGroup":"Conditional Access","secondaryGroup":null,"platform":null,"policyCategoryId":3,"tags":[],"policyData":{"id":"00000000-0000-0000-0000-0000000000a2","displayName":"Block legacy auth","state":"enabled"}},{"id":"1003","policyTypeId":1,"name":null,"displayName":"Require MFA","friendlyName":null,"description":"","readOnly":false,"product":"Entra","primaryGroup":"Conditional Access","secondaryGroup":null,"platform":null,"policyCategoryId":3,"tags":[],"policyData":{"id":"00000000-0000-0000-0000-0000000000a3","displayName":"Require MFA","state":"enabled"}}]}'
            '/beta/tenants/\d+/alignmentDetails\?customBaselineId=' = '{"success":true,"data":{"metrics":{"totalPolicies":1,"matchedPolicies":1},"completedAt":"2026-01-02T00:00:00Z","alignment":{"alignmentScore":100,"matchedPolicies":[{"policyName":"Block legacy auth","policyGuid":"00000000-0000-0000-0000-0000000000f1","product":"Entra","matchingSubjectPolicies":[{"subjectPolicyGuid":null,"policyDataDiff":[],"policyAssignmentsDiff":[]}]}],"matchedWithAcceptedDeviations":[],"deviatedUnaccepted":[],"missingFromSubjectUnaccepted":[],"additionalInSubjectUnaccepted":[]}}}'
        }
    }

    function global:Get-V1CompareResponse([string]$Uri) {
        $global:V1CompareCalls.Add($Uri)
        foreach ($pattern in $global:V1CompareRoutes.Keys) {
            if ($Uri -notmatch $pattern) { continue }
            $route = $global:V1CompareRoutes[$pattern]
            $status = 200
            if ($route -is [hashtable]) { $status = $route.Status; $route = $route.Body }
            return [pscustomobject]@{ StatusCode = $status; Body = ($route | ConvertFrom-Json -Depth 100); Headers = @{} }
        }
        [pscustomobject]@{ StatusCode = 404; Body = [pscustomobject]@{ title = 'Not Found'; status = 404 }; Headers = @{} }
    }

    function global:New-V1CompareSession([switch]$Beta) {
        if ($Beta) {
            return @{
                AuthMode = 'ApiKey'; ApiVersion = 'beta'; ApiHost = 'https://api.example.invalid'
                BaseUrl = 'https://api.example.invalid/api'; Region = 'uk'; ConnectedAt = Get-Date
                ApiKey = (ConvertTo-SecureString 'beta-test-key-value' -AsPlainText -Force)
            }
        }
        @{
            AuthMode = 'ClientCredentials'; ApiVersion = 'v1'; ApiHost = 'https://api.example.invalid'
            BaseUrl = 'https://api.example.invalid'; Region = 'uk'; ConnectedAt = Get-Date
            ClientId = 'client-id-example'
            ClientSecret = (ConvertTo-SecureString 'client-secret-example-value' -AsPlainText -Force)
            AccessToken = (ConvertTo-SecureString 'access-token-example-value' -AsPlainText -Force)
            TokenExpiresAt = [datetime]::UtcNow.AddMinutes(50)
        }
    }

    function global:Set-V1CompareSession([switch]$Beta, [switch]$None) {
        $session = if ($None) { $null } else { New-V1CompareSession -Beta:$Beta }
        & (Get-Module InforcerCommunity) { param($s) $script:InforcerTenantListCache = $null; $script:InforcerSession = $s } $session
    }

    $script:IntuneWarnings = { param($w) @($w | Where-Object { "$_" -match 'Intune' }) }
}

AfterAll {
    foreach ($f in 'Reset-V1CompareRoutes', 'Get-V1CompareResponse', 'New-V1CompareSession', 'Set-V1CompareSession') { Remove-Item "function:global:$f" -ErrorAction SilentlyContinue }
    Remove-Variable -Name V1CompareRoutes, V1CompareCalls -Scope Global -ErrorAction SilentlyContinue
    & (Get-Module InforcerCommunity) { $script:InforcerSession = $null; $script:InforcerTenantListCache = $null }
}

Describe 'Compare and export on both logins' {
BeforeEach {
    Reset-V1CompareRoutes
    Mock -ModuleName InforcerCommunity Invoke-InforcerHttpRequest { Get-V1CompareResponse $Request.Uri }
    Mock -ModuleName InforcerCommunity Import-InforcerSettingsCatalog { }
}

Context 'Get-InforcerDocData tenant selection' {
    It 'v1: collects the requested tenant (detailed record), never the first tenant in the list' {
        Set-V1CompareSession
        $d = InModuleScope InforcerCommunity { Get-InforcerDocData -TenantId 'Fabrikam' 3>$null }
        $d.TenantId | Should -BeExactly $T2
        $d.Tenant.tenantFriendlyName | Should -BeExactly 'Fabrikam'
        $d.Tenant.msTenantId | Should -Be $T2
        $d.Tenant.PSObject.Properties['secureScore'] | Should -Not -BeNullOrEmpty
        $global:V1CompareCalls | Should -Contain "https://api.example.invalid/v1/tenants/$T2"
        $global:V1CompareCalls | Should -Not -Contain "https://api.example.invalid/v1/tenants/$T1"
    } -TestCases @{ T1 = '00000000-0000-0000-0000-000000000001'; T2 = '00000000-0000-0000-0000-000000000002' }

    It 'beta: collects the requested tenant by client tenant id and keeps the list record as is' {
        Set-V1CompareSession -Beta
        $d = InModuleScope InforcerCommunity { Get-InforcerDocData -TenantId 2 }
        $d.TenantId | Should -Be 2
        $d.TenantId | Should -BeOfType [int]
        $d.Tenant.clientTenantId | Should -Be 2
        $d.Tenant.tenantFriendlyName | Should -BeExactly 'Fabrikam'
        @($d.Policies).Count | Should -Be 3
        $d.ContainsKey('Notes') | Should -BeFalse
    }

    It 'v1: when the tenant record cannot be loaded it warns and names the tenant by id, not another tenant' {
        Set-V1CompareSession
        $global:V1CompareRoutes['/v1/tenants/00000000-0000-0000-0000-000000000002$'] = @{ Status = 500; Body = '{"title":"Server error","status":500}' }
        $r = InModuleScope InforcerCommunity {
            $d = Get-InforcerDocData -TenantId '00000000-0000-0000-0000-000000000002' -WarningVariable w -WarningAction SilentlyContinue
            @{ D = $d; W = $w }
        }
        $d = $r.D
        $d | Should -Not -BeNullOrEmpty
        $d.Tenant | Should -BeNullOrEmpty
        @($r.W | Where-Object { "$_" -match 'Could not load details' }).Count | Should -Be 1
        $m = InModuleScope InforcerCommunity -Parameters @{ D = $d } { param($D) ConvertTo-InforcerDocModel -DocData $D }
        $m.TenantName | Should -BeExactly "Tenant $T2"
    } -TestCases @{ T2 = '00000000-0000-0000-0000-000000000002' }

    It 'v1: a numeric tenant id is InvalidTenantId; a 403 on policies is AccessDenied without API-key wording' {
        Set-V1CompareSession
        $e1 = InModuleScope InforcerCommunity { $null = Get-InforcerDocData -TenantId 482 -ErrorVariable e -ErrorAction SilentlyContinue; , $e }
        @($e1 | Where-Object { $_.FullyQualifiedErrorId -like 'InvalidTenantId*' }).Count | Should -Be 1

        $global:V1CompareRoutes['/v1/tenants/[0-9a-f-]{36}/policies$'] = @{ Status = 403; Body = '{"title":"Forbidden","status":403,"detail":"forbidden"}' }
        $e2 = InModuleScope InforcerCommunity { $null = Get-InforcerDocData -TenantId 'Fabrikam' -ErrorVariable e -ErrorAction SilentlyContinue; , $e }
        $err = @($e2 | Where-Object { $_.FullyQualifiedErrorId -like 'AccessDenied*' })
        $err.Count | Should -Be 1
        $err[0].Exception.Message | Should -Not -Match 'API key'
    }
}

Context 'Select-InforcerBaselinePolicies' {
    It 'v1: keeps policies matched by matchingSubjectPolicies id even when the name differs' {
        Set-V1CompareSession
        $kept = InModuleScope InforcerCommunity {
            $d = Get-InforcerDocData -TenantId 'Fabrikam' 3>$null
            $name = Select-InforcerBaselinePolicies -DocData $d -BaselineId 'Contoso Baseline' 3>$null 6>$null
            [pscustomobject]@{ Name = $name; Policies = @($d.Policies) }
        }
        $kept.Name | Should -BeExactly 'Contoso Baseline'
        @($kept.Policies.displayName) | Should -Be @('Block legacy auth (tenant copy)')
        @($global:V1CompareCalls | Where-Object { $_ -match "/v1/tenants/$T2/alignmentDetails\?baselineId=$B1$" }).Count | Should -Be 1
    } -TestCases @{ T2 = '00000000-0000-0000-0000-000000000002'; B1 = '00000000-0000-0000-0000-0000000000b1' }

    It 'beta: matches by policy name against the client tenant id endpoint, as before' {
        Set-V1CompareSession -Beta
        $kept = InModuleScope InforcerCommunity {
            $d = Get-InforcerDocData -TenantId 2
            $null = Select-InforcerBaselinePolicies -DocData $d -BaselineId '00000000-0000-0000-0000-0000000000b1' 3>$null 6>$null
            @($d.Policies)
        }
        @($kept.displayName) | Should -Be @('Block legacy auth')
        @($global:V1CompareCalls | Where-Object { $_ -match '/beta/tenants/2/alignmentDetails\?customBaselineId=' }).Count | Should -Be 1
    }
}

Context 'ConvertTo-InforcerDocModel' {
    It 'ProfileType comes from the v1 policy type name; beta (no type name in the API) stays empty' {
        Set-V1CompareSession
        $v1 = InModuleScope InforcerCommunity { ConvertTo-InforcerDocModel -DocData (Get-InforcerDocData -TenantId 'Fabrikam' 3>$null) }
        $v1.Products['Defender'].Categories['Endpoint security / Antivirus'][0].Basics.ProfileType | Should -BeExactly 'Antivirus Exclusions'
        $v1.Products['Defender'].Categories['Endpoint security / Antivirus'][0].Basics.Id | Should -Be '00000000-0000-0000-0000-0000000000d1'
        $v1.TenantName | Should -BeExactly 'Fabrikam'

        Set-V1CompareSession -Beta
        $beta = InModuleScope InforcerCommunity { ConvertTo-InforcerDocModel -DocData (Get-InforcerDocData -TenantId 2) }
        $beta.Products['Intune'].Categories['Devices / Windows'][0].Basics.ProfileType | Should -BeExactly ''
        $beta.Products['Intune'].Categories['Devices / Windows'][0].Basics.Id | Should -Be '1001'
        $beta.ContainsKey('Notes') | Should -BeFalse
    }
}

Context 'Export-InforcerTenantDocumentation' {
    It 'v1: one Intune warning, and the DocModel carries the note' {
        Set-V1CompareSession
        $m = Export-InforcerTenantDocumentation -TenantId $T2 -WarningVariable w -WarningAction SilentlyContinue 6>$null
        (& $IntuneWarnings $w).Count | Should -Be 1
        @($m.Notes).Count | Should -Be 1
        $m.Notes[0] | Should -Match 'v1 API'
        $m.Notes[0] | Should -Match 'no Intune policies'
        $m.Notes[0] | Should -Match 'Connect-Inforcer -ApiKey'
        $m.Notes[0] | Should -Not -Match 'reported'
        $m.TenantName | Should -BeExactly 'Fabrikam'
    } -TestCases @{ T2 = '00000000-0000-0000-0000-000000000002' }

    It 'beta: no Intune warning and no Notes key' {
        Set-V1CompareSession -Beta
        $m = Export-InforcerTenantDocumentation -TenantId 2 -WarningVariable w -WarningAction SilentlyContinue 6>$null
        (& $IntuneWarnings $w).Count | Should -Be 0
        $m.ContainsKey('Notes') | Should -BeFalse
        $m.TenantName | Should -BeExactly 'Fabrikam'
    }

    It 'pipeline: a v1 tenant binds via MsTenantId, a beta tenant still via ClientTenantId' {
        Set-V1CompareSession
        $m = Get-InforcerTenant -TenantId 'Fabrikam' | Export-InforcerTenantDocumentation 3>$null 6>$null
        $m.TenantId | Should -BeExactly $T2

        Set-V1CompareSession -Beta
        $m = [pscustomobject]@{ ClientTenantId = 2; MsTenantId = $T1 } | Export-InforcerTenantDocumentation 3>$null 6>$null
        $m.TenantId | Should -Be 2
    } -TestCases @{ T1 = '00000000-0000-0000-0000-000000000001'; T2 = '00000000-0000-0000-0000-000000000002' }
}

Context 'Compare-InforcerEnvironments' {
    It 'v1: both sides get the note in the model and a warning each' {
        Set-V1CompareSession
        $model = Compare-InforcerEnvironments -SourceTenantId 'Contoso' -DestinationTenantId 'Fabrikam' -WarningVariable w -WarningAction SilentlyContinue 6>$null
        (& $IntuneWarnings $w).Count | Should -Be 2
        @($model.Notes).Count | Should -Be 2
        $model.Notes[0] | Should -BeLike 'Source (Contoso): *Intune*'
        $model.Notes[1] | Should -BeLike 'Destination (Fabrikam): *Intune*'
    }

    It 'mixed sessions: each side calls its own API, only the v1 side gets the note, and the session is restored' {
        Set-V1CompareSession -None
        $src = New-V1CompareSession -Beta
        $dst = New-V1CompareSession
        $model = Compare-InforcerEnvironments -SourceTenantId 1 -DestinationTenantId 'Fabrikam' -SourceSession $src -DestinationSession $dst -WarningVariable w -WarningAction SilentlyContinue 6>$null
        $model | Should -Not -BeNullOrEmpty
        $model.SourceName | Should -BeExactly 'Contoso'
        $model.DestinationName | Should -BeExactly 'Fabrikam'
        @($model.Notes).Count | Should -Be 1
        $model.Notes[0] | Should -BeLike 'Destination (Fabrikam): *'
        $global:V1CompareCalls | Should -Contain 'https://api.example.invalid/api/beta/tenants/1/policies'
        $global:V1CompareCalls | Should -Contain "https://api.example.invalid/v1/tenants/$T2/policies"
        (InModuleScope InforcerCommunity { $null -eq $script:InforcerSession }) | Should -BeTrue
    } -TestCases @{ T2 = '00000000-0000-0000-0000-000000000002' }

    It 'baseline owner: resolved in the session of each side (beta client tenant id, v1 Microsoft tenant id)' {
        Set-V1CompareSession -None
        $src = New-V1CompareSession -Beta
        $dst = New-V1CompareSession
        $null = Compare-InforcerEnvironments -SourceBaselineId 'Contoso Baseline' -DestinationBaselineId 'Contoso Baseline' -SourceSession $src -DestinationSession $dst -ErrorVariable e -ErrorAction SilentlyContinue 3>$null 6>$null
        @($e | Where-Object { $_.FullyQualifiedErrorId -like 'BaselineOwnerNotFound*' -or $_.FullyQualifiedErrorId -like 'InvalidTenantId*' }).Count | Should -Be 0
        $global:V1CompareCalls | Should -Contain 'https://api.example.invalid/api/beta/tenants/1/policies'
        $global:V1CompareCalls | Should -Contain "https://api.example.invalid/v1/tenants/$T1/policies"
    } -TestCases @{ T1 = '00000000-0000-0000-0000-000000000001' }
}
}
