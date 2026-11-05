<#
.SYNOPSIS
    Retrieves alignment scores or alignment details from the Inforcer API.

    Required API scope(s): Baselines.Read + AlignmentScores.Read + Tenants.Read + tenants.policies.Read
    (API key); Baselines + Align + Tenants permission (API client, unconfirmed).
.DESCRIPTION
    Without -BaselineId: retrieves alignment score summaries (table or raw).
    With -BaselineId: retrieves detailed alignment data including metrics,
    per-policy matches, deviations, diffs, variables, and tags.
    When -TenantId is also specified, queries a single tenant.
    When only -BaselineId is specified, queries the first member tenant (baseline policies are identical across members).
    -BaselineId accepts a GUID or a friendly baseline name (resolved via the baselines API).
    With -BaselineId the metrics summary is written to the host, not the pipeline; the pipeline gets
    one object per policy (use -Format Raw for the metrics as an object).

    API-key login: table rows identify the tenant by TargetTenantClientTenantId.
    Client-credentials login: numeric tenant ids do not exist; table rows carry TargetTenantMsTenantId
    instead.

    Piped tenants (Get-InforcerTenant | Get-InforcerAlignmentDetails): scores, baselines and tenant
    records are fetched once for the whole pipeline, each row carries TenantId, no row repeats, and
    -OutputType JsonObject returns one JSON array. With client credentials the table is always a
    JSON array, also for one row.
.PARAMETER Format
    Table (default) or Raw.
.PARAMETER TenantId
    Optional. Filter to this tenant. When used with -BaselineId, queries only this tenant.
    Accepts the Microsoft Tenant ID (GUID), the tenant name, or (API-key login only) the numeric
    Client Tenant ID.
.PARAMETER BaselineId
    Optional. Baseline GUID or friendly name. When provided, retrieves detailed alignment
    data. Without -TenantId, queries the first member tenant of the baseline.
.PARAMETER Tag
    Optional. When Format is Table (without -BaselineId), filter to tenants with tag containing this value (case-insensitive). No match returns no rows and a warning.
.PARAMETER OutputType
    PowerShellObject (default) or JsonObject. JSON uses Depth 100.
.EXAMPLE
    Get-InforcerAlignmentDetails
.EXAMPLE
    Get-InforcerAlignmentDetails -Format Raw -OutputType JsonObject
.EXAMPLE
    Get-InforcerAlignmentDetails -TenantId 'Contoso' -Tag Production
.EXAMPLE
    Get-InforcerAlignmentDetails -TenantId 'Contoso' -BaselineId "Provision M365"
    Retrieves detailed alignment data using the tenant name and the baseline friendly name (both logins).
.EXAMPLE
    Get-InforcerAlignmentDetails -TenantId '00000000-0000-0000-0000-000000000001' -BaselineId "00000000-0000-0000-0000-000000000004" -Format Raw
    Retrieves the raw alignment detail response by Microsoft Tenant ID and baseline GUID.
.EXAMPLE
    Get-InforcerAlignmentDetails -BaselineId "Inforcer Blueprint Baseline - Tier 2 - Enhanced"
    Retrieves alignment details for the first member tenant of the baseline.
.OUTPUTS
    PSObject or String
.LINK
    https://github.com/royklo/InforcerCommunity/blob/main/docs/CMDLET-REFERENCE.md#get-inforceralignmentdetails
.LINK
    Connect-Inforcer
