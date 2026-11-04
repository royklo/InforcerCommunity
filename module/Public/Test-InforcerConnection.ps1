<#
.SYNOPSIS
    Tests the Inforcer API connection.

    Required API scope(s): Baselines.Read (API key); Baselines permission (API client, unconfirmed).
    A credential without it makes the test return $false.
.DESCRIPTION
    Makes a test request to the baselines endpoint to verify the current session and its credential
    (API key or API client) work, and returns $true or $false so the result can be used as a condition.

    Failures are reported as warnings rather than errors, so `Test-InforcerConnection -ErrorAction Stop`
    still answers the question instead of throwing.
.EXAMPLE
    Connect-Inforcer -ClientId $clientId -ClientSecret $secret -Region uk; Test-InforcerConnection
    Connects then verifies the connection.
.EXAMPLE
    if (-not (Test-InforcerConnection)) { Connect-Inforcer -ClientId $clientId -ClientSecret $secret -Region uk }
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
    Write-Warning 'Not connected. To connect, run: Connect-Inforcer -ClientId <ClientId> -ClientSecret <ClientSecret> -Region <uk|eu|us|anz>'
    return $false
}

Write-Verbose "Testing connection to $(Get-InforcerBaseUrl -Endpoint '/baselines')..."

$requestErrors = $null
$null = Invoke-InforcerApiRequest -Endpoint '/baselines' -Method GET -ErrorAction SilentlyContinue -ErrorVariable requestErrors
if (-not $requestErrors) {
    Write-Host 'SUCCESS! Connection is working.' -ForegroundColor Green
    return $true
}

$reason = $requestErrors[-1].Exception.Message
Write-Host 'FAILED! Connection test failed.' -ForegroundColor Red
Write-Host "Error: $reason" -ForegroundColor Red
Write-Warning "Inforcer connection test failed: $reason"
return $false
}
