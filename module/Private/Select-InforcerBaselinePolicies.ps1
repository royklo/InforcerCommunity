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
        # An unknown name throws. Every caller handles $null (Export errors, Compare errors or
        # falls back for an inherited baseline), so turn it into that instead of an exception
        # that skips their handling.
        try {
            $baselineGuid = Resolve-InforcerBaselineId -BaselineId $BaselineId -BaselineData $allBaselines
        } catch {
            Write-Warning $_.Exception.Message
            return $null
        }
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

    # One entry per baseline policy: its name, every id that identifies it, and the fields that
    # tell same-named policies apart when there is no id to go on. Description is last and decisive
    # for the Microsoft MAM data protection levels, which share everything else.
    $tieBreakers = @('product', 'primaryGroup', 'secondaryGroup', 'description')
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
                        if ($p.PSObject.Properties['policyGuid']) {
                            # beta: policyGuid is the baseline's own policy; in any other tenant only
                            # subjectPolicyGuid points at that tenant's copy.
                            if ($p.policyGuid) { $entryIds.Add([string]$p.policyGuid) }
                            foreach ($m in @($p.matchingSubjectPolicies)) {
                                if ($m -and $m.PSObject.Properties['subjectPolicyGuid'] -and $m.subjectPolicyGuid) { $entryIds.Add([string]$m.subjectPolicyGuid) }
                            }
                        } else {
                            # v1: ids are Microsoft 365 ids; matchingSubjectPolicies[].id is the subject tenant's own policy.
                            if ($p.id) { $entryIds.Add([string]$p.id) }
                            foreach ($m in @($p.matchingSubjectPolicies)) {
                                if ($m.id) { $entryIds.Add([string]$m.id) }
                            }
                        }
                        if ($entryName -or $entryIds.Count) {
                            $entry = [ordered]@{ Name = $entryName; Ids = $entryIds }
                            foreach ($f in $tieBreakers) {
                                $fp = $p.PSObject.Properties[$f]
                                $entry[$f] = if ($fp -and -not [string]::IsNullOrWhiteSpace([string]$fp.Value)) { ([string]$fp.Value).Trim() }
                            }
                            $baselineEntries.Add([PSCustomObject]$entry)
                        }
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

    # Index the tenant's policies by id and by every name field once, then resolve each baseline
    # entry on its own: by id when it has one that matches, by name only when it does not.
    # Pooling every entry's names into one set and matching any policy carrying one of them (the
    # old way) pulled same-named policies into the baseline: the three Microsoft MAM data
    # protection levels share one name, so a baseline holding Level 1 exported all three.
    $policies = @($DocData.Policies)
    $byId = @{}; $byName = @{}
    for ($i = 0; $i -lt $policies.Count; $i++) {
        $pol = $policies[$i]
        $ids = @($pol.policyGuid, $pol.id)
        $names = @($pol.displayName, $pol.friendlyName, $pol.name, $pol.inforcerPolicyTypeName)
        if ($pol.policyData) { $ids += $pol.policyData.id; $names += @($pol.policyData.displayName, $pol.policyData.name) }
        foreach ($k in @($ids | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { ([string]$_).ToLowerInvariant() } | Select-Object -Unique)) {
            if (-not $byId.ContainsKey($k)) { $byId[$k] = [System.Collections.Generic.List[int]]::new() }
            $byId[$k].Add($i)
        }
        foreach ($k in @($names | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { ([string]$_).ToLowerInvariant() } | Select-Object -Unique)) {
            if (-not $byName.ContainsKey($k)) { $byName[$k] = [System.Collections.Generic.List[int]]::new() }
            $byName[$k].Add($i)
        }
    }

    $keep = [System.Collections.Generic.SortedSet[int]]::new()
    $notFound = [System.Collections.Generic.List[string]]::new()
    $ambiguous = [System.Collections.Generic.List[string]]::new()
    $conflicting = [System.Collections.Generic.List[string]]::new()
    foreach ($e in $baselineEntries) {
        $hits = @($e.Ids | ForEach-Object { $byId[([string]$_).ToLowerInvariant()] } | Where-Object { $null -ne $_ } | ForEach-Object { $_ } | Select-Object -Unique)
        if ($hits.Count -eq 0 -and $e.Name) {
            $sameName = @($byName[$e.Name.ToLowerInvariant()] | Where-Object { $null -ne $_ })
            # A same-named policy is a different one when a field both sides carry disagrees: that is
            # how a tenant holding only MAM Level 3 is kept from standing in for a missing Level 1.
            # A field the tenant policy lacks is no evidence either way, so it keeps the candidate.
            $hits = $sameName
            foreach ($f in $tieBreakers) {
                if (-not $e.$f) { continue }
                $hits = @($hits | Where-Object { $v = [string]$policies[$_].$f; [string]::IsNullOrWhiteSpace($v) -or $v.Trim() -eq $e.$f })
            }
            if ($hits.Count -eq 0 -and $sameName.Count -gt 0) {
                $conflicting.Add("$($e.Name) ($($sameName.Count) tenant $(if ($sameName.Count -eq 1) { 'policy' } else { 'policies' }))")
                continue
            }
            if ($hits.Count -gt 1) {
                $ambiguous.Add("$($e.Name) ($($hits.Count) tenant policies)")
                continue
            }
        }
        if ($hits.Count -eq 0) { $notFound.Add($(if ($e.Name) { $e.Name } else { $e.Ids[0] })); continue }
        foreach ($h in $hits) { [void]$keep.Add([int]$h) }
    }

    $originalCount = $policies.Count
    $DocData.Policies = @(foreach ($i in $keep) { $policies[$i] })
    $matchedCount = @($DocData.Policies).Count
    Write-Host "  Filtered to $matchedCount of $originalCount policies in baseline '$baselineFilterName'" -ForegroundColor Gray

    if ($notFound.Count -gt 0) {
        Write-Warning "$($notFound.Count) baseline policies not found in tenant:"
        foreach ($u in $notFound | Sort-Object -Unique) { Write-Warning "  - $u" }
    }
    # Left out rather than all included: guessing would document settings the baseline does not hold.
    if ($ambiguous.Count -gt 0) {
        Write-Warning "$($ambiguous.Count) baseline policies match several tenant policies by name, with nothing to tell them apart, and were left out:"
        foreach ($u in $ambiguous | Sort-Object -Unique) { Write-Warning "  - $u" }
    }
    if ($conflicting.Count -gt 0) {
        Write-Warning "$($conflicting.Count) baseline policies are not in the tenant; a same-named tenant policy differs in product, category or description, so it was not used in their place:"
        foreach ($u in $conflicting | Sort-Object -Unique) { Write-Warning "  - $u" }
    }

    return $baselineFilterName
}
