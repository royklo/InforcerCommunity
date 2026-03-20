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
        unwrapped, but inner structure (e.g. items + continuationToken) is preserved.
        Use this when the caller needs pagination metadata alongside the results.
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
        [switch]$PreserveStructure
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
        UseBasicParsing = $true
    }
    if (-not [string]::IsNullOrWhiteSpace($Body)) {
        $params['Body'] = $Body
    }

    try {
        $webResponse = Invoke-WebRequest @params
        $responseBody = $webResponse.Content
    } catch [System.Net.WebException] {
        $statusCode = [int]$_.Exception.Response.StatusCode
        $reader = $null
        try {
            $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
            $responseBody = $reader.ReadToEnd()
        } finally {
            if ($reader) { $reader.Dispose() }
        }
        $detail = $responseBody
        try {
            $json = $responseBody | ConvertFrom-Json -ErrorAction SilentlyContinue
            if ($json.message) { $detail = $json.message }
            elseif ($json.error) { $detail = $json.error }
        } catch { }
        $apiKeyPattern = [regex]::new([regex]::Escape($apiKey), 'Compiled')
        $detail = $apiKeyPattern.Replace($detail, '[REDACTED]')
        Write-Error -Message "Inforcer API request failed (HTTP $statusCode): $detail" `
            -ErrorId 'ApiRequestFailed' `
            -Category ConnectionError
        return
    }

    if ([string]::IsNullOrWhiteSpace($responseBody)) {
        Write-Error -Message 'API returned an empty response.' -ErrorId 'EmptyResponse' -Category InvalidData
        return
    }

    try {
        $rawResponse = $responseBody | ConvertFrom-Json
    } catch {
        Write-Error -Message "API returned non-JSON response. Base URL may be incorrect. Response starts with: $($responseBody.Substring(0, [Math]::Min(200, $responseBody.Length)))..." `
            -ErrorId 'NonJsonResponse' `
            -Category InvalidData
        return
    }

    if ($null -eq $rawResponse) {
        Write-Error -Message 'API returned an invalid response.' -ErrorId 'EmptyResponse' -Category InvalidData
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
