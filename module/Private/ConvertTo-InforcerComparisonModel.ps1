function Get-InforcerAssignmentString {
    <#
    .SYNOPSIS
        Extracts a human-readable assignment summary string from a policy.
    #>
    [CmdletBinding()]
    param([Parameter()]$Policy)

    $rawAssignments = $null
    if ($Policy.policyData -and $Policy.policyData.assignments) {
        $rawAssignments = $Policy.policyData.assignments
    } elseif ($Policy.assignments) {
        $rawAssignments = $Policy.assignments
    }

    if ($null -eq $rawAssignments -or @($rawAssignments).Count -eq 0) {
        return ''
    }

    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($assignment in @($rawAssignments)) {
        $target = $assignment.target
        if ($null -eq $target) { continue }
        $type = $target.'@odata.type'
        switch -Wildcard ($type) {
            '*allDevicesAssignmentTarget'         { [void]$parts.Add('All Devices') }
            '*allUsersAssignmentTarget'            { [void]$parts.Add('All Users') }
            '*allLicensedUsersAssignmentTarget'    { [void]$parts.Add('All Licensed Users') }
            '*groupAssignmentTarget'               {
                $gid = $target.groupId
                if ($gid) { [void]$parts.Add("Group:$gid") } else { [void]$parts.Add('Group') }
            }
            '*exclusionGroupAssignmentTarget'      {
                $gid = $target.groupId
                if ($gid) { [void]$parts.Add("Exclude:$gid") } else { [void]$parts.Add('Exclude') }
            }
            default {
                if ($type) { [void]$parts.Add($type.Split('.')[-1]) }
                else { [void]$parts.Add('Unknown') }
            }
        }
    }
    return ($parts -join '; ')
}

