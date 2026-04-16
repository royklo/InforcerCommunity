# SettingsCatalog.Tests.ps1
# Pester 5.x tests for the Settings Catalog resolution pipeline.
# Run from repo root: Invoke-Pester ./Tests/SettingsCatalog.Tests.ps1

$ErrorActionPreference = 'Stop'

BeforeAll {
    # Remove any cached module before loading fresh
    Remove-Module -Name 'InforcerCommunity' -ErrorAction SilentlyContinue
    $here = $PSScriptRoot
    $manifestPath = Join-Path $here '..' 'module' 'InforcerCommunity.psd1'
    $manifestPath = [System.IO.Path]::GetFullPath($manifestPath)
    Import-Module $manifestPath -Force -ErrorAction Stop
}

# ---------------------------------------------------------------------------
# Describe: Import-InforcerSettingsCatalog
# ---------------------------------------------------------------------------
Describe 'Import-InforcerSettingsCatalog' {

    BeforeEach {
        # Reset catalog before each test
        InModuleScope InforcerCommunity { $script:InforcerSettingsCatalog = $null }
    }

    It 'loads settings.json and sets $script:InforcerSettingsCatalog as a hashtable keyed by id' {
        # Create a minimal temp settings.json
        $tmpFile = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.json'
        @'
[
  {
    "@odata.type": "#microsoft.graph.deviceManagementConfigurationChoiceSettingDefinition",
    "id": "test_setting_id",
    "displayName": "Test Setting",
    "description": "A test setting",
    "options": [
      { "itemId": "test_setting_id_0", "displayName": "Disabled" },
      { "itemId": "test_setting_id_1", "displayName": "Enabled"  }
    ]
  }
]
'@ | Set-Content -Path $tmpFile -Encoding UTF8

        InModuleScope InforcerCommunity -Parameters @{ TmpFile = $tmpFile } {
            Import-InforcerSettingsCatalog -Path $TmpFile
        }
        $catalog = InModuleScope InforcerCommunity { $script:InforcerSettingsCatalog }
        $catalog | Should -Not -BeNullOrEmpty
        $catalog | Should -BeOfType [hashtable]
        $catalog.ContainsKey('test_setting_id') | Should -BeTrue
        $catalog['test_setting_id'].DisplayName | Should -Be 'Test Setting'
        Remove-Item $tmpFile -ErrorAction SilentlyContinue
    }

    It 'does NOT reload when already cached (guard clause)' {
        # Pre-set the catalog to a sentinel value
        InModuleScope InforcerCommunity { $script:InforcerSettingsCatalog = @{ sentinel = @{ DisplayName = 'pre-loaded' } } }
        # Call without -Force should NOT overwrite
        $tmpFile = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.json'
        '[]' | Set-Content -Path $tmpFile -Encoding UTF8
        InModuleScope InforcerCommunity -Parameters @{ TmpFile = $tmpFile } {
            Import-InforcerSettingsCatalog -Path $TmpFile
        }
        $catalog = InModuleScope InforcerCommunity { $script:InforcerSettingsCatalog }
        $catalog.ContainsKey('sentinel') | Should -BeTrue
        Remove-Item $tmpFile -ErrorAction SilentlyContinue
    }

    It 'reloads when -Force is specified' {
        InModuleScope InforcerCommunity { $script:InforcerSettingsCatalog = @{ sentinel = @{ DisplayName = 'pre-loaded' } } }
        $tmpFile = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.json'
        @'
[{ "id": "new_id", "displayName": "New Entry", "description": "", "options": [] }]
'@ | Set-Content -Path $tmpFile -Encoding UTF8
        InModuleScope InforcerCommunity -Parameters @{ TmpFile = $tmpFile } {
            Import-InforcerSettingsCatalog -Path $TmpFile -Force
        }
        $catalog = InModuleScope InforcerCommunity { $script:InforcerSettingsCatalog }
        $catalog.ContainsKey('sentinel') | Should -BeFalse
        $catalog.ContainsKey('new_id') | Should -BeTrue
        Remove-Item $tmpFile -ErrorAction SilentlyContinue
    }

    It 'returns without loading catalog when explicit path does not exist' {
        InModuleScope InforcerCommunity {
            $script:InforcerSettingsCatalog = $null
            Import-InforcerSettingsCatalog -Path 'C:\DoesNotExist\settings.json'
            $script:InforcerSettingsCatalog | Should -BeNullOrEmpty
        }
    }
}

