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
        $script:expectedCount = 9
        $script:expectedNames = @(
            'Connect-Inforcer', 'Disconnect-Inforcer', 'Test-InforcerConnection',
            'Get-InforcerTenant', 'Get-InforcerBaseline', 'Get-InforcerTenantPolicies',
            'Get-InforcerAlignmentScore', 'Get-InforcerAuditEvent', 'Get-InforcerAuditEventType'
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
            'Get-InforcerAuditEventType'    = @()
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

    It 'Get-InforcerAuditEventType returns cached event types without a connection' {
        $output = @(Get-InforcerAuditEventType -ErrorAction SilentlyContinue)
        $output.Count | Should -BeGreaterThan 0 -Because 'should fall back to built-in cached types'
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
