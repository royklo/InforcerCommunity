# Renderers.Tests.ps1
# Pester 5.x tests for ConvertTo-InforcerHtml and ConvertTo-InforcerMarkdown renderer functions.
# Run from repo root: Invoke-Pester ./Tests/Renderers.Tests.ps1

$ErrorActionPreference = 'Stop'

BeforeAll {
    Remove-Module -Name 'InforcerCommunity' -ErrorAction SilentlyContinue
    $here = $PSScriptRoot
    $manifestPath = [System.IO.Path]::GetFullPath((Join-Path $here '..' 'module' 'InforcerCommunity.psd1'))
    Import-Module $manifestPath -Force -ErrorAction Stop
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

# ---------------------------------------------------------------------------
# Describe: ConvertTo-InforcerComparisonHtml - ENG-03 deprecated badge
# ---------------------------------------------------------------------------
Describe 'ConvertTo-InforcerComparisonHtml - ENG-03 deprecated badge' -Tag 'ENG-03' {

    BeforeAll {
        # Minimal comparison model with one deprecated and one non-deprecated row
        $script:CompModelDepr = @{
            SourceName      = 'Source Tenant'
            DestinationName = 'Dest Tenant'
            Products        = [ordered]@{
                Windows = @{
                    Categories = [ordered]@{
                        'Settings Catalog' = @{
                            ComparisonRows = [System.Collections.Generic.List[object]]@(
                                @{
                                    ItemType     = 'Setting'
                                    Name         = 'Deprecated WiFi Setting'
                                    SettingPath  = 'WiFi > Config'
                                    Category     = 'Windows / Settings Catalog'
                                    Status       = 'Matched'
                                    SourcePolicy = 'Policy A'
                                    SourceValue  = 'WPA2'
                                    DestPolicy   = 'Policy A'
                                    DestValue    = 'WPA2'
                                    IsDeprecated = $true
                                },
                                @{
                                    ItemType     = 'Setting'
                                    Name         = 'Normal Setting'
                                    SettingPath  = ''
                                    Category     = 'Windows / Settings Catalog'
                                    Status       = 'Matched'
                                    SourcePolicy = 'Policy A'
                                    SourceValue  = 'Enabled'
                                    DestPolicy   = 'Policy A'
                                    DestValue    = 'Enabled'
                                    IsDeprecated = $false
                                }
                            )
                        }
                    }
                }
            }
            ManualReview     = [ordered]@{}
            GeneratedAt      = [datetime]::UtcNow
        }
    }

    It 'renders badge-deprecated span for deprecated rows' {
        $html = InModuleScope InforcerCommunity -Parameters @{ Model = $script:CompModelDepr } {
            ConvertTo-InforcerComparisonHtml -ComparisonModel $Model
        }
        $html | Should -Match 'Deprecated WiFi Setting.*badge-deprecated'
    }

    It 'does not render badge-deprecated span for non-deprecated rows' {
        $html = InModuleScope InforcerCommunity -Parameters @{ Model = $script:CompModelDepr } {
            ConvertTo-InforcerComparisonHtml -ComparisonModel $Model
        }
        # The normal setting row should NOT have a badge-deprecated span
        # Extract the table row for Normal Setting and check it does not contain badge-deprecated
        $html | Should -Match 'Normal Setting</td>'
    }
}

# ---------------------------------------------------------------------------
# Describe: ConvertTo-InforcerComparisonHtml - Value Display
# ---------------------------------------------------------------------------
Describe 'ConvertTo-InforcerComparisonHtml - Value Display' -Tag 'VAL', 'Phase5' {

    BeforeAll {
        # Build a comparison model with: one long value (>= 100 chars), one short value (< 100 chars), one Conflicting row
        $longValue = 'A' * 120   # 120 chars — triggers truncation
        $shortValue = 'ShortVal'  # < 100 chars — no truncation
        $script:CompModelVal = @{
            SourceName      = 'Source Tenant'
            DestinationName = 'Dest Tenant'
            Products        = [ordered]@{
                Windows = @{
                    Categories = [ordered]@{
                        'Settings Catalog' = @{
                            ComparisonRows = [System.Collections.Generic.List[object]]@(
                                @{
                                    ItemType     = 'Setting'
                                    Name         = 'Long Value Setting'
                                    SettingPath  = 'Config > Detail'
                                    Category     = 'Windows / Settings Catalog'
                                    Status       = 'Matched'
                                    SourcePolicy = 'Policy A'
                                    SourceValue  = $longValue
                                    DestPolicy   = 'Policy A'
                                    DestValue    = $longValue
                                    IsDeprecated = $false
                                },
                                @{
                                    ItemType     = 'Setting'
                                    Name         = 'Short Value Setting'
                                    SettingPath  = ''
                                    Category     = 'Windows / Settings Catalog'
                                    Status       = 'Matched'
                                    SourcePolicy = 'Policy B'
                                    SourceValue  = $shortValue
                                    DestPolicy   = 'Policy B'
                                    DestValue    = $shortValue
                                    IsDeprecated = $false
                                },
                                @{
                                    ItemType     = 'Setting'
                                    Name         = 'Conflict Setting'
                                    SettingPath  = 'Security > Auth'
                                    Category     = 'Windows / Settings Catalog'
                                    Status       = 'Conflicting'
                                    SourcePolicy = 'Policy C'
                                    SourceValue  = 'ValueA'
                                    DestPolicy   = 'Policy C'
                                    DestValue    = 'ValueB'
                                    IsDeprecated = $false
                                }
                            )
                        }
                    }
                }
            }
            ManualReview     = [ordered]@{}
            GeneratedAt      = [datetime]::UtcNow
        }

        $script:ValHtml = InModuleScope InforcerCommunity -Parameters @{ Model = $script:CompModelVal } {
            ConvertTo-InforcerComparisonHtml -ComparisonModel $Model
        }
    }

    It 'renders value-toggle-btn with More text for long values' -Tag 'VAL-01' {
        $script:ValHtml | Should -Match 'value-toggle-btn.*More'
    }

    It 'does not render value-toggle-btn for short values row' -Tag 'VAL-01' {
        # Short Value Setting row should not contain value-toggle-btn
        # Extract the row by finding Short Value Setting and checking the surrounding context
        # The short value "ShortVal" should appear without a value-toggle-btn nearby
        $shortRowPattern = 'Short Value Setting.*?</tr>'
        $shortRowMatch = [regex]::Match($script:ValHtml, $shortRowPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
        $shortRowMatch.Value | Should -Not -Match 'value-toggle-btn'
    }

    It 'CSS expanded state has white-space pre-wrap' -Tag 'VAL-02' {
        $script:ValHtml | Should -Match '\.value-truncate\.expanded\s*\{[^}]*white-space:\s*pre-wrap'
    }

    It 'CSS base truncate state does not have pre-wrap' -Tag 'VAL-02' {
        # Match the base .value-truncate rule (not .expanded) and verify no pre-wrap
        $baseTruncateMatch = [regex]::Match($script:ValHtml, '\.value-truncate\s*\{[^}]+\}')
        $baseTruncateMatch.Value | Should -Not -Match 'pre-wrap'
    }

    It 'renders value-copy-btn with data-value on all value cells' -Tag 'VAL-03' {
        $script:ValHtml | Should -Match 'value-copy-btn.*data-value'
    }

    It 'JS contains clipboard writeText handler for value-copy-btn' -Tag 'VAL-03' {
        $script:ValHtml | Should -Match 'value-copy-btn'
        $script:ValHtml | Should -Match 'navigator\.clipboard\.writeText'
    }

    It 'value-diff class is on inner element not td for conflicting dest' -Tag 'VAL-04' {
        # For the Conflict Setting row, the dest value td should have class="value-cell" only
        # and the inner div/span should have value-diff
        # Pattern: <td class="value-cell"><div class="value-wrap"><span class="value-text value-diff">ValueB
        $script:ValHtml | Should -Match '<td class="value-cell"><div class="value-wrap"><span class="value-text value-diff">'
    }

    It 'source column does not have value-diff class for conflicting row' -Tag 'VAL-04' {
        # The source value for Conflict Setting ("ValueA") should not have value-diff anywhere
        # Find "ValueA" in value-text or value-truncate and confirm no value-diff
        $script:ValHtml | Should -Match 'class="value-text">ValueA</span>'
    }
}

# ---------------------------------------------------------------------------
# Describe: ConvertTo-InforcerComparisonHtml - Assignments Display
# ---------------------------------------------------------------------------
Describe 'ConvertTo-InforcerComparisonHtml - Assignments Display' -Tag 'ASG', 'Phase6' {

    BeforeAll {
        # Minimal comparison model with IncludingAssignments = $true and rows covering all assignment types:
        # Row 1: include group (no prefix), Row 2: exclude group (red), Row 3: All Devices/All Users (blue),
        # Row 4: include with filter suffix (filter line) + empty dest (em dash)
        $script:CompModelAsg = @{
            SourceName           = 'Source Tenant'
            DestinationName      = 'Dest Tenant'
            IncludingAssignments = $true
            Products             = [ordered]@{
                Windows = @{
                    Categories = [ordered]@{
                        'Settings Catalog' = @{
                            ComparisonRows = [System.Collections.Generic.List[object]]@(
                                @{
                                    ItemType          = 'Setting'
                                    Name              = 'Include Row'
                                    SettingPath       = ''
                                    Category          = 'Windows / Settings Catalog'
                                    Status            = 'Matched'
                                    SourcePolicy      = 'Policy A'
                                    SourceValue       = 'Val1'
                                    DestPolicy        = 'Policy A'
                                    DestValue         = 'Val1'
                                    IsDeprecated      = $false
                                    SourceAssignment  = 'Marketing Team'
                                    DestAssignment    = 'Marketing Team'
                                },
                                @{
                                    ItemType          = 'Setting'
                                    Name              = 'Exclude Row'
                                    SettingPath       = ''
                                    Category          = 'Windows / Settings Catalog'
                                    Status            = 'Matched'
                                    SourcePolicy      = 'Policy B'
                                    SourceValue       = 'Val2'
                                    DestPolicy        = 'Policy B'
                                    DestValue         = 'Val2'
                                    IsDeprecated      = $false
                                    SourceAssignment  = 'Exclude: Finance Team'
                                    DestAssignment    = 'Exclude: Finance Team'
                                },
                                @{
                                    ItemType          = 'Setting'
                                    Name              = 'All Assignment Row'
                                    SettingPath       = ''
                                    Category          = 'Windows / Settings Catalog'
                                    Status            = 'Matched'
                                    SourcePolicy      = 'Policy C'
                                    SourceValue       = 'Val3'
                                    DestPolicy        = 'Policy C'
                                    DestValue         = 'Val3'
                                    IsDeprecated      = $false
                                    SourceAssignment  = 'All Devices'
                                    DestAssignment    = 'All Users'
                                },
                                @{
                                    ItemType          = 'Setting'
                                    Name              = 'Filter Row'
                                    SettingPath       = ''
                                    Category          = 'Windows / Settings Catalog'
                                    Status            = 'Matched'
                                    SourcePolicy      = 'Policy D'
                                    SourceValue       = 'Val4'
                                    DestPolicy        = 'Policy D'
                                    DestValue         = 'Val4'
                                    IsDeprecated      = $false
                                    SourceAssignment  = 'Marketing Team (include: Department = IT)'
                                    DestAssignment    = ''
                                }
                            )
                        }
                    }
                }
            }
            ManualReview  = [ordered]@{}
            GeneratedAt   = [datetime]::UtcNow
        }

        $script:AsgHtml = InModuleScope InforcerCommunity -Parameters @{ Model = $script:CompModelAsg } {
            ConvertTo-InforcerComparisonHtml -ComparisonModel $Model
        }
    }

    # ASG-01: Include-type group renders as plain text in default foreground, no "Include:" prefix, no badge class
    It 'include-type assignment does NOT contain assign-tag class' -Tag 'ASG-01' {
        $script:AsgHtml | Should -Not -Match 'class="assign-tag'
    }

    It 'include-type assignment does NOT prefix group name with "Include:"' -Tag 'ASG-01' {
        # "Marketing Team" should appear without "Include:" prefix in HTML
        $script:AsgHtml | Should -Not -Match '>Include:\s*Marketing Team'
    }

    It 'include-type assignment renders group name with assign-include class' -Tag 'ASG-01' {
        $script:AsgHtml | Should -Match 'class="assign-include"'
    }

    # ASG-02: Exclude-type group renders in red with "Exclude:" prefix
    It 'exclude-type assignment contains assign-exclude class' -Tag 'ASG-02' {
        $script:AsgHtml | Should -Match 'class="assign-exclude"'
    }

    It 'exclude-type assignment text starts with Exclude:' -Tag 'ASG-02' {
        $script:AsgHtml | Should -Match 'assign-exclude[^>]*>Exclude:'
    }

    # ASG-03: All Devices and All Users render with assign-all class (blue)
    It 'All Devices assignment contains assign-all class' -Tag 'ASG-03' {
        $script:AsgHtml | Should -Match 'class="assign-all"'
    }

    It 'All Users assignment also has assign-all class' -Tag 'ASG-03' {
        # Both All Devices and All Users rows should produce assign-all spans
        $allSpanMatches = ([regex]::Matches($script:AsgHtml, 'class="assign-all"')).Count
        $allSpanMatches | Should -BeGreaterThan 1
    }

    # ASG-04: Filter info on a separate muted line below the assignment
    It 'assignment with filter renders assign-filter span' -Tag 'ASG-04' {
        $script:AsgHtml | Should -Match 'class="assign-filter"'
    }

    It 'assign-filter span contains filter parenthetical text' -Tag 'ASG-04' {
        $script:AsgHtml | Should -Match 'assign-filter[^>]*>\s*\(include:'
    }

    # ASG-EMPTY: Empty assignment string displays as em dash in muted color
    It 'empty assignment string renders em dash' -Tag 'ASG-04' {
        $script:AsgHtml | Should -Match '&mdash;'
    }

    # CSS: assign-tag removed, assign-filter added
    It 'CSS does NOT contain .assign-tag class definition' {
        $script:AsgHtml | Should -Not -Match '\.assign-tag\s*\{'
    }

    It 'CSS contains .assign-filter class definition' {
        $script:AsgHtml | Should -Match '\.assign-filter\s*\{'
    }

    # Format-InforcerAssignmentString: filter suffix appended when Filter and FilterMode present
    It 'Format-InforcerAssignmentString appends filter parenthetical suffix when Filter and FilterMode are set' -Tag 'ASG-04' {
        $result = InModuleScope InforcerCommunity {
            $mockAssignment = [PSCustomObject]@{
                Type       = 'Group (Include)'
                Target     = 'Marketing Team'
                Filter     = 'Department = IT'
                FilterMode = 'Include'
            }
            Format-InforcerAssignmentString -Assignments @($mockAssignment)
        }
        $result | Should -Match '\(include: Department = IT\)'
    }

    It 'Format-InforcerAssignmentString Group (Include) emits just target without Include: prefix' -Tag 'ASG-01' {
        $result = InModuleScope InforcerCommunity {
            $mockAssignment = [PSCustomObject]@{
                Type       = 'Group (Include)'
                Target     = 'Sales Group'
                Filter     = ''
                FilterMode = ''
            }
            Format-InforcerAssignmentString -Assignments @($mockAssignment)
        }
        $result | Should -Be 'Sales Group'
        $result | Should -Not -Match 'Include:'
    }
}