# ---------------------------------------------------------------------------
# Describe: Resolve-InforcerSettingName
# ---------------------------------------------------------------------------
Describe 'Resolve-InforcerSettingName' {

    BeforeAll {
        # Inject a small catalog into the module scope for all tests in this block
        InModuleScope InforcerCommunity {
            $script:InforcerSettingsCatalog = @{
                'sirisettings_enabled' = @{
                    DisplayName = 'Enabled'
                    Description = 'Enables or disables Siri'
                    Options     = @{
                        'sirisettings_enabled_false' = 'Disabled'
                        'sirisettings_enabled_true'  = 'Enabled'
                    }
                }
            }
        }
    }

    AfterAll {
        InModuleScope InforcerCommunity { $script:InforcerSettingsCatalog = $null }
    }

    It 'returns displayName for a known settingDefinitionId' {
        $result = InModuleScope InforcerCommunity {
            Resolve-InforcerSettingName -SettingDefinitionId 'sirisettings_enabled'
        }
        $result.DisplayName | Should -Be 'Enabled'
    }

    It 'returns the option label for a known ID and ChoiceValue' {
        $result = InModuleScope InforcerCommunity {
            Resolve-InforcerSettingName -SettingDefinitionId 'sirisettings_enabled' -ChoiceValue 'sirisettings_enabled_false'
        }
        $result.ValueLabel | Should -Be 'Disabled'
    }

    It 'returns friendly-cased ID as DisplayName when ID is unknown' {
        $result = InModuleScope InforcerCommunity {
            Resolve-InforcerSettingName -SettingDefinitionId 'unknown_id_xyz'
        }
        # ConvertTo-FriendlySettingName converts camelCase/snake_case to title case
        $result.DisplayName | Should -Be 'Unknown Id Xyz'
    }

    It 'returns empty DisplayName for null/empty ID' {
        $result = InModuleScope InforcerCommunity {
            Resolve-InforcerSettingName -SettingDefinitionId ''
        }
        $result.DisplayName | Should -Be ''
    }
}

# ---------------------------------------------------------------------------
# Describe: Disconnect-Inforcer clears catalog cache
# ---------------------------------------------------------------------------
Describe 'Disconnect-Inforcer clears InforcerSettingsCatalog' {

    It 'sets $script:InforcerSettingsCatalog to $null on disconnect' {
        # Pre-load a catalog
        InModuleScope InforcerCommunity {
            $script:InforcerSettingsCatalog = @{ 'some_id' = @{ DisplayName = 'Something' } }
            # Also need a session to trigger disconnect
            $script:InforcerSession = @{ ApiKey = 'test-key'; BaseUrl = 'https://example.com' }
        }
        Disconnect-Inforcer -Confirm:$false | Out-Null
        $catalog = InModuleScope InforcerCommunity { $script:InforcerSettingsCatalog }
        $catalog | Should -BeNullOrEmpty
    }
}

