function Invoke-InforcerAssessmentRun {
    <#
    .SYNOPSIS
        Runs a single assessment against one tenant (internal helper).
    .DESCRIPTION
        Executes POST /tenants/{id}/assessments/{id}/runs in a separate runspace so the caller can
        show progress. The URI and auth header are built here with Get-InforcerBaseUrl and
        Get-InforcerAuthHeader (fresh per run, so a long multi-tenant loop never reuses an expired
        v1 token) and handed to the runspace as parameters; the runspace never sees the session.
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
    $headers = Get-InforcerAuthHeader
    if (-not $headers) { return $null }

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

    # This endpoint takes no request body and rejects ANY Content-Type with
    # 400 ValidationFailure ("Unspecified content type <x> is not allowed"). Omitting the
    # header is not enough: Invoke-RestMethod supplies application/x-www-form-urlencoded on a
    # bodyless POST, which is rejected the same way. -ContentType '' suppresses it entirely.
    $ps = [PowerShell]::Create()
    $null = $ps.AddScript('param($Uri, $Headers); Invoke-RestMethod -Uri $Uri -Method POST -Headers $Headers -ContentType ""')
    $null = $ps.AddParameter('Uri', $uri)
    $null = $ps.AddParameter('Headers', $headers)
    $asyncResult = $ps.BeginInvoke()

    $rawResponse = $null
    $hasError = $false
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        # Poll for completion. Ctrl+C during Start-Sleep raises PipelineStoppedException; the
        # outer finally still runs and disposes the runspace, so we don't leak the underlying
        # HTTP socket.
        $lastUpdate = 0
        while (-not $asyncResult.IsCompleted) {
            Start-Sleep -Milliseconds 500
            $elapsed = [math]::Floor($stopwatch.Elapsed.TotalSeconds)
            if ($elapsed -gt 0 -and $elapsed % 10 -eq 0 -and $elapsed -ne $lastUpdate) {
                Write-Host "  Still running... $(& $formatElapsed $elapsed) elapsed"
                $lastUpdate = $elapsed
            }
        }
        try {
            $rawResponse = $ps.EndInvoke($asyncResult)
            if ($ps.Streams.Error.Count -gt 0) {
                $hasError = $true
                foreach ($e in $ps.Streams.Error) {
                    $errMsg = Protect-InforcerApiKeyInText -Text (& $formatApiError $e.ToString())
                    Write-Error -Message $errMsg -ErrorId 'AssessmentRunFailed' -Category InvalidResult
                }
            }
        } catch {
            $hasError = $true
            $errMsg = Protect-InforcerApiKeyInText -Text (& $formatApiError $_.Exception.Message)
            Write-Error -Message "Assessment run failed: $errMsg" -ErrorId 'AssessmentRunFailed' -Category InvalidResult
        }
    } finally {
        # Cancel any in-flight pipeline (no-op if it already completed) and dispose the
        # runspace. This block also runs when the user Ctrl+C's mid-poll, preventing the
        # runspace + socket leak that the previous structure (Dispose only inside the
        # post-loop try/finally) allowed.
        if ($null -ne $ps) {
            try { if ($ps.InvocationStateInfo.State -eq 'Running') { $ps.Stop() } } catch { $null }
            $ps.Dispose()
        }
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
