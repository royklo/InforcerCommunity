function Invoke-InforcerGraphRequest {
    <#
    .SYNOPSIS
        Wraps Invoke-MgGraphRequest with retry logic for documentation enrichment calls.
    .DESCRIPTION
        Sends a Graph API request and returns the response as a PSObject. For paged results, follows
        @odata.nextLink automatically (up to 10,000 items; a warning says when more were available).

        Retries only what can succeed on a second try: throttling (429), server errors (5xx) and
        network failures. 401/403 are not retried: a warning names the permission the call most
        likely lacks and the call returns what it has. Single-object 404 returns $null.

        Based on the Invoke-GraphRequestWithPaging pattern from RKSolutions-Module.
    .PARAMETER Uri
        The Graph API URI (e.g., "https://graph.microsoft.com/v1.0/directoryObjects/{id}").
    .PARAMETER Method
        HTTP method (default: GET).
    .PARAMETER Body
        Optional JSON body (sent as application/json).
    .PARAMETER MaxRetries
        Maximum number of attempts for retryable failures (default: 3).
    .PARAMETER SingleObject
        When set, returns the response directly (not paged). Use for single-object lookups.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter()][string]$Method = 'GET',
        [Parameter()][string]$Body,
        [Parameter()][int]$MaxRetries = 3,
        [Parameter()][switch]$SingleObject
    )

    $mgParams = @{ Method = $Method; OutputType = 'PSObject'; ErrorAction = 'Stop' }
    if ($Body) { $mgParams['Body'] = $Body; $mgParams['ContentType'] = 'application/json' }

    # Returns $true when the caller should retry; warns once for a missing permission.
    $shouldRetry = {
        param($ErrorRecord, [string]$RequestUri, [int]$Attempt)
        $ex = $ErrorRecord.Exception
        $statusCode = $null
        if ($ex.Response) { $statusCode = [int]$ex.Response.StatusCode }
        elseif ($ex.InnerException -and $ex.InnerException.Response) { $statusCode = [int]$ex.InnerException.Response.StatusCode }
        if ($statusCode -in 401, 403) {
            $permission = switch -Regex ($RequestUri) {
                '/deviceManagement/'   { 'DeviceManagementConfiguration.Read.All' }
                '/conditionalAccess/'  { 'Policy.Read.All' }
                default                { 'Directory.Read.All' }
            }
            $path = ([uri]$RequestUri).AbsolutePath
            Write-Warning "Microsoft Graph refused $path (HTTP $statusCode). The signed-in account likely lacks $permission; those names stay as raw IDs."
            return $false
        }
        $retryable = $null -eq $statusCode -or $statusCode -eq 429 -or $statusCode -ge 500
        if ($retryable -and $Attempt -lt $MaxRetries) {
            Start-Sleep -Seconds (2 * $Attempt)
            return $true
        }
        $false
    }

    if ($SingleObject) {
        for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
            try {
                return Invoke-MgGraphRequest -Uri $Uri @mgParams
            } catch {
                if (-not (& $shouldRetry $_ $Uri $attempt)) { return $null }
            }
        }
        return $null
    }

    $results = [System.Collections.Generic.List[object]]::new()
    $currentUri = $Uri
    while ($currentUri) {
        $response = $null
        for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
            try {
                $response = Invoke-MgGraphRequest -Uri $currentUri @mgParams
                break
            } catch {
                if (-not (& $shouldRetry $_ $currentUri $attempt)) { return $results.ToArray() }
            }
        }
        if ($null -eq $response -or -not $response.PSObject.Properties['value']) { break }
        if ($response.value) { $results.AddRange(@($response.value)) }
        $currentUri = $response.'@odata.nextLink'
        if ($currentUri -and $results.Count -ge 10000) {
            Write-Warning "Microsoft Graph returned more than 10,000 items for $(([uri]$Uri).AbsolutePath); only the first $($results.Count) are used."
            break
        }
    }

    $results.ToArray()
}
