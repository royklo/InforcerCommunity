function Get-InforcerThreatIndicator {
    <#
    .SYNOPSIS
        Retrieves the indicators (detections) inforcer's threat detection and response (TDR) raised, or one indicator by id.

        Required API scope(s): none; the API-key (beta) API has no TDR endpoints.
        Required permission: Threats, view indicators (API client, tdr:indicators:view).

    .DESCRIPTION
        Without -IndicatorId: POST /tdr/indicators/search, the indicators whose event happened in the
        date range, newest first, across the tenants you pass (or every tenant the API client may view
        TDR indicators on). Each indicator comes back once, in its latest version within the range. An
        indicator with no event time is placed by when it was detected. inforcer searches at most 30 days
        at a time, so a longer range is searched in 30-day steps (one search each, newest first); without
        -DateFrom the cmdlet searches the last 30 days.

        With -IndicatorId: GET /tdr/indicators/{indicatorId}, the latest version of that indicator. The
        id comes from a search or from a threat's iocs (Get-InforcerThreat -ThreatId).

        Needs a login with an API client (Connect-Inforcer -ClientId -ClientSecret); an API-key login
        gets the error RequiresApiClient.

    .PARAMETER Format
        Raw (default).

    .PARAMETER TenantId
        Only indicators in these tenants: Microsoft tenant ID (GUID) or tenant name. Supports pipeline
        input; piped tenants are searched in one request.

    .PARAMETER IndicatorId
        Return this indicator. The id is opaque: pass it exactly as a search or a threat's iocs gave it.

    .PARAMETER ThreatId
        Only the indicators behind this threat whose event happened in the date range. inforcer refuses
        a threat with more than 2000 indicators in one 30-day step; narrow it with -AlertType.

    .PARAMETER Severity
        Only indicators of these severities: info, medium, high, critical.

    .PARAMETER AlertType
        Only indicators of these alert types, such as TorExitNode.

    .PARAMETER DateFrom
        Only indicators whose event happened at or after this time. Default: 30 days before -DateTo.
        A range longer than 30 days costs one search per 30 days.

    .PARAMETER DateTo
        Only indicators whose event happened at or before this time. Default: now.

    .PARAMETER MaxResults
        Stop after this many indicators. 0 = no limit (default).

    .PARAMETER OutputType
        PowerShellObject (default) or JsonObject. JSON output uses Depth 100.

    .EXAMPLE
        Get-InforcerThreatIndicator -Severity high, critical

        The high and critical indicators of the last 30 days, across every tenant.

    .EXAMPLE
        Get-InforcerThreatIndicator -ThreatId '00000000-0000-0000-0000-0000000000d1' -DateFrom (Get-Date).AddDays(-90)

        The indicators behind one threat over the last 90 days (three searches).

    .EXAMPLE
        (Get-InforcerThreat -ThreatId '00000000-0000-0000-0000-0000000000d1').iocs | Where-Object indicatorId | ForEach-Object { Get-InforcerThreatIndicator -IndicatorId $_.indicatorId }

        Every indicator attached to a threat, whatever its age.

    .EXAMPLE
        Get-InforcerThreatIndicator -AlertType TorExitNode -OutputType JsonObject

        The Tor indicators of the last 30 days as a JSON array (one JSON object with -IndicatorId).

    .OUTPUTS
        PSObject (InforcerCommunity.ThreatIndicator) or String (JSON array, or one JSON object with -IndicatorId)

    .LINK
        https://github.com/royklo/InforcerCommunity/blob/main/docs/CMDLET-REFERENCE.md#get-inforcerthreatindicator

    .LINK
        Get-InforcerThreat
    #>
    [CmdletBinding(DefaultParameterSetName = 'Search')]
    [OutputType([PSObject], [string])]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet('Raw')]
        [string]$Format = 'Raw',

        [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true, ParameterSetName = 'Search')]
        [Alias('ClientTenantId', 'MsTenantId')]
        [object]$TenantId,

        [Parameter(Mandatory = $true, ParameterSetName = 'ById')]
        [ValidateLength(1, 4096)]
        [string]$IndicatorId,

        [Parameter(ParameterSetName = 'Search')]
        [guid]$ThreatId,

        [Parameter(ParameterSetName = 'Search')]
        [ValidateSet('info', 'medium', 'high', 'critical')]
        [string[]]$Severity,

        [Parameter(ParameterSetName = 'Search')]
        [string[]]$AlertType,

        [Parameter(ParameterSetName = 'Search')]
        [DateTime]$DateFrom,

        [Parameter(ParameterSetName = 'Search')]
        [DateTime]$DateTo,

        [Parameter(ParameterSetName = 'Search')]
        [ValidateRange(0, [int]::MaxValue)]
        [int]$MaxResults = 0,

        [Parameter(Mandatory = $false)]
        [ValidateSet('PowerShellObject', 'JsonObject')]
        [string]$OutputType = 'PowerShellObject'
    )

    begin {
        $tenants = [System.Collections.Generic.List[string]]::new()
        $ready = $false
        if (-not (Test-InforcerSession)) {
            Write-Error -Message 'Not connected yet. Please run Connect-Inforcer first.' -ErrorId 'NotConnected' -Category ConnectionError
            return
        }
        if ($script:InforcerSession.ApiVersion -ne 'v1') {
            Write-Error -Message 'Threat indicators need a login with an API client (Connect-Inforcer -ClientId -ClientSecret). The API-key (beta) API has no threat detection and response endpoints.' -ErrorId 'RequiresApiClient' -Category InvalidOperation
            return
        }
        $ready = $true
    }

    process {
        if (-not $ready) { return }
        foreach ($t in @($TenantId | Where-Object { $null -ne $_ -and "$_" -ne '' })) {
            try {
                $tenants.Add((Resolve-InforcerTenantId -TenantId $t))
            } catch {
                Write-Error -Message $_.Exception.Message -ErrorId 'InvalidTenantId' -Category InvalidArgument
                $ready = $false
                return
            }
        }
    }

    end {
        if (-not $ready) { return }

        if ($PSCmdlet.ParameterSetName -eq 'ById') {
            $indicator = Invoke-InforcerApiRequest -Endpoint "/tdr/indicators/$([System.Uri]::EscapeDataString($IndicatorId))" -Method GET -PreserveStructure
            if ($null -eq $indicator) { return }
            if ($OutputType -eq 'JsonObject') { return $indicator | ConvertTo-Json -Depth 100 }
            $indicator.PSObject.TypeNames.Insert(0, 'InforcerCommunity.ThreatIndicator')
            return $indicator
        }

        $to = if ($PSBoundParameters.ContainsKey('DateTo')) { $DateTo.ToUniversalTime() } else { [DateTime]::UtcNow }
        $from = if ($PSBoundParameters.ContainsKey('DateFrom')) { $DateFrom.ToUniversalTime() } else { $to.AddDays(-30) }
        if ($from -gt $to) {
            Write-Error -Message '-DateFrom must be before -DateTo.' -ErrorId 'InvalidDateRange' -Category InvalidArgument
            return
        }

        $body = @{ pageSize = $(if ($MaxResults -gt 0 -and $MaxResults -lt 500) { $MaxResults } else { 500 }) }
        if ($tenants.Count) { $body['msTenantIds'] = @($tenants | Select-Object -Unique) }
        if ($PSBoundParameters.ContainsKey('ThreatId')) { $body['threatId'] = "$ThreatId" }
        if ($Severity) { $body['severities'] = @($Severity) }
        if ($AlertType) { $body['alertTypes'] = @($AlertType) }

        # inforcer searches at most 30 days at a time: walk back from -DateTo in 30-day (UTC) windows.
        # An indicator on a window edge comes back twice, so keep the first (newest) copy.
        $seen = [System.Collections.Generic.HashSet[string]]::new()
        $indicators = [System.Collections.Generic.List[object]]::new()
        $windowTo = $to
        do {
            $windowFrom = if ($windowTo.AddDays(-30) -gt $from) { $windowTo.AddDays(-30) } else { $from }
            $body['dateFrom'] = $windowFrom.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [cultureinfo]::InvariantCulture)
            $body['dateTo'] = $windowTo.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [cultureinfo]::InvariantCulture)
            $left = if ($MaxResults -gt 0) { $MaxResults - $indicators.Count } else { 0 }
            foreach ($i in @(Invoke-InforcerPagedRequest -Endpoint '/tdr/indicators/search' -Method POST -Body $body -MaxResults $left)) {
                if ($null -eq $i -or -not $seen.Add("$($i.id)")) { continue }
                $i.PSObject.TypeNames.Insert(0, 'InforcerCommunity.ThreatIndicator')
                $indicators.Add($i)
            }
            $windowTo = $windowFrom
        } while ($windowTo -gt $from -and ($MaxResults -eq 0 -or $indicators.Count -lt $MaxResults))

        if ($OutputType -eq 'JsonObject') { return ConvertTo-Json -InputObject @($indicators) -Depth 100 }
        foreach ($i in $indicators) { $i }
    }
}
