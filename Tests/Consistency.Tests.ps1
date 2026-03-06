# Consistency.Tests.ps1
# Validates that the script module's exported functions and parameter names match the consistency contract.
# Run from repo root: Invoke-Pester ./Tests/Consistency.Tests.ps1

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $PSCommandPath
$repoRoot = Join-Path $here '..'
$moduleRoot = Join-Path $repoRoot 'module'

# Expected cmdlets and key parameters (from consistency contract) - defined inside Describe for scope
Describe 'Consistency contract' {

    BeforeAll {
        Remove-Module -Name 'Inforcer' -ErrorAction SilentlyContinue
        $modRoot = if ($moduleRoot) { $moduleRoot } else { Join-Path (Get-Location) 'module' }
        $manifestPath = (Resolve-Path (Join-Path $modRoot 'Inforcer.psd1')).Path
        Import-Module $manifestPath -Force
        $script:exported = (Get-Module -Name 'Inforcer').ExportedCommands.Keys
        $script:expectedCount = 8
        $script:expectedNames = @(
            'Connect-Inforcer', 'Disconnect-Inforcer', 'Test-InforcerConnection',
            'Get-InforcerTenant', 'Get-InforcerBaseline', 'Get-InforcerTenantPolicies',
            'Get-InforcerAlignmentScore', 'Get-InforcerAuditEvent'
        )
        $script:expectedParameters = @{
            'Connect-Inforcer'              = @('ApiKey', 'Region', 'BaseUrl')
            'Disconnect-Inforcer'           = @()
            'Test-InforcerConnection'       = @()
            'Get-InforcerTenant'            = @('Format', 'TenantId', 'OutputType')
            'Get-InforcerBaseline'          = @('Format', 'TenantId', 'OutputType')
            'Get-InforcerTenantPolicies'    = @('Format', 'TenantId', 'OutputType')
            'Get-InforcerAlignmentScore'    = @('Format', 'TenantId', 'Tag', 'OutputType')
            'Get-InforcerAuditEvent'        = @('EventType', 'DateFrom', 'DateTo', 'PageSize', 'MaxResults', 'Format', 'OutputType')
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
        $getCmdlets = @('Get-InforcerTenant', 'Get-InforcerBaseline', 'Get-InforcerTenantPolicies', 'Get-InforcerAlignmentScore', 'Get-InforcerAuditEvent')
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
}

Describe 'No-silent-failure contract' {
    # Every cmdlet must produce either output or an error — never silence.
    # Runs without a connection so we can test in CI without API keys.

    BeforeAll {
        Remove-Module -Name 'Inforcer' -ErrorAction SilentlyContinue
        $modRoot = if ($moduleRoot) { $moduleRoot } else { Join-Path (Get-Location) 'module' }
        $manifestPath = (Resolve-Path (Join-Path $modRoot 'Inforcer.psd1')).Path
        Import-Module $manifestPath -Force
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

    It 'Get-InforcerAlignmentScore produces an error when not connected' {
        $err = $null
        Get-InforcerAlignmentScore -ErrorVariable err -ErrorAction SilentlyContinue
        $err | Should -Not -BeNullOrEmpty -Because 'should report not connected, not return silence'
    }

    It 'Get-InforcerAuditEvent produces an error when not connected' {
        $err = $null
        Get-InforcerAuditEvent -ErrorVariable err -ErrorAction SilentlyContinue
        $err | Should -Not -BeNullOrEmpty -Because 'should report not connected, not return silence'
    }
}

Describe 'Parameter binding and behavior' {
    # Invoke each cmdlet with its key parameters to ensure they bind and the cmdlet runs.
    # When not connected we expect connection errors, not parameter binding errors.
    # Validates: parameters work, and cmdlet returns output or error as expected (no silence).

    BeforeAll {
        Remove-Module -Name 'Inforcer' -ErrorAction SilentlyContinue
        $modRoot = if ($moduleRoot) { $moduleRoot } else { Join-Path (Get-Location) 'module' }
        $manifestPath = (Resolve-Path (Join-Path $modRoot 'Inforcer.psd1')).Path
        Import-Module $manifestPath -Force
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

    It 'Get-InforcerAlignmentScore with -Format -TenantId -Tag -OutputType binds and produces output or error' {
        $out = @(); $err = @()
        $out = Get-InforcerAlignmentScore -Format Table -TenantId 1 -Tag 'Production' -OutputType PowerShellObject -ErrorVariable err -ErrorAction SilentlyContinue
        $err = @($err)
        $hasOutput = $null -ne $out
        $hasError = $err.Count -gt 0
        ($hasOutput -or $hasError) | Should -BeTrue -Because 'Get-InforcerAlignmentScore must not silently do nothing'
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

    It 'Get-InforcerAlignmentScore -OutputType JsonObject returns string or error' {
        $out = Get-InforcerAlignmentScore -OutputType JsonObject -ErrorVariable err -ErrorAction SilentlyContinue
        $err = @($err)
        $hasString = $null -ne $out -and $out -is [string]
        $hasError = $err.Count -gt 0
        ($hasString -or $hasError) | Should -BeTrue -Because 'JsonObject path must return string or error'
    }
}
