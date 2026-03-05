<#
.SYNOPSIS
    Retrieves alignment scores from the Inforcer API (table or raw).
.DESCRIPTION
    Format Table: flattened table with one row per alignment. Format Raw: raw API response.
    Optional -TenantId and -Tag (Table only) filters.
.PARAMETER Format
    Table (default) or Raw.
.PARAMETER TenantId
    Optional. Filter to this tenant.
.PARAMETER Tag
    Optional. When Format is Table, filter to tenants with tag containing this value (case-insensitive).
.PARAMETER OutputType
    Used when Format is Raw. PowerShellObject (default) or JsonObject. JSON uses Depth 100.
.EXAMPLE
    Get-InforcerAlignmentScore
.EXAMPLE
    Get-InforcerAlignmentScore -Format Raw -OutputType JsonObject
.EXAMPLE
    Get-InforcerAlignmentScore -TenantId 482 -Tag Production
.EXAMPLE
    Get-InforcerAlignmentScore -Format Table
    Table includes LastComparisonDateTime and uses fresh data from /beta/alignmentScores.
.OUTPUTS
    PSObject or String
.LINK
    Connect-Inforcer
#>
function Get-InforcerAlignmentScore {
[CmdletBinding()]
[OutputType([PSObject], [string])]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Table', 'Raw')]
    [string]$Format = 'Table',

    [Parameter(Mandatory = $false)]
    [object]$TenantId,

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
                if ($item -is [PSObject]) { Add-InforcerPropertyAliases -InputObject $item -ObjectType AlignmentScore | Out-Null }
            }
            if ($filtered -is [array]) { $filtered | ForEach-Object { $_ } } else { $filtered }
        }
        return
    }

    if ($OutputType -eq 'JsonObject') {
        return $response
    }
    foreach ($item in (ConvertTo-InforcerArray $response)) {
        if ($item -is [PSObject]) { Add-InforcerPropertyAliases -InputObject $item -ObjectType AlignmentScore | Out-Null }
    }
    if ($response -is [array]) { $response | ForEach-Object { $_ } } else { $response }
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
            Add-InforcerPropertyAliases -InputObject $t -ObjectType Tenant | Out-Null
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
}

if (-not [string]::IsNullOrWhiteSpace($Tag)) {
    Write-Verbose "Filtering to tenants with tag containing: $Tag"
    $tenants = @($tenants | Where-Object {
        $tagsProp = $_.PSObject.Properties['tags']
        if (-not $tagsProp -or $null -eq $tagsProp.Value) { return $false }
        $val = $tagsProp.Value
        if ($val -is [object[]]) {
            foreach ($x in $val) {
                if ($x -and $x.ToString().IndexOf($Tag, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
            }
        } else {
            if ($val.ToString().IndexOf($Tag, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
        }
        $false
    })
}

Write-Verbose "Building alignment table from alignment scores ($($allAlignmentData.Count) source(s))..."

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
    # (their alignmentSummaries reference it as alignedBaselineTenantId)
    if ($null -ne $TenantId -and $tenantIds.Count -gt 0) {
        $baselineOwnerIds = @($tenantIds.Keys)
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
                    if ([int]::TryParse($abtProp.Value.ToString(), [ref]$abt) -and $baselineOwnerIds -contains $abt) {
                        $childId = 0
                        $childProp = $t.PSObject.Properties['clientTenantId']
                        if ($childProp -and [int]::TryParse($childProp.Value.ToString(), [ref]$childId)) {
                            $tenantIds[$childId] = $true
                        }
                    }
                }
            }
        }
    }
}

# API can return flat array (tenantId, score, baselineGroupName...) or nested (clientTenantId, alignmentSummaries)
$alignmentTable = [System.Collections.ArrayList]::new()