# ---------------------------------------------------------------------------
# Describe: ConvertTo-InforcerSettingRows
# ---------------------------------------------------------------------------
Describe 'ConvertTo-InforcerSettingRows' {

    BeforeAll {
        InModuleScope InforcerCommunity {
            $script:InforcerSettingsCatalog = @{
                'test_choice_id' = @{
                    DisplayName = 'My Choice Setting'
                    Description = ''
                    Options     = @{
                        'test_choice_id_0' = 'Option Zero'
                        'test_choice_id_1' = 'Option One'
                    }
                }
                'test_simple_id' = @{
                    DisplayName = 'My Simple Setting'
                    Description = ''
                    Options     = @{}
                }
                'test_collection_id' = @{
                    DisplayName = 'My Collection Setting'
                    Description = ''
                    Options     = @{}
                }
                'test_group_id' = @{
                    DisplayName = 'My Group Setting'
                    Description = ''
                    Options     = @{}
                }
                'test_child_id' = @{
                    DisplayName = 'Child Setting'
                    Description = ''
                    Options     = @{}
                }
                'test_choice_coll_id' = @{
                    DisplayName = 'My Choice Collection'
                    Description = ''
                    Options     = @{
                        'test_choice_coll_id_a' = 'Label A'
                        'test_choice_coll_id_b' = 'Label B'
                    }
                }
            }
        }
    }

    AfterAll {
        InModuleScope InforcerCommunity { $script:InforcerSettingsCatalog = $null }
    }

    It 'ChoiceSettingInstance produces a row with resolved DisplayName and choice label' {
        $rows = InModuleScope InforcerCommunity {
            $instance = [PSCustomObject]@{
                '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                settingDefinitionId = 'test_choice_id'
                choiceSettingValue  = [PSCustomObject]@{
                    value    = 'test_choice_id_1'
                    children = @()
                }
            }
            ConvertTo-InforcerSettingRows -SettingInstance $instance
        }
        $rows.Count | Should -Be 1
        $rows[0].Name | Should -Be 'My Choice Setting'
        $rows[0].Value | Should -Be 'Option One'
        $rows[0].Indent | Should -Be 0
        $rows[0].IsConfigured | Should -BeTrue
    }

    It 'ChoiceSettingInstance with children produces parent at Indent=0 and child at Indent=1' {
        $rows = InModuleScope InforcerCommunity {
            $childInstance = [PSCustomObject]@{
                '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                settingDefinitionId = 'test_child_id'
                choiceSettingValue  = [PSCustomObject]@{
                    value    = ''
                    children = @()
                }
            }
            $instance = [PSCustomObject]@{
                '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                settingDefinitionId = 'test_choice_id'
                choiceSettingValue  = [PSCustomObject]@{
                    value    = 'test_choice_id_0'
                    children = @($childInstance)
                }
            }
            ConvertTo-InforcerSettingRows -SettingInstance $instance
        }
        $rows.Count | Should -Be 2
        $rows[0].Indent | Should -Be 0
        $rows[1].Indent | Should -Be 1
        $rows[1].Name | Should -Be 'Child Setting'
    }

    It 'SimpleSettingInstance produces a row with resolved DisplayName and literal value' {
        $rows = InModuleScope InforcerCommunity {
            $instance = [PSCustomObject]@{
                '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance'
                settingDefinitionId = 'test_simple_id'
                simpleSettingValue  = [PSCustomObject]@{ value = '42' }
            }
            ConvertTo-InforcerSettingRows -SettingInstance $instance
        }
        $rows.Count | Should -Be 1
        $rows[0].Name | Should -Be 'My Simple Setting'
        $rows[0].Value | Should -Be '42'
        $rows[0].Indent | Should -Be 0
        $rows[0].IsConfigured | Should -BeTrue
    }

    It 'SimpleSettingCollectionInstance produces a row with comma-joined values' {
        $rows = InModuleScope InforcerCommunity {
            $instance = [PSCustomObject]@{
                '@odata.type'                   = '#microsoft.graph.deviceManagementConfigurationSimpleSettingCollectionInstance'
                settingDefinitionId             = 'test_collection_id'
                simpleSettingCollectionValue    = @(
                    [PSCustomObject]@{ value = 'apple' }
                    [PSCustomObject]@{ value = 'banana' }
                )
            }
            ConvertTo-InforcerSettingRows -SettingInstance $instance
        }
        $rows.Count | Should -Be 1
        $rows[0].Value | Should -Be 'apple, banana'
    }

    It 'GroupSettingCollectionInstance produces a header row at Indent=0 and child rows at Indent=1' {
        $rows = InModuleScope InforcerCommunity {
            $childInstance = [PSCustomObject]@{
                '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance'
                settingDefinitionId = 'test_child_id'
                simpleSettingValue  = [PSCustomObject]@{ value = 'child-value' }
            }
            $instance = [PSCustomObject]@{
                '@odata.type'                    = '#microsoft.graph.deviceManagementConfigurationGroupSettingCollectionInstance'
                settingDefinitionId              = 'test_group_id'
                groupSettingCollectionValue      = @(
                    [PSCustomObject]@{ children = @($childInstance) }
                )
            }
            ConvertTo-InforcerSettingRows -SettingInstance $instance
        }
        $rows.Count | Should -Be 2
        $rows[0].Name | Should -Be 'My Group Setting'
        $rows[0].Value | Should -Be ''
        $rows[0].Indent | Should -Be 0
        $rows[0].IsConfigured | Should -BeFalse
        $rows[1].Indent | Should -Be 1
        $rows[1].Name | Should -Be 'Child Setting'
    }

    It 'GroupSettingCollectionInstance with nested group produces Indent 0, 1, 2' {
        $rows = InModuleScope InforcerCommunity {
            $deepChild = [PSCustomObject]@{
                '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance'
                settingDefinitionId = 'test_child_id'
                simpleSettingValue  = [PSCustomObject]@{ value = 'deep' }
            }
            $nestedGroup = [PSCustomObject]@{
                '@odata.type'               = '#microsoft.graph.deviceManagementConfigurationGroupSettingCollectionInstance'
                settingDefinitionId         = 'test_group_id'
                groupSettingCollectionValue = @(
                    [PSCustomObject]@{ children = @($deepChild) }
                )
            }
            $instance = [PSCustomObject]@{
                '@odata.type'                    = '#microsoft.graph.deviceManagementConfigurationGroupSettingCollectionInstance'
                settingDefinitionId              = 'test_group_id'
                groupSettingCollectionValue      = @(
                    [PSCustomObject]@{ children = @($nestedGroup) }
                )
            }
            ConvertTo-InforcerSettingRows -SettingInstance $instance
        }
        # outer header (0), inner header (1), deep child (2)
        $rows.Count | Should -Be 3
        $rows[0].Indent | Should -Be 0
        $rows[1].Indent | Should -Be 1
        $rows[2].Indent | Should -Be 2
    }

    It 'ChoiceSettingCollectionInstance produces one row per collection element with resolved labels' {
        $rows = InModuleScope InforcerCommunity {
            $instance = [PSCustomObject]@{
                '@odata.type'                     = '#microsoft.graph.deviceManagementConfigurationChoiceSettingCollectionInstance'
                settingDefinitionId               = 'test_choice_coll_id'
                choiceSettingCollectionValue      = @(
                    [PSCustomObject]@{ value = 'test_choice_coll_id_a' }
                    [PSCustomObject]@{ value = 'test_choice_coll_id_b' }
                )
            }
            ConvertTo-InforcerSettingRows -SettingInstance $instance
        }
        $rows.Count | Should -Be 2
        $rows[0].Value | Should -Be 'Label A'
        $rows[1].Value | Should -Be 'Label B'
    }

    It 'Unknown @odata.type produces a warning row with "(unhandled type: ...)" value' {
        $rows = InModuleScope InforcerCommunity {
            $instance = [PSCustomObject]@{
                '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationUnknownInstance'
                settingDefinitionId = 'test_simple_id'
            }
            ConvertTo-InforcerSettingRows -SettingInstance $instance
        }
        $rows.Count | Should -Be 1
        $rows[0].Value | Should -Match 'unhandled type'
        $rows[0].IsConfigured | Should -BeFalse
    }

    It 'Every row has exactly 4 properties: Name, Value, Indent, IsConfigured' {
        $rows = InModuleScope InforcerCommunity {
            $instance = [PSCustomObject]@{
                '@odata.type'       = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                settingDefinitionId = 'test_choice_id'
                choiceSettingValue  = [PSCustomObject]@{
                    value    = 'test_choice_id_0'
                    children = @()
                }
            }
            ConvertTo-InforcerSettingRows -SettingInstance $instance
        }
        $rows[0].PSObject.Properties.Name | Should -Be @('Name', 'Value', 'Indent', 'IsConfigured', 'DefinitionId')
    }
}

