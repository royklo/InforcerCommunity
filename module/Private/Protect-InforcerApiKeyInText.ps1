function Protect-InforcerApiKeyInText {
    <#
    .SYNOPSIS
        Replaces every occurrence of the live API key in a text string with [REDACTED] (Private helper).
    .DESCRIPTION
        Used by error-message construction in API helpers to ensure that exception text, response
        bodies, and verbose dumps never leak the active subscription key.
    .PARAMETER Text
        The input text — may contain the API key anywhere.
    .PARAMETER ApiKey
        The plain-text API key to redact. If $null/empty, returns the input unchanged.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [string]$Text,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$ApiKey
    )

    if ([string]::IsNullOrWhiteSpace($Text) -or [string]::IsNullOrWhiteSpace($ApiKey)) {
        return $Text
    }
    # No caching here, so a non-compiled regex is faster than building a fresh compiled one
    # per call — compilation cost only amortizes when the regex object is reused.
    [regex]::Replace($Text, [regex]::Escape($ApiKey), '[REDACTED]')
}
