function Test-InforcerReportRunTerminal {
    <#
    .SYNOPSIS
        Probes GET /reports/runs/{id}/outputs once to determine if a run is terminal (Private helper).
    .DESCRIPTION
        Per API contract (both API versions):
          * 200 → run is terminal; outputs are returned (downloadable)
          * 404 → run is not terminal yet (or doesn't exist — see note)

        beta wraps the outputs as { data: { outputs: [...] } }; v1 returns { outputs: [...] } with
        msTenantId, which is mapped to the module's tenantId (null for a collated output).
        A v1 401 renews the access token and retries once; a v1 429 waits for Retry-After (at most 3 times).

        Used as the polling probe by Get-InforcerReportRun -Wait. Returns a typed result rather
        than throwing on the "not yet" case, so polling loops can branch cleanly.

        Note: a 404 alone cannot distinguish "run pending" from "run-id invalid". This helper
        treats any 404 as "not terminal yet" — the caller's timeout loop is what catches a
        bogus run id (it times out instead of completing). Run-id format validation happens
        client-side via [guid]::TryParse before this is called. On v1 a 404 also means the run
        lies outside the API client's tenant scope.
    .PARAMETER RunId
        The run identifier (GUID) returned from POST /reports/runs.
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

    $uri = Get-InforcerBaseUrl -Endpoint ('/reports/runs/{0}/outputs' -f $RunId)
    $isV1 = $script:InforcerSession.ApiVersion -eq 'v1'

    Write-Verbose "Probing terminal state: GET $uri"

    $forceRefresh = $false
    $retries429 = 0
    while ($true) {
        $headers = Get-InforcerAuthHeader -ForceRefresh:$forceRefresh
        if (-not $headers) { return }
        $headers['Accept'] = 'application/json'

        try {
            $response = Invoke-WebRequest -Uri $uri -Method GET -Headers $headers -SkipHttpErrorCheck -UseBasicParsing -MaximumRedirection 0 -Debug:$false -Verbose:$false -ErrorAction Ignore
        } catch {
            Clear-InforcerRequestCredential -ErrorRecord $_
            $msg = Protect-InforcerApiKeyInText -Text $_.Exception.Message
            Write-Error -Message "Failed to probe run terminal state: $msg" `
                -ErrorId 'ProbeFailed' -Category ConnectionError
            return
        }
        if ($isV1 -and -not $forceRefresh -and [int]$response.StatusCode -eq 401) {
            Write-Verbose 'HTTP 401: renewing the access token and retrying once.'
            $forceRefresh = $true
            continue
        }
        if ($isV1 -and [int]$response.StatusCode -eq 429 -and $retries429 -lt 3) {
            $retries429++
            $delay = Get-InforcerRetryDelay -Value (Get-InforcerHeaderValue -Headers $response.Headers -Name 'Retry-After') -Attempt $retries429
            Write-Verbose "Rate limited (HTTP 429). Retrying in $delay second(s) (attempt $retries429 of 3)."
            Start-Sleep -Seconds $delay
            continue
        }
        break
    }

    $statusCode    = [int]$response.StatusCode
    if ($statusCode -ge 300 -and $statusCode -lt 400) {
        Write-Error -Message (Get-InforcerRedirectMessage -StatusCode $statusCode -Headers $response.Headers) -ErrorId "ProbeFailed_$statusCode" -Category ConnectionError
        return
    }
    $correlationId = Get-InforcerHeaderValue -Headers $response.Headers -Name 'x-correlation-id'
    if ($correlationId) {
        Write-Verbose "x-correlation-id: $correlationId"
    }

    if ($statusCode -eq 200) {
        # beta: { data: { outputs: [...] }, success: true, ... }; v1: { outputs: [...] }.
        # Unwrap: response → (.data →) .outputs (the array of output records).
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
        if ($isV1 -and $outputs.Count -gt 0) {
            $outputs = @(ConvertFrom-InforcerV1Response -InputObject $outputs -ObjectType ReportOutput)
        }
        foreach ($o in $outputs) {
            if ($o -is [PSObject] -and -not $o.PSObject.Properties['runId']) { $o | Add-Member -NotePropertyName 'runId' -NotePropertyValue $RunId.ToString() }
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
            $titleProp = $json.PSObject.Properties['title']
            if ($msgProp) {
                $detail = $msgProp.Value -as [string]
            } elseif ($titleProp) {
                $detail = $titleProp.Value -as [string]
                $problemDetail = $json.PSObject.Properties['detail'].Value -as [string]
                if ($problemDetail -and $problemDetail -ne $detail) { $detail = "${detail}: $problemDetail" }
            }
        } catch {
            Write-Verbose 'Error response body was not JSON; using raw content.'
        }
    }
    if ([string]::IsNullOrWhiteSpace($detail)) { $detail = "HTTP $statusCode" }
    $detail = Protect-InforcerApiKeyInText -Text $detail
    $errMsg = "Failed to probe run '$RunId': $detail"
    if ($correlationId) { $errMsg = "$errMsg [correlation-id: $correlationId]" }
    Write-Error -Message $errMsg -ErrorId "ProbeFailed_$statusCode" -Category ConnectionError
}