function ConvertTo-InforcerComparisonModel {
    <#
    .SYNOPSIS
        Builds a structured comparison model from two sets of policies.
    .DESCRIPTION
        Stage 2 of the Compare-InforcerEnvironments pipeline. Receives raw policy data
        from Stage 1 (Get-InforcerComparisonData) and produces a hierarchical comparison
        model consumed by Stage 3 (HTML/Markdown renderer).

        Compares exclusively at the Intune Settings Catalog setting level:
        - Filters to policyTypeId -eq 10 only
        - Extracts settings using ConvertTo-InforcerSettingRows (reused from Export-InforcerTenantDocumentation)
        - Matches by settingDefinitionId across source and destination
        - Classifies as Matched, Conflicting, SourceOnly, or DestOnly
    .PARAMETER ComparisonData
        Hashtable from Get-InforcerComparisonData containing: SourcePolicies,
        DestinationPolicies, SourceName, DestinationName,
        SettingsCatalog, IncludingAssignments, CollectedAt.
    .OUTPUTS
        Hashtable representing the ComparisonModel.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ComparisonData
    )

    $sourcePolicies       = @($ComparisonData.SourcePolicies)
    $destPolicies         = @($ComparisonData.DestinationPolicies)
    $includingAssignments = $ComparisonData.IncludingAssignments

    # ── Split policies by type: Settings Catalog (policyTypeId 10) vs all others ──
    $srcSC    = [System.Collections.Generic.List[object]]::new()
    $dstSC    = [System.Collections.Generic.List[object]]::new()

    foreach ($p in $sourcePolicies) {
        if ($null -eq $p) { continue }
        if ($p.policyTypeId -eq 10) { [void]$srcSC.Add($p) }
    }
    foreach ($p in $destPolicies) {
        if ($null -eq $p) { continue }
        if ($p.policyTypeId -eq 10) { [void]$dstSC.Add($p) }
    }

    # ── Result containers ─────────────────────────────────────────────────
    $products = [ordered]@{}
    $counters = @{ Matched = 0; Conflicting = 0; SourceOnly = 0; DestOnly = 0 }

    # ── Helper: ensure product/category exists ────────────────────────────
    $ensureProductCategory = {
        param([string]$Product, [string]$Category)
        if (-not $products.Contains($Product)) {
            $products[$Product] = @{
                Counters   = @{ Matched = 0; Conflicting = 0; SourceOnly = 0; DestOnly = 0 }
                Categories = [ordered]@{}
            }
        }
        if (-not $products[$Product].Categories.Contains($Category)) {
            $products[$Product].Categories[$Category] = @{
                ComparisonRows = [System.Collections.Generic.List[object]]::new()
            }
        }
    }

    # ── Helper: add comparison row ────────────────────────────────────────
    $addRow = {
        param([string]$Product, [string]$Category, [hashtable]$Row)
        & $ensureProductCategory $Product $Category
        [void]$products[$Product].Categories[$Category].ComparisonRows.Add($Row)
    }

    # ── Helper: get category key ──────────────────────────────────────────
    $getCategoryKey = {
        param($Policy)
        Get-InforcerCategoryKey -PrimaryGroup $Policy.primaryGroup -SecondaryGroup $Policy.secondaryGroup
    }

    # ── Helper: get product ───────────────────────────────────────────────
    $getProduct = {
        param($Policy)
        $prod = $Policy.product
        if ([string]::IsNullOrWhiteSpace($prod)) { $prod = 'Other' }
        return $prod
    }

    # ── Build set of category prefixes from SC policies ───────────────────
    # Filter non-SC policies by CATEGORY prefix, not product. This avoids
    # including unrelated categories (e.g. Exchange/*) that happen to share
    # a product name (e.g. "Microsoft Defender for Endpoint") with SC policies.
    $scCategoryPrefixes = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($p in ($srcSC + $dstSC)) {
        $catKey = & $getCategoryKey $p
        # Use the first part of the category (before " / ") as the prefix
        $prefix = if ($catKey -match '^([^/]+)') { $Matches[1].Trim() } else { $catKey }
        if (-not [string]::IsNullOrWhiteSpace($prefix)) { [void]$scCategoryPrefixes.Add($prefix) }
    }

    # Non-SC policies: only those whose category prefix matches an SC category
    # AND whose category is not an enrollment/provisioning area (not configuration)
    $isExcludedCategory = {
        param([string]$CatKey)
        $lower = $CatKey.ToLowerInvariant()
        # Enrollment and provisioning categories are not configuration policies
        if ($lower -match 'enrollment|autopilot') { return $true }
        # Exchange categories under Defender product are Defender for Office 365, not Intune
        if ($lower -match '^exchange') { return $true }
        return $false
    }

    $srcNonSC = [System.Collections.Generic.List[object]]::new()
    $dstNonSC = [System.Collections.Generic.List[object]]::new()
    foreach ($p in $sourcePolicies) {
        if ($null -eq $p -or $p.policyTypeId -eq 10) { continue }
        $catKey = & $getCategoryKey $p
        $prefix = if ($catKey -match '^([^/]+)') { $Matches[1].Trim() } else { $catKey }
        if (-not $scCategoryPrefixes.Contains($prefix)) { continue }
        if (& $isExcludedCategory $catKey) { continue }
        [void]$srcNonSC.Add($p)
    }
    foreach ($p in $destPolicies) {
        if ($null -eq $p -or $p.policyTypeId -eq 10) { continue }
        $catKey = & $getCategoryKey $p
        $prefix = if ($catKey -match '^([^/]+)') { $Matches[1].Trim() } else { $catKey }
        if (-not $scCategoryPrefixes.Contains($prefix)) { continue }
        if (& $isExcludedCategory $catKey) { continue }
        [void]$dstNonSC.Add($p)
    }

    # ── Extract settings from SC policies ─────────────────────────────────
    # Build: settingDefinitionId -> { FriendlyName, Value, PolicyName, Product, Category, Assignment }
    $srcSettings = @{}
    $dstSettings = @{}

    foreach ($p in $srcSC) {
        $prod = & $getProduct $p
        $cat  = & $getCategoryKey $p
        if ([string]::IsNullOrWhiteSpace($cat)) { $cat = 'General' }
        $policyName = Get-InforcerPolicyName -Policy $p
        $assignment = if ($includingAssignments) { Get-InforcerAssignmentString -Policy $p } else { '' }

        if ($p.policyData -and $p.policyData.settings) {
            foreach ($settingGroup in @($p.policyData.settings)) {
                if ($null -eq $settingGroup -or $null -eq $settingGroup.settingInstance) { continue }
                $defId = $settingGroup.settingInstance.settingDefinitionId
                if ([string]::IsNullOrEmpty($defId)) { continue }

                # Use ConvertTo-InforcerSettingRows for friendly name and value
                $rows = @(ConvertTo-InforcerSettingRows -SettingInstance $settingGroup.settingInstance)
                $friendlyName = if ($rows.Count -gt 0) { $rows[0].Name } else { $defId }
                # Use first configured value; for group settings the header row has empty value
                $configuredRows = @($rows | Where-Object { $_.IsConfigured -eq $true -and -not [string]::IsNullOrWhiteSpace("$($_.Value)") })
                $value = if ($configuredRows.Count -gt 0) { "$($configuredRows[0].Value)" }
                         elseif ($rows.Count -gt 0) { "$($rows[0].Value)" }
                         else { '' }

                # First occurrence wins for each settingDefinitionId
                if (-not $srcSettings.ContainsKey($defId)) {
                    $srcSettings[$defId] = @{
                        FriendlyName = $friendlyName
                        Value        = $value
                        PolicyName   = $policyName
                        Product      = $prod
                        Category     = $cat
                        Assignment   = $assignment
                    }
                }
            }
        }
    }

    foreach ($p in $dstSC) {
        $prod = & $getProduct $p
        $cat  = & $getCategoryKey $p
        if ([string]::IsNullOrWhiteSpace($cat)) { $cat = 'General' }
        $policyName = Get-InforcerPolicyName -Policy $p
        $assignment = if ($includingAssignments) { Get-InforcerAssignmentString -Policy $p } else { '' }

        if ($p.policyData -and $p.policyData.settings) {
            foreach ($settingGroup in @($p.policyData.settings)) {
                if ($null -eq $settingGroup -or $null -eq $settingGroup.settingInstance) { continue }
                $defId = $settingGroup.settingInstance.settingDefinitionId
                if ([string]::IsNullOrEmpty($defId)) { continue }

                $rows = @(ConvertTo-InforcerSettingRows -SettingInstance $settingGroup.settingInstance)
                $friendlyName = if ($rows.Count -gt 0) { $rows[0].Name } else { $defId }
                # Use first configured value; for group settings the header row has empty value
                $configuredRows = @($rows | Where-Object { $_.IsConfigured -eq $true -and -not [string]::IsNullOrWhiteSpace("$($_.Value)") })
                $value = if ($configuredRows.Count -gt 0) { "$($configuredRows[0].Value)" }
                         elseif ($rows.Count -gt 0) { "$($rows[0].Value)" }
                         else { '' }

                if (-not $dstSettings.ContainsKey($defId)) {
                    $dstSettings[$defId] = @{
                        FriendlyName = $friendlyName
                        Value        = $value
                        PolicyName   = $policyName
                        Product      = $prod
                        Category     = $cat
                        Assignment   = $assignment
                    }
                }
            }
        }
    }

    # ── Helper: extract application name from settingDefinitionId ──────────
    $appNamePatterns = @{
        'word16v2'    = 'Word'
        'excel16v2'   = 'Excel'
        'ppt16v2'     = 'PowerPoint'
        'access16v2'  = 'Access'
        'outlook16v2' = 'Outlook'
        'edge~'       = 'Edge'
        'edge_v\d'    = 'Edge'
        'onent16v2'   = 'OneNote'
        'pub16v2'     = 'Publisher'
        'visio16v2'   = 'Visio'
        'proj16v2'    = 'Project'
    }
    $getAppNameFromDefId = {
        param([string]$DefId)
        $lower = $DefId.ToLowerInvariant()
        foreach ($pattern in $appNamePatterns.Keys) {
            if ($lower -match $pattern) { return $appNamePatterns[$pattern] }
        }
        return $null
    }

    # ── Deduplicate friendly names ─────────────────────────────────────────
    # Multiple settingDefinitionIds can resolve to the same friendly name.
    # When duplicates exist, append the application name extracted from the defId.
    $deduplicateNames = {
        param([hashtable]$SettingsHash)
        # Group by friendly name
        $nameGroups = @{}
        foreach ($defId in $SettingsHash.Keys) {
            $name = $SettingsHash[$defId].FriendlyName
            if (-not $nameGroups.ContainsKey($name)) {
                $nameGroups[$name] = [System.Collections.Generic.List[string]]::new()
            }
            [void]$nameGroups[$name].Add($defId)
        }
        # For groups with >1 entry, disambiguate using app name
        foreach ($name in $nameGroups.Keys) {
            $ids = $nameGroups[$name]
            if ($ids.Count -gt 1) {
                $counter = 1
                foreach ($defId in $ids) {
                    $appName = & $getAppNameFromDefId $defId
                    if ($appName) {
                        $SettingsHash[$defId].FriendlyName = "$name — $appName"
                    } else {
                        # Fallback: extract last meaningful segment of the defId
                        $segments = $defId -split '[_/]'
                        $suffix = if ($segments.Count -ge 2) { $segments[-2] } else { "$counter" }
                        $SettingsHash[$defId].FriendlyName = "$name ($suffix)"
                    }
                    $counter++
                }
            }
        }
    }
    & $deduplicateNames $srcSettings
    & $deduplicateNames $dstSettings

    # ── Compare settings by settingDefinitionId ───────────────────────────
    $allDefIds = @($srcSettings.Keys) + @($dstSettings.Keys) | Sort-Object -Unique

    foreach ($defId in $allDefIds) {
        $inSrc = $srcSettings.ContainsKey($defId)
        $inDst = $dstSettings.ContainsKey($defId)

        $row = @{
            ItemType            = 'Setting'
            SettingDefinitionId = $defId
        }

        if ($inSrc -and $inDst) {
            $srcInfo = $srcSettings[$defId]
            $dstInfo = $dstSettings[$defId]
            $product  = $srcInfo.Product
            $category = $srcInfo.Category

            $row.Name         = $srcInfo.FriendlyName
            $row.Category     = $category
            $row.SourcePolicy = $srcInfo.PolicyName
            $row.SourceValue  = $srcInfo.Value
            $row.DestPolicy   = $dstInfo.PolicyName
            $row.DestValue    = $dstInfo.Value

            if ($includingAssignments) {
                $row.SourceAssignment = $srcInfo.Assignment
                $row.DestAssignment   = $dstInfo.Assignment
            }

            if ($srcInfo.Value -eq $dstInfo.Value) {
                $row.Status = 'Matched'
                $counters.Matched++
                & $ensureProductCategory $product $category
                $products[$product].Counters.Matched++
            } else {
                $row.Status = 'Conflicting'
                $counters.Conflicting++
                & $ensureProductCategory $product $category
                $products[$product].Counters.Conflicting++
            }
            & $addRow $product $category $row

        } elseif ($inSrc) {
            $srcInfo  = $srcSettings[$defId]
            $product  = $srcInfo.Product
            $category = $srcInfo.Category

            $row.Name         = $srcInfo.FriendlyName
            $row.Category     = $category
            $row.Status       = 'SourceOnly'
            $row.SourcePolicy = $srcInfo.PolicyName
            $row.SourceValue  = $srcInfo.Value
            $row.DestPolicy   = ''
            $row.DestValue    = ''

            if ($includingAssignments) {
                $row.SourceAssignment = $srcInfo.Assignment
                $row.DestAssignment   = ''
            }

            $counters.SourceOnly++
            & $ensureProductCategory $product $category
            $products[$product].Counters.SourceOnly++
            & $addRow $product $category $row

        } else {
            $dstInfo  = $dstSettings[$defId]
            $product  = $dstInfo.Product
            $category = $dstInfo.Category

            $row.Name         = $dstInfo.FriendlyName
            $row.Category     = $category
            $row.Status       = 'DestOnly'
            $row.SourcePolicy = ''
            $row.SourceValue  = ''
            $row.DestPolicy   = $dstInfo.PolicyName
            $row.DestValue    = $dstInfo.Value

            if ($includingAssignments) {
                $row.SourceAssignment = ''
                $row.DestAssignment   = $dstInfo.Assignment
            }

            $counters.DestOnly++
            & $ensureProductCategory $product $category
            $products[$product].Counters.DestOnly++
            & $addRow $product $category $row
        }
    }

    # ── Policy-level comparison for non-SC policies ──────────────────────
    # All non-Settings-Catalog policies are compared at the policy level
    # by matching on product|primaryGroup|displayName.
    # Matched/Conflicting → comparison tab; SourceOnly/DestOnly → manual review tab.

    # Build match key: product|primaryGroup|displayName (lowercased)
    $buildMatchKey = {
        param($Policy)
        $prod = (& $getProduct $Policy).ToLowerInvariant()
        $pg = if ($Policy.primaryGroup) { $Policy.primaryGroup.ToLowerInvariant() } else { '' }
        $dn = (Get-InforcerPolicyName -Policy $Policy).ToLowerInvariant()
        return "$prod|$pg|$dn"
    }

    # Index source non-SC by match key
    $srcNonSCIndex = @{}
    foreach ($p in $srcNonSC) {
        $key = & $buildMatchKey $p
        if (-not $srcNonSCIndex.ContainsKey($key)) { $srcNonSCIndex[$key] = $p }
    }
    # Index dest non-SC by match key
    $dstNonSCIndex = @{}
    foreach ($p in $dstNonSC) {
        $key = & $buildMatchKey $p
        if (-not $dstNonSCIndex.ContainsKey($key)) { $dstNonSCIndex[$key] = $p }
    }

    $allNonSCKeys = @($srcNonSCIndex.Keys) + @($dstNonSCIndex.Keys) | Sort-Object -Unique

    # Manual review containers (populated with unmatched non-SC policies below)
    $manualReview = [ordered]@{}
    $manualCount = 0

    $ensureManualCategory = {
        param([string]$Product, [string]$Category)
        if (-not $manualReview.Contains($Product)) {
            $manualReview[$Product] = @{
                Count      = 0
                Categories = [ordered]@{}
            }
        }
        if (-not $manualReview[$Product].Categories.Contains($Category)) {
            $manualReview[$Product].Categories[$Category] = [System.Collections.Generic.List[object]]::new()
        }
    }

    $getPolicyTypeFriendly = {
        param($Policy)
        if ($Policy.inforcerPolicyTypeName) { return $Policy.inforcerPolicyTypeName }
        if ($Policy.primaryGroup) { return $Policy.primaryGroup }
        if ($Policy.product) { return $Policy.product }
        return "Type $($Policy.policyTypeId)"
    }

    foreach ($key in $allNonSCKeys) {
        $inSrc = $srcNonSCIndex.ContainsKey($key)
        $inDst = $dstNonSCIndex.ContainsKey($key)

        if ($inSrc -and $inDst) {
            # ── Matched pair → comparison tab ──
            $srcP = $srcNonSCIndex[$key]
            $dstP = $dstNonSCIndex[$key]

            $prod = & $getProduct $srcP
            $cat  = & $getCategoryKey $srcP
            if ([string]::IsNullOrWhiteSpace($cat)) { $cat = 'General' }
            $policyName = Get-InforcerPolicyName -Policy $srcP

            # Compare policyData as JSON
            $srcJson = if ($srcP.policyData) { $srcP.policyData | ConvertTo-Json -Depth 50 -Compress } else { '' }
            $dstJson = if ($dstP.policyData) { $dstP.policyData | ConvertTo-Json -Depth 50 -Compress } else { '' }

            $status = if ($srcJson -eq $dstJson) { 'Matched' } else { 'Conflicting' }

            # Extract flat settings for non-SC policies so users can see actual values
            $srcFlatSettings = @()
            $dstFlatSettings = @()
            if ($status -ne 'Matched') {
                if ($srcP.policyData) { $srcFlatSettings = @(ConvertTo-FlatSettingRows -PolicyData $srcP.policyData) }
                if ($dstP.policyData) { $dstFlatSettings = @(ConvertTo-FlatSettingRows -PolicyData $dstP.policyData) }
            }

            $row = @{
                ItemType       = 'Policy'
                Name           = $policyName
                Category       = $cat
                Status         = $status
                SourcePolicy   = $policyName
                SourceValue    = if ($status -eq 'Matched') { 'Identical' } else { 'Differs' }
                DestPolicy     = Get-InforcerPolicyName -Policy $dstP
                DestValue      = if ($status -eq 'Matched') { 'Identical' } else { 'Differs' }
                SourceSettings = $srcFlatSettings
                DestSettings   = $dstFlatSettings
            }

            if ($includingAssignments) {
                $row.SourceAssignment = Get-InforcerAssignmentString -Policy $srcP
                $row.DestAssignment   = Get-InforcerAssignmentString -Policy $dstP
            }

            $counters[$status]++
            & $ensureProductCategory $prod $cat
            $products[$prod].Counters[$status]++
            & $addRow $prod $cat $row

        } elseif ($inSrc) {
            # ── Source-only non-SC policy → manual review tab ──
            $srcP = $srcNonSCIndex[$key]
            $prod = & $getProduct $srcP
            $cat  = & $getCategoryKey $srcP
            if ([string]::IsNullOrWhiteSpace($cat)) { $cat = 'General' }
            $policyName = Get-InforcerPolicyName -Policy $srcP

            $flatSettings = @()
            if ($srcP.policyData) { $flatSettings = @(ConvertTo-FlatSettingRows -PolicyData $srcP.policyData) }

            & $ensureManualCategory $prod $cat
            [void]$manualReview[$prod].Categories[$cat].Add(@{
                Environment = 'Source'
                PolicyName  = $policyName
                PolicyType  = & $getPolicyTypeFriendly $srcP
                Category    = $cat
                Reason      = 'Exists only in source tenant'
                Settings    = $flatSettings
            })
            $manualReview[$prod].Count++
            $manualCount++

        } else {
            # ── Dest-only non-SC policy → manual review tab ──
            $dstP = $dstNonSCIndex[$key]
            $prod = & $getProduct $dstP
            $cat  = & $getCategoryKey $dstP
            if ([string]::IsNullOrWhiteSpace($cat)) { $cat = 'General' }
            $policyName = Get-InforcerPolicyName -Policy $dstP

            $flatSettings = @()
            if ($dstP.policyData) { $flatSettings = @(ConvertTo-FlatSettingRows -PolicyData $dstP.policyData) }

            & $ensureManualCategory $prod $cat
            [void]$manualReview[$prod].Categories[$cat].Add(@{
                Environment = 'Destination'
                PolicyName  = $policyName
                PolicyType  = & $getPolicyTypeFriendly $dstP
                Category    = $cat
                Reason      = 'Exists only in destination tenant'
                Settings    = $flatSettings
            })
            $manualReview[$prod].Count++
            $manualCount++
        }
    }

    $counters.Manual = $manualCount

    # ── Alignment score ───────────────────────────────────────────────────
    # Manual review items are excluded from the score
    $totalItems = $counters.Matched + $counters.Conflicting + $counters.SourceOnly + $counters.DestOnly
    $alignmentScore = if ($totalItems -eq 0) { 100 }
                      else { [math]::Round(($counters.Matched / $totalItems) * 100, 1) }

    # ── Return model ──────────────────────────────────────────────────────
    @{
        SourceName           = $ComparisonData.SourceName
        DestinationName      = $ComparisonData.DestinationName
        GeneratedAt          = $ComparisonData.CollectedAt
        AlignmentScore       = $alignmentScore
        TotalItems           = $totalItems
        Counters             = $counters
        Products             = $products
        ManualReview         = $manualReview
        IncludingAssignments = $includingAssignments
    }
}
