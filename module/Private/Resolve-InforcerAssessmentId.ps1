function Resolve-InforcerAssessmentId {
    <#
    .SYNOPSIS
        Resolves an assessment identifier (ID or friendly name) to an assessment ID string.
    .DESCRIPTION
        If the value looks like an existing assessment ID, returns it directly.
        If it is a friendly name, resolves to the assessment ID using -AssessmentData when provided,
        otherwise calls the API to fetch assessments.
    .PARAMETER AssessmentId
        Assessment ID string or friendly assessment name.
    .PARAMETER AssessmentData
        Optional. Pre-fetched array of assessment objects (e.g. from GET /beta/assessments). When provided
        and AssessmentId is a name, resolution is done from this data instead of calling the API.
    .OUTPUTS
        System.String - The resolved assessment ID.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [string]$AssessmentId,

        [Parameter(Mandatory = $false)]
        [object[]]$AssessmentData
    )

    process {
        $assessmentIdString = $AssessmentId.Trim()

        Write-Verbose "Resolving assessment: '$assessmentIdString'..."
        $assessmentsToUse = $AssessmentData
        if ($null -eq $assessmentsToUse -or $assessmentsToUse.Count -eq 0) {
            $assessmentsToUse = @(Invoke-InforcerApiRequest -Endpoint '/beta/assessments' -Method GET -OutputType PowerShellObject)
        }
        $assessments = if ($assessmentsToUse -is [array]) { $assessmentsToUse } else { @($assessmentsToUse) }

        # Pass 1: exact ID match
        foreach ($a in $assessments) {
            if (-not ($a -is [PSObject])) { continue }
            $idProp = $a.PSObject.Properties['id']
            if ($idProp -and $null -ne $idProp.Value -and $idProp.Value.ToString().Trim() -ceq $assessmentIdString) {
                Write-Verbose "Exact ID match found: $assessmentIdString"
                return $assessmentIdString
            }
        }

        # Pass 2: name match (exact case first, then case-insensitive)
        $exactMatch = $null
        $caseInsensitiveMatch = $null
        foreach ($a in $assessments) {
            if (-not ($a -is [PSObject])) { continue }
            $nameProp = $a.PSObject.Properties['name']
            if (-not $nameProp -or $null -eq $nameProp.Value) { continue }
            $aName = $nameProp.Value.ToString().Trim()
            if ($aName -ceq $assessmentIdString) {
                $idProp = $a.PSObject.Properties['id']
                if ($idProp -and $null -ne $idProp.Value) {
                    $exactMatch = $idProp.Value.ToString()
                    break
                }
            } elseif ($null -eq $caseInsensitiveMatch -and $aName.Equals($assessmentIdString, [StringComparison]::OrdinalIgnoreCase)) {
                $idProp = $a.PSObject.Properties['id']
                if ($idProp -and $null -ne $idProp.Value) {
                    $caseInsensitiveMatch = $idProp.Value.ToString()
                }
            }
        }

        $resolved = if ($exactMatch) { $exactMatch } else { $caseInsensitiveMatch }
        if ($resolved) {
            Write-Verbose "Found matching assessment. ID: $resolved"
            return $resolved
        }

        throw [System.InvalidOperationException]::new("No assessment found with name or ID: $assessmentIdString")
    }
}
