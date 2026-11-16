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

    It 'marks a list and its item labels as headers, so comparisons keep their context' {
        $rows = @(Get-ReadabilityRows ([pscustomobject]@{ includeTargets = @([pscustomobject]@{ targetType = 'group'; id = 'all_users' }) }))
        $rows[0].IsConfigured | Should -BeFalse -Because 'the list is a parent in the setting path'
        $rows[1].IsConfigured | Should -BeFalse -Because 'Item 1 is a parent of its fields'
        @($rows | Where-Object { $_.Value -eq 'all_users' })[0].IsConfigured | Should -BeTrue
    }

    It 'keeps a name-only list item a setting' {
        $rows = @(Get-ReadabilityRows ([pscustomobject]@{ apps = @([pscustomobject]@{ bundleId = 'com.example.app' }) }))
        @($rows | Where-Object { $_.Name -eq 'com.example.app' })[0].IsConfigured | Should -BeTrue
    }

    It 'renders objects and lists nested inside a list item' {
        $rows = @(Get-ReadabilityRows ([pscustomobject]@{ profiles = @([pscustomobject]@{ name = 'P1'
            options = [pscustomobject]@{ enabled = $true }; types = @('a', 'b') }) }))
        $enabled = @($rows | Where-Object { $_.Name -match 'Enabled' -and $_.Value -eq 'True' })
        $enabled.Count | Should -Be 1
        $enabled[0].Indent | Should -Be 3
        @($rows | Where-Object { $_.Value -eq 'a, b' }).Count | Should -Be 1
    }

    It 'decodes an encoded payload inside a list item like any other payload' {
        $b64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('<?xml version="1.0"?><plist><dict/></plist>'))
        $rows = @(Get-ReadabilityRows ([pscustomobject]@{ profiles = @([pscustomobject]@{ name = 'P1'; payload = $b64 }) }))
        @($rows | Where-Object { "$($_.Value)" -like '__SCRIPT_CODE__<?xml*' }).Count | Should -Be 1
    }

    It 'keeps a list item''s description, which the renderer skips at policy level' {
        $rows = @(Get-ReadabilityRows ([pscustomobject]@{ indicators = @([pscustomobject]@{ indicatorValue = 'example.com'; description = 'Shadow AI'; action = 'Block' }) }))
        @($rows | Where-Object { $_.Name -eq 'Description' -and $_.Value -eq 'Shadow AI' }).Count | Should -Be 1
    }

    It 'keeps a dotted @odata.type setting inside a list item' {
        $rows = @(Get-ReadabilityRows ([pscustomobject]@{ items = @([pscustomobject]@{ name = 'P1'
            '@odata.type' = '#microsoft.graph.x'; 'registration.allowed.@odata.type' = '#microsoft.graph.allDeviceRegistrationMembership' }) }))
        @($rows | Where-Object { $_.Value -eq 'All Device Registration Membership' }).Count | Should -Be 1
        @($rows | Where-Object { "$($_.Value)" -match 'microsoft\.graph' }).Count | Should -Be 0
    }

    It 'gives every list item its own dotted headers' {
        $rows = @(Get-ReadabilityRows ([pscustomobject]@{ profiles = @(
            [pscustomobject]@{ name = 'P1'; options = [pscustomobject]@{ 'mode.level' = 1 } }
            [pscustomobject]@{ name = 'P2'; options = [pscustomobject]@{ 'mode.level' = 2 } }) }))
        @($rows | Where-Object { $_.Name -eq 'Mode' }).Count | Should -Be 2 -Because 'each item''s Level needs Mode in its path'
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

Describe 'Only Allowed Combinations is read as authentication combinations' {
    It 'leaves other values with semicolons and commas exactly as configured' {
        $model = & $script:M {
            ConvertTo-InforcerDocModel -DocData @{
                Tenant = [pscustomobject]@{ tenantFriendlyName = 'T'; msTenantId = '00000000-0000-0000-0000-000000000001' }
                TenantId = 1; CollectedAt = [datetime]::UtcNow; Baselines = @()
                Policies = @([pscustomobject]@{ id = 'p1'; displayName = 'Chrome'; policyTypeId = 3; product = 'Intune'
                    primaryGroup = 'Windows'; secondaryGroup = 'Configuration'
                    policyData = [pscustomobject]@{ extensionList = 'abc;https://clients2.google.com/crx, def;sms'
                        scriptContent = 'Write-Output sms,voice; Write-Output fido2' } })
            }
        }
        $rows = foreach ($p in $model.Products.Values) { foreach ($c in $p.Categories.Values) { foreach ($pol in $c) { $pol.Settings } } }
        @($rows | Where-Object { $_.Value -eq 'abc;https://clients2.google.com/crx, def;sms' }).Count | Should -Be 1
        @($rows | Where-Object { "$($_.Value)" -match '\+' }).Count | Should -Be 0
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

    It 'gives baselines whose names make the same file name their own file' {
        $dir = Join-Path $TestDrive 'collide'
        $files = @(Export-InforcerTenantDocumentation -TenantId 1 -Baseline 'Tier A', 'Tier-A' -Format Markdown -OutputPath $dir -Show:$false)
        @($files.FullName | Sort-Object -Unique).Count | Should -Be 2
        @(Get-ChildItem $dir).Count | Should -Be 2
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
