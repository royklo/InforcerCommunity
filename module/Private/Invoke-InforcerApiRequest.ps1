function Invoke-InforcerApiRequest {
    <#
    .SYNOPSIS
        Sends a request to the Inforcer REST API (Private helper).
    .DESCRIPTION
        Uses the current session (Inf-Api-Key, BaseUrl), unwraps response.data,
        and returns PSObjects or JSON string. All JSON serialization uses -Depth 100.
    .PARAMETER Endpoint
        API path (e.g. /beta/tenants). Leading slash optional.
    .PARAMETER Method
        HTTP method. Default: GET.
    .PARAMETER Body
        Optional JSON body for POST/PUT.
    .PARAMETER OutputType
        PowerShellObject (return PSObjects) or JsonObject (return JSON string). Default: PowerShellObject.
    .PARAMETER PreserveStructure
        When set, skips the automatic array-unwrapping step. The .data wrapper is still
        unwrapped, but inner structure (e.g. items + continuationToken inside .data) is preserved.
        Use this when the caller needs pagination metadata that lives inside the .data object.
    .PARAMETER PreserveFullResponse
        When set, returns the full parsed API response without any unwrapping. Neither
        .data nor arrays are unwrapped. Use this when pagination metadata (e.g. continuationToken)
        lives at the response root level alongside .data, not inside it.
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
        [switch]$PreserveFullResponse
    )

    if (-not (Test-InforcerSession)) {
        Write-Error -Message 'Not connected. Run Connect-Inforcer first.' `
            -ErrorId 'NotConnected' `
            -Category ConnectionError
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
            -ErrorId 'EmptyApiKey' `
            -Category AuthenticationError
        return
    }

    Write-Verbose "Making $Method request to: $uri"

    $headers = @{
        'Inf-Api-Key'    = $apiKey
        'Accept'         = 'application/json'
        'Content-Type'   = 'application/json'
    }

    $params = @{
        Uri             = $uri
        Method          = $Method
        Headers         = $headers
    }
    if (-not [string]::IsNullOrWhiteSpace($Body)) {
        $params['Body'] = $Body
    }

    try {
        $rawResponse = Invoke-RestMethod @params
    } catch {
        $statusCode = 0
        $detail = $_.Exception.Message

        if ($_.Exception.Response) {
            $statusCode = [int]$_.Exception.Response.StatusCode
        }

        # PS7: ErrorDetails.Message contains the response body
        if ($_.ErrorDetails.Message) {
            $detail = $_.ErrorDetails.Message
            try {
                $json = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction SilentlyContinue
                if ($json) {
                    $errorCode = ($json.PSObject.Properties['errorCode'].Value -as [string])
                    $apiMessage = ($json.PSObject.Properties['message'].Value -as [string])
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
                            if (-not [string]::IsNullOrWhiteSpace($apiMessage)) { $apiMessage } elseif ($json.error) { $json.error } else { $detail }
                        }
                    }
                }
            } catch { }
        }
        # PS5.1 fallback: read from response stream
        elseif ($_.Exception.Response) {
            $reader = $null
            try {
                $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $responseBody = $reader.ReadToEnd()
                $detail = $responseBody
                try {
                    $json = $responseBody | ConvertFrom-Json -ErrorAction SilentlyContinue
                    if ($json.message) { $detail = $json.message }
                    elseif ($json.error) { $detail = $json.error }
                } catch { }
            } finally {
                if ($reader) { $reader.Dispose() }
            }
        }

        $apiKeyPattern = [regex]::new([regex]::Escape($apiKey), 'Compiled')
        $detail = $apiKeyPattern.Replace($detail, '[REDACTED]')
        $msg = if ($statusCode -gt 0) { "Inforcer API request failed (HTTP $statusCode): $detail" } else { "Inforcer API request failed: $detail" }
        $errorId = if ($statusCode -gt 0) { "ApiRequestFailed_$statusCode" } else { 'ApiRequestFailed' }
        Write-Error -Message $msg -ErrorId $errorId -Category ConnectionError
        return
    }

    if ($null -eq $rawResponse) {
        Write-Error -Message 'API returned an empty response.' -ErrorId 'EmptyResponse' -Category InvalidData
        return
    }

    # Invoke-RestMethod auto-parses JSON to PSObject. If the response is a string, the
    # API may have returned a non-JSON Content-Type (e.g. text/plain) despite the body
    # being valid JSON. Try to parse it before reporting as non-JSON.
    if ($rawResponse -is [string]) {
        try {
            $rawResponse = $rawResponse | ConvertFrom-Json -Depth 100 -ErrorAction Stop
        } catch {
            $preview = $rawResponse
            if ($preview.Length -gt 200) { $preview = $preview.Substring(0, 200) + '...' }
            Write-Error -Message "API returned non-JSON response. Base URL may be incorrect. Response starts with: $preview" `
                -ErrorId 'NonJsonResponse' -Category InvalidData
            return
        }
    }
    if ($rawResponse -isnot [PSObject] -and $rawResponse -isnot [array]) {
        $preview = $rawResponse.ToString()
        if ($preview.Length -gt 200) { $preview = $preview.Substring(0, 200) + '...' }
        Write-Error -Message "API returned non-JSON response. Base URL may be incorrect. Response starts with: $preview" `
            -ErrorId 'NonJsonResponse' -Category InvalidData
        return
    }

    # API error payload (success: false) — single, clean message; no stack or raw JSON
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
