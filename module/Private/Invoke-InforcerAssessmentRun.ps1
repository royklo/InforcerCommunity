function Invoke-InforcerAssessmentRun {
    <#
    .SYNOPSIS
        Runs a single assessment against one tenant (internal helper).
    .DESCRIPTION
        Executes POST /tenants/{id}/assessments/{id}/runs in a separate runspace so the caller can
        show progress. The URI and auth header are built here with Get-InforcerBaseUrl and
        Get-InforcerAuthHeader (fresh per run, so a long multi-tenant loop never reuses an expired
        v1 token) and handed to the runspace as parameters; the runspace never sees the session.
        v1 only, like Invoke-InforcerApiRequest: a 429 waits for Retry-After (at most 3 times) and a
        401 renews the token once and retries. beta fails on the first HTTP error, as before.
        Redirects are never followed, so the key or token is never sent to another address.
        Returns the raw API response data (beta: .data; v1: the run object, assessmentId mapped to
        assessment) or $null on error.
    .PARAMETER TenantId
        beta: numeric Client Tenant ID. v1: Microsoft tenant ID (GUID).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [Alias('ClientTenantId')] [string]$TenantId,
        [Parameter(Mandatory)] [string]$ResolvedAssessmentId,
        [Parameter(Mandatory)] [string]$TenantDisplayName,
        [Parameter(Mandatory)] [string]$AssessmentDisplayName
    )

    # Format elapsed time as human-readable (e.g. "1m 23s", "45s")
    $formatElapsed = {
        param([double]$totalSeconds)
        if ($totalSeconds -ge 60) {
            $mins = [math]::Floor($totalSeconds / 60)
            $secs = [math]::Round($totalSeconds % 60)
            return "${mins}m ${secs}s"
        }
        return "$([math]::Round($totalSeconds, 1))s"
    }

    Write-Host "Running '$AssessmentDisplayName' against $TenantDisplayName..."

    $isV1 = $script:InforcerSession.ApiVersion -eq 'v1'
    $uri = Get-InforcerBaseUrl -Endpoint "/tenants/$TenantId/assessments/$ResolvedAssessmentId/runs"

    $formatApiError = {
        param([string]$errMsg)
        if ($errMsg -match '<title>([^<]+)</title>') { return "API error: $($Matches[1].Trim())" }
        if ($isV1 -and $errMsg.TrimStart().StartsWith('{')) {
            try {
                $problem = $errMsg | ConvertFrom-Json -ErrorAction Stop
                $title = $problem.PSObject.Properties['title'].Value -as [string]
                $detail = $problem.PSObject.Properties['detail'].Value -as [string]
                if ($title -and $detail -and $detail -ne $title) { return "${title}: $detail" }
                if ($title) { return $title }
            } catch { Write-Verbose 'Error body was not JSON; using raw text.' }
        }
        if ($errMsg.Length -gt 500) { $errMsg = $errMsg.Substring(0, 200) + '...' }
        $errMsg
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $retries429 = 0
    $renewToken = $false
    $tokenRenewed = $false
    $httpError = $null
    $rawResponse = $null
    while ($true) {
        $headers = Get-InforcerAuthHeader -ForceRefresh:$renewToken
        if (-not $headers) { return $null }
        $renewToken = $false
        $run = Invoke-InforcerAssessmentRunRequest -Uri $uri -Headers $headers
        if ($run.Failure -or @($run.StreamErrors).Count -gt 0) { break }
        $reply = @($run.Output)[0]
        $status = if ($reply) { [int]$reply.StatusCode } else { 0 }
        if ($isV1 -and $status -eq 429 -and $retries429 -lt 3) {
            $retries429++
            $delay = Get-InforcerRetryDelay -Value (Get-InforcerHeaderValue -Headers $reply.Headers -Name 'Retry-After') -Attempt $retries429
            Write-Verbose "Rate limited (HTTP 429). Retrying in $delay second(s) (attempt $retries429 of 3)."
            Start-Sleep -Seconds $delay
            continue
        }
        if ($isV1 -and $status -eq 401 -and -not $tokenRenewed) {
            Write-Verbose 'HTTP 401: renewing the access token and retrying once.'
            $tokenRenewed = $true
            $renewToken = $true
            continue
        }
        if ($status -ge 300 -and $status -lt 400) {
            $httpError = "The API answered with a redirect (HTTP $status), which is not followed: credentials are never sent to another address. Check the -Region or -BaseUrl you connected with."
            break
        }
        if ($status -ge 400 -or $status -lt 200) {
            $body = $reply.Body
            $httpError = if ($body -is [string] -and -not [string]::IsNullOrWhiteSpace($body)) {
                $body
            } elseif ($null -ne $body -and $body -isnot [string]) {
                ConvertTo-Json -InputObject $body -Depth 100 -Compress
            } else {
                "Response status code does not indicate success: $status ($([System.Net.HttpStatusCode]$status))."
            }
            break
        }
        $rawResponse = @($reply.Body)
        break
    }

    $hasError = $false
    foreach ($e in @($run.StreamErrors)) {
        $hasError = $true
        $errMsg = Protect-InforcerApiKeyInText -Text (& $formatApiError $e)
        Write-Error -Message $errMsg -ErrorId 'AssessmentRunFailed' -Category InvalidResult
    }
    if ($run.Failure) {
        $hasError = $true
        $errMsg = Protect-InforcerApiKeyInText -Text (& $formatApiError $run.Failure)
        Write-Error -Message "Assessment run failed: $errMsg" -ErrorId 'AssessmentRunFailed' -Category InvalidResult
    }
    if ($httpError) {
        $hasError = $true
        $errMsg = Protect-InforcerApiKeyInText -Text (& $formatApiError $httpError)
        Write-Error -Message $errMsg -ErrorId 'AssessmentRunFailed' -Category InvalidResult
    }

    $stopwatch.Stop()
    $elapsedStr = & $formatElapsed $stopwatch.Elapsed.TotalSeconds
    if ($hasError) {
        Write-Host "  Failed after $elapsedStr."
        return $null
    }
    Write-Host "  Completed in $elapsedStr."

    # Unwrap response and check for API-level errors
    $responseObj = if ($rawResponse -and $rawResponse.Count -gt 0) { $rawResponse[0] } else { $null }
    if ($null -eq $responseObj) { return $null }
    # Check for success:false (API returned 200 but operation failed)
    $successProp = $responseObj.PSObject.Properties['success']
    if ($successProp -and $successProp.Value -eq $false) {
        $msgProp = $responseObj.PSObject.Properties['message']
        $apiMsg = if ($msgProp) { $msgProp.Value } else { 'Unknown API error' }
        Write-Error -Message "Assessment API error: $apiMsg" -ErrorId 'AssessmentApiFailed' -Category InvalidResult
        return $null
    }
    $dataProp = $responseObj.PSObject.Properties['data']
    if ($dataProp) { return $dataProp.Value }
    if ($isV1) { return ConvertFrom-InforcerV1Response -InputObject $responseObj -ObjectType AssessmentRun }
    return $responseObj
}

