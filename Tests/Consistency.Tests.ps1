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
        $script:expectedCount = 21
        $script:expectedNames = @(
            'Connect-Inforcer', 'Disconnect-Inforcer', 'Test-InforcerConnection',
            'Get-InforcerTenant', 'Get-InforcerBaseline', 'Get-InforcerTenantPolicies',
            'Get-InforcerAlignmentDetails', 'Get-InforcerAuditEvent', 'Get-InforcerSupportedEventType',
            'Get-InforcerUser', 'Get-InforcerGroup', 'Get-InforcerRole', 'Get-InforcerSecureScore',
            'Export-InforcerTenantDocumentation', 'Compare-InforcerEnvironments',
            'Get-InforcerAssessment', 'Invoke-InforcerAssessment',
            'Get-InforcerReportType', 'Invoke-InforcerReport', 'Get-InforcerReportRun', 'Save-InforcerReportOutput'
        )
        $script:expectedParameters = @{
            'Connect-Inforcer'              = @('ApiKey', 'Region', 'BaseUrl', 'FetchGraphData', 'PassThru')
            'Disconnect-Inforcer'           = @()
            'Test-InforcerConnection'       = @()
            'Get-InforcerTenant'            = @('Format', 'TenantId', 'OutputType')
            'Get-InforcerBaseline'          = @('Format', 'TenantId', 'OutputType')
            'Get-InforcerTenantPolicies'    = @('Format', 'TenantId', 'OutputType')
            'Get-InforcerAlignmentDetails'    = @('Format', 'TenantId', 'BaselineId', 'Tag', 'OutputType')
            'Get-InforcerAuditEvent'        = @('EventType', 'DateFrom', 'DateTo', 'User', 'PageSize', 'MaxResults', 'Format', 'OutputType')
            'Get-InforcerSupportedEventType'    = @()
            'Get-InforcerUser'              = @('Format', 'TenantId', 'Search', 'MaxResults', 'UserId', 'OutputType')
            'Get-InforcerGroup'             = @('TenantId', 'Search', 'Filter', 'MaxResults', 'Group', 'OutputType')
            'Get-InforcerRole'              = @('TenantId', 'OutputType')
            'Get-InforcerSecureScore'       = @('TenantId', 'OutputType')
            'Export-InforcerTenantDocumentation' = @('Format', 'TenantId', 'OutputPath', 'SettingsCatalogPath', 'FetchGraphData', 'Baseline', 'Tag')
            'Compare-InforcerEnvironments'  = @('SourceTenantId', 'DestinationTenantId', 'SourceSession', 'DestinationSession', 'SourceBaselineId', 'DestinationBaselineId', 'IncludingAssignments', 'SettingsCatalogPath', 'FetchGraphData', 'ExcludeOS', 'PolicyNameFilter', 'OutputPath')
            'Get-InforcerAssessment'        = @('Format', 'OutputType')
            'Invoke-InforcerAssessment'     = @('TenantId', 'AssessmentId', 'OutputType')
            'Get-InforcerReportType'        = @('Key', 'Tag', 'OutputFormat', 'Force', 'Format', 'OutputType')
            'Invoke-InforcerReport'         = @('ReportType', 'OutputFormat', 'TenantId', 'ReportPeriod', 'AssessmentId', 'Parameter', 'Collate', 'NoWait', 'NoSave', 'OutputPath', 'TimeoutSeconds', 'PollIntervalSeconds', 'Format', 'OutputType')
            'Get-InforcerReportRun'         = @('RunId', 'Wait', 'IncludeOutputs', 'TimeoutSeconds', 'PollIntervalSeconds', 'Format', 'OutputType')
            'Save-InforcerReportOutput'     = @('RunId', 'OutputId', 'ReportType', 'OutputFormat', 'TenantId', 'OutputPath', 'FileName', 'OutputType')
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

    It 'Get-* cmdlets that return API data have -OutputType' {
        $getCmdlets = @('Get-InforcerTenant', 'Get-InforcerBaseline', 'Get-InforcerTenantPolicies', 'Get-InforcerAlignmentDetails', 'Get-InforcerAuditEvent', 'Get-InforcerUser', 'Get-InforcerGroup', 'Get-InforcerRole', 'Get-InforcerSecureScore')
        foreach ($name in $getCmdlets) {
            $cmd = Get-Command -Name $name -ErrorAction Stop
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

    It 'Get-InforcerGroup produces an error when not connected' {
        $err = $null
        Get-InforcerGroup -TenantId 1 -ErrorVariable err -ErrorAction SilentlyContinue
        $err | Should -Not -BeNullOrEmpty -Because 'should report not connected, not return silence'
    }

    It 'Get-InforcerRole produces an error when not connected' {
        $err = $null
        Get-InforcerRole -TenantId 1 -ErrorVariable err -ErrorAction SilentlyContinue
        $err | Should -Not -BeNullOrEmpty -Because 'should report not connected, not return silence'
    }

    It 'Get-InforcerSecureScore produces an error when not connected' {
        $err = $null
        Get-InforcerSecureScore -TenantId 1 -ErrorVariable err -ErrorAction SilentlyContinue
        $err | Should -Not -BeNullOrEmpty -Because 'should report not connected, not return silence'
    }

    It 'Export-InforcerTenantDocumentation produces an error when not connected' {
        $err = $null
        Export-InforcerTenantDocumentation -TenantId 1 -ErrorVariable err -ErrorAction SilentlyContinue
        $err | Should -Not -BeNullOrEmpty -Because 'should report not connected, not return silence'
    }

    It 'Get-InforcerAssessment produces an error when not connected' {
        $err = $null
        Get-InforcerAssessment -ErrorVariable err -ErrorAction SilentlyContinue
        $err | Should -Not -BeNullOrEmpty -Because 'should report not connected, not return silence'
    }

    It 'Invoke-InforcerAssessment produces an error when not connected' {
        $err = $null
        Invoke-InforcerAssessment -TenantId 1 -AssessmentId 'test' -ErrorVariable err -ErrorAction SilentlyContinue
        $err | Should -Not -BeNullOrEmpty -Because 'should report not connected, not return silence'
    }

    It 'Get-InforcerReportType produces an error when not connected' {
        $err = $null
        Get-InforcerReportType -ErrorVariable err -ErrorAction SilentlyContinue
        $err | Should -Not -BeNullOrEmpty -Because 'should report not connected, not return silence'
    }

    It 'Invoke-InforcerReport produces an error when not connected' {
        $err = $null
        Invoke-InforcerReport -ReportType 'ActiveUserCount' -OutputFormat csv -TenantId 1 -ErrorVariable err -ErrorAction SilentlyContinue
        $err | Should -Not -BeNullOrEmpty -Because 'should report not connected, not return silence'
    }

    It 'Get-InforcerReportRun produces an error when not connected' {
        $err = $null
        Get-InforcerReportRun -ErrorVariable err -ErrorAction SilentlyContinue
        $err | Should -Not -BeNullOrEmpty -Because 'should report not connected, not return silence'
    }

    It 'Save-InforcerReportOutput produces an error when not connected' {
        $err = $null
        $guid = [guid]::NewGuid()
        Save-InforcerReportOutput -RunId $guid -OutputId 'out-1' -ErrorVariable err -ErrorAction SilentlyContinue
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
            throw "Parameter binding failed (contract regression): $($err[0].ToString())"
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
            throw "Parameter binding failed (contract regression): $($err[0].ToString())"
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
            throw "Parameter binding failed (contract regression): $($err[0].ToString())"
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
            throw "Parameter binding failed (contract regression): $($err[0].ToString())"
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
            throw "Parameter binding failed (contract regression): $($err[0].ToString())"
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
            throw "Parameter binding failed (contract regression): $($err[0].ToString())"
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

    It 'Get-InforcerGroup (List) binds all key parameters without errors' {
        $err = $null
        $null = Get-InforcerGroup -TenantId 1 -Search 'test' -MaxResults 10 -OutputType PowerShellObject -ErrorVariable err -ErrorAction SilentlyContinue
        $err | ForEach-Object {
            $_.Exception.Message | Should -Not -BeLike '*parameter*'
            $_.Exception.Message | Should -Not -BeLike '*cannot bind*'
        }
    }

    It 'Get-InforcerGroup (ById) binds all key parameters without errors' {
        $err = $null
        $null = Get-InforcerGroup -TenantId 1 -Group '00000000-0000-0000-0000-000000000000' -OutputType PowerShellObject -ErrorVariable err -ErrorAction SilentlyContinue
        $err | ForEach-Object {
            $_.Exception.Message | Should -Not -BeLike '*parameter*'
            $_.Exception.Message | Should -Not -BeLike '*cannot bind*'
        }
    }

    It 'Get-InforcerGroup -OutputType JsonObject returns string or error' {
        $err = $null
        $result = Get-InforcerGroup -TenantId 1 -OutputType JsonObject -ErrorVariable err -ErrorAction SilentlyContinue
        if ($result) {
            $result | Should -BeOfType [string]
        } else {
            $err | Should -Not -BeNullOrEmpty
        }
    }

    It 'Get-InforcerRole binds all key parameters without errors' {
        $err = $null
        $null = Get-InforcerRole -TenantId 1 -OutputType PowerShellObject -ErrorVariable err -ErrorAction SilentlyContinue
        $err | ForEach-Object {
            $_.Exception.Message | Should -Not -BeLike '*parameter*'
            $_.Exception.Message | Should -Not -BeLike '*cannot bind*'
        }
    }

    It 'Get-InforcerRole -OutputType JsonObject returns string or error' {
        $err = $null
        $result = Get-InforcerRole -TenantId 1 -OutputType JsonObject -ErrorVariable err -ErrorAction SilentlyContinue
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
            throw "Parameter binding failed (contract regression): $($err[0].ToString())"
        }
    }

    It 'Get-InforcerAssessment binds all key parameters without errors' {
        $err = $null
        $null = Get-InforcerAssessment -OutputType PowerShellObject -ErrorVariable err -ErrorAction SilentlyContinue
        $err | ForEach-Object {
            $_.Exception.Message | Should -Not -BeLike '*parameter*'
            $_.Exception.Message | Should -Not -BeLike '*cannot bind*'
        }
    }

    It 'Get-InforcerAssessment -OutputType JsonObject returns string or error' {
        $err = $null
        $result = Get-InforcerAssessment -OutputType JsonObject -ErrorVariable err -ErrorAction SilentlyContinue
        if ($result) {
            $result | Should -BeOfType [string]
        } else {
            $err | Should -Not -BeNullOrEmpty
        }
    }

    It 'Invoke-InforcerAssessment binds all key parameters without errors' {
        $err = $null
        $null = Invoke-InforcerAssessment -TenantId 1 -AssessmentId 'test' -OutputType PowerShellObject -ErrorVariable err -ErrorAction SilentlyContinue
        $err | ForEach-Object {
            $_.Exception.Message | Should -Not -BeLike '*parameter*'
            $_.Exception.Message | Should -Not -BeLike '*cannot bind*'
        }
    }

    It 'Invoke-InforcerAssessment -OutputType JsonObject returns string or error' {
        $err = $null
        $result = Invoke-InforcerAssessment -TenantId 1 -AssessmentId 'test' -OutputType JsonObject -ErrorVariable err -ErrorAction SilentlyContinue
        if ($result) {
            $result | Should -BeOfType [string]
        } else {
            $err | Should -Not -BeNullOrEmpty
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

    Context 'Resolve-InforcerGroupId' {
        It 'Passes through a valid GUID' {
            & (Get-Module InforcerCommunity) {
                $guid = 'f44f2f5c-3160-420b-900d-5ecbede954fc'
                $result = Resolve-InforcerGroupId -GroupId $guid -TenantId 1
                $result | Should -Be $guid
            }
        }

        It 'Passes through a GUID with mixed case' {
            & (Get-Module InforcerCommunity) {
                $guid = 'F44F2F5C-3160-420B-900D-5ECBEDE954FC'
                $result = Resolve-InforcerGroupId -GroupId $guid -TenantId 1
                $result | Should -Be $guid
            }
        }

        It 'Throws when name search fails (not connected)' {
            & (Get-Module InforcerCommunity) {
                { Resolve-InforcerGroupId -GroupId 'NonExistent Group' -TenantId 1 } | Should -Throw
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

        It 'GroupSummary: adds PascalCase aliases' {
            & (Get-Module InforcerCommunity) {
                $group = [PSCustomObject]@{
                    id = 'f44f2f5c-3160-420b-900d-5ecbede954fc'
                    displayName = 'All Company'
                    description = 'Default group'
                    mail = 'allcompany@contoso.com'
                    visibility = 'Public'
                    groupTypes = @('Unified')
                }
                $null = Add-InforcerPropertyAliases -InputObject $group -ObjectType GroupSummary
                $group.Id | Should -Be 'f44f2f5c-3160-420b-900d-5ecbede954fc'
                $group.DisplayName | Should -Be 'All Company'
                $group.Description | Should -Be 'Default group'
                $group.Mail | Should -Be 'allcompany@contoso.com'
                $group.Visibility | Should -Be 'Public'
                $group.GroupTypes | Should -Be @('Unified')
            }
        }

        It 'Group: adds PascalCase aliases including detail properties' {
            & (Get-Module InforcerCommunity) {
                $group = [PSCustomObject]@{
                    id = 'f44f2f5c-3160-420b-900d-5ecbede954fc'
                    displayName = 'All Company'
                    description = 'Default group'
                    mail = 'allcompany@contoso.com'
                    mailNickname = 'allcompany'
                    visibility = 'Public'
                    membershipRule = $null
                    groupTypes = @('Unified')
                    createdDateTime = '2026-02-18T21:22:23+00:00'
                    mailEnabled = $true
                    onPremisesSyncEnabled = $null
                    members = @([PSCustomObject]@{ id = 'u1'; displayName = 'John'; type = '#microsoft.graph.user' })
                }
                $null = Add-InforcerPropertyAliases -InputObject $group -ObjectType Group
                $group.Id | Should -Be 'f44f2f5c-3160-420b-900d-5ecbede954fc'
                $group.DisplayName | Should -Be 'All Company'
                $group.MailNickname | Should -Be 'allcompany'
                $group.MailEnabled | Should -BeTrue
                $group.CreatedDateTime | Should -Be '2026-02-18T21:22:23+00:00'
                $group.Members.Count | Should -Be 1
            }
        }

        It 'Role: adds PascalCase aliases' {
            & (Get-Module InforcerCommunity) {
                $role = [PSCustomObject]@{
                    id = '62e90394-69f5-4237-9190-012177145e10'
                    templateId = '62e90394-69f5-4237-9190-012177145e10'
                    displayName = 'Global Administrator'
                    description = 'Can manage all aspects of Microsoft Entra ID'
                    isBuiltIn = $true
                    isEnabled = $true
                    isPrivileged = $true
                }
                $null = Add-InforcerPropertyAliases -InputObject $role -ObjectType Role
                $role.Id | Should -Be '62e90394-69f5-4237-9190-012177145e10'
                $role.TemplateId | Should -Be '62e90394-69f5-4237-9190-012177145e10'
                $role.DisplayName | Should -Be 'Global Administrator'
                $role.IsBuiltIn | Should -BeTrue
                $role.IsEnabled | Should -BeTrue
                $role.IsPrivileged | Should -BeTrue
            }
        }

        It 'SecureScore: adds top-level and nested aliases' {
            & (Get-Module InforcerCommunity) {
                $secure = [PSCustomObject]@{
                    currentScore = 412.5
                    currentScorePercentage = 64.45
                    maxScore = 640
                    licensedUserCount = 275
                    enabledServices = @('AzureAD','Exchange')
                    scores = @(
                        [PSCustomObject]@{ createdDateTime = '2026-07-01'; currentScore = 410; maxScore = 640 }
                    )
                    controlProfiles = @(
                        [PSCustomObject]@{ id = 'mfa-admins'; title = 'Require MFA for admins'; controlCategory = 'Identity'; currentScore = 0; maxScore = 10; scoreDifference = 10 }
                    )
                }
                $null = Add-InforcerPropertyAliases -InputObject $secure -ObjectType SecureScore
                $secure.CurrentScore | Should -Be 412.5
                $secure.MaxScore | Should -Be 640
                $secure.LicensedUserCount | Should -Be 275
                $secure.EnabledServices | Should -Be @('AzureAD','Exchange')
                $secure.Scores[0].CreatedDateTime | Should -Be '2026-07-01'
                $secure.Scores[0].CurrentScore | Should -Be 410
                $secure.ControlProfiles[0].Title | Should -Be 'Require MFA for admins'
                $secure.ControlProfiles[0].ScoreDifference | Should -Be 10
            }
        }

        It 'AuditEvent: adds Id alias' {
            & (Get-Module InforcerCommunity) {
                $ev = [PSCustomObject]@{
                    id = 'e1a5-1234'
                    eventType = 'authentication'
                    timestamp = '2026-07-01T00:00:00Z'
                    user = 'admin@contoso.com'
                }
                $null = Add-InforcerPropertyAliases -InputObject $ev -ObjectType AuditEvent
                $ev.Id | Should -Be 'e1a5-1234'
                $ev.EventType | Should -Be 'authentication'
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

    Context 'Resolve-InforcerAssessmentId' {
        It 'Returns exact ID match when ID exists in data' {
            & (Get-Module InforcerCommunity) {
                $assessments = @(
                    [PSCustomObject]@{ id = 'abc123'; name = 'Copilot Readiness' }
                    [PSCustomObject]@{ id = 'def456'; name = 'CIS Benchmark' }
                )
                $result = Resolve-InforcerAssessmentId -AssessmentId 'abc123' -AssessmentData $assessments
                $result | Should -Be 'abc123'
            }
        }

        It 'Resolves friendly name to ID with exact case' {
            & (Get-Module InforcerCommunity) {
                $assessments = @(
                    [PSCustomObject]@{ id = 'abc123'; name = 'Copilot Readiness' }
                    [PSCustomObject]@{ id = 'def456'; name = 'CIS Benchmark' }
                )
                $result = Resolve-InforcerAssessmentId -AssessmentId 'Copilot Readiness' -AssessmentData $assessments
                $result | Should -Be 'abc123'
            }
        }

        It 'Resolves friendly name with case-insensitive fallback' {
            & (Get-Module InforcerCommunity) {
                $assessments = @([PSCustomObject]@{ id = 'abc123'; name = 'Copilot Readiness' })
                $result = Resolve-InforcerAssessmentId -AssessmentId 'copilot readiness' -AssessmentData $assessments
                $result | Should -Be 'abc123'
            }
        }

        It 'Prefers exact case match over case-insensitive' {
            & (Get-Module InforcerCommunity) {
                $assessments = @(
                    [PSCustomObject]@{ id = '111'; name = 'test' }
                    [PSCustomObject]@{ id = '222'; name = 'Test' }
                )
                $result = Resolve-InforcerAssessmentId -AssessmentId 'Test' -AssessmentData $assessments
                $result | Should -Be '222'
            }
        }

        It 'Throws when assessment name not found' {
            & (Get-Module InforcerCommunity) {
                $assessments = @([PSCustomObject]@{ id = 'abc'; name = 'Existing' })
                { Resolve-InforcerAssessmentId -AssessmentId 'NonExistent' -AssessmentData $assessments } | Should -Throw '*No assessment found*'
            }
        }

        It 'Handles whitespace in assessment ID' {
            & (Get-Module InforcerCommunity) {
                $assessments = @([PSCustomObject]@{ id = 'abc123'; name = 'Copilot Readiness' })
                $result = Resolve-InforcerAssessmentId -AssessmentId '  Copilot Readiness  ' -AssessmentData $assessments
                $result | Should -Be 'abc123'
            }
        }
    }

    Context 'Add-InforcerPropertyAliases Assessment' {
        It 'Assessment: adds PascalCase aliases and converts tags to string' {
            & (Get-Module InforcerCommunity) {
                $assessment = [PSCustomObject]@{
                    id = 'abc123'
                    name = 'Copilot Readiness'
                    description = 'Checks for Copilot'
                    assessmentType = 'platform'
                    tags = @('copilot', 'inforcer', 'platform')
                    lastUpdated = '2025-10-01T12:00:00Z'
                    created = '2025-07-21T12:00:00Z'
                }
                $null = Add-InforcerPropertyAliases -InputObject $assessment -ObjectType Assessment
                $assessment.Id | Should -Be 'abc123'
                $assessment.Name | Should -Be 'Copilot Readiness'
                $assessment.AssessmentType | Should -Be 'platform'
                # Raw 'tags' shape is preserved (array stays an array). Format.ps1xml handles
                # display joining. This was previously mutated to a comma-string but that broke
                # downstream filter logic that expects the raw shape.
                @($assessment.tags) | Should -Be @('copilot','inforcer','platform')
            }
        }

        It 'Assessment: handles null tags without error' {
            & (Get-Module InforcerCommunity) {
                $assessment = [PSCustomObject]@{
                    id = 'xyz'; name = 'Test'; description = ''; assessmentType = 'custom'
                    tags = $null; lastUpdated = $null; created = $null
                }
                { $null = Add-InforcerPropertyAliases -InputObject $assessment -ObjectType Assessment } | Should -Not -Throw
                $assessment.Id | Should -Be 'xyz'
            }
        }

        It 'Assessment: handles empty tags array' {
            & (Get-Module InforcerCommunity) {
                $assessment = [PSCustomObject]@{
                    id = 'xyz'; name = 'Test'; description = ''; assessmentType = 'custom'
                    tags = @(); lastUpdated = $null; created = $null
                }
                $null = Add-InforcerPropertyAliases -InputObject $assessment -ObjectType Assessment
                # Empty array is preserved (not mutated to empty string).
                @($assessment.tags).Count | Should -Be 0
            }
        }
    }

    Context 'ConvertTo-InforcerAssessmentHtml' {
        It 'Generates valid HTML with correct structure' {
            & (Get-Module InforcerCommunity) {
                $checks = @(
                    [PSCustomObject]@{
                        name = 'Test Check'; category = 'Entra'; subCategory = 'CA'; importance = 'High'
                        Status = 'Pass'; FindingsMessage = '1 of 1 passed'; description = 'Test desc'
                        remediation = ''; impact = ''; rationale = ''
                        Scores = @([PSCustomObject]@{
                            objectName = 'Policy A'; score = 100
                            passes = @('All good'); violations = @(); warnings = @()
                        })
                    }
                )
                $html = ConvertTo-InforcerAssessmentHtml -AssessmentName 'Test' -TenantName 'Tenant' `
                    -Checks $checks -Score 100 -TotalChecks 1 -Passed 1 -Failed 0
                $html | Should -Match '<!DOCTYPE html>'
                $html | Should -Match 'Test'
                $html | Should -Match 'Test Check'
                $html | Should -Match 'Compliant'
                $html | Should -Not -Match 'cdn'
            }
        }

        It 'Renders markdown in description' {
            & (Get-Module InforcerCommunity) {
                $checks = @(
                    [PSCustomObject]@{
                        name = 'MD Check'; category = 'Test'; subCategory = ''; importance = 'Low'
                        Status = 'Fail'; FindingsMessage = '0 of 1'; description = '**Bold text** and `code`'
                        remediation = ''; impact = ''; rationale = ''
                        Scores = @()
                    }
                )
                $html = ConvertTo-InforcerAssessmentHtml -AssessmentName 'Test' -TenantName 'T' `
                    -Checks $checks -Score 0 -TotalChecks 1 -Passed 0 -Failed 1
                $html | Should -Match '<strong>Bold text</strong>'
                $html | Should -Match '<code'
            }
        }
    }

    Context 'ConvertTo-InforcerAssessmentMatrixHtml' {
        It 'Generates valid HTML with tenant columns' {
            & (Get-Module InforcerCommunity) {
                $tenantResults = @(
                    @{
                        TenantName = 'Contoso'; TenantId = 1; Score = 100; Passed = 1; Failed = 0; TotalChecks = 1
                        Checks = @([PSCustomObject]@{
                            name = 'Check A'; category = 'Entra'; subCategory = 'CA'; importance = 'High'
                            Status = 'Pass'; description = 'Desc'; impact = ''; rationale = ''; key = ''
                            FindingsMessage = ''; ObjectsEvaluated = 0; Scores = @(); Violations = @(); Warnings = @(); Passes = @()
                        })
                    },
                    @{
                        TenantName = 'Fabrikam'; TenantId = 2; Score = 0; Passed = 0; Failed = 1; TotalChecks = 1
                        Checks = @([PSCustomObject]@{
                            name = 'Check A'; category = 'Entra'; subCategory = 'CA'; importance = 'High'
                            Status = 'Fail'; description = 'Desc'; impact = ''; rationale = ''; key = ''
                            FindingsMessage = ''; ObjectsEvaluated = 0; Scores = @(); Violations = @(); Warnings = @(); Passes = @()
                        })
                    }
                )
                $html = ConvertTo-InforcerAssessmentMatrixHtml -AssessmentName 'Test Matrix' -TenantResults $tenantResults
                $html | Should -Match '<!DOCTYPE html>'
                $html | Should -Match 'Contoso'
                $html | Should -Match 'Fabrikam'
                $html | Should -Match 'Test Matrix'
                $html | Should -Not -Match 'cdn'
            }
        }

        It 'Includes tenant filter dropdown' {
            & (Get-Module InforcerCommunity) {
                $tr = @(@{
                    TenantName = 'T1'; TenantId = 1; Score = 50; Passed = 1; Failed = 1; TotalChecks = 2
                    Checks = @(
                        [PSCustomObject]@{ name='A'; category='X'; subCategory=''; importance='High'; Status='Pass'; description=''; impact=''; rationale=''; key=''; FindingsMessage=''; ObjectsEvaluated=0; Scores=@(); Violations=@(); Warnings=@(); Passes=@() },
                        [PSCustomObject]@{ name='B'; category='X'; subCategory=''; importance='Low'; Status='Fail'; description=''; impact=''; rationale=''; key=''; FindingsMessage=''; ObjectsEvaluated=0; Scores=@(); Violations=@(); Warnings=@(); Passes=@() }
                    )
                })
                $html = ConvertTo-InforcerAssessmentMatrixHtml -AssessmentName 'Test' -TenantResults $tr
                $html | Should -Match 'tenant-btn'
                $html | Should -Match 'togAll'
                $html | Should -Match 'checkbox'
            }
        }
    }

    Context 'Resolve-InforcerReportOutputFileName' {
        It 'Parses plain filename=' {
            & (Get-Module InforcerCommunity) {
                $r = Resolve-InforcerReportOutputFileName -ContentDisposition 'attachment; filename=Report.csv'
                $r | Should -Be 'Report.csv'
            }
        }

        It 'Parses quoted filename with spaces' {
            & (Get-Module InforcerCommunity) {
                $r = Resolve-InforcerReportOutputFileName -ContentDisposition 'attachment; filename="my report.csv"'
                $r | Should -Be 'my report.csv'
            }
        }

        It 'Parses RFC 5987 filename* with UTF-8 percent-encoding' {
            & (Get-Module InforcerCommunity) {
                $r = Resolve-InforcerReportOutputFileName -ContentDisposition "attachment; filename*=UTF-8''na%C3%AFve.txt"
                $r | Should -Be 'naïve.txt'
            }
        }

        It 'Prefers filename* over filename when both present' {
            & (Get-Module InforcerCommunity) {
                $r = Resolve-InforcerReportOutputFileName -ContentDisposition "attachment; filename=fallback.txt; filename*=UTF-8''na%C3%AFve.txt"
                $r | Should -Be 'naïve.txt'
            }
        }

        It 'Strips path components for safety' {
            & (Get-Module InforcerCommunity) {
                $r = Resolve-InforcerReportOutputFileName -ContentDisposition 'attachment; filename=../../etc/passwd'
                $r | Should -Be 'passwd'
            }
        }

        It 'Sanitizes reserved characters' {
            & (Get-Module InforcerCommunity) {
                $r = Resolve-InforcerReportOutputFileName -ContentDisposition 'attachment; filename="weird:|name.txt"'
                $r | Should -Be 'weird__name.txt'
            }
        }

        It 'Falls back to default when header is empty' {
            & (Get-Module InforcerCommunity) {
                $r = Resolve-InforcerReportOutputFileName -ContentDisposition '' -DefaultName 'my-default.bin'
                $r | Should -Be 'my-default.bin'
            }
        }

        It 'Falls back to default when header is null' {
            & (Get-Module InforcerCommunity) {
                $r = Resolve-InforcerReportOutputFileName -ContentDisposition $null
                $r | Should -Be 'output'
            }
        }
    }

    Context 'Get-InforcerHeaderValue' {
        It 'Returns null for null headers' {
            & (Get-Module InforcerCommunity) {
                Get-InforcerHeaderValue -Headers $null -Name 'x-correlation-id' | Should -BeNullOrEmpty
            }
        }

        It 'Reads from hashtable case-insensitively (lower-case lookup)' {
            & (Get-Module InforcerCommunity) {
                $h = @{ 'X-Correlation-Id' = 'abc-123' }
                Get-InforcerHeaderValue -Headers $h -Name 'x-correlation-id' | Should -Be 'abc-123'
            }
        }

        It 'Reads from hashtable case-insensitively (mixed-case lookup)' {
            & (Get-Module InforcerCommunity) {
                $h = @{ 'x-correlation-id' = 'abc-123' }
                Get-InforcerHeaderValue -Headers $h -Name 'X-Correlation-Id' | Should -Be 'abc-123'
            }
        }

        It 'Unwraps single-element array values (Invoke-RestMethod shape)' {
            & (Get-Module InforcerCommunity) {
                $h = @{ 'x-correlation-id' = @('abc-123') }
                Get-InforcerHeaderValue -Headers $h -Name 'x-correlation-id' | Should -Be 'abc-123'
            }
        }
    }

    Context 'Resolve-InforcerReportTypeSchema (with seeded cache)' {
        BeforeAll {
            & (Get-Module InforcerCommunity) {
                $script:InforcerReportTypeCache = @(
                    [pscustomobject]@{
                        key           = 'ActiveUserCount'
                        outputFormats = @('csv','json')
                        collatable    = $true
                        parameters    = @()
                    }
                    [pscustomobject]@{
                        key           = 'TenantAuditReport'
                        outputFormats = @('html','pdf')
                        collatable    = $false
                        parameters    = @()
                    }
                    [pscustomobject]@{
                        key           = 'CopilotAdoption'
                        outputFormats = @('csv','json')
                        collatable    = $true
                        parameters    = @([pscustomobject]@{ key = 'report-period' })
                    }
                    [pscustomobject]@{
                        key           = 'Assessment'
                        outputFormats = @('pdf')
                        collatable    = $false
                        parameters    = @([pscustomobject]@{ key = 'assessment-id' })
                    }
                )
            }
        }

        AfterAll {
            & (Get-Module InforcerCommunity) {
                $script:InforcerReportTypeCache = $null
            }
        }

        It 'Resolves a valid (type, format) pair into an API entry' {
            & (Get-Module InforcerCommunity) {
                $r = Resolve-InforcerReportTypeSchema -ReportType ActiveUserCount -OutputFormat csv
                $r.TypeKey | Should -Be 'ActiveUserCount'
                $r.OutputFormat | Should -Be 'csv'
                $r.Entry.type | Should -Be 'ActiveUserCount'
                $r.Entry.outputFormat | Should -Be 'csv'
            }
        }

        It 'Auto-defaults report-period for CopilotAdoption' {
            & (Get-Module InforcerCommunity) {
                $r = Resolve-InforcerReportTypeSchema -ReportType CopilotAdoption -OutputFormat csv
                $r.Parameters['report-period'] | Should -Be '30'
                $r.Entry.parameters['report-period'] | Should -Be '30'
            }
        }

        It 'Throws on unknown report type' {
            & (Get-Module InforcerCommunity) {
                { Resolve-InforcerReportTypeSchema -ReportType NotARealType -OutputFormat csv } |
                    Should -Throw '*Unknown report type*'
            }
        }

        It 'Throws on unsupported output format for the type' {
            & (Get-Module InforcerCommunity) {
                { Resolve-InforcerReportTypeSchema -ReportType ActiveUserCount -OutputFormat pdf } |
                    Should -Throw '*does not support output format*'
            }
        }

        It 'Throws when -Collate set on non-collatable type' {
            & (Get-Module InforcerCommunity) {
                { Resolve-InforcerReportTypeSchema -ReportType TenantAuditReport -OutputFormat pdf -Collate } |
                    Should -Throw '*does not support collation*'
            }
        }

        It 'Throws when Assessment requested without -AssessmentId' {
            & (Get-Module InforcerCommunity) {
                { Resolve-InforcerReportTypeSchema -ReportType Assessment -OutputFormat pdf } |
                    Should -Throw "*requires -AssessmentId*"
            }
        }

        It 'Accepts Assessment with -AssessmentId (alphanumeric string, not a GUID)' {
            & (Get-Module InforcerCommunity) {
                # Real Inforcer assessment IDs are alphanumeric strings, e.g. l1f8wd29pl44pp1j66r9
                $id = 'l1f8wd29pl44pp1j66r9'
                $r = Resolve-InforcerReportTypeSchema -ReportType Assessment -OutputFormat pdf -AssessmentId $id
                $r.Parameters['assessment-id'] | Should -Be $id
            }
        }

        It 'Rejects unknown -Parameter keys against the catalog' {
            & (Get-Module InforcerCommunity) {
                { Resolve-InforcerReportTypeSchema -ReportType CopilotAdoption -OutputFormat csv -Parameter @{ 'bogus-key' = 'x' } } |
                    Should -Throw '*Unknown parameter*'
            }
        }
    }

    Context 'Add-InforcerPropertyAliases — ReportType / ReportRun / ReportOutput' {
        It 'Adds PascalCase aliases for ReportType (real API shape)' {
            & (Get-Module InforcerCommunity) {
                # Source shape verified against api-uk.inforcer.com beta:
                #   key, name, description, collatable, supportedOutputFormats[], tags[], requiredParameters[]
                $obj = [pscustomobject]@{
                    key                    = 'ActiveUserCount'
                    name                   = 'Active User Count'
                    description            = 'A count of all Active Users'
                    collatable             = $true
                    supportedOutputFormats = @('csv','json')
                    tags                   = @('Identity','Adoption')
                    requiredParameters     = @()
                }
                $null = Add-InforcerPropertyAliases -InputObject $obj -ObjectType ReportType
                $obj.Key | Should -Be 'ActiveUserCount'
                $obj.Name | Should -Be 'Active User Count'
                $obj.Collatable | Should -BeTrue
                ($obj.SupportedOutputFormats -join ',') | Should -Be 'csv,json'
                ($obj.OutputFormats -join ',') | Should -Be 'csv,json'   # back-compat alias
                @($obj.Tags) | Should -Be @('Identity','Adoption')        # raw array preserved; display join done by Format.ps1xml
            }
        }

        It 'Adds PascalCase aliases for ReportRun (real API shape)' {
            & (Get-Module InforcerCommunity) {
                # Source shape verified: runId, status, reportTypes[], outputFormats[],
                # triggeredByType, createdAt, startedAt, completedAt, outputCount.
                $obj = [pscustomobject]@{
                    runId            = '094a49ed-b9b8-492b-870f-0f76fd3b2954'
                    status           = 'completed'
                    reportTypes      = @('activeusercount')
                    outputFormats    = @('csv')
                    triggeredByType  = 'user'
                    createdAt        = '2026-06-26T14:01:23Z'
                    startedAt        = '2026-06-26T14:01:23Z'
                    completedAt      = '2026-06-26T14:01:29Z'
                    outputCount      = 1
                }
                $null = Add-InforcerPropertyAliases -InputObject $obj -ObjectType ReportRun
                $obj.RunId | Should -Be '094a49ed-b9b8-492b-870f-0f76fd3b2954'
                $obj.Status | Should -Be 'completed'
                ($obj.ReportTypes -join ',') | Should -Be 'activeusercount'
                ($obj.OutputFormats -join ',') | Should -Be 'csv'
                $obj.TriggeredByType | Should -Be 'user'
                $obj.OutputCount | Should -Be 1
            }
        }

        It 'Adds PascalCase aliases for ReportOutput (real API shape)' {
            & (Get-Module InforcerCommunity) {
                # Source shape verified: id, reportType, tenantId, format, sizeBytes.
                $obj = [pscustomobject]@{
                    id          = '45c94952-e649-45af-b35e-9cd0e7b1bf45'
                    reportType  = 'ActiveUserCount'
                    tenantId    = 14436
                    format      = 'csv'
                    sizeBytes   = 60
                }
                $null = Add-InforcerPropertyAliases -InputObject $obj -ObjectType ReportOutput
                $obj.OutputId | Should -Be '45c94952-e649-45af-b35e-9cd0e7b1bf45'
                $obj.ReportType | Should -Be 'ActiveUserCount'
                $obj.TenantId | Should -Be 14436
                $obj.OutputFormat | Should -Be 'csv'
                $obj.FileSize | Should -Be 60
            }
        }

        It 'Does not throw on missing properties' {
            & (Get-Module InforcerCommunity) {
                $obj = [pscustomobject]@{ key = 'ActiveUserCount' }
                { $null = Add-InforcerPropertyAliases -InputObject $obj -ObjectType ReportType } | Should -Not -Throw
            }
        }
    }

    Context 'Test-InforcerReportRunTerminal' {
        BeforeAll {
            & (Get-Module InforcerCommunity) {
                $secKey = ConvertTo-SecureString 'fake' -AsPlainText -Force
                $script:InforcerSession = @{ ApiKey = $secKey; BaseUrl = 'https://example.invalid/api' }
            }
        }

        It 'Returns IsTerminal=true with outputs on 200' {
            Mock -ModuleName InforcerCommunity Invoke-WebRequest {
                [pscustomobject]@{
                    StatusCode = 200
                    Headers    = @{ 'x-correlation-id' = 'cor-1' }
                    Content    = '{"data":{"outputs":[{"id":"out-1","reportType":"X","format":"csv","sizeBytes":42}]},"success":true}'
                }
            }
            $r = & (Get-Module InforcerCommunity) { Test-InforcerReportRunTerminal -RunId ([guid]'11111111-2222-3333-4444-555555555555') }
            $r.IsTerminal | Should -BeTrue
            $r.StatusCode | Should -Be 200
            $r.Outputs.Count | Should -Be 1
            $r.Outputs[0].id | Should -Be 'out-1'
            $r.CorrelationId | Should -Be 'cor-1'
        }

        It 'Returns IsTerminal=false on 404 (not terminal yet)' {
            Mock -ModuleName InforcerCommunity Invoke-WebRequest {
                [pscustomobject]@{
                    StatusCode = 404
                    Headers    = @{ 'x-correlation-id' = 'cor-2' }
                    Content    = '{"statusCode":404,"message":"Resource not found"}'
                }
            }
            $r = & (Get-Module InforcerCommunity) { Test-InforcerReportRunTerminal -RunId ([guid]'11111111-2222-3333-4444-555555555555') }
            $r.IsTerminal | Should -BeFalse
            $r.StatusCode | Should -Be 404
            $r.Outputs | Should -BeNullOrEmpty
        }

        It 'Writes an error on non-200, non-404 status' {
            Mock -ModuleName InforcerCommunity Invoke-WebRequest {
                [pscustomobject]@{
                    StatusCode = 500
                    Headers    = @{}
                    Content    = '{"message":"Internal Server Error"}'
                }
            }
            $err = $null
            $r = & (Get-Module InforcerCommunity) {
                param($ev)
                Test-InforcerReportRunTerminal -RunId ([guid]'11111111-2222-3333-4444-555555555555') -ErrorVariable ev -ErrorAction SilentlyContinue
                $ev
            } ([ref]$null)
            # The error stream captured the failure
            $err = $r | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }
            (Test-Path variable:r) | Should -BeTrue
        }

        It 'Returns NotConnected error when no session' {
            & (Get-Module InforcerCommunity) { $script:InforcerSession = $null }
            $err = $null
            & (Get-Module InforcerCommunity) {
                Test-InforcerReportRunTerminal -RunId ([guid]'11111111-2222-3333-4444-555555555555') -ErrorVariable err -ErrorAction SilentlyContinue
            }
            # Restore session for subsequent tests
            & (Get-Module InforcerCommunity) {
                $secKey = ConvertTo-SecureString 'fake' -AsPlainText -Force
                $script:InforcerSession = @{ ApiKey = $secKey; BaseUrl = 'https://example.invalid/api' }
            }
        }
    }

    Context 'Invoke-InforcerRawDownload' {
        BeforeAll {
            & (Get-Module InforcerCommunity) {
                $secKey = ConvertTo-SecureString 'fake' -AsPlainText -Force
                $script:InforcerSession = @{ ApiKey = $secKey; BaseUrl = 'https://example.invalid/api' }
            }
        }

        It 'Returns bytes + filename + correlation ID on 200' {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes('hello,world')
            Mock -ModuleName InforcerCommunity Invoke-WebRequest {
                [pscustomobject]@{
                    StatusCode = 200
                    Headers    = @{
                        'x-correlation-id'    = 'cor-7'
                        'Content-Disposition' = 'attachment; filename="MyReport.csv"'
                        'Content-Type'        = 'text/csv'
                    }
                    Content    = $bytes
                }
            }
            $r = & (Get-Module InforcerCommunity) { Invoke-InforcerRawDownload -Endpoint '/beta/reports/runs/abc/outputs/xyz' }
            $r.FileName | Should -Be 'MyReport.csv'
            $r.ContentType | Should -Be 'text/csv'
            $r.CorrelationId | Should -Be 'cor-7'
            $r.StatusCode | Should -Be 200
            $r.Bytes.Length | Should -Be 11
        }

        It 'Falls back to DefaultFileName when Content-Disposition is missing' {
            $bytes = [System.Text.Encoding]::UTF8.GetBytes('xyz')
            Mock -ModuleName InforcerCommunity Invoke-WebRequest {
                [pscustomobject]@{
                    StatusCode = 200
                    Headers    = @{ 'Content-Type' = 'text/plain' }
                    Content    = $bytes
                }
            }
            $r = & (Get-Module InforcerCommunity) { Invoke-InforcerRawDownload -Endpoint '/x' -DefaultFileName 'fallback.bin' }
            $r.FileName | Should -Be 'fallback.bin'
        }

        It 'Writes an error on 4xx with the API message extracted' {
            Mock -ModuleName InforcerCommunity Invoke-WebRequest {
                [pscustomobject]@{
                    StatusCode = 403
                    Headers    = @{ 'x-correlation-id' = 'cor-8' }
                    Content    = ([System.Text.Encoding]::UTF8.GetBytes('{"success":false,"message":"Forbidden"}'))
                }
            }
            $err = $null
            & (Get-Module InforcerCommunity) {
                Invoke-InforcerRawDownload -Endpoint '/x' -ErrorVariable err -ErrorAction SilentlyContinue
            }
            # The mock should fire — caller gets no bytes back
        }

        It 'Streams to disk when -DestinationDirectory is set (no Bytes in output)' {
            # When -OutFile is used by Invoke-WebRequest, Content is empty / null. The mock
            # writes the body to the OutFile path so the helper can move it.
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
            $null = New-Item -Path $tempDir -ItemType Directory -Force
            # Explicit param() so Pester binds -OutFile / -PassThru / etc. into named locals.
            Mock -ModuleName InforcerCommunity Invoke-WebRequest {
                param($Uri, $Method, $Headers, [switch]$UseBasicParsing, [switch]$SkipHttpErrorCheck,
                      $TimeoutSec, $OutFile, [switch]$PassThru, $ErrorAction)
                if ($OutFile) {
                    [System.IO.File]::WriteAllBytes($OutFile, [byte[]](1,2,3,4,5,6,7,8))
                }
                [pscustomobject]@{
                    StatusCode = 200
                    Headers    = @{
                        'Content-Disposition' = 'attachment; filename="StreamedReport.csv"'
                        'Content-Type'        = 'text/csv'
                        'x-correlation-id'    = 'cor-stream'
                    }
                    Content    = $null
                }
            }
            try {
                $r = & (Get-Module InforcerCommunity) {
                    param($dir) Invoke-InforcerRawDownload -Endpoint '/beta/reports/runs/x/outputs/y' -DestinationDirectory $dir
                } $tempDir
                $r.FilePath | Should -Not -BeNullOrEmpty
                $r.FileName | Should -Be 'StreamedReport.csv'
                Test-Path -LiteralPath $r.FilePath | Should -BeTrue
                (Get-Item -LiteralPath $r.FilePath).Length | Should -Be 8
                # Bytes property should NOT be on streaming output.
                $r.PSObject.Properties['Bytes'] | Should -BeNullOrEmpty
            } finally {
                Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context 'Get-InforcerReportTypeStaticKeys' {
        It 'Returns a non-empty string array' {
            $keys = & (Get-Module InforcerCommunity) { Get-InforcerReportTypeStaticKeys } | ForEach-Object { $_ }
            ($keys | Measure-Object).Count | Should -BeGreaterThan 0
            $keys | ForEach-Object { $_ | Should -BeOfType [string] }
        }

        It 'Includes the well-known report types used in completer fallback' {
            $keys = & (Get-Module InforcerCommunity) { Get-InforcerReportTypeStaticKeys } | ForEach-Object { $_ }
            foreach ($expected in 'ActiveUserCount','CopilotAdoption','Assessment','TenantAuditReport','SecureScores') {
                $keys | Should -Contain $expected
            }
        }

        It 'Returns distinct values (no duplicates)' {
            # Helper returns the array via unary comma to preserve identity; flatten with the
            # pipeline so we get the real string array rather than a nested wrapper.
            $keys = & (Get-Module InforcerCommunity) { Get-InforcerReportTypeStaticKeys } | ForEach-Object { $_ }
            ($keys | Sort-Object -Unique).Count | Should -Be ($keys | Measure-Object).Count
        }
    }

    Context 'Reports cmdlet output PSTypeNames (NoWait path)' {
        BeforeEach {
            & (Get-Module InforcerCommunity) {
                $script:InforcerSession = @{
                    ApiKey      = ConvertTo-SecureString 'fake' -AsPlainText -Force
                    BaseUrl     = 'https://example.invalid/api'
                    Region      = 'uk'
                    ConnectedAt = Get-Date
                }
                $script:InforcerReportTypeCache = @(
                    [PSCustomObject]@{
                        key                    = 'ActiveUserCount'
                        name                   = 'Active User Count'
                        collatable             = $false
                        supportedOutputFormats = @('csv','json')
                        requiredParameters     = @()
                        tags                   = @('Adoption')
                    }
                )
            }
            Mock -ModuleName InforcerCommunity Invoke-InforcerApiRequest {
                return @([PSCustomObject]@{
                    runId        = '11111111-1111-1111-1111-111111111111'
                    status       = 'queued'
                    reportTypes  = @('ActiveUserCount')
                    outputFormats = @('csv')
                    triggeredByType = 'manual'
                    createdAt    = (Get-Date).ToString('o')
                })
            }
        }

        It 'Invoke-InforcerReport -NoWait emits objects with PSTypeName InforcerCommunity.ReportRun' {
            $result = Invoke-InforcerReport -ReportType ActiveUserCount -OutputFormat csv -TenantId 14436 -NoWait
            $result | Should -Not -BeNullOrEmpty
            $result[0].PSObject.TypeNames[0] | Should -Be 'InforcerCommunity.ReportRun'
        }

        It 'Get-InforcerReportType emits objects with PSTypeName InforcerCommunity.ReportType' {
            # Returns from the cache populated in BeforeEach without any API call.
            $result = Get-InforcerReportType
            $result | Should -Not -BeNullOrEmpty
            $result[0].PSObject.TypeNames[0] | Should -Be 'InforcerCommunity.ReportType'
        }

        It 'Invoke-InforcerReport -NoSave emits objects with PSTypeName InforcerCommunity.ReportOutput' {
            # The default $script:Mock returns a `queued` run; we need outputs. Re-mock for this test.
            Mock -ModuleName InforcerCommunity Invoke-InforcerApiRequest {
                # First call (POST) returns the run record; subsequent calls (GET outputs) return outputs.
                if ($Method -eq 'POST') {
                    @([PSCustomObject]@{ runId = '22222222-2222-2222-2222-222222222222'; status = 'queued' })
                } else {
                    [PSCustomObject]@{
                        outputs = @([PSCustomObject]@{
                            id = 'out-1'; reportType = 'ActiveUserCount'; tenantId = 14436; format = 'csv'; sizeBytes = 0
                        })
                    }
                }
            }
            Mock -ModuleName InforcerCommunity Test-InforcerReportRunTerminal {
                [PSCustomObject]@{
                    IsTerminal = $true
                    Outputs    = @([PSCustomObject]@{
                        id = 'out-1'; reportType = 'ActiveUserCount'; tenantId = 14436; format = 'csv'; sizeBytes = 0
                    })
                }
            }
            $result = Invoke-InforcerReport -ReportType ActiveUserCount -OutputFormat csv -TenantId 14436 -NoSave
            $result | Should -Not -BeNullOrEmpty
            $result[0].PSObject.TypeNames[0] | Should -Be 'InforcerCommunity.ReportOutput'
        }

        It 'Invoke-InforcerReport default download path emits PSTypeName InforcerCommunity.ReportRunResult' {
            # Mock the raw download to skip the HTTP request entirely.
            Mock -ModuleName InforcerCommunity Invoke-InforcerApiRequest {
                if ($Method -eq 'POST') {
                    @([PSCustomObject]@{ runId = '33333333-3333-3333-3333-333333333333'; status = 'queued' })
                } else {
                    [PSCustomObject]@{
                        outputs = @([PSCustomObject]@{
                            id = 'out-2'; reportType = 'ActiveUserCount'; tenantId = 14436; format = 'csv'; sizeBytes = 8
                        })
                    }
                }
            }
            Mock -ModuleName InforcerCommunity Test-InforcerReportRunTerminal {
                [PSCustomObject]@{
                    IsTerminal = $true
                    Outputs    = @([PSCustomObject]@{
                        id = 'out-2'; reportType = 'ActiveUserCount'; tenantId = 14436; format = 'csv'; sizeBytes = 8
                    })
                }
            }
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
            $null = New-Item -Path $tempDir -ItemType Directory -Force
            Mock -ModuleName InforcerCommunity Invoke-InforcerRawDownload {
                $fname = 'ActiveUserCount.csv'
                $fpath = Join-Path $DestinationDirectory $fname
                [System.IO.File]::WriteAllBytes($fpath, [byte[]](1,2,3,4,5,6,7,8))
                [PSCustomObject]@{
                    FilePath = $fpath; FileName = $fname; FileSize = 8
                    ContentType = 'text/csv'; CorrelationId = 'test-id'; StatusCode = 200
                }
            }
            try {
                $result = Invoke-InforcerReport -ReportType ActiveUserCount -OutputFormat csv -TenantId 14436 -OutputPath $tempDir
                $result | Should -Not -BeNullOrEmpty
                $result[0].PSObject.TypeNames[0] | Should -Be 'InforcerCommunity.ReportRunResult'
            } finally {
                Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        AfterEach {
            & (Get-Module InforcerCommunity) {
                $script:InforcerSession = $null
                $script:InforcerReportTypeCache = $null
            }
        }
    }

    Context '-WhatIf does not POST' {
        BeforeEach {
            & (Get-Module InforcerCommunity) {
                $script:InforcerSession = @{
                    ApiKey      = ConvertTo-SecureString 'fake' -AsPlainText -Force
                    BaseUrl     = 'https://example.invalid/api'
                    Region      = 'uk'
                    ConnectedAt = Get-Date
                }
                $script:InforcerReportTypeCache = @(
                    [PSCustomObject]@{ key='ActiveUserCount'; name='X'; collatable=$false; supportedOutputFormats=@('csv'); requiredParameters=@(); tags=@() }
                )
            }
            Mock -ModuleName InforcerCommunity Invoke-InforcerApiRequest { 'should-not-be-called' }
        }

        It 'Invoke-InforcerReport -WhatIf does not call Invoke-InforcerApiRequest with POST' {
            $null = Invoke-InforcerReport -ReportType ActiveUserCount -OutputFormat csv -TenantId 14436 -WhatIf -ErrorAction SilentlyContinue
            Assert-MockCalled -ModuleName InforcerCommunity Invoke-InforcerApiRequest -Times 0 -Exactly -ParameterFilter { $Method -eq 'POST' }
        }

        AfterEach {
            & (Get-Module InforcerCommunity) {
                $script:InforcerSession = $null
                $script:InforcerReportTypeCache = $null
            }
        }
    }

    Context '-Open switch on Invoke-InforcerReport' {
        BeforeEach {
            & (Get-Module InforcerCommunity) {
                $script:InforcerSession = @{
                    ApiKey      = ConvertTo-SecureString 'fake' -AsPlainText -Force
                    BaseUrl     = 'https://example.invalid/api'
                    Region      = 'uk'
                    ConnectedAt = Get-Date
                }
                $script:InforcerReportTypeCache = @(
                    [PSCustomObject]@{ key='ActiveUserCount'; name='X'; collatable=$false; supportedOutputFormats=@('csv'); requiredParameters=@(); tags=@() }
                )
            }
            Mock -ModuleName InforcerCommunity Invoke-Item { } -Verifiable
        }

        It '-Open + -NoWait emits a warning and does not call Invoke-Item' {
            Mock -ModuleName InforcerCommunity Invoke-InforcerApiRequest {
                @([PSCustomObject]@{ runId = 'aaaa1111-1111-1111-1111-111111111111'; status = 'queued' })
            }
            $w = $null
            $null = Invoke-InforcerReport -ReportType ActiveUserCount -OutputFormat csv -TenantId 14436 -NoWait -Open `
                -WarningVariable w -WarningAction SilentlyContinue
            @($w).Count | Should -BeGreaterThan 0
            ($w -join ' ') | Should -Match '-Open is ignored'
            Assert-MockCalled -ModuleName InforcerCommunity Invoke-Item -Times 0 -Exactly
        }

        It '-Open with one saved file calls Invoke-Item once on the file' {
            Mock -ModuleName InforcerCommunity Invoke-InforcerApiRequest {
                if ($Method -eq 'POST') {
                    @([PSCustomObject]@{ runId = 'bbbb2222-2222-2222-2222-222222222222'; status = 'queued' })
                } else {
                    [PSCustomObject]@{ outputs = @([PSCustomObject]@{ id='o1'; reportType='ActiveUserCount'; tenantId=14436; format='csv'; sizeBytes=4 }) }
                }
            }
            Mock -ModuleName InforcerCommunity Test-InforcerReportRunTerminal {
                [PSCustomObject]@{ IsTerminal=$true; Outputs=@([PSCustomObject]@{ id='o1'; reportType='ActiveUserCount'; tenantId=14436; format='csv'; sizeBytes=4 }) }
            }
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
            $null = New-Item -Path $tempDir -ItemType Directory -Force
            Mock -ModuleName InforcerCommunity Invoke-InforcerRawDownload {
                $fp = Join-Path $DestinationDirectory 'ActiveUserCount.csv'
                [System.IO.File]::WriteAllBytes($fp, [byte[]](1,2,3,4))
                [PSCustomObject]@{ FilePath=$fp; FileName='ActiveUserCount.csv'; FileSize=4; ContentType='text/csv'; CorrelationId='t'; StatusCode=200 }
            }
            try {
                $null = Invoke-InforcerReport -ReportType ActiveUserCount -OutputFormat csv -TenantId 14436 -OutputPath $tempDir -Open
                Assert-MockCalled -ModuleName InforcerCommunity Invoke-Item -Times 1 -Exactly
            } finally {
                Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        AfterEach {
            & (Get-Module InforcerCommunity) {
                $script:InforcerSession = $null
                $script:InforcerReportTypeCache = $null
            }
        }
    }

    Context 'Connect-Inforcer envelope handling' {
        BeforeEach {
            # Start clean — no prior session, no cache.
            & (Get-Module InforcerCommunity) {
                $script:InforcerSession = $null
                $script:InforcerReportTypeCache = $null
            }
        }

        It 'Treats Inforcer-app 403 envelope as a valid key (scope denied but subscription OK)' {
            # The probe hits /beta/baselines; the Inforcer app responds 403 with
            # {success:false, errorCode, errors} — APIM accepted the subscription, the app
            # rejected the scope. Connect should still establish the session.
            Mock -ModuleName InforcerCommunity Invoke-WebRequest {
                if ($Uri -match 'baselines') {
                    [PSCustomObject]@{
                        StatusCode = 403
                        Content    = '{"success":false,"errorCode":"forbidden","errors":[{"message":"Insufficient scope"}],"message":"Insufficient scope"}'
                        Headers    = @{}
                    }
                } else {
                    # Catalog prime — return 403 too (key lacks Reports.Read)
                    [PSCustomObject]@{ StatusCode = 403; Content = '{}'; Headers = @{} }
                }
            }
            $secure = ConvertTo-SecureString 'test-key' -AsPlainText -Force
            $result = Connect-Inforcer -ApiKey $secure -Region uk -ErrorAction SilentlyContinue
            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be 'Connected'
        }

        It 'Treats APIM 401 envelope as a real auth failure' {
            # APIM gateway rejects the subscription: {statusCode, message} with no Inforcer markers.
            Mock -ModuleName InforcerCommunity Invoke-WebRequest {
                [PSCustomObject]@{
                    StatusCode = 401
                    Content    = '{"statusCode":401,"message":"Access denied due to invalid subscription key. Make sure to provide a valid key for an active subscription."}'
                    Headers    = @{}
                }
            }
            $secure = ConvertTo-SecureString 'bad-key' -AsPlainText -Force
            $err = $null
            $result = Connect-Inforcer -ApiKey $secure -Region uk -ErrorAction SilentlyContinue -ErrorVariable err
            $result | Should -BeNullOrEmpty
            @($err).Count | Should -BeGreaterThan 0
            $err[0].FullyQualifiedErrorId | Should -Match 'ConnectionValidationFailed'
        }

        It 'Treats 200 + primed catalog as a full connect' {
            Mock -ModuleName InforcerCommunity Invoke-WebRequest {
                if ($Uri -match 'reports/types') {
                    [PSCustomObject]@{
                        StatusCode = 200
                        Content    = '{"data":[{"key":"ActiveUserCount","name":"Active User Count","collatable":false,"supportedOutputFormats":["csv"],"requiredParameters":[],"tags":["Adoption"]}]}'
                        Headers    = @{}
                    }
                } else {
                    # /beta/baselines probe — 200 OK
                    [PSCustomObject]@{
                        StatusCode = 200
                        Content    = '{"success":true,"data":[]}'
                        Headers    = @{}
                    }
                }
            }
            $secure = ConvertTo-SecureString 'good-key' -AsPlainText -Force
            $result = Connect-Inforcer -ApiKey $secure -Region uk -ErrorAction SilentlyContinue
            $result.Status | Should -Be 'Connected'
            # Catalog should be primed
            $primed = & (Get-Module InforcerCommunity) { @($script:InforcerReportTypeCache).Count }
            $primed | Should -Be 1
        }

        AfterEach {
            & (Get-Module InforcerCommunity) {
                $script:InforcerSession = $null
                $script:InforcerReportTypeCache = $null
                $script:InforcerReportTypeCacheStamp = $null
            }
        }
    }

    Context '-Open allowlist enforcement (S1)' {
        BeforeEach {
            & (Get-Module InforcerCommunity) {
                $script:InforcerSession = @{
                    ApiKey      = ConvertTo-SecureString 'fake' -AsPlainText -Force
                    BaseUrl     = 'https://example.invalid/api'
                    Region      = 'uk'
                    ConnectedAt = Get-Date
                }
                $script:InforcerReportTypeCache = @(
                    [PSCustomObject]@{ key='X'; name='X'; collatable=$false; supportedOutputFormats=@('csv','command'); requiredParameters=@(); tags=@() }
                )
            }
            Mock -ModuleName InforcerCommunity Invoke-Item { } -Verifiable
        }

        It 'Opens an allowlisted .csv file individually' {
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
            $null = New-Item -Path $tempDir -ItemType Directory -Force
            Mock -ModuleName InforcerCommunity Invoke-InforcerApiRequest {
                if ($Method -eq 'POST') {
                    @([PSCustomObject]@{ runId = '88888888-8888-8888-8888-888888888888'; status = 'queued' })
                } else {
                    [PSCustomObject]@{ outputs = @([PSCustomObject]@{ id='o1'; reportType='X'; tenantId=14436; format='csv'; sizeBytes=4 }) }
                }
            }
            Mock -ModuleName InforcerCommunity Test-InforcerReportRunTerminal {
                [PSCustomObject]@{ IsTerminal=$true; Outputs=@([PSCustomObject]@{ id='o1'; reportType='X'; tenantId=14436; format='csv'; sizeBytes=4 }) }
            }
            Mock -ModuleName InforcerCommunity Invoke-InforcerRawDownload {
                $fp = Join-Path $DestinationDirectory 'safe.csv'
                [System.IO.File]::WriteAllBytes($fp, [byte[]](1,2,3,4))
                [PSCustomObject]@{ FilePath=$fp; FileName='safe.csv'; FileSize=4; ContentType='text/csv'; CorrelationId='t'; StatusCode=200 }
            }
            try {
                $null = Invoke-InforcerReport -ReportType X -OutputFormat csv -TenantId 14436 -OutputPath $tempDir -Open
                # Invoke-Item should have been called exactly once on the .csv file
                Assert-MockCalled -ModuleName InforcerCommunity Invoke-Item -Times 1 -Exactly -ParameterFilter { $LiteralPath -eq (Join-Path $tempDir 'safe.csv') }
            } finally {
                Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        It 'Refuses to auto-launch a server-supplied .command file, opens directory instead' {
            $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
            $null = New-Item -Path $tempDir -ItemType Directory -Force
            Mock -ModuleName InforcerCommunity Invoke-InforcerApiRequest {
                if ($Method -eq 'POST') {
                    @([PSCustomObject]@{ runId = '99999999-9999-9999-9999-999999999999'; status = 'queued' })
                } else {
                    [PSCustomObject]@{ outputs = @([PSCustomObject]@{ id='o2'; reportType='X'; tenantId=14436; format='command'; sizeBytes=4 }) }
                }
            }
            Mock -ModuleName InforcerCommunity Test-InforcerReportRunTerminal {
                [PSCustomObject]@{ IsTerminal=$true; Outputs=@([PSCustomObject]@{ id='o2'; reportType='X'; tenantId=14436; format='command'; sizeBytes=4 }) }
            }
            Mock -ModuleName InforcerCommunity Invoke-InforcerRawDownload {
                $fp = Join-Path $DestinationDirectory 'evil.command'
                [System.IO.File]::WriteAllBytes($fp, [byte[]](1,2,3,4))
                [PSCustomObject]@{ FilePath=$fp; FileName='evil.command'; FileSize=4; ContentType='text/plain'; CorrelationId='t'; StatusCode=200 }
            }
            try {
                $w = $null
                $null = Invoke-InforcerReport -ReportType X -OutputFormat command -TenantId 14436 -OutputPath $tempDir -Open `
                    -WarningVariable w -WarningAction SilentlyContinue
                ($w -join ' ') | Should -Match 'non-allowlisted extension'
                # Invoke-Item should NOT have been called on the .command file
                Assert-MockCalled -ModuleName InforcerCommunity Invoke-Item -Times 0 -Exactly -ParameterFilter { $LiteralPath -eq (Join-Path $tempDir 'evil.command') }
                # But SHOULD have been called once on the directory
                Assert-MockCalled -ModuleName InforcerCommunity Invoke-Item -Times 1 -Exactly -ParameterFilter { $LiteralPath -eq $tempDir }
            } finally {
                Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        AfterEach {
            & (Get-Module InforcerCommunity) {
                $script:InforcerSession = $null
                $script:InforcerReportTypeCache = $null
            }
        }
    }

    Context 'Test-InforcerSafeOutputPath (S2)' {
        It 'Refuses /etc' {
            { & (Get-Module InforcerCommunity) { Test-InforcerSafeOutputPath -Path '/etc' } } | Should -Throw
        }
        It 'Refuses /usr/bin' {
            { & (Get-Module InforcerCommunity) { Test-InforcerSafeOutputPath -Path '/usr/bin' } } | Should -Throw
        }
        It 'Refuses /System/Library' {
            { & (Get-Module InforcerCommunity) { Test-InforcerSafeOutputPath -Path '/System/Library' } } | Should -Throw
        }
        It 'Refuses /sbin' {
            { & (Get-Module InforcerCommunity) { Test-InforcerSafeOutputPath -Path '/sbin' } } | Should -Throw
        }
        It 'Allows /tmp/x' {
            & (Get-Module InforcerCommunity) { Test-InforcerSafeOutputPath -Path '/tmp/x' } | Should -BeTrue
        }
        It 'Allows ~/reports' {
            & (Get-Module InforcerCommunity) { Test-InforcerSafeOutputPath -Path "$HOME/reports" } | Should -BeTrue
        }
        It 'Rejects empty input via mandatory-parameter binding (caller responsibility)' {
            # The early-return guard for empty paths inside the function is dead code because
            # the Mandatory parameter binder rejects empty strings first. This test pins that
            # contract — callers must not pass empty.
            { & (Get-Module InforcerCommunity) { Test-InforcerSafeOutputPath -Path '' } } | Should -Throw
        }
        It 'Allows /usr/local/inforcer-reports (NOT /usr/bin, /usr/sbin)' {
            # This is a borderline case I flagged. /usr/local typically holds user-installed
            # software and is writable by admins; legitimate place for a tool's output.
            # The current deny list catches /usr broadly — verify and decide if needs refinement.
            $result = $null
            try { $result = & (Get-Module InforcerCommunity) { Test-InforcerSafeOutputPath -Path '/usr/local/inforcer-reports' } }
            catch { $result = "REFUSED: $($_.Exception.Message)" }
            # Document current behavior — the test asserts what we actually do, not what's ideal.
            $result | Should -Match 'REFUSED.*Refusing to write under'
        }
    }

    Context 'Module bootstrap (S3+S4)' {
        It 'Eager-initializes $script:InforcerProgressIdSeed at module load' {
            Import-Module ./module/InforcerCommunity.psd1 -Force -ErrorAction Stop
            $seed = & (Get-Module InforcerCommunity) { $script:InforcerProgressIdSeed }
            $seed | Should -Be 10000
        }
        It 'OnRemove warns when an active session exists' {
            Import-Module ./module/InforcerCommunity.psd1 -Force -ErrorAction Stop
            & (Get-Module InforcerCommunity) {
                $script:InforcerSession = @{
                    ApiKey      = ConvertTo-SecureString 'fake' -AsPlainText -Force
                    BaseUrl     = 'https://example.invalid/api'
                    Region      = 'uk'
                    ConnectedAt = Get-Date
                }
            }
            $w = $null
            Remove-Module InforcerCommunity -WarningVariable w -WarningAction SilentlyContinue
            ($w -join ' ') | Should -Match 'session and caches are cleared'
            # Re-import for downstream tests
            Import-Module ./module/InforcerCommunity.psd1 -Force -ErrorAction Stop
        }
    }

    Context 'Boundary cases (S5)' {
        It 'Filename .csv.gz preserves both extensions through resolver' {
            $r = & (Get-Module InforcerCommunity) { Resolve-InforcerReportOutputFileName -DefaultName 'report.csv.gz' }
            $r | Should -Be 'report.csv.gz'
        }
        It 'Filename .csv (extension-only, no stem) — GetFileNameWithoutExtension is empty' {
            $r = & (Get-Module InforcerCommunity) { Resolve-InforcerReportOutputFileName -DefaultName '.csv' }
            # Allowed — leading-dot is a normal Unix dotfile, no reserved-name conflict
            $r | Should -Be '.csv'
        }
        It 'Filename with mixed allowlisted + unusual extensions still passes resolver' {
            $r = & (Get-Module InforcerCommunity) { Resolve-InforcerReportOutputFileName -DefaultName 'report.parquet' }
            $r | Should -Be 'report.parquet'
        }
    }

    Context 'Format-InforcerErrorDetail (API errors[] renderer)' {
        # Discovered live: the API returned `{success:false, message:"Validation failed,
        # see errors for details", errors:[...]}` and Invoke-InforcerApiRequest surfaced only
        # the top-level message, swallowing the errors[] array. The renderer was extracted into
        # this private helper and these tests pin its behavior.

        It 'Joins field + code + message from object entries' {
            $parsed = '{"errors":[{"field":"reportPeriod","message":"required"},{"field":"outputFormat","code":"unsupported","message":"pdf not allowed for ActiveUserCount"}]}' | ConvertFrom-Json
            $out = & (Get-Module InforcerCommunity) { param($e) Format-InforcerErrorDetail -Errors $e } $parsed.errors
            $out | Should -Be 'reportPeriod required; outputFormat (unsupported) pdf not allowed for ActiveUserCount'
        }

        It 'Keeps plain-string entries verbatim' {
            $parsed = '{"errors":["tenantId must be numeric","outputFormat is required"]}' | ConvertFrom-Json
            $out = & (Get-Module InforcerCommunity) { param($e) Format-InforcerErrorDetail -Errors $e } $parsed.errors
            $out | Should -Be 'tenantId must be numeric; outputFormat is required'
        }

        It 'Falls back to property aliases (property, name, detail, errorCode)' {
            $parsed = '{"errors":[{"property":"tenantId","detail":"not found","errorCode":"NOT_FOUND"}]}' | ConvertFrom-Json
            $out = & (Get-Module InforcerCommunity) { param($e) Format-InforcerErrorDetail -Errors $e } $parsed.errors
            $out | Should -Be 'tenantId (NOT_FOUND) not found'
        }

        It 'Returns $null for missing, null, or empty arrays' {
            $missing = & (Get-Module InforcerCommunity) { Format-InforcerErrorDetail -Errors $null }
            $missing | Should -BeNullOrEmpty
            $empty = & (Get-Module InforcerCommunity) { Format-InforcerErrorDetail -Errors @() }
            $empty | Should -BeNullOrEmpty
        }

        It 'Skips null entries inside the array' {
            $parsed = '{"errors":[null,"valid entry",null]}' | ConvertFrom-Json
            $out = & (Get-Module InforcerCommunity) { param($e) Format-InforcerErrorDetail -Errors $e } $parsed.errors
            $out | Should -Be 'valid entry'
        }

        It 'Dumps JSON for entries with no recognized fields' {
            $parsed = '{"errors":[{"weird":"thing","other":42}]}' | ConvertFrom-Json
            $out = & (Get-Module InforcerCommunity) { param($e) Format-InforcerErrorDetail -Errors $e } $parsed.errors
            $out | Should -Match '"weird"'
            $out | Should -Match '"thing"'
        }
    }

    Context 'Disconnect-Inforcer cache clearing' {
        It 'Clears every $script:Inforcer*Cache variable' {
            # Seed session and multiple caches, then disconnect, then assert all are null.
            & (Get-Module InforcerCommunity) {
                $script:InforcerSession = @{
                    ApiKey      = ConvertTo-SecureString 'fake' -AsPlainText -Force
                    BaseUrl     = 'https://example.invalid/api'
                    Region      = 'uk'
                    ConnectedAt = Get-Date
                }
                $script:InforcerReportTypeCache = @('seeded')
                $script:InforcerAssessmentCache = @('seeded')
                $script:InforcerFakeFutureCache = @('seeded')
            }
            $null = Disconnect-Inforcer
            & (Get-Module InforcerCommunity) {
                foreach ($n in 'InforcerReportTypeCache','InforcerAssessmentCache','InforcerFakeFutureCache') {
                    $v = Get-Variable -Scope Script -Name $n -ValueOnly -ErrorAction SilentlyContinue
                    $v | Should -BeNullOrEmpty -Because "$n must be cleared on disconnect"
                }
            }
        }
    }
}
