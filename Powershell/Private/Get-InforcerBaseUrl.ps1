function Get-InforcerBaseUrl {
    <#
    .SYNOPSIS
        Returns the Inforcer API base URL for a region or custom URL.
    .DESCRIPTION
        Maps region codes (anz, eu, uk, us) to production API URLs, or returns
        the provided -BaseUrl when specified.
    .PARAMETER Region
        Region code. Valid: anz, eu, uk, us. Ignored when -BaseUrl is set.
    .PARAMETER BaseUrl
        Optional custom base URL. When set, this is returned (trimmed, no trailing slash).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet('anz', 'eu', 'uk', 'us', IgnoreCase = $true)]
        [string]$Region = 'uk',

        [Parameter(Mandatory = $false)]
        [string]$BaseUrl
    )

    if (-not [string]::IsNullOrWhiteSpace($BaseUrl)) {
        return $BaseUrl.Trim().TrimEnd('/')
    }

    $regionMap = @{
        'anz' = 'https://api-anz.inforcer.com/api'
        'eu'  = 'https://api-eu.inforcer.com/api'
        'uk'  = 'https://api-uk.inforcer.com/api'
        'us'  = 'https://api-us.inforcer.com/api'
    }

    $key = $regionMap[$Region.ToLowerInvariant()]
    if ($key) {
        return $key
    }

    throw [System.ArgumentException]::new(
        "Invalid region: $Region. Valid regions are: anz, eu, uk, us.",
        'Region'
    )
}
