function Resolve-InforcerBaselineId {
    <#
    .SYNOPSIS
        Resolves a baseline identifier (GUID or friendly name) to a baseline GUID.
    .DESCRIPTION
        If the value is a GUID string, returns it directly.
        If it is a friendly name, resolves to the baseline GUID using -BaselineData when provided,
        otherwise calls the API to fetch baselines.
    .PARAMETER BaselineId
        Baseline GUID or friendly baseline name.
    .PARAMETER BaselineData
        Optional. Pre-fetched array of baseline objects (e.g. from GET /beta/baselines). When provided
        and BaselineId is a name, resolution is done from this data instead of calling the API.
    .OUTPUTS
        System.String - The resolved baseline GUID.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$BaselineId,

        [Parameter(Mandatory = $false)]
        [object[]]$BaselineData
    )

    process {
        $baselineIdString = $BaselineId.Trim()

        $guidResult = [guid]::Empty
        if ([guid]::TryParse($baselineIdString, [ref]$guidResult)) {
            Write-Verbose "Baseline GUID detected: $baselineIdString"
            return $baselineIdString
        }

        Write-Verbose "Baseline name detected: '$baselineIdString'. Looking up baseline GUID..."
        $baselinesToUse = $BaselineData
        if ($null -eq $baselinesToUse -or $baselinesToUse.Count -eq 0) {
            $baselinesToUse = @(Invoke-InforcerApiRequest -Endpoint '/beta/baselines' -Method GET -OutputType PowerShellObject)
        }
        $baselines = if ($baselinesToUse -is [array]) { $baselinesToUse } else { @($baselinesToUse) }

        $exactMatch = $null
        $caseInsensitiveMatch = $null
        foreach ($b in $baselines) {
            if (-not ($b -is [PSObject])) { continue }
            $nameProp = $b.PSObject.Properties['name']
            if (-not $nameProp -or $null -eq $nameProp.Value) { continue }
            $bName = $nameProp.Value.ToString().Trim()
            if ($bName -ceq $baselineIdString) {
                $idProp = $b.PSObject.Properties['id']
                if ($idProp -and $null -ne $idProp.Value) {
                    $exactMatch = $idProp.Value.ToString()
                    break
                }
            } elseif ($null -eq $caseInsensitiveMatch -and $bName.Equals($baselineIdString, [StringComparison]::OrdinalIgnoreCase)) {
                $idProp = $b.PSObject.Properties['id']
                if ($idProp -and $null -ne $idProp.Value) {
                    $caseInsensitiveMatch = $idProp.Value.ToString()
                }
            }
        }

        $resolved = if ($exactMatch) { $exactMatch } else { $caseInsensitiveMatch }
        if ($resolved) {
            Write-Verbose "Found matching baseline. GUID: $resolved"
            return $resolved
        }

        throw [System.InvalidOperationException]::new("No baseline found with name: $baselineIdString")
    }
}
