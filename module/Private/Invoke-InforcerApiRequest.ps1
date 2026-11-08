function Invoke-InforcerApiRequest {
    <#
    .SYNOPSIS
        Sends a request to the Inforcer REST API (Private helper).
    .DESCRIPTION
        Works for both login types. API-key sessions call {BaseUrl}/beta{path}; client-credentials
        sessions call {ApiHost}/v1{path} with the v1 path renames (see Get-InforcerBaseUrl).
        Endpoints are version-neutral.

        beta responses: unwraps response.data, then (unless -PreserveStructure) the first array property.
        v1 responses:   a list response unwraps to its single collection array (metadata such as
                        continuationToken is ignored); a single object is never unwrapped. -ObjectType maps
                        v1 property names to the module's canonical names before any JSON conversion.
                        A non-empty failedPolicyTypes is surfaced as a warning.

        Recognised error envelopes:
          * problem+json:  { type, title, status, detail, instance, errors{} }  -> "title: detail (field: message)"
          * App-layer:     { success, message, errors[], errorCode }
          * APIM gateway:  { statusCode, message }
        ErrorId is ApiRequestFailed_<status>. On v1, 429 is retried up to three times honouring Retry-After
        (seconds or HTTP date, capped at 300 s) and a 401 renews the token once and retries.

        The x-correlation-id response header is logged to the verbose stream and included in error
        messages when present.
    .PARAMETER Endpoint
        Version-neutral API path (e.g. /tenants/{id}/policies). Leading slash optional.
    .PARAMETER Method
        HTTP method. Default: GET.
    .PARAMETER Body
        Optional JSON body for POST/PUT/PATCH.
    .PARAMETER OutputType
        PowerShellObject (return PSObjects) or JsonObject (return JSON string). Default: PowerShellObject.
    .PARAMETER PreserveStructure
        beta: unwraps .data but keeps its inner structure (e.g. items + continuationToken).
        v1: returns the response object as-is (collection mapped), without unwrapping.
    .PARAMETER PreserveFullResponse
        Returns the full parsed response without unwrapping (v1: collection mapped via -ObjectType).
    .PARAMETER ObjectType
        v1 only: maps the response to canonical property names via ConvertFrom-InforcerV1Response.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Endpoint,

        [Parameter(Mandatory = $false)]
        [ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'DELETE')]
        [string]$Method = 'GET',

        [Parameter(Mandatory = $false)]
        [string]$Body,

        [Parameter(Mandatory = $false)]
        [ValidateSet('PowerShellObject', 'JsonObject')]
        [string]$OutputType = 'PowerShellObject',

        [Parameter(Mandatory = $false)]
        [switch]$PreserveStructure,

        [Parameter(Mandatory = $false)]
        [switch]$PreserveFullResponse,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Tenant', 'Policy', 'Baseline', 'AlignmentScore', 'AlignmentDetails', 'User', 'Group', 'GroupMember', 'Role',
            'SecureScore', 'Assessment', 'AssessmentRun', 'ReportType', 'ReportRun', 'ReportOutput', 'AuditEvent', 'AuditEventType')]
        [string]$ObjectType
    )

    if (-not (Test-InforcerSession)) {
        Write-Error -Message 'Not connected. Run Connect-Inforcer first.' `
            -ErrorId 'NotConnected' `
            -Category ConnectionError
        return
    }

    $session = $script:InforcerSession
    $isV1 = $session.ApiVersion -eq 'v1'
    $uri = Get-InforcerBaseUrl -Endpoint $Endpoint -Session $session

    Write-Verbose "Making $Method request to: $uri"

    $request = @{ Uri = $uri; Method = $Method }
    if (-not [string]::IsNullOrWhiteSpace($Body)) {
        $request['Body'] = $Body
    }

    $retries429 = 0
    $renewToken = $false
    $tokenRenewed = $false
    while ($true) {
        $headers = Get-InforcerAuthHeader -Session $session -ForceRefresh:$renewToken
        if (-not $headers) { return }
        $renewToken = $false
        $headers['Accept'] = 'application/json'
        $headers['Content-Type'] = 'application/json'
        $attempt = $request.Clone()
        $attempt['Headers'] = $headers

        try {
            $response = Invoke-InforcerHttpRequest -Request $attempt
        } catch {
            Clear-InforcerRequestCredential -ErrorRecord $_
            $detail = Protect-InforcerApiKeyInText -Text $_.Exception.Message -Session $session
            Write-Error -Message "Inforcer API request failed: $detail" -ErrorId 'ApiRequestFailed' -Category ConnectionError
            return
        }

        $statusCode = $response.StatusCode
        $correlationId = Get-InforcerHeaderValue -Headers $response.Headers -Name 'x-correlation-id'
        if ($correlationId) {
            Write-Verbose "x-correlation-id: $correlationId"
        }
        if ($statusCode -lt 400) {
            $rawResponse = $response.Body
            break
        }

        if ($statusCode -eq 429 -and $isV1 -and $retries429 -lt 3) {
            $retries429++
            $delay = Get-InforcerRetryDelay -Value (Get-InforcerHeaderValue -Headers $response.Headers -Name 'Retry-After') -Attempt $retries429
            Write-Verbose "Rate limited (HTTP 429). Retrying in $delay second(s) (attempt $retries429 of 3)."
            Start-Sleep -Seconds $delay
            continue
        }
        if ($statusCode -eq 401 -and $isV1 -and -not $tokenRenewed) {
            Write-Verbose 'HTTP 401: renewing the access token and retrying once.'
            $tokenRenewed = $true
            $renewToken = $true
            continue
        }

        $detail = "Response status code does not indicate success: $statusCode ($([System.Net.HttpStatusCode]$statusCode))."
        $json = $response.Body
        if ($json -is [string]) {
            if (-not [string]::IsNullOrWhiteSpace($json)) { $detail = $json }
            try { $json = $json | ConvertFrom-Json -Depth 100 -ErrorAction Stop } catch { $json = $null }
        }

        if ($json -is [System.Management.Automation.PSCustomObject]) {
            if ($response.Body -isnot [string]) { $detail = $json | ConvertTo-Json -Depth 100 -Compress }
            $apiMessage = $null
            $errorCode  = $null
            $traceId    = $null
            $props = $json.PSObject.Properties
            $isAppEnvelope = $null -ne $props['errorCode'] -or $null -ne $props['success']

            if (-not $isAppEnvelope -and $null -ne $props['title'] -and ($null -ne $props['status'] -or $null -ne $props['type'])) {
                # problem+json (RFC 9457): v1 errors, and beta framework errors such as 415.
                $title = ($props['title'].Value -as [string])
                $problemDetail = ($props['detail'].Value -as [string])
                $apiMessage = if ($title -and $problemDetail -and $problemDetail -ne $title) { "${title}: $problemDetail" }
                              elseif ($problemDetail) { $problemDetail } else { $title }
                $fieldErrors = Format-InforcerProblemError -Errors $props['errors'].Value
                if ($fieldErrors) { $apiMessage = "$apiMessage ($fieldErrors)" }
                $traceId = ($props['traceId'].Value -as [string])
            } elseif ($isAppEnvelope -or $null -ne $props['errors']) {
                # App-layer envelope { success, message, errors[], errorCode }
                $errorCode  = ($props['errorCode'].Value -as [string])
                $apiMessage = ($props['message'].Value -as [string])
                $errorsProp = $props['errors']
                if ($errorsProp -and $errorsProp.Value) {
                    $errorsJoined = Format-InforcerErrorDetail -Errors $errorsProp.Value
                    if (-not [string]::IsNullOrWhiteSpace($errorsJoined)) {
                        if ([string]::IsNullOrWhiteSpace($apiMessage)) {
                            $apiMessage = $errorsJoined
                        } elseif ($apiMessage -notlike "*$errorsJoined*") {
                            $apiMessage = "$apiMessage — $errorsJoined"
                        }
                    }
                }
            } elseif ($null -ne $props['statusCode'] -and $null -ne $props['message']) {
                # APIM gateway { statusCode, message }
                $apiMessage = ($props['message'].Value -as [string])
            }

            $detail = switch ($true) {
                ($statusCode -eq 429 -or ($apiMessage -and $apiMessage -match 'quota|rate.?limit|throttl')) {
                    if (-not [string]::IsNullOrWhiteSpace($apiMessage)) { "API rate limit: $apiMessage" } else { 'API rate limit exceeded. Please wait and try again.' }
                }
                ($errorCode -match '^forbidden$') {
                    if (-not [string]::IsNullOrWhiteSpace($apiMessage)) { $apiMessage } else { "You don't have permission to access this tenant or resource." }
                }
                ($errorCode -match 'notfound|not_found') {
                    if (-not [string]::IsNullOrWhiteSpace($apiMessage)) { $apiMessage } else { 'Tenant or resource not found.' }
                }
                default {
                    if (-not [string]::IsNullOrWhiteSpace($apiMessage)) { $apiMessage }
                    elseif ($props['error']) { $json.error -as [string] }
                    else { $detail }
                }
            }

            if (-not [string]::IsNullOrWhiteSpace($traceId)) {
                $detail = "$detail (traceId: $traceId)"
            }
        }

        $detail = Protect-InforcerApiKeyInText -Text $detail -Session $session
        $msg = "Inforcer API request failed (HTTP $statusCode): $detail"
        if ($correlationId) {
            $msg = "$msg [correlation-id: $correlationId]"
        }
        Write-Error -Message $msg -ErrorId "ApiRequestFailed_$statusCode" -Category ConnectionError
        return
    }

    if ($null -eq $rawResponse) {
        Write-Error -Message 'API returned an empty response.' -ErrorId 'EmptyResponse' -Category InvalidData
        return
    }

    # Invoke-RestMethod auto-parses JSON. A string means a non-JSON Content-Type that may still hold JSON.
    if ($rawResponse -is [string]) {
        try {
            $rawResponse = $rawResponse | ConvertFrom-Json -Depth 100 -ErrorAction Stop
        } catch {
            $preview = $rawResponse
            if ($preview.Length -gt 200) { $preview = $preview.Substring(0, 200) + '...' }
            Write-Error -Message "API returned non-JSON response. Base URL may be incorrect. Response starts with: $(Protect-InforcerApiKeyInText -Text $preview -Session $session)" `
                -ErrorId 'NonJsonResponse' -Category InvalidData
            return
        }
    }
    if ($rawResponse -isnot [PSObject] -and $rawResponse -isnot [array]) {
        $preview = $rawResponse.ToString()
        if ($preview.Length -gt 200) { $preview = $preview.Substring(0, 200) + '...' }
        Write-Error -Message "API returned non-JSON response. Base URL may be incorrect. Response starts with: $(Protect-InforcerApiKeyInText -Text $preview -Session $session)" `
            -ErrorId 'NonJsonResponse' -Category InvalidData
        return
    }

    if ($isV1) {
        $collectionName = Get-InforcerV1CollectionName -Response $rawResponse
        $failedProp = $rawResponse.PSObject.Properties['failedPolicyTypes']
        if ($failedProp -and $failedProp.Value -is [System.Management.Automation.PSCustomObject]) {
            $failed = @($failedProp.Value.PSObject.Properties | ForEach-Object {
                if ([string]::IsNullOrWhiteSpace([string]$_.Value)) { $_.Name } else { "$($_.Name) ($($_.Value))" }
            })
            if ($failed.Count -gt 0) {
                Write-Warning "inforcer could not retrieve $($failed.Count) policy type(s); their policies are missing from this result: $($failed -join '; ')"
            }
        }

        # Plain assignments only: an if-expression would unroll a one-item or empty array.
        if ($collectionName) {
            $data = @(@($rawResponse.$collectionName).Where({ $null -ne $_ }))
            if ($ObjectType) { $data = @(ConvertFrom-InforcerV1Response -InputObject $data -ObjectType $ObjectType) }
        } else {
            $data = $rawResponse
            if ($ObjectType) { $data = ConvertFrom-InforcerV1Response -InputObject $data -ObjectType $ObjectType }
        }

        $result = $data
        if ($collectionName -and ($PreserveFullResponse -or $PreserveStructure)) {
            $full = [ordered]@{}
            foreach ($p in $rawResponse.PSObject.Properties) { $full[$p.Name] = $p.Value }
            $full[$collectionName] = $data
            $result = [PSCustomObject]$full
        }
        if ($PreserveFullResponse) { return $result }
        if ($OutputType -eq 'JsonObject') { return (ConvertTo-Json -InputObject $result -Depth 100) }
        return $result
    }

    # beta: API error payload (success: false) — single, clean message; no stack or raw JSON
    $successValue = $rawResponse.PSObject.Properties['success'].Value
    if ($null -ne $rawResponse.PSObject.Properties['success'] -and $successValue -eq $false) {
        $apiMessage = ($rawResponse.PSObject.Properties['message'].Value -as [string])
        if ([string]::IsNullOrWhiteSpace($apiMessage)) { $apiMessage = 'Request failed.' }
        $apiMessage = $apiMessage.Trim()
        $errorCode = ($rawResponse.PSObject.Properties['errorCode'].Value -as [string])
        if ([string]::IsNullOrWhiteSpace($errorCode)) { $errorCode = '' }

        $friendlyMessage = switch -Regex ($errorCode) {
            '^forbidden$'       { "You don't have permission to access this tenant or resource." }
            'notfound|not_found' { "Tenant or resource not found." }
            default             { $apiMessage }
        }
        if ($rawResponse.errors -is [array] -and $rawResponse.errors.Count -gt 0) {
            $extra = ($rawResponse.errors | ForEach-Object { $_.ToString() }) -join '; '
            if (-not [string]::IsNullOrWhiteSpace($extra)) { $friendlyMessage += " $extra" }
        }
        Write-Error -Message $friendlyMessage -ErrorId 'ApiError' -Category InvalidOperation
        return
    }

    if ($PreserveFullResponse) {
        return $rawResponse
    }

    $data = $rawResponse
    $dataProp = $rawResponse.PSObject.Properties['data']
    if ($dataProp -and $null -ne $dataProp.Value) {
        $data = $dataProp.Value
    }

    if ($OutputType -eq 'JsonObject') {
        $json = $data | ConvertTo-Json -Depth 100
        return $json
    }

    if ($PreserveStructure) {
        return $data
    }

    # If data is a single object with one array property (e.g. value, items, policies), unwrap to that array
    if ($data -isnot [array] -and $data -is [PSObject]) {
        $arrayProp = $data.PSObject.Properties | Where-Object { $_.Value -is [array] } | Select-Object -First 1
        if ($arrayProp) {
            $data = $arrayProp.Value
        }
    }

    $data
}

