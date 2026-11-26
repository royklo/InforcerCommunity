# V1.Tdr.Tests.ps1
# The threat detection and response cmdlets (v1 only). Fixtures are anonymised; no network calls.

BeforeAll {
    Remove-Module -Name 'InforcerCommunity' -ErrorAction SilentlyContinue
    Import-Module (Join-Path $PSScriptRoot '../module/InforcerCommunity.psd1') -Force

    $script:T1 = '00000000-0000-0000-0000-000000000001'
    $script:T2 = '00000000-0000-0000-0000-000000000002'
    $script:Th = '00000000-0000-0000-0000-0000000000d1'

    function global:New-TdrResponse {
        param([string]$Json, [int]$Status = 200)
        [pscustomobject]@{ StatusCode = $Status; Body = ($Json | ConvertFrom-Json -Depth 100); Headers = @{} }
    }

    function global:Set-TdrSession {
        param([switch]$Beta)
        & (Get-Module InforcerCommunity) {
            param($Beta)
            $script:InforcerTenantListCache = $null
            $script:InforcerSession = @{
                AuthMode = $(if ($Beta) { 'ApiKey' } else { 'ClientCredentials' }); ApiVersion = $(if ($Beta) { 'beta' } else { 'v1' })
                ApiHost = 'https://api.example.invalid'; BaseUrl = 'https://api.example.invalid'; Region = 'uk'; ConnectedAt = Get-Date
                ApiKey = (ConvertTo-SecureString 'beta-test-key-value' -AsPlainText -Force)
                ClientId = 'client-id-example'
                ClientSecret = (ConvertTo-SecureString 'client-secret-example-value' -AsPlainText -Force)
                AccessToken = (ConvertTo-SecureString 'access-token-example-value' -AsPlainText -Force)
                TokenExpiresAt = [datetime]::UtcNow.AddMinutes(50)
            }
        } $Beta.IsPresent
    }

    function global:Set-TdrRoute {
        param([scriptblock]$Route)
        $global:TdrCalls = [System.Collections.Generic.List[object]]::new()
        $global:TdrRoute = $Route
        Mock -ModuleName InforcerCommunity Invoke-InforcerHttpRequest {
            $global:TdrCalls.Add([pscustomobject]@{ Uri = [string]$Request.Uri; Method = $Request.Method; Body = $Request.Body })
            & $global:TdrRoute ([string]$Request.Uri) $Request.Method $Request.Body
        }
    }

    $script:ThreatJson = '{"id":"' + $script:Th + '","msTenantId":"' + $script:T1 + '","subjectKind":"user","userPrincipalName":"jo@contoso.com","userDisplayName":"Jo Bloggs","userId":"00000000-0000-0000-0000-000000000005","status":"remediating","verdict":null,"severity":"high","classification":"potentialCompromise","openedAt":"2026-11-18T09:14:03Z","closedAt":null,"mergedIntoThreatId":null,"simulated":false,"raisedViaBackfill":false,"subjectDeviceName":null,"linkedDevices":[],"devicesAffected":0'
    $script:IndicatorJson = '{"id":"b3BhcXVlL2lkKz0=","msTenantId":"' + $script:T1 + '","alertType":"TorExitNode","severity":"high","mitreStage":"initialAccess","detectedAt":"2026-11-18T09:12:40Z","eventTime":"2026-11-18T09:11:58Z","userPrincipalName":"jo@contoso.com","description":"Activity came through Tor."}'
}

AfterAll {
    foreach ($f in 'New-TdrResponse', 'Set-TdrSession', 'Set-TdrRoute') { Remove-Item "function:global:$f" -ErrorAction SilentlyContinue }
    Remove-Variable -Name TdrCalls, TdrRoute, TdrLogEvents -Scope Global -ErrorAction SilentlyContinue
    & (Get-Module InforcerCommunity) { $script:InforcerSession = $null; $script:InforcerTenantListCache = $null }
}

