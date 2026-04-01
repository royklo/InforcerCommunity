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
                                [PSCustomObject]@{ Target = 'All Devices'; Type = 'All Devices'; Filter = ''; FilterMode = '' }
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
                                    [PSCustomObject]@{ Target = 'aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb'; Type = 'Group (Include)'; Filter = ''; FilterMode = 'Include' }
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
                                    [PSCustomObject]@{ Target = 'cccccccc-1111-2222-3333-dddddddddddd'; Type = 'Group (Include)'; Filter = 'filter-id-1'; FilterMode = 'Include' }
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
                                    [PSCustomObject]@{ Target = 'All Users'; Type = 'All Users'; Filter = ''; FilterMode = '' }
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

    It 'has toolbar JavaScript for theme toggle and empty field filter' {
        $script:HtmlOutput | Should -Match '<script'
        $script:HtmlOutput | Should -Match 'toggleTheme'
        $script:HtmlOutput | Should -Match 'toggleEmpty'
    }

    It 'contains TOC with details elements' {
        $script:HtmlOutput | Should -Match 'toc-section'
        $script:HtmlOutput | Should -Match '<details'
    }

    It 'TOC has collapsible product entries, content product sections are collapsed by default' {
        # TOC contains per-product details elements
        $script:HtmlOutput | Should -Match 'toc-l1'
        # Product sections do not have open attribute
        $productOpen = ([regex]::Matches($script:HtmlOutput, '<details class="product-section"[^>]*open')).Count
        $productOpen | Should -Be 0
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
        $script:HtmlOutput | Should -Match '<th>Target</th>'
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

# ---------------------------------------------------------------------------
# Describe: ConvertTo-InforcerMarkdown
# ---------------------------------------------------------------------------
Describe 'ConvertTo-InforcerMarkdown' -Tag 'Markdown' {
    BeforeAll {
        # Markdown-specific DocModel with fixed date and known values for all assertions
        $pipeValueSetting = [PSCustomObject]@{ Name = 'Pipe Setting'; Value = 'value|with|pipes'; Indent = 0; IsConfigured = $true }
        $nullValueSetting = [PSCustomObject]@{ Name = 'Null Setting';  Value = $null;            Indent = 0; IsConfigured = $false }
        $childSetting     = [PSCustomObject]@{ Name = 'Child Setting'; Value = 'child value';     Indent = 1; IsConfigured = $true }
        $assignmentRow    = [PSCustomObject]@{ Target = 'group-guid-1234'; Type = 'Group (Include)'; Filter = 'filter-guid-abcd'; FilterMode = 'Include' }
        $plainSetting     = [PSCustomObject]@{ Name = 'Plain Setting'; Value = 'plain value';     Indent = 0; IsConfigured = $true }

        $script:MdTestDocModel = @{
            TenantName   = 'Test Tenant'
            TenantId     = 12345
            GeneratedAt  = [datetime]'2026-01-15 10:30:00'
            BaselineName = 'TestBaseline'
            Products     = [ordered]@{
                'Intune' = @{
                    Categories = [ordered]@{
                        'Device Configuration' = [System.Collections.Generic.List[object]]@(
                            @{
                                Basics = @{
                                    Name        = 'Windows Security Baseline'
                                    Description = 'Security baseline for Windows devices'
                                    ProfileType = 'Settings Catalog'
                                    Platform    = 'windows10'
                                    Created     = '2026-01-01T00:00:00Z'
                                    Modified    = '2026-01-10T12:00:00Z'
                                    ScopeTags   = 'Default'
                                }
                                Settings    = @($pipeValueSetting, $childSetting, $nullValueSetting)
                                Assignments = @()
                            },
                            @{
                                Basics = @{
                                    Name        = 'Compliance Policy 1'
                                    Description = ''
                                    ProfileType = 'Compliance'
                                    Platform    = ''
                                    Created     = '2026-01-02T00:00:00Z'
                                    Modified    = '2026-01-11T12:00:00Z'
                                    ScopeTags   = ''
                                }
                                Settings    = @()
                                Assignments = @($assignmentRow)
                            }
                        )
                    }
                }
                'Entra' = @{
                    Categories = [ordered]@{
                        'Conditional Access' = [System.Collections.Generic.List[object]]@(
                            @{
                                Basics = @{
                                    Name        = 'MFA Required Policy'
                                    Description = 'Requires MFA for all users'
                                    ProfileType = 'Conditional Access'
                                    Platform    = ''
                                    Created     = '2026-01-03T00:00:00Z'
                                    Modified    = '2026-01-12T12:00:00Z'
                                    ScopeTags   = ''
                                }
                                Settings    = @($plainSetting)
                                Assignments = @()
                            }
                        )
                    }
                }
            }
        }

        $script:MarkdownOutput = InModuleScope InforcerCommunity -Parameters @{ DocModel = $script:MdTestDocModel } {
            ConvertTo-InforcerMarkdown -DocModel $DocModel
        }
    }

    It 'returns a non-empty string' {
        $script:MarkdownOutput | Should -Not -BeNullOrEmpty
        $script:MarkdownOutput | Should -BeOfType [string]
    }

    It 'starts with tenant documentation header' {
        $script:MarkdownOutput | Should -Match '# Tenant Documentation: Test Tenant'
    }

    It 'contains generation timestamp' {
        $script:MarkdownOutput | Should -Match 'Generated: 2026-01-15'
    }

    It 'contains baseline name' {
        $script:MarkdownOutput | Should -Match 'Baseline: TestBaseline'
    }

    It 'contains TOC with product anchor links' {
        $script:MarkdownOutput | Should -Match '\- \[Intune\]\(#intune\)'
    }

    It 'contains TOC with category sub-items' {
        $script:MarkdownOutput | Should -Match '  - \[Device Configuration\]'
    }

    It 'contains product level-2 headings' {
        $script:MarkdownOutput | Should -Match '## Intune'
        $script:MarkdownOutput | Should -Match '## Entra'
    }

    It 'contains category level-3 headings' {
        $script:MarkdownOutput | Should -Match '### Device Configuration'
        $script:MarkdownOutput | Should -Match '### Conditional Access'
    }

    It 'contains policy level-4 headings' {
        $script:MarkdownOutput | Should -Match '#### Windows Security Baseline'
        $script:MarkdownOutput | Should -Match '#### Compliance Policy 1'
        $script:MarkdownOutput | Should -Match '#### MFA Required Policy'
    }

    It 'renders basics as a GFM pipe-delimited table' {
        $script:MarkdownOutput | Should -Match '\| Property \| Value \|'
    }

    It 'renders settings as a GFM pipe-delimited table' {
        $script:MarkdownOutput | Should -Match '\| Setting \| Value \|'
    }

    It 'escapes pipe characters in setting values' {
        # The test value 'value|with|pipes' should appear as 'value\|with\|pipes'
        $script:MarkdownOutput | Should -Match 'value\\|with\\|pipes'
    }

    It 'shows em dash for null or empty values' {
        # Em dash U+2014 - use a variable so -Match receives the actual character
        $emDash = [char]0x2014
        $script:MarkdownOutput | Should -Match ([regex]::Escape($emDash))
    }

    It 'indents child settings with arrow marker' {
        # Child setting with Indent=1 should have arrow prefix (U+21B3)
        $script:MarkdownOutput | Should -Match ([regex]::Escape([char]0x21B3))
    }

    It 'renders assignments table with correct headers' {
        $script:MarkdownOutput | Should -Match '\| Target \| Type \| Filter \| Filter Mode \|'
    }

    It 'skips settings table when policy has no settings' {
        # For 'Compliance Policy 1' which has 0 settings, verify no | Setting | Value | follows its heading
        $lines = $script:MarkdownOutput -split "`n"
        $policyIdx = ($lines | Select-String -Pattern '#### Compliance Policy 1').LineNumber - 1
        $nextPolicyMatch = $lines | Select-String -Pattern '####' | Where-Object { $_.LineNumber - 1 -gt $policyIdx } | Select-Object -First 1
        $nextPolicyIdx = if ($null -ne $nextPolicyMatch) { $nextPolicyMatch.LineNumber - 1 } else { $lines.Count }
        $sectionLines = $lines[$policyIdx..($nextPolicyIdx - 1)] -join "`n"
        $sectionLines | Should -Not -Match '\| Setting \| Value \|'
    }
}
