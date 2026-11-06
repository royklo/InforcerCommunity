function Invoke-InforcerRawDownload {
    <#
    .SYNOPSIS
        Performs a binary-safe GET against an Inforcer API endpoint (Private helper).
    .DESCRIPTION
        Uses Invoke-WebRequest under the hood so the response body is captured as raw bytes
        rather than UTF-8-decoded text. Returns the bytes alongside the server-suggested
        filename (parsed from Content-Disposition) and the x-correlation-id for support.

        Used by Save-InforcerReportOutput to fetch /reports/runs/{id}/outputs/{id} — which can be
        CSV, JSON, HTML, PDF, or other binary content. The URI and auth header come from
        Get-InforcerBaseUrl / Get-InforcerAuthHeader, so it works for API-key (beta) and
        client-credentials (v1) sessions; a v1 401 renews the access token and retries once.

        Error envelope handling mirrors Invoke-InforcerApiRequest: app-layer, APIM, and
        RFC 9110 ProblemDetails shapes are all parsed for a usable error message.
    .PARAMETER Endpoint
        Version-neutral API path (e.g. /reports/runs/.../outputs/...). Leading slash optional.
    .PARAMETER DefaultFileName
        Suggested filename when the server doesn't return a usable Content-Disposition.
        Defaults to 'output'.
    .PARAMETER DestinationDirectory
        When set, response body is streamed directly to a temp file in this directory rather
        than buffered into memory, then renamed to the Content-Disposition filename. Use this
        for large downloads (>100MB) to avoid a 2GB+ in-memory allocation on multi-GB reports.
        The returned object has a `FilePath` instead of `Bytes`. The directory must already exist.
        An existing file is never overwritten: a taken name gets a ' (1)', ' (2)', ... suffix.
        On Windows the saved file is marked as downloaded from the internet (Zone.Identifier).
    .PARAMETER FileName
        Final file name chosen by the caller. When set, the server's Content-Disposition name is
        ignored and never touches the disk. Sanitized like the server name.
    .OUTPUTS
        PSCustomObject with members:
          Bytes         — [byte[]] response body (omitted when -DestinationDirectory is used)
          FilePath      — final on-disk path (only when -DestinationDirectory is used)
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
        [string]$DefaultFileName = 'output',

        [Parameter(Mandatory = $false)]
        [string]$DestinationDirectory,

        [Parameter(Mandatory = $false)]
        [string]$FileName
    )

    if (-not (Test-InforcerSession)) {
        Write-Error -Message 'Not connected. Run Connect-Inforcer first.' `
            -ErrorId 'NotConnected' -Category ConnectionError
        return
    }

    $uri = Get-InforcerBaseUrl -Endpoint $Endpoint

    Write-Verbose "Downloading: GET $uri"

    # When -DestinationDirectory is set, stream the body straight to a temp file via
    # `-OutFile` so we don't materialize a multi-GB body in memory. The body is renamed
    # to the Content-Disposition filename after the response headers are inspected.
    $tempStreamPath = $null
    if ($PSBoundParameters.ContainsKey('DestinationDirectory')) {
        if (-not (Test-Path -LiteralPath $DestinationDirectory -PathType Container)) {
            Write-Error -Message "DestinationDirectory '$DestinationDirectory' does not exist." `
                -ErrorId 'BadDestination' -Category InvalidArgument
            return
        }
        # File.Move resolves relative paths against the process directory, not $PWD.
        $DestinationDirectory = Convert-Path -LiteralPath $DestinationDirectory
        $tempStreamPath = Join-Path -Path $DestinationDirectory -ChildPath ('inforcer-download-' + [guid]::NewGuid().ToString('N') + '.partial')
    }

    $isV1 = $script:InforcerSession.ApiVersion -eq 'v1'
    $forceRefresh = $false
    while ($true) {
        $headers = Get-InforcerAuthHeader -ForceRefresh:$forceRefresh
        if (-not $headers) { return }
        $headers['Accept'] = '*/*'

        try {
            # -SkipHttpErrorCheck lets us inspect status code and body without exception-based flow.
            if ($tempStreamPath) {
                $response = Invoke-WebRequest -Uri $uri -Method GET -Headers $headers -SkipHttpErrorCheck `
                    -MaximumRedirection 0 -UseBasicParsing -OutFile $tempStreamPath -PassThru -ErrorAction Stop
            } else {
                $response = Invoke-WebRequest -Uri $uri -Method GET -Headers $headers -SkipHttpErrorCheck `
                    -MaximumRedirection 0 -UseBasicParsing -ErrorAction Stop
            }
        } catch {
            Clear-InforcerRequestCredential -ErrorRecord $_
            if ($tempStreamPath -and (Test-Path -LiteralPath $tempStreamPath)) {
                Remove-Item -LiteralPath $tempStreamPath -Force -ErrorAction SilentlyContinue
            }
            if ($_.FullyQualifiedErrorId -match 'MaximumRedirect') {
                Write-Error -Message (Get-InforcerRedirectMessage -StatusCode 302 -Headers $null) -ErrorId 'DownloadFailed_302' -Category ConnectionError
                return
            }
            $msg = Protect-InforcerApiKeyInText -Text $_.Exception.Message
            Write-Error -Message "Download request failed: $msg" `
                -ErrorId 'DownloadFailed' -Category ConnectionError
            return
        }

        if ($isV1 -and -not $forceRefresh -and [int]$response.StatusCode -eq 401) {
            Write-Verbose 'HTTP 401: renewing the access token and retrying once.'
            if ($tempStreamPath -and (Test-Path -LiteralPath $tempStreamPath)) {
                Remove-Item -LiteralPath $tempStreamPath -Force -ErrorAction SilentlyContinue
            }
            $forceRefresh = $true
            continue
        }
        break
    }

    $statusCode    = [int]$response.StatusCode
    $correlationId = Get-InforcerHeaderValue -Headers $response.Headers -Name 'x-correlation-id'
    if ($correlationId) {
        Write-Verbose "x-correlation-id: $correlationId"
    }

    if ($statusCode -ge 300 -and $statusCode -lt 400) {
        if ($tempStreamPath) { Remove-Item -LiteralPath $tempStreamPath -Force -ErrorAction SilentlyContinue }
        Write-Error -Message (Get-InforcerRedirectMessage -StatusCode $statusCode -Headers $response.Headers) `
            -ErrorId "DownloadFailed_$statusCode" -Category ConnectionError
        return
    }

    if ($statusCode -lt 200 -or $statusCode -ge 300) {
        # Parse error body for a friendly message — same envelope shapes as Invoke-InforcerApiRequest.
        # If we streamed to disk, the error body is in the temp file, not $response.Content.
        $detail = $null
        $bodyText = $null
        if ($tempStreamPath -and (Test-Path -LiteralPath $tempStreamPath)) {
            try { $bodyText = Get-Content -LiteralPath $tempStreamPath -Raw -ErrorAction Stop } catch { $bodyText = $null }
            Remove-Item -LiteralPath $tempStreamPath -Force -ErrorAction SilentlyContinue
        } elseif ($response.Content) {
            $bodyText = if ($response.Content -is [byte[]]) {
                [System.Text.Encoding]::UTF8.GetString($response.Content)
            } else {
                $response.Content -as [string]
            }
        }
        if ($bodyText) {
            $detail = $bodyText
            try {
                $json = $bodyText | ConvertFrom-Json -ErrorAction Stop
                $apiMessage = $null
                $traceId    = $null
                if ($null -ne $json.PSObject.Properties['message']) {
                    $apiMessage = $json.PSObject.Properties['message'].Value -as [string]
                } elseif ($null -ne $json.PSObject.Properties['title']) {
                    $apiMessage = $json.PSObject.Properties['title'].Value -as [string]
                    $problemDetail = $json.PSObject.Properties['detail'].Value -as [string]
                    if ($problemDetail -and $problemDetail -ne $apiMessage) { $apiMessage = "${apiMessage}: $problemDetail" }
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
        $detail = Protect-InforcerApiKeyInText -Text $detail
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

    $fileName = if ($FileName) {
        Resolve-InforcerReportOutputFileName -DefaultName $FileName
    } else {
        Resolve-InforcerReportOutputFileName -ContentDisposition $disposition -DefaultName $DefaultFileName
    }

    if ($tempStreamPath) {
        # File.Move without overwrite fails when the name is taken, so an existing file is never
        # replaced; the next ' (n)' name is tried instead.
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($fileName)
        $extension = [System.IO.Path]::GetExtension($fileName)
        $candidate = $fileName
        for ($n = 1; ; $n++) {
            $finalPath = Join-Path -Path $DestinationDirectory -ChildPath $candidate
            try {
                [System.IO.File]::Move($tempStreamPath, $finalPath)
                break
            } catch {
                if ($n -le 1000 -and (Test-Path -LiteralPath $finalPath)) {
                    $candidate = '{0} ({1}){2}' -f $stem, $n, $extension
                    continue
                }
                Remove-Item -LiteralPath $tempStreamPath -Force -ErrorAction SilentlyContinue
                Write-Error -Message "Failed to finalize downloaded file at '$finalPath': $($_.Exception.Message)" `
                    -ErrorId 'DownloadFinalizeFailed' -Category WriteError
                return
            }
        }
        $fileName = $candidate
        if ($IsWindows) {
            try {
                Set-Content -LiteralPath $finalPath -Stream 'Zone.Identifier' -Value '[ZoneTransfer]', 'ZoneId=3' -ErrorAction Stop
            } catch {
                Write-Verbose "Could not mark '$finalPath' as downloaded from the internet: $($_.Exception.Message)"
            }
        }
        $size = (Get-Item -LiteralPath $finalPath -ErrorAction SilentlyContinue).Length
        return [PSCustomObject]@{
            FilePath      = $finalPath
            FileName      = $fileName
            FileSize      = $size
            ContentType   = $contentType
            CorrelationId = $correlationId
            StatusCode    = $statusCode
        }
    }

    # In-memory mode (existing behavior — backwards compatible for small payloads).
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
