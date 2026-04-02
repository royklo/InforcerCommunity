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

    # -----------------------------------------------------------------------
    # Test helpers — must be in BeforeAll so Pester 5 "run" phase can see them
    # -----------------------------------------------------------------------
    function New-SCPolicy {
        param(
            [string]$DisplayName,
            [string]$Product,
            [string]$PrimaryGroup,
            [string]$SecondaryGroup = '',
            [int]$PolicyTypeId = 10,
            [array]$SettingDefinitions,
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
            policyTypeId           = $PolicyTypeId
            inforcerPolicyTypeName = 'Settings Catalog'
            policyData             = [PSCustomObject]@{
                displayName            = $DisplayName
                description            = ''
                createdDateTime        = '2025-01-01T00:00:00Z'
                lastModifiedDateTime   = '2025-06-01T00:00:00Z'
                settings               = @()
                settingDefinitions     = $SettingDefinitions
                assignments            = $Assignments
            }
            tags = @()
        }
    }

    function New-SettingDefinition {
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

    function New-SimpleSettingDefinition {
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

    function New-NonSCPolicy {
        param(
            [string]$DisplayName,
            [string]$Product,
            [string]$PrimaryGroup,
            [string]$SecondaryGroup = '',
            [int]$PolicyTypeId = 5,
            [hashtable]$PolicyDataProps = @{},
            [object]$Assignments = $null
        )
        $pdBase = @{
            displayName          = $DisplayName
            description          = ''
            createdDateTime      = '2025-01-01T00:00:00Z'
            lastModifiedDateTime = '2025-06-01T00:00:00Z'
            assignments          = $Assignments
        }
        foreach ($k in $PolicyDataProps.Keys) { $pdBase[$k] = $PolicyDataProps[$k] }
        $pd = [PSCustomObject]$pdBase

        [PSCustomObject]@{
            displayName            = $DisplayName
            friendlyName           = $null
            name                   = $null
            id                     = [guid]::NewGuid().ToString()
            product                = $Product
            primaryGroup           = $PrimaryGroup
            secondaryGroup         = $SecondaryGroup
            policyTypeId           = $PolicyTypeId
            inforcerPolicyTypeName = 'Admin Template'
            policyData             = $pd
            tags = @()
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
            SourceType           = 'Tenant'
            DestinationType      = 'Tenant'
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
        $model.Keys | Should -Contain 'SourceType'
        $model.Keys | Should -Contain 'DestinationType'
        $model.Keys | Should -Contain 'GeneratedAt'
        $model.Keys | Should -Contain 'AlignmentScore'
        $model.Keys | Should -Contain 'TotalItems'
        $model.Keys | Should -Contain 'Counters'
        $model.Keys | Should -Contain 'Products'
        $model.Keys | Should -Contain 'ManualReview'
        $model.Keys | Should -Contain 'IncludingAssignments'
    }

    It 'Counters has Matched, Conflicting, SourceOnly, DestOnly, Manual keys' {
        $data = New-ComparisonData
        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $model.Counters.Keys | Should -Contain 'Matched'
        $model.Counters.Keys | Should -Contain 'Conflicting'
        $model.Counters.Keys | Should -Contain 'SourceOnly'
        $model.Counters.Keys | Should -Contain 'DestOnly'
        $model.Counters.Keys | Should -Contain 'Manual'
    }

    It 'Products is an OrderedDictionary' {
        $data = New-ComparisonData
        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $model.Products.GetType().Name | Should -Be 'OrderedDictionary'
    }
}

# ---------------------------------------------------------------------------
# Describe: Settings Catalog matching (Strategy A)
# ---------------------------------------------------------------------------
Describe 'ConvertTo-InforcerComparisonModel - Settings Catalog matching' {

    It 'identical settings in different policies are Matched' {
        $srcPolicy = New-SCPolicy -DisplayName 'SC Policy A' -Product 'Intune' -PrimaryGroup 'Endpoint Security' -SettingDefinitions @(
            (New-SettingDefinition -SettingDefinitionId 'setting_1' -Value 'value_enabled')
        )
        $dstPolicy = New-SCPolicy -DisplayName 'SC Policy B' -Product 'Intune' -PrimaryGroup 'Endpoint Security' -SettingDefinitions @(
            (New-SettingDefinition -SettingDefinitionId 'setting_1' -Value 'value_enabled')
        )
        $data = New-ComparisonData -SourcePolicies @($srcPolicy) -DestPolicies @($dstPolicy)

        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $model.Counters.Matched | Should -Be 1
        $model.Counters.Conflicting | Should -Be 0
    }

    It 'same settingDefinitionId with different values is Conflicting' {
        $srcPolicy = New-SCPolicy -DisplayName 'SC Policy A' -Product 'Intune' -PrimaryGroup 'Endpoint Security' -SettingDefinitions @(
            (New-SettingDefinition -SettingDefinitionId 'setting_1' -Value 'value_enabled')
        )
        $dstPolicy = New-SCPolicy -DisplayName 'SC Policy B' -Product 'Intune' -PrimaryGroup 'Endpoint Security' -SettingDefinitions @(
            (New-SettingDefinition -SettingDefinitionId 'setting_1' -Value 'value_disabled')
        )
        $data = New-ComparisonData -SourcePolicies @($srcPolicy) -DestPolicies @($dstPolicy)

        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $model.Counters.Conflicting | Should -Be 1
        $model.Counters.Matched | Should -Be 0
    }

    It 'settings only in source are SourceOnly' {
        $srcPolicy = New-SCPolicy -DisplayName 'SC Policy A' -Product 'Intune' -PrimaryGroup 'Endpoint Security' -SettingDefinitions @(
            (New-SettingDefinition -SettingDefinitionId 'setting_src_only' -Value 'value_1')
        )
        $data = New-ComparisonData -SourcePolicies @($srcPolicy) -DestPolicies @()

        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $model.Counters.SourceOnly | Should -Be 1
    }

    It 'settings only in destination are DestOnly' {
        $dstPolicy = New-SCPolicy -DisplayName 'SC Policy B' -Product 'Intune' -PrimaryGroup 'Endpoint Security' -SettingDefinitions @(
            (New-SettingDefinition -SettingDefinitionId 'setting_dst_only' -Value 'value_1')
        )
        $data = New-ComparisonData -SourcePolicies @() -DestPolicies @($dstPolicy)

        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $model.Counters.DestOnly | Should -Be 1
    }

    It 'handles simple setting instances correctly' {
        $srcPolicy = New-SCPolicy -DisplayName 'SC Simple' -Product 'Intune' -PrimaryGroup 'Config' -SettingDefinitions @(
            (New-SimpleSettingDefinition -SettingDefinitionId 'simple_1' -Value 42)
        )
        $dstPolicy = New-SCPolicy -DisplayName 'SC Simple Dest' -Product 'Intune' -PrimaryGroup 'Config' -SettingDefinitions @(
            (New-SimpleSettingDefinition -SettingDefinitionId 'simple_1' -Value 42)
        )
        $data = New-ComparisonData -SourcePolicies @($srcPolicy) -DestPolicies @($dstPolicy)

        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $model.Counters.Matched | Should -Be 1
    }

    It 'comparison rows have correct ItemType "Setting" for SC policies' {
        $srcPolicy = New-SCPolicy -DisplayName 'SC Policy' -Product 'Intune' -PrimaryGroup 'Endpoint Security' -SettingDefinitions @(
            (New-SettingDefinition -SettingDefinitionId 'setting_1' -Value 'value_enabled')
        )
        $dstPolicy = New-SCPolicy -DisplayName 'SC Policy Dest' -Product 'Intune' -PrimaryGroup 'Endpoint Security' -SettingDefinitions @(
            (New-SettingDefinition -SettingDefinitionId 'setting_1' -Value 'value_enabled')
        )
        $data = New-ComparisonData -SourcePolicies @($srcPolicy) -DestPolicies @($dstPolicy)

        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $row = $model.Products['Intune'].Categories.Values | ForEach-Object { $_.ComparisonRows } | Select-Object -First 1
        $row.ItemType | Should -Be 'Setting'
    }
}

# ---------------------------------------------------------------------------
# Describe: Policy-level matching (Strategy B)
# ---------------------------------------------------------------------------
Describe 'ConvertTo-InforcerComparisonModel - Policy-level matching' {

    It 'same match key and same policyData is Matched' {
        $srcPolicy = New-NonSCPolicy -DisplayName 'Admin Template 1' -Product 'Intune' -PrimaryGroup 'Admin Templates' -PolicyTypeId 5 -PolicyDataProps @{ settingA = 'valueA'; settingB = 100 }
        $dstPolicy = New-NonSCPolicy -DisplayName 'Admin Template 1' -Product 'Intune' -PrimaryGroup 'Admin Templates' -PolicyTypeId 5 -PolicyDataProps @{ settingA = 'valueA'; settingB = 100 }
        $data = New-ComparisonData -SourcePolicies @($srcPolicy) -DestPolicies @($dstPolicy)

        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $model.Counters.Matched | Should -Be 1
        $model.Counters.Conflicting | Should -Be 0
    }

    It 'same match key but different policyData is Conflicting' {
        $srcPolicy = New-NonSCPolicy -DisplayName 'Admin Template 1' -Product 'Intune' -PrimaryGroup 'Admin Templates' -PolicyTypeId 5 -PolicyDataProps @{ settingA = 'valueA' }
        $dstPolicy = New-NonSCPolicy -DisplayName 'Admin Template 1' -Product 'Intune' -PrimaryGroup 'Admin Templates' -PolicyTypeId 5 -PolicyDataProps @{ settingA = 'valueB' }
        $data = New-ComparisonData -SourcePolicies @($srcPolicy) -DestPolicies @($dstPolicy)

        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $model.Counters.Conflicting | Should -Be 1
    }

    It 'unmatched non-SC policy without SC overlap is SourceOnly or DestOnly' {
        $srcPolicy = New-NonSCPolicy -DisplayName 'Admin Template Src' -Product 'Intune' -PrimaryGroup 'Admin Templates' -PolicyTypeId 5 -PolicyDataProps @{ settingA = 'valueA' }
        $data = New-ComparisonData -SourcePolicies @($srcPolicy) -DestPolicies @()

        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $model.Counters.SourceOnly | Should -Be 1
    }

    It 'comparison rows have correct ItemType "Policy" for non-SC policies' {
        $srcPolicy = New-NonSCPolicy -DisplayName 'Admin Template 1' -Product 'Intune' -PrimaryGroup 'Admin Templates' -PolicyTypeId 5 -PolicyDataProps @{ settingA = 'valueA' }
        $dstPolicy = New-NonSCPolicy -DisplayName 'Admin Template 1' -Product 'Intune' -PrimaryGroup 'Admin Templates' -PolicyTypeId 5 -PolicyDataProps @{ settingA = 'valueA' }
        $data = New-ComparisonData -SourcePolicies @($srcPolicy) -DestPolicies @($dstPolicy)

        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $row = $model.Products['Intune'].Categories.Values | ForEach-Object { $_.ComparisonRows } | Select-Object -First 1
        $row.ItemType | Should -Be 'Policy'
    }
}

# ---------------------------------------------------------------------------
# Describe: Manual review detection
# ---------------------------------------------------------------------------
Describe 'ConvertTo-InforcerComparisonModel - Manual review' {

    It 'unmatched non-SC policy in area with SC policies triggers manual review' {
        # SC policy in same product/category
        $scPolicy = New-SCPolicy -DisplayName 'SC Policy' -Product 'Intune' -PrimaryGroup 'Endpoint Security' -SettingDefinitions @(
            (New-SettingDefinition -SettingDefinitionId 'setting_1' -Value 'value_enabled')
        )
        # Unmatched admin template in same product/category
        $adminPolicy = New-NonSCPolicy -DisplayName 'Admin Unmatched' -Product 'Intune' -PrimaryGroup 'Endpoint Security' -PolicyTypeId 5 -PolicyDataProps @{ settingA = 'valueA' }

        $data = New-ComparisonData -SourcePolicies @($scPolicy, $adminPolicy) -DestPolicies @($scPolicy)

        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $model.Counters.Manual | Should -BeGreaterOrEqual 1
        $model.ManualReview.Count | Should -BeGreaterOrEqual 1
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

    It 'source empty, destination has policies gives all DestOnly' {
        $dstPolicy = New-NonSCPolicy -DisplayName 'Dest Only' -Product 'Intune' -PrimaryGroup 'Config' -PolicyDataProps @{ a = 1 }
        $data = New-ComparisonData -SourcePolicies @() -DestPolicies @($dstPolicy)

        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $model.Counters.DestOnly | Should -Be 1
        $model.Counters.SourceOnly | Should -Be 0
        $model.Counters.Matched | Should -Be 0
    }

    It 'destination empty, source has policies gives all SourceOnly' {
        $srcPolicy = New-NonSCPolicy -DisplayName 'Src Only' -Product 'Intune' -PrimaryGroup 'Config' -PolicyDataProps @{ a = 1 }
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

    It '100% when all items match' {
        $srcPolicy = New-NonSCPolicy -DisplayName 'Policy A' -Product 'Intune' -PrimaryGroup 'Config' -PolicyTypeId 5 -PolicyDataProps @{ a = 1 }
        $dstPolicy = New-NonSCPolicy -DisplayName 'Policy A' -Product 'Intune' -PrimaryGroup 'Config' -PolicyTypeId 5 -PolicyDataProps @{ a = 1 }
        $data = New-ComparisonData -SourcePolicies @($srcPolicy) -DestPolicies @($dstPolicy)

        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $model.AlignmentScore | Should -Be 100
    }

    It '0% when no items match (all conflicting or one-sided)' {
        $srcPolicy = New-NonSCPolicy -DisplayName 'Policy A' -Product 'Intune' -PrimaryGroup 'Config' -PolicyTypeId 5 -PolicyDataProps @{ a = 1 }
        $dstPolicy = New-NonSCPolicy -DisplayName 'Policy B' -Product 'Intune' -PrimaryGroup 'Config' -PolicyTypeId 5 -PolicyDataProps @{ b = 2 }
        $data = New-ComparisonData -SourcePolicies @($srcPolicy) -DestPolicies @($dstPolicy)

        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $model.AlignmentScore | Should -Be 0
    }

    It 'calculates correct percentage for mixed results' {
        # 1 matched + 1 source-only = 50%
        $matched1 = New-NonSCPolicy -DisplayName 'Matched' -Product 'Intune' -PrimaryGroup 'Config' -PolicyTypeId 5 -PolicyDataProps @{ a = 1 }
        $matched2 = New-NonSCPolicy -DisplayName 'Matched' -Product 'Intune' -PrimaryGroup 'Config' -PolicyTypeId 5 -PolicyDataProps @{ a = 1 }
        $srcOnly = New-NonSCPolicy -DisplayName 'SrcOnly' -Product 'Intune' -PrimaryGroup 'Config' -PolicyTypeId 5 -PolicyDataProps @{ b = 2 }

        $data = New-ComparisonData -SourcePolicies @($matched1, $srcOnly) -DestPolicies @($matched2)

        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $model.AlignmentScore | Should -Be 50
    }

    It 'manual review items are excluded from alignment score' {
        # SC policy matched + unmatched admin template in same area (manual review)
        $scSrc = New-SCPolicy -DisplayName 'SC A' -Product 'Intune' -PrimaryGroup 'Endpoint Security' -SettingDefinitions @(
            (New-SettingDefinition -SettingDefinitionId 'setting_1' -Value 'v1')
        )
        $scDst = New-SCPolicy -DisplayName 'SC B' -Product 'Intune' -PrimaryGroup 'Endpoint Security' -SettingDefinitions @(
            (New-SettingDefinition -SettingDefinitionId 'setting_1' -Value 'v1')
        )
        $adminSrc = New-NonSCPolicy -DisplayName 'Admin Unmatched' -Product 'Intune' -PrimaryGroup 'Endpoint Security' -PolicyTypeId 5 -PolicyDataProps @{ x = 1 }

        $data = New-ComparisonData -SourcePolicies @($scSrc, $adminSrc) -DestPolicies @($scDst)

        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        # 1 matched SC setting, admin template goes to manual review (excluded from score)
        $model.AlignmentScore | Should -Be 100
    }
}

# ---------------------------------------------------------------------------
# Describe: Product-level counters
# ---------------------------------------------------------------------------
Describe 'ConvertTo-InforcerComparisonModel - Product counters' {

    It 'each product has its own Counters' {
        $src1 = New-NonSCPolicy -DisplayName 'P1' -Product 'Intune' -PrimaryGroup 'Config' -PolicyTypeId 5 -PolicyDataProps @{ a = 1 }
        $dst1 = New-NonSCPolicy -DisplayName 'P1' -Product 'Intune' -PrimaryGroup 'Config' -PolicyTypeId 5 -PolicyDataProps @{ a = 1 }
        $src2 = New-NonSCPolicy -DisplayName 'P2' -Product 'Entra' -PrimaryGroup 'Settings' -PolicyTypeId 3 -PolicyDataProps @{ b = 2 }

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
        $srcPolicy = New-NonSCPolicy -DisplayName 'WithAssign' -Product 'Intune' -PrimaryGroup 'Config' -PolicyTypeId 5 -PolicyDataProps @{ a = 1 } -Assignments $assignments
        $dstPolicy = New-NonSCPolicy -DisplayName 'WithAssign' -Product 'Intune' -PrimaryGroup 'Config' -PolicyTypeId 5 -PolicyDataProps @{ a = 1 } -Assignments $assignments
        $data = New-ComparisonData -SourcePolicies @($srcPolicy) -DestPolicies @($dstPolicy) -IncludingAssignments $true

        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $model.IncludingAssignments | Should -BeTrue
        $row = $model.Products['Intune'].Categories.Values | ForEach-Object { $_.ComparisonRows } | Select-Object -First 1
        $row.Keys -contains 'SourceAssignment' | Should -BeTrue
    }

    It 'omits assignment fields when IncludingAssignments is false' {
        $srcPolicy = New-NonSCPolicy -DisplayName 'NoAssign' -Product 'Intune' -PrimaryGroup 'Config' -PolicyTypeId 5 -PolicyDataProps @{ a = 1 }
        $dstPolicy = New-NonSCPolicy -DisplayName 'NoAssign' -Product 'Intune' -PrimaryGroup 'Config' -PolicyTypeId 5 -PolicyDataProps @{ a = 1 }
        $data = New-ComparisonData -SourcePolicies @($srcPolicy) -DestPolicies @($dstPolicy) -IncludingAssignments $false

        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $model.IncludingAssignments | Should -BeFalse
    }
}

# ---------------------------------------------------------------------------
# Describe: Mixed SC and non-SC policies
# ---------------------------------------------------------------------------
Describe 'ConvertTo-InforcerComparisonModel - Mixed policy types' {

    It 'handles both SC and non-SC policies in the same comparison' {
        $scSrc = New-SCPolicy -DisplayName 'SC Policy' -Product 'Intune' -PrimaryGroup 'Endpoint Security' -SettingDefinitions @(
            (New-SettingDefinition -SettingDefinitionId 'sc_setting_1' -Value 'enabled')
        )
        $scDst = New-SCPolicy -DisplayName 'SC Policy Dest' -Product 'Intune' -PrimaryGroup 'Endpoint Security' -SettingDefinitions @(
            (New-SettingDefinition -SettingDefinitionId 'sc_setting_1' -Value 'enabled')
        )
        $nonScSrc = New-NonSCPolicy -DisplayName 'Admin T' -Product 'Exchange' -PrimaryGroup 'Transport' -PolicyTypeId 5 -PolicyDataProps @{ rule = 'block' }
        $nonScDst = New-NonSCPolicy -DisplayName 'Admin T' -Product 'Exchange' -PrimaryGroup 'Transport' -PolicyTypeId 5 -PolicyDataProps @{ rule = 'block' }

        $data = New-ComparisonData -SourcePolicies @($scSrc, $nonScSrc) -DestPolicies @($scDst, $nonScDst)

        $model = InModuleScope InforcerCommunity -Parameters @{ D = $data } {
            ConvertTo-InforcerComparisonModel -ComparisonData $D
        }
        $model.Counters.Matched | Should -Be 2
        $model.TotalItems | Should -Be 2
    }
}
