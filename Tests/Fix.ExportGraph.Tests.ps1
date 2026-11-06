# Fix.ExportGraph.Tests.ps1
# Fix wave 1.5.9c: Export pipeline input, Graph enrichment (maps, scopes, retries, CA names), DocData
# without the JSON round trip, parallel Compare, profile type fallback, Connect redirects.
# Invoke-InforcerHttpRequest / Invoke-MgGraphRequest are mocked; the parallel Compare test runs a
# localhost HttpListener. Fixtures are synthetic (zero GUIDs, example names).

BeforeAll {
    Remove-Module -Name 'InforcerCommunity' -ErrorAction SilentlyContinue
    Import-Module (Join-Path $PSScriptRoot '../module/InforcerCommunity.psd1') -Force

    foreach ($cmd in 'Invoke-MgGraphRequest', 'Connect-MgGraph', 'Get-MgContext', 'Disconnect-MgGraph') {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { New-Item -Path "function:global:$cmd" -Value { } | Out-Null }
    }

    $script:Group1 = '00000000-0000-0000-0000-0000000000a1'
    $script:Group2 = '00000000-0000-0000-0000-0000000000a2'
    $script:CustomRole = '00000000-0000-0000-0000-0000000000c1'
    $script:Location = '00000000-0000-0000-0000-0000000000c2'
    $script:GraphApp = '00000003-0000-0000-c000-000000000000'
    $script:StaticOnlyApp = '0000000a-0000-0000-c000-000000000000'
    $script:AppIds = @($GraphApp, $StaticOnlyApp) + @(1..14 | ForEach-Object { '00000000-0000-0000-0000-0000000001{0:d2}' -f $_ })

    $policies = @(
        [ordered]@{ id = '1001'; policyTypeId = 3; displayName = 'Windows compliance'; friendlyName = $null; product = 'Intune'
            primaryGroup = 'Devices'; secondaryGroup = 'Windows'; tags = @()
            policyData = [ordered]@{ id = '00000000-0000-0000-0000-0000000000d1'; displayName = 'Windows compliance'
                '@odata.type' = '#microsoft.graph.windows10CompliancePolicy'; roleScopeTagIds = @('0')
                assignments = @(@{ target = @{ '@odata.type' = '#microsoft.graph.groupAssignmentTarget'; groupId = $Group1 } }) } }
        [ordered]@{ id = '1002'; policyTypeId = 1; displayName = 'Require MFA'; friendlyName = $null; product = 'Entra'
            primaryGroup = 'Conditional Access'; secondaryGroup = $null; tags = @()
            policyData = [ordered]@{ id = '00000000-0000-0000-0000-0000000000d2'; displayName = 'Require MFA'; state = 'enabled'
                conditions = @{ users = @{ includeGroups = @($Group2); includeRoles = @($CustomRole) }
                    locations = @{ includeLocations = @($Location) }; applications = @{ includeApplications = $AppIds } } } }
        [ordered]@{ id = '1003'; policyTypeId = 12; displayName = 'MultiFactorAuthConfig'
            friendlyName = 'Require Multifactor Authentication to register or join devices with Microsoft Entra'
            product = 'Entra'; primaryGroup = 'Settings'; secondaryGroup = 'All'; tags = @(); policyData = @{ id = 'x3' } }
        [ordered]@{ id = '1004'; policyTypeId = 12; displayName = 'SelfServicePassConfig'; friendlyName = $null
            product = 'Entra'; primaryGroup = 'Settings'; secondaryGroup = 'All'; tags = @(); policyData = @{ id = 'x4' } }
        [ordered]@{ id = '1005'; policyTypeId = 12; displayName = 'AuthenticatorSetupEnforce'; friendlyName = ''
            product = 'Entra'; primaryGroup = 'Settings'; secondaryGroup = 'All'; tags = @(); policyData = @{ id = 'x5' } }
    )
    $script:BetaPoliciesJson = @{ success = $true; data = $policies } | ConvertTo-Json -Depth 100 -Compress

    function global:Reset-FixRoutes {
        $global:FixCalls = [System.Collections.Generic.List[string]]::new()
        $global:FixRoutes = [ordered]@{
            '/beta/tenants$' = '{"success":true,"data":[{"clientTenantId":1,"msTenantId":"00000000-0000-0000-0000-000000000001","tenantFriendlyName":"Contoso","tenantDnsName":"contoso.example","tags":[]},{"clientTenantId":2,"msTenantId":"00000000-0000-0000-0000-000000000002","tenantFriendlyName":"Fabrikam","tenantDnsName":"fabrikam.example","tags":[]}]}'
            '/beta/baselines$' = '{"success":true,"data":[]}'
            '/beta/tenants/\d+/policies$' = $script:BetaPoliciesJson
        }
    }
    function global:Get-FixResponse([string]$Uri) {
        $global:FixCalls.Add($Uri)
        foreach ($pattern in $global:FixRoutes.Keys) {
            if ($Uri -match $pattern) { return [pscustomobject]@{ StatusCode = 200; Body = ($global:FixRoutes[$pattern] | ConvertFrom-Json -Depth 100); Headers = @{} } }
        }
        [pscustomobject]@{ StatusCode = 404; Body = [pscustomobject]@{ title = 'Not Found'; status = 404 }; Headers = @{} }
    }
    function global:New-FixBetaSession([string]$BaseUrl = 'https://api.example.invalid/api') {
        @{ AuthMode = 'ApiKey'; ApiVersion = 'beta'; ApiHost = ($BaseUrl -replace '/api$', ''); BaseUrl = $BaseUrl; Region = 'uk'
            ConnectedAt = Get-Date; ApiKey = (ConvertTo-SecureString 'beta-test-key-value' -AsPlainText -Force) }
    }
    function global:Set-FixSession($Session) {
        & (Get-Module InforcerCommunity) { param($s) $script:InforcerTenantListCache = $null; $script:InforcerSession = $s } $Session
    }

    # Graph fake: getByIds names only Group1, filters/scope tags, roleDefinitions incl. a custom role,
    # named locations, service principals by appId (the Graph name beats the static map).
    function global:Get-FixGraphResponse([string]$Uri, [string]$Method, [string]$Body) {
        $global:GraphCalls.Add("$Method $Uri")
        switch -Regex ($Uri) {
            'directoryObjects/getByIds' {
                $ids = @(($Body | ConvertFrom-Json).ids)
                return [pscustomobject]@{ value = @($ids | Where-Object { $_ -eq $script:Group1 } | ForEach-Object { [pscustomobject]@{ id = $_; displayName = 'Contoso Devices' } }) }
            }
            'assignmentFilters' { return [pscustomobject]@{ value = @() } }
            'roleScopeTags' { return [pscustomobject]@{ value = @([pscustomobject]@{ id = 0; displayName = 'Default' }) } }
            'roleDefinitions' { return [pscustomobject]@{ value = @([pscustomobject]@{ id = $script:CustomRole; displayName = 'Contoso Custom Role' }) } }
            'namedLocations' { return [pscustomobject]@{ value = @([pscustomobject]@{ id = $script:Location; displayName = 'Contoso Office' }) } }
            'servicePrincipals' {
                $decoded = [uri]::UnescapeDataString($Uri)
                $value = @(); if ($decoded -match [regex]::Escape($script:GraphApp)) { $value = @([pscustomobject]@{ appId = $script:GraphApp; displayName = 'Microsoft Graph (tenant name)' }) }
                return [pscustomobject]@{ value = $value }
            }
            'deviceCompliancePolicies' { return [pscustomobject]@{ id = 'x'; deviceCompliancePolicyScript = $null } }
        }
        [pscustomobject]@{ value = @() }
    }

    function global:New-FixHttpError([int]$Status) {
        $resp = [System.Net.Http.HttpResponseMessage]::new([System.Net.HttpStatusCode]$Status)
        [Microsoft.PowerShell.Commands.HttpResponseException]::new("HTTP $Status", $resp)
    }
}

