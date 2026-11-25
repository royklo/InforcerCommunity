function ConvertTo-InforcerTdrAutoContainment {
    # Shapes a GET or PATCH autoContainment answer: msTenantId first (the API leaves it out), then the API's fields.
    param(
        [Parameter(Mandatory)] [PSObject]$Result,
        [Parameter(Mandatory)] [string]$TenantId,
        [string]$OutputType = 'PowerShellObject'
    )
    $out = [ordered]@{ msTenantId = $TenantId }
    foreach ($p in $Result.PSObject.Properties) { $out[$p.Name] = $p.Value }
    $obj = [PSCustomObject]$out
    if ($OutputType -eq 'JsonObject') { return $obj | ConvertTo-Json -Depth 100 }
    $obj.PSObject.TypeNames.Insert(0, 'InforcerCommunity.TdrAutoContainment')
    $obj
}
