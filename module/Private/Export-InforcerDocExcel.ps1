function Export-InforcerDocExcel {
    <#
    .SYNOPSIS
        Exports a DocModel to an Excel workbook with one sheet per product.
    .DESCRIPTION
        Takes the format-agnostic DocModel produced by ConvertTo-InforcerDocModel and writes
        an .xlsx file with one worksheet per product. Each sheet contains all policies for that
        product with policy metadata, settings, and assignments.

        Columns: Category, PolicyName, Description, ProfileType, Platform, Tags, Created,
        Modified, ScopeTags, SettingName, Value, IsConfigured, Assignments.

        Requires the ImportExcel module. If not installed, offers to install it.

        This function handles its own file I/O (ImportExcel writes directly to disk).
    .PARAMETER DocModel
        Hashtable from ConvertTo-InforcerDocModel containing TenantName, TenantId,
        GeneratedAt, BaselineName, and Products ordered dictionary.
    .PARAMETER FilePath
        Full path to the output .xlsx file.
    .OUTPUTS
        None. Writes directly to disk via ImportExcel.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$DocModel,

        [Parameter(Mandatory)]
        [string]$FilePath
    )

    # Check for ImportExcel module — offer to install if missing
    if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
        $answer = Read-Host 'The ImportExcel module is required for Excel export. Install it now? (Y/n)'
        if ($answer -match '^[Yy]?$') {
            Write-Host 'Installing ImportExcel...' -ForegroundColor Cyan
            Install-Module ImportExcel -Scope CurrentUser -Force -ErrorAction Stop
            Write-Host '  ImportExcel installed successfully.' -ForegroundColor Green
        } else {
            Write-Error -Message 'Excel export requires the ImportExcel module. Install it with: Install-Module ImportExcel -Scope CurrentUser' `
                -ErrorId 'ImportExcelNotFound' -Category NotInstalled
            return
        }
    }

    Import-Module ImportExcel -ErrorAction Stop

    # Remove existing file (Export-Excel appends by default)
    if (Test-Path -LiteralPath $FilePath) {
        Remove-Item -LiteralPath $FilePath -Force
    }

    foreach ($prodName in $DocModel.Products.Keys) {
        $product = $DocModel.Products[$prodName]
        $rows = [System.Collections.Generic.List[object]]::new()

        foreach ($catName in $product.Categories.Keys) {
            $policies = $product.Categories[$catName]
            foreach ($policy in $policies) {
                $basics = $policy.Basics

                # Format assignments as a single string (e.g. "All Users; Group (Include): SG-Intune")
                $assignStr = ''
                if ($policy.Assignments -and $policy.Assignments.Count -gt 0) {
                    $parts = [System.Collections.Generic.List[string]]::new()
                    foreach ($a in $policy.Assignments) {
                        $entry = $a.Type
                        if (-not [string]::IsNullOrWhiteSpace($a.Target) -and $a.Target -ne $a.Type) {
                            $entry = "$($a.Type): $($a.Target)"
                        }
                        if (-not [string]::IsNullOrWhiteSpace($a.Filter)) {
                            $filterPart = "Filter ($($a.FilterMode)): $($a.Filter)"
                            $entry = "$entry [$filterPart]"
                        }
                        [void]$parts.Add($entry)
                    }
                    $assignStr = $parts -join '; '
                }

                if ($policy.Settings -and $policy.Settings.Count -gt 0) {
                    # One row per setting — policy metadata repeated on each row for filtering
                    $isFirst = $true
                    foreach ($setting in $policy.Settings) {
                        [void]$rows.Add([PSCustomObject]@{
                            Category     = $catName
                            PolicyName   = $basics.Name
                            Description  = if ($isFirst) { $basics.Description } else { '' }
                            ProfileType  = if ($isFirst) { $basics.ProfileType } else { '' }
                            Platform     = if ($isFirst) { $basics.Platform } else { '' }
                            Tags         = if ($isFirst) { $basics.Tags } else { '' }
                            Created      = if ($isFirst) { $basics.Created } else { '' }
                            Modified     = if ($isFirst) { $basics.Modified } else { '' }
                            ScopeTags    = if ($isFirst) { $basics.ScopeTags } else { '' }
                            SettingName  = $setting.Name
                            Value        = if ([string]::IsNullOrEmpty($setting.Value)) { '' } else { $setting.Value }
                            IsConfigured = $setting.IsConfigured
                            Assignments  = if ($isFirst) { $assignStr } else { '' }
                        })
                        $isFirst = $false
                    }
                } else {
                    # Policy with no settings — still export one row with metadata
                    [void]$rows.Add([PSCustomObject]@{
                        Category     = $catName
                        PolicyName   = $basics.Name
                        Description  = $basics.Description
                        ProfileType  = $basics.ProfileType
                        Platform     = $basics.Platform
                        Tags         = $basics.Tags
                        Created      = $basics.Created
                        Modified     = $basics.Modified
                        ScopeTags    = $basics.ScopeTags
                        SettingName  = ''
                        Value        = ''
                        IsConfigured = ''
                        Assignments  = $assignStr
                    })
                }
            }
        }

        if ($rows.Count -eq 0) { continue }

        # Sanitize sheet name (Excel max 31 chars, no []:*?/\ characters)
        $sheetName = $prodName -replace '[\[\]:*?/\\]', ''
        if ($sheetName.Length -gt 31) { $sheetName = $sheetName.Substring(0, 31) }

        $rows | Export-Excel -Path $FilePath -WorksheetName $sheetName -AutoSize -AutoFilter -FreezeTopRow -BoldTopRow
    }
}
