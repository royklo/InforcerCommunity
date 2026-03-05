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

    # When a single TenantId is specified, use GET /beta/tenants/{id} for efficiency
    $singleTenantId = $null
    if ($null -ne $TenantId) {
        $tenantIdStr = $TenantId.ToString().Trim()
        if ($tenantIdStr -match '^\d+$') {
            $singleTenantId = [int]$tenantIdStr
        } elseif ($tenantIdStr -match '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') {
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

    if ($null -ne $singleTenantId) {
        $response = Invoke-InforcerApiRequest -Endpoint "/beta/tenants/$singleTenantId" -Method GET -OutputType $OutputType
        if ($null -eq $response) { return }
        if ($OutputType -eq 'JsonObject') {
            $response
            return
        }
        $result = $response
        if ($result -is [PSObject]) {
            Add-InforcerPropertyAliases -InputObject $result -ObjectType Tenant | Out-Null
        }
        $result
        return
    }

    $response = Invoke-InforcerApiRequest -Endpoint '/beta/tenants' -Method GET -OutputType $OutputType
    if ($null -eq $response) { return }

    # No filter when listing all
    $predicate = $null

    if ($OutputType -eq 'JsonObject') {
        $response
        return
    }

    $result = $response
    if ($result -is [array]) {
        foreach ($item in $result) {
            if ($item -is [PSObject]) {
                Add-InforcerPropertyAliases -InputObject $item -ObjectType Tenant
            }
        }
    } elseif ($result -is [PSObject]) {
        Add-InforcerPropertyAliases -InputObject $result -ObjectType Tenant
    }

    if ($result -is [array]) {
        $result | ForEach-Object { $_ }
    } else {
        $result
    }
}
}
