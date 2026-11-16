# Fix.DocReadability.Tests.ps1
# Export-InforcerTenantDocumentation readability, found by reading every per-baseline document of the
# inforcer Blueprint Library (2026-11-16): settings below two levels rendered empty, a dotted
# @odata.type setting was dropped, list items showed only "N items", authentication strength
# combinations fell apart, and every -Baseline re-read the whole tenant. Fixtures are synthetic.

BeforeAll {
    Remove-Module -Name 'InforcerCommunity' -ErrorAction SilentlyContinue
    Import-Module (Join-Path $PSScriptRoot '../module/InforcerCommunity.psd1') -Force
    $script:M = Get-Module InforcerCommunity

    function global:Get-ReadabilityRows([object]$PolicyData) {
        & $script:M { param($pd) ConvertTo-FlatSettingRows -PolicyData $pd } $PolicyData
    }
}

AfterAll {
    Remove-Item function:global:Get-ReadabilityRows -ErrorAction SilentlyContinue
}

Describe 'ConvertTo-FlatSettingRows shows what the policy configures' {
    It 'renders a setting nested three objects deep instead of an empty row' {
        $rows = Get-ReadabilityRows ([pscustomobject]@{ data = [pscustomobject]@{ PasskeyMigrationOptOut = [pscustomobject]@{
            optOutSettings = [pscustomobject]@{ passkeyDynamicMigration = $true } } } })
        $leaf = @($rows | Where-Object { $_.Value -eq 'True' })
        $leaf.Count | Should -Be 1
        $leaf[0].Name | Should -Match 'Passkey Dynamic Migration'
        $leaf[0].Indent | Should -Be 3
    }

    It 'renders a Conditional Access device filter rule' {
        $rows = Get-ReadabilityRows ([pscustomobject]@{ conditions = [pscustomobject]@{ devices = [pscustomobject]@{
            deviceFilter = [pscustomobject]@{ mode = 'exclude'; rule = 'device.isCompliant -eq True' } } } })
        @($rows | Where-Object { $_.Value -eq 'device.isCompliant -eq True' }).Count | Should -Be 1
    }

    It 'turns a dotted path ending in @odata.type into the setting it names' {
        $rows = Get-ReadabilityRows ([pscustomobject]@{ data = [pscustomobject]@{ UserAllowedToRegister = [pscustomobject]@{
            'azureADRegistration.allowedToRegister.@odata.type' = '#microsoft.graph.allDeviceRegistrationMembership' } } })
        $leaf = @($rows | Where-Object { $_.Value -match 'Registration Membership' })
        $leaf.Count | Should -Be 1
        $leaf[0].Value | Should -Not -Match 'microsoft\.graph|#'
    }

    It 'still drops @odata.type and other @odata keys that are serialisation metadata' {
        $rows = Get-ReadabilityRows ([pscustomobject]@{ '@odata.type' = '#microsoft.graph.x'; '_value@odata.type' = '#Guid'
            'grant@odata.context' = 'https://graph.microsoft.com/x'; state = 'enabled' })
        @($rows).Count | Should -Be 1
        $rows[0].Value | Should -Be 'enabled'
    }

    It 'lists every field of a list item that has no name' {
        $rows = @(Get-ReadabilityRows ([pscustomobject]@{ includeTargets = @([pscustomobject]@{ targetType = 'group'; id = 'all_users' }) }))
        $rows[0].Value | Should -Be '1 items'
        $rows[1].Name | Should -Be 'Item 1'
        @($rows | Where-Object { $_.Value -eq 'group' -and $_.Indent -eq 2 }).Count | Should -Be 1
        @($rows | Where-Object { $_.Value -eq 'all_users' -and $_.Indent -eq 2 }).Count | Should -Be 1
    }

    It 'labels a named list item by its name and keeps its id out of the label' {
        $rows = @(Get-ReadabilityRows ([pscustomobject]@{ passkeyProfiles = @([pscustomobject]@{
            id = '00000000-0000-0000-0000-000000000001'; name = 'Default passkey profile'; passkeyTypes = 'deviceBound' }) }))
        $rows[1].Name | Should -Be 'Default passkey profile'
        @($rows | Where-Object { $_.Value -eq 'deviceBound' }).Count | Should -Be 1
        @($rows | Where-Object { "$($_.Name)$($_.Value)" -match '00000000-0000' }).Count | Should -Be 0
    }

    It 'gives a list item with a single field one row' {
        $rows = @(Get-ReadabilityRows ([pscustomobject]@{ excludeTargets = @([pscustomobject]@{ id = '00000000-0000-0000-0000-0000000000a1' }) }))
        $rows.Count | Should -Be 2
        $rows[1].Value | Should -Be '00000000-0000-0000-0000-0000000000a1' -Because 'as a value, GUID resolution and masking can reach it'
    }

    It 'keeps list entries that hold a comma apart' {
        $rows = Get-ReadabilityRows ([pscustomobject]@{ allowedCombinations = @('fido2', 'password,softwareOath') })
        $rows[0].Value | Should -Be 'fido2; password,softwareOath'
        (Get-ReadabilityRows ([pscustomobject]@{ x = @('a', 'b') }))[0].Value | Should -Be 'a, b'
    }
}

