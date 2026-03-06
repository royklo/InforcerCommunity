<#
.SYNOPSIS
    Tests the Inforcer API connection.
.DESCRIPTION
    Makes a test request to the /beta/baselines endpoint to verify the current session and API key work.
    Requires an active session (run Connect-Inforcer first).
.EXAMPLE
    Connect-Inforcer -ApiKey $env:INFORCER_API_KEY -Region uk; Test-InforcerConnection
    Connects then verifies the connection.
.OUTPUTS
    None. Writes success or failure to the host.
.LINK
    Connect-Inforcer
#>
function Test-InforcerConnection {
[CmdletBinding()]
param()

if (-not (Test-InforcerSession)) {
    Write-Error -Message "Not connected. To connect, run: Connect-Inforcer -ApiKey <ApiKey> -Region <uk|eu|us|anz>" `
        -ErrorId 'NotConnected' -Category ConnectionError
    return
}

$uri = $script:InforcerSession.BaseUrl + '/beta/baselines'
$apiKey = ConvertFrom-InforcerSecureString -SecureString $script:InforcerSession.ApiKey

Write-Verbose 'Testing connection...'
Write-Verbose "URI: $uri"
Write-Verbose "API Key (first 8 chars): $($apiKey.Substring(0, [Math]::Min(8, $apiKey.Length)))..."
Write-Verbose "API Key Length: $($apiKey.Length)"

try {
    $headers = @{ 'Inf-Api-Key' = $apiKey; 'Accept' = 'application/json' }
    $null = Invoke-RestMethod -Uri $uri -Method GET -Headers $headers -UseBasicParsing
    Write-Host 'SUCCESS! Connection is working.' -ForegroundColor Green
} catch {
    Write-Host 'FAILED! Connection test failed.' -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Error -Message $_.Exception.Message -ErrorId 'ConnectionTestFailed' -Category ConnectionError
}
}
