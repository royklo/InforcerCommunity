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
        [string]$OutputType = 'PowerShellObject'
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
        $response = Invoke-RestMethod @params
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
        $detail = $detail -replace [regex]::Escape($apiKey), '[REDACTED]'
        Write-Error -Message "Inforcer API request failed (HTTP $statusCode): $detail" `
            -ErrorId 'ApiRequestFailed' `
            -Category ConnectionError
        return
    }

    $rawResponse = $response
    if ($response -is [string]) {
        try {
            $rawResponse = $response | ConvertFrom-Json
        } catch {
            Write-Error -Message "API returned non-JSON response. Base URL may be incorrect. Response starts with: $($response.Substring(0, [Math]::Min(200, $response.Length)))..." `
                -ErrorId 'NonJsonResponse' `
                -Category InvalidData
            return
        }
    }

    if ($null -eq $rawResponse) {
        Write-Error -Message 'API returned an empty or invalid response.' -ErrorId 'EmptyResponse' -Category InvalidData
        return
    }

    $data = $rawResponse
    if ($rawResponse.PSObject.Properties['success']) {
        if (-not $rawResponse.success) {
            $msg = if ($rawResponse.message) { $rawResponse.message } else { 'API request failed' }
            if ($rawResponse.errors -is [array] -and $rawResponse.errors.Count -gt 0) {
                $msg += ' - ' + ($rawResponse.errors -join ', ')
            }
            Write-Error -Message $msg -ErrorId 'ApiError' -Category InvalidOperation
            return
        }
    }
    # Unwrap response.data when present (API often returns { "data": [...] } with or without "success")
    $dataProp = $rawResponse.PSObject.Properties['data']
    if ($dataProp -and $null -ne $dataProp.Value) {
        $data = $dataProp.Value
    }

    if ($OutputType -eq 'JsonObject') {
        $json = $data | ConvertTo-Json -Depth 100
        return $json
    }

    # If data is a single object with one array property (e.g. value, items, policies), unwrap to that array
    if ($data -isnot [array] -and $data -is [PSObject]) {
        $arrayProp = $data.PSObject.Properties | Where-Object { $_.Value -is [array] } | Select-Object -First 1
        if ($arrayProp) {
            $data = $arrayProp.Value
        }
    }

    if ($data -is [array]) {
        $data | ForEach-Object { $_ }
    } else {
        $data
    }
}
