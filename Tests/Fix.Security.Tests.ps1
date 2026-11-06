# Fix.Security.Tests.ps1
# Regression tests for security review fixes F1-F7, F9, F10: report download file names, redirects with
# credentials, HTML/JS injection in the reports, Excel formulas, the settings catalog download and
# Markdown escaping. HTTP is mocked or served by loopback listeners; no live API or GitHub call.

BeforeAll {
    Remove-Module -Name 'InforcerCommunity' -ErrorAction SilentlyContinue
    Import-Module (Join-Path $PSScriptRoot '../module/InforcerCommunity.psd1') -Force
    $script:M = Get-Module InforcerCommunity
    $script:RunId = '00000000-0000-0000-0000-0000000000a1'
    $script:Hostile = @(
        'Q" data-probe="1'
        "BS\' x"
        '''";alert(1)//'
        '</script><script>alert(1)</script>'
        '<!--<script>'
        '<img src=x onerror=alert(1)>'
    )

    function global:Set-SecTestSession {
        param([ValidateSet('v1', 'beta')][string]$Mode = 'beta', [string]$ApiHost = 'https://api.example.invalid')
        & (Get-Module InforcerCommunity) {
            param($Mode, $ApiHost)
            $script:InforcerTenantListCache = $null
            if ($Mode -eq 'beta') {
                $script:InforcerSession = @{
                    AuthMode = 'ApiKey'; ApiVersion = 'beta'; ApiHost = $ApiHost; BaseUrl = "$ApiHost/api"; Region = 'uk'
                    ConnectedAt = Get-Date; ApiKey = (ConvertTo-SecureString 'beta-test-key-value' -AsPlainText -Force)
                }
            } else {
                $script:InforcerSession = @{
                    AuthMode = 'ClientCredentials'; ApiVersion = 'v1'; ApiHost = $ApiHost; BaseUrl = $ApiHost; Region = 'uk'
                    ConnectedAt = Get-Date; ClientId = 'client-id-example'
                    ClientSecret = (ConvertTo-SecureString 'client-secret-example-value' -AsPlainText -Force)
                    AccessToken = (ConvertTo-SecureString 'access-token-example-value' -AsPlainText -Force)
                    TokenExpiresAt = [datetime]::UtcNow.AddMinutes(50)
                }
            }
        } $Mode $ApiHost
    }

    # Loopback listener answering every request with $Status (and Location when set); records what reached it.
    function global:Start-SecTestServer {
        param([int]$Status = 200, [string]$Location)
        $listener = $null
        $port = 0
        for ($attempt = 0; $attempt -lt 25 -and -not $listener; $attempt++) {
            $port = Get-Random -Minimum 20000 -Maximum 60000
            $candidate = [System.Net.HttpListener]::new()
            $candidate.Prefixes.Add("http://127.0.0.1:$port/")
            try { $candidate.Start(); $listener = $candidate } catch { $candidate.Close() }
        }
        if (-not $listener) { throw 'Could not start a loopback HttpListener on a free port.' }
        $seen = [hashtable]::Synchronized(@{ Count = 0; Ready = $false })
        $shell = [powershell]::Create()
        $null = $shell.AddScript({
            param($listener, $seen, $status, $location)
            $seen.Ready = $true
            while ($listener.IsListening) {
                try { $ctx = $listener.GetContext() } catch { break }
                $req = $ctx.Request
                $reader = [System.IO.StreamReader]::new($req.InputStream)
                $seen.Body = $reader.ReadToEnd()
                $reader.Dispose()
                $seen.ApiKey = $req.Headers['Inf-Api-Key']
                $seen.Auth = $req.Headers['Authorization']
                $seen.Count = $seen.Count + 1
                $ctx.Response.StatusCode = $status
                if ($location) { $ctx.Response.RedirectLocation = $location }
                $bytes = [System.Text.Encoding]::UTF8.GetBytes('{}')
                $ctx.Response.ContentType = 'application/json'
                $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                $ctx.Response.Close()
            }
        }).AddArgument($listener).AddArgument($seen).AddArgument($Status).AddArgument($Location)
        $null = $shell.BeginInvoke()
        $waited = 0
        while (-not $seen.Ready -and $waited -lt 200) { Start-Sleep -Milliseconds 50; $waited++ }
        [pscustomobject]@{ Url = "http://127.0.0.1:$port"; Seen = $seen; Listener = $listener; Shell = $shell }
    }

    function global:Stop-SecTestServer {
        param($Server)
        try { $Server.Listener.Stop(); $Server.Listener.Close() } catch { $null }
        try { $Server.Shell.Stop(); $Server.Shell.Dispose() } catch { $null }
    }

    function global:New-SecCheck {
        param([string]$Name, [string]$Status = 'Pass', [string]$Category = 'Entra')
        [pscustomobject]@{
            name = $Name; category = $Category; subCategory = ''; importance = 'High'; Status = $Status
            description = ''; impact = ''; rationale = ''; key = ''; FindingsMessage = ''; ObjectsEvaluated = 0
            Scores = @(); Violations = @(); Warnings = @(); Passes = @()
        }
    }

    function global:New-SecDocModel {
        param([string]$PolicyName = 'Policy', [object[]]$Settings = @())
        @{
            TenantName = 'Contoso'; TenantId = 1; GeneratedAt = [datetime]::new(2026, 1, 15, 0, 0, 0, [System.DateTimeKind]::Utc)
            BaselineName = ''
            Products = [ordered]@{
                'Intune' = @{
                    Categories = [ordered]@{
                        'Configuration' = [System.Collections.Generic.List[object]]@(
                            @{
                                Basics = @{ Name = $PolicyName; Description = '@SUM(1)'; ProfileType = 'deviceConfiguration'
                                    Platform = 'windows10AndLater'; Created = ''; Modified = ''; ScopeTags = '' }
                                Settings = $Settings
                                Assignments = @([pscustomobject]@{ Target = 'All Users'; Type = 'All Users'; Filter = ''; FilterMode = '' })
                            }
                        )
                    }
                }
            }
        }
    }

    # Mocked Invoke-WebRequest for a report output: writes $Body to -OutFile, answers with $Disposition.
    $script:DownloadMock = {
        if ($OutFile) { [System.IO.File]::WriteAllText($OutFile, 'server') }
        [pscustomobject]@{
            StatusCode = 200; Content = $null
            Headers = @{ 'Content-Disposition' = $script:SecDisposition; 'Content-Type' = 'text/csv' }
        }
    }
}

AfterAll {
    foreach ($f in 'Set-SecTestSession', 'Start-SecTestServer', 'Stop-SecTestServer', 'New-SecCheck', 'New-SecDocModel') {
        Remove-Item "function:global:$f" -ErrorAction SilentlyContinue
    }
    & (Get-Module InforcerCommunity) { $script:InforcerSession = $null; $script:InforcerTenantListCache = $null }
}

Describe 'F1: report downloads never escape or overwrite' {
    BeforeEach {
        Set-SecTestSession -Mode beta
        $script:Dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $script:Dir
    }

    It 'never turns a server name into a dotfile' {
        & $script:M { Resolve-InforcerReportOutputFileName -ContentDisposition 'attachment; filename=".zshrc"' } | Should -BeExactly '_.zshrc'
        & $script:M { Resolve-InforcerReportOutputFileName -ContentDisposition "attachment; filename*=UTF-8''..%2F.bashrc" } | Should -BeExactly '_.bashrc'
    }

    It 'keeps an existing file and saves under a free name when the server name is taken' {
        Set-Content -LiteralPath (Join-Path $script:Dir 'report.csv') -Value 'original' -NoNewline
        Set-Content -LiteralPath (Join-Path $script:Dir '_.zshrc') -Value 'original' -NoNewline
        $script:SecDisposition = 'attachment; filename="report.csv"'
        Mock -ModuleName InforcerCommunity Invoke-WebRequest $script:DownloadMock
        $first = & $script:M { param($d) Invoke-InforcerRawDownload -Endpoint '/reports/runs/r/outputs/o' -DestinationDirectory $d } $script:Dir
        $second = & $script:M { param($d) Invoke-InforcerRawDownload -Endpoint '/reports/runs/r/outputs/o' -DestinationDirectory $d } $script:Dir
        $script:SecDisposition = 'attachment; filename=".zshrc"'
        $third = & $script:M { param($d) Invoke-InforcerRawDownload -Endpoint '/reports/runs/r/outputs/o' -DestinationDirectory $d } $script:Dir

        Get-Content -LiteralPath (Join-Path $script:Dir 'report.csv') -Raw | Should -BeExactly 'original'
        Get-Content -LiteralPath (Join-Path $script:Dir '_.zshrc') -Raw | Should -BeExactly 'original'
        $first.FileName | Should -BeExactly 'report (1).csv'
        $second.FileName | Should -BeExactly 'report (2).csv'
        $third.FileName | Should -BeExactly '_ (1).zshrc'
        Get-Content -LiteralPath $first.FilePath -Raw | Should -BeExactly 'server'
        @(Get-ChildItem -LiteralPath $script:Dir -Filter '*.partial').Count | Should -Be 0
    }

    It 'with -FileName never writes the server name, so a file of that name is untouched' {
        Set-Content -LiteralPath (Join-Path $script:Dir 'victim.txt') -Value 'original' -NoNewline
        $script:SecDisposition = 'attachment; filename="victim.txt"'
        Mock -ModuleName InforcerCommunity Invoke-WebRequest $script:DownloadMock
        $r1 = Save-InforcerReportOutput -RunId $script:RunId -OutputId 'o1' -OutputPath $script:Dir -FileName 'mine.csv'
        $r2 = Save-InforcerReportOutput -RunId $script:RunId -OutputId 'o1' -OutputPath $script:Dir -FileName 'mine.csv'

        Get-Content -LiteralPath (Join-Path $script:Dir 'victim.txt') -Raw | Should -BeExactly 'original'
        $r1.FileName | Should -BeExactly 'mine.csv'
        $r2.FileName | Should -BeExactly 'mine (1).csv'
        Get-Content -LiteralPath $r1.FilePath -Raw | Should -BeExactly 'server'
        $names = @(Get-ChildItem -LiteralPath $script:Dir).Name
        $names.Count | Should -Be 3
        foreach ($n in 'mine.csv', 'mine (1).csv', 'victim.txt') { $names | Should -Contain $n }
    }
}

Describe 'F5: credentials never follow a redirect' {
    BeforeAll {
        $script:Target = Start-SecTestServer -Status 200
    }
    AfterAll {
        Stop-SecTestServer $script:Target
    }
    BeforeEach {
        $script:Target.Seen.Count = 0
    }

    It 'an API request with the API key stops at a 302' {
        $redirector = Start-SecTestServer -Status 302 -Location "$($script:Target.Url)/stolen"
        try {
            Set-SecTestSession -Mode beta -ApiHost $redirector.Url
            $err = & $script:M { Invoke-InforcerApiRequest -Endpoint '/tenants' -ErrorAction SilentlyContinue -ErrorVariable e; $e }
            $redirector.Seen.Count | Should -Be 1
            $script:Target.Seen.Count | Should -Be 0
            "$err" | Should -Match 'redirect \(HTTP 302\)'
            "$err" | Should -Not -Match 'beta-test-key-value'
        } finally { Stop-SecTestServer $redirector }
    }

    It 'the token request with the client secret stops at a 307' {
        $redirector = Start-SecTestServer -Status 307 -Location "$($script:Target.Url)/oauth/token"
        try {
            $secret = ConvertTo-SecureString 'client-secret-example-value' -AsPlainText -Force
            $result = & $script:M { param($h, $s) Get-InforcerAccessToken -ApiHost $h -ClientId 'client-id-example' -ClientSecret $s } $redirector.Url $secret
            $redirector.Seen.Body | Should -Match 'client_secret'
            $script:Target.Seen.Count | Should -Be 0
            $result.AccessToken | Should -BeNullOrEmpty
            $result.Error | Should -Match 'redirect \(HTTP 307\)'
            $result.Error | Should -Not -Match 'client-secret-example-value'
        } finally { Stop-SecTestServer $redirector }
    }

    It 'the -AssessmentId TAB completer stops at a 302' {
        $attr = (Get-Command Invoke-InforcerReport).Parameters['AssessmentId'].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ArgumentCompleterAttribute] }
        $redirector = Start-SecTestServer -Status 302 -Location "$($script:Target.Url)/assessments"
        try {
            # Warm Invoke-RestMethod up so the completer's 2 s budget never races first-use cost.
            try { $null = Invoke-RestMethod -Uri "$($script:Target.Url)/warmup" -TimeoutSec 30 } catch { $null }
            $script:Target.Seen.Count = 0
            Set-SecTestSession -Mode v1 -ApiHost $redirector.Url
            & $script:M { $script:InforcerAssessmentCache = $null; $script:InforcerAssessmentCacheDeniedAt = $null }
            $res = @(& $attr.ScriptBlock 'Invoke-InforcerReport' 'AssessmentId' '' $null @{ ReportType = 'Assessment' })
            $redirector.Seen.Auth | Should -Be 'Bearer access-token-example-value'
            $script:Target.Seen.Count | Should -Be 0
            $res.Count | Should -Be 0
        } finally { Stop-SecTestServer $redirector }
    }

    It 'a report download with the bearer token stops at a 302' {
        $redirector = Start-SecTestServer -Status 302 -Location "$($script:Target.Url)/blob"
        try {
            Set-SecTestSession -Mode v1 -ApiHost $redirector.Url
            $err = & $script:M { param($d) Invoke-InforcerRawDownload -Endpoint '/reports/runs/r/outputs/o' -DestinationDirectory $d -ErrorAction SilentlyContinue -ErrorVariable e; $e } $TestDrive
            $redirector.Seen.Auth | Should -Be 'Bearer access-token-example-value'
            $script:Target.Seen.Count | Should -Be 0
            "$err" | Should -Match 'redirect \(HTTP 302\)'
            @(Get-ChildItem -LiteralPath $TestDrive -Filter '*.partial').Count | Should -Be 0
        } finally { Stop-SecTestServer $redirector }
    }
}

Describe 'F2: assessment matrix report renders hostile tenant and check names inert' {
    BeforeAll {
        $tr = for ($i = 0; $i -lt $script:Hostile.Count; $i++) {
            @{
                TenantName = $script:Hostile[$i]; TenantId = $i; Score = 100; Passed = 1; Failed = 0; TotalChecks = 1
                Checks = @(New-SecCheck -Name $script:Hostile[$i] -Category $script:Hostile[($i + 1) % $script:Hostile.Count] -Status 'InsufficientPermissions')
            }
        }
        $script:MatrixHtml = & $script:M { param($t) ConvertTo-InforcerAssessmentMatrixHtml -AssessmentName '<b>x</b>' -TenantResults $t } @($tr)
        $script:MatrixScript = [regex]::Match($script:MatrixHtml, '(?s)<script>(.*)</script>').Groups[1].Value
    }

    It 'builds no inline handler from tenant names' {
        $script:MatrixHtml | Should -Not -Match 'onchange="togT'
        $script:MatrixScript | Should -Match "addEventListener\('change'"
    }

    It 'embeds the data with no raw < so nothing can close or comment out the script' {
        ([regex]::Matches($script:MatrixHtml, '</script')).Count | Should -Be 1
        $script:MatrixScript | Should -Not -Match '<!--'
        $script:MatrixScript | Should -Match '\\u003c/script>'
    }

    It 'escapes quotes in the JS esc() used for attributes' {
        $esc = [regex]::Match($script:MatrixScript, '(?m)^function esc\(s\)\{.*$').Value
        $esc | Should -Match '&quot;'
        $esc | Should -Match '&#39;'
        $esc | Should -Not -Match 'innerHTML'
    }

    It 'esc() output contains no quote or angle bracket for any hostile name' -Skip:(-not (Get-Command node -ErrorAction SilentlyContinue)) {
        $esc = [regex]::Match($script:MatrixScript, '(?m)^function esc\(s\)\{.*$').Value
        $js = Join-Path $TestDrive 'esc.js'
        $in = Join-Path $TestDrive 'in.json'
        Set-Content -LiteralPath $in -Value (ConvertTo-Json -InputObject $script:Hostile -Depth 100) -Encoding utf8
        Set-Content -LiteralPath $js -Encoding utf8 -Value "$esc`nconst a=JSON.parse(require('fs').readFileSync(process.argv[2],'utf8').replace(/^\uFEFF/,''));process.stdout.write(JSON.stringify(a.map(esc)));"
        $out = (& node $js $in) | ConvertFrom-Json
        $out.Count | Should -Be $script:Hostile.Count
        foreach ($o in $out) { $o | Should -Not -Match '["''<>]' }
    }
}

Describe 'F3: documentation search highlight builds DOM nodes' {
    It 'never assigns decoded text back through innerHTML' {
        $model = New-SecDocModel -PolicyName '<img src=x onerror=alert(1)>' -Settings @(
            [pscustomobject]@{ Name = '<script>alert(1)</script>'; Value = '"><svg onload=alert(1)>'; Indent = 0; IsConfigured = $true })
        $html = & $script:M { param($m) ConvertTo-InforcerHtml -DocModel $m } $model
        $html | Should -Not -Match 'innerHTML=n\.textContent'
        $html | Should -Match "mk\.textContent=m\[0\]"
        $html | Should -Not -Match '<img src=x'
        $html | Should -Not -Match '<svg onload'
        $html | Should -Match '&lt;img src=x onerror=alert\(1\)&gt;'
    }
}

Describe 'F6: comparison report category filter builds options safely' {
    It 'encodes hostile categories and builds the filter options with DOM nodes' {
        # The report's category is the last part of "<product> / <category>".
        $categories = [ordered]@{}
        foreach ($h in $script:Hostile) {
            $rows = [System.Collections.Generic.List[object]]::new()
            $rows.Add(@{ ItemType = 'Setting'; Name = 'S'; SettingPath = ''; Category = "Windows / $h"; Status = 'Matched'
                SourcePolicy = 'P'; SourceValue = '1'; DestPolicy = 'P'; DestValue = '1'; IsDeprecated = $false })
            $categories[$h] = @{ ComparisonRows = $rows }
        }
        $model = @{
            SourceName = 'Contoso'; DestinationName = 'Fabrikam'; ManualReview = [ordered]@{}; GeneratedAt = [datetime]::UtcNow
            Products = [ordered]@{ Windows = @{ Categories = $categories } }
        }
        $html = & $script:M { param($m) ConvertTo-InforcerComparisonHtml -ComparisonModel $m } $model
        $html | Should -Match 'data-category="Q&quot; data-probe=&quot;1"'
        $html | Should -Not -Match 'data-probe="1'
        $html | Should -Not -Match 'optHtml'
        $html | Should -Not -Match 'tag\.innerHTML'
        $html | Should -Match 'optCb\.value = o\.v'
    }
}

Describe 'F4: Excel export writes tenant data as text' -Skip:(-not (Get-Module -ListAvailable -Name ImportExcel)) {
    It 'leaves no formula and no hyperlink in the workbook' {
        $model = New-SecDocModel -PolicyName '=1+1' -Settings @(
            [pscustomobject]@{ Name = '+cmd'; Value = '=HYPERLINK("https://example.invalid","x")'; Indent = 0; IsConfigured = $true }
            [pscustomobject]@{ Name = '-cmd'; Value = 'https://example.invalid/x'; Indent = 0; IsConfigured = $true }
            [pscustomobject]@{ Name = "`tTab"; Value = "`r=3+3"; Indent = 0; IsConfigured = $true })
        $file = Join-Path $TestDrive 'doc.xlsx'
        & $script:M { param($m, $f) Export-InforcerDocExcel -DocModel $m -FilePath $f } $model $file

        $pkg = Open-ExcelPackage -Path $file
        try {
            $cells = foreach ($ws in $pkg.Workbook.Worksheets) { if ($ws.Dimension) { $ws.Cells[$ws.Dimension.Address] } }
            @($cells | Where-Object { $_.Formula }).Count | Should -Be 0
            @($cells | Where-Object { $_.Hyperlink }).Count | Should -Be 0
            $values = @($cells | ForEach-Object { $_.Value })
            $values | Should -Contain "'=1+1"
            $values | Should -Contain 'https://example.invalid/x'
            $values | Should -Contain '+cmd'
        } finally { Close-ExcelPackage $pkg -NoSave }
    }
}

Describe 'F7: settings catalog freshness check and download validation' {
    BeforeAll {
        $script:Stamp = '2026-11-03T06:15:24Z'
        $script:ValidSettings = '[{"id":"setting_a","displayName":"A"}]'
        $script:ValidCategories = '[{"id":"cat-1","displayName":"C"}]'
        function global:Set-SecCatalogCache {
            param([string]$Dir, $ReleaseTimestamp)
            Set-Content -LiteralPath (Join-Path $Dir 'settings.json') -Value '[{"id":"cached"}]' -NoNewline
            Set-Content -LiteralPath (Join-Path $Dir 'categories.json') -Value '[{"id":"cached"}]' -NoNewline
            @{ lastChecked = [datetime]::UtcNow.AddHours(-48).ToString('o'); releaseTimestamp = $ReleaseTimestamp; schemaVersion = 1 } |
                ConvertTo-Json -Depth 100 | Set-Content -LiteralPath (Join-Path $Dir 'cache-meta.json')
        }
        # GitHub serves release assets as application/octet-stream: Content is a byte[].
        $script:CatalogMock = {
            if ($Uri -like '*last-updated.json') {
                return [pscustomobject]@{ StatusCode = 200; Content = [System.Text.Encoding]::UTF8.GetBytes("{`"updatedAt`":`"$script:Stamp`",`"schemaVersion`":1}") }
            }
            $script:CatalogDownloads++
            $body = if ($Uri -like '*categories.json') { $script:CategoriesBody } else { $script:SettingsBody }
            [System.IO.File]::WriteAllText($OutFile, $body)
        }
    }
    AfterAll { Remove-Item function:global:Set-SecCatalogCache -ErrorAction SilentlyContinue }
    BeforeEach {
        $script:Dir = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $script:Dir
        $script:CatalogDownloads = 0
        $script:SettingsBody = $script:ValidSettings
        $script:CategoriesBody = $script:ValidCategories
        Mock -ModuleName InforcerCommunity Invoke-WebRequest $script:CatalogMock
        Mock -ModuleName InforcerCommunity Write-Host { }
    }

    It 'reads the byte[] last-updated.json and keeps an unchanged cache without downloading' {
        Set-SecCatalogCache -Dir $script:Dir -ReleaseTimestamp $script:Stamp
        $p = & $script:M { param($d) Get-InforcerSettingsCatalogPath -CacheDirectory $d -BaseUrl 'https://example.invalid/dl' } $script:Dir
        $p | Should -Be (Join-Path $script:Dir 'settings.json')
        $script:CatalogDownloads | Should -Be 0
        Get-Content -LiteralPath $p -Raw | Should -BeExactly '[{"id":"cached"}]'
    }

    It 'downloads when the cached release timestamp is unknown and records the remote one' {
        Set-SecCatalogCache -Dir $script:Dir -ReleaseTimestamp $null
        $p = & $script:M { param($d) Get-InforcerSettingsCatalogPath -CacheDirectory $d -BaseUrl 'https://example.invalid/dl' } $script:Dir
        $script:CatalogDownloads | Should -Be 2
        Get-Content -LiteralPath $p -Raw | Should -BeExactly $script:ValidSettings
        $meta = Get-Content -LiteralPath (Join-Path $script:Dir 'cache-meta.json') -Raw | ConvertFrom-Json -AsHashtable
        ([datetime]$meta.releaseTimestamp).ToUniversalTime() | Should -Be ([datetime]::Parse($script:Stamp).ToUniversalTime())
        $meta.schemaVersion | Should -Be 1
    }

    It 'never replaces the cache with a download that is not a catalog (<Name>)' -ForEach @(
        @{ Name = 'HTML error page'; Settings = '<html>rate limited</html>'; Categories = '[{"id":"c"}]' }
        @{ Name = 'JSON object'; Settings = '{"id":"x"}'; Categories = '[{"id":"c"}]' }
        @{ Name = 'truncated JSON'; Settings = '[{"id":"x"},'; Categories = '[{"id":"c"}]' }
        @{ Name = 'empty array'; Settings = '[]'; Categories = '[{"id":"c"}]' }
        @{ Name = 'bad categories'; Settings = '[{"id":"x"}]'; Categories = 'not json' }
    ) {
        Set-SecCatalogCache -Dir $script:Dir -ReleaseTimestamp '2026-01-01T00:00:00Z'
        $script:SettingsBody = $Settings
        $script:CategoriesBody = $Categories
        $p = & $script:M { param($d) Get-InforcerSettingsCatalogPath -CacheDirectory $d -BaseUrl 'https://example.invalid/dl' -WarningAction SilentlyContinue } $script:Dir
        $p | Should -Be (Join-Path $script:Dir 'settings.json')
        Get-Content -LiteralPath (Join-Path $script:Dir 'settings.json') -Raw | Should -BeExactly '[{"id":"cached"}]'
        Get-Content -LiteralPath (Join-Path $script:Dir 'categories.json') -Raw | Should -BeExactly '[{"id":"cached"}]'
        @(Get-ChildItem -LiteralPath $script:Dir -Filter '*.tmp').Count | Should -Be 0
    }

    It 'never replaces the cache with a download over the size cap' {
        Set-SecCatalogCache -Dir $script:Dir -ReleaseTimestamp '2026-01-01T00:00:00Z'
        $null = & $script:M { param($d) Get-InforcerSettingsCatalogPath -CacheDirectory $d -BaseUrl 'https://example.invalid/dl' -MaxDownloadBytes 10 -WarningAction SilentlyContinue } $script:Dir
        Get-Content -LiteralPath (Join-Path $script:Dir 'settings.json') -Raw | Should -BeExactly '[{"id":"cached"}]'
    }
}

Describe 'F9: downloaded outputs are treated as internet content' {
    It '-Open does not auto-launch a legacy .xls output, it opens the directory instead' {
        Set-SecTestSession -Mode beta
        & $script:M {
            $script:InforcerReportTypeCache = @([pscustomobject]@{ key = 'X'; name = 'X'; collatable = $false
                supportedOutputFormats = @('xls'); requiredParameters = @(); tags = @() })
            $script:InforcerReportTypeCacheStamp = Get-Date
        }
        $dir = Join-Path $TestDrive 'xls'
        $null = New-Item -ItemType Directory -Path $dir
        Mock -ModuleName InforcerCommunity Invoke-Item { }
        Mock -ModuleName InforcerCommunity Invoke-InforcerApiRequest {
            if ($Method -eq 'POST') { @([pscustomobject]@{ runId = '00000000-0000-0000-0000-0000000000a1'; status = 'queued' }) }
            else { [pscustomobject]@{ outputs = @([pscustomobject]@{ id = 'o1'; reportType = 'X'; tenantId = 1; format = 'xls'; sizeBytes = 4 }) } }
        }
        Mock -ModuleName InforcerCommunity Test-InforcerReportRunTerminal {
            [pscustomobject]@{ IsTerminal = $true; Outputs = @([pscustomobject]@{ id = 'o1'; reportType = 'X'; tenantId = 1; format = 'xls'; sizeBytes = 4 }) }
        }
        Mock -ModuleName InforcerCommunity Invoke-InforcerRawDownload {
            $fp = Join-Path $DestinationDirectory 'macro.xls'
            [System.IO.File]::WriteAllBytes($fp, [byte[]](1, 2, 3, 4))
            [pscustomobject]@{ FilePath = $fp; FileName = 'macro.xls'; FileSize = 4; ContentType = 'application/vnd.ms-excel'; CorrelationId = 't'; StatusCode = 200 }
        }
        $null = Invoke-InforcerReport -ReportType X -OutputFormat xls -TenantId 1 -OutputPath $dir -Open -WarningAction SilentlyContinue
        Should -Invoke -ModuleName InforcerCommunity Invoke-Item -Times 0 -Exactly -ParameterFilter { $LiteralPath -like '*macro.xls' }
        Should -Invoke -ModuleName InforcerCommunity Invoke-Item -Times 1 -Exactly -ParameterFilter { $LiteralPath -eq $dir }
    }

    It 'marks a saved output with Zone.Identifier ZoneId=3 on Windows' -Skip:(-not $IsWindows) {
        Set-SecTestSession -Mode beta
        $script:SecDisposition = 'attachment; filename="motw.csv"'
        Mock -ModuleName InforcerCommunity Invoke-WebRequest $script:DownloadMock
        $r = & $script:M { param($d) Invoke-InforcerRawDownload -Endpoint '/reports/runs/r/outputs/o' -DestinationDirectory $d } $TestDrive
        (Get-Content -LiteralPath $r.FilePath -Stream 'Zone.Identifier') -join "`n" | Should -Match 'ZoneId=3'
    }
}

Describe 'F10: Markdown export escapes HTML in table cells and headings' {
    It 'encodes ampersand and angle brackets while keeping the pipe and newline handling' {
        $model = New-SecDocModel -PolicyName '<img src=x onerror=alert(1)>' -Settings @(
            [pscustomobject]@{ Name = '<script>alert(1)</script>'; Value = "a|b`nc & d"; Indent = 0; IsConfigured = $true })
        $md = & $script:M { param($m) ConvertTo-InforcerMarkdown -DocModel $m } $model
        $md | Should -Match '(?m)^#### &lt;img src=x onerror=alert\(1\)&gt;\r?$'
        $md | Should -Match '\| &lt;script&gt;alert\(1\)&lt;/script&gt; \| a\\\|b<br>c &amp; d \|'
        $md | Should -Not -Match '<script>'
        $md | Should -Not -Match '<img'
    }
}

Describe 'F5: run polling does not follow a redirect' {
    It 'Test-InforcerReportRunTerminal stops at a 302 with the redirect message' {
        & $script:M { $script:InforcerSession = @{ AuthMode = 'ApiKey'; ApiVersion = 'beta'; ApiHost = 'https://api.example.invalid'; BaseUrl = 'https://api.example.invalid/api'; Region = 'uk'; ApiKey = (ConvertTo-SecureString 'k' -AsPlainText -Force) } }
        Mock -ModuleName InforcerCommunity Invoke-WebRequest { [pscustomobject]@{ StatusCode = 302; Headers = @{ Location = 'https://elsewhere.invalid/x' }; Content = '' } }
        $r = & $script:M { Test-InforcerReportRunTerminal -RunId ([guid]'00000000-0000-0000-0000-0000000000a1') -ErrorVariable ev -ErrorAction SilentlyContinue; $ev } 
        "$r" | Should -Match 'redirect \(HTTP 302\)'
        Should -Invoke -ModuleName InforcerCommunity Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $MaximumRedirection -eq 0 }
    }
}
