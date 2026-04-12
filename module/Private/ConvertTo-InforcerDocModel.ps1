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
        [hashtable]$RoleNameMap,

        [Parameter()]
        [hashtable]$LocationNameMap,

        [Parameter()]
        [hashtable]$AppNameMap,

        [Parameter()]
        [hashtable]$ScopeTagMap,

        [Parameter()]
        [switch]$ComparisonMode
    )

    # Friendly labels for Conditional Access camelCase property names
    $caFriendlyNames = @{
        'includeUsers'                    = 'Include Users'
        'excludeUsers'                    = 'Exclude Users'
        'includeGroups'                   = 'Include Groups'
        'excludeGroups'                   = 'Exclude Groups'
        'includeRoles'                    = 'Include Roles'
        'excludeRoles'                    = 'Exclude Roles'
        'includeGuestsOrExternalUsers'    = 'Include Guests or External Users'
        'excludeGuestsOrExternalUsers'    = 'Exclude Guests or External Users'
        'includeApplications'             = 'Include Applications'
        'excludeApplications'             = 'Exclude Applications'
        'includeUserActions'              = 'Include User Actions'
        'includeAuthenticationContextClassReferences' = 'Include Authentication Context'
        'includeLocations'                = 'Include Locations'
        'excludeLocations'                = 'Exclude Locations'
        'includePlatforms'                = 'Include Platforms'
        'excludePlatforms'                = 'Exclude Platforms'
        'includeServicePrincipals'        = 'Include Service Principals'
        'excludeServicePrincipals'        = 'Exclude Service Principals'
        'clientAppTypes'                  = 'Client App Types'
        'userRiskLevels'                  = 'User Risk Levels'
        'signInRiskLevels'                = 'Sign-in Risk Levels'
        'servicePrincipalRiskLevels'      = 'Service Principal Risk Levels'
        'grantControls'                   = 'Grant Controls'
        'builtInControls'                 = 'Built-in Controls'
        'customAuthenticationFactors'     = 'Custom Authentication Factors'
        'termsOfUse'                      = 'Terms of Use'
        'authenticationStrength'          = 'Authentication Strength'
        'operator'                        = 'Operator'
        'allowedCombinations'             = 'Allowed Combinations'
        'requirementsSatisfied'           = 'Requirements Satisfied'
        'policyType'                      = 'Policy Type'
        'combinationConfigurations'       = 'Combination Configurations'
        'sessionControls'                 = 'Session Controls'
        'applicationEnforcedRestrictions' = 'Application Enforced Restrictions'
        'cloudAppSecurity'                = 'Cloud App Security'
        'persistentBrowser'               = 'Persistent Browser'
        'signInFrequency'                 = 'Sign-in Frequency'
        'disableResilienceDefaults'       = 'Disable Resilience Defaults'
        'continuousAccessEvaluation'      = 'Continuous Access Evaluation'
        'secureSignInSession'             = 'Secure Sign-in Session'
        'transferMethods'                 = 'Transfer Methods'
        'modifiedDateTime'                = 'Modified'
        'conditions'                      = 'Conditions'
        'users'                           = 'Users'
        'applications'                    = 'Applications'
        'locations'                       = 'Locations'
        'platforms'                       = 'Platforms'
        'devices'                         = 'Devices'
        'clientApplications'              = 'Client Applications'
    }

    # Friendly labels for camelCase auth combination values
    $caFriendlyValues = @{
        'windowsHelloForBusiness'       = 'Windows Hello for Business'
        'fido2'                         = 'FIDO2 Security Key'
        'deviceBasedPush'               = 'Device-based Push'
        'temporaryAccessPassOneTime'    = 'Temporary Access Pass (One-time)'
        'temporaryAccessPassMultiUse'   = 'Temporary Access Pass (Multi-use)'
        'password,microsoftAuthenticatorPush' = 'Password + Microsoft Authenticator'
        'password,softwareOath'         = 'Password + Software OATH Token'
        'password,hardwareOath'         = 'Password + Hardware OATH Token'
        'password,sms'                  = 'Password + SMS'
        'password,voice'                = 'Password + Voice'
        'federatedMultiFactor'          = 'Federated Multi-factor'
        'federatedSingleFactor'         = 'Federated Single-factor'
        'microsoftAuthenticatorPush'    = 'Microsoft Authenticator Push'
        'softwareOath'                  = 'Software OATH Token'
        'hardwareOath'                  = 'Hardware OATH Token'
        'sms'                           = 'SMS'
        'voice'                         = 'Voice'
        'x509CertificateMultiFactor'    = 'X.509 Certificate (Multi-factor)'
        'x509CertificateSingleFactor'   = 'X.509 Certificate (Single-factor)'
        'authenticationTransfer'        = 'Authentication Transfer'
        'deviceCodeFlow'                = 'Device Code Flow'
    }

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

        # Resolve GUIDs in CA policy settings (groups, roles, named locations)
        if ($settings.Count -gt 0 -and ($GroupNameMap -or $RoleNameMap -or $LocationNameMap)) {
            $guidPattern = '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
            foreach ($row in $settings) {
                $val = $row.Value
                if ([string]::IsNullOrWhiteSpace($val)) { continue }
                # Single GUID value
                if ($val -match $guidPattern) {
                    if ($GroupNameMap -and $GroupNameMap.ContainsKey($val)) { $row.Value = $GroupNameMap[$val] }
                    elseif ($RoleNameMap -and $RoleNameMap.ContainsKey($val)) { $row.Value = $RoleNameMap[$val] }
                    elseif ($LocationNameMap -and $LocationNameMap.ContainsKey($val)) { $row.Value = $LocationNameMap[$val] }
                }
                # Comma-separated list of GUIDs (from array joins)
                elseif ($val -match '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}') {
                    $parts = $val -split ',\s*'
                    $resolved = $false
                    $newParts = foreach ($part in $parts) {
                        $p = $part.Trim()
                        if ($p -match $guidPattern) {
                            if ($GroupNameMap -and $GroupNameMap.ContainsKey($p)) { $resolved = $true; $GroupNameMap[$p] }
                            elseif ($RoleNameMap -and $RoleNameMap.ContainsKey($p)) { $resolved = $true; $RoleNameMap[$p] }
                            elseif ($LocationNameMap -and $LocationNameMap.ContainsKey($p)) { $resolved = $true; $LocationNameMap[$p] }
                            else { $p }
                        } else { $p }
                    }
                    if ($resolved) { $row.Value = $newParts -join ', ' }
                }
            }
        }

        # Friendly CA property names, app ID resolution, and value labels
        if ($settings.Count -gt 0) {
            $guidPat = '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
            foreach ($row in @($settings)) {
                $name = $row.Name
                $val  = $row.Value
                # Resolve application IDs in Value (single or comma-separated)
                if ($AppNameMap -and -not [string]::IsNullOrWhiteSpace($val)) {
                    if ($val -match $guidPat -and $AppNameMap.ContainsKey($val)) {
                        $row.Value = $AppNameMap[$val]
                    } elseif ($val -match '[0-9a-f]{8}-') {
                        $parts = $val -split ',\s*'
                        $changed = $false
                        $newParts = foreach ($p in $parts) {
                            $pt = $p.Trim()
                            if ($pt -match $guidPat -and $AppNameMap.ContainsKey($pt)) { $changed = $true; $AppNameMap[$pt] }
                            else { $pt }
                        }
                        if ($changed) { $row.Value = $newParts -join ', ' }
                    }
                }
                # Resolve camelCase values (e.g. allowedCombinations like "password,softwareOath")
                $val = $row.Value
                if (-not [string]::IsNullOrWhiteSpace($val) -and $val -is [string]) {
                    # Try full value first (handles combo keys like "password,microsoftAuthenticatorPush")
                    $trimmedVal = $val.Trim()
                    $normalizedVal = (($trimmedVal -split ',') | ForEach-Object { $_.Trim() }) -join ','
                    if ($caFriendlyValues.ContainsKey($trimmedVal)) {
                        $row.Value = $caFriendlyValues[$trimmedVal]
                    } elseif ($caFriendlyValues.ContainsKey($normalizedVal)) {
                        $row.Value = $caFriendlyValues[$normalizedVal]
                    } elseif ($trimmedVal -match ',') {
                        # Fall back to per-part resolution
                        $parts = $trimmedVal -split ',\s*'
                        $changed = $false
                        $newParts = foreach ($p in $parts) {
                            $pt = $p.Trim()
                            if ($caFriendlyValues.ContainsKey($pt)) { $changed = $true; $caFriendlyValues[$pt] }
                            else { $pt }
                        }
                        if ($changed) { $row.Value = $newParts -join ', ' }
                    }
                }
                # Rename camelCase CA property names to friendly labels
                if ($caFriendlyNames.ContainsKey($name)) {
                    $row.Name = $caFriendlyNames[$name]
                }
            }
        }

        # Convert ISO 8601 durations (e.g. PT0S, P30D, PT24H) to friendly text
        foreach ($row in @($settings)) {
            $v = $row.Value
            if (-not [string]::IsNullOrWhiteSpace($v) -and $v -match '^P(?:(\d+)D)?(?:T(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?)?$') {
                $days = if ($Matches[1]) { [int]$Matches[1] } else { 0 }
                $hours = if ($Matches[2]) { [int]$Matches[2] } else { 0 }
                $mins = if ($Matches[3]) { [int]$Matches[3] } else { 0 }
                $secs = if ($Matches[4]) { [int]$Matches[4] } else { 0 }
                $parts = @()
                if ($days -gt 0) { $parts += "$days day$(if ($days -ne 1) { 's' })" }
                if ($hours -gt 0) { $parts += "$hours hour$(if ($hours -ne 1) { 's' })" }
                if ($mins -gt 0) { $parts += "$mins minute$(if ($mins -ne 1) { 's' })" }
                if ($secs -gt 0) { $parts += "$secs second$(if ($secs -ne 1) { 's' })" }
                if ($parts.Count -eq 0) { $row.Value = '0 (immediate)' }
                else { $row.Value = $parts -join ', ' }
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
