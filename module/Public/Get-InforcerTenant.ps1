<#
.SYNOPSIS
    Retrieves tenant information from the Inforcer API.

    Required API scope(s): Tenants.Read (API key); Tenants permission (API client, unconfirmed).
.DESCRIPTION
    Lists tenants. Optionally filter by -TenantId (numeric ID, Microsoft Tenant ID GUID, or tenant name).
    When the API returns licenses as an array, it is converted to a comma-separated string in the
    licenses property. PolicyDiff shows policy change information when available.

    The list holds every tenant field (licenses, SecureScore, IsBaseline, tags, alignmentSummaries, ...)
    with both logins. Client-credentials login: -TenantId loads the tenant's own record, which adds
    AuthenticationMode; -TenantId <GUID> makes that one call only, a name is first resolved from the
    session's tenant list. With client credentials -OutputType JsonObject is always a JSON array, also
    for one tenant.

    ClientTenantId does not exist with client credentials; use MsTenantId or the tenant name.
.PARAMETER Format
    Output format. Raw = raw API response (default).
.PARAMETER TenantId
    Optional. Return this tenant only. Accepts the Microsoft Tenant ID (GUID), the tenant name or
    DNS name, or (API-key login only) the numeric Client Tenant ID.
.PARAMETER OutputType
    PowerShellObject (default) or JsonObject. JSON output uses Depth 100.
.EXAMPLE
    Get-InforcerTenant
.EXAMPLE
    Get-InforcerTenant -TenantId 102   # API key only (numeric Client Tenant ID)
    API-key login: returns the tenant with Client Tenant ID 102.
.EXAMPLE
    Get-InforcerTenant -TenantId 'Contoso'
    Returns the tenant named Contoso (works with both logins).
.EXAMPLE
    Get-InforcerTenant | Where-Object IsBaseline
    Lists baseline tenants.
.EXAMPLE
    Get-InforcerTenant -Format Raw -OutputType JsonObject
.OUTPUTS
    PSObject or String (when -OutputType JsonObject)
.LINK
    https://github.com/royklo/InforcerCommunity/blob/main/docs/CMDLET-REFERENCE.md#get-inforcertenant
.LINK
    Connect-Inforcer
#>
function Get-InforcerTenant {
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

begin {
    $listRefreshed = $false
}

process {
    if (-not (Test-InforcerSession)) {
        Write-Error -Message 'Not connected yet. Please run Connect-Inforcer first.' -ErrorId 'NotConnected' -Category ConnectionError
        return
    }

    Write-Verbose 'Retrieving tenant information...'
    $isV1 = $script:InforcerSession.ApiVersion -eq 'v1'

    # Get-InforcerTenantList objects are a shared cache: filter and copy them, never modify them.
    if ($null -ne $TenantId) {
        try {
            $singleTenantId = Resolve-InforcerTenantId -TenantId $TenantId -ErrorAction Stop
        } catch {
            Write-Error -Message $_.Exception.Message -ErrorId 'InvalidTenantId' -Category InvalidArgument
            return
        }
        if ($isV1) {
            # The v1 record is fetched by id; the list is only needed to resolve a name.
            $detailErr = $null
            $detail = Invoke-InforcerApiRequest -Endpoint "/tenants/$singleTenantId" -Method GET -ObjectType Tenant -ErrorAction SilentlyContinue -ErrorVariable detailErr
            if ($null -eq $detail) {
                if (-not $detailErr -or $detailErr[-1].FullyQualifiedErrorId -like 'ApiRequestFailed_404*') {
                    Write-Error -Message "Tenant or resource not found." -ErrorId 'TenantNotFound' -Category ObjectNotFound
                } else {
                    Write-Error -ErrorRecord $detailErr[-1]
                }
                return
            }
            $tenantData = @($detail)
        } else {
            $pick = {
                param($list)
                foreach ($t in $list) {
                    $id = $t.PSObject.Properties['clientTenantId'].Value
                    if ($null -ne $id -and [int]$id -eq $singleTenantId) { $t }
                }
            }
            # Fresh once per call (piped tenants reuse it), so the returned record is never stale.
            $tenantData = @(& $pick @(Get-InforcerTenantList -Refresh:(-not $listRefreshed)))
            $listRefreshed = $true
            if ($tenantData.Count -eq 0) {
                Write-Error -Message "Tenant or resource not found." -ErrorId 'TenantNotFound' -Category ObjectNotFound
                return
            }
        }
    } else {
        $listErr = $null
        $tenantData = @(Get-InforcerTenantList -Refresh:(-not $listRefreshed) -ErrorVariable listErr)
        $listRefreshed = $true
        # A failed request returns nothing; an empty v1 list is still `[]` in JSON.
        if ($listErr -or ($tenantData.Count -eq 0 -and -not ($isV1 -and $OutputType -eq 'JsonObject'))) { return }
    }

    if ($OutputType -eq 'JsonObject') {
        if ($isV1) { return ConvertTo-Json -InputObject $tenantData -Depth 100 }
        return ($tenantData | ConvertTo-Json -Depth 100)
    }

    $idProperty = if ($isV1) { 'msTenantId' } else { 'clientTenantId' }
    $seen = @{}
    foreach ($item in $tenantData) {
        if ($item -isnot [PSObject]) { $item; continue }
        $id = $item.PSObject.Properties[$idProperty].Value
        if ($null -ne $id) {
            $key = if ($isV1) { "$id" } else { [int]$id }
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
        }
        $copy = [ordered]@{}
        foreach ($p in $item.PSObject.Properties) { $copy[$p.Name] = $p.Value }
        $out = [PSCustomObject]$copy
        $null = Add-InforcerPropertyAliases -InputObject $out -ObjectType Tenant
        $out.PSObject.TypeNames.Insert(0, 'InforcerCommunity.Tenant')
        $out
    }
}
}
