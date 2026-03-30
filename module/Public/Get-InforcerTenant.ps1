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

    $singleTenantId = $null
    if ($null -ne $TenantId) {
        try {
            $singleTenantId = Resolve-InforcerTenantId -TenantId $TenantId
        } catch {
            Write-Error -Message $_.Exception.Message -ErrorId 'InvalidTenantId' -Category InvalidArgument
            return
        }
    }

    # Always use list endpoint then filter by TenantId when specified (single-tenant GET can return full list)
    $response = Invoke-InforcerApiRequest -Endpoint '/beta/tenants' -Method GET -OutputType $OutputType
    if ($null -eq $response) { return }

    if ($OutputType -eq 'JsonObject') {
        if ($null -ne $singleTenantId) {
            $obj = $response | ConvertFrom-Json
            $arr = if ($obj -is [array]) { @($obj) } else { @($obj) }
            $filtered = @($arr | Where-Object {
                $id = $_.clientTenantId
                if ($null -eq $id) { $id = $_.ClientTenantId }
                $id -ne $null -and [int]$id -eq $singleTenantId
            })
            if ($filtered.Count -eq 0) {
                Write-Error -Message "Tenant or resource not found." -ErrorId 'TenantNotFound' -Category ObjectNotFound
                return
            }
            ($filtered | ConvertTo-Json -Depth 100)
        } else {
            $response
        }
        return
    }

    # Force to array (API can return single object or array)
    $all = @($response)
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
