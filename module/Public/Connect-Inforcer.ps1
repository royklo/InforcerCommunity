<#
.SYNOPSIS
    Establishes a secure connection to the inforcer REST API.
.DESCRIPTION
    Two ways to log in; the API version follows from the login:
      * -ClientId / -ClientSecret (OAuth client credentials) uses the current v1 API. The connection is
        validated by requesting an access token; the token is renewed automatically before it expires.
      * -ApiKey uses the legacy beta API. API keys are due to be retired by inforcer, so this login shows
        a warning. Before returning Connected, a minimal API call validates the key; an expired, revoked
        or invalid key is refused. A valid key that lacks the probe endpoint's scope still connects.
    You can specify -Region (uk, eu, us, anz) or -BaseUrl for a custom host. Secrets and tokens are
    stored only as SecureString.
.PARAMETER ApiKey
    The inforcer API key (legacy beta API). Can be SecureString or String (converted to SecureString).
.PARAMETER ClientId
    The client ID of an inforcer API client (v1 API). Create one in the inforcer portal under
    Configure > REST API.
.PARAMETER ClientSecret
    The client secret of the API client. Can be SecureString or String (converted to SecureString).
.PARAMETER Region
    Region for production API. Valid: uk, eu, us, anz. Default: uk. Ignored when -BaseUrl is set.
.PARAMETER BaseUrl
    Optional custom API host, with or without '/api' (e.g. https://api.example.com or
    https://api.example.com/api). When set, -Region is ignored.
.EXAMPLE
    Connect-Inforcer -ClientId $clientId -ClientSecret (Read-Host -AsSecureString -Prompt 'Client secret') -Region uk
    Connects with an API client (v1 API).
.EXAMPLE
    Connect-Inforcer -ApiKey "your-api-key" -Region uk
    Connects with a legacy API key (beta API).
.EXAMPLE
    $key = Read-Host -AsSecureString -Prompt "API Key"; Connect-Inforcer -ApiKey $key -Region uk
.EXAMPLE
    Connect-Inforcer -ApiKey $key -BaseUrl "https://api.example.com/api"
    Connects using a custom base URL (use your actual API base URL in place of the example).
.EXAMPLE
    Connect-Inforcer -ApiKey "your-api-key" -Region uk -FetchGraphData
    Connects to inforcer and also launches Microsoft Graph interactive sign-in for group name resolution.
.PARAMETER FetchGraphData
    Also connect to Microsoft Graph via interactive sign-in. This enables group name resolution
    in Export-InforcerTenantDocumentation. Requires Microsoft.Graph.Authentication module
    (auto-installed if missing).
.PARAMETER PassThru
    When specified, returns the session hashtable to the pipeline in addition to
    storing it in the module-scoped session variable. Use this to capture sessions
    for cross-account comparison with Compare-InforcerEnvironments. Secrets and tokens in it
    are SecureStrings.
.OUTPUTS
    PSObject with Status, Region, BaseUrl, ConnectedAt.
.LINK
    https://github.com/royklo/InforcerCommunity/blob/main/docs/CMDLET-REFERENCE.md#connect-inforcer
.LINK
    Disconnect-Inforcer
.LINK
    Get-InforcerTenant
#>
function Connect-Inforcer {
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Intentional convenience: users may pass a plain-text API key or client secret which is converted to SecureString for storage.')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'ClientSecret',
    Justification = 'Accepts SecureString or String; a String is converted to SecureString immediately.')]
[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'ApiKey')]
[OutputType([PSObject])]
param(
    [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'ApiKey')]
    [Alias('Key')]
    [object]$ApiKey,

    [Parameter(Mandatory = $true, ParameterSetName = 'ClientCredentials')]
    [ValidateNotNullOrEmpty()]
    [string]$ClientId,

    [Parameter(Mandatory = $true, ParameterSetName = 'ClientCredentials')]
    [object]$ClientSecret,

    [Parameter(Mandatory = $false, Position = 1)]
    [ValidateSet('anz', 'eu', 'uk', 'us', IgnoreCase = $true)]
    [string]$Region = 'uk',

    [Parameter(Mandatory = $false)]
    [string]$BaseUrl,

    [Parameter(Mandatory = $false)]
    [switch]$FetchGraphData,

    [Parameter(Mandatory = $false)]
    [switch]$PassThru
)

