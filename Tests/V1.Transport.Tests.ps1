# V1.Transport.Tests.ps1
# Session, auth header, URL building, v1 mapping, unwrap, errors, retries, paging and tenant resolution.
# Fixtures are anonymised (zero GUIDs, example names); no network calls.

BeforeAll {
    Remove-Module -Name 'InforcerCommunity' -ErrorAction SilentlyContinue
    Import-Module (Join-Path $PSScriptRoot '../module/InforcerCommunity.psd1') -Force
    $script:M = Get-Module InforcerCommunity

    $script:Tid1 = '00000000-0000-0000-0000-000000000001'
    $script:Tid2 = '00000000-0000-0000-0000-000000000002'

    # Shape returned by the module's Invoke-InforcerHttpRequest wrapper (Invoke-RestMethod -SkipHttpErrorCheck).
    function global:New-V1TestResponse {
        param([int]$Status = 200, $Body, [string]$RetryAfter)
        if ($Body -is [string]) { $Body = $Body | ConvertFrom-Json -Depth 100 }
        $h = @{}
        if ($RetryAfter) { $h['Retry-After'] = @($RetryAfter) }
        [pscustomobject]@{ StatusCode = $Status; Body = $Body; Headers = $h }
    }

    function global:Set-V1TestSession {
        param([switch]$Beta, [switch]$ExpiredToken)
        & (Get-Module InforcerCommunity) {
            param($Beta, $ExpiredToken)
            $script:InforcerTenantListCache = $null
            if ($Beta) {
                $script:InforcerSession = @{
                    AuthMode = 'ApiKey'; ApiVersion = 'beta'; ApiHost = 'https://api.example.invalid'
                    BaseUrl = 'https://api.example.invalid/api'; Region = 'uk'; ConnectedAt = Get-Date
                    ApiKey = (ConvertTo-SecureString 'beta-test-key-value' -AsPlainText -Force)
                }
            } else {
                $script:InforcerSession = @{
                    AuthMode = 'ClientCredentials'; ApiVersion = 'v1'; ApiHost = 'https://api.example.invalid'
                    BaseUrl = 'https://api.example.invalid'; Region = 'uk'; ConnectedAt = Get-Date
                    ClientId = 'client-id-example'
                    ClientSecret = (ConvertTo-SecureString 'client-secret-example-value' -AsPlainText -Force)
                    AccessToken = (ConvertTo-SecureString 'access-token-example-value' -AsPlainText -Force)
                    TokenExpiresAt = if ($ExpiredToken) { [datetime]::UtcNow.AddMinutes(2) } else { [datetime]::UtcNow.AddMinutes(50) }
                }
            }
        } $Beta.IsPresent $ExpiredToken.IsPresent
    }
}

AfterAll {
    Remove-Item function:global:New-V1TestResponse -ErrorAction SilentlyContinue
    Remove-Item function:global:Set-V1TestSession -ErrorAction SilentlyContinue
    & (Get-Module InforcerCommunity) { $script:InforcerSession = $null; $script:InforcerTenantListCache = $null }
}

Describe 'Test-InforcerSession' {
    It 'is true for a client-credentials session' {
        Set-V1TestSession
        & $script:M { Test-InforcerSession } | Should -BeTrue
    }
    It 'is false for a v1 session without a client secret' {
        & $script:M { Test-InforcerSession -Session @{ ApiVersion = 'v1'; ApiHost = 'https://api.example.invalid' } } | Should -BeFalse
    }
    It 'is true for a legacy session shape without ApiVersion' {
        & $script:M { Test-InforcerSession -Session @{ ApiKey = (ConvertTo-SecureString 'k' -AsPlainText -Force); BaseUrl = 'https://api.example.invalid/api' } } | Should -BeTrue
    }
}

Describe 'Get-InforcerBaseUrl' {
    It 'maps a region to the API host without a path' {
        & $script:M { Get-InforcerBaseUrl -Region uk } | Should -Be 'https://api-uk.inforcer.com'
    }
    It 'accepts -BaseUrl as host+/api and as host' {
        & $script:M { Get-InforcerBaseUrl -BaseUrl 'https://api.example.invalid/api/' } | Should -Be 'https://api.example.invalid'
        & $script:M { Get-InforcerBaseUrl -BaseUrl 'https://api.example.invalid' } | Should -Be 'https://api.example.invalid'
    }
    It 'builds beta URIs from neutral endpoints' {
        Set-V1TestSession -Beta
        & $script:M { Get-InforcerBaseUrl -Endpoint '/tenants' } | Should -Be 'https://api.example.invalid/api/beta/tenants'
    }
    It 'does not apply v1 renames on beta' {
        Set-V1TestSession -Beta
        & $script:M { Get-InforcerBaseUrl -Endpoint '/tenants/5/roles' } | Should -Be 'https://api.example.invalid/api/beta/tenants/5/roles'
    }
    It 'builds v1 URIs' {
        Set-V1TestSession
        & $script:M { Get-InforcerBaseUrl -Endpoint 'tenants' } | Should -Be 'https://api.example.invalid/v1/tenants'
        & $script:M { Get-InforcerBaseUrl -Endpoint '/baselines' } | Should -Be 'https://api.example.invalid/v1/baselines'
    }
    It 'renames roles to directoryRoles on v1' {
        Set-V1TestSession
        & $script:M { param($t) Get-InforcerBaseUrl -Endpoint "/tenants/$t/roles" } $script:Tid1 | Should -Be "https://api.example.invalid/v1/tenants/$script:Tid1/directoryRoles"
    }
    It 'renames auditEvents/eventTypes to auditEvents/types on v1' {
        Set-V1TestSession
        & $script:M { Get-InforcerBaseUrl -Endpoint '/auditEvents/eventTypes' } | Should -Be 'https://api.example.invalid/v1/auditEvents/types'
    }
    It 'renames the customBaselineId query parameter to baselineId on v1' {
        Set-V1TestSession
        & $script:M { Get-InforcerBaseUrl -Endpoint '/tenants/x/alignmentDetails?customBaselineId=abc' } | Should -Be 'https://api.example.invalid/v1/tenants/x/alignmentDetails?baselineId=abc'
    }
}