Describe 'Get-InforcerTdrThreat' {
    It 'searches with the filters in the body and follows the continuation token' {
        Set-TdrSession
        Set-TdrRoute {
            param($Uri, $Method, $Body)
            if (($Body | ConvertFrom-Json).continuationToken -eq 'p2') { return New-TdrResponse ('{"threats":[' + ($script:ThreatJson -replace '0d1"', '0d2"') + '}],"continuationToken":null}') }
            New-TdrResponse ('{"threats":[' + $script:ThreatJson + '}],"continuationToken":"p2"}')
        }
        $from = [datetime]::new(2026, 11, 1, 0, 0, 0, [DateTimeKind]::Utc)
        $r = @(Get-InforcerTdrThreat -TenantId $script:T1 -Status open, remediating -Severity high -Verdict merged -DateFrom $from -ErrorVariable e)
        $e | Should -BeNullOrEmpty
        $r.Count | Should -Be 2
        $r[0].PSObject.TypeNames[0] | Should -Be 'InforcerCommunity.TdrThreat'
        $global:TdrCalls[0].Method | Should -Be 'POST'
        $global:TdrCalls[0].Uri | Should -Be 'https://api.example.invalid/v1/tdr/threats/search'
        $b = $global:TdrCalls[0].Body | ConvertFrom-Json
        $b.msTenantIds | Should -Be @($script:T1)
        $b.statuses | Should -Be @('open', 'remediating')
        $b.severities | Should -Be @('high')
        $b.verdicts | Should -Be @('merged')
        $global:TdrCalls[0].Body | Should -Match '"dateFrom":"2026-11-01T00:00:00Z"'
        $b.PSObject.Properties['dateTo'] | Should -BeNullOrEmpty
        $b.pageSize | Should -Be 500
        ($global:TdrCalls[1].Body | ConvertFrom-Json).continuationToken | Should -Be 'p2'
    }

    It 'sends no tenant or date filter by default and caps the page at -MaxResults' {
        Set-TdrSession
        Set-TdrRoute { param($Uri, $Method, $Body) New-TdrResponse ('{"threats":[' + $script:ThreatJson + '}],"continuationToken":"more"}') }
        $r = @(Get-InforcerTdrThreat -MaxResults 1)
        $r.Count | Should -Be 1
        $global:TdrCalls.Count | Should -Be 1
        $b = $global:TdrCalls[0].Body | ConvertFrom-Json
        $b.pageSize | Should -Be 1
        foreach ($k in 'msTenantIds', 'statuses', 'dateFrom', 'dateTo') { $b.PSObject.Properties[$k] | Should -BeNullOrEmpty }
    }

    It 'searches piped tenants in one request' {
        Set-TdrSession
        Set-TdrRoute { param($Uri, $Method, $Body) New-TdrResponse '{"threats":[],"continuationToken":null}' }
        $r = @([pscustomobject]@{ MsTenantId = $script:T1 }, [pscustomobject]@{ MsTenantId = $script:T2 } | Get-InforcerTdrThreat)
        $r.Count | Should -Be 0
        $global:TdrCalls.Count | Should -Be 1
        ($global:TdrCalls[0].Body | ConvertFrom-Json).msTenantIds | Should -Be @($script:T1, $script:T2)
    }

    It 'returns one threat with its summary and IoCs by id' {
        Set-TdrSession
        Set-TdrRoute { param($Uri, $Method, $Body) New-TdrResponse ($script:ThreatJson + ',"summary":"A **Tor** sign-in.","iocs":[{"iocId":"abc","indicatorId":"b3BhcXVlL2lkKz0="},{"iocId":"def","indicatorId":null}]}') }
        $t = Get-InforcerTdrThreat -ThreatId $script:Th
        $global:TdrCalls[0].Method | Should -Be 'GET'
        $global:TdrCalls[0].Uri | Should -Be "https://api.example.invalid/v1/tdr/threats/$($script:Th)"
        $t.PSObject.TypeNames[0] | Should -Be 'InforcerCommunity.TdrThreat'
        $t.summary | Should -Be 'A **Tor** sign-in.'
        @($t.iocs).Count | Should -Be 2
        @($t.linkedDevices).Count | Should -Be 0
        (Get-InforcerTdrThreat -ThreatId $script:Th -OutputType JsonObject | ConvertFrom-Json).iocs[0].iocId | Should -Be 'abc'
    }

    It 'returns a JSON array for a search, even with one threat' {
        Set-TdrSession
        Set-TdrRoute { param($Uri, $Method, $Body) New-TdrResponse ('{"threats":[' + $script:ThreatJson + '}],"continuationToken":null}') }
        $json = Get-InforcerTdrThreat -OutputType JsonObject
        $json.TrimStart() | Should -BeLike '`[*'
        @($json | ConvertFrom-Json).Count | Should -Be 1
    }

    It 'accepts the benign verdict' {
        Set-TdrSession
        Set-TdrRoute { param($Uri, $Method, $Body) New-TdrResponse '{"threats":[],"continuationToken":null}' }
        $null = Get-InforcerTdrThreat -Verdict benign -ErrorVariable e
        $e | Should -BeNullOrEmpty
        ($global:TdrCalls[0].Body | ConvertFrom-Json).verdicts | Should -Be @('benign')
    }

    It 'reports a 404 for an unknown threat' {
        Set-TdrSession
        Set-TdrRoute { param($Uri, $Method, $Body) New-TdrResponse '{"title":"Not found","status":404}' 404 }
        $t = Get-InforcerTdrThreat -ThreatId $script:Th -ErrorAction SilentlyContinue -ErrorVariable e
        $t | Should -BeNullOrEmpty
        "$($e[-1])" | Should -BeLike '*404*'
    }

    It 'needs an API client login' {
        Set-TdrSession -Beta
        Set-TdrRoute { param($Uri, $Method, $Body) throw 'no request expected' }
        Get-InforcerTdrThreat -ErrorAction SilentlyContinue -ErrorVariable e
        $e[-1].FullyQualifiedErrorId | Should -BeLike 'RequiresApiClient*'
        $global:TdrCalls.Count | Should -Be 0
    }
}

