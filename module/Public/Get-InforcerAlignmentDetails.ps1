<#
.SYNOPSIS
    Retrieves alignment scores or alignment details from the Inforcer API.
.DESCRIPTION
    Without -BaselineId: retrieves alignment score summaries (table or raw).
    With -BaselineId: retrieves detailed alignment data including metrics,
    per-policy matches, deviations, diffs, variables, and tags.
    When -TenantId is also specified, queries a single tenant.
    When only -BaselineId is specified, queries all member tenants of that baseline.
    -BaselineId accepts a GUID or a friendly baseline name (resolved via the baselines API).
.PARAMETER Format
    Table (default) or Raw.
.PARAMETER TenantId
    Optional. Filter to this tenant. When used with -BaselineId, queries only this tenant.
.PARAMETER BaselineId
    Optional. Baseline GUID or friendly name. When provided, retrieves detailed alignment
    data. Without -TenantId, loops through all member tenants of the baseline.
.PARAMETER Tag
    Optional. When Format is Table (without -BaselineId), filter to tenants with tag containing this value (case-insensitive).
.PARAMETER OutputType
    PowerShellObject (default) or JsonObject. JSON uses Depth 100.
.EXAMPLE
    Get-InforcerAlignmentDetails
.EXAMPLE
    Get-InforcerAlignmentDetails -Format Raw -OutputType JsonObject
.EXAMPLE
    Get-InforcerAlignmentDetails -TenantId 482 -Tag Production
.EXAMPLE
    Get-InforcerAlignmentDetails -TenantId 139 -BaselineId "Provision M365"
    Retrieves detailed alignment data using the baseline friendly name.
.EXAMPLE
    Get-InforcerAlignmentDetails -TenantId 139 -BaselineId "91e0b0f7-69f1-453f-8d73-5a6f726b5b21" -Format Raw
    Retrieves raw alignment detail response by baseline GUID.
.EXAMPLE
    Get-InforcerAlignmentDetails -BaselineId "Inforcer Blueprint Baseline - Tier 2 - Enhanced"
    Retrieves alignment details for all member tenants of the baseline.
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
    [Alias('ClientTenantId')]
    [object]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$BaselineId,

    [Parameter(Mandatory = $false)]
    [string]$Tag,

    [Parameter(Mandatory = $false)]
    [ValidateSet('PowerShellObject', 'JsonObject')]
    [string]$OutputType = 'PowerShellObject'
)

if (-not (Test-InforcerSession)) {
    Write-Error -Message 'Not connected yet. Please run Connect-Inforcer first.' -ErrorId 'NotConnected' -Category ConnectionError
    return
}

