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

    try {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($session.ApiKey)
        try {
            $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            $hasKey = -not [string]::IsNullOrWhiteSpace($plain)
        } finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    } catch {
        return $false
    }

    return $hasKey -and -not [string]::IsNullOrWhiteSpace($session.BaseUrl)
}