Describe 'Get-InforcerTdrIndicator' {
    It 'always sends a date range of 30 days ending now by default' {
        Set-TdrSession
        Set-TdrRoute { param($Uri, $Method, $Body) New-TdrResponse ('{"indicators":[' + $script:IndicatorJson + '],"continuationToken":null}') }
        $r = @(Get-InforcerTdrIndicator -ErrorVariable e)
        $e | Should -BeNullOrEmpty
        $r.Count | Should -Be 1
        $r[0].PSObject.TypeNames[0] | Should -Be 'InforcerCommunity.TdrIndicator'
        $global:TdrCalls[0].Uri | Should -Be 'https://api.example.invalid/v1/tdr/indicators/search'
        $b = $global:TdrCalls[0].Body | ConvertFrom-Json
        $to = ([datetime]$b.dateTo).ToUniversalTime()
        $from = ([datetime]$b.dateFrom).ToUniversalTime()
        ($to - $from).TotalDays | Should -Be 30
        ([datetime]::UtcNow - $to).TotalMinutes | Should -BeLessThan 5
    }

    It 'sends every filter and searches a range longer than 30 days in 30-day steps, newest first' {
        Set-TdrSession
        Set-TdrRoute { param($Uri, $Method, $Body) New-TdrResponse '{"indicators":[],"continuationToken":null}' }
        $from = [datetime]::new(2026, 9, 1, 0, 0, 0, [DateTimeKind]::Utc)
        $to = [datetime]::new(2026, 11, 10, 0, 0, 0, [DateTimeKind]::Utc)
        $null = Get-InforcerTdrIndicator -TenantId $script:T1 -ThreatId $script:Th -Severity high, critical -AlertType TorExitNode -DateFrom $from -DateTo $to
        $global:TdrCalls.Count | Should -Be 3
        $global:TdrCalls[0].Body | Should -Match '"dateFrom":"2026-10-11T00:00:00Z"'
        $global:TdrCalls[0].Body | Should -Match '"dateTo":"2026-11-10T00:00:00Z"'
        $global:TdrCalls[1].Body | Should -Match '"dateFrom":"2026-09-11T00:00:00Z"'
        $global:TdrCalls[2].Body | Should -Match '"dateFrom":"2026-09-01T00:00:00Z"'
        $global:TdrCalls[2].Body | Should -Match '"dateTo":"2026-09-11T00:00:00Z"'
        $b = $global:TdrCalls[0].Body | ConvertFrom-Json
        $b.msTenantIds | Should -Be @($script:T1)
        $b.threatId | Should -Be $script:Th
        $b.severities | Should -Be @('high', 'critical')
        $b.alertTypes | Should -Be @('TorExitNode')
    }

    It 'keeps an indicator on a window edge once and stops at -MaxResults' {
        Set-TdrSession
        Set-TdrRoute { param($Uri, $Method, $Body) New-TdrResponse ('{"indicators":[' + $script:IndicatorJson + '],"continuationToken":null}') }
        $end = [datetime]::new(2026, 11, 10, 0, 0, 0, [DateTimeKind]::Utc)
        $r = @(Get-InforcerTdrIndicator -DateFrom $end.AddDays(-90) -DateTo $end)
        $r.Count | Should -Be 1
        $global:TdrCalls.Count | Should -Be 3
        $null = Get-InforcerTdrIndicator -DateFrom $end.AddDays(-90) -DateTo $end -MaxResults 1
        $global:TdrCalls.Count | Should -Be 4 -Because 'the first window already gave the one result asked for'
    }

    It 'refuses -DateFrom after -DateTo before any request' {
        Set-TdrSession
        Set-TdrRoute { param($Uri, $Method, $Body) throw 'no request expected' }
        Get-InforcerTdrIndicator -DateFrom '2026-11-02' -DateTo '2026-11-01' -ErrorAction SilentlyContinue -ErrorVariable e
        $e[-1].FullyQualifiedErrorId | Should -BeLike 'InvalidDateRange*'
        $global:TdrCalls.Count | Should -Be 0
    }

    It 'escapes the opaque id in the path' {
        Set-TdrSession
        Set-TdrRoute { param($Uri, $Method, $Body) New-TdrResponse $script:IndicatorJson }
        $i = Get-InforcerTdrIndicator -IndicatorId 'b3BhcXVlL2lkKz0/+='
        $global:TdrCalls[0].Uri | Should -Be 'https://api.example.invalid/v1/tdr/indicators/b3BhcXVlL2lkKz0%2F%2B%3D'
        $i.alertType | Should -Be 'TorExitNode'
        $i.PSObject.TypeNames[0] | Should -Be 'InforcerCommunity.TdrIndicator'
    }

    It 'needs an API client login' {
        Set-TdrSession -Beta
        Set-TdrRoute { param($Uri, $Method, $Body) throw 'no request expected' }
        Get-InforcerTdrIndicator -IndicatorId 'x' -ErrorAction SilentlyContinue -ErrorVariable e
        $e[-1].FullyQualifiedErrorId | Should -BeLike 'RequiresApiClient*'
        $global:TdrCalls.Count | Should -Be 0
    }
}

