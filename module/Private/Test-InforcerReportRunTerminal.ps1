function Test-InforcerReportRunTerminal {
    <#
    .SYNOPSIS
        Probes GET /beta/reports/runs/{id}/outputs once to determine if a run is terminal (Private helper).
    .DESCRIPTION
        Per API contract:
          * 200 → run is terminal; outputs are returned (downloadable)
          * 404 → run is not terminal yet (or doesn't exist — see note)

        Used as the polling probe by Get-InforcerReportRun -Wait. Returns a typed result rather
        than throwing on the "not yet" case, so polling loops can branch cleanly.

        Note: a 404 alone cannot distinguish "run pending" from "run-id invalid". This helper
        treats any 404 as "not terminal yet" — the caller's timeout loop is what catches a
        bogus run id (it times out instead of completing). Run-id format validation happens
        client-side via [guid]::TryParse before this is called.
    .PARAMETER RunId
        The run identifier (GUID) returned from POST /beta/reports/runs.
    .OUTPUTS
        PSCustomObject with members:
          RunId          — the run identifier (string form of the guid)
          IsTerminal     — boolean
          Outputs        — the parsed outputs array (when IsTerminal=$true), else $null
          CorrelationId  — x-correlation-id of this probe, or $null
          StatusCode     — raw HTTP status code (int)
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [guid]$RunId
    )

    if (-not (Test-InforcerSession)) {
        Write-Error -Message 'Not connected. Run Connect-Inforcer first.' `
            -ErrorId 'NotConnected' -Category ConnectionError
        return
    }

    $apiKey = ConvertFrom-InforcerSecureString -SecureString $script:InforcerSession.ApiKey
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        Write-Error -Message 'API key is empty or invalid. Please reconnect.' `
            -ErrorId 'EmptyApiKey' -Category AuthenticationError
        return
    }

    $uri = $script:InforcerSession.BaseUrl + ('/beta/reports/runs/{0}/outputs' -f $RunId)
    $headers = @{
        'Inf-Api-Key' = $apiKey
        'Accept'      = 'application/json'
    }

    Write-Verbose "Probing terminal state: GET $uri"

    try {
        $response = Invoke-WebRequest -Uri $uri -Method GET -Headers $headers -SkipHttpErrorCheck -UseBasicParsing -ErrorAction Stop
    } catch {
        $msg = Protect-InforcerApiKeyInText -Text $_.Exception.Message -ApiKey $apiKey
        Write-Error -Message "Failed to probe run terminal state: $msg" `
            -ErrorId 'ProbeFailed' -Category ConnectionError
        return
    }

    $statusCode    = [int]$response.StatusCode
    $correlationId = Get-InforcerHeaderValue -Headers $response.Headers -Name 'x-correlation-id'
    if ($correlationId) {
        Write-Verbose "x-correlation-id: $correlationId"
    }

    if ($statusCode -eq 200) {
        # Response shape (confirmed): { data: { outputs: [...] }, success: true, message, errors }
        # Unwrap: response → .data → .outputs (the array of output records).
        $outputs = @()
        if ($response.Content) {
            try {
                $body = $response.Content | ConvertFrom-Json -Depth 100 -ErrorAction Stop
                $unwrapped = $body
                $dataProp = $body.PSObject.Properties['data']
                if ($dataProp -and $null -ne $dataProp.Value) { $unwrapped = $dataProp.Value }
                if ($unwrapped -is [PSObject]) {
                    $outputsProp = $unwrapped.PSObject.Properties['outputs']
                    if ($outputsProp -and $null -ne $outputsProp.Value) {
                        $outputs = @($outputsProp.Value)
                    } elseif ($unwrapped -is [array]) {
                        $outputs = @($unwrapped)
                    }
                } elseif ($unwrapped -is [array]) {
                    $outputs = @($unwrapped)
                }
            } catch {
                Write-Verbose '200 response was not JSON-parseable; returning empty outputs.'
            }
        }
        return [PSCustomObject]@{
            RunId         = $RunId.ToString()
            IsTerminal    = $true
            Outputs       = $outputs
            CorrelationId = $correlationId
            StatusCode    = $statusCode
        }
    }

    if ($statusCode -eq 404) {
        return [PSCustomObject]@{
            RunId         = $RunId.ToString()
            IsTerminal    = $false
            Outputs       = $null
            CorrelationId = $correlationId
            StatusCode    = $statusCode
        }
    }

    # Any other status is an error worth surfacing — parse the body for a useful message.
    $detail = $response.Content
    if ($detail) {
        try {
            $json = $response.Content | ConvertFrom-Json -ErrorAction Stop
            $msgProp = $json.PSObject.Properties['message']
            if ($msgProp) { $detail = $msgProp.Value -as [string] }
        } catch {
            Write-Verbose 'Error response body was not JSON; using raw content.'
        }
    }
    if ([string]::IsNullOrWhiteSpace($detail)) { $detail = "HTTP $statusCode" }
    $errMsg = "Failed to probe run '$RunId': $detail"
    if ($correlationId) { $errMsg = "$errMsg [correlation-id: $correlationId]" }
    Write-Error -Message $errMsg -ErrorId "ProbeFailed_$statusCode" -Category ConnectionError
}