Describe 'Get-InforcerAuthHeader' {
    It 'builds only Inf-Api-Key for an API-key session' {
        Set-V1TestSession -Beta
        $h = & $script:M { Get-InforcerAuthHeader }
        $h.Keys | Should -Be @('Inf-Api-Key')
        $h['Inf-Api-Key'] | Should -Be 'beta-test-key-value'
    }
    It 'uses the cached token while it is valid' {
        Set-V1TestSession
        Mock -ModuleName InforcerCommunity Invoke-RestMethod { throw 'should not be called' }
        $h = & $script:M { Get-InforcerAuthHeader }
        $h['Authorization'] | Should -BeExactly 'Bearer access-token-example-value'
        Should -Invoke -ModuleName InforcerCommunity Invoke-RestMethod -Times 0 -Exactly
    }
    It 'renews the token when less than five minutes remain and stores it in the session' {
        Set-V1TestSession -ExpiredToken
        Mock -ModuleName InforcerCommunity Invoke-RestMethod { [pscustomobject]@{ access_token = 'renewed-token'; token_type = 'Bearer'; expires_in = 3600 } }
        $h = & $script:M { Get-InforcerAuthHeader }
        $h['Authorization'] | Should -BeExactly 'Bearer renewed-token'
        $exp = & $script:M { $script:InforcerSession.TokenExpiresAt }
        ($exp - [datetime]::UtcNow).TotalMinutes | Should -BeGreaterThan 55
        Should -Invoke -ModuleName InforcerCommunity Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'https://api.example.invalid/oauth/token' -and $Method -eq 'POST' -and
            $ContentType -eq 'application/x-www-form-urlencoded' -and $Body.grant_type -eq 'client_credentials' -and
            $Body.client_id -eq 'client-id-example' -and $Body.client_secret -eq 'client-secret-example-value'
        }
    }
    It 'renews on -ForceRefresh' {
        Set-V1TestSession
        Mock -ModuleName InforcerCommunity Invoke-RestMethod { [pscustomobject]@{ access_token = 'forced-token'; expires_in = 3600 } }
        (& $script:M { Get-InforcerAuthHeader -ForceRefresh })['Authorization'] | Should -BeExactly 'Bearer forced-token'
    }
    It 'reports a failed token request without the secret' {
        Set-V1TestSession -ExpiredToken
        Mock -ModuleName InforcerCommunity Invoke-InforcerHttpRequest {
            New-V1TestResponse -Status 401 -Body '{"error":"invalid_client","error_description":"bad client-secret-example-value"}'
        }
        $e = & $script:M { $h = Get-InforcerAuthHeader -ErrorAction SilentlyContinue -ErrorVariable ev; $h; $ev }
        @($e).Count | Should -Be 1
        $e[0].FullyQualifiedErrorId | Should -Match '^TokenRequestFailed'
        $msg = $e[0].Exception.Message
        $msg | Should -Match 'HTTP 401'
        $msg | Should -Match 'invalid_client'
        $msg | Should -Not -Match 'client-secret-example-value'
    }
}

Describe 'Protect-InforcerApiKeyInText' {
    It 'redacts the session secret, access token and bearer tokens' {
        Set-V1TestSession
        $t = & $script:M { Protect-InforcerApiKeyInText -Text 'a client-secret-example-value b access-token-example-value c Authorization: Bearer abc.def-ghi' }
        $t | Should -Not -Match 'client-secret-example-value|access-token-example-value|abc\.def-ghi'
        $t | Should -Match 'Bearer \[REDACTED\]'
    }
    It 'redacts JWT-shaped strings and an explicit -ApiKey' {
        $t = & $script:M { Protect-InforcerApiKeyInText -Text 'x eyJhbGciOi.eyJzdWIiOi.c2lnbmF0dXJl y explicit-key' -ApiKey 'explicit-key' -Session @{} }
        $t | Should -BeExactly 'x [REDACTED] y [REDACTED]'
    }
}

