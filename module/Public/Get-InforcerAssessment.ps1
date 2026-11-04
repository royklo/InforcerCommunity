<#
.SYNOPSIS
    Retrieves available assessments from the Inforcer API.

    Required API scope(s): Assessments.Read (API key); Tenant Assessment permission (API client, unconfirmed).
.DESCRIPTION
    Lists all assessments available for evaluation (e.g. Copilot Readiness, CIS Benchmarks,
    Essential Eight). Each assessment has an ID, name, description, tags, and type.
    Works with both login types: an API key uses the legacy API, a client ID and secret
    (Connect-Inforcer -ClientId) uses the v1 API. The output has the same properties either way.
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

$response = Invoke-InforcerApiRequest -Endpoint '/assessments' -Method GET -OutputType $OutputType -ObjectType Assessment
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

# Prime the assessment cache so the -AssessmentId tab completer on Invoke-InforcerReport
# is instant. Successful list call also clears any prior denial sentinel.
$script:InforcerAssessmentCache       = @($result)
$script:InforcerAssessmentCacheDeniedAt = $null

$result
}
