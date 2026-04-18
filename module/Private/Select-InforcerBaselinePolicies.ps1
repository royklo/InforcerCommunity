function Select-InforcerBaselinePolicies {
    <#
    .SYNOPSIS
        Filters a DocData policy collection to only policies belonging to a specific baseline.
    .DESCRIPTION
        Resolves the baseline identifier (GUID or friendly name), retrieves alignment details
        from the Inforcer API, and filters DocData.Policies in place to only those in the baseline.
        Must be called while the correct $script:InforcerSession is active.
    .PARAMETER DocData
        The DocData hashtable from Get-InforcerDocData. Contains .Tenant.clientTenantId and .Policies.
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

    $clientTenantId = $DocData.Tenant.clientTenantId

    # Resolve baseline name to GUID
    $baselineGuid = $null
    $baselineFilterName = $null
    $guidTest = [guid]::Empty
    if ([guid]::TryParse($BaselineId.Trim(), [ref]$guidTest)) {
        $baselineGuid = $BaselineId.Trim()
    } else {
        $allBaselines = @(Invoke-InforcerApiRequest -Endpoint '/beta/baselines' -Method GET -OutputType PowerShellObject)
        $baselineGuid = Resolve-InforcerBaselineId -BaselineId $BaselineId -BaselineData $allBaselines
        foreach ($bl in $allBaselines) {
            if ($bl.id -eq $baselineGuid) { $baselineFilterName = $bl.name; break }
        }
    }
    if (-not $baselineFilterName) { $baselineFilterName = $BaselineId }

    # Get alignment details
    Write-Host '  Retrieving alignment details...' -ForegroundColor Gray
    $alignEndpoint = "/beta/tenants/$clientTenantId/alignmentDetails?customBaselineId=$baselineGuid"
    $alignResponse = Invoke-InforcerApiRequest -Endpoint $alignEndpoint -Method GET -OutputType PowerShellObject -ErrorAction SilentlyContinue

    if ($null -eq $alignResponse) {
        Write-Warning "Could not retrieve alignment details for baseline '$baselineFilterName'."
        return $null
    }

    # Collect policy names AND GUIDs from baseline alignment status arrays
    $baselinePolicyNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $baselinePolicyGuids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $alignment = $alignResponse.alignment
    if ($null -ne $alignment) {
        $baselineArrays = @('matchedPolicies', 'matchedWithAcceptedDeviations', 'deviatedUnaccepted', 'missingFromSubjectUnaccepted')
        foreach ($arrayName in $baselineArrays) {
            $arr = $alignment.PSObject.Properties[$arrayName]
            if ($arr -and $null -ne $arr.Value) {
                foreach ($p in @($arr.Value)) {
                    if ($p -is [PSObject]) {
                        if ($p.PSObject.Properties['policyName'] -and $p.policyName) {
                            [void]$baselinePolicyNames.Add($p.policyName)
                        }
                        if ($p.PSObject.Properties['policyGuid'] -and $p.policyGuid) {
                            [void]$baselinePolicyGuids.Add($p.policyGuid)
                        }
                    }
                }
            }
        }
    }

    $baselineTotal = $baselinePolicyNames.Count
    if ($baselinePolicyGuids.Count -gt $baselineTotal) { $baselineTotal = $baselinePolicyGuids.Count }

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

    # Warn about unmatched baseline policies
    if ($matchedCount -lt $baselineTotal) {
        $matchedNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($pol in @($DocData.Policies)) {
            foreach ($n in @($pol.displayName, $pol.friendlyName, $pol.name)) {
                if (-not [string]::IsNullOrWhiteSpace($n)) { [void]$matchedNames.Add($n) }
            }
            if ($pol.policyData) {
                foreach ($n in @($pol.policyData.displayName, $pol.policyData.name)) {
                    if (-not [string]::IsNullOrWhiteSpace($n)) { [void]$matchedNames.Add($n) }
                }
            }
        }
        $unmatched = @($baselinePolicyNames | Where-Object { -not $matchedNames.Contains($_) })
        if ($unmatched.Count -gt 0) {
            Write-Warning "$($unmatched.Count) baseline policies not found in tenant:"
            foreach ($u in $unmatched | Sort-Object) { Write-Warning "  - $u" }
        }
    }

    return $baselineFilterName
}