# --- Alignment Details mode: -BaselineId provided ---
if (-not [string]::IsNullOrWhiteSpace($BaselineId)) {

    # Resolve baseline (fetch baselines once — reused for member lookup when no TenantId)
    $allBaselines = $null
    try {
        $guidTest = [guid]::Empty
        if (-not [guid]::TryParse($BaselineId.Trim(), [ref]$guidTest)) {
            # Name lookup — fetch baselines so we can reuse them for members
            $allBaselines = @(Invoke-InforcerApiRequest -Endpoint '/beta/baselines' -Method GET -OutputType PowerShellObject)
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

    if ($null -ne $TenantId) {
        # Single tenant mode — resolve ID and friendly name
        try {
            $clientTenantId = Resolve-InforcerTenantId -TenantId $TenantId
        } catch {
            Write-Error -Message $_.Exception.Message -ErrorId 'InvalidTenantId' -Category InvalidArgument
            return
        }
        $tenantFriendlyName = "Tenant $clientTenantId"
        $tenantsForName = @(Invoke-InforcerApiRequest -Endpoint '/beta/tenants' -Method GET -OutputType PowerShellObject)
        foreach ($t in $tenantsForName) {
            if ($t -is [PSObject]) {
                $cidProp = $t.PSObject.Properties['clientTenantId']
                if ($cidProp -and [int]$cidProp.Value -eq $clientTenantId) {
                    $fnProp = $t.PSObject.Properties['tenantFriendlyName']
                    if ($fnProp -and $fnProp.Value) { $tenantFriendlyName = $fnProp.Value.ToString() }
                    break
                }
            }
        }
        [void]$tenantsToQuery.Add(@{ Id = $clientTenantId; Name = $tenantFriendlyName })
    } else {
        # All members mode — find baseline members
        if ($null -eq $allBaselines) {
            $allBaselines = @(Invoke-InforcerApiRequest -Endpoint '/beta/baselines' -Method GET -OutputType PowerShellObject)
        }
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
        foreach ($member in @($membersProp.Value)) {
            if (-not ($member -is [PSObject])) { continue }
            $mIdProp = $member.PSObject.Properties['clientTenantId']
            if (-not $mIdProp -or $null -eq $mIdProp.Value) { continue }
            $mId = [int]$mIdProp.Value
            $mNameProp = $member.PSObject.Properties['tenantFriendlyName']
            $mName = if ($mNameProp -and $null -ne $mNameProp.Value) { $mNameProp.Value.ToString() } else { "Tenant $mId" }
            [void]$tenantsToQuery.Add(@{ Id = $mId; Name = $mName })
            break
        }
        if ($tenantsToQuery.Count -eq 0) {
            Write-Warning 'No member tenants found for this baseline.'
            return
        }
        Write-Verbose "Using member tenant $($tenantsToQuery[0].Name) ($($tenantsToQuery[0].Id)) to retrieve baseline policies."
    }

    # Status map for policy arrays
    $arrayStatusMap = @{
        'matchedPolicies'                = 'Aligned'
        'matchedWithAcceptedDeviations'  = 'Accepted Deviation'
        'deviatedUnaccepted'             = 'Unaccepted Deviation'
        'missingFromSubjectUnaccepted'   = 'Recommended From Baseline'
        'additionalInSubjectUnaccepted'  = 'Existing Customer Policy'
    }

    # Query each tenant
    foreach ($tenantEntry in $tenantsToQuery) {
        $tId = $tenantEntry.Id
        $tName = $tenantEntry.Name

        Write-Verbose "Retrieving alignment details for tenant $tId ($tName), baseline $baselineGuid..."
        $detailEndpoint = "/beta/tenants/$tId/alignmentDetails?customBaselineId=$baselineGuid"
        $response = Invoke-InforcerApiRequest -Endpoint $detailEndpoint -Method GET -OutputType $OutputType -ErrorAction SilentlyContinue -ErrorVariable apiErr
        if ($null -eq $response) {
            $errMsg = if ($apiErr -and $apiErr.Count -gt 0) { $apiErr[0].Exception.Message } else { $null }
            if ($errMsg -match 'permission|forbidden|access') {
                Write-Warning "No access to alignment details for tenant '$tName' ($tId). You may not have permission to view this baseline's data."
            } else {
                Write-Warning "No alignment data returned for tenant '$tName' ($tId)."
            }
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
                $row.PSObject.TypeNames.Insert(0, 'InforcerCommunity.AlignmentDetailPolicy')
                $row
            }
        }
    }
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
    $response = Invoke-InforcerApiRequest -Endpoint '/beta/alignmentScores' -Method GET -OutputType $OutputType
    if ($null -eq $response) { return }

    if ($null -ne $TenantId) {
        try {
            $clientTenantId = Resolve-InforcerTenantId -TenantId $TenantId
        } catch {
            Write-Error -Message $_.Exception.Message -ErrorId 'InvalidTenantId' -Category InvalidArgument
            return
        }
        Write-Verbose "Filtering alignment scores to tenant ID $clientTenantId..."
        $predicate = {
            param($p)
            $tidProp = $p.PSObject.Properties['tenantId']
            if (-not $tidProp) { $tidProp = $p.PSObject.Properties['clientTenantId'] }
            if ($tidProp -and [int]$tidProp.Value -eq $clientTenantId) { return $true }
            $summariesProp = $p.PSObject.Properties['alignmentSummaries']
            if ($summariesProp -and $summariesProp.Value -is [object[]]) {
                foreach ($s in $summariesProp.Value) {
                    if ($s -is [PSObject]) {
                        $aidProp = $s.PSObject.Properties['alignedBaselineTenantId']
                        if ($aidProp -and [int]$aidProp.Value -eq $clientTenantId) { return $true }
                    }
                }
            }
            $false
        }
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

# Format Table: use /beta/alignmentScores for fresh data, optionally join tenant names from /beta/tenants
Write-Verbose 'Retrieving alignment scores for table...'
$alignmentResponse = Invoke-InforcerApiRequest -Endpoint '/beta/alignmentScores' -Method GET -OutputType PowerShellObject
if ($null -eq $alignmentResponse) { return }

$allAlignmentData = ConvertTo-InforcerArray $alignmentResponse
# Detect flat format before deciding whether we need /beta/tenants
$firstItem = $null
if ($allAlignmentData.Count -gt 0) { $firstItem = $allAlignmentData[0] }
$flatFormat = ($firstItem -is [PSObject]) -and $firstItem.PSObject.Properties['tenantId'] -and $firstItem.PSObject.Properties['score'] -and -not $firstItem.PSObject.Properties['alignmentSummaries']

# Only fetch tenants when needed: nested format, or -TenantId, or -Tag (for baseline-owner expansion or tag filtering)
$needTenants = (-not $flatFormat) -or ($null -ne $TenantId) -or -not [string]::IsNullOrWhiteSpace($Tag)

$allTenants = @()
$tenantLookup = @{}
if ($needTenants) {
    Write-Verbose 'Retrieving tenant information for alignment table...'
    $tenantResponse = Invoke-InforcerApiRequest -Endpoint '/beta/tenants' -Method GET -OutputType PowerShellObject
    if ($null -eq $tenantResponse) { return }
    $allTenants = ConvertTo-InforcerArray $tenantResponse
    foreach ($t in $allTenants) {
        if ($t -is [PSObject]) {
            $null = Add-InforcerPropertyAliases -InputObject $t -ObjectType Tenant
            $idProp = $t.PSObject.Properties['clientTenantId']
            if ($null -ne $idProp -and $null -ne $idProp.Value) {
                $id = [int]$idProp.Value
                $tenantLookup[$id] = $t
            }
        }
    }
}

# Filter tenants by TenantId and Tag (same as before)
$tenants = @($allTenants | Where-Object { $_ -is [PSObject] })

if ($null -ne $TenantId) {
    try {
        $clientTenantId = Resolve-InforcerTenantId -TenantId $TenantId -TenantData $allTenants
    } catch {
        Write-Error -Message $_.Exception.Message -ErrorId 'InvalidTenantId' -Category InvalidArgument
        return
    }
    Write-Verbose "Filtering to tenant ID: $clientTenantId"
    $tenants = @($tenants | Where-Object {
        $idProp = $_.PSObject.Properties['clientTenantId']
        $idProp -and [int]$idProp.Value -eq $clientTenantId
    })
    # If no tenant with this ID exists in the system, return nothing.
    if ($tenants.Count -eq 0) {
        Write-Verbose "No tenant found with ID $clientTenantId. Returning no results."
        return
    }
}

if (-not [string]::IsNullOrWhiteSpace($Tag)) {
    Write-Verbose "Filtering to tenants with tag containing: $Tag"
    $tagPattern = "*$Tag*"
    $tenants = @($tenants | Where-Object {
        $tagsProp = $_.PSObject.Properties['tags']
        if (-not $tagsProp -or $null -eq $tagsProp.Value) { return $false }
        $val = $tagsProp.Value
        if ($val -is [object[]]) {
            foreach ($x in $val) {
                if ($x -and $x.ToString() -like $tagPattern) { return $true }
            }
        } else {
            if ($val.ToString() -like $tagPattern) { return $true }
        }
        $false
    })
}

Write-Verbose "Building alignment table from alignment scores ($($allAlignmentData.Count) source(s))..."

# Helper: add to $targetIds any tenant that is aligned to a baseline owned by an ID in $baselineOwnerIds
function Add-ChildTenantIdsFromAlignments {
    param([System.Collections.Hashtable]$targetIds, [array]$allTenants, [array]$baselineOwnerIds)
    foreach ($t in $allTenants) {
        if (-not ($t -is [PSObject])) { continue }
        $sumProp = $t.PSObject.Properties['alignmentSummaries']
        if (-not $sumProp -or $null -eq $sumProp.Value) { continue }
        $sums = $sumProp.Value
        if ($sums -isnot [object[]]) { $sums = @($sums) }
        foreach ($s in $sums) {
            if (-not ($s -is [PSObject])) { continue }
            $abtProp = $s.PSObject.Properties['alignedBaselineTenantId']
            if ($abtProp -and $null -ne $abtProp.Value) {
                $abt = 0
                if ([int]::TryParse($abtProp.Value.ToString(), [ref]$abt) -and ($baselineOwnerIds -contains $abt)) {
                    $childId = 0
                    $childProp = $t.PSObject.Properties['clientTenantId']
                    if ($childProp -and [int]::TryParse($childProp.Value.ToString(), [ref]$childId)) {
                        $targetIds[$childId] = $true
                    }
                }
            }
        }
    }
}

# Only filter by tenant when user explicitly passed -TenantId or -Tag; otherwise show all alignment rows
$tenantIds = @{}
if ($null -ne $TenantId -or -not [string]::IsNullOrWhiteSpace($Tag)) {
    foreach ($t in $tenants) {
        $idProp = $t.PSObject.Properties['clientTenantId']
        if ($idProp -and $null -ne $idProp.Value) {
            $tid = 0
            if ([int]::TryParse($idProp.Value.ToString(), [ref]$tid)) { $tenantIds[$tid] = $true }
        }
    }
    # If the requested tenant is a baseline owner, also include tenants aligned TO it
    if ($null -ne $TenantId -and $tenantIds.Count -gt 0) {
        $baselineOwnerIds = @($tenantIds.Keys)
        Add-ChildTenantIdsFromAlignments -targetIds $tenantIds -allTenants $allTenants -baselineOwnerIds $baselineOwnerIds
    }
}

# API can return flat array (tenantId, score, baselineGroupName...) or nested (clientTenantId, alignmentSummaries)
$alignmentTable = [System.Collections.ArrayList]::new()

if ($flatFormat) {
    foreach ($item in $allAlignmentData) {
        if (-not ($item -is [PSObject])) { continue }
        $tidProp = $item.PSObject.Properties['tenantId']
        if (-not $tidProp) { $tidProp = $item.PSObject.Properties['clientTenantId'] }
        $targetTenantClientTenantId = 0
        if ($tidProp -and $null -ne $tidProp.Value) {
            if (-not [int]::TryParse($tidProp.Value.ToString(), [ref]$targetTenantClientTenantId)) { continue }
        }
        if ($tenantIds.Count -gt 0 -and -not $tenantIds.ContainsKey($targetTenantClientTenantId)) { continue }

        $scoreVal = $item.PSObject.Properties['score'].Value
        $alignmentScoreFormatted = FormatAlignmentScore $scoreVal

        $row = [PSCustomObject]@{
            TargetTenantFriendlyName    = ($item.PSObject.Properties['tenantFriendlyName'].Value -as [string])
            TargetTenantClientTenantId  = $targetTenantClientTenantId
            AlignmentScore              = $alignmentScoreFormatted
            BaselineName                = $item.PSObject.Properties['baselineGroupName'].Value
            BaselineId                  = $item.PSObject.Properties['baselineGroupId'].Value
            LastComparisonDateTime      = $item.PSObject.Properties['lastComparisonDateTime'].Value
        }
        $row.PSObject.TypeNames.Insert(0, 'InforcerCommunity.AlignmentScore')
        [void]$alignmentTable.Add($row)
    }
} else {
    foreach ($tenant in $allAlignmentData) {
        if (-not ($tenant -is [PSObject])) { continue }
        $cidProp = $tenant.PSObject.Properties['clientTenantId']
        $targetTenantClientTenantId = 0
        if ($null -ne $cidProp -and $null -ne $cidProp.Value) {
            if (-not [int]::TryParse($cidProp.Value.ToString(), [ref]$targetTenantClientTenantId)) { continue }
        }
        if ($tenantIds.Count -gt 0 -and -not $tenantIds.ContainsKey($targetTenantClientTenantId)) { continue }

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
            $row.PSObject.TypeNames.Insert(0, 'InforcerCommunity.AlignmentScore')
            [void]$alignmentTable.Add($row)
        }
    }
}

Write-Verbose "Generated alignment table with $($alignmentTable.Count) row(s)."
if ($OutputType -eq 'JsonObject') {
    $json = $alignmentTable | ConvertTo-Json -Depth 100
    Write-Output $json
    return
}
$alignmentTable
}
