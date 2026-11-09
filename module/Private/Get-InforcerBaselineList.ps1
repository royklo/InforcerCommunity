function Get-InforcerBaselineList {
    <#
    .SYNOPSIS
        Returns the baseline list with canonical property names, cached per session (Private helper).
    .DESCRIPTION
        GET /baselines (v1 mapped to the module names). Cached in $script:InforcerBaselineListCache for the
        session that fetched it, like Get-InforcerTenantList, and cleared with the other Inforcer*Cache*
        variables on Connect/Disconnect. A failed request is not cached; its error goes to the error stream.
        The objects are shared: callers read them and copy before decorating.
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
    $cache = $script:InforcerBaselineListCache
    if (-not $Refresh -and $cache -and $session -and [object]::ReferenceEquals($cache.Session, $session)) {
        return $cache.Baselines
    }

    $requestErrors = $null
    $baselines = @(Invoke-InforcerApiRequest -Endpoint '/baselines' -Method GET -ObjectType Baseline -ErrorVariable requestErrors)
    if (-not $requestErrors -and $session) {
        $script:InforcerBaselineListCache = @{ Session = $session; Baselines = $baselines }
    }
    $baselines
}
