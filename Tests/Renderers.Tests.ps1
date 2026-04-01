# Renderers.Tests.ps1
# Pester 5.x tests for ConvertTo-InforcerDocJson and ConvertTo-InforcerDocCsv renderer functions.
# Run from repo root: Invoke-Pester ./Tests/Renderers.Tests.ps1

$ErrorActionPreference = 'Stop'

BeforeAll {
    Remove-Module -Name 'InforcerCommunity' -ErrorAction SilentlyContinue
    $here = $PSScriptRoot
    $manifestPath = [System.IO.Path]::GetFullPath((Join-Path $here '..' 'module' 'InforcerCommunity.psd1'))
    Import-Module $manifestPath -Force -ErrorAction Stop

    # Build a minimal test DocModel inline
    # Covers: 2 products, 2 categories, 3 policies (one with no settings, two with settings)
    # Includes: setting with $null Value, setting with empty string Value, settings at different Indent levels

    $script:TestDocModel = @{
        TenantName   = 'Test Tenant'
        TenantId     = 'tenant-001'
        GeneratedAt  = [datetime]'2026-04-01T12:00:00Z'
        BaselineName = 'Standard Baseline'
        Products     = [ordered]@{
            'Intune'  = @{
                Categories = [ordered]@{
                    'Settings' = [System.Collections.Generic.List[object]]@(
                        # Policy 1: 3 settings including null and empty values, varying Indent
                        @{
                            Basics = @{
                                Name        = 'BitLocker Policy'
                                Description = 'Enables BitLocker encryption'
                                ProfileType = 'Settings Catalog'
                                Platform    = 'Windows'
                                Created     = '2025-01-15'
                                Modified    = '2025-03-01'
                                ScopeTags   = ''
                            }
                            Settings = @(
                                [PSCustomObject]@{ Name = 'BitLocker Drive Encryption'; Value = 'Enabled'; Indent = 0; IsConfigured = $true }
                                [PSCustomObject]@{ Name = 'Encryption Method'; Value = $null; Indent = 1; IsConfigured = $false }
                                [PSCustomObject]@{ Name = 'Startup PIN'; Value = ''; Indent = 1; IsConfigured = $false }
                            )
                            Assignments = @(
                                [PSCustomObject]@{ Group = 'group-001'; Filter = ''; FilterMode = ''; Type = 'allDevicesAssignmentTarget' }
                            )
                        }
                        # Policy 2: 2 settings at Indent 0
                        @{
                            Basics = @{
                                Name        = 'Defender Policy'
                                Description = 'Defender antivirus settings'
                                ProfileType = 'Settings Catalog'
                                Platform    = 'Windows'
                                Created     = '2025-02-01'
                                Modified    = '2025-03-15'
                                ScopeTags   = ''
                            }
                            Settings = @(
                                [PSCustomObject]@{ Name = 'Real-time Protection'; Value = 'Enabled'; Indent = 0; IsConfigured = $true }
                                [PSCustomObject]@{ Name = 'Cloud-delivered Protection'; Value = 'Enabled'; Indent = 0; IsConfigured = $true }
                            )
                            Assignments = @()
                        }
                    )
                }
            }
            'Entra' = @{
                Categories = [ordered]@{
                    'Conditional Access / Policies' = [System.Collections.Generic.List[object]]@(
                        # Policy 3: 0 settings (tests empty-settings boundary)
                        @{
                            Basics = @{
                                Name        = 'Require MFA'
                                Description = 'Requires MFA for all users'
                                ProfileType = 'Conditional Access'
                                Platform    = ''
                                Created     = '2025-01-01'
                                Modified    = '2025-01-01'
                                ScopeTags   = ''
                            }
                            Settings    = @()
                            Assignments = @()
                        }
                    )
                }
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Describe: ConvertTo-InforcerDocJson
# ---------------------------------------------------------------------------
Describe 'ConvertTo-InforcerDocJson' -Tag 'Json' {

    It 'Output is valid JSON (ConvertFrom-Json does not throw)' {
        $result = InModuleScope InforcerCommunity -Parameters @{ DocModel = $script:TestDocModel } {
            ConvertTo-InforcerDocJson -DocModel $DocModel
        }
        { $result | ConvertFrom-Json -Depth 100 } | Should -Not -Throw
    }

    It 'Output contains TenantName key' {
        $result = InModuleScope InforcerCommunity -Parameters @{ DocModel = $script:TestDocModel } {
            ConvertTo-InforcerDocJson -DocModel $DocModel
        }
        $parsed = $result | ConvertFrom-Json -Depth 100
        $parsed.TenantName | Should -Be 'Test Tenant'
    }

    It 'Output contains TenantId key' {
        $result = InModuleScope InforcerCommunity -Parameters @{ DocModel = $script:TestDocModel } {
            ConvertTo-InforcerDocJson -DocModel $DocModel
        }
        $parsed = $result | ConvertFrom-Json -Depth 100
        $parsed.TenantId | Should -Be 'tenant-001'
    }

    It 'Output contains GeneratedAt key' {
        $result = InModuleScope InforcerCommunity -Parameters @{ DocModel = $script:TestDocModel } {
            ConvertTo-InforcerDocJson -DocModel $DocModel
        }
        $parsed = $result | ConvertFrom-Json -Depth 100
        $parsed.GeneratedAt | Should -Not -BeNullOrEmpty
    }

    It 'Output contains BaselineName key' {
        $result = InModuleScope InforcerCommunity -Parameters @{ DocModel = $script:TestDocModel } {
            ConvertTo-InforcerDocJson -DocModel $DocModel
        }
        $parsed = $result | ConvertFrom-Json -Depth 100
        $parsed.BaselineName | Should -Be 'Standard Baseline'
    }

    It 'Output contains Products key' {
        $result = InModuleScope InforcerCommunity -Parameters @{ DocModel = $script:TestDocModel } {
            ConvertTo-InforcerDocJson -DocModel $DocModel
        }
        $parsed = $result | ConvertFrom-Json -Depth 100
        $parsed.Products | Should -Not -BeNullOrEmpty
    }

    It 'Products contain nested Categories with policy arrays (JSON-02)' {
        $result = InModuleScope InforcerCommunity -Parameters @{ DocModel = $script:TestDocModel } {
            ConvertTo-InforcerDocJson -DocModel $DocModel
        }
        $parsed = $result | ConvertFrom-Json -Depth 100
        $parsed.Products.Intune.Categories.Settings | Should -Not -BeNullOrEmpty
        $parsed.Products.Intune.Categories.Settings.Count | Should -Be 2
    }

    It 'Null values in DocModel are preserved as null in JSON output (D-12)' {
        $result = InModuleScope InforcerCommunity -Parameters @{ DocModel = $script:TestDocModel } {
            ConvertTo-InforcerDocJson -DocModel $DocModel
        }
        # null should appear as literal null in the JSON string (not as empty string "")
        $result | Should -Match '"Value":\s*null'
    }

    It 'Output is pretty-printed (contains newlines, not single-line)' {
        $result = InModuleScope InforcerCommunity -Parameters @{ DocModel = $script:TestDocModel } {
            ConvertTo-InforcerDocJson -DocModel $DocModel
        }
        $result | Should -Match "`n"
    }

    It 'Output is a string' {
        $result = InModuleScope InforcerCommunity -Parameters @{ DocModel = $script:TestDocModel } {
            ConvertTo-InforcerDocJson -DocModel $DocModel
        }
        $result | Should -BeOfType [string]
    }
}

# ---------------------------------------------------------------------------
# Describe: ConvertTo-InforcerDocCsv
# ---------------------------------------------------------------------------
Describe 'ConvertTo-InforcerDocCsv' -Tag 'Csv' {

    It 'Output is a single string (not string array)' {
        $result = InModuleScope InforcerCommunity -Parameters @{ DocModel = $script:TestDocModel } {
            ConvertTo-InforcerDocCsv -DocModel $DocModel
        }
        $result | Should -BeOfType [string]
        # It's a single string, not multiple
        @($result).Count | Should -Be 1
    }

    It 'Output header row contains exactly the required columns (D-24)' {
        $result = InModuleScope InforcerCommunity -Parameters @{ DocModel = $script:TestDocModel } {
            ConvertTo-InforcerDocCsv -DocModel $DocModel
        }
        $firstLine = ($result -split [Environment]::NewLine)[0]
        $firstLine | Should -Be '"Product","Category","PolicyName","SettingName","Value","Indent","IsConfigured"'
    }

    It 'One row per setting value across all products/categories/policies (CSV-02)' {
        $result = InModuleScope InforcerCommunity -Parameters @{ DocModel = $script:TestDocModel } {
            ConvertTo-InforcerDocCsv -DocModel $DocModel
        }
        # TestDocModel has 3+2+0 = 5 settings rows, plus 1 header = 6 lines
        $lines = $result -split [Environment]::NewLine | Where-Object { $_ -ne '' }
        $lines.Count | Should -Be 6  # 1 header + 5 data rows
    }

    It 'Empty/null values in DocModel produce empty string in CSV (D-11)' {
        $result = InModuleScope InforcerCommunity -Parameters @{ DocModel = $script:TestDocModel } {
            ConvertTo-InforcerDocCsv -DocModel $DocModel
        }
        # null Value row for "Encryption Method" should appear with empty value field ""
        # Find the row for "Encryption Method"
        $lines = $result -split [Environment]::NewLine
        $encMethodRow = $lines | Where-Object { $_ -match '"Encryption Method"' }
        $encMethodRow | Should -Not -BeNullOrEmpty
        $encMethodRow | Should -Match '"Encryption Method","","1"'
    }

    It 'Policies with no settings produce no CSV rows (D-26)' {
        $result = InModuleScope InforcerCommunity -Parameters @{ DocModel = $script:TestDocModel } {
            ConvertTo-InforcerDocCsv -DocModel $DocModel
        }
        # "Require MFA" policy has 0 settings -- should not appear in CSV
        $result | Should -Not -Match '"Require MFA"'
    }

    It 'Product column contains correct product name' {
        $result = InModuleScope InforcerCommunity -Parameters @{ DocModel = $script:TestDocModel } {
            ConvertTo-InforcerDocCsv -DocModel $DocModel
        }
        $result | Should -Match '"Intune"'
        $result | Should -Not -Match '"Entra"'  # Entra has no settings
    }

    It 'Category column contains correct category name' {
        $result = InModuleScope InforcerCommunity -Parameters @{ DocModel = $script:TestDocModel } {
            ConvertTo-InforcerDocCsv -DocModel $DocModel
        }
        $result | Should -Match '"Settings"'
    }

    It 'PolicyName column contains correct policy name' {
        $result = InModuleScope InforcerCommunity -Parameters @{ DocModel = $script:TestDocModel } {
            ConvertTo-InforcerDocCsv -DocModel $DocModel
        }
        $result | Should -Match '"BitLocker Policy"'
        $result | Should -Match '"Defender Policy"'
    }
}