Describe 'ConvertFrom-InforcerV1Response' {
    BeforeAll {
        function script:Map([string]$Json, [string]$Type) {
            $o = $Json | ConvertFrom-Json -Depth 100
            & (Get-Module InforcerCommunity) { param($o, $t) ConvertFrom-InforcerV1Response -InputObject $o -ObjectType $t } $o $Type
        }
        function script:Names($o) { @($o.PSObject.Properties.Name) }
    }

    It 'Tenant: name/dnsName to tenantFriendlyName/tenantDnsName, alignment summary timestamp renamed' {
        $r = Map '{"msTenantId":"00000000-0000-0000-0000-000000000001","name":"Contoso","dnsName":"contoso.onmicrosoft.com","authenticationMode":"x","alignmentSummaries":[{"alignedBaselineId":"b","alignedBaselineMsTenantId":"00000000-0000-0000-0000-000000000002","lastAlignmentTimestamp":"2026-01-01T00:00:00Z"}]}' Tenant
        Names $r | Should -Be @('msTenantId', 'tenantFriendlyName', 'tenantDnsName', 'authenticationMode', 'alignmentSummaries')
        $r.tenantFriendlyName | Should -BeExactly 'Contoso'
        Names $r.alignmentSummaries[0] | Should -Contain 'lastAlignmentDateTime'
        Names $r.alignmentSummaries[0] | Should -Not -Contain 'lastAlignmentTimestamp'
    }
    It 'Policy: policyTypeName to inforcerPolicyTypeName, id kept' {
        $r = Map '{"id":"p1","policyTypeId":1,"policyTypeName":"Settings Catalog","displayName":"P","policyData":{"id":"p1"}}' Policy
        Names $r | Should -Be @('id', 'policyTypeId', 'inforcerPolicyTypeName', 'displayName', 'policyData')
    }
    It 'Baseline: baselineTenant flattened, members and items renamed' {
        $r = Map '{"id":"b1","name":"Base","baselineTenant":{"msTenantId":"00000000-0000-0000-0000-000000000001","name":"Contoso","dnsName":"contoso.onmicrosoft.com"},"mode":"include","members":[{"msTenantId":"00000000-0000-0000-0000-000000000002","name":"Fabrikam","dnsName":"fabrikam.onmicrosoft.com","lastAlignmentScore":90}],"items":[{"product":"Intune","primaryGroup":"Windows","secondaryGroup":"Settings","alignAssignments":true}]}' Baseline
        Names $r | Should -Be @('id', 'name', 'baselineMsTenantId', 'baselineTenantFriendlyName', 'baselineTenantDnsName', 'mode', 'members', 'items')
        Names $r.members[0] | Should -Be @('msTenantId', 'tenantFriendlyName', 'tenantDnsName', 'lastAlignmentScore')
        Names $r.items[0] | Should -Be @('policyCategoryProduct', 'policyCategoryPrimaryGroup', 'policyCategorySecondaryGroup', 'alignAssignments')
    }
    It 'Baseline: a null baselineTenant still yields the canonical keys' {
        $r = Map '{"id":"b1","baselineTenant":null}' Baseline
        Names $r | Should -Be @('id', 'baselineMsTenantId', 'baselineTenantFriendlyName', 'baselineTenantDnsName')
    }
    It 'AlignmentScore: every renamed field maps to the beta name' {
        $r = Map '{"msTenantId":"00000000-0000-0000-0000-000000000001","tenantName":"Contoso","alignedBaselineId":"b","alignedBaselineMsTenantId":"00000000-0000-0000-0000-000000000002","alignedBaselineName":"Base","alignmentScore":97.5,"alignedThreshold":90,"semiAlignedThreshold":70,"lastAlignmentTimestamp":"t"}' AlignmentScore
        Names $r | Should -Be @('msTenantId', 'tenantFriendlyName', 'baselineGroupId', 'alignedBaselineMsTenantId', 'baselineGroupName', 'score', 'alignedThreshold', 'semiAlignedThreshold', 'lastComparisonDateTime')
    }
    It 'AlignmentDetails: buckets, metrics and per-policy fields map to the beta shape' {
        $json = '{"completedAt":"c","baseline":{"id":"b","msTenantId":"00000000-0000-0000-0000-000000000002"},"baselineDataTimestamp":"bt","tenantDataTimestamp":"tt","alignmentScore":98,"metrics":{"totalPolicies":3,"matched":1,"matchedWithAcceptedDeviations":0,"deviated":1,"missingFromTenant":1,"additionalInTenant":0},"policies":{"matched":[{"id":"p","policyTypeName":"T","displayName":"Policy A","product":"Intune","tags":[{"name":"x"}],"tenantPolicies":[{"id":"tp","policyDataDiff":[{"op":"replace","path":"/a","baselineValue":"1","tenantValue":"2"}],"tags":[]}],"variables":[{"name":"v","tenantValue":"t"}],"acceptedDeviations":[{"acceptedTimestamp":"a","reason":"r"}],"similarPolicies":[{"id":"s","name":"Sim","categoryName":"Cat"}]}],"matchedWithAcceptedDeviations":[],"deviated":[],"missingFromTenant":[],"additionalInTenant":[]}}'
        $r = Map $json AlignmentDetails
        Names $r | Should -Be @('completedAt', 'baseline', 'alignment', 'metrics')
        Names $r.alignment | Should -Be @('alignmentScore', 'baselineDataTimestamp', 'subjectDataTimestamp', 'matchedPolicies', 'matchedWithAcceptedDeviations', 'deviatedUnaccepted', 'missingFromSubjectUnaccepted', 'additionalInSubjectUnaccepted')
        Names $r.metrics | Should -Be @('totalPolicies', 'matchedPolicies', 'matchedWithAcceptedDeviations', 'deviatedPolicies', 'recommendedPoliciesFromBaseline', 'customerOnlyPolicies')
        $p = $r.alignment.matchedPolicies[0]
        $p.policyName | Should -BeExactly 'Policy A'
        $p.inforcerPolicyTypeName | Should -BeExactly 'T'
        Names $p | Should -Contain 'policyTags'
        $p.matchingSubjectPolicies[0].policyDataDiff[0].subjectValue | Should -Be '2'
        $p.matchingVariables[0].variableName | Should -Be 'v'
        $p.acceptedDeviations[0].acceptedReason | Should -Be 'r'
        $p.similarPolicies[0].policyCategoryName | Should -Be 'Cat'
        $r.alignment.deviatedUnaccepted.Count | Should -Be 0
    }
    It 'User: groupCount/roleCount to groups/roles' {
        $r = Map '{"id":"u","displayName":"User","groupCount":3,"roleCount":1}' User
        Names $r | Should -Be @('id', 'displayName', 'groups', 'roles')
    }
    It 'User detail: arrays named groups/roles stay as they are' {
        $r = Map '{"id":"u","groups":[{"id":"g"}],"roles":[]}' User
        $r.groups[0].id | Should -Be 'g'
    }
    It 'AssessmentRun: assessmentId to assessment' {
        $r = Map '{"assessmentId":"a","name":"N","results":[]}' AssessmentRun
        Names $r | Should -Be @('assessment', 'name', 'results')
    }
    It 'ReportRun: reportRunId to runId' {
        Names (Map '{"reportRunId":"r","status":"queued"}' ReportRun) | Should -Be @('runId', 'status')
    }
    It 'ReportOutput: msTenantId to tenantId (null stays null for collated output)' {
        $r = Map '{"id":"o","reportType":"X","msTenantId":null,"format":"csv","sizeBytes":4}' ReportOutput
        Names $r | Should -Be @('id', 'reportType', 'tenantId', 'format', 'sizeBytes')
        $r.tenantId | Should -BeNullOrEmpty
    }
    It '<Type> has no renames and passes through unchanged' -ForEach @(
        @{ Type = 'Group'; Json = '{"id":"g","displayName":"G","membershipRule":null}' }
        @{ Type = 'GroupMember'; Json = '{"id":"m","displayName":"M","type":"#microsoft.graph.user"}' }
        @{ Type = 'Role'; Json = '{"id":"r","templateId":"t","displayName":"R","isBuiltIn":true}' }
        @{ Type = 'SecureScore'; Json = '{"currentScore":1,"maxScore":2,"scores":[]}' }
        @{ Type = 'Assessment'; Json = '{"id":"a","name":"A","assessmentType":"platform"}' }
        @{ Type = 'ReportType'; Json = '{"key":"K","name":"N","singleTenantOnly":false}' }
        @{ Type = 'AuditEvent'; Json = '{"id":"e","eventType":"x","timestamp":"t","metadata":{}}' }
        @{ Type = 'AuditEventType'; Json = '{"name":"tenantCreate"}' }
    ) {
        $src = $Json | ConvertFrom-Json -Depth 100
        $r = Map $Json $Type
        ($r | ConvertTo-Json -Depth 100 -Compress) | Should -BeExactly ($src | ConvertTo-Json -Depth 100 -Compress)
    }
    It 'never emits duplicate keys when the canonical name is already present' {
        $r = Map '{"name":"v1","tenantFriendlyName":"canonical","msTenantId":"00000000-0000-0000-0000-000000000001"}' Tenant
        Names $r | Should -Be @('tenantFriendlyName', 'msTenantId')
        $r.tenantFriendlyName | Should -BeExactly 'canonical'
    }
    It 'does not modify its input' {
        $o = '{"name":"Contoso"}' | ConvertFrom-Json
        $null = & $script:M { param($o) ConvertFrom-InforcerV1Response -InputObject $o -ObjectType Tenant } $o
        Names $o | Should -Be @('name')
    }
}

