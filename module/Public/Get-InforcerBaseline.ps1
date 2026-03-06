<#
.SYNOPSIS
    Retrieves baseline information from the Inforcer API.
.DESCRIPTION
    Retrieves baseline groups and members. Optionally filter by -TenantId (owner or member).
.PARAMETER Format
    Raw (default).
.PARAMETER TenantId
    Optional. Filter baselines where this tenant is owner or member.
.PARAMETER OutputType
    PowerShellObject (default) or JsonObject.
.EXAMPLE
    Get-InforcerBaseline
.EXAMPLE
    Get-InforcerBaseline -TenantId 482
.EXAMPLE
    Get-InforcerBaseline -OutputType JsonObject
    Returns JSON string with full depth (100).
.OUTPUTS
    PSObject or String
.LINK
    Connect-Inforcer
#>
function Get-InforcerBaseline {
[CmdletBinding()]
[OutputType([PSObject], [string])]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Raw')]
    [string]$Format = 'Raw',

    [Parameter(Mandatory = $false)]
    [object]$TenantId,

    [Parameter(Mandatory = $false)]
    [ValidateSet('PowerShellObject', 'JsonObject')]
    [string]$OutputType = 'PowerShellObject'
)

if (-not (Test-InforcerSession)) {
    Write-Error -Message 'Not connected yet. Please run Connect-Inforcer first.' -ErrorId 'NotConnected' -Category ConnectionError
    return
}

Write-Verbose 'Retrieving baseline information...'

$response = Invoke-InforcerApiRequest -Endpoint '/beta/baselines' -Method GET -OutputType $OutputType
if ($null -eq $response) { return }

$filterPredicate = $null
if ($null -ne $TenantId) {
    try {
        $clientTenantId = Resolve-InforcerTenantId -TenantId $TenantId
    } catch {
        Write-Error -Message $_.Exception.Message -ErrorId 'InvalidTenantId' -Category InvalidArgument
        return
    }
    Write-Verbose "Filtering baselines to tenant ID $clientTenantId..."
    $filterPredicate = {
        param($p)
        $ownerProp = $p.PSObject.Properties['baselineClientTenantId']
        if ($ownerProp -and [int]$ownerProp.Value -eq $clientTenantId) { return $true }
        $membersProp = $p.PSObject.Properties['members']
        if ($membersProp -and $membersProp.Value -is [object[]]) {
            foreach ($m in $membersProp.Value) {
                if ($m -is [PSObject]) {
                    $cid = $m.PSObject.Properties['clientTenantId'].Value
                    if ($null -ne $cid -and [int]$cid -eq $clientTenantId) { return $true }
                }
            }
        }
        $false
    }
}

if ($OutputType -eq 'JsonObject') {
    if ($filterPredicate) {
        Filter-InforcerResponse -InputObject $response -FilterScript $filterPredicate -OutputType JsonObject
    } else {
        $response
    }
    return
}

$result = $response
if ($result -is [array]) {
    foreach ($item in $result) {
        if ($item -is [PSObject]) {
            Add-InforcerPropertyAliases -InputObject $item -ObjectType Baseline
            $item.PSObject.TypeNames.Insert(0, 'InforcerCommunity.Baseline')
        }
    }
} elseif ($result -is [PSObject]) {
    Add-InforcerPropertyAliases -InputObject $result -ObjectType Baseline
    $result.PSObject.TypeNames.Insert(0, 'InforcerCommunity.Baseline')
}

if ($filterPredicate) {
    $result = Filter-InforcerResponse -InputObject $result -FilterScript $filterPredicate -OutputType PowerShellObject
}

if ($result -is [array]) {
    $result | ForEach-Object { $_ }
} else {
    $result
}
}
