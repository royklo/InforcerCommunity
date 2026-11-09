function Protect-InforcerApiKeyInText {
    <#
    .SYNOPSIS
        Replaces every credential in a text string with [REDACTED] (Private helper).
    .DESCRIPTION
        Used by error-message construction in API helpers so exception text, response bodies and
        verbose dumps never leak a credential. Redacts:
          * the -ApiKey value, when given
          * the session's API key, client secret and access token
          * any bearer token or JWT-shaped string
    .PARAMETER Text
        The input text.
    .PARAMETER ApiKey
        Optional plain-text secret not (yet) stored in the session, e.g. during the token request.
    .PARAMETER Session
        Session whose secrets are redacted. Defaults to the current session.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [string]$Text,

        [Parameter(Mandatory = $false, Position = 1)]
        [string]$ApiKey,

        [Parameter(Mandatory = $false)]
        [hashtable]$Session = $script:InforcerSession
    )

    if ([string]::IsNullOrWhiteSpace($Text)) { return $Text }

    $secrets = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($ApiKey)) { $secrets.Add($ApiKey) }
    if ($Session) {
        foreach ($name in 'ApiKey', 'ClientSecret', 'AccessToken') {
            $value = $Session[$name]
            if ($value -is [System.Security.SecureString] -and $value.Length -gt 0) {
                $secrets.Add([System.Net.NetworkCredential]::new('', $value).Password)
            }
        }
    }
    foreach ($s in $secrets) { $Text = $Text.Replace($s, '[REDACTED]') }
    $Text = [regex]::Replace($Text, '(?i)\bbearer\s+[A-Za-z0-9\-._~+/]+=*', 'Bearer [REDACTED]')
    [regex]::Replace($Text, '\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*', '[REDACTED]')
}
