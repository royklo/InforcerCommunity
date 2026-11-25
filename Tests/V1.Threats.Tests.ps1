# V1.Threats.Tests.ps1
# Get-InforcerThreat and Get-InforcerThreatIndicator (v1 only). Fixtures are anonymised; no network calls.

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
    Remove-Variable -Name TdrCalls, TdrRoute -Scope Global -ErrorAction SilentlyContinue
    & (Get-Module InforcerCommunity) { $script:InforcerSession = $null; $script:InforcerTenantListCache = $null }
}

Describe 'Get-InforcerThreat' {
    It 'searches with the filters in the body and follows the continuation token' {
        Set-TdrSession
        Set-TdrRoute {
            param($Uri, $Method, $Body)
            if (($Body | ConvertFrom-Json).continuationToken -eq 'p2') { return New-TdrResponse ('{"threats":[' + ($script:ThreatJson -replace '0d1"', '0d2"') + '}],"continuationToken":null}') }
            New-TdrResponse ('{"threats":[' + $script:ThreatJson + '}],"continuationToken":"p2"}')
        }
        $from = [datetime]::new(2026, 11, 1, 0, 0, 0, [DateTimeKind]::Utc)
        $r = @(Get-InforcerThreat -TenantId $script:T1 -Status open, remediating -Severity high -Verdict merged -DateFrom $from -ErrorVariable e)
        $e | Should -BeNullOrEmpty
        $r.Count | Should -Be 2
        $r[0].PSObject.TypeNames[0] | Should -Be 'InforcerCommunity.Threat'
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
        $r = @(Get-InforcerThreat -MaxResults 1)
        $r.Count | Should -Be 1
        $global:TdrCalls.Count | Should -Be 1
        $b = $global:TdrCalls[0].Body | ConvertFrom-Json
        $b.pageSize | Should -Be 1
        foreach ($k in 'msTenantIds', 'statuses', 'dateFrom', 'dateTo') { $b.PSObject.Properties[$k] | Should -BeNullOrEmpty }
    }

    It 'searches piped tenants in one request' {
        Set-TdrSession
        Set-TdrRoute { param($Uri, $Method, $Body) New-TdrResponse '{"threats":[],"continuationToken":null}' }
        $r = @([pscustomobject]@{ MsTenantId = $script:T1 }, [pscustomobject]@{ MsTenantId = $script:T2 } | Get-InforcerThreat)
        $r.Count | Should -Be 0
        $global:TdrCalls.Count | Should -Be 1
        ($global:TdrCalls[0].Body | ConvertFrom-Json).msTenantIds | Should -Be @($script:T1, $script:T2)
    }

    It 'returns one threat with its summary and IoCs by id' {
        Set-TdrSession
        Set-TdrRoute { param($Uri, $Method, $Body) New-TdrResponse ($script:ThreatJson + ',"summary":"A **Tor** sign-in.","iocs":[{"iocId":"abc","indicatorId":"b3BhcXVlL2lkKz0="},{"iocId":"def","indicatorId":null}]}') }
        $t = Get-InforcerThreat -ThreatId $script:Th
        $global:TdrCalls[0].Method | Should -Be 'GET'
        $global:TdrCalls[0].Uri | Should -Be "https://api.example.invalid/v1/tdr/threats/$($script:Th)"
        $t.PSObject.TypeNames[0] | Should -Be 'InforcerCommunity.Threat'
        $t.summary | Should -Be 'A **Tor** sign-in.'
        @($t.iocs).Count | Should -Be 2
        @($t.linkedDevices).Count | Should -Be 0
        (Get-InforcerThreat -ThreatId $script:Th -OutputType JsonObject | ConvertFrom-Json).iocs[0].iocId | Should -Be 'abc'
    }

    It 'returns a JSON array for a search, even with one threat' {
        Set-TdrSession
        Set-TdrRoute { param($Uri, $Method, $Body) New-TdrResponse ('{"threats":[' + $script:ThreatJson + '}],"continuationToken":null}') }
        $json = Get-InforcerThreat -OutputType JsonObject
        $json.TrimStart() | Should -BeLike '`[*'
        @($json | ConvertFrom-Json).Count | Should -Be 1
    }

    It 'reports a 404 for an unknown threat' {
        Set-TdrSession
        Set-TdrRoute { param($Uri, $Method, $Body) New-TdrResponse '{"title":"Not found","status":404}' 404 }
        $t = Get-InforcerThreat -ThreatId $script:Th -ErrorAction SilentlyContinue -ErrorVariable e
        $t | Should -BeNullOrEmpty
        "$($e[-1])" | Should -BeLike '*404*'
    }

    It 'needs an API client login' {
        Set-TdrSession -Beta
        Set-TdrRoute { param($Uri, $Method, $Body) throw 'no request expected' }
        Get-InforcerThreat -ErrorAction SilentlyContinue -ErrorVariable e
        $e[-1].FullyQualifiedErrorId | Should -BeLike 'RequiresApiClient*'
        $global:TdrCalls.Count | Should -Be 0
    }
}

