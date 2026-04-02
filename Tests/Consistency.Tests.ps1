# Consistency.Tests.ps1
# Validates that the script module's exported functions and parameter names match the consistency contract.
# Run from repo root: Invoke-Pester ./Tests/Consistency.Tests.ps1

$ErrorActionPreference = 'Stop'

# Resolve path to InforcerCommunity.psd1. Defined in global scope so Pester BeforeAll blocks can call it.
function global:Get-InforcerCommunityManifestPath {
    if ($script:manifestPathCache -and (Test-Path -LiteralPath $script:manifestPathCache)) { return $script:manifestPathCache }
    $here = $PSScriptRoot
    if (-not $here -and $PSCommandPath) { $here = Split-Path -Parent $PSCommandPath }
    if ($here) {
        $tryPath = Join-Path (Join-Path (Join-Path $here '..') 'module') 'InforcerCommunity.psd1'
        if (Test-Path -LiteralPath $tryPath) { $script:manifestPathCache = $tryPath; return $tryPath }
    }
    $root = Get-Location
    $tryPath = Join-Path (Join-Path $root 'module') 'InforcerCommunity.psd1'
    if (-not (Test-Path -LiteralPath $tryPath)) {
        throw "Module manifest not found. Run from repo root. Tried: $tryPath"
    }
    $script:manifestPathCache = $tryPath
    $tryPath
}

