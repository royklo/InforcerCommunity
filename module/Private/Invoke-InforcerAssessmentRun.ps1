function Invoke-InforcerAssessmentRun {
    <#
    .SYNOPSIS
        Runs a single assessment against one tenant (internal helper).
    .DESCRIPTION
        Executes POST /beta/tenants/{id}/assessments/{id}/runs asynchronously
        with progress updates. Returns the raw API response data or $null on error.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [int]$ClientTenantId,
        [Parameter(Mandatory)] [string]$ResolvedAssessmentId,
        [Parameter(Mandatory)] [string]$TenantDisplayName,
        [Parameter(Mandatory)] [string]$AssessmentDisplayName
    )

    Write-Host "Running '$AssessmentDisplayName' against $TenantDisplayName..."

    $endpoint = "/beta/tenants/$ClientTenantId/assessments/$ResolvedAssessmentId/runs"
    $uri = $script:InforcerSession.BaseUrl + $endpoint
    $apiKey = ConvertFrom-InforcerSecureString -SecureString $script:InforcerSession.ApiKey
    $headers = @{ 'Inf-Api-Key' = $apiKey; 'Content-Type' = 'application/json' }

    $ps = [PowerShell]::Create()
    $null = $ps.AddScript('param($Uri, $Headers); Invoke-RestMethod -Uri $Uri -Method POST -Headers $Headers')
    $null = $ps.AddParameter('Uri', $uri)
    $null = $ps.AddParameter('Headers', $headers)
    $asyncResult = $ps.BeginInvoke()

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $lastUpdate = 0
    while (-not $asyncResult.IsCompleted) {
        Start-Sleep -Milliseconds 500
        $elapsed = [math]::Floor($stopwatch.Elapsed.TotalSeconds)
        if ($elapsed -gt 0 -and $elapsed % 10 -eq 0 -and $elapsed -ne $lastUpdate) {
            Write-Host "  Still running... ${elapsed}s elapsed"
            $lastUpdate = $elapsed
        }
    }

    $rawResponse = $null
    $hasError = $false
    try {
        $rawResponse = $ps.EndInvoke($asyncResult)
        if ($ps.Streams.Error.Count -gt 0) {
            $hasError = $true
            foreach ($e in $ps.Streams.Error) {
                $errMsg = $e.ToString()
                if ($errMsg -match '<title>([^<]+)</title>') { $errMsg = "API error: $($Matches[1].Trim())" }
                elseif ($errMsg.Length -gt 500) { $errMsg = $errMsg.Substring(0, 200) + '...' }
                Write-Error -Message $errMsg -ErrorId 'AssessmentRunFailed' -Category InvalidResult
            }
        }
    } catch {
        $hasError = $true
        $errMsg = $_.Exception.Message
        if ($errMsg -match '<title>([^<]+)</title>') { $errMsg = "API error: $($Matches[1].Trim())" }
        elseif ($errMsg.Length -gt 500) { $errMsg = $errMsg.Substring(0, 200) + '...' }
        Write-Error -Message "Assessment run failed: $errMsg" -ErrorId 'AssessmentRunFailed' -Category InvalidResult
    } finally {
        $ps.Dispose()
    }

    $stopwatch.Stop()
    $elapsed = [math]::Round($stopwatch.Elapsed.TotalSeconds, 1)
    if ($hasError) {
        Write-Host "  Failed after ${elapsed}s."
        return $null
    }
    Write-Host "  Completed in ${elapsed}s."

    # Unwrap response
    $responseObj = if ($rawResponse -and $rawResponse.Count -gt 0) { $rawResponse[0] } else { $null }
    if ($null -eq $responseObj) { return $null }
    $dataProp = $responseObj.PSObject.Properties['data']
    if ($dataProp) { return $dataProp.Value } else { return $responseObj }
}
