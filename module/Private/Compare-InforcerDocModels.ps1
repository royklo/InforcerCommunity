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
        [switch]$IncludingAssignments,

        [Parameter()]
        [switch]$IgnoreUnassignedPolicies,

        [Parameter()]
        [string[]]$ExcludeOS,

        [Parameter()]
        [string]$PolicyNameFilter
    )

    # ── Result containers ─────────────────────────────────────────────────
    $products = [ordered]@{}
    $counters = @{ Matched = 0; Conflicting = 0; SourceOnly = 0; DestOnly = 0 }

    # ── Noise exclusion patterns ──────────────────────────────────────────
    $excludedSettingNames = @(
        'Onboarding blob from Connector'
        'Onboarding Blob'
        'Tenant Id'
        'Tenant Id (Device)'
    )

    # App protection: settings that enumerate individual app IDs (noise)
    # Also filter @odata metadata that leaks through non-SC policies
    $appIdSettingPatterns = @(
        '^bundleId$'
        '^packageId$'
        'apps\[\d+\]'
        '^apps$'
        '^approvedKeyboards$'
        '@odata\.'
        '^tenant\s*id'
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
        # Note: unresolved settingDefinitionIds now get cleaned names in Resolve-InforcerSettingName
        # so they pass through with readable labels like "Excel > Security > Vba Warnings Policy"
        return $false
    }

    # ── Known ADMX app codes for disambiguation ──────────────────────────
    $admxAppCodes = @{
        'excel16v2' = 'Excel'; 'excel16v8' = 'Excel'; 'word16v2' = 'Word'
        'ppt16v2' = 'PowerPoint'; 'access16v2' = 'Access'; 'outlk16v2' = 'Outlook'
        'visio16v2' = 'Visio'; 'proj16v2' = 'Project'; 'pub16v2' = 'Publisher'
        'onent16v2' = 'OneNote'; 'office16v2' = 'Office'; 'office16v8' = 'Office'
    }

    # ── Helper: resolve context name from catalog + defId for disambiguation ─
    $getCategoryName = {
        param([string]$DefId)
        if ([string]::IsNullOrEmpty($DefId)) { return '' }

        $catName = ''
        if ($null -ne $script:InforcerSettingsCatalog -and $script:InforcerSettingsCatalog.ContainsKey($DefId)) {
            $catName = $script:InforcerSettingsCatalog[$DefId].CategoryName
        }

        # Extract app name from ADMX defId (excel16v2, word16v2, etc.)
        $appName = ''
        $stripped = $DefId -replace '^(user|device)_vendor_msft_policy_config_', ''
        foreach ($code in $admxAppCodes.Keys) {
            if ($stripped -match "^${code}[~_]") { $appName = $admxAppCodes[$code]; break }
        }

        # Combine: "App > Category" or just "App" or just "Category"
        if ($appName -and $catName) { return "$appName > $catName" }
        if ($appName) { return $appName }
        if ($catName) { return $catName }

        # Fallback: extract profile/zone context from defId pattern
        if ($DefId -match '_(?:domainprofile|privateprofile|publicprofile)_') {
            $profile = $Matches[0].Trim('_')
            $display = switch ($profile) {
                'domainprofile'  { 'Domain Profile' }
                'privateprofile' { 'Private Profile' }
                'publicprofile'  { 'Public Profile' }
            }
            return $display
        }
        return ''
    }

    # ── Helper: build setting paths from the Indent hierarchy ─────────────
    # Walks the Settings array and returns a list of hashtables:
    #   @{ Name; SettingPath; Value; DefinitionId }
    # Only configured settings (IsConfigured=$true) are returned.
    # Parent headers (IsConfigured=$false) are tracked for path building only.
    $buildSettingPaths = {
        param([array]$Settings)

        $result = [System.Collections.Generic.List[object]]::new()
        if ($null -eq $Settings -or $Settings.Count -eq 0) { return $result }

        # Parent stack: list of parent names indexed by indent level
        $parentStack = [System.Collections.Generic.List[string]]::new()

        foreach ($setting in $Settings) {
            $indent = if ($null -ne $setting.Indent) { [int]$setting.Indent } else { 0 }
            $name   = "$($setting.Name)"
            $value  = "$($setting.Value)"
            $defId  = "$($setting.DefinitionId)"
            $isConfigured = $setting.IsConfigured -eq $true

            if (-not $isConfigured) {
                # Group header — update parent stack at this indent level
                while ($parentStack.Count -gt $indent) {
                    $parentStack.RemoveAt($parentStack.Count - 1)
                }
                [void]$parentStack.Add($name)
            } else {
                # Configured setting — build path from parent stack + this name
                while ($parentStack.Count -gt $indent) {
                    $parentStack.RemoveAt($parentStack.Count - 1)
                }

                # Build the full path from parent stack + catalog category
                if ($parentStack.Count -gt 0) {
                    $pathParts = @($parentStack) + @($name)
                    $settingPath = $pathParts -join ' > '
                } else {
                    # No parent stack — try to add catalog category for context
                    $catContext = & $getCategoryName $defId
                    if (-not [string]::IsNullOrWhiteSpace($catContext)) {
                        $settingPath = "$catContext > $name"
                    } else {
                        $settingPath = $name
                    }
                }

                [void]$result.Add(@{
                    Name         = $name
                    SettingPath  = $settingPath
                    Value        = $value
                    DefinitionId = $defId
                })
            }
        }

        return $result
    }

    # ── Helper: build a lookup from setting paths ─────────────────────────
    # Returns hashtable keyed by DefinitionId (or SettingPath fallback) -> @{ Name; Value; SettingPath; DefinitionId }
    # When duplicate paths occur, uses catalog CategoryName for disambiguation
    $buildSettingLookup = {
        param([array]$Settings)
        $paths = & $buildSettingPaths $Settings
        $lookup = [ordered]@{}
        foreach ($p in $paths) {
            $key = if (-not [string]::IsNullOrEmpty($p.DefinitionId)) {
                $p.DefinitionId.ToLowerInvariant()
            } else {
                $p.SettingPath.ToLowerInvariant()
            }
            # Skip excluded settings
            if (& $isExcludedSetting $p.Name) { continue }
            if (& $isExcludedSetting $key) { continue }
            # Skip structural array count rows (e.g., "40 items")
            if ($p.Value -match '^\d+ items$') { continue }

            # Handle duplicate paths — use category name for disambiguation
            if ($lookup.Contains($key)) {
                $catName = & $getCategoryName $p.DefinitionId
                if (-not [string]::IsNullOrWhiteSpace($catName)) {
                    $key = "$catName > $($p.Name)"
                    $p.SettingPath = $key
                }
                # If still duplicate after category, add numeric suffix
                if ($lookup.Contains($key)) {
                    $idx = 2
                    while ($lookup.Contains("${key} ($idx)")) { $idx++ }
                    $key = "${key} ($idx)"
                    $p.SettingPath = $key
                }
            }
            $lookup[$key] = $p
        }
        # Also retroactively disambiguate the FIRST entry when it was initially
        # stored without category context but a duplicate was found
        # (re-key the first entry with its category if the original key was bare)
        $keysToReplace = [System.Collections.Generic.List[string]]::new()
        foreach ($key in $lookup.Keys) {
            $entry = $lookup[$key]
            $catName = & $getCategoryName $entry.DefinitionId
            if (-not [string]::IsNullOrWhiteSpace($catName) -and $key -eq $entry.Name) {
                # Check if there are other entries with category-prefixed versions of this name
                $hasDuplicates = $false
                foreach ($otherKey in $lookup.Keys) {
                    if ($otherKey -ne $key -and $otherKey -match [regex]::Escape($entry.Name) -and $otherKey -ne $entry.SettingPath) {
                        $hasDuplicates = $true; break
                    }
                }
                if ($hasDuplicates) {
                    [void]$keysToReplace.Add($key)
                }
            }
        }
        foreach ($oldKey in $keysToReplace) {
            $entry = $lookup[$oldKey]
            $catName = & $getCategoryName $entry.DefinitionId
            $newKey = "$catName > $($entry.Name)"
            if (-not $lookup.Contains($newKey)) {
                $entry.SettingPath = $newKey
                $lookup.Remove($oldKey)
                $lookup[$newKey] = $entry
            }
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

    # ── Categories that should go to manual review instead of comparison ──
    $manualReviewCategories = [ordered]@{}

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
        # ExcludeOS filter (case-insensitive contains)
        if ($ExcludeOS) {
            $skipProduct = $false
            $prodLower = $productName.ToLowerInvariant()
            foreach ($ep in $ExcludeOS) {
                if ($prodLower -match [regex]::Escape($ep.ToLowerInvariant())) { $skipProduct = $true; break }
            }
            if ($skipProduct) { continue }
        }

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

            # Filter out unassigned policies when -IgnoreUnassignedPolicies is set
            if ($IgnoreUnassignedPolicies) {
                $srcPolicies = @($srcPolicies | Where-Object { $null -ne $_ -and $null -ne $_.Assignments -and @($_.Assignments).Count -gt 0 })
                $dstPolicies = @($dstPolicies | Where-Object { $null -ne $_ -and $null -ne $_.Assignments -and @($_.Assignments).Count -gt 0 })
            }

            # Filter by policy name (case-insensitive contains)
            if (-not [string]::IsNullOrWhiteSpace($PolicyNameFilter)) {
                $srcPolicies = @($srcPolicies | Where-Object { $null -ne $_ -and $_.Basics.Name -and $_.Basics.Name.IndexOf($PolicyNameFilter, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 })
                $dstPolicies = @($dstPolicies | Where-Object { $null -ne $_ -and $_.Basics.Name -and $_.Basics.Name.IndexOf($PolicyNameFilter, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 })
            }

            $categoryLabel = "$productName / $categoryName"

            # Route non-comparable categories to manual review
            $catLower = $categoryName.ToLowerInvariant()
            if ($catLower -match 'script|remediation|custom compliance') {
                # Add to manual review instead of comparison
                # Helper: collect settings with base64 decoding for script content
                $collectMRSettings = {
                    param($Policy, [string]$Side)
                    if ($null -eq $Policy -or $null -eq $Policy.Basics) { return }
                    if (-not $manualReviewCategories.Contains($categoryLabel)) {
                        $manualReviewCategories[$categoryLabel] = [System.Collections.Generic.List[object]]::new()
                    }
                    $settingsSummary = [System.Collections.Generic.List[object]]::new()
                    foreach ($s in @($Policy.Settings)) {
                        if ($s.IsConfigured -eq $true -and -not [string]::IsNullOrWhiteSpace("$($s.Value)")) {
                            $settingName = "$($s.Name)"
                            $settingValue = "$($s.Value)"
                            # Skip binary hash fields (not displayable)
                            if ($settingName -match '^hashed|Hash$') { continue }
                            # Decode base64 script content (but not hashes)
                            if ($settingName -match '^(scriptContent|detectionScriptContent|remediationScriptContent)$') {
                                try {
                                    $decoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($settingValue))
                                    $settingValue = $decoded
                                } catch {
                                    # Not valid base64 — keep original
                                }
                            }
                            [void]$settingsSummary.Add(@{ Name = $settingName; Value = $settingValue })
                        }
                    }
                    [void]$manualReviewCategories[$categoryLabel].Add(@{
                        PolicyName = $Policy.Basics.Name; Side = $Side; ProfileType = $Policy.Basics.ProfileType; Settings = $settingsSummary
                    })
                }
                foreach ($p in $srcPolicies) { & $collectMRSettings $p 'Source' }
                foreach ($p in $dstPolicies) { & $collectMRSettings $p 'Destination' }
                continue  # Skip auto-comparison for this category
            }

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

                    # Collect all setting keys (definitionId or settingPath depending on policy type)
                    $allSettingKeys = [System.Collections.Generic.List[string]]::new()
                    foreach ($k in $srcLookup.Keys) {
                        if (-not $allSettingKeys.Contains($k)) { [void]$allSettingKeys.Add($k) }
                    }
                    foreach ($k in $dstLookup.Keys) {
                        if (-not $allSettingKeys.Contains($k)) { [void]$allSettingKeys.Add($k) }
                    }

                    foreach ($settingKey in $allSettingKeys) {
                        $inSrc = $srcLookup.Contains($settingKey)
                        $inDst = $dstLookup.Contains($settingKey)
                        $srcVal = if ($inSrc) { $srcLookup[$settingKey].Value } else { '' }
                        $dstVal = if ($inDst) { $dstLookup[$settingKey].Value } else { '' }
                        $displayName = if ($inSrc) { $srcLookup[$settingKey].Name } else { $dstLookup[$settingKey].Name }

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
                            SettingPath  = if ($inSrc) { $srcLookup[$settingKey].SettingPath } else { $dstLookup[$settingKey].SettingPath }
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

                        foreach ($settingKey in $srcLookup.Keys) {
                            $srcVal = $srcLookup[$settingKey].Value
                            # Skip empty source-only settings
                            if (& $isEmptyValue $srcVal) { continue }

                            $row = @{
                                ItemType     = 'Setting'
                                Name         = $srcLookup[$settingKey].Name
                                SettingPath  = $srcLookup[$settingKey].SettingPath
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

                        foreach ($settingKey in $dstLookup.Keys) {
                            $dstVal = $dstLookup[$settingKey].Value
                            # Skip empty dest-only settings
                            if (& $isEmptyValue $dstVal) { continue }

                            $row = @{
                                ItemType     = 'Setting'
                                Name         = $dstLookup[$settingKey].Name
                                SettingPath  = $dstLookup[$settingKey].SettingPath
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

    # ── Manual Review = script/remediation/custom compliance + deprecated ──
    $manualReview = $manualReviewCategories

    # ── Deprecated Settings scan (both tenants) ──────────────────────────
    # Scan ALL settings in both DocModels. If a policy contains ANY deprecated
    # setting, add it to manual review with a "contains deprecated" flag.
    $scanForDeprecated = {
        param([hashtable]$Model, [string]$Side)
        if ($null -eq $Model -or $null -eq $Model.Products) { return }
        foreach ($prodName in $Model.Products.Keys) {
            $prodData = $Model.Products[$prodName]
            if ($null -eq $prodData -or $null -eq $prodData.Categories) { continue }
            foreach ($catName in $prodData.Categories.Keys) {
                foreach ($policy in @($prodData.Categories[$catName])) {
                    if ($null -eq $policy -or $null -eq $policy.Basics) { continue }
                    # Check if ANY setting in this policy is deprecated
                    $hasDeprecated = $false
                    $settingsSummary = [System.Collections.Generic.List[object]]::new()
                    foreach ($s in @($policy.Settings)) {
                        if ($s.IsConfigured -ne $true) { continue }
                        $settingName = "$($s.Name)"
                        $settingValue = "$($s.Value)"
                        $defId = "$($s.DefinitionId)"
                        if ([string]::IsNullOrWhiteSpace($settingValue)) { continue }
                        # Check deprecated via name, catalog, or value
                        $isDepr = $settingName -match 'deprecated' -or $settingValue -match 'deprecated'
                        if (-not $isDepr -and -not [string]::IsNullOrEmpty($defId) -and
                            $null -ne $script:InforcerSettingsCatalog -and
                            $script:InforcerSettingsCatalog.ContainsKey($defId)) {
                            $catEntry = $script:InforcerSettingsCatalog[$defId]
                            if ($catEntry.DisplayName -match 'deprecated') {
                                $isDepr = $true
                                $settingName = $catEntry.DisplayName
                            }
                        }
                        if ($isDepr) {
                            $hasDeprecated = $true
                            [void]$settingsSummary.Add(@{
                                Name         = $settingName
                                Value        = $settingValue
                                IsDeprecated = $true
                            })
                        }
                    }
                    if ($hasDeprecated) {
                        $catLabel = "$prodName / $catName"
                        if (-not $manualReview.Contains($catLabel)) {
                            $manualReview[$catLabel] = [System.Collections.Generic.List[object]]::new()
                        }
                        [void]$manualReview[$catLabel].Add(@{
                            PolicyName     = $policy.Basics.Name
                            Side           = $Side
                            ProfileType    = $policy.Basics.ProfileType
                            Settings       = $settingsSummary
                            HasDeprecated  = $true
                        })
                    }
                }
            }
        }
    }
    & $scanForDeprecated $SourceModel 'Source'
    & $scanForDeprecated $DestinationModel 'Destination'

    # manualReview now contains: script/remediation/custom compliance + deprecated policies

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
        DeprecatedSettings   = @()  # deprecated policies are now in ManualReview with HasDeprecated flag
        Products             = $products
        ManualReview         = $manualReview
        IncludingAssignments = [bool]$IncludingAssignments
    }
}
