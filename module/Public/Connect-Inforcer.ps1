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
    [switch]$FetchGraphData
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
} catch {
    # Parse response body from PS7 (ErrorDetails) or PS5.1 (WebException)
    $statusCode = 0
    $apiMessage = $null
    if ($_.Exception -is [System.Net.WebException] -and $_.Exception.Response) {
        $statusCode = [int]$_.Exception.Response.StatusCode
    }
    if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
        try {
            $json = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($json) {
                if ($json.PSObject.Properties['statusCode']) { $statusCode = [int]$json.statusCode }
                $apiMessage = $json.PSObject.Properties['message'].Value -as [string]
            }
        } catch { }
    }
    $msg = switch ($true) {
        ($statusCode -eq 401) { 'Connection failed: the API key is invalid for this endpoint.' }
        ($statusCode -eq 429 -or $statusCode -eq 403 -and $apiMessage -match 'quota|rate.?limit|throttl') {
            if ($apiMessage) { "API rate limit: $apiMessage" } else { 'API rate limit exceeded. Please wait and try again.' }
        }
        default {
            if ($apiMessage) { "Connection validation failed: $apiMessage" } else { "Connection validation failed: $($_.Exception.Message)" }
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
