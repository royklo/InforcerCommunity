function Compare-InforcerDocModels {
    <#
    .SYNOPSIS
        Compares two DocModels and produces a ComparisonModel with setting-level diff rows.
    .DESCRIPTION
        Core diff engine for the Compare-InforcerEnvironments pipeline rewrite.
        Walks two DocModels (which have identical structure: Products -> Categories -> Policies ->
        Settings) and produces comparison rows by matching policies by name within the same
        product/category.

        Key behaviors:
        - Child settings show, parent group headers (IsConfigured=$false) do not
        - Both-empty settings are skipped (no noise rows)
        - "Onboarding blob from Connector" is always excluded (unique per tenant)
        - Duplicate setting names are disambiguated via parent > child paths
        - Source-only/Dest-only with empty value are skipped
        - App protection policies scoped to appGroupType level (no individual app IDs)
    .PARAMETER SourceModel
        DocModel hashtable for the source tenant (from ConvertTo-InforcerDocModel).
    .PARAMETER DestinationModel
        DocModel hashtable for the destination tenant (from ConvertTo-InforcerDocModel).
    .PARAMETER IncludingAssignments
        When true, populates SourceAssignment and DestAssignment on each comparison row.
    .OUTPUTS
        Hashtable representing the ComparisonModel consumed by ConvertTo-InforcerComparisonHtml.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$SourceModel,

        [Parameter(Mandatory)]
        [hashtable]$DestinationModel,

        [Parameter()]
        [switch]$IncludingAssignments
    )

    # ── Result containers ─────────────────────────────────────────────────
    $products = [ordered]@{}
    $counters = @{ Matched = 0; Conflicting = 0; SourceOnly = 0; DestOnly = 0 }

    # ── Noise exclusion patterns ──────────────────────────────────────────
    $excludedSettingNames = @(
        'Onboarding blob from Connector'
        'Onboarding Blob'
    )

    # App protection: settings that enumerate individual app IDs (noise)
    $appIdSettingPatterns = @(
        '^bundleId$'
        '^packageId$'
        'apps\[\d+\]'
        '^apps$'
        '^approvedKeyboards$'
    )

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

    # ── Helper: add comparison row and update counters ────────────────────
    $addRow = {
        param([string]$Product, [string]$Category, [hashtable]$Row)
        & $ensureProductCategory $Product $Category
        [void]$products[$Product].Categories[$Category].ComparisonRows.Add($Row)
        $status = $Row.Status
        $counters[$status]++
        $products[$Product].Counters[$status]++
    }

    # ── Helper: check if a setting name should be excluded ────────────────
    $isExcludedSetting = {
        param([string]$Name)
        foreach ($excluded in $excludedSettingNames) {
            if ($Name -eq $excluded) { return $true }
        }
        foreach ($pattern in $appIdSettingPatterns) {
            if ($Name -match $pattern) { return $true }
        }
        return $false
    }

    # ── Helper: build setting paths from the Indent hierarchy ─────────────
    # Walks the Settings array and returns a list of hashtables:
    #   @{ Name = 'display name'; SettingPath = 'Parent > Child'; Value = '...' }
    # Only configured settings (IsConfigured=$true) are returned.
    # Parent headers (IsConfigured=$false) are tracked for path building only.
    $buildSettingPaths = {
        param([array]$Settings)

        $result = [System.Collections.Generic.List[object]]::new()
        if ($null -eq $Settings -or $Settings.Count -eq 0) { return $result }

        # Parent stack: list of parent names indexed by indent level
        # parentStack[0] = name of indent-0 parent, parentStack[1] = indent-1 parent, etc.
        $parentStack = [System.Collections.Generic.List[string]]::new()

        foreach ($setting in $Settings) {
            $indent = if ($null -ne $setting.Indent) { [int]$setting.Indent } else { 0 }
            $name   = "$($setting.Name)"
            $value  = "$($setting.Value)"
            $isConfigured = $setting.IsConfigured -eq $true

            if (-not $isConfigured) {
                # Group header — update parent stack at this indent level
                # Trim stack to current indent level, then set this as the parent
                while ($parentStack.Count -gt $indent) {
                    $parentStack.RemoveAt($parentStack.Count - 1)
                }
                [void]$parentStack.Add($name)
            } else {
                # Configured setting — build path from parent stack + this name
                # Trim stack to current indent level (in case indent jumped)
                while ($parentStack.Count -gt $indent) {
                    $parentStack.RemoveAt($parentStack.Count - 1)
                }

                # Build the full path
                if ($parentStack.Count -gt 0) {
                    $pathParts = @($parentStack) + @($name)
                    $settingPath = $pathParts -join ' > '
                } else {
                    $settingPath = $name
                }

                [void]$result.Add(@{
                    Name        = $name
                    SettingPath = $settingPath
                    Value       = $value
                })
            }
        }

        return $result
    }

    # ── Helper: build a lookup from setting paths ─────────────────────────
    # Returns hashtable keyed by SettingPath -> @{ Name; Value; SettingPath }
    $buildSettingLookup = {
        param([array]$Settings)
        $paths = & $buildSettingPaths $Settings
        $lookup = [ordered]@{}
        foreach ($p in $paths) {
            $key = $p.SettingPath
            # Skip excluded settings
            if (& $isExcludedSetting $p.Name) { continue }
            if (& $isExcludedSetting $key) { continue }
            # Skip structural array count rows (e.g., "40 items")
            if ($p.Value -match '^\d+ items$') { continue }

            # Handle duplicate paths (shouldn't normally happen with proper path building)
            if ($lookup.Contains($key)) {
                $idx = 2
                while ($lookup.Contains("${key} ($idx)")) { $idx++ }
                $key = "${key} ($idx)"
            }
            $lookup[$key] = $p
        }
        return $lookup
    }

    # ── Helper: format assignment string from DocModel assignments ────────
    $formatAssignment = {
        param([array]$Assignments)
        Format-InforcerAssignmentString -Assignments $Assignments
    }

    # ── Helper: check if value is empty/not-configured ────────────────────
    $isEmptyValue = {
        param([string]$Val)
        return ([string]::IsNullOrWhiteSpace($Val) -or $Val -eq 'Not configured' -or $Val -eq 'Not Configured')
    }

    # ── Collect all products from both models ─────────────────────────────
    $allProducts = [System.Collections.Generic.List[string]]::new()
    if ($SourceModel.Products) {
        foreach ($k in $SourceModel.Products.Keys) {
            if (-not $allProducts.Contains($k)) { [void]$allProducts.Add($k) }
        }
    }
    if ($DestinationModel.Products) {
        foreach ($k in $DestinationModel.Products.Keys) {
            if (-not $allProducts.Contains($k)) { [void]$allProducts.Add($k) }
        }
    }

    foreach ($productName in $allProducts) {
        $srcProduct = if ($SourceModel.Products -and $SourceModel.Products.Contains($productName)) {
            $SourceModel.Products[$productName]
        } else { $null }
        $dstProduct = if ($DestinationModel.Products -and $DestinationModel.Products.Contains($productName)) {
            $DestinationModel.Products[$productName]
        } else { $null }

        # Collect all categories from both sides
        $allCategories = [System.Collections.Generic.List[string]]::new()
        if ($srcProduct -and $srcProduct.Categories) {
            foreach ($k in $srcProduct.Categories.Keys) {
                if (-not $allCategories.Contains($k)) { [void]$allCategories.Add($k) }
            }
        }
        if ($dstProduct -and $dstProduct.Categories) {
            foreach ($k in $dstProduct.Categories.Keys) {
                if (-not $allCategories.Contains($k)) { [void]$allCategories.Add($k) }
            }
        }

        foreach ($categoryName in $allCategories) {
            $srcPolicies = @()
            $dstPolicies = @()
            if ($srcProduct -and $srcProduct.Categories -and $srcProduct.Categories.Contains($categoryName)) {
                $srcPolicies = @($srcProduct.Categories[$categoryName])
            }
            if ($dstProduct -and $dstProduct.Categories -and $dstProduct.Categories.Contains($categoryName)) {
                $dstPolicies = @($dstProduct.Categories[$categoryName])
            }

            $categoryLabel = "$productName / $categoryName"

            # ── Match policies by Basics.Name (case-insensitive) ──────────
            # Build lookup: lowered name -> list of policies (handle duplicates)
            $srcPolicyIndex = [ordered]@{}
            foreach ($p in $srcPolicies) {
                if ($null -eq $p -or $null -eq $p.Basics) { continue }
                $key = $p.Basics.Name.ToLowerInvariant()
                if (-not $srcPolicyIndex.Contains($key)) {
                    $srcPolicyIndex[$key] = [System.Collections.Generic.List[object]]::new()
                }
                [void]$srcPolicyIndex[$key].Add($p)
            }
            $dstPolicyIndex = [ordered]@{}
            foreach ($p in $dstPolicies) {
                if ($null -eq $p -or $null -eq $p.Basics) { continue }
                $key = $p.Basics.Name.ToLowerInvariant()
                if (-not $dstPolicyIndex.Contains($key)) {
                    $dstPolicyIndex[$key] = [System.Collections.Generic.List[object]]::new()
                }
                [void]$dstPolicyIndex[$key].Add($p)
            }

            # All unique policy name keys
            $allPolicyKeys = [System.Collections.Generic.List[string]]::new()
            foreach ($k in $srcPolicyIndex.Keys) {
                if (-not $allPolicyKeys.Contains($k)) { [void]$allPolicyKeys.Add($k) }
            }
            foreach ($k in $dstPolicyIndex.Keys) {
                if (-not $allPolicyKeys.Contains($k)) { [void]$allPolicyKeys.Add($k) }
            }

            foreach ($policyKey in $allPolicyKeys) {
                $hasSrc = $srcPolicyIndex.Contains($policyKey)
                $hasDst = $dstPolicyIndex.Contains($policyKey)

                if ($hasSrc -and $hasDst) {
                    # ── Matched policy pair — compare settings ────────────
                    # Take first policy from each side (index 0)
                    $srcPolicy = $srcPolicyIndex[$policyKey][0]
                    $dstPolicy = $dstPolicyIndex[$policyKey][0]

                    $srcPolicyName = $srcPolicy.Basics.Name
                    $dstPolicyName = $dstPolicy.Basics.Name
                    $srcAssignStr  = if ($IncludingAssignments) { & $formatAssignment $srcPolicy.Assignments } else { '' }
                    $dstAssignStr  = if ($IncludingAssignments) { & $formatAssignment $dstPolicy.Assignments } else { '' }

                    $srcLookup = & $buildSettingLookup $srcPolicy.Settings
                    $dstLookup = & $buildSettingLookup $dstPolicy.Settings

                    # Collect all setting paths
                    $allSettingPaths = [System.Collections.Generic.List[string]]::new()
                    foreach ($k in $srcLookup.Keys) {
                        if (-not $allSettingPaths.Contains($k)) { [void]$allSettingPaths.Add($k) }
                    }
                    foreach ($k in $dstLookup.Keys) {
                        if (-not $allSettingPaths.Contains($k)) { [void]$allSettingPaths.Add($k) }
                    }

                    foreach ($settingPath in $allSettingPaths) {
                        $inSrc = $srcLookup.Contains($settingPath)
                        $inDst = $dstLookup.Contains($settingPath)
                        $srcVal = if ($inSrc) { $srcLookup[$settingPath].Value } else { '' }
                        $dstVal = if ($inDst) { $dstLookup[$settingPath].Value } else { '' }
                        $displayName = if ($inSrc) { $srcLookup[$settingPath].Name } else { $dstLookup[$settingPath].Name }

                        # Skip if both values are empty/not-configured
                        if ((& $isEmptyValue $srcVal) -and (& $isEmptyValue $dstVal)) { continue }

                        # Determine status
                        if ($inSrc -and $inDst) {
                            $status = if ($srcVal -eq $dstVal) { 'Matched' } else { 'Conflicting' }
                        } elseif ($inSrc) {
                            # Source-only: skip if value is empty
                            if (& $isEmptyValue $srcVal) { continue }
                            $status = 'SourceOnly'
                        } else {
                            # Dest-only: skip if value is empty
                            if (& $isEmptyValue $dstVal) { continue }
                            $status = 'DestOnly'
                        }

                        $row = @{
                            ItemType     = 'Setting'
                            Name         = $displayName
                            SettingPath  = $settingPath
                            Category     = $categoryLabel
                            Status       = $status
                            SourcePolicy = $srcPolicyName
                            SourceValue  = $srcVal
                            DestPolicy   = $dstPolicyName
                            DestValue    = $dstVal
                        }
                        if ($IncludingAssignments) {
                            $row.SourceAssignment = $srcAssignStr
                            $row.DestAssignment   = $dstAssignStr
                        }

                        & $addRow $productName $categoryName $row
                    }

                } elseif ($hasSrc) {
                    # ── Source-only policies ───────────────────────────────
                    foreach ($srcPolicy in $srcPolicyIndex[$policyKey]) {
                        $srcPolicyName = $srcPolicy.Basics.Name
                        $srcAssignStr  = if ($IncludingAssignments) { & $formatAssignment $srcPolicy.Assignments } else { '' }
                        $srcLookup = & $buildSettingLookup $srcPolicy.Settings

                        foreach ($settingPath in $srcLookup.Keys) {
                            $srcVal = $srcLookup[$settingPath].Value
                            # Skip empty source-only settings
                            if (& $isEmptyValue $srcVal) { continue }

                            $row = @{
                                ItemType     = 'Setting'
                                Name         = $srcLookup[$settingPath].Name
                                SettingPath  = $settingPath
                                Category     = $categoryLabel
                                Status       = 'SourceOnly'
                                SourcePolicy = $srcPolicyName
                                SourceValue  = $srcVal
                                DestPolicy   = ''
                                DestValue    = ''
                            }
                            if ($IncludingAssignments) {
                                $row.SourceAssignment = $srcAssignStr
                                $row.DestAssignment   = ''
                            }

                            & $addRow $productName $categoryName $row
                        }
                    }

                } else {
                    # ── Dest-only policies ────────────────────────────────
                    foreach ($dstPolicy in $dstPolicyIndex[$policyKey]) {
                        $dstPolicyName = $dstPolicy.Basics.Name
                        $dstAssignStr  = if ($IncludingAssignments) { & $formatAssignment $dstPolicy.Assignments } else { '' }
                        $dstLookup = & $buildSettingLookup $dstPolicy.Settings

                        foreach ($settingPath in $dstLookup.Keys) {
                            $dstVal = $dstLookup[$settingPath].Value
                            # Skip empty dest-only settings
                            if (& $isEmptyValue $dstVal) { continue }

                            $row = @{
                                ItemType     = 'Setting'
                                Name         = $dstLookup[$settingPath].Name
                                SettingPath  = $settingPath
                                Category     = $categoryLabel
                                Status       = 'DestOnly'
                                SourcePolicy = ''
                                SourceValue  = ''
                                DestPolicy   = $dstPolicyName
                                DestValue    = $dstVal
                            }
                            if ($IncludingAssignments) {
                                $row.SourceAssignment = ''
                                $row.DestAssignment   = $dstAssignStr
                            }

                            & $addRow $productName $categoryName $row
                        }
                    }
                }
            }
        }
    }

    # ── Alignment score ───────────────────────────────────────────────────
    $totalItems = $counters.Matched + $counters.Conflicting + $counters.SourceOnly + $counters.DestOnly
    $alignmentScore = if ($totalItems -eq 0) { 100 }
                      else { [math]::Round(($counters.Matched / $totalItems) * 100, 1) }

    # ── Return ComparisonModel ────────────────────────────────────────────
    @{
        SourceName           = $SourceModel.TenantName
        DestinationName      = $DestinationModel.TenantName
        GeneratedAt          = [datetime]::UtcNow
        AlignmentScore       = $alignmentScore
        TotalItems           = $totalItems
        Counters             = $counters
        Products             = $products
        IncludingAssignments = [bool]$IncludingAssignments
    }
}
