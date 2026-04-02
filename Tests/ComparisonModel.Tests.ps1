# ComparisonModel.Tests.ps1
# Pester 5.x tests for ConvertTo-InforcerComparisonModel.
# Run from repo root: Invoke-Pester ./Tests/ComparisonModel.Tests.ps1

$ErrorActionPreference = 'Stop'

BeforeAll {
    Remove-Module -Name 'InforcerCommunity' -ErrorAction SilentlyContinue
    $here = $PSScriptRoot
    $manifestPath = Join-Path $here '..' 'module' 'InforcerCommunity.psd1'
    $manifestPath = [System.IO.Path]::GetFullPath($manifestPath)
    Import-Module $manifestPath -Force -ErrorAction Stop

    # Set up a minimal settings catalog so Resolve-InforcerSettingName works
    InModuleScope InforcerCommunity {
        $script:InforcerSettingsCatalog = @{
            'device_vendor_msft_bitlocker_requiredeviceencryption' = @{
                DisplayName = 'Require Device Encryption'
                Description = 'Requires BitLocker encryption'
                Options     = @{
                    'device_vendor_msft_bitlocker_requiredeviceencryption_1' = 'Enabled'
                    'device_vendor_msft_bitlocker_requiredeviceencryption_0' = 'Disabled'
                }
            }
            'device_vendor_msft_firewall_enabled' = @{
                DisplayName = 'Firewall Enabled'
                Description = 'Windows Firewall'
                Options     = @{
                    'device_vendor_msft_firewall_enabled_true'  = 'True'
                    'device_vendor_msft_firewall_enabled_false' = 'False'
                }
            }
            'simple_setting_1' = @{
                DisplayName = 'Simple Setting One'
                Description = 'A simple setting'
                Options     = @{}
            }
        }
    }

    # -----------------------------------------------------------------------
    # Test helpers
    # -----------------------------------------------------------------------
    function New-SCPolicy {
        param(
            [string]$DisplayName,
            [string]$Product,
            [string]$PrimaryGroup,
            [string]$SecondaryGroup = '',
            [array]$Settings,
            [object]$Assignments = $null
        )
        [PSCustomObject]@{
            displayName            = $DisplayName
            friendlyName           = $null
            name                   = $null
            id                     = [guid]::NewGuid().ToString()
            product                = $Product
            primaryGroup           = $PrimaryGroup
            secondaryGroup         = $SecondaryGroup
            policyTypeId           = 10
            inforcerPolicyTypeName = 'Settings Catalog'
            policyData             = [PSCustomObject]@{
                displayName          = $DisplayName
                description          = ''
                createdDateTime      = '2025-01-01T00:00:00Z'
                lastModifiedDateTime = '2025-06-01T00:00:00Z'
                settings             = $Settings
                assignments          = $Assignments
            }
            tags = @()
        }
    }

    function New-Setting {
        param(
            [string]$SettingDefinitionId,
            [string]$ODataType = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance',
            [string]$Value
        )
        [PSCustomObject]@{
            settingInstance = [PSCustomObject]@{
                '@odata.type'       = $ODataType
                settingDefinitionId = $SettingDefinitionId
                choiceSettingValue  = [PSCustomObject]@{ value = $Value; children = @() }
            }
        }
    }

    function New-SimpleSetting {
        param(
            [string]$SettingDefinitionId,
            [object]$Value
        )
        [PSCustomObject]@{
            settingInstance = [PSCustomObject]@{
                '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance'
                settingDefinitionId = $SettingDefinitionId
                simpleSettingValue  = [PSCustomObject]@{ value = $Value }
            }
        }
    }

    function New-ComparisonData {
        param(
            [array]$SourcePolicies = @(),
            [array]$DestPolicies = @(),
            [bool]$IncludingAssignments = $false
        )
        @{
            SourcePolicies       = $SourcePolicies
            DestinationPolicies  = $DestPolicies
            SourceName           = 'Source Tenant'
            DestinationName      = 'Dest Tenant'
            SettingsCatalog      = @{}
            IncludingAssignments = $IncludingAssignments
            CollectedAt          = [datetime]::UtcNow
        }
    }
}

