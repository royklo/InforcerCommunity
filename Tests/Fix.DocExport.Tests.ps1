# Fix.DocExport.Tests.ps1
# Export-InforcerTenantDocumentation fixes found while generating per-baseline documentation from the
# inforcer Blueprint Library (2026-11-16): baseline membership by id before name, no whole-tenant
# export when -Baseline does not resolve, name/value settings keep their value, and an existing
# app-only Graph session is reused instead of opening a browser. Fixtures are synthetic.

BeforeAll {
    Remove-Module -Name 'InforcerCommunity' -ErrorAction SilentlyContinue
    Import-Module (Join-Path $PSScriptRoot '../module/InforcerCommunity.psd1') -Force
    $script:M = Get-Module InforcerCommunity

    foreach ($cmd in 'Connect-MgGraph', 'Get-MgContext', 'Disconnect-MgGraph') {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { New-Item -Path "function:global:$cmd" -Value { } | Out-Null }
    }

    # Alignment response holding the given entries as matched policies (beta shape: policyGuid present).
    function global:New-DocExportAlignment([object[]]$Entries) {
        [pscustomobject]@{ alignment = [pscustomobject]@{
            matchedPolicies = $Entries; matchedWithAcceptedDeviations = @(); deviatedUnaccepted = @(); missingFromSubjectUnaccepted = @()
        } }
    }
    function global:Invoke-DocExportSelect([hashtable]$Doc) {
        & $script:M {
            param($d)
            $null = Select-InforcerBaselinePolicies -DocData $d -BaselineId '00000000-0000-0000-0000-0000000000b1' -WarningVariable w 6>$null 3>$null
            $script:docExportWarnings = $w
        } $Doc
        (& $script:M { $script:docExportWarnings }) -join "`n"
    }

    function global:New-DocExportMamTenant {
        @{ TenantId = 1; Policies = @(
            [pscustomobject]@{ id = 'T_1'; displayName = 'IOS - Security - U - MAM'; product = 'Intune'; primaryGroup = 'iOS/iPadOS'; secondaryGroup = 'App Protection Policies'; description = 'Level 1 is the minimum.' }
            [pscustomobject]@{ id = 'T_2'; displayName = 'IOS - Security - U - MAM'; product = 'Intune'; primaryGroup = 'iOS/iPadOS'; secondaryGroup = 'App Protection Policies'; description = 'Level 2 is the standard.' }
            [pscustomobject]@{ id = 'T_3'; displayName = 'IOS - Security - U - MAM'; product = 'Intune'; primaryGroup = 'iOS/iPadOS'; secondaryGroup = 'App Protection Policies'; description = 'Level 3 is high.' }
        ) }
    }
}

AfterAll {
    Remove-Item function:global:New-DocExportAlignment, function:global:Invoke-DocExportSelect, function:global:New-DocExportMamTenant -ErrorAction SilentlyContinue
}