# ---------------------------------------------------------------------------
# Describe: ConvertTo-FlatSettingRows
# ---------------------------------------------------------------------------
Describe 'ConvertTo-FlatSettingRows' {

    It 'enumerates policyData properties as Name/Value rows, skipping reserved fields' {
        $rows = InModuleScope InforcerCommunity {
            $policyData = [PSCustomObject]@{
                '@odata.type'     = '#microsoft.graph.something'
                'id'              = 'policy-123'
                'displayName'     = 'My Policy'
                'allowBluetooth'  = 'true'
                'passwordLength'  = '8'
            }
            ConvertTo-FlatSettingRows -PolicyData $policyData
        }
        $names = $rows | ForEach-Object { $_.Name }
        $names | Should -Contain 'Allow Bluetooth'
        $names | Should -Contain 'Password Length'
        $names | Should -Not -Contain '@odata.type'
        $names | Should -Not -Contain 'id'
        $names | Should -Not -Contain 'displayName'
    }

    It 'recurses into nested objects with Indent=1' {
        $rows = InModuleScope InforcerCommunity {
            $nested = [PSCustomObject]@{
                innerProp = 'inner-value'
            }
            $policyData = [PSCustomObject]@{
                'outerSection' = $nested
            }
            ConvertTo-FlatSettingRows -PolicyData $policyData
        }
        # Should have header row for outerSection (Indent=0) and child row (Indent=1)
        $rows.Count | Should -Be 2
        $rows[0].Name | Should -Be 'Outer Section'
        $rows[0].Indent | Should -Be 0
        $rows[1].Name | Should -Be 'Inner Prop'
        $rows[1].Indent | Should -Be 1
    }

    It 'returns empty list for null PolicyData' {
        $rows = InModuleScope InforcerCommunity {
            ConvertTo-FlatSettingRows -PolicyData $null
        }
        $rows.Count | Should -Be 0
    }
}

