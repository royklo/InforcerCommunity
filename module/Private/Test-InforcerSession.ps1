function Test-InforcerSession {
    <#
    .SYNOPSIS
        Verifies that an Inforcer API session is active.
    .DESCRIPTION
        True when the session has a host (ApiHost or BaseUrl) and a non-empty credential:
        an ApiKey (API-key login, beta API) or a ClientSecret (client-credentials login, v1 API).
        Used by all data cmdlets before making API calls. Does not throw.
    .PARAMETER Session
        Session hashtable to test. Defaults to the current session.
    .OUTPUTS
        System.Boolean - True if session is valid, false otherwise.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $false)]
        [hashtable]$Session = $script:InforcerSession
    )

    if (-not $Session) { return $false }

    $hasHost = -not [string]::IsNullOrWhiteSpace($Session.ApiHost) -or -not [string]::IsNullOrWhiteSpace($Session.BaseUrl)
    if (-not $hasHost) { return $false }

    $credential = if ($Session.ApiVersion -eq 'v1') { $Session.ClientSecret } else { $Session.ApiKey }
    return ($null -ne $credential -and $credential.Length -gt 0)
}