$isClientCredentials = $PSCmdlet.ParameterSetName -eq 'ClientCredentials'
$credentialLabel = if ($isClientCredentials) { 'ClientSecret' } else { 'ApiKey' }

$rawSecret = if ($isClientCredentials) { $ClientSecret } else { $ApiKey }
while ($rawSecret -is [PSObject] -and $rawSecret.BaseObject) {
    $rawSecret = $rawSecret.BaseObject
}

$secureSecret = $null
if ($rawSecret -is [System.Security.SecureString]) {
    $secureSecret = $rawSecret
} elseif ($rawSecret -is [string]) {
    $secureSecret = ConvertTo-SecureString -String $rawSecret -AsPlainText -Force
} else {
    $typeName = if ($null -eq $rawSecret) { 'null' } else { $rawSecret.GetType().Name }
    Write-Error -Message "$credentialLabel must be a String or SecureString. Received: $typeName" `
        -ErrorId $(if ($isClientCredentials) { 'InvalidClientSecretType' } else { 'InvalidApiKeyType' }) -Category InvalidArgument
    return
}
$rawSecret = $null

if ($secureSecret.Length -eq 0 -or [string]::IsNullOrWhiteSpace((ConvertFrom-InforcerSecureString -SecureString $secureSecret))) {
    if ($isClientCredentials) {
        Write-Error -Message 'Client secret cannot be empty.' -ErrorId 'EmptyClientSecret' -Category InvalidArgument
    } else {
        Write-Error -Message 'API key cannot be empty.' -ErrorId 'EmptyApiKey' -Category InvalidArgument
    }
    return
}

try {
    $apiHost = Get-InforcerBaseUrl -Region $Region -BaseUrl $BaseUrl
} catch {
    Write-Error -Message $_.Exception.Message -ErrorId 'InvalidRegion' -Category InvalidArgument
    return
}

if (!$PSCmdlet.ShouldProcess('Inforcer session', 'Connect')) { return }

if ($isClientCredentials) {
    $newSession = @{
        AuthMode     = 'ClientCredentials'
        ApiVersion   = 'v1'
        ApiHost      = $apiHost
        BaseUrl      = $apiHost
        Region       = $Region
        ClientId     = $ClientId
        ClientSecret = $secureSecret
    }
    # Validation = a successful token request. No scope probe: any valid client connects, whatever it may read.
    $token = Get-InforcerAccessToken -ApiHost $apiHost -ClientId $ClientId -ClientSecret $secureSecret
    if ($token.Error) {
        Write-Error -Message "Connection failed: $($token.Error)" -ErrorId 'ConnectionValidationFailed' -Category AuthenticationError
        return
    }
    $newSession['AccessToken'] = $token.AccessToken
    $newSession['TokenExpiresAt'] = $token.ExpiresAt
    $baseUrlValue = $apiHost
} else {
    $baseUrlValue = $apiHost + '/api'
    $newSession = @{
        AuthMode   = 'ApiKey'
        ApiVersion = 'beta'
        ApiHost    = $apiHost
        BaseUrl    = $baseUrlValue
        Region     = $Region
        ApiKey     = $secureSecret
    }

    # Validate the API key with a minimal request before reporting Connected.
    #
    # Validation principle: Connect-Inforcer must accept ANY valid key regardless of scope.
    # We pick /beta/baselines as a probe target because it's a common endpoint, but the result
    # is interpreted by RESPONSE SHAPE, not just status code:
    #
    #   * 200                                     → key valid, full scope for this endpoint
    #   * 4xx with Inforcer-app error envelope    → key valid; APIM accepted the subscription,
    #                                               the Inforcer app rejected the scope. That's
    #                                               proof the subscription works.
    #   * 4xx whose errors[] names a key-lifecycle
    #     problem ("API key has expired")         → key itself is dead, not a scope gap. Error out.
    #   * 401 with APIM gateway envelope          → APIM rejected the subscription itself. Real
    #                                               auth failure — error out.
    #   * Other 4xx/5xx                           → propagate the message.
    #
    # APIM gateway envelope shape (rejection):   { "statusCode": 401, "message": "Access denied due to invalid subscription key..." }
    # Inforcer app envelope shape (scope deny):  { "success": false, "errorCode": "forbidden", "message": "...", "errors": [...] }
    $validateHeaders = Get-InforcerAuthHeader -Session $newSession
    $validateHeaders['Accept'] = 'application/json'

    $probeUri = Get-InforcerBaseUrl -Endpoint '/baselines' -Session $newSession
    $probeSucceeded = $false
    $probeStatusCode = 0
    $probeApiMessage = $null
    $probeErrorsText = $null        # errors[] only, without the generic top-level message
    $probeEnvelope   = 'unknown'    # 'inforcer' | 'apim' | 'unknown'
    $probeRawError   = $null

    # Use Invoke-WebRequest -SkipHttpErrorCheck (PS7+) so 4xx/5xx don't throw — keeps the
    # parent's error stream / -ErrorVariable clean when validation goes through the
    # "envelope-shape says key is valid" path even on 403.
    try {
        # -TimeoutSec 10 prevents Connect from hanging indefinitely on slow networks / proxies /
        # captive portals. The probe is just a GET on /beta/baselines, so 10s is generous.
        $probeResponse = Invoke-WebRequest -Uri $probeUri -Method GET -Headers $validateHeaders `
            -UseBasicParsing -SkipHttpErrorCheck -Verbose:$false -Debug:$false -TimeoutSec 10 -ErrorAction Stop
    } catch {
        # Only real network errors (DNS, connection refused, TLS) land here; 4xx/5xx are
        # captured via the response object thanks to -SkipHttpErrorCheck.
        $probeRawError = $_
        Write-Error -Message "Connection failed: $(Protect-InforcerApiKeyInText -Text $_.Exception.Message -Session $newSession)" `
            -ErrorId 'ConnectionValidationFailed' -Category ConnectionError
        return
    }

    $probeStatusCode = [int]$probeResponse.StatusCode
    if ($probeStatusCode -ge 200 -and $probeStatusCode -lt 300) {
        $probeSucceeded = $true
    } else {
        $bodyText = if ($probeResponse.Content -is [byte[]]) {
            [System.Text.Encoding]::UTF8.GetString($probeResponse.Content)
        } else {
            $probeResponse.Content -as [string]
        }
        $json = $null
        if ($bodyText) {
            try { $json = $bodyText | ConvertFrom-Json -ErrorAction Stop } catch { $json = $null }
        }
        if ($json) {
            $msgProp = $json.PSObject.Properties['message']
            if ($msgProp) { $probeApiMessage = $msgProp.Value -as [string] }

            # errors[] carries the actionable detail ("API key has expired."); the top-level
            # message is the generic auth placeholder ("A valid API key is required to access
            # this endpoint.") that the API also emits for plain scope denials. Kept in its own
            # variable because the key-lifecycle test below must read errors[] ONLY — see there.
            $errorsProp = $json.PSObject.Properties['errors']
            if ($errorsProp) {
                $probeErrorsText = Format-InforcerErrorDetail -Errors $errorsProp.Value
                if (-not [string]::IsNullOrWhiteSpace($probeErrorsText)) {
                    if ([string]::IsNullOrWhiteSpace($probeApiMessage)) { $probeApiMessage = $probeErrorsText }
                    elseif ($probeApiMessage -notlike "*$probeErrorsText*") { $probeApiMessage = "$probeApiMessage — $probeErrorsText" }
                }
            }

            # Envelope detection: Inforcer app responses carry success / errorCode / errors;
            # APIM gateway responses only carry statusCode + message (no Inforcer markers).
            $hasInforcerMarkers = $json.PSObject.Properties['success'] -or `
                                  $json.PSObject.Properties['errorCode'] -or `
                                  $json.PSObject.Properties['errors']
            $isApimShape       = $json.PSObject.Properties['statusCode'] -and `
                                 $json.PSObject.Properties['message'] -and `
                                 (-not $hasInforcerMarkers) -and `
                                 (-not $json.PSObject.Properties['data'])
            if ($hasInforcerMarkers) { $probeEnvelope = 'inforcer' }
            elseif ($isApimShape)   { $probeEnvelope = 'apim' }
        }
    }

    # An expired / revoked / disabled key comes back in the SAME Inforcer app envelope as a
    # scope denial — measured against a live environment with an expired key, right down to
    # errorCode 'forbidden', which a scope denial also returns:
    #
    #   403 {"data":null,"errorCode":"forbidden","success":false,
    #        "message":"A valid API key is required to access this endpoint.",
    #        "errors":["API key has expired."]}
    #
    # So neither status code, envelope shape nor errorCode can tell "your key is dead" (must
    # not connect) from "your key lacks THIS scope" (must connect — see the validation
    # principle above). The API has no key-introspection endpoint and no way to read a key's
    # scopes, so errors[] is the only signal that exists.
    #
    # Read errors[] ONLY, never the joined message: the top-level "A valid API key is required
    # to access this endpoint." is the generic auth placeholder the API also serves for plain
    # scope denials, so matching it would lock out every narrow-scope key — exactly the
    # any-scope-connects rule this cmdlet exists to protect.
    $keyRejected = $probeErrorsText -match 'expired|revoked|deactivated|disabled|not active'

    # Decide validation outcome from status code AND envelope shape.
    $keyValid = switch ($true) {
        $probeSucceeded                                              { $true; break }   # 200 OK
        $keyRejected                                                 { $false; break }  # key itself is dead
        ($probeStatusCode -eq 403 -and $probeEnvelope -eq 'inforcer'){ $true; break }   # APIM passed, scope denied
        ($probeStatusCode -eq 401 -and $probeEnvelope -eq 'inforcer'){ $true; break }   # Same shape, different code on some routes
        default                                                      { $false }
    }

    if ($keyValid -and -not $probeSucceeded) {
        Write-Verbose "Key validated against /beta/baselines via $probeEnvelope envelope (HTTP $probeStatusCode). Subscription is active; scope for /beta/baselines is not granted, but the session is established."
        # Say this out loud rather than only under -Verbose. Connecting on a denied probe is
        # correct — a Reports.Read-only key is a legitimate caller — but the key's scopes are
        # unverified, so 'Connected' promises less here than it does after a 200. Without this
        # line the next cmdlet's 403 looks like the session lied.
        Write-Warning ('Connected, but the key''s scopes could not be verified: the probe on /beta/baselines returned HTTP {0}. The API subscription is live and the key is not expired. If a cmdlet now fails with 403, the key is missing that endpoint''s scope.' -f $probeStatusCode)
    }

    if (-not $keyValid) {
        $msg = switch ($true) {
            $keyRejected {
                "Connection failed: $($probeApiMessage.TrimEnd('.')). Generate a new API key in the Inforcer portal."
                break
            }
            ($probeStatusCode -eq 401 -and $probeEnvelope -eq 'apim') {
                if ($probeApiMessage) { "Connection failed: $probeApiMessage" }
                else { 'Connection failed: the API subscription key is invalid (APIM gateway rejection). Verify the key in the Inforcer portal.' }
                break
            }
            ($probeStatusCode -eq 429 -or ($probeStatusCode -eq 403 -and $probeApiMessage -match 'quota|rate.?limit|throttl')) {
                if ($probeApiMessage) { "API rate limit: $probeApiMessage" } else { 'API rate limit exceeded. Please wait and try again.' }
                break
            }
            ($probeStatusCode -eq 401) {
                if ($probeApiMessage) { "Connection failed: $probeApiMessage" }
                else { 'Connection failed: the API key was rejected.' }
                break
            }
            default {
                if ($probeApiMessage) { "Connection validation failed: $probeApiMessage" }
                elseif ($probeRawError) { "Connection validation failed: $($probeRawError.Exception.Message)" }
                else { 'Connection validation failed.' }
            }
        }
        Write-Error -Message (Protect-InforcerApiKeyInText -Text $msg -Session $newSession) -ErrorId 'ConnectionValidationFailed' -Category AuthenticationError
        return
    }
}