if ($flatFormat) {
    foreach ($item in $allAlignmentData) {
        if (-not ($item -is [PSObject])) { continue }
        $tidProp = $item.PSObject.Properties['tenantId']
        $targetTenantClientTenantId = 0
        if ($tidProp -and $null -ne $tidProp.Value) {
            if (-not [int]::TryParse($tidProp.Value.ToString(), [ref]$targetTenantClientTenantId)) { continue }
        }
        if ($tenantIds.Count -gt 0 -and -not $tenantIds.ContainsKey($targetTenantClientTenantId)) { continue }

        $scoreVal = $item.PSObject.Properties['score'].Value
        $alignmentScoreFormatted = FormatAlignmentScore $scoreVal

        $row = [PSCustomObject]@{
            BaselineName                    = $item.PSObject.Properties['baselineGroupName'].Value
            BaselineId                      = $item.PSObject.Properties['baselineGroupId'].Value
            AlignmentScore                   = $alignmentScoreFormatted
            AlignedThreshold                 = $null
            SemiAlignedThreshold             = $null
            LastAlignmentDateTime            = $null
            LastComparisonDateTime           = $item.PSObject.Properties['lastComparisonDateTime'].Value
            BaselineOwnerTenantFriendlyName  = $null
            BaselineOwnerTenantMsTenantId    = $null
            BaselineOwnerTenantId            = $null
            TargetTenantFriendlyName         = ($item.PSObject.Properties['tenantFriendlyName'].Value -as [string])
            TargetTenantMsTenantId           = $null
            TargetTenantClientTenantId       = $targetTenantClientTenantId
            AlignedBaselineId                = $item.PSObject.Properties['baselineGroupId'].Value
        }
        $row.PSObject.Properties.Add([System.Management.Automation.PSAliasProperty]::new('TenantFriendlyName', 'TargetTenantFriendlyName'))
        $row.PSObject.Properties.Add([System.Management.Automation.PSAliasProperty]::new('TenantMsTenantId', 'TargetTenantMsTenantId'))
        $row.PSObject.Properties.Add([System.Management.Automation.PSAliasProperty]::new('TenantClientTenantId', 'TargetTenantClientTenantId'))
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
    $targetTenantMsTenantId = $tenant.PSObject.Properties['msTenantId'].Value -as [string]

    foreach ($alignment in $summaries) {
        if (-not ($alignment -is [PSObject])) { continue }

        $baselineOwnerTenantId = 0
        $aidProp = $alignment.PSObject.Properties['alignedBaselineTenantId']
        if ($null -ne $aidProp -and $null -ne $aidProp.Value) {
            $tmp = 0
            if ([int]::TryParse($aidProp.Value.ToString(), [ref]$tmp)) { $baselineOwnerTenantId = $tmp }
        }

        $baselineOwnerFriendlyName = "Unknown (ID: $baselineOwnerTenantId)"
        $baselineOwnerMsTenantId = $null
        if ($tenantLookup.ContainsKey($baselineOwnerTenantId)) {
            $ownerTenant = $tenantLookup[$baselineOwnerTenantId]
            $fn = $ownerTenant.PSObject.Properties['tenantFriendlyName'].Value
            $baselineOwnerFriendlyName = if ($fn) { $fn.ToString() } else { "Unknown (ID: $baselineOwnerTenantId)" }
            $baselineOwnerMsTenantId = $ownerTenant.PSObject.Properties['msTenantId'].Value -as [string]
        }

        $scoreProp = $alignment.PSObject.Properties['alignmentScore']
        $alignmentScoreFormatted = FormatAlignmentScore $(if ($scoreProp -and $null -ne $scoreProp.Value) { $scoreProp.Value } else { $null })

        $row = [PSCustomObject]@{
            BaselineName                    = $alignment.PSObject.Properties['alignedBaselineName'].Value
            BaselineId                      = $alignment.PSObject.Properties['alignedBaselineId'].Value
            AlignmentScore                   = $alignmentScoreFormatted
            AlignedThreshold                 = $alignment.PSObject.Properties['alignedThreshold'].Value
            SemiAlignedThreshold             = $alignment.PSObject.Properties['semiAlignedThreshold'].Value
            LastAlignmentDateTime            = $alignment.PSObject.Properties['lastAlignmentDateTime'].Value
            LastComparisonDateTime           = $alignment.PSObject.Properties['lastComparisonDateTime'].Value
            BaselineOwnerTenantFriendlyName  = $baselineOwnerFriendlyName
            BaselineOwnerTenantMsTenantId    = $baselineOwnerMsTenantId
            BaselineOwnerTenantId            = $baselineOwnerTenantId
            TargetTenantFriendlyName         = $targetTenantFriendlyName
            TargetTenantMsTenantId            = $targetTenantMsTenantId
            TargetTenantClientTenantId       = $targetTenantClientTenantId
            AlignedBaselineId                = $alignment.PSObject.Properties['alignedBaselineId'].Value
        }
        $row.PSObject.Properties.Add([System.Management.Automation.PSAliasProperty]::new('TenantFriendlyName', 'TargetTenantFriendlyName'))
        $row.PSObject.Properties.Add([System.Management.Automation.PSAliasProperty]::new('TenantMsTenantId', 'TargetTenantMsTenantId'))
        $row.PSObject.Properties.Add([System.Management.Automation.PSAliasProperty]::new('TenantClientTenantId', 'TargetTenantClientTenantId'))
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
$alignmentTable | ForEach-Object { $_ }
}
