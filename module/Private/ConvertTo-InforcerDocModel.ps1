function Get-InforcerCategoryKey {
    <#
    .SYNOPSIS
        Builds a category key from primaryGroup and secondaryGroup, deduplicating when appropriate.
    .DESCRIPTION
        Returns primaryGroup alone when secondaryGroup is null, empty, equal to primaryGroup,
        or equal to "All". Otherwise returns "primaryGroup / secondaryGroup".
        Used by ConvertTo-InforcerDocModel for deterministic category naming (per D-11).
    #>
    [CmdletBinding()]
    param(
        [Parameter()][string]$PrimaryGroup,
        [Parameter()][string]$SecondaryGroup
    )
    if ([string]::IsNullOrWhiteSpace($SecondaryGroup) -or
        $SecondaryGroup -eq $PrimaryGroup -or
        $SecondaryGroup -eq 'All') {
        return $PrimaryGroup
    }
    return "$PrimaryGroup / $SecondaryGroup"
}

function Get-InforcerPolicyName {
    <#
    .SYNOPSIS
        Resolves a policy display name using the D-13 fallback chain.
    .DESCRIPTION
        Applies: displayName -> friendlyName -> name -> policyData.name ->
        policyData.displayName -> "Policy {id}". Ensures no policy appears with a null name.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Policy)
    $name = $Policy.displayName -as [string]
    if ([string]::IsNullOrWhiteSpace($name)) { $name = $Policy.friendlyName -as [string] }
    if ([string]::IsNullOrWhiteSpace($name)) { $name = $Policy.name -as [string] }
    if ([string]::IsNullOrWhiteSpace($name) -and $Policy.policyData) {
        $name = $Policy.policyData.name -as [string]
        if ([string]::IsNullOrWhiteSpace($name)) { $name = $Policy.policyData.displayName -as [string] }
    }
    if ([string]::IsNullOrWhiteSpace($name)) {
        $idVal = $Policy.id
        $name = "Policy $(if ($null -ne $idVal) { $idVal } else { 'Unknown' })"
    }
    return $name
}

