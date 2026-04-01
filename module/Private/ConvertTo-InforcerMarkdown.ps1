function ConvertTo-MarkdownAnchor {
    <#
    .SYNOPSIS
        Converts a display name string to a GitHub Flavored Markdown anchor fragment.
    .PARAMETER Text
        The heading text to convert.
    .OUTPUTS
        [string] Lowercase anchor fragment (e.g. 'Device Configuration' -> 'device-configuration').
    #>
    param([Parameter(Mandatory)][string]$Text)
    ($Text.ToLower() -replace '[^a-z0-9\s-]', '' -replace '\s+', '-').Trim('-')
}

function ConvertTo-MarkdownTable {
    <#
    .SYNOPSIS
        Builds a GFM pipe-delimited Markdown table from headers and rows.
    .PARAMETER Headers
        Array of column header strings.
    .PARAMETER Rows
        Array of string arrays, one per data row. Each inner array must have the same
        number of elements as Headers.
    .OUTPUTS
        [string] Complete GFM table block (header row + separator + data rows).
    #>
    param(
        [Parameter(Mandatory)][string[]]$Headers,
        [Parameter(Mandatory)][object[]]$Rows
    )

    $sb = [System.Text.StringBuilder]::new()

    # Header row
    $headerCells = $Headers | ForEach-Object { " $_ " }
    [void]$sb.AppendLine("|$($headerCells -join '|')|")

    # Separator row
    $sepCells = $Headers | ForEach-Object { ' --- ' }
    [void]$sb.AppendLine("|$($sepCells -join '|')|")

    # Data rows
    foreach ($row in $Rows) {
        $cells = @($row) | ForEach-Object {
            $val = if ($null -eq $_ -or "$_" -eq '') { [char]0x2014 } else { "$_" }
            # Escape pipe characters (D-20)
            $val = $val -replace '\|', '\|'
            " $val "
        }
        [void]$sb.AppendLine("|$($cells -join '|')|")
    }

    $sb.ToString().TrimEnd()
}

function ConvertTo-InforcerMarkdown {
    <#
    .SYNOPSIS
        Renders a DocModel as a GitHub Flavored Markdown document.
    .DESCRIPTION
        Consumes the format-agnostic DocModel produced by ConvertTo-InforcerDocModel and returns
        a complete GFM Markdown string with:
        - Document header (tenant name, generation timestamp, baseline)
        - Anchor-based Table of Contents (Products -> Categories, two-level)
        - Per-product (##), per-category (###), per-policy (####) headings
        - Basics table (Property | Value), Settings table (Setting | Value), Assignments table
        - Pipe characters in cell values escaped as \| (per D-20)
        - Null/empty values rendered as em dash (U+2014) (per D-10)
        - Child settings (Indent > 0) prefixed with arrow markers (U+21B3) (per D-08)

        No file I/O, no API calls. Returns the Markdown string only.
    .PARAMETER DocModel
        Hashtable from ConvertTo-InforcerDocModel containing TenantName, TenantId,
        GeneratedAt, BaselineName, and Products (OrderedDictionary).
    .OUTPUTS
        [string] Complete GFM Markdown document.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$DocModel
    )

    $sb = [System.Text.StringBuilder]::new()

    # -------------------------------------------------------------------------
    # Document header
    # -------------------------------------------------------------------------
    [void]$sb.AppendLine("# Tenant Documentation: $($DocModel.TenantName)")
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("*Generated: $($DocModel.GeneratedAt.ToString('yyyy-MM-dd HH:mm:ss')) UTC*")
    [void]$sb.AppendLine()

    if (-not [string]::IsNullOrWhiteSpace($DocModel.BaselineName)) {
        [void]$sb.AppendLine("*Baseline: $($DocModel.BaselineName)*")
        [void]$sb.AppendLine()
    }

    # -------------------------------------------------------------------------
    # Table of Contents
    # -------------------------------------------------------------------------
    [void]$sb.AppendLine('## Table of Contents')
    [void]$sb.AppendLine()

    foreach ($prodName in $DocModel.Products.Keys) {
        $prodAnchor = ConvertTo-MarkdownAnchor -Text $prodName
        [void]$sb.AppendLine("- [$prodName](#$prodAnchor)")
        $product = $DocModel.Products[$prodName]
        foreach ($catName in $product.Categories.Keys) {
            $catAnchor = ConvertTo-MarkdownAnchor -Text $catName
            [void]$sb.AppendLine("  - [$catName](#$catAnchor)")
        }
    }
    [void]$sb.AppendLine()
    [void]$sb.AppendLine('---')
    [void]$sb.AppendLine()

    # -------------------------------------------------------------------------
    # Content sections
    # -------------------------------------------------------------------------
    foreach ($prodName in $DocModel.Products.Keys) {
        [void]$sb.AppendLine("## $prodName")
        [void]$sb.AppendLine()

        $product = $DocModel.Products[$prodName]

        foreach ($catName in $product.Categories.Keys) {
            [void]$sb.AppendLine("### $catName")
            [void]$sb.AppendLine()

            $policies = $product.Categories[$catName]

            foreach ($policy in @($policies)) {
                $policyName = if ($policy.Basics -and $policy.Basics.Name) { $policy.Basics.Name } else { 'Unknown Policy' }
                [void]$sb.AppendLine("#### $policyName")
                [void]$sb.AppendLine()

                # Basics table - skip Name row (it is the heading)
                $basicsRows = @()
                $basics = $policy.Basics
                $basicsProps = @('Description', 'ProfileType', 'Platform', 'Created', 'Modified', 'ScopeTags')
                foreach ($prop in $basicsProps) {
                    $basicsRows += ,@($prop, $basics[$prop])
                }
                [void]$sb.AppendLine((ConvertTo-MarkdownTable -Headers @('Property', 'Value') -Rows $basicsRows))
                [void]$sb.AppendLine()

                # Settings table (only if there are settings)
                if ($policy.Settings -and $policy.Settings.Count -gt 0) {
                    $settingsRows = @()
                    foreach ($setting in @($policy.Settings)) {
                        $settingName = if ($setting.Indent -gt 0) {
                            "$('  ' * $setting.Indent)" + [char]0x21B3 + " $($setting.Name)"
                        } else {
                            $setting.Name
                        }
                        $settingsRows += ,@($settingName, $setting.Value)
                    }
                    [void]$sb.AppendLine((ConvertTo-MarkdownTable -Headers @('Setting', 'Value') -Rows $settingsRows))
                    [void]$sb.AppendLine()
                }

                # Assignments table (only if there are assignments)
                if ($policy.Assignments -and $policy.Assignments.Count -gt 0) {
                    $assignmentRows = @()
                    foreach ($assignment in @($policy.Assignments)) {
                        $assignmentRows += ,@($assignment.Group, $assignment.Filter, $assignment.FilterMode, $assignment.Type)
                    }
                    [void]$sb.AppendLine((ConvertTo-MarkdownTable -Headers @('Group', 'Filter', 'Filter Mode', 'Type') -Rows $assignmentRows))
                    [void]$sb.AppendLine()
                }
            }
        }
    }

    $sb.ToString()
}
