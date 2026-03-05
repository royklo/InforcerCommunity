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
    Optional custom base URL. When set, -Region is ignored. Use a UAT URL (e.g. containing uat or inforcerdev) to connect to UAT; output shows Environment = UAT only when connected to UAT or DEV.
.EXAMPLE
    Connect-Inforcer -ApiKey "your-api-key" -Region uk
.EXAMPLE
    $key = Read-Host -AsSecureString -Prompt "API Key"; Connect-Inforcer -ApiKey $key -Region uk
.EXAMPLE
    Connect-Inforcer -ApiKey $key -BaseUrl "https://REDACTED-UAT/api"
    Connects to UAT; output includes Environment = UAT. Production connections do not show Environment.
.OUTPUTS
    PSObject with Status, Region, BaseUrl, ConnectedAt; Environment is included only when connected to UAT or DEV.
.LINK
    Disconnect-Inforcer
.LINK
    Get-InforcerTenant
#>
function Connect-Inforcer {
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
    [string]$BaseUrl
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

# Validate the API key with a minimal request before reporting Connected
$validateUri = $baseUrlValue.TrimEnd('/') + '/beta/baselines'
$validateHeaders = @{
    'Inf-Api-Key' = $plain
    'Accept'      = 'application/json'
}
try {
    $null = Invoke-RestMethod -Uri $validateUri -Method GET -Headers $validateHeaders -UseBasicParsing
} catch [System.Net.WebException] {
    $statusCode = 0
    if ($_.Exception.Response) { $statusCode = [int]$_.Exception.Response.StatusCode }
    $msg = $_.Exception.Message
    if ($statusCode -eq 401) {
        $msg = 'Connection failed: the API key is invalid for this endpoint. Use a key that matches the environment (e.g. UAT key with UAT URL, production key with production URL).'
    } else {
        $msg = "Connection validation failed (HTTP $statusCode): $msg"
    }
    Write-Error -Message $msg -ErrorId 'ConnectionValidationFailed' -Category AuthenticationError
    return
} catch {
    Write-Error -Message "Connection validation failed: $($_.Exception.Message)" -ErrorId 'ConnectionValidationFailed' -Category AuthenticationError
    return
}

# Derive environment from BaseUrl for display (UAT/DEV vs Production)
$environment = $null
if ($baseUrlValue -match 'uat|inforcerdev') { $environment = 'UAT' }
elseif ($baseUrlValue -match '\bdev\b|\.dev\.') { $environment = 'DEV' }

$script:InforcerSession = @{
    ApiKey      = $secureApiKey
    BaseUrl     = $baseUrlValue
    Region      = $Region
    ConnectedAt = Get-Date
}

Write-Verbose "Successfully connected to Inforcer API at $baseUrlValue $(if ($environment) { "($environment)" } else { '(Production)' })"

$out = [PSCustomObject]@{
    Status      = 'Connected'
    Region      = $Region
    BaseUrl     = $baseUrlValue
    ConnectedAt = $script:InforcerSession.ConnectedAt
}
if ($environment) {
    $out.PSObject.Properties.Add([System.Management.Automation.PSNoteProperty]::new('Environment', $environment))
}
$out
}
