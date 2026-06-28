<#
.SYNOPSIS
    Establishes a secure connection to the Inforcer REST API.
.DESCRIPTION
    Creates an authenticated session using an API key. You can specify -Region (uk, eu, us, anz)
    or -BaseUrl for custom endpoints. The API key is stored as a SecureString.
    Before returning Connected, a minimal API call validates the key; if it fails (e.g. wrong key for the endpoint),
    the connection is not established and an error is returned.
.PARAMETER ApiKey
    The Inforcer API key. Can be SecureString or String (converted to SecureString).
.PARAMETER Region
    Region for production API. Valid: uk, eu, us, anz. Default: uk. Ignored when -BaseUrl is set.
.PARAMETER BaseUrl
    Optional custom base URL. When set, -Region is ignored.
.EXAMPLE
    Connect-Inforcer -ApiKey "your-api-key" -Region uk
.EXAMPLE
    $key = Read-Host -AsSecureString -Prompt "API Key"; Connect-Inforcer -ApiKey $key -Region uk
.EXAMPLE
    Connect-Inforcer -ApiKey $key -BaseUrl "https://api.example.com/api"
    Connects using a custom base URL (use your actual API base URL in place of the example).
.EXAMPLE
    Connect-Inforcer -ApiKey "your-api-key" -Region uk -FetchGraphData
    Connects to Inforcer and also launches Microsoft Graph interactive sign-in for group name resolution.
.PARAMETER FetchGraphData
    Also connect to Microsoft Graph via interactive sign-in. This enables group name resolution
    in Export-InforcerTenantDocumentation. Requires Microsoft.Graph.Authentication module
    (auto-installed if missing).
.PARAMETER PassThru
    When specified, returns the session hashtable to the pipeline in addition to
    storing it in the module-scoped session variable. Use this to capture sessions
    for cross-account comparison with Compare-InforcerEnvironments.
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
    Justification = 'Intentional convenience: users may pass a plain-text API key which is converted to SecureString for storage.')]
[CmdletBinding(SupportsShouldProcess = $true)]
[OutputType([PSObject])]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [Alias('Key')]
    [object]$ApiKey,

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

$rawApiKey = $ApiKey
while ($rawApiKey -is [PSObject] -and $rawApiKey.BaseObject) {
    $rawApiKey = $rawApiKey.BaseObject
}

$secureApiKey = $null
if ($rawApiKey -is [System.Security.SecureString]) {
    $secureApiKey = $rawApiKey
} elseif ($rawApiKey -is [string]) {
    $secureApiKey = ConvertTo-SecureString -String $rawApiKey -AsPlainText -Force
} else {
    Write-Error -Message "ApiKey must be a String or SecureString. Received: $($rawApiKey.GetType().Name)" `
        -ErrorId 'InvalidApiKeyType' -Category InvalidArgument
    return
}

$plain = ConvertFrom-InforcerSecureString -SecureString $secureApiKey
if ([string]::IsNullOrWhiteSpace($plain)) {
    Write-Error -Message 'API key cannot be empty.' -ErrorId 'EmptyApiKey' -Category InvalidArgument
    return
}

try {
    $baseUrlValue = Get-InforcerBaseUrl -Region $Region -BaseUrl $BaseUrl
} catch {
    Write-Error -Message $_.Exception.Message -ErrorId 'InvalidRegion' -Category InvalidArgument
    return
}

if (!$PSCmdlet.ShouldProcess('Inforcer session', 'Connect')) { return }

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
#   * 401 with APIM gateway envelope          → APIM rejected the subscription itself. Real
#                                               auth failure — error out.
#   * Other 4xx/5xx                           → propagate the message.
#
# APIM gateway envelope shape (rejection):   { "statusCode": 401, "message": "Access denied due to invalid subscription key..." }
# Inforcer app envelope shape (scope deny):  { "success": false, "errorCode": "forbidden", "message": "...", "errors": [...] }
$validateHeaders = @{
    'Inf-Api-Key' = $plain
    'Accept'      = 'application/json'
}

$probeUri = $baseUrlValue.TrimEnd('/') + '/beta/baselines'
$probeSucceeded = $false
$probeStatusCode = 0
$probeApiMessage = $null
$probeEnvelope   = 'unknown'    # 'inforcer' | 'apim' | 'unknown'
$probeRawError   = $null

# Use Invoke-WebRequest -SkipHttpErrorCheck (PS7+) so 4xx/5xx don't throw — keeps the
# parent's error stream / -ErrorVariable clean when validation goes through the
# "envelope-shape says key is valid" path even on 403.
try {
    $probeResponse = Invoke-WebRequest -Uri $probeUri -Method GET -Headers $validateHeaders `
        -UseBasicParsing -SkipHttpErrorCheck -ErrorAction Stop
} catch {
    # Only real network errors (DNS, connection refused, TLS) land here; 4xx/5xx are
    # captured via the response object thanks to -SkipHttpErrorCheck.
    $probeRawError = $_
    Write-Error -Message "Connection failed: $($_.Exception.Message)" `
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

# Decide validation outcome from status code AND envelope shape.
$keyValid = switch ($true) {
    $probeSucceeded                                              { $true; break }   # 200 OK
    ($probeStatusCode -eq 403 -and $probeEnvelope -eq 'inforcer'){ $true; break }   # APIM passed, scope denied
    ($probeStatusCode -eq 401 -and $probeEnvelope -eq 'inforcer'){ $true; break }   # Same shape, different code on some routes
    default                                                      { $false }
}

if ($keyValid -and -not $probeSucceeded) {
    Write-Verbose "Key validated against /beta/baselines via $probeEnvelope envelope (HTTP $probeStatusCode). Subscription is active; scope for /beta/baselines is not granted, but the session is established."
}

if (-not $keyValid) {
    $msg = switch ($true) {
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
    Write-Error -Message $msg -ErrorId 'ConnectionValidationFailed' -Category AuthenticationError
    return
}

$script:InforcerSession = @{
    ApiKey      = $secureApiKey
    BaseUrl     = $baseUrlValue
    Region      = $Region
    ConnectedAt = Get-Date
}

Write-Verbose "Successfully connected to Inforcer API at $baseUrlValue"

if ($PassThru) {
    # Return a clone of the session hashtable so callers have an independent copy
    $sessionCopy = @{
        ApiKey      = $script:InforcerSession.ApiKey
        BaseUrl     = $script:InforcerSession.BaseUrl
        Region      = $script:InforcerSession.Region
        ConnectedAt = $script:InforcerSession.ConnectedAt
    }
    Write-Output $sessionCopy
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
