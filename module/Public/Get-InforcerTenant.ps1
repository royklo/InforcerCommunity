<#
.SYNOPSIS
    Retrieves tenant information from the Inforcer API.
.DESCRIPTION
    Lists tenants. Optionally filter by -TenantId (Client Tenant ID or Microsoft Tenant ID GUID).
    Output includes PascalCase aliases (e.g. ClientTenantId, TenantFriendlyName). When the API
    returns licenses as an array, it is converted to a comma-separated string in the licenses property.
    PolicyDiff and PolicyDiffFormatted (from recentChanges) show policy change information when available.
.PARAMETER Format
    Output format. Raw = raw API response (default).
.PARAMETER TenantId
    Optional. Filter to this tenant (integer or GUID).
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
        $tenantIdStr = $TenantId.ToString().Trim()
        $parsedInt = 0
        $parsedGuid = [guid]::Empty
        if ([int]::TryParse($tenantIdStr, [ref]$parsedInt)) {
            $singleTenantId = $parsedInt
        } elseif ([guid]::TryParse($tenantIdStr, [ref]$parsedGuid)) {
            try {
                $singleTenantId = Resolve-InforcerTenantId -TenantId $TenantId
            } catch {
                Write-Error -Message $_.Exception.Message -ErrorId 'InvalidTenantId' -Category InvalidArgument
                return
            }
        } else {
            Write-Error -Message 'Invalid TenantId format. Use numeric Client Tenant ID or GUID.' -ErrorId 'InvalidTenantId' -Category InvalidArgument
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
        if ($item -is [PSObject]) { $null = Add-InforcerPropertyAliases -InputObject $item -ObjectType Tenant }
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