# Clear stale caches from any prior session before establishing the new one. This catches
# the denial sentinels ($script:InforcerAssessmentCacheDeniedAt, ...) that would otherwise
# persist after a re-key — a user who reconnects with a higher-scope key shouldn't still
# see "scope required" hints from the previous one. Uses the same wildcard pattern that
# Disconnect-Inforcer uses, so any future Inforcer*Cache* var is included automatically.
$cacheVarsToClear = Get-Variable -Scope Script -Name 'Inforcer*Cache*' -ErrorAction SilentlyContinue
if ($cacheVarsToClear) {
    $cacheVarsToClear | Clear-Variable -Scope Script -Force -ErrorAction SilentlyContinue
    Write-Verbose ('Cleared {0} stale cache variable(s) before establishing new session.' -f $cacheVarsToClear.Count)
}

$newSession['ConnectedAt'] = Get-Date
$script:InforcerSession = $newSession

Write-Verbose "Successfully connected to Inforcer API at $baseUrlValue ($($newSession.ApiVersion) API)"
if (-not $isClientCredentials) {
    Write-Warning ('You connected with an API key, which uses inforcer''s legacy beta API. API keys are due to be retired. ' +
        'Switch to an API client: create one in the inforcer portal (Configure > REST API), then run ' +
        'Connect-Inforcer -ClientId <client id> -ClientSecret <client secret> -Region ' + $Region + '. ' +
        'With an API client, pass the Microsoft tenant ID (GUID) or tenant name instead of the numeric tenant id.')
}

