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

        Compares all policy types at the individual setting level:
        - Settings Catalog (policyTypeId 10): extracts via ConvertTo-InforcerSettingRows
        - Non-SC policies: extracts via ConvertTo-FlatSettingRows
        - Matches by setting name/definition across source and destination
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

    # ── Filter SC policies by excluded categories (Fix 1) ─────────────────
    $filteredSrcSC = [System.Collections.Generic.List[object]]::new()
    $filteredDstSC = [System.Collections.Generic.List[object]]::new()
    foreach ($p in $srcSC) {
        $catKey = & $getCategoryKey $p
        if (& $isExcludedCategory $catKey) { continue }
        [void]$filteredSrcSC.Add($p)
    }
    foreach ($p in $dstSC) {
        $catKey = & $getCategoryKey $p
        if (& $isExcludedCategory $catKey) { continue }
        [void]$filteredDstSC.Add($p)
    }
    $srcSC = $filteredSrcSC
    $dstSC = $filteredDstSC

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

    # ── Extract settings from SC policies (Fix 3: capture ALL rows) ───────
    # Build: uniqueKey -> { FriendlyName, Value, PolicyName, Product, Category, Assignment }
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

                # Get ALL rows from ConvertTo-InforcerSettingRows (handles group settings like ASR rules)
                $rows = @(ConvertTo-InforcerSettingRows -SettingInstance $settingGroup.settingInstance)
                $configuredRows = @($rows | Where-Object { $_.IsConfigured -eq $true })

                if ($configuredRows.Count -eq 0) {
                    # No configured rows — use defId as fallback
                    $friendlyName = if ($rows.Count -gt 0) { $rows[0].Name } else { $defId }
                    $uniqueKey = $defId
                    if (-not $srcSettings.ContainsKey($uniqueKey)) {
                        $srcSettings[$uniqueKey] = @{
                            FriendlyName = $friendlyName
                            Value        = ''
                            PolicyName   = $policyName
                            Product      = $prod
                            Category     = $cat
                            Assignment   = $assignment
                        }
                    }
                } elseif ($configuredRows.Count -eq 1) {
                    # Single configured row — use defId as key
                    $cr = $configuredRows[0]
                    $uniqueKey = $defId
                    if (-not $srcSettings.ContainsKey($uniqueKey)) {
                        $srcSettings[$uniqueKey] = @{
                            FriendlyName = $cr.Name
                            Value        = "$($cr.Value)"
                            PolicyName   = $policyName
                            Product      = $prod
                            Category     = $cat
                            Assignment   = $assignment
                        }
                    }
                } else {
                    # Multiple configured rows (group settings like ASR rules)
                    # Add each as a separate entry with composite key
                    $rowIdx = 0
                    foreach ($cr in $configuredRows) {
                        $uniqueKey = "${defId}_${rowIdx}_$($cr.Name)"
                        if (-not $srcSettings.ContainsKey($uniqueKey)) {
                            $srcSettings[$uniqueKey] = @{
                                FriendlyName = $cr.Name
                                Value        = "$($cr.Value)"
                                PolicyName   = $policyName
                                Product      = $prod
                                Category     = $cat
                                Assignment   = $assignment
                            }
                        }
                        $rowIdx++
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
                $configuredRows = @($rows | Where-Object { $_.IsConfigured -eq $true })

                if ($configuredRows.Count -eq 0) {
                    $friendlyName = if ($rows.Count -gt 0) { $rows[0].Name } else { $defId }
                    $uniqueKey = $defId
                    if (-not $dstSettings.ContainsKey($uniqueKey)) {
                        $dstSettings[$uniqueKey] = @{
                            FriendlyName = $friendlyName
                            Value        = ''
                            PolicyName   = $policyName
                            Product      = $prod
                            Category     = $cat
                            Assignment   = $assignment
                        }
                    }
                } elseif ($configuredRows.Count -eq 1) {
                    $cr = $configuredRows[0]
                    $uniqueKey = $defId
                    if (-not $dstSettings.ContainsKey($uniqueKey)) {
                        $dstSettings[$uniqueKey] = @{
                            FriendlyName = $cr.Name
                            Value        = "$($cr.Value)"
                            PolicyName   = $policyName
                            Product      = $prod
                            Category     = $cat
                            Assignment   = $assignment
                        }
                    }
                } else {
                    $rowIdx = 0
                    foreach ($cr in $configuredRows) {
                        $uniqueKey = "${defId}_${rowIdx}_$($cr.Name)"
                        if (-not $dstSettings.ContainsKey($uniqueKey)) {
                            $dstSettings[$uniqueKey] = @{
                                FriendlyName = $cr.Name
                                Value        = "$($cr.Value)"
                                PolicyName   = $policyName
                                Product      = $prod
                                Category     = $cat
                                Assignment   = $assignment
                            }
                        }
                        $rowIdx++
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

    # ── Setting-level comparison for non-SC policies (Fix 2) ─────────────
    # Non-Settings-Catalog policies are now compared at the individual setting
    # level using ConvertTo-FlatSettingRows, just like SC policies.

    # Metadata properties to skip when comparing non-SC settings
    $metadataSkipNames = @(
        '@odata.type', '@odata.context', 'id', 'createdDateTime', 'lastModifiedDateTime',
        'roleScopeTagIds', 'version', 'templateId', 'displayName', 'description',
        'assignments', 'settings', 'name', 'deletedDateTime', 'policyGuid'
    )

    # Build match key: product|primaryGroup|displayName (lowercased)
    $buildMatchKey = {
        param($Policy)
        $prod = (& $getProduct $Policy).ToLowerInvariant()
        $pg = if ($Policy.primaryGroup) { $Policy.primaryGroup.ToLowerInvariant() } else { '' }
        $dn = (Get-InforcerPolicyName -Policy $Policy).ToLowerInvariant()
        return "$prod|$pg|$dn"
    }

    # Helper: extract flat settings from a non-SC policy, filtered and as a name->value lookup
    $getNonSCSettingLookup = {
        param($PolicyData)
        $lookup = @{}
        if ($null -eq $PolicyData) { return $lookup }
        $flatRows = @(ConvertTo-FlatSettingRows -PolicyData $PolicyData)
        foreach ($r in $flatRows) {
            if ($r.IsConfigured -ne $true) { continue }
            if ($r.Name -like '*@odata*') { continue }
            if ($r.Name -in $metadataSkipNames) { continue }
            # Use name as key; handle duplicates by appending index
            $key = $r.Name
            if ($lookup.ContainsKey($key)) {
                $idx = 2
                while ($lookup.ContainsKey("${key} ($idx)")) { $idx++ }
                $key = "${key} ($idx)"
            }
            $lookup[$key] = [string]$r.Value
        }
        return $lookup
    }

    # Helper: add setting-level rows for a non-SC policy pair or single policy
    $addNonSCSettingRows = {
        param(
            [string]$Product,
            [string]$Category,
            [string]$SrcPolicyName,
            [string]$DstPolicyName,
            [string]$SrcAssignment,
            [string]$DstAssignment,
            [hashtable]$SrcLookup,
            [hashtable]$DstLookup
        )
        $allNames = @(@($SrcLookup.Keys) + @($DstLookup.Keys)) | Sort-Object -Unique
        foreach ($settingName in $allNames) {
            $inS = $SrcLookup.ContainsKey($settingName)
            $inD = $DstLookup.ContainsKey($settingName)
            $sVal = if ($inS) { $SrcLookup[$settingName] } else { '' }
            $dVal = if ($inD) { $DstLookup[$settingName] } else { '' }

            $settingRow = @{
                ItemType     = 'Setting'
                Name         = $settingName
                Category     = $Category
                SourcePolicy = $SrcPolicyName
                DestPolicy   = $DstPolicyName
            }

            if ($includingAssignments) {
                $settingRow.SourceAssignment = $SrcAssignment
                $settingRow.DestAssignment   = $DstAssignment
            }

            if ($inS -and $inD) {
                $settingRow.SourceValue = $sVal
                $settingRow.DestValue   = $dVal
                if ($sVal -eq $dVal) {
                    $settingRow.Status = 'Matched'
                    $counters.Matched++
                    & $ensureProductCategory $Product $Category
                    $products[$Product].Counters.Matched++
                } else {
                    $settingRow.Status = 'Conflicting'
                    $counters.Conflicting++
                    & $ensureProductCategory $Product $Category
                    $products[$Product].Counters.Conflicting++
                }
            } elseif ($inS) {
                $settingRow.SourceValue = $sVal
                $settingRow.DestValue   = ''
                $settingRow.Status      = 'SourceOnly'
                $counters.SourceOnly++
                & $ensureProductCategory $Product $Category
                $products[$Product].Counters.SourceOnly++
            } else {
                $settingRow.SourceValue = ''
                $settingRow.DestValue   = $dVal
                $settingRow.Status      = 'DestOnly'
                $counters.DestOnly++
                & $ensureProductCategory $Product $Category
                $products[$Product].Counters.DestOnly++
            }

            & $addRow $Product $Category $settingRow
        }
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

    foreach ($key in $allNonSCKeys) {
        $inSrc = $srcNonSCIndex.ContainsKey($key)
        $inDst = $dstNonSCIndex.ContainsKey($key)

        if ($inSrc -and $inDst) {
            # ── Matched pair → setting-level comparison ──
            $srcP = $srcNonSCIndex[$key]
            $dstP = $dstNonSCIndex[$key]

            $prod = & $getProduct $srcP
            $cat  = & $getCategoryKey $srcP
            if ([string]::IsNullOrWhiteSpace($cat)) { $cat = 'General' }
            $srcPolicyName = Get-InforcerPolicyName -Policy $srcP
            $dstPolicyName = Get-InforcerPolicyName -Policy $dstP
            $srcAssign = if ($includingAssignments) { Get-InforcerAssignmentString -Policy $srcP } else { '' }
            $dstAssign = if ($includingAssignments) { Get-InforcerAssignmentString -Policy $dstP } else { '' }

            $srcLookup = & $getNonSCSettingLookup $srcP.policyData
            $dstLookup = & $getNonSCSettingLookup $dstP.policyData

            & $addNonSCSettingRows $prod $cat $srcPolicyName $dstPolicyName $srcAssign $dstAssign $srcLookup $dstLookup

        } elseif ($inSrc) {
            # ── Source-only non-SC policy → all settings as SourceOnly ──
            $srcP = $srcNonSCIndex[$key]
            $prod = & $getProduct $srcP
            $cat  = & $getCategoryKey $srcP
            if ([string]::IsNullOrWhiteSpace($cat)) { $cat = 'General' }
            $srcPolicyName = Get-InforcerPolicyName -Policy $srcP
            $srcAssign = if ($includingAssignments) { Get-InforcerAssignmentString -Policy $srcP } else { '' }

            $srcLookup = & $getNonSCSettingLookup $srcP.policyData
            $emptyLookup = @{}

            & $addNonSCSettingRows $prod $cat $srcPolicyName '' $srcAssign '' $srcLookup $emptyLookup

        } else {
            # ── Dest-only non-SC policy → all settings as DestOnly ──
            $dstP = $dstNonSCIndex[$key]
            $prod = & $getProduct $dstP
            $cat  = & $getCategoryKey $dstP
            if ([string]::IsNullOrWhiteSpace($cat)) { $cat = 'General' }
            $dstPolicyName = Get-InforcerPolicyName -Policy $dstP
            $dstAssign = if ($includingAssignments) { Get-InforcerAssignmentString -Policy $dstP } else { '' }

            $emptyLookup = @{}
            $dstLookup = & $getNonSCSettingLookup $dstP.policyData

            & $addNonSCSettingRows $prod $cat '' $dstPolicyName '' $dstAssign $emptyLookup $dstLookup
        }
    }

    # ── Alignment score ───────────────────────────────────────────────────
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
        ManualReview         = [ordered]@{}
        IncludingAssignments = $includingAssignments
    }
}
