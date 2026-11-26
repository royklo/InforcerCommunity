function Get-InforcerTdrLog {
    <#
    .SYNOPSIS
        Searches the raw log events inforcer's threat detection and response (TDR) collected from a tenant.

        Required API scope(s): none; the API-key (beta) API has no TDR endpoints.
        Required permission: Threats, view events (API client, tdr:events:view).

    .DESCRIPTION
        POST /tdr/logs/search: one tenant's log events in the date range, newest first. The logs are
        Microsoft Entra interactive user sign-ins, service principal sign-ins and directory audits, and
        Microsoft 365 audit events; non-interactive user sign-ins are not included. Every event carries
        the fields all logs share, plus one object named after its logType (signIn,
        servicePrincipalSignIn, directoryAudit or m365Audit) with the rest.

        inforcer searches at most 24 hours at a time and only the last 30 days. Without -DateFrom the
        cmdlet searches the last 24 hours; a longer range is searched in 24-hour steps, newest first.
        Every step and every page of 500 events is one search, and inforcer allows 20 searches per 5
        minutes and 1000 a day for all your API clients together. Past that limit the cmdlet waits as
        long as inforcer asks and carries on, so a long range on a busy tenant can take a while: narrow
        it with -LogType, -UserPrincipalName or -MaxResults. A search that fails ends the cmdlet; the
        events found until then are still returned.

        Needs a login with an API client (Connect-Inforcer -ClientId -ClientSecret); an API-key login
        gets the error RequiresApiClient.

    .PARAMETER Format
        Raw (default).

    .PARAMETER TenantId
        The tenant: Microsoft tenant ID (GUID) or tenant name. Supports pipeline input; piped tenants
        are searched one after the other.

    .PARAMETER LogType
        Which log to search: signIn, servicePrincipalSignIn, directoryAudit, m365Audit, or all
        (default) for every log together.

    .PARAMETER UserPrincipalName
        Only events of this user: the user who signed in, or who acted in an audit event. Matched
        whole, without regard to case. Not allowed with -LogType servicePrincipalSignIn.

    .PARAMETER IncludeSimulated
        Also return the events a threat simulation wrote, which are not real activity. Each event says
        whether it is simulated.

    .PARAMETER DateFrom
        Only events at or after this time, at most 30 days ago. Default: 24 hours before -DateTo.
        A range longer than 24 hours costs at least one search per 24 hours.

    .PARAMETER DateTo
        Only events at or before this time. Default: now.

    .PARAMETER MaxResults
        Stop after this many events. 0 = no limit (default).

    .PARAMETER OutputType
        PowerShellObject (default) or JsonObject. JSON output uses Depth 100.

    .EXAMPLE
        Get-InforcerTdrLog -TenantId 'Contoso'

        Every log event of the last 24 hours.

    .EXAMPLE
        Get-InforcerTdrLog -TenantId 'Contoso' -LogType signIn -UserPrincipalName 'jo.bloggs@contoso.com' -DateFrom (Get-Date).AddDays(-7)

        One user's sign-ins of the last week (seven searches).

    .EXAMPLE
        Get-InforcerTdrLog -TenantId 'Contoso' -LogType directoryAudit | Where-Object { $_.directoryAudit.category -eq 'RoleManagement' }

        Yesterday's role changes.

    .EXAMPLE
        Get-InforcerTdrLog -TenantId 'Contoso' -LogType m365Audit -MaxResults 100 -OutputType JsonObject

        The 100 newest Microsoft 365 audit events of the last 24 hours as a JSON array.

    .OUTPUTS
        PSObject (InforcerCommunity.TdrLogEvent) or String (JSON array)

    .LINK
        https://github.com/royklo/InforcerCommunity/blob/main/docs/CMDLET-REFERENCE.md#get-inforcertdrlog

    .LINK
        Get-InforcerTdrThreat

    .LINK
        Get-InforcerTdrIndicator
    #>
    [CmdletBinding()]
    [OutputType([PSObject], [string])]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet('Raw')]
        [string]$Format = 'Raw',

        [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
        [Alias('ClientTenantId', 'MsTenantId')]
        [object]$TenantId,

        [Parameter(Mandatory = $false)]
        [ValidateSet('all', 'signIn', 'servicePrincipalSignIn', 'directoryAudit', 'm365Audit')]
        [string]$LogType,

        [Parameter(Mandatory = $false)]
        [ValidateLength(1, 320)]
        [string]$UserPrincipalName,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeSimulated,

        [Parameter(Mandatory = $false)]
        [DateTime]$DateFrom,

        [Parameter(Mandatory = $false)]
        [DateTime]$DateTo,

        [Parameter(Mandatory = $false)]
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
            Write-Error -Message 'Threat detection and response logs need a login with an API client (Connect-Inforcer -ClientId -ClientSecret). The API-key (beta) API has no threat detection and response endpoints.' -ErrorId 'RequiresApiClient' -Category InvalidOperation
            return
        }
        if ($UserPrincipalName -and $LogType -eq 'servicePrincipalSignIn') {
            Write-Error -Message '-UserPrincipalName cannot be used with -LogType servicePrincipalSignIn: a service principal sign-in has no user.' -ErrorId 'UserPrincipalNameNotAllowed' -Category InvalidArgument
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
        if (-not $ready -or -not $tenants.Count) { return }

        $to = if ($PSBoundParameters.ContainsKey('DateTo')) { $DateTo.ToUniversalTime() } else { [DateTime]::UtcNow }
        $from = if ($PSBoundParameters.ContainsKey('DateFrom')) { $DateFrom.ToUniversalTime() } else { $to.AddHours(-24) }
        # The API takes whole seconds; the window edges below are compared with event times.
        $to = $to.AddTicks(-($to.Ticks % [TimeSpan]::TicksPerSecond))
        $from = $from.AddTicks(-($from.Ticks % [TimeSpan]::TicksPerSecond))
        if ($from -gt $to) {
            Write-Error -Message '-DateFrom must be before -DateTo.' -ErrorId 'InvalidDateRange' -Category InvalidArgument
            return
        }
        # (Get-Date).AddDays(-30) is already a moment too old when it gets here, so allow a little slack.
        if ($from -lt [DateTime]::UtcNow.AddDays(-30).AddMinutes(-5)) {
            Write-Error -Message 'inforcer searches only the last 30 days of log events: -DateFrom must be at most 30 days ago.' -ErrorId 'InvalidDateRange' -Category InvalidArgument
            return
        }

        $body = @{ pageSize = $(if ($MaxResults -gt 0 -and $MaxResults -lt 500) { $MaxResults } else { 500 }) }
        if ($LogType) { $body['logType'] = $LogType }
        if ($UserPrincipalName) { $body['userPrincipalName'] = $UserPrincipalName }
        if ($IncludeSimulated) { $body['includeSimulated'] = $true }

        $events = [System.Collections.Generic.List[object]]::new()
        $failed = $null
        foreach ($tenant in @($tenants | Select-Object -Unique)) {
            $body['msTenantId'] = $tenant
            $windowTo = $to
            $edge = $null
            do {
                $windowFrom = if ($windowTo.AddHours(-24) -gt $from) { $windowTo.AddHours(-24) } else { $from }
                # inforcer refuses a dateFrom of 30 days ago or older, and a long search reaches its last window late.
                $oldest = [DateTime]::UtcNow.AddDays(-30).AddMinutes(5)
                if ($windowFrom -lt $oldest) { $windowFrom = $oldest.AddTicks(-($oldest.Ticks % [TimeSpan]::TicksPerSecond)) }
                if ($windowFrom -gt $windowTo -or ($edge -and $windowFrom -eq $windowTo)) { break }
                $body['dateFrom'] = $windowFrom.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [cultureinfo]::InvariantCulture)
                $body['dateTo'] = $windowTo.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [cultureinfo]::InvariantCulture)
                $left = if ($MaxResults -gt 0) { $MaxResults - $events.Count } else { 0 }
                foreach ($e in @(Invoke-InforcerPagedRequest -Endpoint '/tdr/logs/search' -Method POST -Body $body -MaxResults $left -ErrorVariable failed)) {
                    if ($null -eq $e) { continue }
                    # Both ends of a window count, so an event exactly on an edge is also in the newer window:
                    # skip it here. Ids cannot tell: several events share one.
                    # ponytail: such a skip can leave the result one short of -MaxResults; ask for one more if that matters.
                    $time = $e.eventTime -as [DateTime]
                    if ($edge -and $time -and $time.ToUniversalTime() -ge $edge) { continue }
                    $e.PSObject.TypeNames.Insert(0, 'InforcerCommunity.TdrLogEvent')
                    $events.Add($e)
                }
                $edge = $windowTo = $windowFrom
            } while (-not $failed -and $windowTo -gt $from -and ($MaxResults -eq 0 -or $events.Count -lt $MaxResults))
            if ($failed -or ($MaxResults -gt 0 -and $events.Count -ge $MaxResults)) { break }
        }

        if ($OutputType -eq 'JsonObject') { return ConvertTo-Json -InputObject @($events) -Depth 100 }
        foreach ($e in $events) { $e }
    }
}