# ---------------------------------------------------------------------------
# Describe: Integration test (requires real settings.json)
# ---------------------------------------------------------------------------
# Integration tests are conditional on settings.json being present (it is gitignored -- 62.5 MB).
# Resolve at script scope (outside Describe/BeforeAll) so -Skip can reference it at discovery time.
$script:IntegrationSettingsPath = Join-Path ([System.Environment]::GetFolderPath('UserProfile')) '.inforcercommunity' 'data' 'settings.json'
$script:IntegrationSettingsAvailable = Test-Path -LiteralPath $script:IntegrationSettingsPath

Describe 'Integration: Load real settings.json and resolve known ID' {

    It 'loads real settings.json and resolves a known settingDefinitionId' -Skip:(-not $script:IntegrationSettingsAvailable) {
        InModuleScope InforcerCommunity -Parameters @{ SettingsPath = $script:IntegrationSettingsPath } {
            Import-InforcerSettingsCatalog -Path $SettingsPath -Force
        }
        # sirisettings_enabled is the first entry in settings.json
        $result = InModuleScope InforcerCommunity {
            Resolve-InforcerSettingName -SettingDefinitionId 'sirisettings_enabled'
        }
        $result.DisplayName | Should -Not -Be 'sirisettings_enabled'
        $result.DisplayName | Should -Be 'Enabled'
    }

    It 'resolves choice value label from real settings.json' -Skip:(-not $script:IntegrationSettingsAvailable) {
        $result = InModuleScope InforcerCommunity {
            Resolve-InforcerSettingName -SettingDefinitionId 'sirisettings_enabled' -ChoiceValue 'sirisettings_enabled_false'
        }
        $result.ValueLabel | Should -Be 'Disabled'
    }
}