Describe 'Get-InforcerTdrLog' {
    BeforeAll {
        $script:Stamp = { param([datetime]$Time) $Time.ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [cultureinfo]::InvariantCulture) }
        $script:LogJson = {
            param([string]$Id, [datetime]$Time, [string]$LogType = 'signIn')
            '{"id":"' + $Id + '","logType":"' + $LogType + '","msTenantId":"00000000-0000-0000-0000-000000000001","eventTime":"' +
            $Time.ToString("yyyy-MM-dd'T'HH:mm:ss.fff'+00:00'", [cultureinfo]::InvariantCulture) + '","simulated":false,"result":"success","' + $LogType + '":{"userPrincipalName":"jo@contoso.com"}}'
        }
        # Answers like the API: every event between dateFrom and dateTo, both ends included.
        $script:LogRoute = {
            param($Uri, $Method, $Body)
            $b = $Body | ConvertFrom-Json
            $hit = @($global:TdrLogEvents | Where-Object { $_.Time -ge $b.dateFrom.ToUniversalTime() -and $_.Time -le $b.dateTo.ToUniversalTime() } | ForEach-Object { $_.Json })
            New-TdrResponse ('{"events":[' + ($hit -join ',') + '],"continuationToken":null}')
        }
        $now = [datetime]::UtcNow
        $script:End = $now.AddTicks(-($now.Ticks % [TimeSpan]::TicksPerSecond)).AddHours(-1)
    }

    It 'searches the last 24 hours of every log by default and follows the continuation token' {
        Set-TdrSession
        Set-TdrRoute {
            param($Uri, $Method, $Body)
            $t = [datetime]::UtcNow.AddMinutes(-5)
            if (($Body | ConvertFrom-Json).continuationToken -eq 'p2') { return New-TdrResponse ('{"events":[' + (& $script:LogJson 'b' $t.AddMinutes(-1)) + '],"continuationToken":null}') }
            New-TdrResponse ('{"events":[' + (& $script:LogJson 'a' $t) + '],"continuationToken":"p2"}')
        }
        $before = [datetime]::UtcNow
        $r = @(Get-InforcerTdrLog -TenantId $script:T1 -ErrorVariable e)
        $e | Should -BeNullOrEmpty
        $r.Count | Should -Be 2
        $r[0].PSObject.TypeNames[0] | Should -Be 'InforcerCommunity.TdrLogEvent'
        $r[0].signIn.userPrincipalName | Should -Be 'jo@contoso.com'
        $global:TdrCalls.Count | Should -Be 2
        $global:TdrCalls[0].Method | Should -Be 'POST'
        $global:TdrCalls[0].Uri | Should -Be 'https://api.example.invalid/v1/tdr/logs/search'
        $b = $global:TdrCalls[0].Body | ConvertFrom-Json
        $b.msTenantId | Should -Be $script:T1
        $b.pageSize | Should -Be 500
        ($b.dateTo - $b.dateFrom).TotalHours | Should -Be 24
        [Math]::Abs(($b.dateTo.ToUniversalTime() - $before).TotalSeconds) | Should -BeLessThan 30
        foreach ($name in 'logType', 'userPrincipalName', 'includeSimulated') { $b.PSObject.Properties[$name] | Should -BeNullOrEmpty }
    }

    It 'sends the filters and caps the page at -MaxResults' {
        Set-TdrSession
        Set-TdrRoute { param($Uri, $Method, $Body) New-TdrResponse '{"events":[],"continuationToken":null}' }
        $null = Get-InforcerTdrLog -TenantId $script:T1 -LogType signIn -UserPrincipalName 'Jo@contoso.com' -IncludeSimulated -MaxResults 20
        $b = $global:TdrCalls[0].Body | ConvertFrom-Json
        $b.logType | Should -Be 'signIn'
        $b.userPrincipalName | Should -Be 'Jo@contoso.com'
        $b.includeSimulated | Should -BeTrue
        $b.pageSize | Should -Be 20
    }

    It 'searches a longer range in 24-hour steps, newest first, under <Culture>' -ForEach @(@{ Culture = 'en-US' }, @{ Culture = 'th-TH' }, @{ Culture = 'da-DK' }) {
        $saved = [cultureinfo]::CurrentCulture
        try {
            [cultureinfo]::CurrentCulture = $Culture
            Set-TdrSession
            Set-TdrRoute { param($Uri, $Method, $Body) New-TdrResponse '{"events":[],"continuationToken":null}' }
            $null = Get-InforcerTdrLog -TenantId $script:T1 -DateFrom $script:End.AddHours(-60) -DateTo $script:End
            $global:TdrCalls.Count | Should -Be 3
            $edges = 0, -24, -48, -60 | ForEach-Object { & $script:Stamp $script:End.AddHours($_) }
            foreach ($i in 0..2) {
                $b = $global:TdrCalls[$i].Body | ConvertFrom-Json -DateKind String
                $b.dateTo | Should -Be $edges[$i]
                $b.dateFrom | Should -Be $edges[$i + 1]
            }
        } finally {
            [cultureinfo]::CurrentCulture = $saved
        }
    }

    It 'keeps events that share an id, and returns an event on a window edge once' {
        Set-TdrSession
        $global:TdrLogEvents = @(
            @{ Time = $script:End.AddHours(-1); Json = (& $script:LogJson 'shared' $script:End.AddHours(-1) 'signIn') }
            @{ Time = $script:End.AddHours(-1); Json = (& $script:LogJson 'shared' $script:End.AddHours(-1) 'm365Audit') }
            @{ Time = $script:End.AddHours(-2); Json = (& $script:LogJson 'shared' $script:End.AddHours(-2) 'm365Audit') }
            @{ Time = $script:End.AddHours(-24); Json = (& $script:LogJson 'edge' $script:End.AddHours(-24)) }
            @{ Time = $script:End.AddHours(-30); Json = (& $script:LogJson 'old' $script:End.AddHours(-30)) }
        )
        Set-TdrRoute $script:LogRoute
        $r = @(Get-InforcerTdrLog -TenantId $script:T1 -DateFrom $script:End.AddHours(-48) -DateTo $script:End.AddMilliseconds(500))
        $global:TdrCalls.Count | Should -Be 2
        $r.id | Should -Be @('shared', 'shared', 'shared', 'edge', 'old')
        $r = @(Get-InforcerTdrLog -TenantId $script:T1 -DateFrom $script:End.AddHours(-48) -DateTo $script:End -MaxResults 2)
        $r.Count | Should -Be 2
        $global:TdrCalls.Count | Should -Be 3 -Because 'the first window already gave the two results asked for'
    }

    It 'returns the newest events up to -MaxResults when one of them lies on a window edge' {
        Set-TdrSession
        $global:TdrLogEvents = @(-1, -2, -24, -25, -26, -27, -50 | ForEach-Object { @{ Time = $script:End.AddHours($_); Json = (& $script:LogJson "h$(-$_)" $script:End.AddHours($_)) } })
        Set-TdrRoute $script:LogRoute
        $r = @(Get-InforcerTdrLog -TenantId $script:T1 -DateFrom $script:End.AddHours(-72) -DateTo $script:End -MaxResults 5)
        $r.id | Should -Be @('h1', 'h2', 'h24', 'h25', 'h26')
    }

    It 'returns events as they are found, so Select-Object -First ends the search' {
        Set-TdrSession
        $global:TdrLogEvents = @(-1, -30, -60 | ForEach-Object { @{ Time = $script:End.AddHours($_); Json = (& $script:LogJson "h$(-$_)" $script:End.AddHours($_)) } })
        Set-TdrRoute $script:LogRoute
        $r = @(Get-InforcerTdrLog -TenantId $script:T1 -DateFrom $script:End.AddHours(-72) -DateTo $script:End | Select-Object -First 1)
        $r.id | Should -Be 'h1'
        $global:TdrCalls.Count | Should -Be 1
    }

    It 'stops at the first failed search under -ErrorAction <Action>, with the earlier events returned' -ForEach @(@{ Action = 'Ignore' }, @{ Action = 'Stop' }) {
        Set-TdrSession
        Set-TdrRoute {
            param($Uri, $Method, $Body)
            if ($global:TdrCalls.Count -eq 1) { return New-TdrResponse ('{"events":[' + (& $script:LogJson 'a' $script:End.AddHours(-1)) + '],"continuationToken":null}') }
            New-TdrResponse '{"title":"Gateway Timeout","status":504}' 504
        }
        $got = [System.Collections.Generic.List[object]]::new()
        try {
            Get-InforcerTdrLog -TenantId $script:T1, $script:T2 -DateFrom $script:End.AddHours(-72) -DateTo $script:End -ErrorAction $Action | ForEach-Object { $got.Add($_) }
            $threw = $false
        } catch { $threw = $true }
        $threw | Should -Be ($Action -eq 'Stop')
        $got.id | Should -Be 'a'
        $global:TdrCalls.Count | Should -Be 2
    }

    It 'sends a -DateFrom just inside the 30-day limit as given' {
        Set-TdrSession
        Set-TdrRoute { param($Uri, $Method, $Body) New-TdrResponse '{"events":[],"continuationToken":null}' }
        $from = [datetime]::UtcNow.AddDays(-30).AddMinutes(2)
        $null = Get-InforcerTdrLog -TenantId $script:T1 -DateFrom $from -DateTo $from.AddMinutes(8)
        ($global:TdrCalls[0].Body | ConvertFrom-Json -DateKind String).dateFrom | Should -Be (& $script:Stamp $from)
    }

    It 'warns instead of searching when the whole range lies beyond the 30 days' {
        Set-TdrSession
        Set-TdrRoute { param($Uri, $Method, $Body) throw 'no request expected' }
        $from = [datetime]::UtcNow.AddDays(-30).AddMinutes(-2)
        $r = @(Get-InforcerTdrLog -TenantId $script:T1 -DateFrom $from -DateTo $from.AddMinutes(4) -WarningVariable w -WarningAction SilentlyContinue)
        $r.Count | Should -Be 0
        "$w" | Should -BeLike '*30 days*'
        $global:TdrCalls.Count | Should -Be 0
    }

    It 'refuses an empty -TenantId' {
        Set-TdrSession
        Set-TdrRoute { param($Uri, $Method, $Body) throw 'no request expected' }
        Get-InforcerTdrLog -TenantId @('') -ErrorAction SilentlyContinue -ErrorVariable e
        $e[-1].FullyQualifiedErrorId | Should -BeLike 'InvalidTenantId*'
    }

    It 'stops at the first search that fails and still returns what it found' {
        Set-TdrSession
        Set-TdrRoute {
            param($Uri, $Method, $Body)
            if ($global:TdrCalls.Count -eq 1) { return New-TdrResponse ('{"events":[' + (& $script:LogJson 'a' $script:End.AddHours(-1)) + '],"continuationToken":null}') }
            New-TdrResponse '{"title":"Gateway Timeout","status":504,"detail":"The search ran for longer than 30 seconds."}' 504
        }
        $r = @(Get-InforcerTdrLog -TenantId $script:T1, $script:T2 -DateFrom $script:End.AddHours(-72) -DateTo $script:End -ErrorAction SilentlyContinue -ErrorVariable e)
        $r.Count | Should -Be 1
        "$($e[-1])" | Should -BeLike '*504*'
        $global:TdrCalls.Count | Should -Be 2 -Because 'no later window and no other tenant is searched after a failure'
    }

    It 'refuses <Name> before any request' -ForEach @(
        @{ Name = '-DateFrom after -DateTo'; Splat = @{ DateFrom = [datetime]::UtcNow.AddHours(-1); DateTo = [datetime]::UtcNow.AddHours(-2) }; ErrorId = 'InvalidDateRange*' }
        @{ Name = 'a -DateFrom more than 30 days ago'; Splat = @{ DateFrom = [datetime]::UtcNow.AddDays(-31) }; ErrorId = 'InvalidDateRange*' }
        @{ Name = '-UserPrincipalName with service principal sign-ins'; Splat = @{ LogType = 'servicePrincipalSignIn'; UserPrincipalName = 'jo@contoso.com' }; ErrorId = 'UserPrincipalNameNotAllowed*' }
    ) {
        Set-TdrSession
        Set-TdrRoute { param($Uri, $Method, $Body) throw 'no request expected' }
        Get-InforcerTdrLog -TenantId $script:T1 @Splat -ErrorAction SilentlyContinue -ErrorVariable e
        $e[-1].FullyQualifiedErrorId | Should -BeLike $ErrorId
        $global:TdrCalls.Count | Should -Be 0
    }

    It 'searches from just inside the 30-day limit when -DateFrom is exactly 30 days ago' {
        Set-TdrSession
        Set-TdrRoute { param($Uri, $Method, $Body) New-TdrResponse '{"events":[],"continuationToken":null}' }
        $null = Get-InforcerTdrLog -TenantId $script:T1 -DateFrom ([datetime]::UtcNow.AddDays(-30)) -DateTo ([datetime]::UtcNow.AddDays(-30).AddHours(2)) -ErrorVariable e
        $e | Should -BeNullOrEmpty
        $global:TdrCalls.Count | Should -Be 1
        $sent = ($global:TdrCalls[0].Body | ConvertFrom-Json).dateFrom.ToUniversalTime()
        $sent | Should -BeGreaterThan ([datetime]::UtcNow.AddDays(-30))
        $sent | Should -BeLessThan ([datetime]::UtcNow.AddDays(-30).AddMinutes(10))
    }

    It 'treats a -DateTo in the future as now, and searches a tenant named twice once' {
        Set-TdrSession
        Set-TdrRoute { param($Uri, $Method, $Body) New-TdrResponse '{"events":[],"continuationToken":null}' }
        $null = Get-InforcerTdrLog -TenantId $script:T1, $script:T1 -DateFrom ([datetime]::UtcNow.AddHours(-2)) -DateTo ([datetime]::UtcNow.AddDays(60))
        $global:TdrCalls.Count | Should -Be 1
        $sent = ($global:TdrCalls[0].Body | ConvertFrom-Json).dateTo.ToUniversalTime()
        [Math]::Abs(($sent - [datetime]::UtcNow).TotalSeconds) | Should -BeLessThan 30
    }

    It 'shows who did what for every log type' {
        Set-TdrSession
        $global:TdrLogEvents = @(
            @{ Time = $script:End.AddHours(-1); Json = '{"id":"a","logType":"signIn","eventTime":"' + (& $script:Stamp $script:End.AddHours(-1)) + '","simulated":false,"result":"success","signIn":{"userPrincipalName":"jo@contoso.com","appName":"Example App"}}' }
            @{ Time = $script:End.AddHours(-2); Json = '{"id":"b","logType":"servicePrincipalSignIn","eventTime":"' + (& $script:Stamp $script:End.AddHours(-2)) + '","simulated":false,"result":"success","servicePrincipalSignIn":{"servicePrincipalName":"Backup app","resourceName":"Example Graph"}}' }
            @{ Time = $script:End.AddHours(-3); Json = '{"id":"c","logType":"directoryAudit","eventTime":"' + (& $script:Stamp $script:End.AddHours(-3)) + '","simulated":false,"result":"success","directoryAudit":{"actor":"admin@contoso.com","operation":"Add member to role"}}' }
            @{ Time = $script:End.AddHours(-4); Json = '{"id":"d","logType":"m365Audit","eventTime":"' + (& $script:Stamp $script:End.AddHours(-4)) + '","simulated":false,"result":"success","m365Audit":{"userPrincipalName":"sam@contoso.com","operation":"New-InboxRule"}}' }
        )
        Set-TdrRoute $script:LogRoute
        $text = Get-InforcerTdrLog -TenantId $script:T1 -DateFrom $script:End.AddHours(-12) -DateTo $script:End | Out-String -Width 200
        foreach ($line in 'Actor\s+: jo@contoso\.com', 'Activity\s+: Sign-in to Example App', 'Actor\s+: Backup app', 'Activity\s+: Sign-in to Example Graph',
            'Actor\s+: admin@contoso\.com', 'Activity\s+: Add member to role', 'Actor\s+: sam@contoso\.com', 'Activity\s+: New-InboxRule') { $text | Should -Match $line }
    }

    It 'searches piped tenants one after the other' {
        Set-TdrSession
        Set-TdrRoute { param($Uri, $Method, $Body) New-TdrResponse '{"events":[],"continuationToken":null}' }
        $null = [pscustomobject]@{ TenantId = $script:T1 }, [pscustomobject]@{ TenantId = $script:T2 } | Get-InforcerTdrLog
        $global:TdrCalls.Count | Should -Be 2
        ($global:TdrCalls | ForEach-Object { ($_.Body | ConvertFrom-Json).msTenantId }) | Should -Be @($script:T1, $script:T2)
    }

    It 'returns a JSON array, even with one event' {
        Set-TdrSession
        Set-TdrRoute { param($Uri, $Method, $Body) New-TdrResponse ('{"events":[' + (& $script:LogJson 'a' $script:End.AddHours(-1)) + '],"continuationToken":null}') }
        $json = Get-InforcerTdrLog -TenantId $script:T1 -DateFrom $script:End.AddHours(-2) -DateTo $script:End -OutputType JsonObject
        $json | Should -BeOfType [string]
        $json.TrimStart() | Should -BeLike '`[*'
        @($json | ConvertFrom-Json).Count | Should -Be 1
        Set-TdrRoute { param($Uri, $Method, $Body) New-TdrResponse '{"events":[],"continuationToken":null}' }
        Get-InforcerTdrLog -TenantId $script:T1 -OutputType JsonObject | Should -Be '[]'
    }

    It 'needs an API client login' {
        Set-TdrSession -Beta
        Set-TdrRoute { param($Uri, $Method, $Body) throw 'no request expected' }
        Get-InforcerTdrLog -TenantId $script:T1 -ErrorAction SilentlyContinue -ErrorVariable e
        $e[-1].FullyQualifiedErrorId | Should -BeLike 'RequiresApiClient*'
        $global:TdrCalls.Count | Should -Be 0
    }
}

