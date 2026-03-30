<#
.SYNOPSIS
    Retrieves tenant information from the Inforcer API.
.DESCRIPTION
    Lists tenants. Optionally filter by -TenantId (numeric ID, Microsoft Tenant ID GUID, or tenant name).
    Output includes PascalCase aliases (e.g. ClientTenantId, TenantFriendlyName). When the API
    returns licenses as an array, it is converted to a comma-separated string in the licenses property.
    PolicyDiff shows policy change information when available.
.PARAMETER Format
    Output format. Raw = raw API response (default).
.PARAMETER TenantId
    Optional. Filter to this tenant (numeric ID, GUID, or tenant name).
.PARAMETER OutputType
    PowerShellObject (default) or JsonObject. JSON output uses Depth 100.
.EXAMPLE
    Get-InforcerTenant
.EXAMPLE
    Get-InforcerTenant -TenantId 482
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
    [Alias('ClientTenantId')]
    [object]$TenantId,

    [Parameter(Mandatory = $false)]
    [ValidateSet('PowerShellObject', 'JsonObject')]
    [string]$OutputType = 'PowerShellObject'
)

process {
    if (-not (Test-InforcerSession)) {
        Write-Error -Message 'Not connected yet. Please run Connect-Inforcer first.' -ErrorId 'NotConnected' -Category ConnectionError
        return
    }

    Write-Verbose 'Retrieving tenant information...'

    # Fetch tenant list once — reuse for both name/GUID resolution and output
    $tenantData = @(Invoke-InforcerApiRequest -Endpoint '/beta/tenants' -Method GET -OutputType PowerShellObject)
    if ($null -eq $tenantData -or $tenantData.Count -eq 0) { return }

    $singleTenantId = $null
    if ($null -ne $TenantId) {
        try {
            $singleTenantId = Resolve-InforcerTenantId -TenantId $TenantId -TenantData $tenantData
        } catch {
            Write-Error -Message $_.Exception.Message -ErrorId 'InvalidTenantId' -Category InvalidArgument
            return
        }
    }

    if ($OutputType -eq 'JsonObject') {
        # Filter PSObjects first, then convert to JSON once — avoids unnecessary serialize/deserialize round-trip
        $jsonData = $tenantData
        if ($null -ne $singleTenantId) {
            $jsonData = @($tenantData | Where-Object {
                $id = $_.clientTenantId
                if ($null -eq $id) { $id = $_.ClientTenantId }
                $null -ne $id -and [int]$id -eq $singleTenantId
            })
            if ($jsonData.Count -eq 0) {
                Write-Error -Message "Tenant or resource not found." -ErrorId 'TenantNotFound' -Category ObjectNotFound
                return
            }
        }
        return ($jsonData | ConvertTo-Json -Depth 100)
    }

    # Force to array (API can return single object or array)
    $all = @($tenantData)
    foreach ($item in $all) {
        if ($item -is [PSObject]) {
            $null = Add-InforcerPropertyAliases -InputObject $item -ObjectType Tenant
            $item.PSObject.TypeNames.Insert(0, 'InforcerCommunity.Tenant')
        }
    }
    # Dedupe by ClientTenantId (aliases already applied above)
    $seen = @{}
    $result = foreach ($item in $all) {
        $id = $item.ClientTenantId
        if ($null -eq $id) { $id = $item.clientTenantId }
        if ($null -eq $id) { $item; continue }
        $idInt = [int]$id
        if ($seen.ContainsKey($idInt)) { continue }
        $seen[$idInt] = $true
        $item
    }
    # Filter to one tenant when -TenantId passed
    if ($null -ne $singleTenantId) {
        $result = @($result) | Where-Object {
            $id = $_.ClientTenantId
            if ($null -eq $id) { $id = $_.clientTenantId }
            $null -ne $id -and [int]$id -eq $singleTenantId
        }
        if (-not $result) {
            Write-Error -Message "Tenant or resource not found." -ErrorId 'TenantNotFound' -Category ObjectNotFound
            return
        }
    }
    $result
}
}
