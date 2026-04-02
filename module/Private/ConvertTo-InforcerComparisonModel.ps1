function Test-IsSettingsCatalogPolicy {
    <#
    .SYNOPSIS
        Determines whether a policy is a Settings Catalog policy.
    .DESCRIPTION
        A policy is Settings Catalog if its policyData has a settingDefinitions array
        containing objects with settingInstance.settingDefinitionId properties.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Policy)

    if ($null -eq $Policy.policyData) { return $false }
    $defs = $Policy.policyData.settingDefinitions
    if ($null -eq $defs -or @($defs).Count -eq 0) { return $false }

    foreach ($def in @($defs)) {
        if ($null -ne $def.settingInstance -and
            -not [string]::IsNullOrEmpty($def.settingInstance.settingDefinitionId)) {
            return $true
        }
    }
    return $false
}

function Get-InforcerSettingValue {
    <#
    .SYNOPSIS
        Extracts the comparison value from a settingInstance based on its @odata.type.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$SettingInstance)

    $odataType = $SettingInstance.'@odata.type'

    switch -Wildcard ($odataType) {
        '*choiceSettingInstance' {
            $csv = $SettingInstance.choiceSettingValue
            if ($csv -and $csv.value) { return $csv.value }
            return ''
        }
        '*simpleSettingInstance' {
            $val = $SettingInstance.simpleSettingValue.value
            if ($null -ne $val) { return "$val" }
            return ''
        }
        '*simpleSettingCollectionInstance' {
            $values = @($SettingInstance.simpleSettingCollectionValue | ForEach-Object { $_.value }) -join ', '
            return $values
        }
        '*groupSettingCollectionInstance' {
            # Serialize to JSON for comparison
            return ($SettingInstance.groupSettingCollectionValue | ConvertTo-Json -Depth 100 -Compress)
        }
        '*choiceSettingCollectionInstance' {
            $values = @($SettingInstance.choiceSettingCollectionValue | ForEach-Object { $_.value }) -join ', '
            return $values
        }
        default {
            return ($SettingInstance | ConvertTo-Json -Depth 100 -Compress)
        }
    }
}

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

function Get-InforcerNormalizedPolicyData {
    <#
    .SYNOPSIS
        Returns a normalized JSON string of policyData for comparison, excluding metadata fields.
    #>
    [CmdletBinding()]
    param([Parameter()]$PolicyData)

    if ($null -eq $PolicyData) { return '{}' }

    $skip = @(
        '@odata.type', '@odata.context', 'id', 'createdDateTime', 'lastModifiedDateTime',
        'roleScopeTagIds', 'version', 'templateId', 'displayName', 'description',
        'assignments', 'name', 'deletedDateTime', 'policyGuid'
    )

    $normalized = [ordered]@{}
    foreach ($prop in $PolicyData.PSObject.Properties) {
        if ($prop.Name -in $skip) { continue }
        $normalized[$prop.Name] = $prop.Value
    }

    return ($normalized | ConvertTo-Json -Depth 100 -Compress)
}

