<#
.SYNOPSIS
    Retrieves available assessments from the Inforcer API.
.DESCRIPTION
    Lists all assessments available for evaluation (e.g. Copilot Readiness, CIS Benchmarks,
    Essential Eight). Each assessment has an ID, name, description, tags, and type.
.PARAMETER Format
    Raw (default).
.PARAMETER OutputType
    PowerShellObject (default) or JsonObject. JSON uses Depth 100.
.EXAMPLE
    Get-InforcerAssessment
    Lists all available assessments.
.EXAMPLE
    Get-InforcerAssessment -OutputType JsonObject
    Returns assessments as a JSON string with full depth.
.OUTPUTS
    PSObject or String
.LINK
    https://github.com/royklo/InforcerCommunity/blob/main/docs/CMDLET-REFERENCE.md#get-inforcerassessment
.LINK
    Connect-Inforcer
.LINK
    Invoke-InforcerAssessment
#>
function Get-InforcerAssessment {
[CmdletBinding()]
[OutputType([PSObject], [string])]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Raw')]
    [string]$Format = 'Raw',

    [Parameter(Mandatory = $false)]
    [ValidateSet('PowerShellObject', 'JsonObject')]
    [string]$OutputType = 'PowerShellObject'
)

if (-not (Test-InforcerSession)) {
    Write-Error -Message 'Not connected yet. Please run Connect-Inforcer first.' -ErrorId 'NotConnected' -Category ConnectionError
    return
}

Write-Verbose 'Retrieving assessments...'

$response = Invoke-InforcerApiRequest -Endpoint '/beta/assessments' -Method GET -OutputType $OutputType
if ($null -eq $response) { return }

if ($OutputType -eq 'JsonObject') {
    $response
    return
}

$result = $response
if ($result -is [array]) {
    foreach ($item in $result) {
        if ($item -is [PSObject]) {
            $null = Add-InforcerPropertyAliases -InputObject $item -ObjectType Assessment
            $item.PSObject.TypeNames.Insert(0, 'InforcerCommunity.Assessment')
        }
    }
} elseif ($result -is [PSObject]) {
    $null = Add-InforcerPropertyAliases -InputObject $result -ObjectType Assessment
    $result.PSObject.TypeNames.Insert(0, 'InforcerCommunity.Assessment')
}

$result
}