function Invoke-InforcerHttpRequest {
    # Invoke-RestMethod that returns HTTP errors instead of throwing them, so a caller's -ErrorVariable
    # only ever holds the module's own error record. Network failures still throw.
    # Redirects are never followed: the request carries the API key, token or client secret.
    param([Parameter(Mandatory = $true)][hashtable]$Request)

    $statusCode = $null
    $responseHeaders = $null
    # -ErrorAction Ignore: a 3xx also raises a non-terminating 'maximum redirection' record (holding the request headers); network failures still throw.
    $body = Invoke-RestMethod @Request -MaximumRedirection 0 -SkipHttpErrorCheck -StatusCodeVariable statusCode -ResponseHeadersVariable responseHeaders -Verbose:$false -Debug:$false -ErrorAction Ignore
    if ($statusCode -ge 300 -and $statusCode -lt 400) {
        throw (Get-InforcerRedirectMessage -StatusCode $statusCode -Headers $responseHeaders)
    }
    [PSCustomObject]@{
        StatusCode = if ($statusCode) { [int]$statusCode } else { 200 }
        Body       = $body
        Headers    = $responseHeaders
    }
}

function Get-InforcerRedirectMessage {
    param([int]$StatusCode, $Headers)

    $location = Get-InforcerHeaderValue -Headers $Headers -Name 'Location'
    $target = if ($location) { " to '$location'" } else { '' }
    "The API answered with a redirect (HTTP $StatusCode)$target. The module does not follow redirects, so credentials are never sent to another address. Check -BaseUrl or -Region."
}

