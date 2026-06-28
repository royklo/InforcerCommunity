function Invoke-InforcerRawDownload {
    <#
    .SYNOPSIS
        Performs a binary-safe GET against an Inforcer API endpoint (Private helper).
    .DESCRIPTION
        Uses Invoke-WebRequest under the hood so the response body is captured as raw bytes
        rather than UTF-8-decoded text. Returns the bytes alongside the server-suggested
        filename (parsed from Content-Disposition) and the x-correlation-id for support.

        Used by Save-InforcerReportOutput to fetch /beta/reports/runs/{id}/outputs/{id} —
        which can be CSV, JSON, HTML, PDF, or other binary content.

        Error envelope handling mirrors Invoke-InforcerApiRequest: app-layer, APIM, and
        RFC 9110 ProblemDetails shapes are all parsed for a usable error message.
    .PARAMETER Endpoint
        API path (e.g. /beta/reports/runs/.../outputs/...). Leading slash optional.
    .PARAMETER DefaultFileName
        Suggested filename when the server doesn't return a usable Content-Disposition.
        Defaults to 'output'.
    .OUTPUTS
        PSCustomObject with members:
          Bytes         — [byte[]] response body
          FileName      — sanitized filename (from Content-Disposition or DefaultFileName)
          ContentType   — value of Content-Type header (or $null)
          CorrelationId — x-correlation-id of the response (or $null)
          StatusCode    — int HTTP status code
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Endpoint,

        [Parameter(Mandatory = $false)]
        [string]$DefaultFileName = 'output'
    )

    if (-not (Test-InforcerSession)) {
        Write-Error -Message 'Not connected. Run Connect-Inforcer first.' `
            -ErrorId 'NotConnected' -Category ConnectionError
        return
    }

    $endpoint = $Endpoint.Trim()
    if (-not $endpoint.StartsWith('/')) {
        $endpoint = '/' + $endpoint
    }

    $uri = $script:InforcerSession.BaseUrl + $endpoint

    $apiKey = ConvertFrom-InforcerSecureString -SecureString $script:InforcerSession.ApiKey
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        Write-Error -Message 'API key is empty or invalid. Please reconnect.' `
            -ErrorId 'EmptyApiKey' -Category AuthenticationError
        return
    }

    $headers = @{
        'Inf-Api-Key' = $apiKey
        'Accept'      = '*/*'
    }

    Write-Verbose "Downloading: GET $uri"

    try {
        # -SkipHttpErrorCheck lets us inspect status code and body without exception-based flow.
        $response = Invoke-WebRequest -Uri $uri -Method GET -Headers $headers -SkipHttpErrorCheck -UseBasicParsing -ErrorAction Stop
    } catch {
        $msg = Protect-InforcerApiKeyInText -Text $_.Exception.Message -ApiKey $apiKey
        Write-Error -Message "Download request failed: $msg" `
            -ErrorId 'DownloadFailed' -Category ConnectionError
        return
    }

    $statusCode    = [int]$response.StatusCode
    $correlationId = Get-InforcerHeaderValue -Headers $response.Headers -Name 'x-correlation-id'
    if ($correlationId) {
        Write-Verbose "x-correlation-id: $correlationId"
    }

    if ($statusCode -lt 200 -or $statusCode -ge 300) {
        # Parse error body for a friendly message — same envelope shapes as Invoke-InforcerApiRequest.
        $detail = $null
        if ($response.Content) {
            $bodyText = if ($response.Content -is [byte[]]) {
                [System.Text.Encoding]::UTF8.GetString($response.Content)
            } else {
                $response.Content -as [string]
            }
            $detail = $bodyText
            try {
                $json = $bodyText | ConvertFrom-Json -ErrorAction Stop
                $apiMessage = $null
                $traceId    = $null
                if ($null -ne $json.PSObject.Properties['message']) {
                    $apiMessage = $json.PSObject.Properties['message'].Value -as [string]
                } elseif ($null -ne $json.PSObject.Properties['title']) {
                    $apiMessage = $json.PSObject.Properties['title'].Value -as [string]
                    if ($null -ne $json.PSObject.Properties['traceId']) {
                        $traceId = $json.PSObject.Properties['traceId'].Value -as [string]
                    }
                }
                if (-not [string]::IsNullOrWhiteSpace($apiMessage)) { $detail = $apiMessage }
                if (-not [string]::IsNullOrWhiteSpace($traceId))    { $detail = "$detail (traceId: $traceId)" }
            } catch {
                Write-Verbose 'Error response body was not JSON; using raw content.'
            }
        }
        if ([string]::IsNullOrWhiteSpace($detail)) { $detail = "HTTP $statusCode" }
        $detail = Protect-InforcerApiKeyInText -Text $detail -ApiKey $apiKey
        $msg = "Inforcer API download failed (HTTP $statusCode): $detail"
        if ($correlationId) { $msg = "$msg [correlation-id: $correlationId]" }
        Write-Error -Message $msg -ErrorId "DownloadFailed_$statusCode" -Category ConnectionError
        return
    }

    # Extract Content-Disposition / Content-Type header values (cross-shape tolerant).
    $disposition = $null
    $contentType = $null
    if ($response.Headers) {
        $disposition = Get-InforcerHeaderValue -Headers $response.Headers -Name 'Content-Disposition'
        $contentType = Get-InforcerHeaderValue -Headers $response.Headers -Name 'Content-Type'
    }

    $fileName = Resolve-InforcerReportOutputFileName -ContentDisposition $disposition -DefaultName $DefaultFileName

    # Invoke-WebRequest returns Content as byte[] when -UseBasicParsing and binary response.
    $bytes = if ($response.Content -is [byte[]]) {
        $response.Content
    } elseif ($response.Content -is [string]) {
        [System.Text.Encoding]::UTF8.GetBytes($response.Content)
    } else {
        @()
    }

    [PSCustomObject]@{
        Bytes         = $bytes
        FileName      = $fileName
        ContentType   = $contentType
        CorrelationId = $correlationId
        StatusCode    = $statusCode
    }
}