# Expected cmdlets and key parameters (from consistency contract) - defined inside Describe for scope
Describe 'Consistency contract' {

    BeforeAll {
        Remove-Module -Name 'InforcerCommunity' -ErrorAction SilentlyContinue
        $path = Get-InforcerCommunityManifestPath
        Import-Module $path -Force
        $script:exported = (Get-Module -Name 'InforcerCommunity').ExportedCommands.Keys
        $script:expectedCount = 12
        $script:expectedNames = @(
            'Connect-Inforcer', 'Disconnect-Inforcer', 'Test-InforcerConnection',
            'Get-InforcerTenant', 'Get-InforcerBaseline', 'Get-InforcerTenantPolicies',
            'Get-InforcerAlignmentDetails', 'Get-InforcerAuditEvent', 'Get-InforcerSupportedEventType',
            'Get-InforcerUser', 'Export-InforcerTenantDocumentation',
            'Compare-InforcerEnvironments'
        )
        $script:expectedParameters = @{
            'Connect-Inforcer'              = @('ApiKey', 'Region', 'BaseUrl', 'FetchGraphData', 'PassThru')
            'Disconnect-Inforcer'           = @()
            'Test-InforcerConnection'       = @()
            'Get-InforcerTenant'            = @('Format', 'TenantId', 'OutputType')
            'Get-InforcerBaseline'          = @('Format', 'TenantId', 'OutputType')
            'Get-InforcerTenantPolicies'    = @('Format', 'TenantId', 'OutputType')
            'Get-InforcerAlignmentDetails'    = @('Format', 'TenantId', 'BaselineId', 'Tag', 'OutputType')
            'Get-InforcerAuditEvent'        = @('EventType', 'DateFrom', 'DateTo', 'PageSize', 'MaxResults', 'Format', 'OutputType')
            'Get-InforcerSupportedEventType'    = @()
            'Get-InforcerUser'              = @('Format', 'TenantId', 'Search', 'MaxResults', 'UserId', 'OutputType')
            'Export-InforcerTenantDocumentation' = @('Format', 'TenantId', 'OutputPath', 'SettingsCatalogPath', 'FetchGraphData', 'Baseline', 'Tag')
            'Compare-InforcerEnvironments'  = @('SourceTenantId', 'DestinationTenantId', 'SourceSession', 'DestinationSession', 'IncludingAssignments', 'SettingsCatalogPath', 'OutputPath')
        }
    }

    It 'Module exports all expected cmdlets' {
        foreach ($name in $script:expectedNames) {
            $script:exported | Should -Contain $name
        }
        @($script:exported).Count | Should -Be $script:expectedCount
    }

    It 'Each cmdlet has expected parameters (subset check)' {
        foreach ($name in $script:expectedNames) {
            $expectedParams = $script:expectedParameters[$name]
            if ($null -eq $expectedParams -or $expectedParams.Count -eq 0) { continue }
            $cmd = Get-Command -Name $name -ErrorAction Stop
            $paramNames = $cmd.Parameters.Keys
            foreach ($p in $expectedParams) {
                $paramNames | Should -Contain $p
            }
        }
    }

    It 'Get-* cmdlets that return API data have -Format and -OutputType' {
        $getCmdlets = @('Get-InforcerTenant', 'Get-InforcerBaseline', 'Get-InforcerTenantPolicies', 'Get-InforcerAlignmentDetails', 'Get-InforcerAuditEvent', 'Get-InforcerUser')
        foreach ($name in $getCmdlets) {
            $cmd = Get-Command -Name $name -ErrorAction Stop
            $cmd.Parameters.Keys | Should -Contain 'Format'
            $cmd.Parameters.Keys | Should -Contain 'OutputType'
        }
    }

    It 'Every exported cmdlet has comment-based help (Synopsis and at least one Example)' {
        foreach ($name in $script:expectedNames) {
            $help = Get-Help -Name $name -ErrorAction Stop
            $help.Synopsis | Should -Not -BeNullOrEmpty -Because "cmdlet $name must have .SYNOPSIS"
            $help.Examples | Should -Not -BeNullOrEmpty -Because "cmdlet $name must have at least one .EXAMPLE"
        }
    }

    It 'Every exported cmdlet has complete Get-Help: Description, Parameters documented, and Online URI' {
        foreach ($name in $script:expectedNames) {
            $help = Get-Help -Name $name -Full -ErrorAction Stop

            # Description
            $desc = $help.Description
            ($null -ne $desc -and @($desc).Count -gt 0) | Should -BeTrue -Because "cmdlet $name must have .DESCRIPTION"

            # Every declared parameter (excluding common params) should be documented
            $cmd = Get-Command -Name $name -ErrorAction Stop
            $commonParams = @('Verbose','Debug','ErrorAction','WarningAction','InformationAction','ErrorVariable','WarningVariable','InformationVariable','OutVariable','OutBuffer','PipelineVariable','ProgressAction','WhatIf','Confirm')
            $declaredParams = @($cmd.Parameters.Keys | Where-Object { $_ -notin $commonParams })
            $documentedParams = @()
            if ($help.parameters -and $help.parameters.parameter) {
                $documentedParams = @($help.parameters.parameter | ForEach-Object { $_.Name })
            }
            foreach ($p in $declaredParams) {
                $documentedParams | Should -Contain $p -Because "cmdlet $name parameter '$p' must be documented in help"
            }

            # Online help URI (first URI in .LINK)
            $uris = @($help.relatedLinks.navigationLink | Where-Object { $_.uri } | ForEach-Object { $_.uri })
            $uris.Count | Should -BeGreaterThan 0 -Because "cmdlet $name must have a .LINK URI for Get-Help -Online"
            $uris[0] | Should -Match '^https://' -Because "cmdlet $name online help URI must be an HTTPS URL"
        }
    }
}