#>
function Get-InforcerAlignmentDetails {
[CmdletBinding()]
[OutputType([PSObject], [string])]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Table', 'Raw')]
    [string]$Format = 'Table',

    [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
    [Alias('ClientTenantId', 'MsTenantId')]
    [object]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$BaselineId,

    [Parameter(Mandatory = $false)]
    [string]$Tag,

    [Parameter(Mandatory = $false)]
    [ValidateSet('PowerShellObject', 'JsonObject')]
    [string]$OutputType = 'PowerShellObject'
)

begin { $requestedTenantIds = [System.Collections.Generic.List[object]]::new() }
process { $requestedTenantIds.Add($TenantId) }
end {
$piped = $PSCmdlet.MyInvocation.ExpectingInput
if ($piped -and $requestedTenantIds.Count -eq 0) { return }
$requested = $requestedTenantIds.ToArray()

if (-not (Test-InforcerSession)) {
    Write-Error -Message 'Not connected yet. Please run Connect-Inforcer first.' -ErrorId 'NotConnected' -Category ConnectionError
    return
}

$isV1 = $script:InforcerSession.ApiVersion -eq 'v1'

# The id the current API keys tenants by: beta [int] clientTenantId, v1 [string] msTenantId.
function Get-TenantKey($Object) {
    $name = if ($isV1) { 'msTenantId' } else { 'clientTenantId' }
    $value = $Object.PSObject.Properties[$name].Value
    if ($null -eq $value) { return $null }
    if ($isV1) { return "$value" }
    $n = 0
    if ([int]::TryParse($value.ToString(), [ref]$n)) { return $n }
    $null
}

function Add-PipedTenantId($Object, $Id) {
    if ($piped -and $null -ne $Id -and $Object -is [PSObject] -and -not $Object.PSObject.Properties['TenantId']) {
        $Object.PSObject.Properties.Add([System.Management.Automation.PSNoteProperty]::new('TenantId', $Id))
    }
}

# Fetched at most once per call, whatever the number of piped tenants.
$allBaselines = $null

# --- Alignment Details mode: -BaselineId provided ---
if (-not [string]::IsNullOrWhiteSpace($BaselineId)) {

    try {
        $guidTest = [guid]::Empty
        if (-not [guid]::TryParse($BaselineId.Trim(), [ref]$guidTest)) {
            $allBaselines = @(Get-InforcerBaselineList -Refresh)
            $baselineGuid = Resolve-InforcerBaselineId -BaselineId $BaselineId -BaselineData $allBaselines
        } else {
            $baselineGuid = $BaselineId.Trim()
        }
    } catch {
        Write-Error -Message $_.Exception.Message -ErrorId 'InvalidBaselineId' -Category InvalidArgument
        return
    }

    # Build list of tenants to query
    $tenantsToQuery = [System.Collections.Generic.List[object]]::new()
    $queuedIds = @{}

    foreach ($requestedTenantId in $requested) {
        if ($null -ne $requestedTenantId) {
            # Single tenant mode — resolve ID and friendly name
            try {
                $resolvedTenantId = Resolve-InforcerTenantId -TenantId $requestedTenantId -ErrorAction Stop
            } catch {
                Write-Error -Message $_.Exception.Message -ErrorId 'InvalidTenantId' -Category InvalidArgument
                if ($piped) { continue }
                return
            }
            if ($queuedIds.ContainsKey($resolvedTenantId)) { continue }
            $tenantFriendlyName = "Tenant $resolvedTenantId"
            foreach ($t in @(Get-InforcerTenantList)) {
                if ($t -is [PSObject] -and (Get-TenantKey $t) -eq $resolvedTenantId) {
                    $fnProp = $t.PSObject.Properties['tenantFriendlyName']
                    if ($fnProp -and $fnProp.Value) { $tenantFriendlyName = $fnProp.Value.ToString() }
                    break
                }
            }
            $queuedIds[$resolvedTenantId] = $true
            [void]$tenantsToQuery.Add(@{ Id = $resolvedTenantId; Name = $tenantFriendlyName })
        } else {
            # All members mode — find baseline members
            if ($null -eq $allBaselines) { $allBaselines = @(Get-InforcerBaselineList -Refresh) }
            $baselineObj = $null
            foreach ($bl in $allBaselines) {
                if (-not ($bl -is [PSObject])) { continue }
                $idProp = $bl.PSObject.Properties['id']
                if ($idProp -and $null -ne $idProp.Value -and $idProp.Value.ToString() -eq $baselineGuid) {
                    $baselineObj = $bl
                    break
                }
            }
            if ($null -eq $baselineObj) {
                Write-Error -Message "Baseline not found: $baselineGuid" -ErrorId 'BaselineNotFound' -Category ObjectNotFound
                return
            }
            $membersProp = $baselineObj.PSObject.Properties['members']
            if (-not $membersProp -or $null -eq $membersProp.Value -or @($membersProp.Value).Count -eq 0) {
                Write-Warning 'No member tenants found for this baseline.'
                return
            }
            # Pick first member only — baseline policies are the same regardless of member
            $memberEntry = $null
            foreach ($member in @($membersProp.Value)) {
                if (-not ($member -is [PSObject])) { continue }
                $mId = Get-TenantKey $member
                if ($null -eq $mId) { continue }
                $mNameProp = $member.PSObject.Properties['tenantFriendlyName']
                $mName = if ($mNameProp -and $null -ne $mNameProp.Value) { $mNameProp.Value.ToString() } else { "Tenant $mId" }
                $memberEntry = @{ Id = $mId; Name = $mName }
                break
            }
            if ($null -eq $memberEntry) {
                Write-Warning 'No member tenants found for this baseline.'
                return
            }
            Write-Verbose "Using member tenant $($memberEntry.Name) ($($memberEntry.Id)) to retrieve baseline policies."
            if ($queuedIds.ContainsKey($memberEntry.Id)) { continue }
            $queuedIds[$memberEntry.Id] = $true
            [void]$tenantsToQuery.Add($memberEntry)
        }
    }

    # Status map for policy arrays
    $arrayStatusMap = @{
        'matchedPolicies'                = 'Aligned'
        'matchedWithAcceptedDeviations'  = 'Accepted Deviation'
        'deviatedUnaccepted'             = 'Unaccepted Deviation'
        'missingFromSubjectUnaccepted'   = 'Recommended From Baseline'
        'additionalInSubjectUnaccepted'  = 'Existing Customer Policy'
    }

    # Piped JSON: one array for all tenants, built from the objects.
    $pipedJson = $piped -and $OutputType -eq 'JsonObject'
    $requestOutputType = if ($pipedJson) { 'PowerShellObject' } else { $OutputType }
    $jsonItems = [System.Collections.Generic.List[object]]::new()

    # Query each tenant
    foreach ($tenantEntry in $tenantsToQuery) {
        $tId = $tenantEntry.Id
        $tName = $tenantEntry.Name

        Write-Verbose "Retrieving alignment details for tenant $tId ($tName), baseline $baselineGuid..."
        $detailEndpoint = "/tenants/$tId/alignmentDetails?customBaselineId=$baselineGuid"
        $response = Invoke-InforcerApiRequest -Endpoint $detailEndpoint -Method GET -OutputType $requestOutputType -PreserveStructure:$pipedJson -ObjectType AlignmentDetails -ErrorAction SilentlyContinue -ErrorVariable apiErr
        if ($null -eq $response) {
            $errMsg = if ($apiErr -and $apiErr.Count -gt 0) { $apiErr[-1].Exception.Message } else { $null }
            if ($errMsg -match 'permission|forbidden|access') {
                Write-Warning "No access to alignment details for tenant '$tName' ($tId). You may not have permission to view this baseline's data."
            } else {
                Write-Warning "No alignment data returned for tenant '$tName' ($tId)."
            }
            continue
        }

        if ($pipedJson) {
            Add-PipedTenantId $response $tId
            $jsonItems.Add($response)
            continue
        }

        if ($OutputType -eq 'JsonObject') {
            $response
            continue
        }

        if ($Format -eq 'Raw') {
            if ($response -is [PSObject]) {
                $null = Add-InforcerPropertyAliases -InputObject $response -ObjectType AlignmentDetail
            }
            Add-PipedTenantId $response $tId
            $response
            continue
        }

        # Format Table: flatten into metrics summary + per-policy rows
        $alignment = $null
        $metrics = $null
        $completedAt = $null

        if ($response -is [PSObject]) {
            $alignmentProp = $response.PSObject.Properties['alignment']
            if ($alignmentProp -and $null -ne $alignmentProp.Value) { $alignment = $alignmentProp.Value }
            $metricsProp = $response.PSObject.Properties['metrics']
            if ($metricsProp -and $null -ne $metricsProp.Value) { $metrics = $metricsProp.Value }
            $completedAtProp = $response.PSObject.Properties['completedAt']
            if ($completedAtProp -and $null -ne $completedAtProp.Value) { $completedAt = $completedAtProp.Value }
        }

        if ($null -eq $alignment) {
            Write-Warning "No alignment data returned for tenant $tName ($tId)."
            continue
        }

        $alignmentScoreVal = $alignment.PSObject.Properties['alignmentScore'].Value
        $alignmentScoreFormatted = if ($null -ne $alignmentScoreVal) {
            [Math]::Round([double]$alignmentScoreVal, 2)
        } else { $null }
        $totalPolicies            = if ($metrics) { $metrics.PSObject.Properties['totalPolicies'].Value } else { $null }
        $alignedCount             = if ($metrics) { $metrics.PSObject.Properties['matchedPolicies'].Value } else { $null }
        $acceptedDeviationCount   = if ($metrics) { $metrics.PSObject.Properties['matchedWithAcceptedDeviations'].Value } else { $null }
        $unacceptedDeviationCount = if ($metrics) { $metrics.PSObject.Properties['deviatedPolicies'].Value } else { $null }
        $recommendedCount         = if ($metrics) { $metrics.PSObject.Properties['recommendedPoliciesFromBaseline'].Value } else { $null }
        $existingCustomerCount    = if ($metrics) { $metrics.PSObject.Properties['customerOnlyPolicies'].Value } else { $null }

        # Display metrics summary via host (not pipeline) so it doesn't break | Format-Table
        Write-Host ""
        Write-Host "  Tenant: $tName ($tId)" -ForegroundColor Cyan
        Write-Host "  Alignment Score: $alignmentScoreFormatted | Total: $totalPolicies | Aligned: $alignedCount | Accepted Deviation: $acceptedDeviationCount | Unaccepted Deviation: $unacceptedDeviationCount | Recommended: $recommendedCount | Customer Only: $existingCustomerCount"
        Write-Host "  Completed: $completedAt"
        Write-Host ""

        # Per-policy rows
        foreach ($arrayName in $arrayStatusMap.Keys) {
            $policyArrayProp = $alignment.PSObject.Properties[$arrayName]
            if (-not $policyArrayProp -or $null -eq $policyArrayProp.Value) { continue }
            $status = $arrayStatusMap[$arrayName]
            foreach ($policy in @($policyArrayProp.Value)) {
                if (-not ($policy -is [PSObject])) { continue }
                $tagNames = [System.Collections.Generic.List[string]]::new()
                $policyTagsProp = $policy.PSObject.Properties['policyTags']
                if ($policyTagsProp -and $null -ne $policyTagsProp.Value) {
                    foreach ($t in @($policyTagsProp.Value)) {
                        if ($t -is [PSObject] -and $t.PSObject.Properties['name']) {
                            [void]$tagNames.Add($t.PSObject.Properties['name'].Value)
                        }
                    }
                }

                $row = [PSCustomObject]@{
                    PolicyName             = $policy.PSObject.Properties['policyName'].Value
                    AlignmentStatus        = $status
                    Product                = $policy.PSObject.Properties['product'].Value
                    PrimaryGroup           = $policy.PSObject.Properties['primaryGroup'].Value
                    SecondaryGroup         = $policy.PSObject.Properties['secondaryGroup'].Value
                    InforcerPolicyTypeName = $policy.PSObject.Properties['inforcerPolicyTypeName'].Value
                    Tags                   = ($tagNames -join ', ')
                }
                Add-PipedTenantId $row $tId
                $row.PSObject.TypeNames.Insert(0, 'InforcerCommunity.AlignmentDetailPolicy')
                $row
            }
        }
    }
    if ($pipedJson) { ConvertTo-Json -InputObject @($jsonItems) -Depth 100 }
    return
}

function FormatAlignmentScore($scoreVal) {
    if ($null -eq $scoreVal) { return $null }
    $scoreStr = $scoreVal.ToString().Replace(',', '.')
    $scoreNumeric = 0.0
    if (-not [double]::TryParse($scoreStr, [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$scoreNumeric)) { return $null }
    $rounded = [Math]::Round($scoreNumeric, 1)
    if ($rounded -eq [Math]::Floor($rounded)) { return [int][Math]::Floor($rounded).ToString() }
    return $rounded.ToString('F1', [System.Globalization.CultureInfo]::InvariantCulture).Replace('.', ',')
}

if ($Format -eq 'Raw') {
    Write-Verbose 'Retrieving alignment scores (raw)...'
    $requestOutputType = if ($piped) { 'PowerShellObject' } else { $OutputType }
    $response = Invoke-InforcerApiRequest -Endpoint '/alignmentScores' -Method GET -OutputType $requestOutputType -ObjectType AlignmentScore
    if ($null -eq $response) { return }

    $predicateFor = {
        param($resolvedTenantId)
        if ($isV1) {
            { param($p) "$($p.PSObject.Properties['msTenantId'].Value)" -eq $resolvedTenantId }.GetNewClosure()
        } else {
            {
                param($p)
                $tidProp = $p.PSObject.Properties['tenantId']
                if (-not $tidProp) { $tidProp = $p.PSObject.Properties['clientTenantId'] }
                if ($tidProp -and [int]$tidProp.Value -eq $resolvedTenantId) { return $true }
                $summariesProp = $p.PSObject.Properties['alignmentSummaries']
                if ($summariesProp -and $summariesProp.Value -is [object[]]) {
                    foreach ($s in $summariesProp.Value) {
                        if ($s -is [PSObject]) {
                            $aidProp = $s.PSObject.Properties['alignedBaselineTenantId']
                            if ($aidProp -and [int]$aidProp.Value -eq $resolvedTenantId) { return $true }
                        }
                    }
                }
                $false
            }.GetNewClosure()
        }
    }

    if ($piped) {
        # One row per score item, deduped across piped tenants; TenantId is the item's own tenant.
        $items = @(ConvertTo-InforcerArray $response)
        $keep = [bool[]]::new($items.Count)
        foreach ($requestedTenantId in $requested) {
            if ($null -eq $requestedTenantId) { for ($i = 0; $i -lt $items.Count; $i++) { $keep[$i] = $true }; continue }
            try {
                $resolvedTenantId = Resolve-InforcerTenantId -TenantId $requestedTenantId -ErrorAction Stop
            } catch {
                Write-Error -Message $_.Exception.Message -ErrorId 'InvalidTenantId' -Category InvalidArgument
                continue
            }
            $predicate = & $predicateFor $resolvedTenantId
            for ($i = 0; $i -lt $items.Count; $i++) {
                if (-not $keep[$i] -and $items[$i] -is [PSObject] -and (& $predicate $items[$i])) { $keep[$i] = $true }
            }
        }
        $selected = @(for ($i = 0; $i -lt $items.Count; $i++) { if ($keep[$i]) { $items[$i] } })
        foreach ($item in $selected) { if ($item -is [PSObject]) { Add-PipedTenantId $item (Get-TenantKey $item) } }
        if ($OutputType -eq 'JsonObject') { return ConvertTo-Json -InputObject @($selected) -Depth 100 }
        foreach ($item in $selected) {
            if ($item -is [PSObject]) {
                $null = Add-InforcerPropertyAliases -InputObject $item -ObjectType AlignmentScore
                $item.PSObject.TypeNames.Insert(0, 'InforcerCommunity.AlignmentScoreRaw')
            }
            $item
        }
        return
    }

    if ($null -ne $TenantId) {
        try {
            $resolvedTenantId = Resolve-InforcerTenantId -TenantId $TenantId -ErrorAction Stop
        } catch {
            Write-Error -Message $_.Exception.Message -ErrorId 'InvalidTenantId' -Category InvalidArgument
            return
        }
        Write-Verbose "Filtering alignment scores to tenant ID $resolvedTenantId..."
        $predicate = & $predicateFor $resolvedTenantId
        if ($OutputType -eq 'JsonObject') {
            Filter-InforcerResponse -InputObject $response -FilterScript $predicate -OutputType JsonObject
        } else {
            $filtered = Filter-InforcerResponse -InputObject $response -FilterScript $predicate -OutputType PowerShellObject
            foreach ($item in (ConvertTo-InforcerArray $filtered)) {
                if ($item -is [PSObject]) {
                    $null = Add-InforcerPropertyAliases -InputObject $item -ObjectType AlignmentScore
                    $item.PSObject.TypeNames.Insert(0, 'InforcerCommunity.AlignmentScoreRaw')
                }
            }
            $filtered
        }
        return
    }

    if ($OutputType -eq 'JsonObject') {
        return $response
    }
    foreach ($item in (ConvertTo-InforcerArray $response)) {
        if ($item -is [PSObject]) {
            $null = Add-InforcerPropertyAliases -InputObject $item -ObjectType AlignmentScore
            $item.PSObject.TypeNames.Insert(0, 'InforcerCommunity.AlignmentScoreRaw')
        }
    }
    $response
    return
}

# Format Table: alignment scores, joined with the tenant list only when filtering needs it
Write-Verbose 'Retrieving alignment scores for table...'
$alignmentResponse = Invoke-InforcerApiRequest -Endpoint '/alignmentScores' -Method GET -OutputType PowerShellObject -ObjectType AlignmentScore
if ($null -eq $alignmentResponse) { return }

$allAlignmentData = ConvertTo-InforcerArray $alignmentResponse
$scoreTenantProperty = if ($isV1) { 'msTenantId' } else { 'tenantId' }
$firstItem = $null
if ($allAlignmentData.Count -gt 0) { $firstItem = $allAlignmentData[0] }
$flatFormat = ($firstItem -is [PSObject]) -and $firstItem.PSObject.Properties[$scoreTenantProperty] -and $firstItem.PSObject.Properties['score'] -and -not $firstItem.PSObject.Properties['alignmentSummaries']

$anyTenantRequested = @($requested | Where-Object { $null -ne $_ }).Count -gt 0
$needTenants = (-not $flatFormat) -or $anyTenantRequested -or -not [string]::IsNullOrWhiteSpace($Tag)

# Tenant objects come from the shared tenant cache: read them, never modify them.
$allTenants = @()
if ($needTenants) {
    Write-Verbose 'Retrieving tenant information for alignment table...'
    $allTenants = @(Get-InforcerTenantList)
    if ($allTenants.Count -eq 0) { return }
}

# Add to $targetIds every tenant aligned to a baseline owned by an id in $baselineOwnerIds,
# read from the tenant list's alignmentSummaries (beta alignedBaselineTenantId, v1 alignedBaselineMsTenantId).
function Add-ChildTenantIdsFromAlignments {
    param([System.Collections.Hashtable]$targetIds, [array]$allTenants, [array]$baselineOwnerIds)
    $ownerName = if ($isV1) { 'alignedBaselineMsTenantId' } else { 'alignedBaselineTenantId' }
    foreach ($t in $allTenants) {
        if (-not ($t -is [PSObject])) { continue }
        $sumProp = $t.PSObject.Properties['alignmentSummaries']
        if (-not $sumProp -or $null -eq $sumProp.Value) { continue }
        foreach ($s in @($sumProp.Value)) {
            if (-not ($s -is [PSObject])) { continue }
            $ownerProp = $s.PSObject.Properties[$ownerName]
            if (-not $ownerProp -or $null -eq $ownerProp.Value) { continue }
            $owner = $ownerProp.Value.ToString()
            if (-not $isV1) {
                $n = 0
                if (-not [int]::TryParse($owner, [ref]$n)) { continue }
                $owner = $n
            }
            if ($baselineOwnerIds -notcontains $owner) { continue }
            $childId = Get-TenantKey $t
            if ($null -ne $childId) { $targetIds[$childId] = $true }
        }
    }
}

# True when one of the tenant's tags contains $Tag (v1 tags are {name, description}; beta tags are strings).
function Test-TenantTag($Tenant) {
    $tagsProp = $Tenant.PSObject.Properties['tags']
    if (-not $tagsProp -or $null -eq $tagsProp.Value) { return $false }
    foreach ($x in @($tagsProp.Value)) {
        $text = if ($x -is [PSObject] -and $x.PSObject.Properties['name']) { $x.PSObject.Properties['name'].Value } else { $x }
        if ($text -and $text.ToString().IndexOf($Tag, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
    }
    $false
}

# Only filter by tenant when a tenant or -Tag was given; otherwise show all alignment rows.
# Piped tenants: the union of what each tenant alone would select, built once.
$tenantIds = @{}
# A requested tenant or -Tag that matches nothing must return nothing, not every row.
$filterTenants = $anyTenantRequested -or -not [string]::IsNullOrWhiteSpace($Tag)
foreach ($requestedTenantId in $requested) {
    $tenants = @($allTenants | Where-Object { $_ -is [PSObject] })

    if ($null -ne $requestedTenantId) {
        try {
            $resolvedTenantId = Resolve-InforcerTenantId -TenantId $requestedTenantId -TenantData $allTenants -ErrorAction Stop
        } catch {
            Write-Error -Message $_.Exception.Message -ErrorId 'InvalidTenantId' -Category InvalidArgument
            if ($piped) { continue }
            return
        }
        Write-Verbose "Filtering to tenant ID: $resolvedTenantId"
        $tenants = @($tenants | Where-Object { (Get-TenantKey $_) -eq $resolvedTenantId })
        if ($tenants.Count -eq 0) {
            Write-Verbose "No tenant found with ID $resolvedTenantId. Returning no results."
            if ($piped) { continue }
            return
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Tag)) {
        Write-Verbose "Filtering to tenants with tag containing: $Tag"
        $tenants = @($tenants | Where-Object { Test-TenantTag $_ })
    }

    if ($null -eq $requestedTenantId -and [string]::IsNullOrWhiteSpace($Tag)) { continue }
    $selectedIds = @{}
    foreach ($t in $tenants) {
        $tid = Get-TenantKey $t
        if ($null -ne $tid) { $selectedIds[$tid] = $true }
    }
    # If the requested tenant is a baseline owner, also include tenants aligned TO it
    if ($null -ne $requestedTenantId -and $selectedIds.Count -gt 0) {
        Add-ChildTenantIdsFromAlignments -targetIds $selectedIds -allTenants $allTenants -baselineOwnerIds @($selectedIds.Keys)
    }
    foreach ($id in $selectedIds.Keys) { $tenantIds[$id] = $true }
}

if (-not [string]::IsNullOrWhiteSpace($Tag) -and -not @($allTenants | Where-Object { $_ -is [PSObject] -and (Test-TenantTag $_) }).Count) {
    Write-Warning "No tenant has a tag matching '$Tag'."
}

Write-Verbose "Building alignment table from alignment scores ($($allAlignmentData.Count) source(s))..."

# API can return flat array (tenantId, score, baselineGroupName...) or nested (clientTenantId, alignmentSummaries)
$alignmentTable = [System.Collections.ArrayList]::new()

if ($flatFormat) {
    foreach ($item in $allAlignmentData) {
        if (-not ($item -is [PSObject])) { continue }
        $scoreVal = $item.PSObject.Properties['score'].Value
        $alignmentScoreFormatted = FormatAlignmentScore $scoreVal

        if ($isV1) {
            $targetTenantMsTenantId = Get-TenantKey $item
            if ($filterTenants -and ($null -eq $targetTenantMsTenantId -or -not $tenantIds.ContainsKey($targetTenantMsTenantId))) { continue }
            $row = [PSCustomObject]@{
                TargetTenantFriendlyName    = ($item.PSObject.Properties['tenantFriendlyName'].Value -as [string])
                TargetTenantMsTenantId      = $targetTenantMsTenantId
                AlignmentScore              = $alignmentScoreFormatted
                BaselineName                = $item.PSObject.Properties['baselineGroupName'].Value
                BaselineId                  = $item.PSObject.Properties['baselineGroupId'].Value
                LastComparisonDateTime      = $item.PSObject.Properties['lastComparisonDateTime'].Value
            }
            Add-PipedTenantId $row $targetTenantMsTenantId
        } else {
            $tidProp = $item.PSObject.Properties['tenantId']
            if (-not $tidProp) { $tidProp = $item.PSObject.Properties['clientTenantId'] }
            $targetTenantClientTenantId = 0
            if ($tidProp -and $null -ne $tidProp.Value) {
                if (-not [int]::TryParse($tidProp.Value.ToString(), [ref]$targetTenantClientTenantId)) { continue }
            }
            if ($filterTenants -and -not $tenantIds.ContainsKey($targetTenantClientTenantId)) { continue }
            $row = [PSCustomObject]@{
                TargetTenantFriendlyName    = ($item.PSObject.Properties['tenantFriendlyName'].Value -as [string])
                TargetTenantClientTenantId  = $targetTenantClientTenantId
                AlignmentScore              = $alignmentScoreFormatted
                BaselineName                = $item.PSObject.Properties['baselineGroupName'].Value
                BaselineId                  = $item.PSObject.Properties['baselineGroupId'].Value
                LastComparisonDateTime      = $item.PSObject.Properties['lastComparisonDateTime'].Value
            }
            Add-PipedTenantId $row $targetTenantClientTenantId
        }
        $row.PSObject.TypeNames.Insert(0, 'InforcerCommunity.AlignmentScore')
        [void]$alignmentTable.Add($row)
    }
} elseif (-not $isV1) {
    foreach ($tenant in $allAlignmentData) {
        if (-not ($tenant -is [PSObject])) { continue }
        $cidProp = $tenant.PSObject.Properties['clientTenantId']
        $targetTenantClientTenantId = 0
        if ($null -ne $cidProp -and $null -ne $cidProp.Value) {
            if (-not [int]::TryParse($cidProp.Value.ToString(), [ref]$targetTenantClientTenantId)) { continue }
        }
        if ($filterTenants -and -not $tenantIds.ContainsKey($targetTenantClientTenantId)) { continue }

        $summariesProp = $tenant.PSObject.Properties['alignmentSummaries']
        if (-not $summariesProp -or $null -eq $summariesProp.Value) { continue }
        $summaries = ConvertTo-InforcerArray $summariesProp.Value
        if ($summaries.Count -eq 0) { continue }

        $targetTenantFriendlyName = $tenant.PSObject.Properties['tenantFriendlyName'].Value -as [string]
        if (-not $targetTenantFriendlyName) { $targetTenantFriendlyName = '' }

        foreach ($alignment in $summaries) {
            if (-not ($alignment -is [PSObject])) { continue }

            $scoreProp = $alignment.PSObject.Properties['alignmentScore']
            $alignmentScoreFormatted = FormatAlignmentScore $(if ($scoreProp -and $null -ne $scoreProp.Value) { $scoreProp.Value } else { $null })

            $row = [PSCustomObject]@{
                TargetTenantFriendlyName    = $targetTenantFriendlyName
                TargetTenantClientTenantId  = $targetTenantClientTenantId
                AlignmentScore              = $alignmentScoreFormatted
                BaselineName                = $alignment.PSObject.Properties['alignedBaselineName'].Value
                BaselineId                  = $alignment.PSObject.Properties['alignedBaselineId'].Value
                LastComparisonDateTime      = $alignment.PSObject.Properties['lastComparisonDateTime'].Value
                AlignedThreshold            = $alignment.PSObject.Properties['alignedThreshold'].Value
                SemiAlignedThreshold        = $alignment.PSObject.Properties['semiAlignedThreshold'].Value
            }
            Add-PipedTenantId $row $targetTenantClientTenantId
            $row.PSObject.TypeNames.Insert(0, 'InforcerCommunity.AlignmentScore')
            [void]$alignmentTable.Add($row)
        }
    }
}

Write-Verbose "Generated alignment table with $($alignmentTable.Count) row(s)."
if ($OutputType -eq 'JsonObject') {
    if ($isV1 -or $piped) { return ConvertTo-Json -InputObject @($alignmentTable) -Depth 100 }
    $json = $alignmentTable | ConvertTo-Json -Depth 100
    Write-Output $json
    return
}
$alignmentTable
}
}