Describe 'Invoke-InforcerApiRequest on v1' {
    BeforeEach { Set-V1TestSession }

    It 'unwraps the collection, maps it and sends a bearer header to the v1 URI' {
        Mock -ModuleName InforcerCommunity Invoke-RestMethod {
            [pscustomobject]@{ tenants = @([pscustomobject]@{ msTenantId = '00000000-0000-0000-0000-000000000001'; name = 'Contoso'; dnsName = 'contoso.example' }) }
        }
        $r = @(& $script:M { Invoke-InforcerApiRequest -Endpoint '/tenants' -ObjectType Tenant })
        $r.Count | Should -Be 1
        $r[0].tenantFriendlyName | Should -BeExactly 'Contoso'
        Should -Invoke -ModuleName InforcerCommunity Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Uri -eq 'https://api.example.invalid/v1/tenants' -and $Headers['Authorization'] -eq 'Bearer access-token-example-value' -and -not $Headers.ContainsKey('Inf-Api-Key')
        }
    }
    It 'never unwraps a single object that holds arrays' {
        Mock -ModuleName InforcerCommunity Invoke-RestMethod {
            [pscustomobject]@{ msTenantId = '00000000-0000-0000-0000-000000000001'; name = 'Contoso'; tags = @(); licenses = @([pscustomobject]@{ sku = 'X' }) }
        }
        $r = & $script:M { Invoke-InforcerApiRequest -Endpoint '/tenants/00000000-0000-0000-0000-000000000001' -ObjectType Tenant }
        $r.tenantFriendlyName | Should -BeExactly 'Contoso'
        $r.licenses[0].sku | Should -Be 'X'
    }
    It 'unwraps a collection next to metadata keys and ignores the metadata' {
        Mock -ModuleName InforcerCommunity Invoke-RestMethod {
            [pscustomobject]@{ users = @([pscustomobject]@{ id = 'u1'; groupCount = 2 }); userCount = 1; continuationToken = $null }
        }
        $r = @(& $script:M { Invoke-InforcerApiRequest -Endpoint '/tenants/x/users' -ObjectType User })
        $r.Count | Should -Be 1
        $r[0].groups | Should -Be 2
    }
    It '-OutputType JsonObject returns a JSON array, not the wrapper, even for one item' {
        Mock -ModuleName InforcerCommunity Invoke-RestMethod { [pscustomobject]@{ reportRuns = @([pscustomobject]@{ reportRunId = 'r1' }) } }
        $j = & $script:M { Invoke-InforcerApiRequest -Endpoint '/reports/runs' -ObjectType ReportRun -OutputType JsonObject }
        $j.TrimStart() | Should -Match '^\['
        $j | Should -Match '"runId"'
        $j | Should -Not -Match 'reportRuns|reportRunId'
    }
    It '-OutputType JsonObject of an empty collection is []' {
        Mock -ModuleName InforcerCommunity Invoke-RestMethod { [pscustomobject]@{ policies = @(); failedPolicyTypes = [pscustomobject]@{} } }
        (& $script:M { Invoke-InforcerApiRequest -Endpoint '/tenants/x/policies' -OutputType JsonObject }) | Should -Be '[]'
    }
    It 'warns with the type names when failedPolicyTypes is not empty' {
        Mock -ModuleName InforcerCommunity Invoke-RestMethod {
            [pscustomobject]@{ policies = @(); failedPolicyTypes = [pscustomobject]@{ 'Device Configuration' = 'timeout'; 'Compliance' = 'error' } }
        }
        $w = & $script:M { $null = Invoke-InforcerApiRequest -Endpoint '/tenants/x/policies' -WarningVariable wv -WarningAction SilentlyContinue; $wv }
        ($w -join ' ') | Should -Match 'Device Configuration'
        ($w -join ' ') | Should -Match 'Compliance'
    }
    It 'stays quiet when failedPolicyTypes is empty' {
        Mock -ModuleName InforcerCommunity Invoke-RestMethod { [pscustomobject]@{ policies = @(); failedPolicyTypes = [pscustomobject]@{} } }
        $w = & $script:M { $null = Invoke-InforcerApiRequest -Endpoint '/tenants/x/policies' -WarningVariable wv -WarningAction SilentlyContinue; $wv }
        $w | Should -BeNullOrEmpty
    }
    It '-PreserveFullResponse keeps continuationToken and maps the collection' {
        Mock -ModuleName InforcerCommunity Invoke-RestMethod {
            [pscustomobject]@{ groups = @([pscustomobject]@{ id = 'g1' }); groupCount = 9; continuationToken = 'next' }
        }
        $r = & $script:M { Invoke-InforcerApiRequest -Endpoint '/tenants/x/groups' -ObjectType Group -PreserveFullResponse }
        $r.continuationToken | Should -Be 'next'
        $r.groupCount | Should -Be 9
        @($r.groups).Count | Should -Be 1
    }
    It 'turns problem+json into "title: detail (field: message)" with ApiRequestFailed_<status>' {
        Mock -ModuleName InforcerCommunity Invoke-InforcerHttpRequest {
            New-V1TestResponse -Status 400 -Body '{"type":"about:blank","title":"Validation failed","status":400,"detail":"The request is invalid","instance":"/v1/x","errors":{"baselineId":["is required","must be a uuid"]}}'
        }
        $e = & $script:M { Invoke-InforcerApiRequest -Endpoint '/tenants/x/alignmentDetails' -ErrorAction SilentlyContinue -ErrorVariable ev; $ev }
        $e[0].FullyQualifiedErrorId | Should -Match '^ApiRequestFailed_400'
        $e[0].Exception.Message | Should -Match 'Validation failed: The request is invalid \(baselineId: is required, must be a uuid\)'
    }
    It 'keeps 404 messages recognisable for callers matching 404|not found' {
        Mock -ModuleName InforcerCommunity Invoke-InforcerHttpRequest {
            New-V1TestResponse -Status 404 -Body '{"type":"about:blank","title":"Not Found","status":404,"detail":"Tenant not found"}'
        }
        $e = & $script:M { Invoke-InforcerApiRequest -Endpoint '/tenants/x' -ErrorAction SilentlyContinue -ErrorVariable ev; $ev }
        $e[0].FullyQualifiedErrorId | Should -Match '^ApiRequestFailed_404'
        $e[0].Exception.Message | Should -Match '404|not found'
        @($e).Count | Should -Be 1 -Because 'callers check $err[0].FullyQualifiedErrorId, so no raw web error may precede it'
    }
    It 'reports a failed token renewal once as TokenRequestFailed' {
        Set-V1TestSession -ExpiredToken
        Mock -ModuleName InforcerCommunity Invoke-InforcerHttpRequest { New-V1TestResponse -Status 401 -Body '{"error":"invalid_client"}' }
        $e = & $script:M { Invoke-InforcerApiRequest -Endpoint '/tenants' -ErrorAction SilentlyContinue -ErrorVariable ev; $ev }
        @($e).Count | Should -Be 1
        $e[0].FullyQualifiedErrorId | Should -Match '^TokenRequestFailed'
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 1 -Exactly
    }
    It 'honours Retry-After seconds on 429 and then succeeds' {
        $script:calls = 0
        Mock -ModuleName InforcerCommunity Start-Sleep { }
        Mock -ModuleName InforcerCommunity Invoke-InforcerHttpRequest {
            $script:calls++
            if ($script:calls -eq 1) { return (New-V1TestResponse -Status 429 -RetryAfter '7' -Body '{"title":"Too Many Requests","status":429}') }
            New-V1TestResponse -Body '{"tenants":[{"msTenantId":"00000000-0000-0000-0000-000000000001"}]}'
        }
        $r = @(& $script:M { Invoke-InforcerApiRequest -Endpoint '/tenants' })
        $r.Count | Should -Be 1
        Should -Invoke -ModuleName InforcerCommunity Start-Sleep -Times 1 -Exactly -ParameterFilter { $Seconds -eq 7 }
    }
    It 'honours a Retry-After HTTP date' {
        $s = & $script:M { Get-InforcerRetryDelay -Value ([datetimeoffset]::UtcNow.AddSeconds(30).ToString('r')) }
        $s | Should -BeGreaterOrEqual 28
        $s | Should -BeLessOrEqual 31
    }
    It 'gives up after three 429 retries with ApiRequestFailed_429' {
        Mock -ModuleName InforcerCommunity Start-Sleep { }
        Mock -ModuleName InforcerCommunity Invoke-InforcerHttpRequest { New-V1TestResponse -Status 429 -RetryAfter '1' }
        $e = & $script:M { Invoke-InforcerApiRequest -Endpoint '/tenants' -ErrorAction SilentlyContinue -ErrorVariable ev; $ev }
        @($e).Count | Should -Be 1 -Because 'only the module error reaches -ErrorVariable'
        $e[0].FullyQualifiedErrorId | Should -Match '^ApiRequestFailed_429'
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 4 -Exactly
        Should -Invoke -ModuleName InforcerCommunity Start-Sleep -Times 3 -Exactly
    }
    It 'renews the token once on 401 and retries' {
        $script:calls = 0
        Mock -ModuleName InforcerCommunity Invoke-InforcerHttpRequest {
            if ($Request.Uri -like '*/oauth/token') { return (New-V1TestResponse -Body '{"access_token":"renewed-after-401","expires_in":3600}') }
            $script:calls++
            if ($script:calls -eq 1) { return (New-V1TestResponse -Status 401) }
            New-V1TestResponse -Body '{"tenants":[]}'
        }
        $e = & $script:M { $null = Invoke-InforcerApiRequest -Endpoint '/tenants' -ErrorAction SilentlyContinue -ErrorVariable ev; $ev }
        $e | Should -BeNullOrEmpty
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 1 -Exactly -ParameterFilter { $Request.Uri -like '*/oauth/token' }
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 1 -Exactly -ParameterFilter { $Request.Headers['Authorization'] -eq 'Bearer renewed-after-401' }
    }
    It 'renews only once when a 401 is followed by a 429' {
        $script:calls = 0
        Mock -ModuleName InforcerCommunity Start-Sleep { }
        Mock -ModuleName InforcerCommunity Invoke-InforcerHttpRequest {
            if ($Request.Uri -like '*/oauth/token') { return (New-V1TestResponse -Body '{"access_token":"renewed","expires_in":3600}') }
            $script:calls++
            switch ($script:calls) {
                1 { New-V1TestResponse -Status 401 }
                2 { New-V1TestResponse -Status 429 -RetryAfter '1' }
                default { New-V1TestResponse -Body '{"tenants":[]}' }
            }
        }
        $null = & $script:M { Invoke-InforcerApiRequest -Endpoint '/tenants' }
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 1 -Exactly -ParameterFilter { $Request.Uri -like '*/oauth/token' }
    }
    It 'reports a second 401 instead of looping' {
        Mock -ModuleName InforcerCommunity Invoke-InforcerHttpRequest {
            if ($Request.Uri -like '*/oauth/token') { return (New-V1TestResponse -Body '{"access_token":"renewed","expires_in":3600}') }
            New-V1TestResponse -Status 401 -Body '{"title":"Unauthorized","status":401}'
        }
        $e = & $script:M { Invoke-InforcerApiRequest -Endpoint '/tenants' -ErrorAction SilentlyContinue -ErrorVariable ev; $ev }
        $e[0].FullyQualifiedErrorId | Should -Match '^ApiRequestFailed_401'
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 1 -Exactly -ParameterFilter { $Request.Uri -like '*/oauth/token' }
    }
    It 'never puts the token in an error message' {
        Mock -ModuleName InforcerCommunity Invoke-InforcerHttpRequest { New-V1TestResponse -Status 500 -Body '{"title":"Boom","status":500,"detail":"echo access-token-example-value"}' }
        $e = & $script:M { Invoke-InforcerApiRequest -Endpoint '/tenants' -ErrorAction SilentlyContinue -ErrorVariable ev; $ev }
        $e[0].Exception.Message | Should -Not -Match 'access-token-example-value'
    }
}

