<#
.SYNOPSIS
    Tests the Inforcer API connection.
.DESCRIPTION
    Makes a test request to the /beta/baselines endpoint to verify the current session and API key
    work, and returns $true or $false so the result can be used as a condition.

    Failures are reported as warnings rather than errors, so `Test-InforcerConnection -ErrorAction Stop`
    still answers the question instead of throwing.
.EXAMPLE
    Connect-Inforcer -ApiKey $env:INFORCER_API_KEY -Region uk; Test-InforcerConnection
    Connects then verifies the connection.
.EXAMPLE
    if (-not (Test-InforcerConnection)) { Connect-Inforcer -ApiKey $key -Region uk }
    Reconnects only when the current session is dead.
.OUTPUTS
    System.Boolean. $true when the API responded, $false when it did not or there is no session.
    Status messages go to the host; failures to the warning stream and details to verbose.
.LINK
    https://github.com/royklo/InforcerCommunity/blob/main/docs/CMDLET-REFERENCE.md#test-inforcerconnection
.LINK
    Connect-Inforcer
#>
function Test-InforcerConnection {
[CmdletBinding()]
[OutputType([bool])]
param()

if (-not (Test-InforcerSession)) {
    Write-Warning 'Not connected. To connect, run: Connect-Inforcer -ApiKey <ApiKey> -Region <uk|eu|us|anz>'
    return $false
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
    return $true
} catch {
    Write-Host 'FAILED! Connection test failed.' -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Warning "Inforcer connection test failed: $($_.Exception.Message)"
    return $false
}
}