Describe 'Dates sent to the API do not follow the regional settings' {
    It 'sends Gregorian dates with a colon separator under <Culture>' -ForEach @(@{ Culture = 'th-TH' }, @{ Culture = 'da-DK' }) {
        $saved = [cultureinfo]::CurrentCulture
        try {
            [cultureinfo]::CurrentCulture = $Culture
            Set-TdrSession
            Set-TdrRoute { param($Uri, $Method, $Body) if ($Uri -like '*indicators*') { New-TdrResponse '{"indicators":[],"continuationToken":null}' } else { New-TdrResponse '{"threats":[],"continuationToken":null}' } }
            $from = [datetime]::new(2026, 11, 1, 8, 5, 0, [System.DateTimeKind]::Utc)
            $to = [datetime]::new(2026, 11, 10, 13, 5, 0, [System.DateTimeKind]::Utc)
            Get-InforcerTdrThreat -DateFrom $from -DateTo $to | Out-Null
            Get-InforcerTdrIndicator -DateFrom $from -DateTo $to | Out-Null
            foreach ($call in $global:TdrCalls) {
                $b = $call.Body | ConvertFrom-Json -DateKind String
                $b.dateFrom | Should -Be '2026-11-01T08:05:00Z'
                $b.dateTo | Should -Be '2026-11-10T13:05:00Z'
            }
            $global:TdrCalls.Count | Should -Be 2
        } finally {
            [cultureinfo]::CurrentCulture = $saved
        }
    }
}

