function ConvertTo-InforcerDocJson {
    <#
    .SYNOPSIS
        Serializes a DocModel hashtable to a JSON string.
    .DESCRIPTION
        Takes the format-agnostic DocModel produced by ConvertTo-InforcerDocModel and returns
        a pretty-printed JSON string. Preserves the full Product -> Category -> Policy ->
        Sections (Basics, Settings, Assignments) structure at full depth.

        Null values in the DocModel are preserved as JSON null (not converted to empty string).
        Output is pretty-printed by default (ConvertTo-Json default behavior).

        This function performs no file I/O and makes no API calls — it is a pure transform.
        File writing is handled by the public Export-InforcerDocumentation cmdlet (Phase 3).
    .PARAMETER DocModel
        Hashtable from ConvertTo-InforcerDocModel containing TenantName, TenantId,
        GeneratedAt, BaselineName, and Products ordered dictionary.
    .OUTPUTS
        System.String — Pretty-printed JSON text representing the full DocModel.
    .EXAMPLE
        $json = ConvertTo-InforcerDocJson -DocModel $docModel
        # Returns JSON string; write to disk via Set-Content $outputPath -Value $json -Encoding UTF8
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$DocModel
    )

    $DocModel | ConvertTo-Json -Depth 100
}