Describe 'Invoke-InforcerApiRequest on beta (unchanged behaviour)' {
    BeforeEach { Set-V1TestSession -Beta }

    It 'unwraps .data, sends Inf-Api-Key and accepts neutral and /beta paths' {
        Mock -ModuleName InforcerCommunity Invoke-RestMethod { [pscustomobject]@{ success = $true; data = @([pscustomobject]@{ clientTenantId = 1 }) } }
        @(& $script:M { Invoke-InforcerApiRequest -Endpoint '/tenants' }).Count | Should -Be 1
        @(& $script:M { Invoke-InforcerApiRequest -Endpoint '/tenants' -ObjectType Tenant }).Count | Should -Be 1
        Should -Invoke -ModuleName InforcerCommunity Invoke-RestMethod -Times 2 -Exactly -ParameterFilter {
            $Uri -eq 'https://api.example.invalid/api/beta/tenants' -and $Headers['Inf-Api-Key'] -eq 'beta-test-key-value' -and -not $Headers.ContainsKey('Authorization')
        }
    }
    It 'does not retry a beta 401' {
        Mock -ModuleName InforcerCommunity Invoke-InforcerHttpRequest { New-V1TestResponse -Status 401 -Body '{"statusCode":401,"message":"Access denied"}' }
        $e = & $script:M { Invoke-InforcerApiRequest -Endpoint '/tenants' -ErrorAction SilentlyContinue -ErrorVariable ev; $ev }
        $e[0].FullyQualifiedErrorId | Should -Match '^ApiRequestFailed_401'
        $e[0].Exception.Message | Should -Match 'Access denied'
        Should -Invoke -ModuleName InforcerCommunity Invoke-InforcerHttpRequest -Times 1 -Exactly
    }
    It 'keeps the app-envelope errors[] detail' {
        Mock -ModuleName InforcerCommunity Invoke-InforcerHttpRequest { New-V1TestResponse -Status 403 -Body '{"success":false,"errorCode":"forbidden","message":"Forbidden","errors":["Insufficient scope"]}' }
        $e = & $script:M { Invoke-InforcerApiRequest -Endpoint '/tenants' -ErrorAction SilentlyContinue -ErrorVariable ev; $ev }
        $e[0].Exception.Message | Should -Match 'HTTP 403.*Insufficient scope'
    }
}

