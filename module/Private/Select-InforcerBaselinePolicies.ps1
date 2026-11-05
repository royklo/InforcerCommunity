function Select-InforcerBaselinePolicies {
    <#
    .SYNOPSIS
        Filters a DocData policy collection to only policies belonging to a specific baseline.
    .DESCRIPTION
        Resolves the baseline identifier (GUID or friendly name), retrieves alignment details
        from the Inforcer API, and filters DocData.Policies in place to only those in the baseline.
        Must be called while the correct $script:InforcerSession is active.
    .PARAMETER DocData
        The DocData hashtable from Get-InforcerDocData. Contains .TenantId and .Policies.
        Policies array is modified in place.
    .PARAMETER BaselineId
        Baseline GUID or friendly name.
    .OUTPUTS
        System.String — the resolved baseline display name, or $null if alignment data could not be retrieved.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object]$DocData,

        [Parameter(Mandatory)]
        [string]$BaselineId
    )

    $tenantId = $DocData.TenantId

    # Resolve baseline name to GUID
    $baselineGuid = $null
    $baselineFilterName = $null
    $guidTest = [guid]::Empty
    if ([guid]::TryParse($BaselineId.Trim(), [ref]$guidTest)) {
        $baselineGuid = $BaselineId.Trim()
    } else {
        # DocData already holds this session's baselines; the cached list covers callers without them.
        $allBaselines = @($DocData.Baselines | Where-Object { $null -ne $_ })
        if ($allBaselines.Count -eq 0) { $allBaselines = @(Get-InforcerBaselineList) }
        $baselineGuid = Resolve-InforcerBaselineId -BaselineId $BaselineId -BaselineData $allBaselines
        foreach ($bl in $allBaselines) {
            if ($bl.id -eq $baselineGuid) { $baselineFilterName = $bl.name; break }
        }
    }
    if (-not $baselineFilterName) { $baselineFilterName = $BaselineId }

    # Get alignment details
    Write-Host '  Retrieving alignment details...' -ForegroundColor Gray
    $alignEndpoint = "/tenants/$tenantId/alignmentDetails?customBaselineId=$baselineGuid"
    $alignResponse = Invoke-InforcerApiRequest -Endpoint $alignEndpoint -Method GET -OutputType PowerShellObject -ObjectType AlignmentDetails -ErrorAction SilentlyContinue

    if ($null -eq $alignResponse) {
        Write-Warning "Could not retrieve alignment details for baseline '$baselineFilterName'."
        return $null
    }

    # Collect policy names AND GUIDs from baseline alignment status arrays
    $baselinePolicyNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $baselinePolicyGuids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    # One entry per baseline policy (its name and every id that identifies it), for counting and the not-found list.
    $baselineEntries = [System.Collections.Generic.List[object]]::new()
    $alignment = $alignResponse.alignment
    if ($null -ne $alignment) {
        $baselineArrays = @('matchedPolicies', 'matchedWithAcceptedDeviations', 'deviatedUnaccepted', 'missingFromSubjectUnaccepted')
        foreach ($arrayName in $baselineArrays) {
            $arr = $alignment.PSObject.Properties[$arrayName]
            if ($arr -and $null -ne $arr.Value) {
                foreach ($p in @($arr.Value)) {
                    if ($p -is [PSObject]) {
                        $entryName = if ($p.PSObject.Properties['policyName'] -and $p.policyName) { [string]$p.policyName }
                        $entryIds = [System.Collections.Generic.List[string]]::new()
                        if ($entryName) { [void]$baselinePolicyNames.Add($entryName) }
                        if ($p.PSObject.Properties['policyGuid']) {
                            if ($p.policyGuid) { $entryIds.Add([string]$p.policyGuid) }
                        } else {
                            # v1: ids are Microsoft 365 ids; matchingSubjectPolicies[].id is the subject tenant's own policy.
                            if ($p.id) { $entryIds.Add([string]$p.id) }
                            foreach ($m in @($p.matchingSubjectPolicies)) {
                                if ($m.id) { $entryIds.Add([string]$m.id) }
                            }
                        }
                        foreach ($g in $entryIds) { [void]$baselinePolicyGuids.Add($g) }
                        if ($entryName -or $entryIds.Count) { $baselineEntries.Add([PSCustomObject]@{ Name = $entryName; Ids = $entryIds }) }
                    }
                }
            }
        }
    }

    $baselineTotal = $baselineEntries.Count

    if ($baselineTotal -eq 0) {
        Write-Warning "Baseline '$baselineFilterName' contains no policies in alignment data."
        return $null
    }

    # Filter DocData.Policies in place using multi-field matching chain
    $originalCount = @($DocData.Policies).Count
    $DocData.Policies = @($DocData.Policies | Where-Object {
        foreach ($n in @($_.displayName, $_.friendlyName, $_.name, $_.inforcerPolicyTypeName)) {
            if (-not [string]::IsNullOrWhiteSpace($n) -and $baselinePolicyNames.Contains($n)) { return $true }
        }
        if ($_.policyData) {
            foreach ($n in @($_.policyData.displayName, $_.policyData.name)) {
                if (-not [string]::IsNullOrWhiteSpace($n) -and $baselinePolicyNames.Contains($n)) { return $true }
            }
        }
        foreach ($g in @($_.policyGuid, $_.id)) {
            if (-not [string]::IsNullOrWhiteSpace($g) -and $baselinePolicyGuids.Contains($g)) { return $true }
        }
        if ($_.policyData -and $_.policyData.id) {
            if ($baselinePolicyGuids.Contains($_.policyData.id)) { return $true }
        }
        return $false
    })
    $matchedCount = @($DocData.Policies).Count
    Write-Host "  Filtered to $matchedCount of $originalCount policies in baseline '$baselineFilterName'" -ForegroundColor Gray

    # Warn about baseline policies the tenant has under neither their name nor any of their ids
    if ($matchedCount -lt $baselineTotal) {
        $matchedNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $matchedIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($pol in @($DocData.Policies)) {
            foreach ($n in @($pol.displayName, $pol.friendlyName, $pol.name, $pol.inforcerPolicyTypeName)) {
                if (-not [string]::IsNullOrWhiteSpace($n)) { [void]$matchedNames.Add($n) }
            }
            foreach ($g in @($pol.policyGuid, $pol.id)) {
                if (-not [string]::IsNullOrWhiteSpace($g)) { [void]$matchedIds.Add($g) }
            }
            if ($pol.policyData) {
                foreach ($n in @($pol.policyData.displayName, $pol.policyData.name)) {
                    if (-not [string]::IsNullOrWhiteSpace($n)) { [void]$matchedNames.Add($n) }
                }
                if ($pol.policyData.id) { [void]$matchedIds.Add($pol.policyData.id) }
            }
        }
        $unmatched = @(foreach ($e in $baselineEntries) {
            if ($e.Name -and $matchedNames.Contains($e.Name)) { continue }
            if (@($e.Ids | Where-Object { $matchedIds.Contains($_) }).Count) { continue }
            if ($e.Name) { $e.Name } else { $e.Ids[0] }
        })
        if ($unmatched.Count -gt 0) {
            Write-Warning "$($unmatched.Count) baseline policies not found in tenant:"
            foreach ($u in $unmatched | Sort-Object -Unique) { Write-Warning "  - $u" }
        }
    }

    return $baselineFilterName
}
