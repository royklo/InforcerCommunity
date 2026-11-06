function Get-InforcerTenantList {
    <#
    .SYNOPSIS
        Returns the tenant list with canonical property names, cached per session (Private helper).
    .DESCRIPTION
        beta: GET /tenants (rich objects incl. clientTenantId). v1: GET /tenants (the same fields
        without clientTenantId), mapped to the beta property names. Cached in $script:InforcerTenantListCache
        for the session that fetched it, so swapping sessions (Compare-InforcerEnvironments) never
        returns another account's tenants. Cleared with the other Inforcer*Cache* variables on
        Connect/Disconnect. A failed request is not cached; its error goes to the error stream.
    .PARAMETER Refresh
        Ignore the cache and fetch again.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$Refresh
    )

    $session = $script:InforcerSession
    $cache = $script:InforcerTenantListCache
    if (-not $Refresh -and $cache -and $session -and [object]::ReferenceEquals($cache.Session, $session)) {
        return $cache.Tenants
    }

    $requestErrors = $null
    $tenants = @(Invoke-InforcerApiRequest -Endpoint '/tenants' -Method GET -ObjectType Tenant -ErrorVariable requestErrors)
    if (-not $requestErrors -and $session) {
        $script:InforcerTenantListCache = @{ Session = $session; Tenants = $tenants }
    }
    $tenants
}
