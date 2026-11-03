function Invoke-InforcerPagedRequest {
    <#
    .SYNOPSIS
        Returns all items of a paged Inforcer API list, following continuationToken (Private helper).
    .DESCRIPTION
        Works for both API versions. GET passes continuationToken in the query string; POST passes it in
        the JSON body. Items come from the beta .data array (or the array inside .data, e.g. .data.items)
        or the v1 collection. Stops when the token is empty or repeats, or when -MaxResults is reached.
        An API error is written to the error stream and ends paging; items already read are returned.
    .PARAMETER Endpoint
        Version-neutral API path, may already contain a query string.
    .PARAMETER Method
        GET (default) or POST.
    .PARAMETER Body
        POST body as a hashtable; continuationToken is added per page.
    .PARAMETER ObjectType
        v1 only: maps items to canonical property names.
    .PARAMETER MaxResults
        Stop after this many items. 0 = no limit.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Endpoint,

        [Parameter(Mandatory = $false)]
        [ValidateSet('GET', 'POST')]
        [string]$Method = 'GET',

        [Parameter(Mandatory = $false)]
        [hashtable]$Body,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Tenant', 'Policy', 'Baseline', 'AlignmentScore', 'AlignmentDetails', 'User', 'Group', 'GroupMember', 'Role',
            'SecureScore', 'Assessment', 'AssessmentRun', 'ReportType', 'ReportRun', 'ReportOutput', 'AuditEvent', 'AuditEventType')]
        [string]$ObjectType,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$MaxResults = 0
    )

    $items = [System.Collections.Generic.List[object]]::new()
    $seenTokens = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $token = $null
    $page = 0

    do {
        $page++
        $request = @{ Method = $Method; PreserveFullResponse = $true }
        if ($ObjectType) { $request['ObjectType'] = $ObjectType }
        if ($Method -eq 'POST') {
            $pageBody = if ($Body) { $Body.Clone() } else { @{} }
            if ($token) { $pageBody['continuationToken'] = $token } else { $pageBody.Remove('continuationToken') }
            $request['Body'] = $pageBody | ConvertTo-Json -Depth 100 -Compress
            $request['Endpoint'] = $Endpoint
        } else {
            $request['Endpoint'] = if ($token) {
                $Endpoint + $(if ($Endpoint.Contains('?')) { '&' } else { '?' }) + 'continuationToken=' + [System.Uri]::EscapeDataString($token)
            } else { $Endpoint }
        }

        $response = Invoke-InforcerApiRequest @request
        if ($null -eq $response) { break }

        $pageItems = $null
        $container = $response
        $dataProp = $response.PSObject.Properties['data']
        if ($dataProp) {
            $container = $dataProp.Value
            if ($container -is [array]) { $pageItems = $container }
            elseif ($container -is [System.Management.Automation.PSCustomObject]) {
                $arrayProp = $container.PSObject.Properties | Where-Object { $_.Value -is [array] } | Select-Object -First 1
                if ($arrayProp) { $pageItems = $arrayProp.Value }
            }
        } else {
            $collectionName = Get-InforcerV1CollectionName -Response $response
            if ($collectionName) { $pageItems = $response.$collectionName }
            elseif ($response -is [array]) { $pageItems = $response }
        }

        foreach ($i in @($pageItems)) {
            if ($null -eq $i) { continue }
            $items.Add($i)
            if ($MaxResults -gt 0 -and $items.Count -ge $MaxResults) { break }
        }
        if ($MaxResults -gt 0 -and $items.Count -ge $MaxResults) { break }

        $next = $response.PSObject.Properties['continuationToken'].Value -as [string]
        if ([string]::IsNullOrWhiteSpace($next) -and $container -is [System.Management.Automation.PSCustomObject]) {
            $next = $container.PSObject.Properties['continuationToken'].Value -as [string]
        }
        if ([string]::IsNullOrWhiteSpace($next)) { break }
        if (-not $seenTokens.Add($next)) {
            Write-Verbose 'API returned a continuationToken it already returned. Stopping pagination.'
            break
        }
        Write-Verbose "Page $page returned $(@($pageItems).Count) item(s); fetching the next page."
        $token = $next
    } while ($true)

    $items.ToArray()
}