function Invoke-InforcerAssessmentRunRequest {
    <#
    .SYNOPSIS
        Sends the run POST in a separate runspace and waits for it, reporting progress (internal helper).
    .DESCRIPTION
        Returns Output (the runspace output), StreamErrors (error texts) and Failure (exception text).
        The output is one { StatusCode, Body, Headers } object: HTTP errors do not throw and redirects are
        not followed (the caller reports them). Network failures still throw. The runspace gets the URI
        and headers only, never the session.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Uri,
        [Parameter(Mandatory)] [object]$Headers
    )

    # This endpoint takes no request body and rejects ANY Content-Type with
    # 400 ValidationFailure ("Unspecified content type <x> is not allowed"). Omitting the
    # header is not enough: Invoke-RestMethod supplies application/x-www-form-urlencoded on a
    # bodyless POST, which is rejected the same way. -ContentType '' suppresses it entirely.
    $runScript = @'
param($Uri, $Headers)
$statusCode = $null; $responseHeaders = $null
$body = Invoke-RestMethod -Uri $Uri -Method POST -Headers $Headers -ContentType "" -MaximumRedirection 0 -SkipHttpErrorCheck -StatusCodeVariable statusCode -ResponseHeadersVariable responseHeaders -ErrorAction Ignore
[pscustomobject]@{ StatusCode = [int]$statusCode; Body = $body; Headers = $responseHeaders }
'@

    $result = [pscustomobject]@{ Output = $null; StreamErrors = @(); Failure = $null }
    $ps = [PowerShell]::Create()
    try {
        $null = $ps.AddScript($runScript)
        $null = $ps.AddParameter('Uri', $Uri)
        $null = $ps.AddParameter('Headers', $Headers)
        $asyncResult = $ps.BeginInvoke()

        # WaitOne returns as soon as the run completes. On Ctrl+C the finally block still stops and
        # disposes the runspace, so the HTTP socket is not leaked.
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $lastUpdate = 0
        while (-not $asyncResult.AsyncWaitHandle.WaitOne(500)) {
            $elapsed = [math]::Floor($stopwatch.Elapsed.TotalSeconds)
            if ($elapsed -gt 0 -and $elapsed % 10 -eq 0 -and $elapsed -ne $lastUpdate) {
                $text = if ($elapsed -ge 60) { "$([math]::Floor($elapsed / 60))m $([math]::Round($elapsed % 60))s" } else { "${elapsed}s" }
                Write-Host "  Still running... $text elapsed"
                $lastUpdate = $elapsed
            }
        }
        try {
            $result.Output = $ps.EndInvoke($asyncResult)
            $result.StreamErrors = @(foreach ($e in $ps.Streams.Error) { $e.ToString() })
        } catch {
            $result.Failure = $_.Exception.Message
        }
    } finally {
        if ($null -ne $ps) {
            try { if ($ps.InvocationStateInfo.State -eq 'Running') { $ps.Stop() } } catch { $null }
            $ps.Dispose()
        }
    }
    $result
}