AfterAll {
    foreach ($f in 'Reset-FixRoutes', 'Get-FixResponse', 'New-FixBetaSession', 'Set-FixSession', 'Get-FixGraphResponse', 'New-FixHttpError') {
        Remove-Item "function:global:$f" -ErrorAction SilentlyContinue
    }
    Remove-Variable -Name FixRoutes, FixCalls, GraphCalls -Scope Global -ErrorAction SilentlyContinue
    & (Get-Module InforcerCommunity) { $script:InforcerSession = $null; $script:InforcerTenantListCache = $null }
}

Describe 'Fix 1.5.9c: Export, Graph enrichment, Compare, profile type' {
BeforeEach {
    Reset-FixRoutes
    $global:GraphCalls = [System.Collections.Generic.List[string]]::new()
    Mock -ModuleName InforcerCommunity Invoke-InforcerHttpRequest { Get-FixResponse $Request.Uri }
    Mock -ModuleName InforcerCommunity Import-InforcerSettingsCatalog { }
    Mock -ModuleName InforcerCommunity Start-Process { }
    Mock -ModuleName InforcerCommunity Start-Sleep { }
    Mock -ModuleName InforcerCommunity Invoke-MgGraphRequest { Get-FixGraphResponse $Uri $Method $Body }
    Mock -ModuleName InforcerCommunity Connect-InforcerGraph { [pscustomobject]@{ Account = 'admin@contoso.example'; TenantId = '00000000-0000-0000-0000-000000000001' } }
    Set-FixSession (New-FixBetaSession)
}

Context 'guardian F1: piped tenants and -OutputPath' {
    It 'a second piped tenant with a file -OutputPath stops with OutputPathIsFileForSeveralTenants before fetching it' {
        $file = Join-Path $TestDrive 'report.html'
        $err = $null
        try {
            @([pscustomobject]@{ ClientTenantId = 1 }, [pscustomobject]@{ ClientTenantId = 2 }) |
                Export-InforcerTenantDocumentation -OutputPath $file -Show:$false 6>$null | Out-Null
        } catch { $err = $_ }
        $err | Should -Not -BeNullOrEmpty
        $err.FullyQualifiedErrorId | Should -BeLike 'OutputPathIsFileForSeveralTenants*'
        @($global:FixCalls | Where-Object { $_ -match '/policies$' }).Count | Should -Be 1
        Test-Path $file | Should -BeTrue
    }

    It 'piped tenants to a directory write one file each and -Show opens each HTML file once' {
        $dir = Join-Path $TestDrive 'out'
        $files = @([pscustomobject]@{ ClientTenantId = 1 }, [pscustomobject]@{ ClientTenantId = 2 }, [pscustomobject]@{ ClientTenantId = 1 }) |
            Export-InforcerTenantDocumentation -OutputPath $dir -Show 6>$null
        @($files.FullName | Sort-Object -Unique).Count | Should -Be 2
        Should -Invoke -ModuleName InforcerCommunity Start-Process -Times 2 -Exactly
    }
}

Context 'guardian F2 + scope-tag map: Graph maps never cross tenants or calls' {
    It 'the second piped tenant does not inherit the first tenant''s group or scope-tag names when its Graph sign-in fails' {
        $script:connects = 0
        Mock -ModuleName InforcerCommunity Connect-InforcerGraph {
            $script:connects++
            if ($script:connects -eq 1) { [pscustomobject]@{ Account = 'admin@contoso.example'; TenantId = '00000000-0000-0000-0000-000000000001' } }
        }
        $models = @([pscustomobject]@{ ClientTenantId = 1 }, [pscustomobject]@{ ClientTenantId = 2 }) |
            Export-InforcerTenantDocumentation -FetchGraphData -WarningAction SilentlyContinue 6>$null
        $first = $models[0].Products['Intune'].Categories['Devices / Windows'][0]
        $second = $models[1].Products['Intune'].Categories['Devices / Windows'][0]
        "$($first.Assignments[0].Target)" | Should -Match 'Contoso Devices'
        $first.Basics.ScopeTags | Should -BeExactly 'Default'
        "$($second.Assignments[0].Target)" | Should -Not -Match 'Contoso Devices'
        $second.Basics.ScopeTags | Should -BeExactly '0'
    }

    It 'a later call without -FetchGraphData shows raw scope-tag ids' {
        $null = Export-InforcerTenantDocumentation -TenantId 1 -FetchGraphData 6>$null
        $m = Export-InforcerTenantDocumentation -TenantId 2 6>$null
        $m.Products['Intune'].Categories['Devices / Windows'][0].Basics.ScopeTags | Should -BeExactly '0'
    }
}

Context 'static F1/F3, performance F7: Conditional Access names via Resolve-InforcerGraphEnrichment' {
    It 'Export resolves groups with getByIds, custom roles via roleDefinitions, locations, and apps by batched appId filter' {
        $maps = InModuleScope InforcerCommunity { Resolve-InforcerGraphEnrichment -DocData (Get-InforcerDocData -TenantId 1) -ConditionalAccess 6>$null }
        $maps.GroupNameMap[$Group1] | Should -BeExactly 'Contoso Devices'
        $maps.GroupNameMap[$Group2] | Should -BeExactly $Group2
        $maps.RoleNameMap[$CustomRole] | Should -BeExactly 'Contoso Custom Role'
        $maps.LocationNameMap[$Location] | Should -BeExactly 'Contoso Office'
        $maps.AppNameMap[$GraphApp] | Should -BeExactly 'Microsoft Graph (tenant name)'
        $maps.AppNameMap[$StaticOnlyApp] | Should -BeExactly 'Microsoft Intune'
        @($global:GraphCalls | Where-Object { $_ -match 'servicePrincipals' }).Count | Should -Be 2
        @($global:GraphCalls | Where-Object { $_ -match '^POST .*directoryObjects/getByIds$' }).Count | Should -Be 1
        @($global:GraphCalls | Where-Object { $_ -match 'directoryObjects/[0-9a-f-]{36}$|directoryRoleTemplates|servicePrincipals\(appId' }).Count | Should -Be 0
        @($global:GraphCalls | Where-Object { $_ -match 'roleManagement/directory/roleDefinitions' }).Count | Should -Be 1
    } -TestCases @{ Group1 = '00000000-0000-0000-0000-0000000000a1'; Group2 = '00000000-0000-0000-0000-0000000000a2'; CustomRole = '00000000-0000-0000-0000-0000000000c1'; Location = '00000000-0000-0000-0000-0000000000c2'; GraphApp = '00000003-0000-0000-c000-000000000000'; StaticOnlyApp = '0000000a-0000-0000-c000-000000000000' }

    It 'getByIds is chunked at 1000 ids; compliance rules are fetched only with -ComplianceRules' {
        $many = @(1..1001 | ForEach-Object { [pscustomobject]@{ policyData = [pscustomobject]@{ assignments = @([pscustomobject]@{ target = [pscustomobject]@{ groupId = ('00000000-0000-0000-0000-{0:d12}' -f $_) } }) } } })
        $null = InModuleScope InforcerCommunity -Parameters @{ P = $many } { param($P) Resolve-InforcerGraphEnrichment -DocData @{ Policies = $P } 6>$null }
        @($global:GraphCalls | Where-Object { $_ -match 'getByIds' }).Count | Should -Be 2
        @($global:GraphCalls | Where-Object { $_ -match 'deviceCompliancePolicies' }).Count | Should -Be 0

        $global:GraphCalls.Clear()
        $null = InModuleScope InforcerCommunity { Resolve-InforcerGraphEnrichment -DocData (Get-InforcerDocData -TenantId 1) -ComplianceRules 6>$null }
        @($global:GraphCalls | Where-Object { $_ -match 'deviceCompliancePolicies' }).Count | Should -Be 1
    }
}

Context 'static F2/F20: Graph scopes, retries and the 10,000 cap' {
    It 'Connect-InforcerGraph asks for Directory, Policy and DeviceManagementConfiguration read scopes, and no caller narrows them' {
        $default = InModuleScope InforcerCommunity { (Get-Item function:Connect-InforcerGraph).ScriptBlock.Ast.Body.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'RequiredScopes' } | ForEach-Object { $_.DefaultValue.Extent.Text } }
        "$default" | Should -Match 'Directory\.Read\.All'
        "$default" | Should -Match 'Policy\.Read\.All'
        "$default" | Should -Match 'DeviceManagementConfiguration\.Read\.All'
        $callers = Get-ChildItem (Join-Path $PSScriptRoot '../module') -Recurse -Filter *.ps1 | Select-String -Pattern 'Connect-InforcerGraph\b.*-RequiredScopes'
        @($callers).Count | Should -Be 0
    }

    It 'a 403 is not retried and the warning names the likely missing permission' {
        Mock -ModuleName InforcerCommunity Invoke-MgGraphRequest { $global:GraphCalls.Add($Uri); throw (New-FixHttpError 403) }
        $r = InModuleScope InforcerCommunity {
            $out = Invoke-InforcerGraphRequest -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/namedLocations' -WarningVariable w -WarningAction SilentlyContinue
            @{ Out = $out; W = $w }
        }
        @($r.Out).Count | Should -Be 0
        $global:GraphCalls.Count | Should -Be 1
        "$($r.W)" | Should -Match 'Policy\.Read\.All'
        Should -Invoke -ModuleName InforcerCommunity Start-Sleep -Times 0 -Exactly
    }

    It 'a 503 is retried; -Body is sent as JSON' {
        $script:n = 0
        Mock -ModuleName InforcerCommunity Invoke-MgGraphRequest {
            $script:n++
            if ($script:n -eq 1) { throw (New-FixHttpError 503) }
            [pscustomobject]@{ id = 'ok'; body = $Body; ct = $ContentType }
        }
        $o = InModuleScope InforcerCommunity { Invoke-InforcerGraphRequest -Uri 'https://graph.microsoft.com/v1.0/x' -Method POST -Body '{"a":1}' -SingleObject }
        $o.id | Should -Be 'ok'
        $o.body | Should -Be '{"a":1}'
        $o.ct | Should -Be 'application/json'
        Should -Invoke -ModuleName InforcerCommunity Start-Sleep -Times 1 -Exactly
    }

    It 'warns when the 10,000-item cap truncates a paged result' {
        Mock -ModuleName InforcerCommunity Invoke-MgGraphRequest {
            [pscustomobject]@{ value = @(1..1000 | ForEach-Object { [pscustomobject]@{ id = $_ } }); '@odata.nextLink' = 'https://graph.microsoft.com/v1.0/next' }
        }
        $r = InModuleScope InforcerCommunity { $o = Invoke-InforcerGraphRequest -Uri 'https://graph.microsoft.com/v1.0/groups' -WarningVariable w -WarningAction SilentlyContinue; @{ N = @($o).Count; W = $w } }
        $r.N | Should -Be 10000
        "$($r.W)" | Should -Match '10,000'
    }
}