# ---------------------------------------------------------------------------
# Describe: Model structure
# ---------------------------------------------------------------------------
Describe 'ConvertTo-InforcerComparisonModel - Model structure' {

    It 'returns a hashtable with all required top-level keys' {
        $data = New-ComparisonData
        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $model.Keys | Should -Contain 'SourceName'
        $model.Keys | Should -Contain 'DestinationName'
        $model.Keys | Should -Contain 'GeneratedAt'
        $model.Keys | Should -Contain 'AlignmentScore'
        $model.Keys | Should -Contain 'TotalItems'
        $model.Keys | Should -Contain 'Counters'
        $model.Keys | Should -Contain 'Products'
        $model.Keys | Should -Contain 'ManualReview'
        $model.Keys | Should -Contain 'IncludingAssignments'
    }

    It 'Counters has Matched, Conflicting, SourceOnly, DestOnly keys' {
        $data = New-ComparisonData
        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $model.Counters.Keys | Should -Contain 'Matched'
        $model.Counters.Keys | Should -Contain 'Conflicting'
        $model.Counters.Keys | Should -Contain 'SourceOnly'
        $model.Counters.Keys | Should -Contain 'DestOnly'
    }

    It 'Products is an OrderedDictionary' {
        $data = New-ComparisonData
        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $model.Products.GetType().Name | Should -Be 'OrderedDictionary'
    }

    It 'ManualReview is an empty OrderedDictionary' {
        $data = New-ComparisonData
        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $model.ManualReview.GetType().Name | Should -Be 'OrderedDictionary'
        $model.ManualReview.Count | Should -Be 0
    }
}