function Format-InforcerProblemError {
    # problem+json errors{}: { "<field>": ["message", ...] } -> "field: message; field: message"
    param($Errors)

    if ($Errors -isnot [System.Management.Automation.PSCustomObject]) { return Format-InforcerErrorDetail -Errors $Errors }
    $parts = foreach ($p in $Errors.PSObject.Properties) {
        $messages = @($p.Value | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) }) -join ', '
        if ($messages) { "$($p.Name): $messages" } else { $p.Name }
    }
    if ($parts) { @($parts) -join '; ' }
}

function Get-InforcerRetryDelay {
    # Retry-After is either delay-seconds or an HTTP date; falls back to exponential backoff. Capped at 300s.
    param([string]$Value, [int]$Attempt = 1)

    $seconds = 0
    if (-not [string]::IsNullOrWhiteSpace($Value)) {
        $date = [datetimeoffset]::MinValue
        if ([int]::TryParse($Value.Trim(), [ref]$seconds)) {
            $seconds = [Math]::Max(0, $seconds)
        } elseif ([datetimeoffset]::TryParse($Value.Trim(), [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$date)) {
            $seconds = [int][Math]::Ceiling(($date - [datetimeoffset]::UtcNow).TotalSeconds)
            $seconds = [Math]::Max(0, $seconds)
        } else {
            $seconds = [int][Math]::Pow(2, $Attempt)
        }
    } else {
        $seconds = [int][Math]::Pow(2, $Attempt)
    }
    [Math]::Min(300, [Math]::Max(1, $seconds))
}