Describe 'Authentication strength combinations read as combinations' {
    It 'names each combination once, with its methods joined by +' {
        $model = & $script:M {
            ConvertTo-InforcerDocModel -DocData @{
                Tenant = [pscustomobject]@{ tenantFriendlyName = 'T'; msTenantId = '00000000-0000-0000-0000-000000000001' }
                TenantId = 1; CollectedAt = [datetime]::UtcNow; Baselines = @()
                Policies = @([pscustomobject]@{ id = 'p1'; displayName = 'CA'; policyTypeId = 1; product = 'Entra'
                    primaryGroup = 'Conditional Access'; secondaryGroup = 'Policies'
                    policyData = [pscustomobject]@{ grantControls = [pscustomobject]@{ authenticationStrength = [pscustomobject]@{
                        allowedCombinations = @('fido2', 'password,softwareOath', 'password,microsoftAuthenticatorPush') } } } })
            }
        }
        $row = foreach ($p in $model.Products.Values) { foreach ($c in $p.Categories.Values) { foreach ($pol in $c) { $pol.Settings | Where-Object { $_.Name -eq 'Allowed Combinations' } } } }
        $row.Value | Should -Be 'FIDO2 Security Key; Password + Software OATH Token; Password + Microsoft Authenticator'
    }
}

Describe 'Export-InforcerTenantDocumentation with several baselines' {
    BeforeEach {
        Mock -ModuleName InforcerCommunity Test-InforcerSession { $true }
        Mock -ModuleName InforcerCommunity Resolve-InforcerTenantId { 1 }
        Mock -ModuleName InforcerCommunity Write-Host { }
        Mock -ModuleName InforcerCommunity Import-InforcerSettingsCatalog { }
        Mock -ModuleName InforcerCommunity Get-InforcerDocData {
            @{ TenantId = 1; Baselines = @(); CollectedAt = [datetime]::UtcNow
               Tenant = [pscustomobject]@{ tenantFriendlyName = 'Contoso'; msTenantId = '00000000-0000-0000-0000-000000000001' }
               Policies = @(
                   [pscustomobject]@{ id = 'a'; displayName = 'Policy A'; policyTypeId = 1; product = 'Entra'; primaryGroup = 'G'; secondaryGroup = 'S'; policyData = [pscustomobject]@{ state = 'enabled' } }
                   [pscustomobject]@{ id = 'b'; displayName = 'Policy B'; policyTypeId = 1; product = 'Entra'; primaryGroup = 'G'; secondaryGroup = 'S'; policyData = [pscustomobject]@{ state = 'disabled' } }
               ) }
        }
        # Keeps the policy whose id is the baseline name's last letter; 'Broken' does not resolve.
        Mock -ModuleName InforcerCommunity Select-InforcerBaselinePolicies {
            if ($BaselineId -eq 'Broken') { Write-Warning 'No baseline found with name: Broken'; return $null }
            $keep = $BaselineId.Substring($BaselineId.Length - 1).ToLower()
            $DocData.Policies = @($DocData.Policies | Where-Object { $_.id -eq $keep })
            $BaselineId
        }
    }

    It 'reads the tenant once and returns one document per baseline, each with only its policies' {
        $models = @(Export-InforcerTenantDocumentation -TenantId 1 -Baseline 'Baseline A', 'Baseline B')
        Should -Invoke -ModuleName InforcerCommunity Get-InforcerDocData -Times 1 -Exactly
        $models.Count | Should -Be 2
        $models[0].FilterBaseline | Should -Be 'Baseline A'
        @($models[0].Products['Entra'].Categories.Values | ForEach-Object { $_ } | ForEach-Object { $_.Basics.Name }) | Should -Be @('Policy A')
        @($models[1].Products['Entra'].Categories.Values | ForEach-Object { $_ } | ForEach-Object { $_.Basics.Name }) | Should -Be @('Policy B')
    }

    It 'reports a baseline that does not resolve and still documents the others' {
        $models = @(Export-InforcerTenantDocumentation -TenantId 1 -Baseline 'Broken', 'Baseline B' -ErrorVariable e -ErrorAction SilentlyContinue -WarningAction SilentlyContinue)
        $models.Count | Should -Be 1
        $models[0].FilterBaseline | Should -Be 'Baseline B'
        @($e | Where-Object { "$($_.FullyQualifiedErrorId)" -match '^BaselineFilterFailed' }).Count | Should -Be 1
    }

    It 'writes one file per baseline, named after it' {
        $dir = Join-Path $TestDrive 'out'
        $files = @(Export-InforcerTenantDocumentation -TenantId 1 -Baseline 'Baseline A', 'Baseline B' -Format Markdown -OutputPath $dir -Show:$false)
        @($files.Name | Sort-Object) | Should -Be @('Contoso-Baseline-A-Documentation.md', 'Contoso-Baseline-B-Documentation.md')
    }

    It 'refuses a file -OutputPath for several baselines' {
        { Export-InforcerTenantDocumentation -TenantId 1 -Baseline 'Baseline A', 'Baseline B' -Format Html -OutputPath (Join-Path $TestDrive 'one.html') -Show:$false } |
            Should -Throw -ErrorId 'OutputPathIsFileForSeveralBaselines*'
    }

    It 'keeps the single-baseline file name as it was' {
        $files = @(Export-InforcerTenantDocumentation -TenantId 1 -Baseline 'Baseline A' -Format Markdown -OutputPath (Join-Path $TestDrive 'single') -Show:$false)
        $files[0].Name | Should -Be 'Contoso-Documentation.md'
    }
}