# ---------------------------------------------------------------------------
# Describe: Settings Catalog matching
# ---------------------------------------------------------------------------
Describe 'ConvertTo-InforcerComparisonModel - Settings Catalog matching' {

    It 'identical settings in different policies are Matched' {
        $srcPolicy = New-SCPolicy -DisplayName 'SC Policy A' -Product 'Intune' -PrimaryGroup 'Endpoint Security' -Settings @(
            (New-Setting -SettingDefinitionId 'device_vendor_msft_bitlocker_requiredeviceencryption' -Value 'device_vendor_msft_bitlocker_requiredeviceencryption_1')
        )
        $dstPolicy = New-SCPolicy -DisplayName 'SC Policy B' -Product 'Intune' -PrimaryGroup 'Endpoint Security' -Settings @(
            (New-Setting -SettingDefinitionId 'device_vendor_msft_bitlocker_requiredeviceencryption' -Value 'device_vendor_msft_bitlocker_requiredeviceencryption_1')
        )
        $data = New-ComparisonData -SourcePolicies @($srcPolicy) -DestPolicies @($dstPolicy)

        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $model.Counters.Matched | Should -Be 1
        $model.Counters.Conflicting | Should -Be 0
    }

    It 'same settingDefinitionId with different values is Conflicting' {
        $srcPolicy = New-SCPolicy -DisplayName 'SC Policy A' -Product 'Intune' -PrimaryGroup 'Endpoint Security' -Settings @(
            (New-Setting -SettingDefinitionId 'device_vendor_msft_bitlocker_requiredeviceencryption' -Value 'device_vendor_msft_bitlocker_requiredeviceencryption_1')
        )
        $dstPolicy = New-SCPolicy -DisplayName 'SC Policy B' -Product 'Intune' -PrimaryGroup 'Endpoint Security' -Settings @(
            (New-Setting -SettingDefinitionId 'device_vendor_msft_bitlocker_requiredeviceencryption' -Value 'device_vendor_msft_bitlocker_requiredeviceencryption_0')
        )
        $data = New-ComparisonData -SourcePolicies @($srcPolicy) -DestPolicies @($dstPolicy)

        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $model.Counters.Conflicting | Should -Be 1
        $model.Counters.Matched | Should -Be 0
    }

    It 'settings only in source are SourceOnly' {
        $srcPolicy = New-SCPolicy -DisplayName 'SC Policy A' -Product 'Intune' -PrimaryGroup 'Endpoint Security' -Settings @(
            (New-Setting -SettingDefinitionId 'device_vendor_msft_firewall_enabled' -Value 'device_vendor_msft_firewall_enabled_true')
        )
        $data = New-ComparisonData -SourcePolicies @($srcPolicy) -DestPolicies @()

        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $model.Counters.SourceOnly | Should -Be 1
    }

    It 'settings only in destination are DestOnly' {
        $dstPolicy = New-SCPolicy -DisplayName 'SC Policy B' -Product 'Intune' -PrimaryGroup 'Endpoint Security' -Settings @(
            (New-Setting -SettingDefinitionId 'device_vendor_msft_firewall_enabled' -Value 'device_vendor_msft_firewall_enabled_true')
        )
        $data = New-ComparisonData -SourcePolicies @() -DestPolicies @($dstPolicy)

        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $model.Counters.DestOnly | Should -Be 1
    }

    It 'handles simple setting instances correctly' {
        $srcPolicy = New-SCPolicy -DisplayName 'SC Simple' -Product 'Intune' -PrimaryGroup 'Config' -Settings @(
            (New-SimpleSetting -SettingDefinitionId 'simple_setting_1' -Value 42)
        )
        $dstPolicy = New-SCPolicy -DisplayName 'SC Simple Dest' -Product 'Intune' -PrimaryGroup 'Config' -Settings @(
            (New-SimpleSetting -SettingDefinitionId 'simple_setting_1' -Value 42)
        )
        $data = New-ComparisonData -SourcePolicies @($srcPolicy) -DestPolicies @($dstPolicy)

        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $model.Counters.Matched | Should -Be 1
    }

    It 'comparison rows have correct ItemType "Setting"' {
        $srcPolicy = New-SCPolicy -DisplayName 'SC Policy' -Product 'Intune' -PrimaryGroup 'Endpoint Security' -Settings @(
            (New-Setting -SettingDefinitionId 'device_vendor_msft_bitlocker_requiredeviceencryption' -Value 'device_vendor_msft_bitlocker_requiredeviceencryption_1')
        )
        $dstPolicy = New-SCPolicy -DisplayName 'SC Policy Dest' -Product 'Intune' -PrimaryGroup 'Endpoint Security' -Settings @(
            (New-Setting -SettingDefinitionId 'device_vendor_msft_bitlocker_requiredeviceencryption' -Value 'device_vendor_msft_bitlocker_requiredeviceencryption_1')
        )
        $data = New-ComparisonData -SourcePolicies @($srcPolicy) -DestPolicies @($dstPolicy)

        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $row = $model.Products['Intune'].Categories.Values | ForEach-Object { $_.ComparisonRows } | Select-Object -First 1
        $row.ItemType | Should -Be 'Setting'
    }

    It 'comparison rows include SettingDefinitionId' {
        $srcPolicy = New-SCPolicy -DisplayName 'SC Policy' -Product 'Intune' -PrimaryGroup 'Endpoint Security' -Settings @(
            (New-Setting -SettingDefinitionId 'device_vendor_msft_bitlocker_requiredeviceencryption' -Value 'device_vendor_msft_bitlocker_requiredeviceencryption_1')
        )
        $dstPolicy = New-SCPolicy -DisplayName 'SC Policy Dest' -Product 'Intune' -PrimaryGroup 'Endpoint Security' -Settings @(
            (New-Setting -SettingDefinitionId 'device_vendor_msft_bitlocker_requiredeviceencryption' -Value 'device_vendor_msft_bitlocker_requiredeviceencryption_1')
        )
        $data = New-ComparisonData -SourcePolicies @($srcPolicy) -DestPolicies @($dstPolicy)

        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $row = $model.Products['Intune'].Categories.Values | ForEach-Object { $_.ComparisonRows } | Select-Object -First 1
        $row.SettingDefinitionId | Should -Be 'device_vendor_msft_bitlocker_requiredeviceencryption'
    }

    It 'resolves friendly names from settings catalog' {
        $srcPolicy = New-SCPolicy -DisplayName 'SC Policy' -Product 'Intune' -PrimaryGroup 'Endpoint Security' -Settings @(
            (New-Setting -SettingDefinitionId 'device_vendor_msft_bitlocker_requiredeviceencryption' -Value 'device_vendor_msft_bitlocker_requiredeviceencryption_1')
        )
        $dstPolicy = New-SCPolicy -DisplayName 'SC Policy Dest' -Product 'Intune' -PrimaryGroup 'Endpoint Security' -Settings @(
            (New-Setting -SettingDefinitionId 'device_vendor_msft_bitlocker_requiredeviceencryption' -Value 'device_vendor_msft_bitlocker_requiredeviceencryption_1')
        )
        $data = New-ComparisonData -SourcePolicies @($srcPolicy) -DestPolicies @($dstPolicy)

        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $row = $model.Products['Intune'].Categories.Values | ForEach-Object { $_.ComparisonRows } | Select-Object -First 1
        $row.Name | Should -Be 'Require Device Encryption'
    }

    It 'ignores non-SC policies (policyTypeId != 10)' {
        $nonScPolicy = [PSCustomObject]@{
            displayName            = 'Admin Template'
            friendlyName           = $null
            name                   = $null
            id                     = [guid]::NewGuid().ToString()
            product                = 'Intune'
            primaryGroup           = 'Admin Templates'
            secondaryGroup         = ''
            policyTypeId           = 5
            inforcerPolicyTypeName = 'Admin Template'
            policyData             = [PSCustomObject]@{
                displayName = 'Admin Template'
                settingA    = 'valueA'
            }
            tags = @()
        }
        $data = New-ComparisonData -SourcePolicies @($nonScPolicy) -DestPolicies @()

        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $model.TotalItems | Should -Be 0
        $model.Products.Count | Should -Be 0
    }
}