Describe 'Get-InforcerTdrAutoContainment' {
    BeforeAll {
        $script:AcJson = '{"enabled":true,"configured":true,"settings":{"severityThreshold":"high","allowedActions":["blockUser"],"allowedDeviceActions":[],"allowedTargets":[],"deniedTargets":["breakglass@contoso.com"]},"updatedAt":"2026-11-20T14:03:11Z","updatedBy":"SIEM integration"}'
    }
    It 'reads each piped tenant and puts msTenantId first' {
        Set-TdrSession
        Set-TdrRoute { param($Uri) New-TdrResponse $script:AcJson }
        $r = @([pscustomobject]@{ msTenantId = $script:T1 }, [pscustomobject]@{ msTenantId = $script:T2 }) | Get-InforcerTdrAutoContainment
        $global:TdrCalls.Count | Should -Be 2
        $global:TdrCalls[0].Uri | Should -BeLike "*/v1/tenants/$($script:T1)/tdr/autoContainment"
        $global:TdrCalls[0].Method | Should -Be 'GET'
        $r[1].msTenantId | Should -Be $script:T2
        $r[0].PSObject.Properties.Name[0] | Should -Be 'msTenantId'
        $r[0].settings.deniedTargets | Should -Be 'breakglass@contoso.com'
        $r[0].PSObject.TypeNames[0] | Should -Be 'InforcerCommunity.TdrAutoContainment'
    }
    It 'returns JSON with -OutputType JsonObject' {
        Set-TdrSession
        Set-TdrRoute { param($Uri) New-TdrResponse '{"enabled":false,"configured":false,"settings":null,"updatedAt":null,"updatedBy":null}' }
        $j = Get-InforcerTdrAutoContainment -TenantId $script:T1 -OutputType JsonObject | ConvertFrom-Json
        $j.msTenantId | Should -Be $script:T1
        $j.configured | Should -BeFalse
    }
    It 'needs an API client' {
        Set-TdrSession -Beta
        Set-TdrRoute { param($Uri) throw 'no call expected' }
        Get-InforcerTdrAutoContainment -TenantId $script:T1 -ErrorVariable e -ErrorAction SilentlyContinue
        $e[0].FullyQualifiedErrorId | Should -Match '^RequiresApiClient'
        $global:TdrCalls.Count | Should -Be 0
    }
}