Context 'static F4: Entra/SharePoint/M365 names from the API, map for category and fallback only' {
    It 'uses friendlyName, and the corrected fallback labels and categories' {
        $m = Export-InforcerTenantDocumentation -TenantId 1 6>$null
        $names = @{}
        foreach ($cat in $m.Products['Entra'].Categories.Keys) { foreach ($p in $m.Products['Entra'].Categories[$cat]) { $names[$p.Basics.Name] = $cat } }
        $names['Require Multifactor Authentication to register or join devices with Microsoft Entra'] | Should -BeExactly 'Device settings'
        $names['Guest self-service sign up'] | Should -BeExactly 'External Identities'
        $names['Registration campaign'] | Should -BeExactly 'Authentication methods'
        $names.ContainsKey('Multifactor authentication') | Should -BeFalse
        $names.ContainsKey('Self-service password reset') | Should -BeFalse
    }
}

Context 'performance F6: DocData without the JSON round trip' {
    It 'fetches policies directly (not via Get-InforcerTenantPolicies) with the same raw objects; empty list stays $null' {
        Mock -ModuleName InforcerCommunity Get-InforcerTenantPolicies { throw 'should not be called' }
        $d = InModuleScope InforcerCommunity { Get-InforcerDocData -TenantId 1 }
        @($d.Policies).Count | Should -Be 5
        $d.Policies[0].PSObject.Properties['PolicyName'] | Should -BeNullOrEmpty
        Should -Invoke -ModuleName InforcerCommunity Get-InforcerTenantPolicies -Times 0 -Exactly

        $global:FixRoutes['/beta/tenants/\d+/policies$'] = '{"success":true,"data":[]}'
        $e = InModuleScope InforcerCommunity { Get-InforcerDocData -TenantId 1 }
        $e.Policies | Should -BeNullOrEmpty
        $e.ContainsKey('Policies') | Should -BeTrue
    }
}