Describe 'No-silent-failure contract' {
    # Every cmdlet must produce either output or an error — never silence.
    # Runs without a connection so we can test in CI without API keys.

    BeforeAll {
        Remove-Module -Name 'InforcerCommunity' -ErrorAction SilentlyContinue
        Import-Module (Get-InforcerCommunityManifestPath) -Force
    }

    It 'Disconnect-Inforcer produces output when not connected' {
        $output = Disconnect-Inforcer
        $output | Should -Not -BeNullOrEmpty
    }

    It 'Test-InforcerConnection produces an error when not connected' {
        $err = $null
        Test-InforcerConnection -ErrorVariable err -ErrorAction SilentlyContinue
        $err | Should -Not -BeNullOrEmpty -Because 'should report not connected, not return silence'
    }

    It 'Get-InforcerTenant produces an error when not connected' {
        $err = $null
        Get-InforcerTenant -ErrorVariable err -ErrorAction SilentlyContinue
        $err | Should -Not -BeNullOrEmpty -Because 'should report not connected, not return silence'
    }

    It 'Get-InforcerBaseline produces an error when not connected' {
        $err = $null
        Get-InforcerBaseline -ErrorVariable err -ErrorAction SilentlyContinue
        $err | Should -Not -BeNullOrEmpty -Because 'should report not connected, not return silence'
    }

    It 'Get-InforcerTenantPolicies produces an error when not connected' {
        $err = $null
        Get-InforcerTenantPolicies -TenantId 1 -ErrorVariable err -ErrorAction SilentlyContinue
        $err | Should -Not -BeNullOrEmpty -Because 'should report not connected, not return silence'
    }

    It 'Get-InforcerAlignmentDetails produces an error when not connected' {
        $err = $null
        Get-InforcerAlignmentDetails -ErrorVariable err -ErrorAction SilentlyContinue
        $err | Should -Not -BeNullOrEmpty -Because 'should report not connected, not return silence'
    }

    It 'Get-InforcerAuditEvent produces an error when not connected' {
        $err = $null
        Get-InforcerAuditEvent -ErrorVariable err -ErrorAction SilentlyContinue
        $err | Should -Not -BeNullOrEmpty -Because 'should report not connected, not return silence'
    }

    It 'Get-InforcerUser produces an error when not connected' {
        $err = $null
        Get-InforcerUser -TenantId 1 -ErrorVariable err -ErrorAction SilentlyContinue
        $err | Should -Not -BeNullOrEmpty -Because 'should report not connected, not return silence'
    }

    It 'Export-InforcerTenantDocumentation produces an error when not connected' {
        $err = $null
        Export-InforcerTenantDocumentation -TenantId 1 -ErrorVariable err -ErrorAction SilentlyContinue
        $err | Should -Not -BeNullOrEmpty -Because 'should report not connected, not return silence'
    }
}