Describe 'Invoke-InforcerPagedRequest' {
    It 'follows continuationToken in the query string on v1 GET' {
        Set-V1TestSession
        Mock -ModuleName InforcerCommunity Invoke-RestMethod {
            switch -Wildcard ($Uri) {
                '*continuationToken=t2' { [pscustomobject]@{ users = @([pscustomobject]@{ id = 'u3' }); continuationToken = $null } }
                '*continuationToken=t%2B1' { [pscustomobject]@{ users = @([pscustomobject]@{ id = 'u2' }); continuationToken = 't2' } }
                default { [pscustomobject]@{ users = @([pscustomobject]@{ id = 'u1'; groupCount = 1 }); userCount = 3; continuationToken = 't+1' } }
            }
        }
        $r = @(& $script:M { Invoke-InforcerPagedRequest -Endpoint '/tenants/x/users?search=a' -ObjectType User })
        $r.id | Should -Be @('u1', 'u2', 'u3')
        $r[0].groups | Should -Be 1
        Should -Invoke -ModuleName InforcerCommunity Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Uri -eq 'https://api.example.invalid/v1/tenants/x/users?search=a&continuationToken=t%2B1' }
    }
    It 'stops when the API repeats a token' {
        Set-V1TestSession
        Mock -ModuleName InforcerCommunity Invoke-RestMethod { [pscustomobject]@{ groups = @([pscustomobject]@{ id = 'g' }); continuationToken = 'same' } }
        $r = @(& $script:M { Invoke-InforcerPagedRequest -Endpoint '/tenants/x/groups' })
        $r.Count | Should -Be 2
    }
    It 'stops at -MaxResults' {
        Set-V1TestSession
        Mock -ModuleName InforcerCommunity Invoke-RestMethod {
            [pscustomobject]@{ members = @(1..100 | ForEach-Object { [pscustomobject]@{ id = "m$_" } }); continuationToken = [guid]::NewGuid().ToString() }
        }
        $r = @(& $script:M { Invoke-InforcerPagedRequest -Endpoint '/tenants/x/groups/g/members' -MaxResults 150 })
        $r.Count | Should -Be 150
        Should -Invoke -ModuleName InforcerCommunity Invoke-RestMethod -Times 2 -Exactly
    }
    It 'passes continuationToken in the POST body on v1 audit search' {
        Set-V1TestSession
        Mock -ModuleName InforcerCommunity Invoke-RestMethod {
            $b = $Body | ConvertFrom-Json
            if ($b.continuationToken -eq 'c1') { [pscustomobject]@{ auditEvents = @([pscustomobject]@{ id = 'e2' }); continuationToken = $null } }
            else { [pscustomobject]@{ auditEvents = @([pscustomobject]@{ id = 'e1' }); continuationToken = 'c1' } }
        }
        $r = @(& $script:M { Invoke-InforcerPagedRequest -Endpoint '/auditEvents/search' -Method POST -Body @{ pageSize = 1; eventTypes = @('x') } -ObjectType AuditEvent })
        $r.id | Should -Be @('e1', 'e2')
        Should -Invoke -ModuleName InforcerCommunity Invoke-RestMethod -Times 2 -Exactly -ParameterFilter { $Method -eq 'POST' -and ($Body | ConvertFrom-Json).pageSize -eq 1 }
    }
    It 'pages beta lists with the token at the response root' {
        Set-V1TestSession -Beta
        Mock -ModuleName InforcerCommunity Invoke-RestMethod {
            if ($Uri -like '*continuationToken=b2') { [pscustomobject]@{ data = @([pscustomobject]@{ id = 'u2' }); continuationToken = $null; totalCount = 2 } }
            else { [pscustomobject]@{ data = @([pscustomobject]@{ id = 'u1' }); continuationToken = 'b2'; totalCount = 2 } }
        }
        (@(& $script:M { Invoke-InforcerPagedRequest -Endpoint '/tenants/1/users' })).id | Should -Be @('u1', 'u2')
    }
    It 'pages beta audit search with items and token inside .data' {
        Set-V1TestSession -Beta
        Mock -ModuleName InforcerCommunity Invoke-RestMethod {
            $b = $Body | ConvertFrom-Json
            if ($b.continuationToken) { [pscustomobject]@{ success = $true; data = [pscustomobject]@{ items = @([pscustomobject]@{ id = 'e2' }); continuationToken = $null } } }
            else { [pscustomobject]@{ success = $true; data = [pscustomobject]@{ items = @([pscustomobject]@{ id = 'e1' }); continuationToken = 'n' } } }
        }
        (@(& $script:M { Invoke-InforcerPagedRequest -Endpoint '/auditEvents/search' -Method POST -Body @{ pageSize = 1 } })).id | Should -Be @('e1', 'e2')
    }
}