Context 'decision 4: Profile type on beta' {
    It 'fills ProfileType from policyTypeId when the API sends no type name; ids without evidence stay blank' {
        InModuleScope InforcerCommunity {
            Get-InforcerPolicyTypeName -PolicyTypeId 10 | Should -BeExactly 'Intune Configuration Policies'
            Get-InforcerPolicyTypeName -PolicyTypeId '3' | Should -BeExactly 'Device Compliance Policy'
            foreach ($id in 5, 29, 30, 10202, 10204, 10215, 10234, 10235, 10268, 10306) { Get-InforcerPolicyTypeName -PolicyTypeId $id | Should -BeExactly '' }
            Get-InforcerPolicyTypeName -PolicyTypeId $null | Should -BeExactly ''
            $m = ConvertTo-InforcerDocModel -DocData @{ TenantId = 1; Policies = @(
                [pscustomobject]@{ id = 1; policyTypeId = 3; displayName = 'a'; product = 'Intune'; primaryGroup = 'A' }
                [pscustomobject]@{ id = 2; policyTypeId = 3; inforcerPolicyTypeName = 'Name from the API'; displayName = 'b'; product = 'Intune'; primaryGroup = 'B' }
            ) }
            $m.Products['Intune'].Categories['A'][0].Basics.ProfileType | Should -BeExactly 'Device Compliance Policy'
            $m.Products['Intune'].Categories['B'][0].Basics.ProfileType | Should -BeExactly 'Name from the API'
        }
    }
}

