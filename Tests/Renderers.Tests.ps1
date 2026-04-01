# Renderers.Tests.ps1
# Pester 5.x tests for all output format renderers (HTML, Markdown, JSON, CSV).
# Run from repo root: Invoke-Pester ./Tests/Renderers.Tests.ps1
# Run Markdown-specific: Invoke-Pester ./Tests/Renderers.Tests.ps1 -Tag 'Markdown'

$ErrorActionPreference = 'Stop'

BeforeAll {
    Remove-Module -Name 'InforcerCommunity' -ErrorAction SilentlyContinue
    $here = $PSScriptRoot
    $manifestPath = [System.IO.Path]::GetFullPath((Join-Path $here '..' 'module' 'InforcerCommunity.psd1'))
    Import-Module $manifestPath -Force -ErrorAction Stop

    # Shared test DocModel used by all renderer describe blocks.
    # Build inside module scope so private functions can be called; expose via script variable.
    $script:TestDocModel = InModuleScope InforcerCommunity {
        $pipeValueSetting = [PSCustomObject]@{
            Name         = 'Pipe Setting'
            Value        = 'value|with|pipes'
            Indent       = 0
            IsConfigured = $true
        }
        $nullValueSetting = [PSCustomObject]@{
            Name         = 'Null Setting'
            Value        = $null
            Indent       = 0
            IsConfigured = $false
        }
        $childSetting = [PSCustomObject]@{
            Name         = 'Child Setting'
            Value        = 'child value'
            Indent       = 1
            IsConfigured = $true
        }
        $assignmentRow = [PSCustomObject]@{
            Group      = 'group-guid-1234'
            Filter     = 'filter-guid-abcd'
            FilterMode = 'include'
            Type       = 'groupAssignmentTarget'
        }
        $plainSetting = [PSCustomObject]@{
            Name         = 'Plain Setting'
            Value        = 'plain value'
            Indent       = 0
            IsConfigured = $true
        }

        $intuneCategory = [ordered]@{}
        $intuneCategory['Device Configuration'] = [System.Collections.Generic.List[object]]::new()

        # Policy 1: 3 settings (Indent 0 with pipe, Indent 1 child, Indent 0 null), no assignments
        $intuneCategory['Device Configuration'].Add(@{
            Basics      = @{
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
        })

        # Policy 2: 0 settings, 1 assignment
        $intuneCategory['Device Configuration'].Add(@{
            Basics      = @{
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
        })

        $entraCategory = [ordered]@{}
        $entraCategory['Conditional Access'] = [System.Collections.Generic.List[object]]::new()

        # Policy 3: 1 setting, 0 assignments
        $entraCategory['Conditional Access'].Add(@{
            Basics      = @{
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
        })

        @{
            TenantName   = 'Test Tenant'
            TenantId     = 12345
            GeneratedAt  = [datetime]'2026-01-15 10:30:00'
            BaselineName = 'TestBaseline'
            Products     = [ordered]@{
                'Intune' = @{ Categories = $intuneCategory }
                'Entra'  = @{ Categories = $entraCategory }
            }
        }
    }
}

# ---------------------------------------------------------------------------
# JSON renderer stub (Plan 02-03 will fill this in)
# ---------------------------------------------------------------------------
Describe 'ConvertTo-InforcerDocJson' -Tag 'JSON' {
    It 'Placeholder — implemented in Plan 02-03' -Skip {
        $true | Should -Be $true
    }
}

# ---------------------------------------------------------------------------
# CSV renderer stub (Plan 02-03 will fill this in)
# ---------------------------------------------------------------------------
Describe 'ConvertTo-InforcerDocCsv' -Tag 'CSV' {
    It 'Placeholder — implemented in Plan 02-03' -Skip {
        $true | Should -Be $true
    }
}

# ---------------------------------------------------------------------------
# Markdown renderer tests
# ---------------------------------------------------------------------------
Describe 'ConvertTo-InforcerMarkdown' -Tag 'Markdown' {
    BeforeAll {
        # Call renderer inside InModuleScope so private function is accessible
        $script:MarkdownOutput = InModuleScope InforcerCommunity -Parameters @{ DocModel = $script:TestDocModel } {
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
        # Em dash U+2014
        $script:MarkdownOutput | Should -Match [char]0x2014
    }

    It 'indents child settings with arrow marker' {
        # Child setting with Indent=1 should have arrow prefix
        $script:MarkdownOutput | Should -Match ([regex]::Escape([char]0x21B3))
    }

    It 'renders assignments table with correct headers' {
        $script:MarkdownOutput | Should -Match '\| Group \| Filter \| Filter Mode \| Type \|'
    }

    It 'skips settings table when policy has no settings' {
        # For 'Compliance Policy 1' which has 0 settings, the Settings table header should not appear
        # between its heading and the next heading. We verify no | Setting | Value | line follows #### Compliance Policy 1.
        $lines = $script:MarkdownOutput -split "`n"
        $policyIdx = ($lines | Select-String -Pattern '#### Compliance Policy 1').LineNumber - 1
        $nextPolicyIdx = ($lines | Select-String -Pattern '####' | Where-Object { $_.LineNumber - 1 -gt $policyIdx } | Select-Object -First 1).LineNumber - 1
        if ($null -eq $nextPolicyIdx) { $nextPolicyIdx = $lines.Count }
        $sectionLines = $lines[$policyIdx..($nextPolicyIdx - 1)] -join "`n"
        $sectionLines | Should -Not -Match '\| Setting \| Value \|'
    }
}