Describe 'Tenant list and Resolve-InforcerTenantId' {
    BeforeEach {
        Mock -ModuleName InforcerCommunity Invoke-RestMethod {
            [pscustomobject]@{ tenants = @(
                [pscustomobject]@{ msTenantId = '00000000-0000-0000-0000-000000000001'; name = 'Contoso'; dnsName = 'contoso.onmicrosoft.com' },
                [pscustomobject]@{ msTenantId = '00000000-0000-0000-0000-000000000002'; name = 'Fabrikam'; dnsName = 'fabrikam.onmicrosoft.com' },
                [pscustomobject]@{ msTenantId = '00000000-0000-0000-0000-000000000003'; name = 'Twin'; dnsName = 'twin1.onmicrosoft.com' },
                [pscustomobject]@{ msTenantId = '00000000-0000-0000-0000-000000000004'; name = 'Twin'; dnsName = 'twin2.onmicrosoft.com' }
            ) }
        }
    }

    It 'caches the mapped tenant list for the session' {
        Set-V1TestSession
        $a = @(& $script:M { Get-InforcerTenantList })
        $b = @(& $script:M { Get-InforcerTenantList })
        $a[0].tenantFriendlyName | Should -BeExactly 'Contoso'
        $b.Count | Should -Be 4
        Should -Invoke -ModuleName InforcerCommunity Invoke-RestMethod -Times 1 -Exactly
    }
    It 'does not cache a failed tenant list request' {
        Set-V1TestSession
        Mock -ModuleName InforcerCommunity Invoke-InforcerHttpRequest { New-V1TestResponse -Status 403 -Body '{"title":"Forbidden","status":403}' }
        $null = & $script:M { Get-InforcerTenantList -ErrorAction SilentlyContinue }
        & $script:M { $script:InforcerTenantListCache } | Should -BeNullOrEmpty
    }
    It 'does not serve the cache to a different session' {
        Set-V1TestSession
        $null = & $script:M { Get-InforcerTenantList }
        & $script:M { $script:InforcerSession = $script:InforcerSession.Clone() }
        $null = & $script:M { Get-InforcerTenantList }
        Should -Invoke -ModuleName InforcerCommunity Invoke-RestMethod -Times 2 -Exactly
    }
    It 'refuses a numeric id on v1 with TenantIdNumericNotSupportedOnV1' {
        Set-V1TestSession
        $err = $null
        try { & $script:M { Resolve-InforcerTenantId -TenantId 482 } } catch { $err = $_ }
        $err.FullyQualifiedErrorId | Should -Match '^TenantIdNumericNotSupportedOnV1'
        $err.Exception.Message | Should -Match 'API key'
        $err.Exception.Message | Should -Match 'Microsoft tenant ID'
    }
    It 'passes a GUID through on v1 without an API call' {
        Set-V1TestSession
        & $script:M { Resolve-InforcerTenantId -TenantId '00000000-0000-0000-0000-00000000000A' } | Should -BeExactly '00000000-0000-0000-0000-00000000000a'
        Should -Invoke -ModuleName InforcerCommunity Invoke-RestMethod -Times 0 -Exactly
    }
    It 'resolves a name or DNS name to msTenantId on v1' {
        Set-V1TestSession
        $r = & $script:M { Resolve-InforcerTenantId -TenantId 'contoso' }
        $r | Should -BeExactly '00000000-0000-0000-0000-000000000001'
        $r | Should -BeOfType [string]
        & $script:M { Resolve-InforcerTenantId -TenantId 'fabrikam.onmicrosoft.com' } | Should -BeExactly '00000000-0000-0000-0000-000000000002'
    }
    It 'refuses an ambiguous name and asks for the GUID on v1' {
        Set-V1TestSession
        { & $script:M { Resolve-InforcerTenantId -TenantId 'Twin' } } | Should -Throw '*2 tenants match*Microsoft tenant ID*'
    }
    It 'resolves names from raw v1 -TenantData too' {
        Set-V1TestSession
        $data = @([pscustomobject]@{ msTenantId = '00000000-0000-0000-0000-000000000009'; name = 'Raw'; dnsName = 'raw.example' })
        & $script:M { param($d) Resolve-InforcerTenantId -TenantId 'Raw' -TenantData $d } $data | Should -BeExactly '00000000-0000-0000-0000-000000000009'
    }
    It 'keeps beta numeric passthrough and name resolution to [int]' {
        Set-V1TestSession -Beta
        Mock -ModuleName InforcerCommunity Invoke-RestMethod { [pscustomobject]@{ data = @([pscustomobject]@{ clientTenantId = 7; tenantFriendlyName = 'Contoso'; msTenantId = '00000000-0000-0000-0000-000000000001' }) } }
        & $script:M { Resolve-InforcerTenantId -TenantId '42' } | Should -BeOfType [int]
        $r = & $script:M { Resolve-InforcerTenantId -TenantId 'Contoso' }
        $r | Should -Be 7
        $r | Should -BeOfType [int]
        & $script:M { Resolve-InforcerTenantId -TenantId '00000000-0000-0000-0000-000000000001' } | Should -Be 7
    }
}