Describe 'Select-InforcerBaselinePolicies: one baseline entry resolves to its own policy' {
    BeforeEach { Mock -ModuleName InforcerCommunity Write-Host { } }

    It 'keeps only the MAM level the baseline holds when the levels share a name and have no id' {
        Mock -ModuleName InforcerCommunity Invoke-InforcerApiRequest {
            New-DocExportAlignment @([pscustomobject]@{ policyName = 'IOS - Security - U - MAM'; policyGuid = $null; product = 'Intune'; primaryGroup = 'iOS/iPadOS'; secondaryGroup = 'App Protection Policies'; description = 'Level 1 is the minimum.' })
        }
        $doc = New-DocExportMamTenant
        $warnings = Invoke-DocExportSelect $doc
        @($doc.Policies).id | Should -Be @('T_1') -Because 'Level 2 and 3 share the name but are not in the baseline'
        $warnings | Should -BeNullOrEmpty
    }

    It 'does not add a same-named policy when the entry matched by id' {
        # The entry carries no category, so only the id can tell the two apart: a name lookup here
        # would find both and leave the policy out as ambiguous.
        Mock -ModuleName InforcerCommunity Invoke-InforcerApiRequest {
            New-DocExportAlignment @([pscustomobject]@{ policyName = 'macOS - Hardening'; policyGuid = '00000000-0000-0000-0000-0000000000d1' })
        }
        $doc = @{ TenantId = 1; Policies = @(
            [pscustomobject]@{ id = 'x'; policyGuid = '00000000-0000-0000-0000-0000000000d1'; displayName = 'macOS - Hardening'; product = 'Intune'; primaryGroup = 'macOS'; secondaryGroup = 'Configuration' }
            [pscustomobject]@{ id = 'y'; policyGuid = '00000000-0000-0000-0000-0000000000d2'; displayName = 'macOS - Hardening'; product = 'Intune'; primaryGroup = 'macOS'; secondaryGroup = 'Compliance' }
        ) }
        $null = Invoke-DocExportSelect $doc
        @($doc.Policies).id | Should -Be @('x')
    }

    It 'matches the tenant copy by matchingSubjectPolicies[].subjectPolicyGuid when the baseline id is the baseline''s own (beta)' {
        # Beta policyGuid is the baseline-side id, so in another tenant only the subject GUID points at
        # the copy; without it the two same-named copies are ambiguous and the policy is lost.
        Mock -ModuleName InforcerCommunity Invoke-InforcerApiRequest {
            New-DocExportAlignment @([pscustomobject]@{ policyName = 'CA - Require MFA'; policyGuid = '00000000-0000-0000-0000-0000000000f0'
                matchingSubjectPolicies = @([pscustomobject]@{ subjectPolicyGuid = '00000000-0000-0000-0000-0000000000f2' }) })
        }
        $doc = @{ TenantId = 1; Policies = @(
            [pscustomobject]@{ id = 'c1'; policyGuid = '00000000-0000-0000-0000-0000000000f1'; displayName = 'CA - Require MFA' }
            [pscustomobject]@{ id = 'c2'; policyGuid = '00000000-0000-0000-0000-0000000000f2'; displayName = 'CA - Require MFA' }
        ) }
        $warnings = Invoke-DocExportSelect $doc
        @($doc.Policies).id | Should -Be @('c2')
        $warnings | Should -BeNullOrEmpty
    }

    It 'leaves out and names a policy it cannot tell apart, instead of including every candidate' {
        Mock -ModuleName InforcerCommunity Invoke-InforcerApiRequest {
            New-DocExportAlignment @([pscustomobject]@{ policyName = 'IOS - Security - U - MAM'; policyGuid = $null; product = 'Intune'; primaryGroup = 'iOS/iPadOS'; secondaryGroup = 'App Protection Policies' })
        }
        $doc = New-DocExportMamTenant
        $warnings = Invoke-DocExportSelect $doc
        @($doc.Policies).Count | Should -Be 0
        $warnings | Should -Match 'match several tenant policies'
        $warnings | Should -Match ([regex]::Escape('IOS - Security - U - MAM (3 tenant policies)'))
    }

    It 'falls back to the name when no id matches, and never narrows candidates away on a field the tenant lacks' {
        # The tenant copies carry no product or category; narrowing on those must keep both, so the
        # description can still pick the right one.
        Mock -ModuleName InforcerCommunity Invoke-InforcerApiRequest {
            New-DocExportAlignment @([pscustomobject]@{ policyName = 'Password Protection'; policyGuid = '00000000-0000-0000-0000-0000000000e1'; product = 'Entra'; primaryGroup = 'Settings'; secondaryGroup = 'All'; description = 'Strict' })
        }
        $doc = @{ TenantId = 1; Policies = @(
            [pscustomobject]@{ id = 'p'; displayName = 'Password Protection'; description = 'Strict' }
            [pscustomobject]@{ id = 'q'; displayName = 'Password Protection'; description = 'Relaxed' }
        ) }
        $warnings = Invoke-DocExportSelect $doc
        @($doc.Policies).id | Should -Be @('p')
        $warnings | Should -BeNullOrEmpty
    }
}

Describe 'Export-InforcerTenantDocumentation -Baseline that does not resolve' {
    It 'errors with BaselineFilterFailed and exports nothing, instead of exporting every policy' {
        Mock -ModuleName InforcerCommunity Test-InforcerSession { $true }
        Mock -ModuleName InforcerCommunity Resolve-InforcerTenantId { 1 }
        Mock -ModuleName InforcerCommunity Write-Host { }
        Mock -ModuleName InforcerCommunity Get-InforcerDocData { @{ TenantId = 1; TenantName = 'T'; Policies = @([pscustomobject]@{ id = 'p1'; displayName = 'Internal only' }) } }
        Mock -ModuleName InforcerCommunity Select-InforcerBaselinePolicies { $null }
        Mock -ModuleName InforcerCommunity ConvertTo-InforcerDocModel { throw 'must not build a document' }

        $out = Export-InforcerTenantDocumentation -TenantId 1 -Baseline 'Empty Baseline' -ErrorVariable e -ErrorAction SilentlyContinue
        $out | Should -BeNullOrEmpty
        "$($e[0].FullyQualifiedErrorId)" | Should -Match '^BaselineFilterFailed'
        Should -Invoke -ModuleName InforcerCommunity ConvertTo-InforcerDocModel -Times 0 -Exactly
    }

    It 'turns an unknown baseline name into BaselineFilterFailed, naming why, instead of a terminating exception' {
        Mock -ModuleName InforcerCommunity Test-InforcerSession { $true }
        Mock -ModuleName InforcerCommunity Resolve-InforcerTenantId { 1 }
        Mock -ModuleName InforcerCommunity Write-Host { }
        Mock -ModuleName InforcerCommunity Get-InforcerDocData { @{ TenantId = 1; TenantName = 'T'; Baselines = @([pscustomobject]@{ id = '00000000-0000-0000-0000-0000000000b1'; name = 'Known' }); Policies = @([pscustomobject]@{ id = 'p1' }) } }
        Mock -ModuleName InforcerCommunity ConvertTo-InforcerDocModel { throw 'must not build a document' }

        $out = Export-InforcerTenantDocumentation -TenantId 1 -Baseline 'Unknown' -ErrorVariable e -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
        $out | Should -BeNullOrEmpty
        # -ErrorVariable also records the exception Select caught internally, so find ours by id.
        $failed = @($e | Where-Object { "$($_.FullyQualifiedErrorId)" -match '^BaselineFilterFailed' })
        $failed.Count | Should -Be 1
        "$($failed[0])" | Should -Match 'No baseline found with name: Unknown'
    }
}