Describe 'Set-InforcerTdrAutoContainment' {
    It 'asks for confirmation by default' {
        (Get-Command Set-InforcerTdrAutoContainment).ScriptBlock.Attributes |
            Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] } |
            ForEach-Object ConfirmImpact | Should -Be 'High'
    }
    It 'sends only the settings passed, an empty list as []' {
        Set-TdrSession
        Set-TdrRoute { param($Uri) New-TdrResponse '{"enabled":false,"configured":true,"settings":{"severityThreshold":"critical","allowedActions":[],"allowedDeviceActions":[],"allowedTargets":[],"deniedTargets":["breakglass@contoso.com"]},"updatedAt":"2026-11-25T10:00:00Z","updatedBy":"api client"}' }
        $r = Set-InforcerTdrAutoContainment -TenantId $script:T1 -SeverityThreshold critical -AllowedAction @() -DeniedTarget 'breakglass@contoso.com' -Confirm:$false
        $global:TdrCalls[0].Method | Should -Be 'PATCH'
        $global:TdrCalls[0].Uri | Should -BeLike "*/v1/tenants/$($script:T1)/tdr/autoContainment"
        $global:TdrCalls[0].Body | Should -Be '{"settings":{"severityThreshold":"critical","allowedActions":[],"deniedTargets":["breakglass@contoso.com"]}}'
        $r.msTenantId | Should -Be $script:T1
        $r.configured | Should -BeTrue
    }
    It 'sends enabled false on its own' {
        Set-TdrSession
        Set-TdrRoute { param($Uri) New-TdrResponse '{"enabled":false,"configured":true,"settings":null,"updatedAt":null,"updatedBy":null}' }
        $null = Set-InforcerTdrAutoContainment -TenantId $script:T1 -Enabled $false -Confirm:$false
        $global:TdrCalls[0].Body | Should -Be '{"enabled":false}'
    }
    It 'refuses a call without a change, and -WhatIf sends nothing' {
        Set-TdrSession
        Set-TdrRoute { param($Uri) throw 'no call expected' }
        Set-InforcerTdrAutoContainment -TenantId $script:T1 -ErrorVariable e -ErrorAction SilentlyContinue
        $e[0].FullyQualifiedErrorId | Should -Match '^NoChangeSpecified'
        Set-InforcerTdrAutoContainment -TenantId $script:T1 -Enabled $true -WhatIf
        $global:TdrCalls.Count | Should -Be 0
    }
    It 'does not retry a 409, which a retry cannot fix' {
        Set-TdrSession
        Mock -ModuleName InforcerCommunity Start-Sleep { }
        Set-TdrRoute { param($Uri) New-TdrResponse -Status 409 '{"title":"Conflict","status":409,"detail":"Auto-containment is not configured; send settings to turn it on."}' }
        Set-InforcerTdrAutoContainment -TenantId $script:T1 -Enabled $true -Confirm:$false -ErrorVariable e -ErrorAction SilentlyContinue
        $e[0].FullyQualifiedErrorId | Should -Match '^ApiRequestFailed_409'
        $global:TdrCalls.Count | Should -Be 1
        Should -Invoke -ModuleName InforcerCommunity Start-Sleep -Times 0 -Exactly
    }
}
