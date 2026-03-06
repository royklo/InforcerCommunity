function ConvertFrom-InforcerSecureString {
    <#
    .SYNOPSIS
        Converts a SecureString to plain text (Private helper).
    .DESCRIPTION
        Used by Connect-Inforcer, Test-InforcerConnection, and Invoke-InforcerApiRequest
        to obtain the API key for HTTP requests. Callers should use the result immediately
        and avoid storing it in long-lived variables.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Security.SecureString]$SecureString
    )
    if (-not $SecureString) { return '' }
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}
