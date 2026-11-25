function Get-InforcerTdrThreat {
    <#
    .SYNOPSIS
        Retrieves the threats inforcer's threat detection and response (TDR) raised, or one threat by id.

        Required API scope(s): none; the API-key (beta) API has no TDR endpoints.
        Required permission: Threats, view incidents (API client, tdr:incidents:view).

    .DESCRIPTION
        Without -ThreatId: POST /tdr/threats/search, the threats open at any time in the date range,
        newest first, across the tenants you pass (or every tenant the API client may view TDR
        incidents on). Without -DateFrom and -DateTo inforcer searches the last 7 days. Threats spawned
        from another threat are not listed; read them with -ThreatId.

        With -ThreatId: GET /tdr/threats/{threatId}, the threat plus its AI-written summary (Markdown)
        and iocs, each with the indicatorId to pass to Get-InforcerTdrIndicator -IndicatorId.

        Needs a login with an API client (Connect-Inforcer -ClientId -ClientSecret); an API-key login
        gets the error RequiresApiClient.

    .PARAMETER Format
        Raw (default).

    .PARAMETER TenantId
        Only threats in these tenants: Microsoft tenant ID (GUID) or tenant name. Supports pipeline input;
        piped tenants are searched in one request.

    .PARAMETER ThreatId
        Return this threat, with its summary and IoCs.

    .PARAMETER Status
        Only threats in these statuses: open, triaging, remediating, pendingReview, closed.

    .PARAMETER Severity
        Only threats of these severities: info, medium, high, critical.

    .PARAMETER Verdict
        Only closed threats with these verdicts: remediated, falsePositive, acceptedRisk, merged.

    .PARAMETER DateFrom
        Only threats still open at or after this time. Default: 7 days before -DateTo.

    .PARAMETER DateTo
        Only threats opened at or before this time. Default: now.

    .PARAMETER MaxResults
        Stop after this many threats. 0 = no limit (default).

    .PARAMETER OutputType
        PowerShellObject (default) or JsonObject. JSON output uses Depth 100.

    .EXAMPLE
        Get-InforcerTdrThreat -Status open, triaging, remediating -Severity high, critical

        The open high and critical threats of the last 7 days, across every tenant.

    .EXAMPLE
        Get-InforcerTdrThreat -TenantId 'Contoso' -DateFrom (Get-Date).AddDays(-30)

        Every threat in Contoso open in the last 30 days.

    .EXAMPLE
        (Get-InforcerTdrThreat -ThreatId '00000000-0000-0000-0000-0000000000d1').summary

        The AI-written summary of one threat.

    .EXAMPLE
        Get-InforcerTdrThreat -Severity critical -OutputType JsonObject | Set-Content threats.json

        The critical threats as a JSON array (one JSON object with -ThreatId).

    .OUTPUTS
        PSObject (InforcerCommunity.TdrThreat) or String (JSON array, or one JSON object with -ThreatId)

    .LINK
        https://github.com/royklo/InforcerCommunity/blob/main/docs/CMDLET-REFERENCE.md#get-inforcertdrthreat

    .LINK
        Get-InforcerTdrIndicator
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
        [guid]$ThreatId,

        [Parameter(ParameterSetName = 'Search')]
        [ValidateSet('open', 'triaging', 'remediating', 'pendingReview', 'closed')]
        [string[]]$Status,

        [Parameter(ParameterSetName = 'Search')]
        [ValidateSet('info', 'medium', 'high', 'critical')]
        [string[]]$Severity,

        [Parameter(ParameterSetName = 'Search')]
        [ValidateSet('remediated', 'falsePositive', 'acceptedRisk', 'merged')]
        [string[]]$Verdict,

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
            Write-Error -Message 'Threats need a login with an API client (Connect-Inforcer -ClientId -ClientSecret). The API-key (beta) API has no threat detection and response endpoints.' -ErrorId 'RequiresApiClient' -Category InvalidOperation
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
            $threat = Invoke-InforcerApiRequest -Endpoint "/tdr/threats/$ThreatId" -Method GET -PreserveStructure
            if ($null -eq $threat) { return }
            if ($OutputType -eq 'JsonObject') { return $threat | ConvertTo-Json -Depth 100 }
            $threat.PSObject.TypeNames.Insert(0, 'InforcerCommunity.TdrThreat')
            return $threat
        }

        $body = @{ pageSize = $(if ($MaxResults -gt 0 -and $MaxResults -lt 500) { $MaxResults } else { 500 }) }
        if ($tenants.Count) { $body['msTenantIds'] = @($tenants | Select-Object -Unique) }
        if ($Status) { $body['statuses'] = @($Status) }
        if ($Severity) { $body['severities'] = @($Severity) }
        if ($Verdict) { $body['verdicts'] = @($Verdict) }
        if ($PSBoundParameters.ContainsKey('DateFrom')) { $body['dateFrom'] = $DateFrom.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [cultureinfo]::InvariantCulture) }
        if ($PSBoundParameters.ContainsKey('DateTo')) { $body['dateTo'] = $DateTo.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [cultureinfo]::InvariantCulture) }

        $threats = Invoke-InforcerPagedRequest -Endpoint '/tdr/threats/search' -Method POST -Body $body -MaxResults $MaxResults |
            ForEach-Object { $_.PSObject.TypeNames.Insert(0, 'InforcerCommunity.TdrThreat'); $_ }
        if ($OutputType -eq 'JsonObject') { return ConvertTo-Json -InputObject @($threats) -Depth 100 }
        $threats
    }
}
