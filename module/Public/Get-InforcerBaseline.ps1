<#
.SYNOPSIS
    Retrieves baseline information from the Inforcer API.

    Required API scope(s): Baselines.Read + Tenants.Read (only when -TenantId is a GUID or tenant name)
    (API key); Baselines + Tenants (only for a tenant name) permission (API client, unconfirmed).
.DESCRIPTION
    Retrieves baseline groups and members. Optionally filter by -TenantId (owner or member).
    API-key login: the owner is identified by BaselineClientTenantId and members by ClientTenantId.
    Client-credentials login: those numeric ids do not exist; the owner is BaselineMsTenantId and
    members carry MsTenantId.
    Piped tenants (Get-InforcerTenant | Get-InforcerBaseline): the baselines are fetched once, each
    baseline is returned once per piped tenant it belongs to with that tenant in TenantId, and
    -OutputType JsonObject returns one JSON array.
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
    Get-InforcerBaseline -TenantId 'Contoso'
    Baselines owned by, or including, the tenant named Contoso (both logins).
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

begin { $requestedTenantIds = [System.Collections.Generic.List[object]]::new() }
process { $requestedTenantIds.Add($TenantId) }
end {
$piped = $PSCmdlet.MyInvocation.ExpectingInput
if ($piped -and $requestedTenantIds.Count -eq 0) { return }

if (-not (Test-InforcerSession)) {
    Write-Error -Message 'Not connected yet. Please run Connect-Inforcer first.' -ErrorId 'NotConnected' -Category ConnectionError
    return
}

Write-Verbose 'Retrieving baseline information...'
$isV1 = $script:InforcerSession.ApiVersion -eq 'v1'

# One fetch per call, also when tenants are piped. The list is shared with the session cache: copy before decorating.
$listErr = $null
$baselines = @(Get-InforcerBaselineList -Refresh -ErrorVariable listErr)
if ($listErr) { return }

$hasTenant = {
    param($p, $tid)
    if ($tid -is [string]) {
        if ("$($p.PSObject.Properties['baselineMsTenantId'].Value)" -eq $tid) { return $true }
        foreach ($m in @($p.PSObject.Properties['members'].Value)) {
            if ($m -is [PSObject] -and "$($m.PSObject.Properties['msTenantId'].Value)" -eq $tid) { return $true }
        }
        return $false
    }
    $ownerProp = $p.PSObject.Properties['baselineClientTenantId']
    if ($ownerProp -and [int]$ownerProp.Value -eq $tid) { return $true }
    $membersProp = $p.PSObject.Properties['members']
    if ($membersProp -and $membersProp.Value -is [object[]]) {
        foreach ($m in $membersProp.Value) {
            if ($m -is [PSObject]) {
                $cid = $m.PSObject.Properties['clientTenantId'].Value
                if ($null -ne $cid -and [int]$cid -eq $tid) { return $true }
            }
        }
    }
    $false
}

$copyOf = {
    param($b)
    $copy = [ordered]@{}
    foreach ($prop in $b.PSObject.Properties) { $copy[$prop.Name] = $prop.Value }
    [PSCustomObject]$copy
}

$decorate = {
    param($b)
    $null = Add-InforcerPropertyAliases -InputObject $b -ObjectType Baseline
    $b.PSObject.TypeNames.Insert(0, 'InforcerCommunity.Baseline')
    $b
}

if (-not $piped) {
    $resolvedTenantId = $null
    if ($null -ne $requestedTenantIds[0]) {
        try {
            $resolvedTenantId = Resolve-InforcerTenantId -TenantId $requestedTenantIds[0] -ErrorAction Stop
        } catch {
            Write-Error -Message $_.Exception.Message -ErrorId 'InvalidTenantId' -Category InvalidArgument
            return
        }
        Write-Verbose "Filtering baselines to tenant ID $resolvedTenantId..."
    }

    if ($OutputType -eq 'JsonObject') {
        if ($isV1) {
            # v1 list contract: always a JSON array, also for one match or none.
            $selected = @(foreach ($b in $baselines) { if ($null -eq $resolvedTenantId -or ($b -is [PSObject] -and (& $hasTenant $b $resolvedTenantId))) { $b } })
            return ConvertTo-Json -InputObject $selected -Depth 100
        }
        $json = $baselines | ConvertTo-Json -Depth 100
        if ($null -eq $json) { return }
        if ($null -eq $resolvedTenantId) { return $json }
        return Filter-InforcerResponse -InputObject $json -FilterScript { param($p) & $hasTenant $p $resolvedTenantId } -OutputType JsonObject
    }

    if ($baselines.Count -eq 0) { return }
    $result = @(foreach ($b in $baselines) { if ($b -is [PSObject]) { & $decorate (& $copyOf $b) } else { $b } })
    if ($null -ne $resolvedTenantId) {
        $result = Filter-InforcerResponse -InputObject $result -FilterScript { param($p) & $hasTenant $p $resolvedTenantId } -OutputType PowerShellObject
    }
    return $result
}

# Piped tenants: one row per (tenant, baseline), carrying the tenant in TenantId.
$rows = [System.Collections.Generic.List[object]]::new()
$seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($requested in $requestedTenantIds) {
    $resolvedTenantId = $null
    if ($null -ne $requested) {
        try {
            $resolvedTenantId = Resolve-InforcerTenantId -TenantId $requested -ErrorAction Stop
        } catch {
            Write-Error -Message $_.Exception.Message -ErrorId 'InvalidTenantId' -Category InvalidArgument
            continue
        }
    }
    foreach ($b in $baselines) {
        if ($b -isnot [PSObject]) { continue }
        if ($null -ne $resolvedTenantId -and -not (& $hasTenant $b $resolvedTenantId)) { continue }
        if (-not $seen.Add("$resolvedTenantId|$($b.PSObject.Properties['id'].Value)")) { continue }
        $row = & $copyOf $b
        if ($null -ne $resolvedTenantId -and -not $row.PSObject.Properties['TenantId']) {
            $row.PSObject.Properties.Add([System.Management.Automation.PSNoteProperty]::new('TenantId', $resolvedTenantId))
        }
        $rows.Add($row)
    }
}

if ($OutputType -eq 'JsonObject') {
    return ConvertTo-Json -InputObject @($rows) -Depth 100
}
foreach ($row in $rows) { & $decorate $row }
}
}
