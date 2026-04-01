function ConvertTo-InforcerDocCsv {
    <#
    .SYNOPSIS
        Flattens a DocModel into a settings-focused CSV string.
    .DESCRIPTION
        Takes the format-agnostic DocModel produced by ConvertTo-InforcerDocModel and returns
        a CSV string with one row per setting value across all products, categories, and policies.

        Columns: Product, Category, PolicyName, SettingName, Value, Indent, IsConfigured
        Null and empty setting values are output as empty string (per D-11, for clean Excel import).
        Assignments and Basics sections are excluded — this is a settings-only flat export (per D-26).
        Policies with no settings produce no CSV rows.

        This function performs no file I/O and makes no API calls — it is a pure transform.
        File writing is handled by the public Export-InforcerDocumentation cmdlet (Phase 3).
    .PARAMETER DocModel
        Hashtable from ConvertTo-InforcerDocModel containing TenantName, TenantId,
        GeneratedAt, BaselineName, and Products ordered dictionary.
    .OUTPUTS
        System.String — CSV text (header + data rows) joined by Environment.NewLine.
    .EXAMPLE
        $csv = ConvertTo-InforcerDocCsv -DocModel $docModel
        # Returns CSV string; write to disk via Set-Content $outputPath -Value $csv -Encoding UTF8
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$DocModel
    )

    $rows = [System.Collections.Generic.List[object]]::new()

    foreach ($prodName in $DocModel.Products.Keys) {
        $product = $DocModel.Products[$prodName]
        foreach ($catName in $product.Categories.Keys) {
            $policies = $product.Categories[$catName]
            foreach ($policy in $policies) {
                foreach ($setting in $policy.Settings) {
                    [void]$rows.Add([PSCustomObject]@{
                        Product      = $prodName
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
    }

    ($rows | ConvertTo-Csv -NoTypeInformation) -join [Environment]::NewLine
}
