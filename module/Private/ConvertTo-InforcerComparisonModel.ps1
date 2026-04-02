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

    # ── Excluded products (non-Intune) ─────────────────────────────────────
    $excludedProducts = @('Microsoft Defender for Office 365', 'Defender for Office 365', 'Microsoft 365')

    $isExcludedProduct = {
        param([string]$ProductName)
        foreach ($ep in $excludedProducts) {
            if ($ProductName -like "*$ep*") { return $true }
        }
        return $false
    }

    # ── Filter to Settings Catalog only (policyTypeId 10) ─────────────────
    $srcSC = [System.Collections.Generic.List[object]]::new()
    $dstSC = [System.Collections.Generic.List[object]]::new()

    foreach ($p in $sourcePolicies) {
        if ($null -eq $p) { continue }
        $prod = $p.product
        if (-not [string]::IsNullOrWhiteSpace($prod) -and (& $isExcludedProduct $prod)) { continue }
        if ($p.policyTypeId -eq 10) { [void]$srcSC.Add($p) }
    }
    foreach ($p in $destPolicies) {
        if ($null -eq $p) { continue }
        $prod = $p.product
        if (-not [string]::IsNullOrWhiteSpace($prod) -and (& $isExcludedProduct $prod)) { continue }
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
    # Non-Settings-Catalog Intune policies with flat JSON can be compared at
    # the policy level by matching on product|primaryGroup|displayName.
    $scProductNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($p in $srcSC) { [void]$scProductNames.Add((& $getProduct $p)) }
    foreach ($p in $dstSC) { [void]$scProductNames.Add((& $getProduct $p)) }

    # Collect non-SC policies from both sides (excluding filtered products)
    $srcNonSC = [System.Collections.Generic.List[object]]::new()
    $dstNonSC = [System.Collections.Generic.List[object]]::new()

    foreach ($p in $sourcePolicies) {
        if ($null -eq $p) { continue }
        if ($p.policyTypeId -eq 10) { continue }
        $prod = & $getProduct $p
        if (-not [string]::IsNullOrWhiteSpace($prod) -and (& $isExcludedProduct $prod)) { continue }
        if (-not $scProductNames.Contains($prod)) { continue }
        [void]$srcNonSC.Add($p)
    }
    foreach ($p in $destPolicies) {
        if ($null -eq $p) { continue }
        if ($p.policyTypeId -eq 10) { continue }
        $prod = & $getProduct $p
        if (-not [string]::IsNullOrWhiteSpace($prod) -and (& $isExcludedProduct $prod)) { continue }
        if (-not $scProductNames.Contains($prod)) { continue }
        [void]$dstNonSC.Add($p)
    }

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
    $matchedNonSCKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($key in $allNonSCKeys) {
        $inSrc = $srcNonSCIndex.ContainsKey($key)
        $inDst = $dstNonSCIndex.ContainsKey($key)

        if ($inSrc -and $inDst) {
            $srcP = $srcNonSCIndex[$key]
            $dstP = $dstNonSCIndex[$key]
            [void]$matchedNonSCKeys.Add($key)

            $prod = & $getProduct $srcP
            $cat  = & $getCategoryKey $srcP
            if ([string]::IsNullOrWhiteSpace($cat)) { $cat = 'General' }
            $policyName = Get-InforcerPolicyName -Policy $srcP

            # Compare policyData as JSON
            $srcJson = if ($srcP.policyData) { $srcP.policyData | ConvertTo-Json -Depth 50 -Compress } else { '' }
            $dstJson = if ($dstP.policyData) { $dstP.policyData | ConvertTo-Json -Depth 50 -Compress } else { '' }

            $status = if ($srcJson -eq $dstJson) { 'Matched' } else { 'Conflicting' }

            $row = @{
                ItemType     = 'Policy'
                Name         = $policyName
                Category     = $cat
                Status       = $status
                SourcePolicy = $policyName
                SourceValue  = if ($status -eq 'Matched') { 'Identical' } else { 'Differs' }
                DestPolicy   = Get-InforcerPolicyName -Policy $dstP
                DestValue    = if ($status -eq 'Matched') { 'Identical' } else { 'Differs' }
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
            $srcP = $srcNonSCIndex[$key]
            $prod = & $getProduct $srcP
            $cat  = & $getCategoryKey $srcP
            if ([string]::IsNullOrWhiteSpace($cat)) { $cat = 'General' }
            $policyName = Get-InforcerPolicyName -Policy $srcP

            $row = @{
                ItemType     = 'Policy'
                Name         = $policyName
                Category     = $cat
                Status       = 'SourceOnly'
                SourcePolicy = $policyName
                SourceValue  = 'Configured'
                DestPolicy   = ''
                DestValue    = ''
            }

            if ($includingAssignments) {
                $row.SourceAssignment = Get-InforcerAssignmentString -Policy $srcP
                $row.DestAssignment   = ''
            }

            $counters.SourceOnly++
            & $ensureProductCategory $prod $cat
            $products[$prod].Counters.SourceOnly++
            & $addRow $prod $cat $row

        } else {
            $dstP = $dstNonSCIndex[$key]
            $prod = & $getProduct $dstP
            $cat  = & $getCategoryKey $dstP
            if ([string]::IsNullOrWhiteSpace($cat)) { $cat = 'General' }
            $policyName = Get-InforcerPolicyName -Policy $dstP

            $row = @{
                ItemType     = 'Policy'
                Name         = $policyName
                Category     = $cat
                Status       = 'DestOnly'
                SourcePolicy = ''
                SourceValue  = ''
                DestPolicy   = $policyName
                DestValue    = 'Configured'
            }

            if ($includingAssignments) {
                $row.SourceAssignment = ''
                $row.DestAssignment   = Get-InforcerAssignmentString -Policy $dstP
            }

            $counters.DestOnly++
            & $ensureProductCategory $prod $cat
            $products[$prod].Counters.DestOnly++
            & $addRow $prod $cat $row
        }
    }

    # ── Manual Review: only truly non-comparable policies ────────────────
    # Policies that could not be matched by the non-SC comparison above
    # (i.e., from products not in the SC product set) are sent to manual review.
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

    foreach ($p in $sourcePolicies) {
        if ($null -eq $p) { continue }
        if ($p.policyTypeId -eq 10) { continue }
        $prod = & $getProduct $p
        if (-not [string]::IsNullOrWhiteSpace($prod) -and (& $isExcludedProduct $prod)) { continue }
        # Skip policies already handled by non-SC comparison
        if ($scProductNames.Contains($prod)) { continue }
        $cat  = & $getCategoryKey $p
        if ([string]::IsNullOrWhiteSpace($cat)) { $cat = 'General' }
        $policyName = Get-InforcerPolicyName -Policy $p

        $flatSettings = @()
        if ($p.policyData) {
            $flatSettings = @(ConvertTo-FlatSettingRows -PolicyData $p.policyData)
        }

        & $ensureManualCategory $prod $cat
        [void]$manualReview[$prod].Categories[$cat].Add(@{
            Environment = 'Source'
            PolicyName  = $policyName
            PolicyType  = & $getPolicyTypeFriendly $p
            Category    = $cat
            Reason      = 'Non-Intune policy — cannot auto-compare'
            Settings    = $flatSettings
        })
        $manualReview[$prod].Count++
        $manualCount++
    }

    foreach ($p in $destPolicies) {
        if ($null -eq $p) { continue }
        if ($p.policyTypeId -eq 10) { continue }
        $prod = & $getProduct $p
        if (-not [string]::IsNullOrWhiteSpace($prod) -and (& $isExcludedProduct $prod)) { continue }
        # Skip policies already handled by non-SC comparison
        if ($scProductNames.Contains($prod)) { continue }
        $cat  = & $getCategoryKey $p
        if ([string]::IsNullOrWhiteSpace($cat)) { $cat = 'General' }
        $policyName = Get-InforcerPolicyName -Policy $p

        $flatSettings = @()
        if ($p.policyData) {
            $flatSettings = @(ConvertTo-FlatSettingRows -PolicyData $p.policyData)
        }

        & $ensureManualCategory $prod $cat
        [void]$manualReview[$prod].Categories[$cat].Add(@{
            Environment = 'Destination'
            PolicyName  = $policyName
            PolicyType  = & $getPolicyTypeFriendly $p
            Category    = $cat
            Reason      = 'Non-Intune policy — cannot auto-compare'
            Settings    = $flatSettings
        })
        $manualReview[$prod].Count++
        $manualCount++
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
