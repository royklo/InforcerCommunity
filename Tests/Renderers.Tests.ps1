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

# ---------------------------------------------------------------------------
# Describe: ConvertTo-InforcerHtml
# ---------------------------------------------------------------------------
Describe 'ConvertTo-InforcerHtml' -Tag 'Html' {

    BeforeAll {
        # HTML-specific DocModel with fixed date for timestamp assertions
        $script:HtmlTestDocModel = @{
            TenantName   = 'Test Tenant'
            TenantId     = 99999
            GeneratedAt  = [datetime]::new(2026, 1, 15, 10, 30, 0, [System.DateTimeKind]::Utc)
            BaselineName = 'Test Baseline'
            Products     = [ordered]@{
                'Intune' = @{
                    Categories = [ordered]@{
                        'Compliance' = [System.Collections.Generic.List[object]]@(
                            @{
                                Basics = @{
                                    Name        = 'Windows Compliance Policy'
                                    Description = 'Requires BitLocker'
                                    ProfileType = 'deviceCompliancePolicy'
                                    Platform    = 'windows10AndLater'
                                    Created     = '2025-06-01T00:00:00Z'
                                    Modified    = '2025-12-01T00:00:00Z'
                                    ScopeTags   = 'Production'
                                }
                                Settings    = @(
                                    [PSCustomObject]@{ Name = 'BitLocker Required'; Value = 'True';  Indent = 0; IsConfigured = $true }
                                    [PSCustomObject]@{ Name = 'Storage Encryption';  Value = 'True';  Indent = 1; IsConfigured = $true }
                                    [PSCustomObject]@{ Name = 'Firewall Required';   Value = $null;   Indent = 0; IsConfigured = $true }
                                )
                                Assignments = @(
                                    [PSCustomObject]@{ Group = 'aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb'; Filter = ''; FilterMode = 'include'; Type = 'groupAssignmentTarget' }
                                )
                            }
                        )
                        'Configuration' = [System.Collections.Generic.List[object]]@(
                            @{
                                Basics = @{
                                    Name        = 'Windows Defender Config'
                                    Description = 'AV settings'
                                    ProfileType = 'deviceConfiguration'
                                    Platform    = 'windows10AndLater'
                                    Created     = '2025-05-01T00:00:00Z'
                                    Modified    = '2025-10-01T00:00:00Z'
                                    ScopeTags   = ''
                                }
                                Settings    = @(
                                    [PSCustomObject]@{ Name = 'Real-time Protection'; Value = '';     Indent = 0; IsConfigured = $true }
                                    [PSCustomObject]@{ Name = 'Cloud Protection';     Value = 'High'; Indent = 0; IsConfigured = $true }
                                    [PSCustomObject]@{ Name = 'Block at First Sight'; Value = 'True'; Indent = 1; IsConfigured = $true }
                                )
                                Assignments = @(
                                    [PSCustomObject]@{ Group = 'cccccccc-1111-2222-3333-dddddddddddd'; Filter = 'filter-id-1'; FilterMode = 'include'; Type = 'groupAssignmentTarget' }
                                )
                            }
                        )
                    }
                }
                'Entra' = @{
                    Categories = [ordered]@{
                        'Conditional Access / Policies' = [System.Collections.Generic.List[object]]@(
                            @{
                                Basics = @{
                                    Name        = 'Block Legacy Auth'
                                    Description = 'Blocks legacy authentication protocols'
                                    ProfileType = 'conditionalAccessPolicy'
                                    Platform    = ''
                                    Created     = '2025-01-01T00:00:00Z'
                                    Modified    = '2025-09-01T00:00:00Z'
                                    ScopeTags   = ''
                                }
                                Settings    = @()
                                Assignments = @(
                                    [PSCustomObject]@{ Group = 'eeeeeeee-1111-2222-3333-ffffffffffff'; Filter = ''; FilterMode = ''; Type = 'allLicensedUsersAssignmentTarget' }
                                )
                            }
                        )
                    }
                }
            }
        }

        $script:HtmlOutput = InModuleScope InforcerCommunity -Parameters @{ DocModel = $script:HtmlTestDocModel } {
            ConvertTo-InforcerHtml -DocModel $DocModel
        }
    }

    It 'produces valid HTML document structure' {
        $script:HtmlOutput | Should -Match '(?s)^<!DOCTYPE html>'
        $script:HtmlOutput | Should -Match '</html>\s*$'
    }

    It 'contains embedded CSS style block' {
        $script:HtmlOutput | Should -Match '<style>'
        $script:HtmlOutput | Should -Match '</style>'
    }

    It 'has no external resource references' {
        $script:HtmlOutput | Should -Not -Match 'href="http'
        $script:HtmlOutput | Should -Not -Match 'src="http'
    }

    It 'has no JavaScript' {
        $script:HtmlOutput | Should -Not -Match '<script'
    }

    It 'contains TOC with details elements' {
        $script:HtmlOutput | Should -Match '<nav'
        $script:HtmlOutput | Should -Match '<details'
    }

    It 'TOC is collapsed by default - no open attributes on any details element' {
        $allDetails  = ([regex]::Matches($script:HtmlOutput, '<details')).Count
        $openDetails = ([regex]::Matches($script:HtmlOutput, '<details[^>]*open')).Count
        $allDetails  | Should -BeGreaterThan 0
        $openDetails | Should -Be 0
    }

    It 'contains policy details/summary elements with policy-section class' {
        $script:HtmlOutput | Should -Match 'class="policy-section"'
    }

    It 'shows setting count badge in policy summary' {
        $script:HtmlOutput | Should -Match '<span class="badge">\d+ settings</span>'
    }

    It 'renders basics table with Property/Value headers' {
        $script:HtmlOutput | Should -Match '<th>Property</th>'
        $script:HtmlOutput | Should -Match '<th>Value</th>'
    }

    It 'renders settings table with Setting/Value headers' {
        $script:HtmlOutput | Should -Match '<th>Setting</th>'
    }

    It 'applies padding-left for settings with Indent greater than 0' {
        # Indent=1 should produce padding-left: 1.5rem
        $script:HtmlOutput | Should -Match 'padding-left:\s*1\.5rem'
    }

    It 'uses em dash for null or empty setting values' {
        $script:HtmlOutput | Should -Match '(&mdash;|class="muted")'
    }

    It 'contains prefers-color-scheme media query in CSS' {
        $script:HtmlOutput | Should -Match 'prefers-color-scheme'
    }

    It 'contains system font stack in CSS' {
        $script:HtmlOutput | Should -Match '-apple-system'
    }

    It 'shows tenant name in h1 header element' {
        $script:HtmlOutput | Should -Match '<h1[^>]*>.*Test Tenant.*</h1>'
    }

    It 'shows generation timestamp in output' {
        $script:HtmlOutput | Should -Match '2026-01-15'
    }

    It 'shows tenant info in footer section' {
        $script:HtmlOutput | Should -Match 'class="footer"'
        $script:HtmlOutput | Should -Match 'Test Tenant'
    }

    It 'renders assignments table when assignments exist' {
        $script:HtmlOutput | Should -Match '<th>Group</th>'
    }

    It 'uses HtmlEncode for XSS prevention' {
        $fnDef = InModuleScope InforcerCommunity {
            (Get-Command ConvertTo-InforcerHtml -ErrorAction Stop).ScriptBlock.ToString()
        }
        $fnDef | Should -Match 'HtmlEncode'
    }

    It 'returns a non-empty string longer than 1000 characters' {
        $script:HtmlOutput | Should -Not -BeNullOrEmpty
        $script:HtmlOutput.Length | Should -BeGreaterThan 1000
    }

    It 'handles DocModel with no products without throwing' {
        $emptyModel = @{
            TenantName   = 'Empty Tenant'
            TenantId     = 0
            GeneratedAt  = [datetime]::UtcNow
            BaselineName = ''
            Products     = [ordered]@{}
        }
        $result = InModuleScope InforcerCommunity -Parameters @{ M = $emptyModel } {
            ConvertTo-InforcerHtml -DocModel $M
        }
        $result | Should -Match '<!DOCTYPE html>'
        $result | Should -Match 'Empty Tenant'
    }
}
