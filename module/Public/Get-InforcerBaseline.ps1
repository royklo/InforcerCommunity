<#
.SYNOPSIS
    Retrieves baseline information from the Inforcer API.

    Required API scope(s): Baselines.Read
.DESCRIPTION
    Retrieves baseline groups and members. Optionally filter by -TenantId (owner or member).
    API-key login: the owner is identified by BaselineClientTenantId and members by ClientTenantId.
    Client-credentials login: those numeric ids do not exist; the owner is BaselineMsTenantId and
    members carry MsTenantId.
.PARAMETER Format
    Raw (default).
.PARAMETER TenantId
    Optional. Filter baselines where this tenant is owner or member. Accepts the Microsoft Tenant ID
    (GUID), the tenant name, or (API-key login only) the numeric Client Tenant ID.
.PARAMETER OutputType
    PowerShellObject (default) or JsonObject.
.EXAMPLE
    Get-InforcerBaseline
.EXAMPLE
    Get-InforcerBaseline -TenantId 482
.EXAMPLE
    Get-InforcerBaseline -TenantId '00000000-0000-0000-0000-000000000001'
    Baselines owned by, or including, the tenant with this Microsoft Tenant ID (both logins).
.EXAMPLE
    Get-InforcerBaseline -OutputType JsonObject
    Returns JSON string with full depth (100).
.OUTPUTS
    PSObject or String
.LINK
    https://github.com/royklo/InforcerCommunity/blob/main/docs/CMDLET-REFERENCE.md#get-inforcerbaseline
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

    [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
    [Alias('ClientTenantId', 'MsTenantId')]
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

$response = Invoke-InforcerApiRequest -Endpoint '/baselines' -Method GET -OutputType $OutputType -ObjectType Baseline
if ($null -eq $response) { return }

$filterPredicate = $null
if ($null -ne $TenantId) {
    try {
        $resolvedTenantId = Resolve-InforcerTenantId -TenantId $TenantId -ErrorAction Stop
    } catch {
        Write-Error -Message $_.Exception.Message -ErrorId 'InvalidTenantId' -Category InvalidArgument
        return
    }
    Write-Verbose "Filtering baselines to tenant ID $resolvedTenantId..."
    if ($resolvedTenantId -is [string]) {
        $filterPredicate = {
            param($p)
            if ("$($p.PSObject.Properties['baselineMsTenantId'].Value)" -eq $resolvedTenantId) { return $true }
            foreach ($m in @($p.PSObject.Properties['members'].Value)) {
                if ($m -is [PSObject] -and "$($m.PSObject.Properties['msTenantId'].Value)" -eq $resolvedTenantId) { return $true }
            }
            $false
        }
    } else {
        $filterPredicate = {
            param($p)
            $ownerProp = $p.PSObject.Properties['baselineClientTenantId']
            if ($ownerProp -and [int]$ownerProp.Value -eq $resolvedTenantId) { return $true }
            $membersProp = $p.PSObject.Properties['members']
            if ($membersProp -and $membersProp.Value -is [object[]]) {
                foreach ($m in $membersProp.Value) {
                    if ($m -is [PSObject]) {
                        $cid = $m.PSObject.Properties['clientTenantId'].Value
                        if ($null -ne $cid -and [int]$cid -eq $resolvedTenantId) { return $true }
                    }
                }
            }
            $false
        }
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
            $null = Add-InforcerPropertyAliases -InputObject $item -ObjectType Baseline
            $item.PSObject.TypeNames.Insert(0, 'InforcerCommunity.Baseline')
        }
    }
} elseif ($result -is [PSObject]) {
    $null = Add-InforcerPropertyAliases -InputObject $result -ObjectType Baseline
    $result.PSObject.TypeNames.Insert(0, 'InforcerCommunity.Baseline')
}

if ($filterPredicate) {
    $result = Filter-InforcerResponse -InputObject $result -FilterScript $filterPredicate -OutputType PowerShellObject
}

$result
}
