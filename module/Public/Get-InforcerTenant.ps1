<#
.SYNOPSIS
    Retrieves tenant information from the Inforcer API.
.DESCRIPTION
    Lists tenants. Optionally filter by -TenantId (numeric ID, Microsoft Tenant ID GUID, or tenant name).
    Output includes PascalCase aliases (e.g. ClientTenantId, TenantFriendlyName). When the API
    returns licenses as an array, it is converted to a comma-separated string in the licenses property.
    PolicyDiff and PolicyDiffFormatted (from recentChanges) show policy change information when available.
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
    Connect-Inforcer
#>
function Get-InforcerTenant {
[CmdletBinding()]
[OutputType([PSObject], [string])]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Raw')]
    [string]$Format = 'Raw',

    [Parameter(Mandatory = $false, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
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
        if ($item -is [PSObject]) { Add-InforcerPropertyAliases -InputObject $item -ObjectType Tenant | Out-Null }
    }
    # Dedupe by ClientTenantId
    $seen = @{}
    $result = $all | Where-Object {
        $id = $_.ClientTenantId; if ($null -eq $id) { $id = $_.clientTenantId }
        if ($null -eq $id) { return $true }
        $id = [int]$id
        if ($seen[$id]) { return $false }
        $seen[$id] = $true
        $true
    }
    # Filter to one tenant when -TenantId passed
    if ($null -ne $singleTenantId) {
        $result = $result | Where-Object {
            $id = $_.ClientTenantId; if ($null -eq $id) { $id = $_.clientTenantId }
            $null -ne $id -and [int]$id -eq $singleTenantId
        }
        if (-not $result) {
            Write-Error -Message "Tenant or resource not found." -ErrorId 'TenantNotFound' -Category ObjectNotFound
            return
        }
    }
    $result | ForEach-Object { $_ }
}
}