Describe 'ConvertTo-FlatSettingRows: name/value pairs keep their value' {
    It 'renders each pair as a named row with its value' {
        $rows = & $script:M {
            ConvertTo-FlatSettingRows -PolicyData ([pscustomobject]@{ values = @(
                [pscustomobject]@{ name = 'LockoutThreshold'; value = '10' }
                [pscustomobject]@{ name = 'EnableBannedPasswordCheck'; value = $true }
            ) })
        }
        $lockout = @($rows | Where-Object { $_.Value -eq '10' })
        $lockout.Count | Should -Be 1
        $lockout[0].Name | Should -Not -BeNullOrEmpty
        @($rows | Where-Object { $_.Value -eq 'True' }).Count | Should -Be 1
    }

    It 'still shows an app list item by its bundle id, without a value' {
        $rows = & $script:M { ConvertTo-FlatSettingRows -PolicyData ([pscustomobject]@{ apps = @([pscustomobject]@{ bundleId = 'com.example.app' }) }) }
        $app = @($rows | Where-Object { $_.Name -eq 'com.example.app' })
        $app.Count | Should -Be 1
        $app[0].Value | Should -Be ''
    }
}

Describe 'Connect-InforcerGraph reuses a non-interactive session' {
    BeforeEach {
        Mock -ModuleName InforcerCommunity Get-Module { [pscustomobject]@{ Name = 'Microsoft.Graph.Authentication' } }
        Mock -ModuleName InforcerCommunity Import-Module { }
        Mock -ModuleName InforcerCommunity Write-Host { }
        Mock -ModuleName InforcerCommunity Connect-MgGraph { throw 'must not open an interactive sign-in' }
        Mock -ModuleName InforcerCommunity Disconnect-MgGraph { }
    }

    It 'reuses an app-only session for the right tenant with the needed roles' {
        Mock -ModuleName InforcerCommunity Get-MgContext {
            [pscustomobject]@{ Account = $null; AuthType = 'UserProvidedAccessToken'; ClientId = 'app-1'; TenantId = '00000000-0000-0000-0000-000000000001'
                Scopes = @('Directory.Read.All', 'Policy.Read.All', 'DeviceManagementConfiguration.Read.All') }
        }
        $ctx = & $script:M { Connect-InforcerGraph -TenantId '00000000-0000-0000-0000-000000000001' }
        $ctx.ClientId | Should -Be 'app-1'
        Should -Invoke -ModuleName InforcerCommunity Connect-MgGraph -Times 0 -Exactly
    }

    It 'does not reuse an app-only session signed in to another tenant' {
        Mock -ModuleName InforcerCommunity Get-MgContext {
            [pscustomobject]@{ Account = $null; AuthType = 'AppOnly'; ClientId = 'app-1'; TenantId = '00000000-0000-0000-0000-000000000009'
                Scopes = @('Directory.Read.All', 'Policy.Read.All', 'DeviceManagementConfiguration.Read.All') }
        }
        $ctx = & $script:M { Connect-InforcerGraph -TenantId '00000000-0000-0000-0000-000000000001' -WarningVariable w -WarningAction SilentlyContinue; $script:graphWarn = $w }
        $ctx | Should -BeNullOrEmpty -Because 'names from another tenant would be wrong, and silently so'
        (& $script:M { $script:graphWarn }) -join ' ' | Should -Match '000000000009'
        Should -Invoke -ModuleName InforcerCommunity Connect-MgGraph -Times 0 -Exactly
    }

    It 'returns nothing with a warning, never a browser prompt, when the app-only session lacks a role' {
        Mock -ModuleName InforcerCommunity Get-MgContext {
            [pscustomobject]@{ Account = $null; AuthType = 'AppOnly'; ClientId = 'app-1'; TenantId = '00000000-0000-0000-0000-000000000001'; Scopes = @('Directory.Read.All') }
        }
        $ctx = & $script:M { Connect-InforcerGraph -TenantId '00000000-0000-0000-0000-000000000001' -WarningVariable w -WarningAction SilentlyContinue; $script:graphWarn = $w }
        $ctx | Should -BeNullOrEmpty
        (& $script:M { $script:graphWarn }) -join ' ' | Should -Match 'Policy.Read.All'
        Should -Invoke -ModuleName InforcerCommunity Connect-MgGraph -Times 0 -Exactly
    }
}
