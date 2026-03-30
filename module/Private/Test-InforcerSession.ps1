function Test-InforcerSession {
    <#
    .SYNOPSIS
        Verifies that an Inforcer API session is active.
    .DESCRIPTION
        Checks that $script:InforcerSession exists and has a non-empty ApiKey and BaseUrl.
        Used by all data cmdlets before making API calls. Does not throw.
    .OUTPUTS
        System.Boolean - True if session is valid, false otherwise.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if (-not $script:InforcerSession) {
        return $false
    }

    $session = $script:InforcerSession
    if (-not $session.ApiKey -or -not $session.BaseUrl) {
        return $false
    }

    return ($session.ApiKey.Length -gt 0) -and -not [string]::IsNullOrWhiteSpace($session.BaseUrl)
}
