function ConvertTo-InforcerArray {
    <#
    .SYNOPSIS
        Normalizes a value to an array (Private helper).
    .DESCRIPTION
        Returns @() for null; otherwise returns @($InputObject) so that single objects and arrays are treated uniformly.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false, ValueFromPipeline = $true)]
        [object]$InputObject
    )
    if ($null -eq $InputObject) { return @() }
    return @($InputObject)
}
