function Get-InforcerAuthHeader {
    <#
    .SYNOPSIS
        Returns the authentication header for an Inforcer session (Private helper).
    .DESCRIPTION
        The only place the Inforcer auth header is built.
          API-key session (beta):            @{ 'Inf-Api-Key' = <key> }
          Client-credentials session (v1):   @{ Authorization = 'Bearer <token>' }
        For v1 the access token is requested when missing and renewed when less than five minutes
        remain; the new token and expiry are written back into the session hashtable.
        On failure it writes one error (NotConnected, EmptyApiKey or TokenRequestFailed) and returns
        nothing, so callers do: $h = Get-InforcerAuthHeader; if (-not $h) { return }
    .PARAMETER Session
        Session hashtable. Defaults to the current session.
    .PARAMETER ForceRefresh
        v1 only: request a new token even when the current one has not expired (used after a 401).
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory = $false)]
        [hashtable]$Session = $script:InforcerSession,

        [Parameter(Mandatory = $false)]
        [switch]$ForceRefresh
    )

    if (-not $Session) {
        Write-Error -Message 'Not connected. Run Connect-Inforcer first.' -ErrorId 'NotConnected' -Category ConnectionError
        return
    }

    if ($Session.ApiVersion -eq 'v1') {
        $expiresAt = $Session.TokenExpiresAt -as [datetime]
        if ($ForceRefresh -or -not $Session.AccessToken -or -not $expiresAt -or $expiresAt -lt [datetime]::UtcNow.AddMinutes(5)) {
            $token = Get-InforcerAccessToken -ApiHost $Session.ApiHost -ClientId $Session.ClientId -ClientSecret $Session.ClientSecret
            if ($token.Error) {
                Write-Error -Message $token.Error -ErrorId 'TokenRequestFailed' -Category AuthenticationError
                return
            }
            $Session.AccessToken = $token.AccessToken
            $Session.TokenExpiresAt = $token.ExpiresAt
        }
        return @{ Authorization = 'Bearer ' + (ConvertFrom-InforcerSecureString -SecureString $Session.AccessToken) }
    }

    $apiKey = if ($Session.ApiKey -is [System.Security.SecureString]) { ConvertFrom-InforcerSecureString -SecureString $Session.ApiKey }
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        Write-Error -Message 'API key is empty or invalid. Please reconnect.' -ErrorId 'EmptyApiKey' -Category AuthenticationError
        return
    }
    @{ 'Inf-Api-Key' = $apiKey }
}

function Get-InforcerAccessToken {
    <#
    .SYNOPSIS
        Requests an OAuth client-credentials access token for the v1 API (Private helper).
    .DESCRIPTION
        POST {ApiHost}/oauth/token (form-encoded). Returns AccessToken (SecureString), ExpiresAt (UTC)
        and Error. On failure AccessToken is $null and Error holds a clean message that never contains
        the secret. Writes no errors itself, so the caller decides how to report.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
        Justification = 'The token arrives as plain text from the token endpoint and is stored only as a SecureString.')]
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ApiHost,

        [Parameter(Mandatory = $true)]
        [string]$ClientId,

        [Parameter(Mandatory = $true)]
        [System.Security.SecureString]$ClientSecret
    )

    $secret = ConvertFrom-InforcerSecureString -SecureString $ClientSecret
    $request = @{
        Uri         = $ApiHost.TrimEnd('/') + '/oauth/token'
        Method      = 'POST'
        Body        = @{ grant_type = 'client_credentials'; client_id = $ClientId; client_secret = $secret }
        ContentType = 'application/x-www-form-urlencoded'
        Headers     = @{ Accept = 'application/json' }
        TimeoutSec  = 30
    }

    $errorText = $null
    $response = $null
    try {
        $result = Invoke-InforcerHttpRequest -Request $request
        $response = $result.Body
        if ($result.StatusCode -ge 400) {
            $json = $response
            if ($json -is [string]) { try { $json = $json | ConvertFrom-Json -Depth 100 -ErrorAction Stop } catch { $json = $null } }
            $reason = $null
            if ($json -is [System.Management.Automation.PSCustomObject]) {
                $parts = foreach ($n in 'title', 'detail', 'error', 'error_description') {
                    $v = $json.PSObject.Properties[$n].Value -as [string]
                    if (-not [string]::IsNullOrWhiteSpace($v)) { $v.Trim().TrimEnd('.') }
                }
                $reason = @($parts | Select-Object -Unique) -join ': '
            }
            if ([string]::IsNullOrWhiteSpace($reason)) { $reason = [string][System.Net.HttpStatusCode]$result.StatusCode }
            $hint = if ($result.StatusCode -in 400, 401) { ' Check the client ID and secret, and that the client is active and not expired.' } else { '' }
            $errorText = "Token request failed (HTTP $($result.StatusCode)): $reason.$hint"
        }
    } catch {
        $errorText = "Token request failed: $($_.Exception.Message)"
    }

    $accessToken = $null
    if (-not $errorText) {
        $accessToken = $response.PSObject.Properties['access_token'].Value -as [string]
        if ([string]::IsNullOrWhiteSpace($accessToken)) { $errorText = 'Token request failed: the response contained no access_token.' }
    }
    if ($errorText) {
        return [PSCustomObject]@{ AccessToken = $null; ExpiresAt = $null; Error = (Protect-InforcerApiKeyInText -Text $errorText -ApiKey $secret -Session @{}) }
    }

    $lifetime = $response.PSObject.Properties['expires_in'].Value -as [int]
    if ($null -eq $lifetime -or $lifetime -le 0) { $lifetime = 3600 }

    [PSCustomObject]@{
        AccessToken = ConvertTo-SecureString -String $accessToken -AsPlainText -Force
        ExpiresAt   = [datetime]::UtcNow.AddSeconds($lifetime)
        Error       = $null
    }
}