# Best-effort prime of the Reports catalog cache so Get-InforcerReportType /
# Invoke-InforcerReport argument completers show the live key list on the very
# first TAB. Silent on any failure (key may lack Reports.Read, transient network,
# rate limit) — the cmdlets re-prime on first invocation via Resolve-InforcerReportTypeSchema.
# Skip prime when cache is already populated (cache-clear above runs first, so reaching
# here with populated cache means a defensive condition we shouldn't overwrite).
$skipPrime = $false
if ($script:InforcerReportTypeCache -and @($script:InforcerReportTypeCache).Count -gt 0) {
    Write-Verbose 'Reports catalog cache already populated — skipping prime.'
    $skipPrime = $true
}
if (-not $skipPrime) { try {
    $catalogHeaders = Get-InforcerAuthHeader -Session $newSession
    $catalogHeaders['Accept'] = 'application/json'
    $catalogProbe = Invoke-WebRequest -Uri (Get-InforcerBaseUrl -Endpoint '/reports/types' -Session $newSession) `
        -Method GET -Headers $catalogHeaders -UseBasicParsing -SkipHttpErrorCheck -Verbose:$false -Debug:$false `
        -TimeoutSec 4 -ErrorAction Stop
    if ([int]$catalogProbe.StatusCode -ge 200 -and [int]$catalogProbe.StatusCode -lt 300) {
        $catalogJson = if ($catalogProbe.Content -is [byte[]]) {
            [System.Text.Encoding]::UTF8.GetString($catalogProbe.Content)
        } else { $catalogProbe.Content -as [string] }
        if ($catalogJson) {
            $parsed = $catalogJson | ConvertFrom-Json -Depth 100 -ErrorAction Stop
            $entries = if ($isClientCredentials) {
                $listProp = $parsed.PSObject.Properties['reportTypes']
                @(ConvertFrom-InforcerV1Response -InputObject @($(if ($listProp) { $listProp.Value })) -ObjectType ReportType)
            } else {
                $dataProp = $parsed.PSObject.Properties['data']
                if ($dataProp) { @($dataProp.Value) } else { @($parsed) }
            }
            if ($entries.Count -gt 0) {
                $script:InforcerReportTypeCache = $entries
                $script:InforcerReportTypeCacheStamp = Get-Date
                Write-Verbose "Primed Reports catalog cache ($($entries.Count) types) for argument completion."
            }
        }
    } else {
        Write-Verbose "Skipping Reports catalog prime: HTTP $([int]$catalogProbe.StatusCode) (missing Reports read permission)."
    }
} catch {
    Write-Verbose "Skipping Reports catalog prime: $(Protect-InforcerApiKeyInText -Text $_.Exception.Message -Session $newSession)"
} } # end of if (-not $skipPrime) wrapper

if ($PassThru) {
    # An independent copy; secrets and tokens in it are SecureStrings only.
    Write-Output $script:InforcerSession.Clone()
}

# Also connect to Microsoft Graph if requested
if ($FetchGraphData) {
    Write-Host 'Connecting to Microsoft Graph...' -ForegroundColor Cyan
    $graphCtx = Connect-InforcerGraph -RequiredScopes @('Directory.Read.All')
    if ($graphCtx) {
        Write-Host "  Graph connected as: $($graphCtx.Account)" -ForegroundColor Green
    }
}

$out = [PSCustomObject]@{
    Status      = 'Connected'
    Region      = $Region
    BaseUrl     = $baseUrlValue
    ConnectedAt = $script:InforcerSession.ConnectedAt
}
$out
}