Describe 'Get-InforcerThreatIndicator' {
    It 'always sends a date range of 30 days ending now by default' {
        Set-TdrSession
        Set-TdrRoute { param($Uri, $Method, $Body) New-TdrResponse ('{"indicators":[' + $script:IndicatorJson + '],"continuationToken":null}') }
        $r = @(Get-InforcerThreatIndicator -ErrorVariable e)
        $e | Should -BeNullOrEmpty
        $r.Count | Should -Be 1
        $r[0].PSObject.TypeNames[0] | Should -Be 'InforcerCommunity.ThreatIndicator'
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
        $null = Get-InforcerThreatIndicator -TenantId $script:T1 -ThreatId $script:Th -Severity high, critical -AlertType TorExitNode -DateFrom $from -DateTo $to
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
        $r = @(Get-InforcerThreatIndicator -DateFrom $end.AddDays(-90) -DateTo $end)
        $r.Count | Should -Be 1
        $global:TdrCalls.Count | Should -Be 3
        $null = Get-InforcerThreatIndicator -DateFrom $end.AddDays(-90) -DateTo $end -MaxResults 1
        $global:TdrCalls.Count | Should -Be 4 -Because 'the first window already gave the one result asked for'
    }

    It 'refuses -DateFrom after -DateTo before any request' {
        Set-TdrSession
        Set-TdrRoute { param($Uri, $Method, $Body) throw 'no request expected' }
        Get-InforcerThreatIndicator -DateFrom '2026-11-02' -DateTo '2026-11-01' -ErrorAction SilentlyContinue -ErrorVariable e
        $e[-1].FullyQualifiedErrorId | Should -BeLike 'InvalidDateRange*'
        $global:TdrCalls.Count | Should -Be 0
    }

    It 'escapes the opaque id in the path' {
        Set-TdrSession
        Set-TdrRoute { param($Uri, $Method, $Body) New-TdrResponse $script:IndicatorJson }
        $i = Get-InforcerThreatIndicator -IndicatorId 'b3BhcXVlL2lkKz0/+='
        $global:TdrCalls[0].Uri | Should -Be 'https://api.example.invalid/v1/tdr/indicators/b3BhcXVlL2lkKz0%2F%2B%3D'
        $i.alertType | Should -Be 'TorExitNode'
        $i.PSObject.TypeNames[0] | Should -Be 'InforcerCommunity.ThreatIndicator'
    }

    It 'needs an API client login' {
        Set-TdrSession -Beta
        Set-TdrRoute { param($Uri, $Method, $Body) throw 'no request expected' }
        Get-InforcerThreatIndicator -IndicatorId 'x' -ErrorAction SilentlyContinue -ErrorVariable e
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
            Get-InforcerThreat -DateFrom $from -DateTo $to | Out-Null
            Get-InforcerThreatIndicator -DateFrom $from -DateTo $to | Out-Null
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

Describe 'Get-InforcerAutoContainment' {
    BeforeAll {
        $script:AcJson = '{"enabled":true,"configured":true,"settings":{"severityThreshold":"high","allowedActions":["blockUser"],"allowedDeviceActions":[],"allowedTargets":[],"deniedTargets":["breakglass@contoso.com"]},"updatedAt":"2026-11-20T14:03:11Z","updatedBy":"SIEM integration"}'
    }
    It 'reads each piped tenant and puts msTenantId first' {
        Set-TdrSession
        Set-TdrRoute { param($Uri) New-TdrResponse $script:AcJson }
        $r = @([pscustomobject]@{ msTenantId = $script:T1 }, [pscustomobject]@{ msTenantId = $script:T2 }) | Get-InforcerAutoContainment
        $global:TdrCalls.Count | Should -Be 2
        $global:TdrCalls[0].Uri | Should -BeLike "*/v1/tenants/$($script:T1)/tdr/autoContainment"
        $global:TdrCalls[0].Method | Should -Be 'GET'
        $r[1].msTenantId | Should -Be $script:T2
        $r[0].PSObject.Properties.Name[0] | Should -Be 'msTenantId'
        $r[0].settings.deniedTargets | Should -Be 'breakglass@contoso.com'
        $r[0].PSObject.TypeNames[0] | Should -Be 'InforcerCommunity.AutoContainment'
    }
    It 'returns JSON with -OutputType JsonObject' {
        Set-TdrSession
        Set-TdrRoute { param($Uri) New-TdrResponse '{"enabled":false,"configured":false,"settings":null,"updatedAt":null,"updatedBy":null}' }
        $j = Get-InforcerAutoContainment -TenantId $script:T1 -OutputType JsonObject | ConvertFrom-Json
        $j.msTenantId | Should -Be $script:T1
        $j.configured | Should -BeFalse
    }
    It 'needs an API client' {
        Set-TdrSession -Beta
        Set-TdrRoute { param($Uri) throw 'no call expected' }
        Get-InforcerAutoContainment -TenantId $script:T1 -ErrorVariable e -ErrorAction SilentlyContinue
        $e[0].FullyQualifiedErrorId | Should -Match '^RequiresApiClient'
        $global:TdrCalls.Count | Should -Be 0
    }
}

Describe 'Set-InforcerAutoContainment' {
    It 'asks for confirmation by default' {
        (Get-Command Set-InforcerAutoContainment).ScriptBlock.Attributes |
            Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] } |
            ForEach-Object ConfirmImpact | Should -Be 'High'
    }
    It 'sends only the settings passed, an empty list as []' {
        Set-TdrSession
        Set-TdrRoute { param($Uri) New-TdrResponse '{"enabled":false,"configured":true,"settings":{"severityThreshold":"critical","allowedActions":[],"allowedDeviceActions":[],"allowedTargets":[],"deniedTargets":["breakglass@contoso.com"]},"updatedAt":"2026-11-25T10:00:00Z","updatedBy":"api client"}' }
        $r = Set-InforcerAutoContainment -TenantId $script:T1 -SeverityThreshold critical -AllowedAction @() -DeniedTarget 'breakglass@contoso.com' -Confirm:$false
        $global:TdrCalls[0].Method | Should -Be 'PATCH'
        $global:TdrCalls[0].Uri | Should -BeLike "*/v1/tenants/$($script:T1)/tdr/autoContainment"
        $global:TdrCalls[0].Body | Should -Be '{"settings":{"severityThreshold":"critical","allowedActions":[],"deniedTargets":["breakglass@contoso.com"]}}'
        $r.msTenantId | Should -Be $script:T1
        $r.configured | Should -BeTrue
    }
    It 'sends enabled false on its own' {
        Set-TdrSession
        Set-TdrRoute { param($Uri) New-TdrResponse '{"enabled":false,"configured":true,"settings":null,"updatedAt":null,"updatedBy":null}' }
        $null = Set-InforcerAutoContainment -TenantId $script:T1 -Enabled $false -Confirm:$false
        $global:TdrCalls[0].Body | Should -Be '{"enabled":false}'
    }
    It 'refuses a call without a change, and -WhatIf sends nothing' {
        Set-TdrSession
        Set-TdrRoute { param($Uri) throw 'no call expected' }
        Set-InforcerAutoContainment -TenantId $script:T1 -ErrorVariable e -ErrorAction SilentlyContinue
        $e[0].FullyQualifiedErrorId | Should -Match '^NoChangeSpecified'
        Set-InforcerAutoContainment -TenantId $script:T1 -Enabled $true -WhatIf
        $global:TdrCalls.Count | Should -Be 0
    }
    It 'does not retry a 409, which a retry cannot fix' {
        Set-TdrSession
        Mock -ModuleName InforcerCommunity Start-Sleep { }
        Set-TdrRoute { param($Uri) New-TdrResponse -Status 409 '{"title":"Conflict","status":409,"detail":"Auto-containment is not configured; send settings to turn it on."}' }
        Set-InforcerAutoContainment -TenantId $script:T1 -Enabled $true -Confirm:$false -ErrorVariable e -ErrorAction SilentlyContinue
        $e[0].FullyQualifiedErrorId | Should -Match '^ApiRequestFailed_409'
        $global:TdrCalls.Count | Should -Be 1
        Should -Invoke -ModuleName InforcerCommunity Start-Sleep -Times 0 -Exactly
    }
}