function ConvertTo-InforcerDocModel {
    <#
    .SYNOPSIS
        Normalizes raw Inforcer API data into a format-agnostic DocModel.
    .DESCRIPTION
        Takes a DocData bundle (from Get-InforcerDocData) and transforms it into the
        hierarchical DocModel structure: Products -> Categories -> Policies, each with
        Basics, Settings, and Assignments sections.

        Settings Catalog policies (policyTypeId 10) have their settingDefinitionIDs resolved
        to friendly names via ConvertTo-InforcerSettingRows. All other policy types have their
        policyData properties enumerated as flat Name/Value rows via ConvertTo-FlatSettingRows.

        The DocModel is format-agnostic: it contains only data, no rendering logic, and makes
        no API calls (per NORM-06).
    .PARAMETER DocData
        Hashtable from Get-InforcerDocData containing:
        Tenant, Baselines, Policies, TenantId, CollectedAt.
    .OUTPUTS
        Hashtable representing the DocModel tree (per D-10).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$DocData,

        [Parameter()]
        [hashtable]$GroupNameMap,

        [Parameter()]
        [hashtable]$FilterMap,

        [Parameter()]
        [hashtable]$ScopeTagMap,

        [Parameter()]
        [switch]$ComparisonMode
    )

    $tenant   = $DocData.Tenant
    $policies = $DocData.Policies
    $baselines = $DocData.Baselines

    # Tenant metadata
    $tenantName = ''
    if ($null -ne $tenant) {
        $tenantName = $tenant.tenantFriendlyName
        if ([string]::IsNullOrWhiteSpace($tenantName)) { $tenantName = $tenant.tenantDnsName }
        if ([string]::IsNullOrWhiteSpace($tenantName)) { $tenantName = "Tenant $($DocData.TenantId)" }
    }

    # Collect all baseline names for this tenant
    $baselineNames = @()
    if ($null -ne $baselines -and $baselines.Count -gt 0) {
        foreach ($bl in @($baselines)) {
            $blName = $bl.name
            if ([string]::IsNullOrWhiteSpace($blName)) { $blName = $bl.baselineGroupName }
            if (-not [string]::IsNullOrWhiteSpace($blName)) { $baselineNames += $blName }
        }
    }

    # Group policies by product -> category (per NORM-01, NORM-02, D-04, D-05)
    $products = [ordered]@{}

    foreach ($policy in @($policies)) {
        if ($null -eq $policy) { continue }

        $prod = $policy.product
        if ([string]::IsNullOrWhiteSpace($prod)) { $prod = 'Other' }

        # Normalize policy name (per NORM-05, D-13)
        $policyName = Get-InforcerPolicyName -Policy $policy

        # Map to friendly display name and Microsoft admin portal category
        $displayInfo = Get-InforcerPolicyDisplayInfo -PolicyName $policyName `
            -Product $prod -PrimaryGroup $policy.primaryGroup `
            -SecondaryGroup $policy.secondaryGroup -PolicyTypeId $policy.policyTypeId
        if ($displayInfo.FriendlyName) { $policyName = $displayInfo.FriendlyName }

        $catKey = if ($displayInfo.Category) {
            $displayInfo.Category
        } else {
            Get-InforcerCategoryKey -PrimaryGroup $policy.primaryGroup -SecondaryGroup $policy.secondaryGroup
        }
        if ([string]::IsNullOrWhiteSpace($catKey)) { $catKey = 'General' }

        # ComparisonMode filtering: only Intune-relevant products, skip non-comparable categories
        if ($ComparisonMode) {
            $prodLower = $prod.ToLowerInvariant()
            $intuneProducts = @('intune', 'windows', 'macos', 'ios', 'android', 'defender')
            $isIntuneRelevant = $false
            foreach ($ip in $intuneProducts) {
                if ($prodLower -match [regex]::Escape($ip)) { $isIntuneRelevant = $true; break }
            }
            if (-not $isIntuneRelevant) { continue }
            # Skip compliance policies
            $catLower = $catKey.ToLowerInvariant()
            if ($catLower -match 'compliance') { continue }
            # Skip enrollment/autopilot categories
            if ($catLower -match 'enrollment|autopilot') { continue }
            # Skip exchange categories (Defender for Office 365, not Intune)
            if ($catLower -match '^exchange') { continue }
        }

        # Ensure product and category exist (per NORM-02)
        if (-not $products.Contains($prod)) {
            $products[$prod] = @{ Categories = [ordered]@{} }
        }
        if (-not $products[$prod].Categories.Contains($catKey)) {
            $products[$prod].Categories[$catKey] = [System.Collections.Generic.List[object]]::new()
        }

        # Extract policy tags (baseline membership indicators)
        $policyTags = @()
        if ($null -ne $policy.tags -and @($policy.tags).Count -gt 0) {
            $policyTags = @($policy.tags | ForEach-Object {
                if ($_ -is [PSObject] -and $_.PSObject.Properties['name']) { $_.name } else { $_.ToString() }
            } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }

        # Basics section (per NORM-04)
        $basics = @{
            Name        = $policyName
            Description = if ($policy.policyData -and $policy.policyData.description) { $policy.policyData.description } else { '' }
            ProfileType = if ($policy.inforcerPolicyTypeName) { $policy.inforcerPolicyTypeName } else { '' }
            Platform    = if ($policy.platform) { $policy.platform } else { '' }  # null ~96% per D-14
            Created     = if ($policy.policyData -and $policy.policyData.createdDateTime) { $policy.policyData.createdDateTime } else { '' }
            Modified    = if ($policy.policyData -and $policy.policyData.lastModifiedDateTime) { $policy.policyData.lastModifiedDateTime } else { '' }
            ScopeTags   = ''
            Tags        = if ($policyTags.Count -gt 0) { $policyTags -join ', ' } else { '' }
        }
        # Scope tags normalization (per D-15) -- resolve IDs to names when ScopeTagMap available
        $scopeTags = $policy.policyData.roleScopeTagIds
        if ($null -ne $scopeTags -and $scopeTags.Count -gt 0) {
            if ($ScopeTagMap -and $ScopeTagMap.Count -gt 0) {
                $resolvedTags = @($scopeTags | ForEach-Object {
                    $tagId = $_.ToString()
                    if ($ScopeTagMap.ContainsKey($tagId)) { $ScopeTagMap[$tagId] } else { $tagId }
                })
                $basics.ScopeTags = ($resolvedTags -join ', ')
            } else {
                $basics.ScopeTags = ($scopeTags -join ', ')
            }
        }

        # Settings section: route by policyTypeId (per D-06, D-07, SCAT-01..06)
        $settings = [System.Collections.Generic.List[object]]::new()
        $policyTypeId = $policy.policyTypeId

        if ($policyTypeId -eq 10 -and $policy.policyData -and $policy.policyData.settings) {
            # Settings Catalog -- use ConvertTo-InforcerSettingRows (per SCAT-01..06)
            foreach ($settingGroup in @($policy.policyData.settings)) {
                if ($null -ne $settingGroup -and $settingGroup.settingInstance) {
                    foreach ($row in (ConvertTo-InforcerSettingRows -SettingInstance $settingGroup.settingInstance)) {
                        [void]$settings.Add($row)
                    }
                }
            }
        } elseif ($null -ne $policy.policyData) {
            # Non-catalog -- use ConvertTo-FlatSettingRows (per D-07)
            foreach ($row in (ConvertTo-FlatSettingRows -PolicyData $policy.policyData)) {
                [void]$settings.Add($row)
            }
        }

        # Assignments section (per NORM-03) -- uses Resolve-InforcerAssignments
        $rawAssignments = $policy.policyData.assignments
        if ($null -eq $rawAssignments) { $rawAssignments = $policy.assignments }
        $resolveParams = @{ RawAssignments = $rawAssignments }
        if ($null -ne $GroupNameMap)  { $resolveParams['GroupNameMap'] = $GroupNameMap }
        if ($null -ne $FilterMap)     { $resolveParams['FilterMap'] = $FilterMap }
        $assignments = @(Resolve-InforcerAssignments @resolveParams)

        # Assemble normalized policy (per NORM-03)
        $normalizedPolicy = @{
            Basics       = $basics
            Settings     = $settings.ToArray()
            Assignments  = $assignments
            PolicyTypeId = $policyTypeId
        }

        [void]$products[$prod].Categories[$catKey].Add($normalizedPolicy)
    }

    # Return the DocModel (per D-10, NORM-06)
    @{
        TenantName   = $tenantName
        TenantId     = $DocData.TenantId
        GeneratedAt  = $DocData.CollectedAt
        BaselineName = if ($baselineNames.Count -gt 0) { $baselineNames[0] } else { '' }
        Baselines    = $baselineNames
        Products     = $products
    }
}