# ---------------------------------------------------------------------------
# Describe: Empty environments
# ---------------------------------------------------------------------------
Describe 'ConvertTo-InforcerComparisonModel - Empty environments' {

    It 'both environments empty gives 100% alignment score' {
        $data = New-ComparisonData
        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $model.AlignmentScore | Should -Be 100
        $model.TotalItems | Should -Be 0
    }

    It 'source empty, destination has SC policies gives all DestOnly' {
        $dstPolicy = New-SCPolicy -DisplayName 'Dest SC' -Product 'Intune' -PrimaryGroup 'Config' -Settings @(
            (New-Setting -SettingDefinitionId 'device_vendor_msft_firewall_enabled' -Value 'device_vendor_msft_firewall_enabled_true')
        )
        $data = New-ComparisonData -SourcePolicies @() -DestPolicies @($dstPolicy)

        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $model.Counters.DestOnly | Should -Be 1
        $model.Counters.SourceOnly | Should -Be 0
        $model.Counters.Matched | Should -Be 0
    }

    It 'destination empty, source has SC policies gives all SourceOnly' {
        $srcPolicy = New-SCPolicy -DisplayName 'Src SC' -Product 'Intune' -PrimaryGroup 'Config' -Settings @(
            (New-Setting -SettingDefinitionId 'device_vendor_msft_firewall_enabled' -Value 'device_vendor_msft_firewall_enabled_true')
        )
        $data = New-ComparisonData -SourcePolicies @($srcPolicy) -DestPolicies @()

        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $model.Counters.SourceOnly | Should -Be 1
        $model.Counters.DestOnly | Should -Be 0
    }
}

# ---------------------------------------------------------------------------
# Describe: Alignment score calculation
# ---------------------------------------------------------------------------
Describe 'ConvertTo-InforcerComparisonModel - Alignment score' {

    It '100% when all settings match' {
        $srcPolicy = New-SCPolicy -DisplayName 'SC A' -Product 'Intune' -PrimaryGroup 'Config' -Settings @(
            (New-Setting -SettingDefinitionId 'device_vendor_msft_bitlocker_requiredeviceencryption' -Value 'device_vendor_msft_bitlocker_requiredeviceencryption_1')
        )
        $dstPolicy = New-SCPolicy -DisplayName 'SC B' -Product 'Intune' -PrimaryGroup 'Config' -Settings @(
            (New-Setting -SettingDefinitionId 'device_vendor_msft_bitlocker_requiredeviceencryption' -Value 'device_vendor_msft_bitlocker_requiredeviceencryption_1')
        )
        $data = New-ComparisonData -SourcePolicies @($srcPolicy) -DestPolicies @($dstPolicy)

        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $model.AlignmentScore | Should -Be 100
    }

    It '0% when no items match (all one-sided)' {
        $srcPolicy = New-SCPolicy -DisplayName 'SC A' -Product 'Intune' -PrimaryGroup 'Config' -Settings @(
            (New-Setting -SettingDefinitionId 'device_vendor_msft_bitlocker_requiredeviceencryption' -Value 'device_vendor_msft_bitlocker_requiredeviceencryption_1')
        )
        $dstPolicy = New-SCPolicy -DisplayName 'SC B' -Product 'Intune' -PrimaryGroup 'Config' -Settings @(
            (New-Setting -SettingDefinitionId 'device_vendor_msft_firewall_enabled' -Value 'device_vendor_msft_firewall_enabled_true')
        )
        $data = New-ComparisonData -SourcePolicies @($srcPolicy) -DestPolicies @($dstPolicy)

        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $model.AlignmentScore | Should -Be 0
    }

    It 'calculates correct percentage for mixed results' {
        # 1 matched + 1 source-only = 50%
        $srcPolicy = New-SCPolicy -DisplayName 'SC Src' -Product 'Intune' -PrimaryGroup 'Config' -Settings @(
            (New-Setting -SettingDefinitionId 'device_vendor_msft_bitlocker_requiredeviceencryption' -Value 'device_vendor_msft_bitlocker_requiredeviceencryption_1'),
            (New-Setting -SettingDefinitionId 'device_vendor_msft_firewall_enabled' -Value 'device_vendor_msft_firewall_enabled_true')
        )
        $dstPolicy = New-SCPolicy -DisplayName 'SC Dst' -Product 'Intune' -PrimaryGroup 'Config' -Settings @(
            (New-Setting -SettingDefinitionId 'device_vendor_msft_bitlocker_requiredeviceencryption' -Value 'device_vendor_msft_bitlocker_requiredeviceencryption_1')
        )

        $data = New-ComparisonData -SourcePolicies @($srcPolicy) -DestPolicies @($dstPolicy)

        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $model.AlignmentScore | Should -Be 50
    }
}