Describe 'Connect-Inforcer with client credentials' {
    BeforeEach { & $script:M { $script:InforcerSession = $null; $script:InforcerReportTypeCache = $null } }
    AfterEach { & $script:M { $script:InforcerSession = $null; $script:InforcerReportTypeCache = $null; $script:InforcerReportTypeCacheStamp = $null } }

    It 'connects to v1 with a token and stores only SecureStrings' {
        Mock -ModuleName InforcerCommunity Invoke-RestMethod { [pscustomobject]@{ access_token = 'connect-token-value'; token_type = 'Bearer'; expires_in = 3600 } }
        Mock -ModuleName InforcerCommunity Invoke-WebRequest { [pscustomobject]@{ StatusCode = 403; Content = '{}'; Headers = @{} } }
        $secret = ConvertTo-SecureString 'connect-secret-value' -AsPlainText -Force
        $w = $null
        $r = Connect-Inforcer -ClientId 'client-id-example' -ClientSecret $secret -Region eu -WarningVariable w
        $r.Status | Should -Be 'Connected'
        $r.BaseUrl | Should -Be 'https://api-eu.inforcer.com'
        $w | Should -BeNullOrEmpty -Because 'the legacy warning is only for API keys'
        $s = & $script:M { $script:InforcerSession }
        $s.AuthMode | Should -Be 'ClientCredentials'
        $s.ApiVersion | Should -Be 'v1'
        $s.ApiHost | Should -Be 'https://api-eu.inforcer.com'
        $s.ContainsKey('ApiKey') | Should -BeFalse
        $s.ClientSecret | Should -BeOfType [securestring]
        $s.AccessToken | Should -BeOfType [securestring]
        $s.TokenExpiresAt.Kind | Should -Be 'Utc'
        Should -Invoke -ModuleName InforcerCommunity Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Uri -eq 'https://api-eu.inforcer.com/oauth/token' }
    }
    It 'accepts a plain-string secret and a host+/api -BaseUrl' {
        Mock -ModuleName InforcerCommunity Invoke-RestMethod { [pscustomobject]@{ access_token = 't'; expires_in = 3600 } }
        Mock -ModuleName InforcerCommunity Invoke-WebRequest { [pscustomobject]@{ StatusCode = 403; Content = '{}'; Headers = @{} } }
        $null = Connect-Inforcer -ClientId 'c' -ClientSecret 'plain-secret' -BaseUrl 'https://api.example.invalid/api'
        (& $script:M { $script:InforcerSession.ApiHost }) | Should -Be 'https://api.example.invalid'
    }
    It 'fails cleanly on a wrong secret without echoing it and without a session' {
        Mock -ModuleName InforcerCommunity Invoke-InforcerHttpRequest { New-V1TestResponse -Status 401 -Body '{"title":"Unauthorized","status":401,"detail":"Invalid client credentials"}' }
        $err = $null
        $r = Connect-Inforcer -ClientId 'c' -ClientSecret 'wrong-secret-value' -ErrorAction SilentlyContinue -ErrorVariable err
        $r | Should -BeNullOrEmpty
        $err[0].FullyQualifiedErrorId | Should -Match '^ConnectionValidationFailed'
        $err[0].Exception.Message | Should -Match 'HTTP 401'
        $err[0].Exception.Message | Should -Not -Match 'wrong-secret-value'
        & $script:M { $script:InforcerSession } | Should -BeNullOrEmpty
    }
    It '-PassThru holds no plaintext secret or token' {
        Mock -ModuleName InforcerCommunity Invoke-RestMethod { [pscustomobject]@{ access_token = 'passthru-token-value'; expires_in = 3600 } }
        Mock -ModuleName InforcerCommunity Invoke-WebRequest { [pscustomobject]@{ StatusCode = 403; Content = '{}'; Headers = @{} } }
        $out = Connect-Inforcer -ClientId 'c' -ClientSecret 'passthru-secret-value' -PassThru
        $session = $out | Where-Object { $_ -is [hashtable] }
        $session.ApiVersion | Should -Be 'v1'
        $text = ($session | ConvertTo-Json -Depth 10) + ($session | Out-String)
        $text | Should -Not -Match 'passthru-token-value|passthru-secret-value'
        [object]::ReferenceEquals($session, (& $script:M { $script:InforcerSession })) | Should -BeFalse
    }
    It 'primes the report type cache from the v1 reportTypes collection' {
        Mock -ModuleName InforcerCommunity Invoke-RestMethod { [pscustomobject]@{ access_token = 't'; expires_in = 3600 } }
        Mock -ModuleName InforcerCommunity Invoke-WebRequest {
            [pscustomobject]@{ StatusCode = 200; Headers = @{}; Content = '{"reportTypes":[{"key":"ActiveUserCount","name":"Active User Count","collatable":false,"singleTenantOnly":false,"supportedOutputFormats":["csv"],"tags":[],"requiredParameters":[]}]}' }
        }
        $null = Connect-Inforcer -ClientId 'c' -ClientSecret 's'
        $cache = & $script:M { $script:InforcerReportTypeCache }
        @($cache).Count | Should -Be 1
        $cache[0].key | Should -Be 'ActiveUserCount'
        Should -Invoke -ModuleName InforcerCommunity Invoke-WebRequest -Times 1 -Exactly -ParameterFilter { $Uri -eq 'https://api-uk.inforcer.com/v1/reports/types' -and $Headers['Authorization'] -eq 'Bearer t' }
    }
    It 'shows the legacy warning on an API-key login and builds a beta session' {
        Mock -ModuleName InforcerCommunity Invoke-WebRequest { [pscustomobject]@{ StatusCode = 200; Content = '{"success":true,"data":[]}'; Headers = @{} } }
        $w = $null
        $r = Connect-Inforcer -ApiKey 'key-value-example' -Region uk -WarningVariable w -WarningAction SilentlyContinue
        $r.BaseUrl | Should -Be 'https://api-uk.inforcer.com/api'
        ($w -join ' ') | Should -Match 'legacy'
        $s = & $script:M { $script:InforcerSession }
        $s.AuthMode | Should -Be 'ApiKey'
        $s.ApiVersion | Should -Be 'beta'
        Should -Invoke -ModuleName InforcerCommunity Invoke-WebRequest -ParameterFilter { $Uri -eq 'https://api-uk.inforcer.com/api/beta/baselines' -and $Headers['Inf-Api-Key'] -eq 'key-value-example' }
    }
}

Describe 'Test-InforcerConnection and Disconnect-Inforcer on v1' {
    It 'tests the v1 session through the transport and never writes key material to verbose' {
        Set-V1TestSession
        Mock -ModuleName InforcerCommunity Invoke-RestMethod { [pscustomobject]@{ baselines = @() } }
        $all = Test-InforcerConnection -Verbose 4>&1 6>$null
        ($all | Where-Object { $_ -is [bool] }) | Should -BeTrue
        ($all | Out-String) | Should -Not -Match 'first 8|Length|access-token-example-value|client-secret-example-value'
        Should -Invoke -ModuleName InforcerCommunity Invoke-RestMethod -Times 1 -Exactly -ParameterFilter { $Uri -eq 'https://api.example.invalid/v1/baselines' }
    }
    It 'disconnects a v1 session' {
        Set-V1TestSession
        Disconnect-Inforcer | Should -Be 'Disconnected from Inforcer API.'
        & $script:M { $script:InforcerSession } | Should -BeNullOrEmpty
    }
}
