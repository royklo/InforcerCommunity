# Private helper; name Filter kept for API response filtering (PSScriptAnalyzer may warn PSUseApprovedVerbs).
function Filter-InforcerResponse {
    <#
    .SYNOPSIS
        Filters API response by a scriptblock (Private helper).
    .DESCRIPTION
        Preserves single-object vs array shape. When re-serializing to JSON uses -Depth 100.
    .PARAMETER InputObject
        Single object or array of objects (PSObject or JSON string).
    .PARAMETER FilterScript
        Scriptblock that returns $true for items to keep. $_ is the current item.
    .PARAMETER OutputType
        PowerShellObject (filter PSObjects) or JsonObject (parse JSON, filter, re-serialize with Depth 100).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [scriptblock]$FilterScript,

        [Parameter(Mandatory = $false)]
        [ValidateSet('PowerShellObject', 'JsonObject')]
        [string]$OutputType = 'PowerShellObject'
    )

    process {
        if ($null -eq $InputObject) { return $null }

        if ($OutputType -eq 'JsonObject') {
            $json = $InputObject
            if ($InputObject -isnot [string]) {
                $json = $InputObject | ConvertTo-Json -Depth 100
            }
            if ([string]::IsNullOrWhiteSpace($json)) { return '[]' }
            try {
                $objects = $json | ConvertFrom-Json
            } catch {
                Write-Error -Message "Filter-InforcerResponse: invalid JSON. $($_.Exception.Message)" -ErrorId 'InvalidJson' -Category InvalidData
                return $null
            }
            # JSON "null" parses to $null; avoid passing to filter script
            if ($null -eq $objects) { return 'null' }
            $filtered = if ($objects -is [array]) {
                @($objects | Where-Object { $null -ne $_ -and (& $FilterScript $_) })
            } else {
                if (& $FilterScript $objects) { $objects } else { $null }
            }
            if ($null -eq $filtered) { return 'null' }
            if ($filtered -is [array] -and $filtered.Count -eq 0) { return '[]' }
            return $filtered | ConvertTo-Json -Depth 100
        }

        if ($InputObject -is [array]) {
            return @($InputObject | Where-Object { $_ -is [PSObject] -and (& $FilterScript $_) })
        }
        if ($InputObject -is [PSObject]) {
            if (& $FilterScript $InputObject) { return $InputObject }
            return $null
        }
        $null
    }
}