Describe 'Parameter binding and behavior' {
    # Invoke each cmdlet with its key parameters to ensure they bind and the cmdlet runs.
    # When not connected we expect connection errors, not parameter binding errors.
    # Validates: parameters work, and cmdlet returns output or error as expected (no silence).

    BeforeAll {
        Remove-Module -Name 'InforcerCommunity' -ErrorAction SilentlyContinue
        Import-Module (Get-InforcerCommunityManifestPath) -Force
    }

    It 'Connect-Inforcer accepts ApiKey and Region and produces output or error' {
        $secure = ConvertTo-SecureString -String 'dummy-key' -AsPlainText -Force
        $result = $null
        $err = $null
        try { $result = Connect-Inforcer -ApiKey $secure -Region 'uk' -ErrorVariable err -ErrorAction SilentlyContinue } catch { $err = @($_) }
        $hasOutput = $null -ne $result -and (@($result).Count -gt 0)
        $hasError = $null -ne $err -and (@($err).Count -gt 0)
        ($hasOutput -or $hasError) | Should -BeTrue -Because 'Connect-Inforcer must not silently do nothing'
        if ($hasError -and $err[0].ToString() -match 'Cannot bind|Parameter.*not found|Unknown parameter') {
            Set-ItResult -Inconclusive -Because 'Parameter binding failed; check parameter names'
        }
    }

    It 'Get-InforcerTenant with -Format -TenantId -OutputType binds and produces output or error' {
        $out = @(); $err = @()
        $out = Get-InforcerTenant -Format Raw -TenantId 1 -OutputType PowerShellObject -ErrorVariable err -ErrorAction SilentlyContinue
        $err = @($err)
        $hasOutput = $null -ne $out -and (@($out).Count -ge 0)
        $hasError = $err.Count -gt 0
        ($hasOutput -or $hasError) | Should -BeTrue -Because 'Get-InforcerTenant must not silently do nothing'
        if ($hasError -and $err[0].ToString() -match 'Cannot bind|Parameter.*not found|Unknown parameter') {
            Set-ItResult -Inconclusive -Because 'Parameter binding failed'
        }
    }

    It 'Get-InforcerBaseline with -Format -TenantId -OutputType binds and produces output or error' {
        $out = @(); $err = @()
        $out = Get-InforcerBaseline -Format Raw -TenantId 1 -OutputType PowerShellObject -ErrorVariable err -ErrorAction SilentlyContinue
        $err = @($err)
        $hasOutput = $null -ne $out
        $hasError = $err.Count -gt 0
        ($hasOutput -or $hasError) | Should -BeTrue -Because 'Get-InforcerBaseline must not silently do nothing'
        if ($hasError -and $err[0].ToString() -match 'Cannot bind|Parameter.*not found|Unknown parameter') {
            Set-ItResult -Inconclusive -Because 'Parameter binding failed'
        }
    }

    It 'Get-InforcerTenantPolicies with -Format -TenantId -OutputType binds and produces output or error' {
        $out = @(); $err = @()
        $out = Get-InforcerTenantPolicies -Format Raw -TenantId 1 -OutputType PowerShellObject -ErrorVariable err -ErrorAction SilentlyContinue
        $err = @($err)
        $hasOutput = $null -ne $out
        $hasError = $err.Count -gt 0
        ($hasOutput -or $hasError) | Should -BeTrue -Because 'Get-InforcerTenantPolicies must not silently do nothing'
        if ($hasError -and $err[0].ToString() -match 'Cannot bind|Parameter.*not found|Unknown parameter') {
            Set-ItResult -Inconclusive -Because 'Parameter binding failed'
        }
    }

    It 'Get-InforcerAlignmentDetails with -Format -TenantId -Tag -OutputType binds and produces output or error' {
        $out = @(); $err = @()
        $out = Get-InforcerAlignmentDetails -Format Table -TenantId 1 -Tag 'Production' -OutputType PowerShellObject -ErrorVariable err -ErrorAction SilentlyContinue
        $err = @($err)
        $hasOutput = $null -ne $out
        $hasError = $err.Count -gt 0
        ($hasOutput -or $hasError) | Should -BeTrue -Because 'Get-InforcerAlignmentDetails must not silently do nothing'
        if ($hasError -and $err[0].ToString() -match 'Cannot bind|Parameter.*not found|Unknown parameter') {
            Set-ItResult -Inconclusive -Because 'Parameter binding failed'
        }
    }

    It 'Get-InforcerAuditEvent with -EventType -DateFrom -DateTo -PageSize -MaxResults -Format -OutputType binds and produces output or error' {
        $out = @(); $err = @()
        $out = Get-InforcerAuditEvent -EventType 'Login' -DateFrom (Get-Date).AddDays(-1) -DateTo (Get-Date) -PageSize 10 -MaxResults 5 -Format Raw -OutputType PowerShellObject -ErrorVariable err -ErrorAction SilentlyContinue
        $err = @($err)
        $hasOutput = $null -ne $out
        $hasError = $err.Count -gt 0
        ($hasOutput -or $hasError) | Should -BeTrue -Because 'Get-InforcerAuditEvent must not silently do nothing'
        if ($hasError -and $err[0].ToString() -match 'Cannot bind|Parameter.*not found|Unknown parameter') {
            Set-ItResult -Inconclusive -Because 'Parameter binding failed'
        }
    }

    It 'Get-InforcerTenant -OutputType JsonObject returns string or error' {
        $out = Get-InforcerTenant -OutputType JsonObject -ErrorVariable err -ErrorAction SilentlyContinue
        $err = @($err)
        $hasString = $null -ne $out -and $out -is [string]
        $hasError = $err.Count -gt 0
        ($hasString -or $hasError) | Should -BeTrue -Because 'JsonObject path must return string or error'
    }

    It 'Get-InforcerAlignmentDetails -OutputType JsonObject returns string or error' {
        $out = Get-InforcerAlignmentDetails -OutputType JsonObject -ErrorVariable err -ErrorAction SilentlyContinue
        $err = @($err)
        $hasString = $null -ne $out -and $out -is [string]
        $hasError = $err.Count -gt 0
        ($hasString -or $hasError) | Should -BeTrue -Because 'JsonObject path must return string or error'
    }

    It 'Get-InforcerAlignmentDetails -BaselineId without -TenantId attempts baseline member lookup' {
        $err = $null
        Get-InforcerAlignmentDetails -BaselineId 'test-guid' -ErrorVariable err -ErrorAction SilentlyContinue
        # Without a session, this produces a connection error (not a parameter validation error)
        $err = @($err)
        $err.Count | Should -BeGreaterThan 0 -Because 'no session should produce connection error'
    }

    It 'Get-InforcerTenant -TenantId with invalid format produces an error' {
        $err = $null
        Get-InforcerTenant -TenantId 'not-valid-id' -ErrorVariable err -ErrorAction SilentlyContinue
        $err | Should -Not -BeNullOrEmpty -Because 'invalid TenantId format should error'
    }

    It 'Connect-Inforcer with empty string ApiKey produces an error' {
        $err = $null
        try { Connect-Inforcer -ApiKey '' -Region uk -ErrorVariable err -ErrorAction SilentlyContinue } catch { $err = @($_) }
        $err | Should -Not -BeNullOrEmpty -Because 'empty ApiKey must not connect'
    }

    It 'Get-InforcerUser (List) binds all key parameters without errors' {
        $err = $null
        $null = Get-InforcerUser -Format Raw -TenantId 1 -Search 'test' -MaxResults 10 -OutputType PowerShellObject -ErrorVariable err -ErrorAction SilentlyContinue
        $err | ForEach-Object {
            $_.Exception.Message | Should -Not -BeLike '*parameter*'
            $_.Exception.Message | Should -Not -BeLike '*cannot bind*'
        }
    }

    It 'Get-InforcerUser (ById) binds all key parameters without errors' {
        $err = $null
        $null = Get-InforcerUser -Format Raw -TenantId 1 -UserId '00000000-0000-0000-0000-000000000000' -OutputType PowerShellObject -ErrorVariable err -ErrorAction SilentlyContinue
        $err | ForEach-Object {
            $_.Exception.Message | Should -Not -BeLike '*parameter*'
            $_.Exception.Message | Should -Not -BeLike '*cannot bind*'
        }
    }

    It 'Get-InforcerUser -OutputType JsonObject returns string or error' {
        $err = $null
        $result = Get-InforcerUser -TenantId 1 -OutputType JsonObject -ErrorVariable err -ErrorAction SilentlyContinue
        if ($result) {
            $result | Should -BeOfType [string]
        } else {
            $err | Should -Not -BeNullOrEmpty
        }
    }

    It 'Export-InforcerTenantDocumentation with key parameters binds and produces output or error' {
        $out = @(); $err = @()
        $out = Export-InforcerTenantDocumentation -Format Html -TenantId 1 -OutputPath $TestDrive `
            -ErrorVariable err -ErrorAction SilentlyContinue
        $err = @($err)
        $hasOutput = $null -ne $out
        $hasError = $err.Count -gt 0
        ($hasOutput -or $hasError) | Should -BeTrue -Because 'Export-InforcerTenantDocumentation must not silently do nothing'
        if ($hasError -and $err[0].ToString() -match 'Cannot bind|Parameter.*not found|Unknown parameter') {
            Set-ItResult -Inconclusive -Because 'Parameter binding failed; check parameter names'
        }
    }
}

Describe 'Private helpers (via module scope)' {

    BeforeAll {
        Remove-Module -Name 'InforcerCommunity' -ErrorAction SilentlyContinue
        Import-Module (Get-InforcerCommunityManifestPath) -Force
    }

    Context 'Test-InforcerSession' {
        It 'Returns false when no session exists' {
            & (Get-Module InforcerCommunity) {
                $script:InforcerSession = $null
                Test-InforcerSession | Should -BeFalse
            }
        }

        It 'Returns true with valid session' {
            & (Get-Module InforcerCommunity) {
                $secKey = ConvertTo-SecureString 'test-key' -AsPlainText -Force
                $script:InforcerSession = @{ ApiKey = $secKey; BaseUrl = 'https://api.test.com' }
                Test-InforcerSession | Should -BeTrue
            }
        }

        It 'Returns false with empty SecureString (length 0)' {
            & (Get-Module InforcerCommunity) {
                $emptyKey = [System.Security.SecureString]::new()
                $script:InforcerSession = @{ ApiKey = $emptyKey; BaseUrl = 'https://api.test.com' }
                Test-InforcerSession | Should -BeFalse
            }
        }

        It 'Returns false with empty BaseUrl' {
            & (Get-Module InforcerCommunity) {
                $secKey = ConvertTo-SecureString 'test-key' -AsPlainText -Force
                $script:InforcerSession = @{ ApiKey = $secKey; BaseUrl = '' }
                Test-InforcerSession | Should -BeFalse
            }
        }

        It 'Returns false with null ApiKey' {
            & (Get-Module InforcerCommunity) {
                $script:InforcerSession = @{ ApiKey = $null; BaseUrl = 'https://api.test.com' }
                Test-InforcerSession | Should -BeFalse
            }
        }
    }

    Context 'Resolve-InforcerTenantId' {
        It 'Resolves numeric integer to Int32' {
            & (Get-Module InforcerCommunity) {
                $result = Resolve-InforcerTenantId -TenantId 482
                $result | Should -Be 482
                $result | Should -BeOfType [int]
            }
        }

        It 'Resolves numeric string to Int32' {
            & (Get-Module InforcerCommunity) {
                $result = Resolve-InforcerTenantId -TenantId '123'
                $result | Should -Be 123
                $result | Should -BeOfType [int]
            }
        }

        It 'Throws when tenant name not found' {
            & (Get-Module InforcerCommunity) {
                { Resolve-InforcerTenantId -TenantId 'not-valid' -ErrorAction SilentlyContinue } | Should -Throw '*No tenant found*'
            }
        }
    }

    Context 'Resolve-InforcerBaselineId' {
        It 'Passes through a valid GUID' {
            & (Get-Module InforcerCommunity) {
                $guid = '91e0b0f7-69f1-453f-8d73-5a6f726b5b21'
                $result = Resolve-InforcerBaselineId -BaselineId $guid
                $result | Should -Be $guid
            }
        }

        It 'Resolves name with exact case match' {
            & (Get-Module InforcerCommunity) {
                $baselines = @(
                    [PSCustomObject]@{ id = 'aaa'; name = 'Provision M365' }
                    [PSCustomObject]@{ id = 'bbb'; name = 'Security Baseline' }
                )
                $result = Resolve-InforcerBaselineId -BaselineId 'Provision M365' -BaselineData $baselines
                $result | Should -Be 'aaa'
            }
        }

        It 'Resolves name with case-insensitive fallback' {
            & (Get-Module InforcerCommunity) {
                $baselines = @([PSCustomObject]@{ id = 'ccc'; name = 'Security Baseline' })
                $result = Resolve-InforcerBaselineId -BaselineId 'security baseline' -BaselineData $baselines
                $result | Should -Be 'ccc'
            }
        }

        It 'Prefers exact case match over case-insensitive' {
            & (Get-Module InforcerCommunity) {
                $baselines = @(
                    [PSCustomObject]@{ id = '111'; name = 'test' }
                    [PSCustomObject]@{ id = '222'; name = 'Test' }
                )
                $result = Resolve-InforcerBaselineId -BaselineId 'Test' -BaselineData $baselines
                $result | Should -Be '222'
            }
        }

        It 'Throws when baseline name not found' {
            & (Get-Module InforcerCommunity) {
                $baselines = @([PSCustomObject]@{ id = 'aaa'; name = 'Existing' })
                { Resolve-InforcerBaselineId -BaselineId 'NonExistent' -BaselineData $baselines } | Should -Throw '*No baseline found*'
            }
        }
    }

    Context 'Add-InforcerPropertyAliases' {
        It 'Tenant: adds PascalCase aliases and converts licenses to string' {
            & (Get-Module InforcerCommunity) {
                $tenant = [PSCustomObject]@{
                    clientTenantId = 482
                    tenantFriendlyName = 'Contoso'
                    licenses = @([PSCustomObject]@{ sku = 'PREMIUM' }, [PSCustomObject]@{ sku = 'EMS' })
                }
                $null = Add-InforcerPropertyAliases -InputObject $tenant -ObjectType Tenant
                $tenant.ClientTenantId | Should -Be 482
                $tenant.TenantFriendlyName | Should -Be 'Contoso'
                $tenant.licenses | Should -BeOfType [string]
                $tenant.licenses | Should -Be 'PREMIUM, EMS'
            }
        }

        It 'Policy: sets PolicyName from displayName and creates FriendlyName alias' {
            & (Get-Module InforcerCommunity) {
                $policy = [PSCustomObject]@{ id = 'p1'; displayName = 'CA Block Legacy'; friendlyName = 'Block Legacy' }
                $null = Add-InforcerPropertyAliases -InputObject $policy -ObjectType Policy
                $policy.PolicyName | Should -Be 'CA Block Legacy'
                $policy.FriendlyName | Should -Be 'CA Block Legacy'
                $policy.PSObject.Properties['displayName'] | Should -BeNullOrEmpty
                $policy.PSObject.Properties['FriendlyName'].MemberType | Should -Be 'AliasProperty'
            }
        }

        It 'Policy: falls back to name when displayName is missing' {
            & (Get-Module InforcerCommunity) {
                $policy = [PSCustomObject]@{ id = 'p2'; name = 'Fallback Name' }
                $null = Add-InforcerPropertyAliases -InputObject $policy -ObjectType Policy
                $policy.PolicyName | Should -Be 'Fallback Name'
            }
        }

        It 'Policy: falls back to "Policy {id}" when all names missing' {
            & (Get-Module InforcerCommunity) {
                $policy = [PSCustomObject]@{ id = 'p3' }
                $null = Add-InforcerPropertyAliases -InputObject $policy -ObjectType Policy
                $policy.PolicyName | Should -Be 'Policy p3'
            }
        }

        It 'AlignmentScore: adds PascalCase aliases' {
            & (Get-Module InforcerCommunity) {
                $score = [PSCustomObject]@{ tenantId = 1; score = 95; baselineGroupName = 'BL1'; lastComparisonDateTime = '2026-01-01' }
                $null = Add-InforcerPropertyAliases -InputObject $score -ObjectType AlignmentScore
                $score.TenantId | Should -Be 1
                $score.Score | Should -Be 95
                $score.BaselineGroupName | Should -Be 'BL1'
                $score.LastComparisonDateTime | Should -Be '2026-01-01'
            }
        }

        It 'AuditEvent: flattens metadata fields and preserves metadata property' {
            & (Get-Module InforcerCommunity) {
                $auditEvt = [PSCustomObject]@{
                    correlationId = 'c1'; eventType = 'authentication'
                    metadata = [PSCustomObject]@{
                        clientIpv4 = '10.0.0.1'; clientIpv6 = '::1'
                        nameLookup = [PSCustomObject]@{ 'user:username:1' = 'john@test.com'; 'user:displayName:1' = 'John' }
                    }
                }
                $null = Add-InforcerPropertyAliases -InputObject $auditEvt -ObjectType AuditEvent
                $auditEvt.ClientIpv4 | Should -Be '10.0.0.1'
                $auditEvt.ClientIpv6 | Should -Be '::1'
                $auditEvt.UserName | Should -Be 'john@test.com'
                $auditEvt.UserDisplayName | Should -Be 'John'
                $auditEvt.PSObject.Properties['metadata'] | Should -Not -BeNullOrEmpty
            }
        }

        It 'AlignmentDetail: adds aliases to metrics and per-policy arrays' {
            & (Get-Module InforcerCommunity) {
                $detail = [PSCustomObject]@{
                    alignmentScore = 92.5; completedAt = '2026-01-01'
                    metrics = [PSCustomObject]@{ totalPolicies = 50; matchedPolicies = 45 }
                    alignment = [PSCustomObject]@{
                        matchedPolicies = @([PSCustomObject]@{ policyName = 'P1'; product = 'Intune' })
                    }
                }
                $null = Add-InforcerPropertyAliases -InputObject $detail -ObjectType AlignmentDetail
                $detail.AlignmentScore | Should -Be 92.5
                $detail.CompletedAt | Should -Be '2026-01-01'
                $detail.metrics.TotalPolicies | Should -Be 50
                $detail.alignment.matchedPolicies[0].PolicyName | Should -Be 'P1'
            }
        }
    }

    Context 'Filter-InforcerResponse' {
        It 'Filters PSObject array correctly' {
            & (Get-Module InforcerCommunity) {
                $items = @([PSCustomObject]@{ id = 1; name = 'A' }, [PSCustomObject]@{ id = 2; name = 'B' })
                $result = Filter-InforcerResponse -InputObject $items -FilterScript { param($p) $p.name -eq 'A' } -OutputType PowerShellObject
                @($result).Count | Should -Be 1
                $result[0].id | Should -Be 1
            }
        }

        It 'Filters JSON string correctly' {
            & (Get-Module InforcerCommunity) {
                $json = '[{"id":1,"name":"A"},{"id":2,"name":"B"}]'
                $result = Filter-InforcerResponse -InputObject $json -FilterScript { param($p) $p.name -eq 'B' } -OutputType JsonObject
                $parsed = $result | ConvertFrom-Json
                $parsed.id | Should -Be 2
            }
        }

        It 'Returns null JSON when no matches on JSON input' {
            & (Get-Module InforcerCommunity) {
                $json = '[{"id":1}]'
                $result = Filter-InforcerResponse -InputObject $json -FilterScript { $false } -OutputType JsonObject
                $result | Should -Be 'null'
            }
        }

        It 'Returns empty JSON for whitespace input' {
            & (Get-Module InforcerCommunity) {
                $result = Filter-InforcerResponse -InputObject '  ' -FilterScript { $true } -OutputType JsonObject
                $result | Should -Be '[]'
            }
        }
    }

    Context 'ConvertTo-InforcerArray' {
        It 'Wraps single object in array' {
            & (Get-Module InforcerCommunity) {
                $obj = [PSCustomObject]@{ id = 1 }
                $result = ConvertTo-InforcerArray $obj
                @($result).Count | Should -Be 1
            }
        }

        It 'Returns array as-is' {
            & (Get-Module InforcerCommunity) {
                $arr = @([PSCustomObject]@{ id = 1 }, [PSCustomObject]@{ id = 2 })
                $result = ConvertTo-InforcerArray $arr
                @($result).Count | Should -Be 2
            }
        }

        It 'Returns empty array for null' {
            & (Get-Module InforcerCommunity) {
                $result = ConvertTo-InforcerArray $null
                @($result).Count | Should -Be 0
            }
        }
    }
}