# ---------------------------------------------------------------------------
# Describe: Product-level counters
# ---------------------------------------------------------------------------
Describe 'ConvertTo-InforcerComparisonModel - Product counters' {

    It 'each product has its own Counters' {
        $src1 = New-SCPolicy -DisplayName 'SC1' -Product 'Intune' -PrimaryGroup 'Config' -Settings @(
            (New-Setting -SettingDefinitionId 'device_vendor_msft_bitlocker_requiredeviceencryption' -Value 'device_vendor_msft_bitlocker_requiredeviceencryption_1')
        )
        $dst1 = New-SCPolicy -DisplayName 'SC1D' -Product 'Intune' -PrimaryGroup 'Config' -Settings @(
            (New-Setting -SettingDefinitionId 'device_vendor_msft_bitlocker_requiredeviceencryption' -Value 'device_vendor_msft_bitlocker_requiredeviceencryption_1')
        )
        $src2 = New-SCPolicy -DisplayName 'SC2' -Product 'Entra' -PrimaryGroup 'Settings' -Settings @(
            (New-Setting -SettingDefinitionId 'device_vendor_msft_firewall_enabled' -Value 'device_vendor_msft_firewall_enabled_true')
        )

        $data = New-ComparisonData -SourcePolicies @($src1, $src2) -DestPolicies @($dst1)

        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $model.Products['Intune'].Counters.Matched | Should -Be 1
        $model.Products['Entra'].Counters.SourceOnly | Should -Be 1
    }
}

# ---------------------------------------------------------------------------
# Describe: Assignments
# ---------------------------------------------------------------------------
Describe 'ConvertTo-InforcerComparisonModel - Assignments' {

    It 'includes assignment info in rows when IncludingAssignments is true' {
        $assignments = @(
            [PSCustomObject]@{
                target = [PSCustomObject]@{
                    '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget'
                }
            }
        )
        $srcPolicy = New-SCPolicy -DisplayName 'WithAssign' -Product 'Intune' -PrimaryGroup 'Config' -Settings @(
            (New-Setting -SettingDefinitionId 'device_vendor_msft_bitlocker_requiredeviceencryption' -Value 'device_vendor_msft_bitlocker_requiredeviceencryption_1')
        ) -Assignments $assignments
        $dstPolicy = New-SCPolicy -DisplayName 'WithAssignDst' -Product 'Intune' -PrimaryGroup 'Config' -Settings @(
            (New-Setting -SettingDefinitionId 'device_vendor_msft_bitlocker_requiredeviceencryption' -Value 'device_vendor_msft_bitlocker_requiredeviceencryption_1')
        ) -Assignments $assignments
        $data = New-ComparisonData -SourcePolicies @($srcPolicy) -DestPolicies @($dstPolicy) -IncludingAssignments $true

        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $model.IncludingAssignments | Should -BeTrue
        $row = $model.Products['Intune'].Categories.Values | ForEach-Object { $_.ComparisonRows } | Select-Object -First 1
        $row.Keys -contains 'SourceAssignment' | Should -BeTrue
        $row.SourceAssignment | Should -Be 'All Devices'
    }

    It 'omits assignment fields when IncludingAssignments is false' {
        $srcPolicy = New-SCPolicy -DisplayName 'NoAssign' -Product 'Intune' -PrimaryGroup 'Config' -Settings @(
            (New-Setting -SettingDefinitionId 'device_vendor_msft_bitlocker_requiredeviceencryption' -Value 'device_vendor_msft_bitlocker_requiredeviceencryption_1')
        )
        $dstPolicy = New-SCPolicy -DisplayName 'NoAssignDst' -Product 'Intune' -PrimaryGroup 'Config' -Settings @(
            (New-Setting -SettingDefinitionId 'device_vendor_msft_bitlocker_requiredeviceencryption' -Value 'device_vendor_msft_bitlocker_requiredeviceencryption_1')
        )
        $data = New-ComparisonData -SourcePolicies @($srcPolicy) -DestPolicies @($dstPolicy) -IncludingAssignments $false

        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $model.IncludingAssignments | Should -BeFalse
    }
}