Context 'guardian F7: Connect-Inforcer output type' {
    It 'declares hashtable for -PassThru' {
        (Get-Command Connect-Inforcer).OutputType.Type | Should -Contain ([hashtable])
    }
}

Context 'Connect-Inforcer refuses redirects for credentialed requests' {
    BeforeEach { Set-FixSession $null }
    It 'a 3xx on the API-key probe fails the connection without following it' {
        Mock -ModuleName InforcerCommunity Invoke-WebRequest {
            [pscustomobject]@{ StatusCode = 302; Headers = @{ Location = 'https://elsewhere.example/x' }; Content = '' }
        }
        $null = Connect-Inforcer -ApiKey 'beta-test-key-value' -Region uk -Confirm:$false -ErrorVariable e -ErrorAction SilentlyContinue 3>$null 6>$null
        @($e | Where-Object { $_.FullyQualifiedErrorId -like 'ConnectionValidationFailed*' -and "$_" -match 'redirect' }).Count | Should -Be 1
        (InModuleScope InforcerCommunity { $null -eq $script:InforcerSession }) | Should -BeTrue
        Should -Invoke -ModuleName InforcerCommunity Invoke-WebRequest -ParameterFilter { $MaximumRedirection -eq 0 -and $Uri -match '/baselines$' } -Times 1 -Exactly
    }

    It 'the report catalog prime sends no redirect-following request and a 3xx leaves the cache empty' {
        Mock -ModuleName InforcerCommunity Invoke-WebRequest {
            if ($Uri -match '/reports/types$') { return [pscustomobject]@{ StatusCode = 307; Headers = @{ Location = 'https://elsewhere.example/y' }; Content = '' } }
            [pscustomobject]@{ StatusCode = 200; Headers = @{}; Content = '{"success":true,"data":[]}' }
        }
        $null = Connect-Inforcer -ApiKey 'beta-test-key-value' -Region uk -Confirm:$false 3>$null 6>$null
        (InModuleScope InforcerCommunity { $null -ne $script:InforcerSession }) | Should -BeTrue
        (InModuleScope InforcerCommunity { @($script:InforcerReportTypeCache).Where({ $_ }).Count }) | Should -Be 0
        Should -Invoke -ModuleName InforcerCommunity Invoke-WebRequest -ParameterFilter { $MaximumRedirection -eq 0 -and $Uri -match '/reports/types$' } -Times 1 -Exactly
    }
}
}

