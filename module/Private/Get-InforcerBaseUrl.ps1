function Get-InforcerBaseUrl {
    <#
    .SYNOPSIS
        Returns the Inforcer API host for a region, or the full request URI for an endpoint (Private helper).
    .DESCRIPTION
        Host mode (-Region / -BaseUrl): maps a region (anz, eu, uk, us) to its API host
        (https://api-{region}.inforcer.com), or normalises -BaseUrl to a host by trimming a
        trailing '/', '/api', '/api/beta' or '/v1'. Both 'https://host' and 'https://host/api' work.

        Endpoint mode (-Endpoint): builds the request URI for the session's API version.
          beta: {BaseUrl}/beta{path}
          v1:   {ApiHost}/v1{path}, with the v1 renames applied:
                /tenants/{id}/roles -> /tenants/{id}/directoryRoles
                /auditEvents/eventTypes -> /auditEvents/types
                query customBaselineId= -> baselineId=
    .PARAMETER Region
        Region code. Valid: anz, eu, uk, us. Ignored when -BaseUrl is set.
    .PARAMETER BaseUrl
        Optional custom host (with or without '/api').
    .PARAMETER Endpoint
        API path, version-neutral (e.g. /tenants/{id}/policies).
    .PARAMETER Session
        Session hashtable for -Endpoint. Defaults to the current session.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Host')]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false, ParameterSetName = 'Host')]
        [ValidateSet('anz', 'eu', 'uk', 'us', IgnoreCase = $true)]
        [string]$Region = 'uk',

        [Parameter(Mandatory = $false, ParameterSetName = 'Host')]
        [string]$BaseUrl,

        [Parameter(Mandatory = $true, ParameterSetName = 'Endpoint')]
        [string]$Endpoint,

        [Parameter(Mandatory = $false, ParameterSetName = 'Endpoint')]
        [hashtable]$Session = $script:InforcerSession
    )

    if ($PSCmdlet.ParameterSetName -eq 'Endpoint') {
        if (-not $Session) { throw [System.InvalidOperationException]::new('Not connected. Run Connect-Inforcer first.') }
        $path = $Endpoint.Trim()
        if (-not $path.StartsWith('/')) { $path = '/' + $path }

        if ($Session.ApiVersion -eq 'v1') {
            $apiHost = $Session.ApiHost
            if ([string]::IsNullOrWhiteSpace($apiHost)) { $apiHost = $Session.BaseUrl -replace '/api/?$', '' }
            $path = $path -replace '^(/tenants/[^/?]+)/roles(?=/|\?|$)', '$1/directoryRoles'
            $path = $path -replace '^/auditEvents/eventTypes(?=/|\?|$)', '/auditEvents/types'
            $path = $path -replace '([?&])customBaselineId=', '${1}baselineId='
            return $apiHost.TrimEnd('/') + '/v1' + $path
        }
        return $Session.BaseUrl.TrimEnd('/') + '/beta' + $path
    }

    if (-not [string]::IsNullOrWhiteSpace($BaseUrl)) {
        return ($BaseUrl.Trim().TrimEnd('/') -replace '(?i)(/api(/beta)?|/v1)$', '')
    }

    $regionMap = @{
        'anz' = 'https://api-anz.inforcer.com'
        'eu'  = 'https://api-eu.inforcer.com'
        'uk'  = 'https://api-uk.inforcer.com'
        'us'  = 'https://api-us.inforcer.com'
    }

    $apiHostForRegion = $regionMap[$Region.ToLowerInvariant()]
    if ($apiHostForRegion) {
        return $apiHostForRegion
    }

    throw [System.ArgumentException]::new(
        "Invalid region: $Region. Valid regions are: anz, eu, uk, us.",
        'Region'
    )
}
