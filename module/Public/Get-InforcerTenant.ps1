<#
.SYNOPSIS
    Retrieves tenant information from the Inforcer API.

    Required API scope(s): Tenants.Read
.DESCRIPTION
    Lists tenants. Optionally filter by -TenantId (numeric ID, Microsoft Tenant ID GUID, or tenant name).
    When the API returns licenses as an array, it is converted to a comma-separated string in the
    licenses property. PolicyDiff shows policy change information when available.

    API-key login: the list already holds every tenant field (ClientTenantId, licenses, SecureScore,
    IsBaseline, tags, alignmentSummaries, ...), so -Detailed changes nothing.
    Client-credentials login: the list holds only TenantFriendlyName, TenantDnsName and MsTenantId.
    -Detailed, or -TenantId, loads each tenant's full record (licenses, SecureScore, IsBaseline, tags,
    alignmentSummaries, LastBackupTimestamp, AuthenticationMode) with one extra call per tenant.
    -TenantId <GUID> makes that one call only; a name is first resolved from the session's tenant list.

    ClientTenantId does not exist with client credentials; use MsTenantId or the tenant name.
.PARAMETER Format
    Output format. Raw = raw API response (default).
.PARAMETER TenantId
    Optional. Return this tenant only, with its full record. Accepts the Microsoft Tenant ID (GUID),
    the tenant name or DNS name, or (API-key login only) the numeric Client Tenant ID.
.PARAMETER Detailed
    Load the full record of every tenant. Client-credentials login only; with an API key the list is
    already complete and the switch is ignored, so scripts work with both logins.
.PARAMETER OutputType
    PowerShellObject (default) or JsonObject. JSON output uses Depth 100.
.EXAMPLE
    Get-InforcerTenant
.EXAMPLE
    Get-InforcerTenant -TenantId 482
    API-key login: returns the tenant with Client Tenant ID 482.
.EXAMPLE
    Get-InforcerTenant -TenantId 'Contoso'
    Returns the tenant named Contoso with its full record (works with both logins).
.EXAMPLE
    Get-InforcerTenant -Detailed | Where-Object IsBaseline
    Lists baseline tenants. With client credentials -Detailed is needed for IsBaseline.
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
    [switch]$Detailed,

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
        $tenantData = @(Get-InforcerTenantList -Refresh:(-not $listRefreshed))
        $listRefreshed = $true
        if ($tenantData.Count -eq 0) { return }
    }

    if ($null -eq $TenantId -and $isV1 -and $Detailed) {
        $seenIds = @{}
        $unique = @(foreach ($t in $tenantData) {
            $id = $t.PSObject.Properties['msTenantId'].Value
            if ($null -eq $id -or $seenIds.ContainsKey("$id")) { continue }
            $seenIds["$id"] = $true
            $t
        })
        $details = [System.Collections.Generic.List[object]]::new($unique.Count)
        for ($i = 0; $i -lt $unique.Count; $i++) {
            $t = $unique[$i]
            $name = $t.PSObject.Properties['tenantFriendlyName'].Value
            Write-Progress -Activity 'Loading tenant details' -Status "$($i + 1) of $($unique.Count): $name" -PercentComplete ([int](100 * $i / $unique.Count))
            $detailErr = $null
            $detail = Invoke-InforcerApiRequest -Endpoint "/tenants/$($t.msTenantId)" -Method GET -ObjectType Tenant -ErrorAction SilentlyContinue -ErrorVariable detailErr
            if ($null -eq $detail) {
                $reason = if ($detailErr) { $detailErr[-1].Exception.Message } else { 'empty response' }
                Write-Warning "Could not load details for tenant '$name'; returning its summary. $reason"
                $detail = $t
            }
            $details.Add($detail)
        }
        Write-Progress -Activity 'Loading tenant details' -Completed
        $tenantData = $details.ToArray()
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