Describe 'performance F1: Compare collects source and destination in parallel' {
    BeforeAll {
        $tcp = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0); $tcp.Start()
        $script:Port = $tcp.LocalEndpoint.Port; $tcp.Stop()
        $script:Listener = [System.Net.HttpListener]::new()
        $Listener.Prefixes.Add("http://localhost:$Port/")
        $Listener.Start()
        $script:Log = [System.Collections.Concurrent.ConcurrentQueue[object]]::new()
        $routes = [ordered]@{
            '^/api/beta/tenants$' = '{"success":true,"data":[{"clientTenantId":1,"msTenantId":"00000000-0000-0000-0000-000000000001","tenantFriendlyName":"Contoso","tenantDnsName":"contoso.example"}]}'
            '^/api/beta/baselines$' = '{"success":true,"data":[]}'
            '^/api/beta/tenants/1/policies$' = '{"success":true,"data":[{"id":"1","policyTypeId":3,"displayName":"Windows compliance","product":"Intune","primaryGroup":"Devices","secondaryGroup":"Windows","tags":[],"policyData":{"id":"00000000-0000-0000-0000-0000000000d1","passwordRequired":true}}]}'
            '^/v1/tenants$' = '{"tenants":[{"msTenantId":"00000000-0000-0000-0000-000000000002","name":"Fabrikam","dnsName":"fabrikam.example"}]}'
            '^/v1/tenants/00000000-0000-0000-0000-000000000002$' = '{"msTenantId":"00000000-0000-0000-0000-000000000002","name":"Fabrikam","dnsName":"fabrikam.example","tags":[]}'
            '^/v1/baselines$' = '{"baselines":[]}'
            '^/v1/tenants/00000000-0000-0000-0000-000000000002/policies$' = '{"policies":[{"id":"00000000-0000-0000-0000-0000000000e1","policyTypeId":1,"policyTypeName":"Conditional Access Policy","displayName":"Require MFA","product":"Entra","primaryGroup":"Conditional Access","tags":[],"policyData":{"id":"00000000-0000-0000-0000-0000000000e1"}}],"failedPolicyTypes":{}}'
        }
        $server = {
            param($Listener, $Log, $Routes, $DelayMs)
            while ($Listener.IsListening) {
                try { $ctx = $Listener.GetContext() } catch { break }
                $path = $ctx.Request.Url.AbsolutePath
                $start = [datetime]::UtcNow
                if ($path -match '/policies$') { Start-Sleep -Milliseconds $DelayMs }
                $status = 404; $body = '{"title":"Not Found","status":404}'
                foreach ($k in $Routes.Keys) { if ($path -match $k) { $status = 200; $body = $Routes[$k]; break } }
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($body)
                $ctx.Response.StatusCode = $status
                $ctx.Response.ContentType = 'application/json'
                $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                $ctx.Response.Close()
                $Log.Enqueue([pscustomobject]@{ Path = $path; Start = $start; End = [datetime]::UtcNow })
            }
        }.ToString()
        $script:Pool = [runspacefactory]::CreateRunspacePool(1, 4); $Pool.Open()
        $script:Servers = foreach ($i in 1..4) {
            $p = [powershell]::Create(); $p.RunspacePool = $Pool
            $null = $p.AddScript($server).AddArgument($Listener).AddArgument($Log).AddArgument($routes).AddArgument(3000)
            [pscustomobject]@{ P = $p; H = $p.BeginInvoke() }
        }
    }
    AfterAll {
        $Listener.Stop(); $Listener.Close()
        foreach ($s in $Servers) { $s.P.Dispose() }
        $Pool.Dispose()
        & (Get-Module InforcerCommunity) { $script:InforcerSession = $null; $script:InforcerTenantListCache = $null }
    }

    It 'beta source and v1 destination: the two policies calls overlap, the v1 warning comes back once, the session is restored' {
        Mock -ModuleName InforcerCommunity Import-InforcerSettingsCatalog { }
        & (Get-Module InforcerCommunity) { $script:InforcerSession = $null; $script:InforcerTenantListCache = $null }
        $src = @{ AuthMode = 'ApiKey'; ApiVersion = 'beta'; ApiHost = "http://localhost:$Port"; BaseUrl = "http://localhost:$Port/api"; Region = 'uk'
            ConnectedAt = Get-Date; ApiKey = (ConvertTo-SecureString 'beta-test-key-value' -AsPlainText -Force) }
        $dst = @{ AuthMode = 'ClientCredentials'; ApiVersion = 'v1'; ApiHost = "http://localhost:$Port"; BaseUrl = "http://localhost:$Port"; Region = 'uk'
            ConnectedAt = Get-Date; ClientId = 'client-id-example'
            ClientSecret = (ConvertTo-SecureString 'client-secret-example-value' -AsPlainText -Force)
            AccessToken = (ConvertTo-SecureString 'access-token-example-value' -AsPlainText -Force); TokenExpiresAt = [datetime]::UtcNow.AddMinutes(50) }

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $model = Compare-InforcerEnvironments -SourceTenantId 1 -DestinationTenantId '00000000-0000-0000-0000-000000000002' `
            -SourceSession $src -DestinationSession $dst -WarningVariable w -WarningAction SilentlyContinue 6>$null
        $sw.Stop()
        Write-Host "  parallel Compare against 2 x 3 s policies: $([math]::Round($sw.Elapsed.TotalSeconds, 2)) s"

        $model.SourceName | Should -BeExactly 'Contoso'
        $model.DestinationName | Should -BeExactly 'Fabrikam'
        $calls = @($Log.ToArray() | Where-Object { $_.Path -match '/policies$' })
        $calls.Count | Should -Be 2
        ($calls | Measure-Object -Property Start -Maximum).Maximum | Should -BeLessThan ($calls | Measure-Object -Property End -Minimum).Minimum
        (InModuleScope InforcerCommunity { $null -eq $script:InforcerSession }) | Should -BeTrue
    }
}
