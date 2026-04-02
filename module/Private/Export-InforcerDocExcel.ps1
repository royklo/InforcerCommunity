function Export-InforcerDocExcel {
    <#
    .SYNOPSIS
        Exports a DocModel to an Excel workbook with one sheet per product.
    .DESCRIPTION
        Takes the format-agnostic DocModel produced by ConvertTo-InforcerDocModel and writes
        an .xlsx file with one worksheet per product. Each sheet contains all policies for that
        product with columns: Category, PolicyName, SettingName, Value, Indent, IsConfigured.

        Requires the ImportExcel module. If not installed, emits an error with install instructions.

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
                foreach ($setting in $policy.Settings) {
                    [void]$rows.Add([PSCustomObject]@{
                        Category     = $catName
                        PolicyName   = $policy.Basics.Name
                        SettingName  = $setting.Name
                        Value        = if ([string]::IsNullOrEmpty($setting.Value)) { '' } else { $setting.Value }
                        Indent       = $setting.Indent
                        IsConfigured = $setting.IsConfigured
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