function ConvertTo-InforcerComparisonModel {
    <#
    .SYNOPSIS
        Builds a structured comparison model from two sets of policies.
    .DESCRIPTION
        Stage 2 of the Compare-InforcerEnvironments pipeline. Receives raw policy data
        from Stage 1 (Get-InforcerComparisonData) and produces a hierarchical comparison
        model consumed by Stage 3 (HTML/Markdown renderer).

        Uses two strategies:
        - Strategy A (Settings Catalog): Compare at individual settingDefinitionId level
        - Strategy B (everything else): Compare at policy level using match key

        Manual review is triggered when an unmatched non-SC policy exists in a
        product/category area where SC policies also exist (cross-structure ambiguity).
    .PARAMETER ComparisonData
        Hashtable from Get-InforcerComparisonData containing: SourcePolicies,
        DestinationPolicies, SourceName, DestinationName, SourceType, DestinationType,
        SettingsCatalog, IncludingAssignments, CollectedAt.
    .OUTPUTS
        Hashtable representing the ComparisonModel.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ComparisonData
    )

    $sourcePolicies      = @($ComparisonData.SourcePolicies)
    $destPolicies        = @($ComparisonData.DestinationPolicies)
    $settingsCatalog     = $ComparisonData.SettingsCatalog
    $includingAssignments = $ComparisonData.IncludingAssignments

    # ── Classify policies ─────────────────────────────────────────────────
    $srcSC  = [System.Collections.Generic.List[object]]::new()
    $srcNSC = [System.Collections.Generic.List[object]]::new()
    $dstSC  = [System.Collections.Generic.List[object]]::new()
    $dstNSC = [System.Collections.Generic.List[object]]::new()

    foreach ($p in $sourcePolicies) {
        if ($null -eq $p) { continue }
        if (Test-IsSettingsCatalogPolicy -Policy $p) { [void]$srcSC.Add($p) }
        else { [void]$srcNSC.Add($p) }
    }
    foreach ($p in $destPolicies) {
        if ($null -eq $p) { continue }
        if (Test-IsSettingsCatalogPolicy -Policy $p) { [void]$dstSC.Add($p) }
        else { [void]$dstNSC.Add($p) }
    }

    # ── Result containers ─────────────────────────────────────────────────
    $products     = [ordered]@{}
    $manualReview = [ordered]@{}
    $counters     = @{ Matched = 0; Conflicting = 0; SourceOnly = 0; DestOnly = 0; Manual = 0 }

    # Track which product/category areas have SC policies (for manual review detection)
    $scAreas = @{}  # key: "product|category" -> $true

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

    # ── Strategy A: Settings Catalog ──────────────────────────────────────
    # Extract { settingDefinitionId -> { value, policyName, product, category, assignment } }

    $srcSettings = @{}  # key: settingDefinitionId -> hashtable
    $dstSettings = @{}

    foreach ($p in $srcSC) {
        $prod = & $getProduct $p
        $cat  = & $getCategoryKey $p
        if ([string]::IsNullOrWhiteSpace($cat)) { $cat = 'General' }
        $policyName = Get-InforcerPolicyName -Policy $p
        $assignment = if ($includingAssignments) { Get-InforcerAssignmentString -Policy $p } else { '' }
        $areaKey = "$prod|$cat".ToLowerInvariant()
        $scAreas[$areaKey] = $true

        foreach ($def in @($p.policyData.settingDefinitions)) {
            if ($null -eq $def.settingInstance) { continue }
            $defId = $def.settingInstance.settingDefinitionId
            if ([string]::IsNullOrEmpty($defId)) { continue }

            $value = Get-InforcerSettingValue -SettingInstance $def.settingInstance

            # First occurrence wins for each settingDefinitionId
            if (-not $srcSettings.ContainsKey($defId)) {
                $srcSettings[$defId] = @{
                    Value      = $value
                    PolicyName = $policyName
                    Product    = $prod
                    Category   = $cat
                    Assignment = $assignment
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
        $areaKey = "$prod|$cat".ToLowerInvariant()
        $scAreas[$areaKey] = $true

        foreach ($def in @($p.policyData.settingDefinitions)) {
            if ($null -eq $def.settingInstance) { continue }
            $defId = $def.settingInstance.settingDefinitionId
            if ([string]::IsNullOrEmpty($defId)) { continue }

            $value = Get-InforcerSettingValue -SettingInstance $def.settingInstance

            if (-not $dstSettings.ContainsKey($defId)) {
                $dstSettings[$defId] = @{
                    Value      = $value
                    PolicyName = $policyName
                    Product    = $prod
                    Category   = $cat
                    Assignment = $assignment
                }
            }
        }
    }

    # Compare SC settings
    $allDefIds = @($srcSettings.Keys) + @($dstSettings.Keys) | Sort-Object -Unique

    foreach ($defId in $allDefIds) {
        $inSrc = $srcSettings.ContainsKey($defId)
        $inDst = $dstSettings.ContainsKey($defId)

        # Resolve friendly name
        $friendlyName = $defId
        if ($null -ne $settingsCatalog -and $settingsCatalog.Count -gt 0) {
            $entry = $settingsCatalog[$defId]
            if ($null -ne $entry -and $entry.DisplayName) {
                $friendlyName = $entry.DisplayName
            } else {
                $friendlyName = "$defId (unresolved)"
            }
        }

        $row = @{
            ItemType = 'Setting'
            Name     = $friendlyName
        }

        if ($inSrc -and $inDst) {
            $srcInfo = $srcSettings[$defId]
            $dstInfo = $dstSettings[$defId]
            $product  = $srcInfo.Product
            $category = $srcInfo.Category

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

    # ── Strategy B: Non-SC policies ───────────────────────────────────────
    # Build match key: "policyTypeId|product|primaryGroup|displayName" (lowercased)

    $srcNSCMap = [ordered]@{}  # matchKey -> list of policies
    $dstNSCMap = [ordered]@{}

    foreach ($p in $srcNSC) {
        $prod = & $getProduct $p
        $policyName = Get-InforcerPolicyName -Policy $p
        $matchKey = "$($p.policyTypeId)|$prod|$($p.primaryGroup)|$policyName".ToLowerInvariant()
        if (-not $srcNSCMap.Contains($matchKey)) {
            $srcNSCMap[$matchKey] = [System.Collections.Generic.List[object]]::new()
        }
        [void]$srcNSCMap[$matchKey].Add($p)
    }

    foreach ($p in $dstNSC) {
        $prod = & $getProduct $p
        $policyName = Get-InforcerPolicyName -Policy $p
        $matchKey = "$($p.policyTypeId)|$prod|$($p.primaryGroup)|$policyName".ToLowerInvariant()
        if (-not $dstNSCMap.Contains($matchKey)) {
            $dstNSCMap[$matchKey] = [System.Collections.Generic.List[object]]::new()
        }
        [void]$dstNSCMap[$matchKey].Add($p)
    }

    $allMatchKeys = @($srcNSCMap.Keys) + @($dstNSCMap.Keys) | Sort-Object -Unique

    foreach ($matchKey in $allMatchKeys) {
        $inSrc = $srcNSCMap.Contains($matchKey)
        $inDst = $dstNSCMap.Contains($matchKey)

        if ($inSrc -and $inDst) {
            # Matched key — compare policyData
            $srcP = $srcNSCMap[$matchKey][0]
            $dstP = $dstNSCMap[$matchKey][0]
            $prod = & $getProduct $srcP
            $cat  = & $getCategoryKey $srcP
            if ([string]::IsNullOrWhiteSpace($cat)) { $cat = 'General' }
            $policyName = Get-InforcerPolicyName -Policy $srcP

            $srcJson = Get-InforcerNormalizedPolicyData -PolicyData $srcP.policyData
            $dstJson = Get-InforcerNormalizedPolicyData -PolicyData $dstP.policyData

            $row = @{
                ItemType     = 'Policy'
                Name         = $policyName
                SourcePolicy = $policyName
                DestPolicy   = (Get-InforcerPolicyName -Policy $dstP)
                SourceValue  = $srcJson
                DestValue    = $dstJson
            }

            if ($includingAssignments) {
                $row.SourceAssignment = Get-InforcerAssignmentString -Policy $srcP
                $row.DestAssignment   = Get-InforcerAssignmentString -Policy $dstP
            }

            if ($srcJson -eq $dstJson) {
                $row.Status = 'Matched'
                $counters.Matched++
                & $ensureProductCategory $prod $cat
                $products[$prod].Counters.Matched++
            } else {
                $row.Status = 'Conflicting'
                $counters.Conflicting++
                & $ensureProductCategory $prod $cat
                $products[$prod].Counters.Conflicting++
            }
            & $addRow $prod $cat $row

        } elseif ($inSrc) {
            # Source-only: check for manual review
            $srcP = $srcNSCMap[$matchKey][0]
            $prod = & $getProduct $srcP
            $cat  = & $getCategoryKey $srcP
            if ([string]::IsNullOrWhiteSpace($cat)) { $cat = 'General' }
            $policyName = Get-InforcerPolicyName -Policy $srcP
            $areaKey = "$prod|$cat".ToLowerInvariant()

            if ($scAreas.ContainsKey($areaKey)) {
                # Manual review: unmatched non-SC in area with SC policies
                $counters.Manual++
                if (-not $manualReview.Contains($prod)) {
                    $manualReview[$prod] = @{
                        Count      = 0
                        Categories = [ordered]@{}
                    }
                }
                $manualReview[$prod].Count++
                if (-not $manualReview[$prod].Categories.Contains($cat)) {
                    $manualReview[$prod].Categories[$cat] = [System.Collections.Generic.List[object]]::new()
                }
                [void]$manualReview[$prod].Categories[$cat].Add(@{
                    Environment = 'Source'
                    PolicyName  = $policyName
                    PolicyType  = $srcP.inforcerPolicyTypeName
                    Reason      = 'Unmatched non-SC policy in area with Settings Catalog policies'
                })
            } else {
                $row = @{
                    ItemType     = 'Policy'
                    Name         = $policyName
                    Status       = 'SourceOnly'
                    SourcePolicy = $policyName
                    SourceValue  = (Get-InforcerNormalizedPolicyData -PolicyData $srcP.policyData)
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
            }

        } else {
            # Dest-only: check for manual review
            $dstP = $dstNSCMap[$matchKey][0]
            $prod = & $getProduct $dstP
            $cat  = & $getCategoryKey $dstP
            if ([string]::IsNullOrWhiteSpace($cat)) { $cat = 'General' }
            $policyName = Get-InforcerPolicyName -Policy $dstP
            $areaKey = "$prod|$cat".ToLowerInvariant()

            if ($scAreas.ContainsKey($areaKey)) {
                # Manual review
                $counters.Manual++
                if (-not $manualReview.Contains($prod)) {
                    $manualReview[$prod] = @{
                        Count      = 0
                        Categories = [ordered]@{}
                    }
                }
                $manualReview[$prod].Count++
                if (-not $manualReview[$prod].Categories.Contains($cat)) {
                    $manualReview[$prod].Categories[$cat] = [System.Collections.Generic.List[object]]::new()
                }
                [void]$manualReview[$prod].Categories[$cat].Add(@{
                    Environment = 'Destination'
                    PolicyName  = $policyName
                    PolicyType  = $dstP.inforcerPolicyTypeName
                    Reason      = 'Unmatched non-SC policy in area with Settings Catalog policies'
                })
            } else {
                $row = @{
                    ItemType     = 'Policy'
                    Name         = $policyName
                    Status       = 'DestOnly'
                    SourcePolicy = ''
                    SourceValue  = ''
                    DestPolicy   = $policyName
                    DestValue    = (Get-InforcerNormalizedPolicyData -PolicyData $dstP.policyData)
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
    }

    # ── Alignment score ───────────────────────────────────────────────────
    $totalItems = $counters.Matched + $counters.Conflicting + $counters.SourceOnly + $counters.DestOnly
    $alignmentScore = if ($totalItems -eq 0) { 100 }
                      else { [math]::Round(($counters.Matched / $totalItems) * 100) }

    # ── Return model ──────────────────────────────────────────────────────
    @{
        SourceName           = $ComparisonData.SourceName
        DestinationName      = $ComparisonData.DestinationName
        SourceType           = $ComparisonData.SourceType
        DestinationType      = $ComparisonData.DestinationType
        GeneratedAt          = $ComparisonData.CollectedAt
        AlignmentScore       = $alignmentScore
        TotalItems           = $totalItems
        Counters             = $counters
        Products             = $products
        ManualReview         = $manualReview
        IncludingAssignments = $includingAssignments
    }
}
