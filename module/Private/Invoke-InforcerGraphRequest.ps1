function Invoke-InforcerGraphRequest {
    <#
    .SYNOPSIS
        Wraps Invoke-MgGraphRequest with retry logic for documentation enrichment calls.
    .DESCRIPTION
        Sends a Graph API request with automatic retry on transient failures (throttling, server errors).
        Returns the response as a PSObject. For paged results, follows @odata.nextLink automatically.

        Based on the Invoke-GraphRequestWithPaging pattern from RKSolutions-Module.
    .PARAMETER Uri
        The Graph API URI (e.g., "https://graph.microsoft.com/v1.0/directoryObjects/{id}").
    .PARAMETER Method
        HTTP method (default: GET).
    .PARAMETER MaxRetries
        Maximum number of retry attempts for transient failures (default: 3).
    .PARAMETER SingleObject
        When set, returns the response directly (not paged). Use for single-object lookups.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter()][string]$Method = 'GET',
        [Parameter()][int]$MaxRetries = 3,
        [Parameter()][switch]$SingleObject
    )

    if ($SingleObject) {
        $retryCount = 0
        do {
            try {
                return Invoke-MgGraphRequest -Uri $Uri -Method $Method -OutputType PSObject -ErrorAction Stop
            } catch {
                $statusCode = $null
                if ($_.Exception.Response) { $statusCode = $_.Exception.Response.StatusCode.value__ }
                elseif ($_.Exception.InnerException -and $_.Exception.InnerException.Response) {
                    $statusCode = $_.Exception.InnerException.Response.StatusCode.value__
                }
                if ($statusCode -eq 404) { return $null }
                $retryCount++
                if ($retryCount -ge $MaxRetries) { return $null }
                Start-Sleep -Seconds (2 * $retryCount)
            }
        } while ($retryCount -lt $MaxRetries)
        return $null
    }

    # Paged collection request
    $results = [System.Collections.Generic.List[object]]::new()
    $currentUri = $Uri
    do {
        $retryCount = 0
        $success = $false
        do {
            try {
                $response = Invoke-MgGraphRequest -Uri $currentUri -Method $Method -OutputType PSObject -ErrorAction Stop
                $success = $true
                if ($response -and $response.PSObject.Properties['value']) {
                    if ($response.value -and $response.value.Count -gt 0) { $results.AddRange($response.value) }
                    $currentUri = $response.'@odata.nextLink'
                } else {
                    $currentUri = $null
                }
            } catch {
                $statusCode = $null
                if ($_.Exception.Response) { $statusCode = $_.Exception.Response.StatusCode.value__ }
                elseif ($_.Exception.InnerException -and $_.Exception.InnerException.Response) {
                    $statusCode = $_.Exception.InnerException.Response.StatusCode.value__
                }
                if ($statusCode -eq 400) { return $results.ToArray() }
                $retryCount++
                if ($retryCount -ge $MaxRetries) { return $results.ToArray() }
                Start-Sleep -Seconds (2 * $retryCount)
            }
        } while (-not $success -and $retryCount -lt $MaxRetries)
        if (-not $success) { break }
        if ($results.Count -gt 10000) { break }
    } while ($currentUri)

    $results.ToArray()
}
