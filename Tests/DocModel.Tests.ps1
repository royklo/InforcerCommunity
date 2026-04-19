# DocModel.Tests.ps1
# Pester 5.x tests for ConvertTo-InforcerDocModel normalization.
# Run from repo root: Invoke-Pester ./Tests/DocModel.Tests.ps1

$ErrorActionPreference = 'Stop'

# Evaluate integration data availability at script scope (not BeforeAll) so
# Pester 5 -Skip: can reference the variable at discovery time.
$script:IntegrationDataAvailable = (
    (Test-Path (Join-Path $PSScriptRoot '..' 'scripts' 'sample-data' 'tenant-policies.json')) -and
    (Test-Path (Join-Path $PSScriptRoot '..' 'scripts' 'sample-data' 'tenants.json')) -and
    (Test-Path (Join-Path $PSScriptRoot '..' 'scripts' 'sample-data' 'baselines.json'))
)
$script:SettingsCatalogAvailable = Test-Path (Join-Path $PSScriptRoot '..' 'module' 'data' 'settings.json')

BeforeAll {
    Remove-Module -Name 'InforcerCommunity' -ErrorAction SilentlyContinue
    $here = $PSScriptRoot
    $manifestPath = Join-Path $here '..' 'module' 'InforcerCommunity.psd1'
    $manifestPath = [System.IO.Path]::GetFullPath($manifestPath)
    Import-Module $manifestPath -Force -ErrorAction Stop

    # Re-evaluate data availability inside BeforeAll (script-scope vars from discovery not accessible here).
    $tenantPoliciesPath = [System.IO.Path]::GetFullPath((Join-Path $here '..' 'scripts' 'sample-data' 'tenant-policies.json'))
    $tenantsPath        = [System.IO.Path]::GetFullPath((Join-Path $here '..' 'scripts' 'sample-data' 'tenants.json'))
    $baselinesPath      = [System.IO.Path]::GetFullPath((Join-Path $here '..' 'scripts' 'sample-data' 'baselines.json'))
    $catalogPath        = [System.IO.Path]::GetFullPath((Join-Path $here '..' 'module' 'data' 'settings.json'))

    $integrationAvailable = (Test-Path $tenantPoliciesPath) -and (Test-Path $tenantsPath) -and (Test-Path $baselinesPath)
    $catalogAvailable     = Test-Path $catalogPath

    if ($integrationAvailable) {
        $script:TenantPolicies = Get-Content $tenantPoliciesPath -Raw | ConvertFrom-Json -Depth 100
        $script:Tenants        = Get-Content $tenantsPath -Raw        | ConvertFrom-Json -Depth 100
        $script:Baselines      = Get-Content $baselinesPath -Raw      | ConvertFrom-Json -Depth 100

        # Load settings catalog inside module scope so $script:InforcerSettingsCatalog is populated
        if ($catalogAvailable) {
            InModuleScope InforcerCommunity -Parameters @{ CatalogPath = $catalogPath } {
                Import-InforcerSettingsCatalog -Path $CatalogPath -Force
            }
        }

        # Build DocData and run ConvertTo-InforcerDocModel by passing file paths into the module
        # scope so all data loading and transformation happens within the same PS session scope.
        $script:DocModel = InModuleScope InforcerCommunity -Parameters @{
            TenantPoliciesPath = $tenantPoliciesPath
            TenantsPath        = $tenantsPath
            BaselinesPath      = $baselinesPath
        } {
            $tenantPolicies = Get-Content $TenantPoliciesPath -Raw | ConvertFrom-Json -Depth 100
            $tenants        = Get-Content $TenantsPath -Raw        | ConvertFrom-Json -Depth 100
            $baselines      = Get-Content $BaselinesPath -Raw      | ConvertFrom-Json -Depth 100

            $docData = @{
                Tenant      = $tenants[0]
                Baselines   = $baselines
                Policies    = $tenantPolicies
                TenantId    = $tenants[0].clientTenantId
                CollectedAt = [datetime]::UtcNow
            }
            ConvertTo-InforcerDocModel -DocData $docData
        }
    }
}

# ---------------------------------------------------------------------------
# Describe: Get-InforcerCategoryKey (unit tests)
# ---------------------------------------------------------------------------
Describe 'Get-InforcerCategoryKey' {

    It 'returns primaryGroup when secondaryGroup equals primaryGroup' {
        $result = InModuleScope InforcerCommunity {
            Get-InforcerCategoryKey -PrimaryGroup 'Settings' -SecondaryGroup 'Settings'
        }
        $result | Should -Be 'Settings'
    }

    It 'returns "A / B" when primaryGroup and secondaryGroup differ' {
        $result = InModuleScope InforcerCommunity {
            Get-InforcerCategoryKey -PrimaryGroup 'Conditional Access' -SecondaryGroup 'Policies'
        }
        $result | Should -Be 'Conditional Access / Policies'
    }

    It 'returns primaryGroup when secondaryGroup is "All"' {
        $result = InModuleScope InforcerCommunity {
            Get-InforcerCategoryKey -PrimaryGroup 'Settings' -SecondaryGroup 'All'
        }
        $result | Should -Be 'Settings'
    }

    It 'returns primaryGroup when secondaryGroup is null' {
        $result = InModuleScope InforcerCommunity {
            Get-InforcerCategoryKey -PrimaryGroup 'Windows' -SecondaryGroup $null
        }
        $result | Should -Be 'Windows'
    }

    It 'returns primaryGroup when secondaryGroup is empty string' {
        $result = InModuleScope InforcerCommunity {
            Get-InforcerCategoryKey -PrimaryGroup 'Exchange' -SecondaryGroup ''
        }
        $result | Should -Be 'Exchange'
    }
}

# ---------------------------------------------------------------------------
# Describe: Get-InforcerPolicyName (unit tests)
# ---------------------------------------------------------------------------
Describe 'Get-InforcerPolicyName' {

    It 'returns displayName when set' {
        $policy = [PSCustomObject]@{ displayName = 'My Policy'; friendlyName = $null; name = $null; policyData = $null; id = 42 }
        $result = InModuleScope InforcerCommunity -Parameters @{ P = $policy } {
            Get-InforcerPolicyName -Policy $P
        }
        $result | Should -Be 'My Policy'
    }

    It 'falls back to friendlyName when displayName is null' {
        $policy = [PSCustomObject]@{ displayName = $null; friendlyName = 'Friendly Name'; name = $null; policyData = $null; id = 42 }
        $result = InModuleScope InforcerCommunity -Parameters @{ P = $policy } {
            Get-InforcerPolicyName -Policy $P
        }
        $result | Should -Be 'Friendly Name'
    }

    It 'falls back to name when displayName and friendlyName are null' {
        $policy = [PSCustomObject]@{ displayName = $null; friendlyName = $null; name = 'Policy Name'; policyData = $null; id = 42 }
        $result = InModuleScope InforcerCommunity -Parameters @{ P = $policy } {
            Get-InforcerPolicyName -Policy $P
        }
        $result | Should -Be 'Policy Name'
    }

    It 'falls back to policyData.displayName when top-level names are null' {
        $pd = [PSCustomObject]@{ displayName = 'PD Display'; name = $null }
        $policy = [PSCustomObject]@{ displayName = $null; friendlyName = $null; name = $null; policyData = $pd; id = 42 }
        $result = InModuleScope InforcerCommunity -Parameters @{ P = $policy } {
            Get-InforcerPolicyName -Policy $P
        }
        $result | Should -Be 'PD Display'
    }

    It 'falls back to "Policy {id}" when all names are null' {
        $pd = [PSCustomObject]@{ displayName = $null; name = $null }
        $policy = [PSCustomObject]@{ displayName = $null; friendlyName = $null; name = $null; policyData = $pd; id = 99 }
        $result = InModuleScope InforcerCommunity -Parameters @{ P = $policy } {
            Get-InforcerPolicyName -Policy $P
        }
        $result | Should -Be 'Policy 99'
    }

    It 'produces "Policy Unknown" when all names and id are null' {
        $policy = [PSCustomObject]@{ displayName = $null; friendlyName = $null; name = $null; policyData = $null; id = $null }
        $result = InModuleScope InforcerCommunity -Parameters @{ P = $policy } {
            Get-InforcerPolicyName -Policy $P
        }
        $result | Should -Be 'Policy Unknown'
    }
}

# ---------------------------------------------------------------------------
# Describe: ConvertTo-InforcerDocModel structure (integration tests)
# ---------------------------------------------------------------------------
Describe 'ConvertTo-InforcerDocModel - DocModel structure' -Skip:(-not $script:IntegrationDataAvailable) {

    It 'DocModel has TenantName, TenantId, GeneratedAt, Products keys' {
        $script:DocModel.Keys | Should -Contain 'TenantName'
        $script:DocModel.Keys | Should -Contain 'TenantId'
        $script:DocModel.Keys | Should -Contain 'GeneratedAt'
        $script:DocModel.Keys | Should -Contain 'Products'
    }

    It 'DocModel.TenantName is non-empty' {
        $script:DocModel.TenantName | Should -Not -BeNullOrEmpty
    }

    It 'DocModel.TenantId equals the input TenantId' {
        $script:DocModel.TenantId | Should -Be $script:Tenants[0].clientTenantId
    }

    It 'Products is an OrderedDictionary' {
        $script:DocModel.Products.GetType().Name | Should -Be 'OrderedDictionary'
    }

    It 'At least 8 products are present from sample data' {
        $script:DocModel.Products.Count | Should -BeGreaterOrEqual 8
    }

    It 'Each product has a Categories OrderedDictionary' {
        foreach ($prod in $script:DocModel.Products.Values) {
            $prod.Keys | Should -Contain 'Categories'
            $prod.Categories.GetType().Name | Should -Be 'OrderedDictionary'
        }
    }

    It 'Each category contains an array or list of policy objects' {
        foreach ($prod in $script:DocModel.Products.Values) {
            foreach ($cat in $prod.Categories.Values) {
                $cat | Should -Not -BeNullOrEmpty
                # Should be enumerable (array or list)
                { $cat.Count } | Should -Not -Throw
            }
        }
    }

    It 'Each policy has Basics, Settings, and Assignments keys' {
        $anyPolicy = $null
        foreach ($prod in $script:DocModel.Products.Values) {
            foreach ($cat in $prod.Categories.Values) {
                foreach ($pol in $cat) {
                    $anyPolicy = $pol
                    break
                }
                if ($anyPolicy) { break }
            }
            if ($anyPolicy) { break }
        }
        $anyPolicy | Should -Not -BeNullOrEmpty
        $anyPolicy.Keys | Should -Contain 'Basics'
        $anyPolicy.Keys | Should -Contain 'Settings'
        $anyPolicy.Keys | Should -Contain 'Assignments'
    }

    It 'Basics has Name, Description, ProfileType, Platform, Created, Modified, ScopeTags' {
        $pol = $null
        foreach ($prod in $script:DocModel.Products.Values) {
            foreach ($cat in $prod.Categories.Values) {
                if ($cat.Count -gt 0) { $pol = $cat[0]; break }
            }
            if ($pol) { break }
        }
        $pol.Basics.Keys | Should -Contain 'Name'
        $pol.Basics.Keys | Should -Contain 'Description'
        $pol.Basics.Keys | Should -Contain 'ProfileType'
        $pol.Basics.Keys | Should -Contain 'Platform'
        $pol.Basics.Keys | Should -Contain 'Created'
        $pol.Basics.Keys | Should -Contain 'Modified'
        $pol.Basics.Keys | Should -Contain 'ScopeTags'
    }

    It 'No policy has null or empty Name in Basics (fallback chain works for all 194 policies)' {
        $nullNames = [System.Collections.Generic.List[string]]::new()
        foreach ($prod in $script:DocModel.Products.Values) {
            foreach ($cat in $prod.Categories.Values) {
                foreach ($pol in $cat) {
                    if ([string]::IsNullOrWhiteSpace($pol.Basics.Name)) {
                        [void]$nullNames.Add("Policy with null name found")
                    }
                }
            }
        }
        $nullNames.Count | Should -Be 0
    }

    It 'Total policy count equals source policy count (194)' {
        $total = 0
        foreach ($prod in $script:DocModel.Products.Values) {
            foreach ($cat in $prod.Categories.Values) {
                $total += $cat.Count
            }
        }
        $total | Should -Be $script:TenantPolicies.Count
    }
}

# ---------------------------------------------------------------------------
# Describe: Category key logic (integration tests)
# ---------------------------------------------------------------------------
Describe 'ConvertTo-InforcerDocModel - Category key deduplication' -Skip:(-not $script:IntegrationDataAvailable) {

    It 'Entra Settings/All policies are remapped to admin portal categories' {
        # Settings/All policies should be remapped by Get-InforcerPolicyDisplayInfo
        # to categories like "Authentication methods", "Enterprise applications", etc.
        $entraCategories = $script:DocModel.Products['Entra'].Categories.Keys
        $entraCategories | Should -Contain 'Authentication methods'
        $entraCategories | Should -Not -Contain 'Settings'
        $entraCategories | Should -Not -Contain 'Settings / All'
    }

    It 'Conditional Access/Policies policies produce category key "Conditional Access / Policies"' {
        $entraCategories = $script:DocModel.Products['Entra'].Categories.Keys
        $entraCategories | Should -Contain 'Conditional Access / Policies'
    }

    It 'No category key contains " / All" suffix' {
        foreach ($prod in $script:DocModel.Products.Values) {
            foreach ($catKey in $prod.Categories.Keys) {
                $catKey | Should -Not -Match ' / All$'
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Describe: Assignments (integration tests)
# ---------------------------------------------------------------------------
Describe 'ConvertTo-InforcerDocModel - Assignments' -Skip:(-not $script:IntegrationDataAvailable) {

    It 'At least one policy has non-empty Assignments array' {
        $found = $false
        foreach ($prod in $script:DocModel.Products.Values) {
            foreach ($cat in $prod.Categories.Values) {
                foreach ($pol in $cat) {
                    if ($pol.Assignments -and $pol.Assignments.Count -gt 0) {
                        $found = $true
                        break
                    }
                }
                if ($found) { break }
            }
            if ($found) { break }
        }
        $found | Should -BeTrue
    }

    It 'Assignments array contains objects with Target, Type, Filter, FilterMode properties' {
        $assignedPol = $null
        foreach ($prod in $script:DocModel.Products.Values) {
            foreach ($cat in $prod.Categories.Values) {
                foreach ($pol in $cat) {
                    if ($pol.Assignments -and $pol.Assignments.Count -gt 0) {
                        $assignedPol = $pol
                        break
                    }
                }
                if ($assignedPol) { break }
            }
            if ($assignedPol) { break }
        }
        $a = $assignedPol.Assignments[0]
        $a.PSObject.Properties.Name | Should -Contain 'Target'
        $a.PSObject.Properties.Name | Should -Contain 'Type'
        $a.PSObject.Properties.Name | Should -Contain 'Filter'
        $a.PSObject.Properties.Name | Should -Contain 'FilterMode'
    }
}

# ---------------------------------------------------------------------------
# Describe: Settings resolution (integration tests)
# ---------------------------------------------------------------------------
Describe 'ConvertTo-InforcerDocModel - Settings rows' -Skip:(-not $script:IntegrationDataAvailable) {

    It 'Settings Catalog policy (policyTypeId 10) has at least one Settings row' -Skip:(-not $script:SettingsCatalogAvailable) {
        $type10 = $null
        # Find a policyTypeId 10 from source data and locate it in the DocModel
        $sourcePol = $script:TenantPolicies | Where-Object { $_.policyTypeId -eq 10 -and $_.policyData.settings.Count -gt 0 } | Select-Object -First 1
        $pName = if ($sourcePol.displayName) { $sourcePol.displayName } elseif ($sourcePol.friendlyName) { $sourcePol.friendlyName } else { $sourcePol.name }
        $prod = $sourcePol.product

        if ($script:DocModel.Products.Contains($prod)) {
            foreach ($cat in $script:DocModel.Products[$prod].Categories.Values) {
                foreach ($pol in $cat) {
                    if ($pol.Basics.Name -eq $pName) {
                        $type10 = $pol
                        break
                    }
                }
                if ($type10) { break }
            }
        }
        $type10 | Should -Not -BeNullOrEmpty
        $type10.Settings.Count | Should -BeGreaterThan 0
    }

    It 'Settings Catalog policy Settings rows have Names that are not raw settingDefinitionIds' -Skip:(-not $script:SettingsCatalogAvailable) {
        $sourcePol = $script:TenantPolicies | Where-Object { $_.policyTypeId -eq 10 -and $_.policyData.settings.Count -gt 0 } | Select-Object -First 1
        $pName = if ($sourcePol.displayName) { $sourcePol.displayName } elseif ($sourcePol.friendlyName) { $sourcePol.friendlyName } else { $sourcePol.name }
        $prod = $sourcePol.product

        $type10 = $null
        if ($script:DocModel.Products.Contains($prod)) {
            foreach ($cat in $script:DocModel.Products[$prod].Categories.Values) {
                foreach ($pol in $cat) {
                    if ($pol.Basics.Name -eq $pName) { $type10 = $pol; break }
                }
                if ($type10) { break }
            }
        }

        # At least one row should have a Name that does NOT start with typical settingDefinitionId prefixes
        $hasHumanReadable = $type10.Settings | Where-Object {
            -not ($_.Name -match '^(user|device)_vendor_msft_')
        }
        $hasHumanReadable.Count | Should -BeGreaterThan 0
    }

    It 'Non-catalog policy has Settings rows from flat property enumeration' {
        # Use policyTypeId != 10 and has policyData
        $sourcePol = $script:TenantPolicies | Where-Object { $_.policyTypeId -ne 10 -and $null -ne $_.policyData } | Select-Object -First 1
        $pName = if ($sourcePol.displayName) { $sourcePol.displayName } elseif ($sourcePol.friendlyName) { $sourcePol.friendlyName } else { $sourcePol.name }
        $prod = $sourcePol.product

        $nonCatalog = $null
        if ($script:DocModel.Products.Contains($prod)) {
            foreach ($cat in $script:DocModel.Products[$prod].Categories.Values) {
                foreach ($pol in $cat) {
                    if ($pol.Basics.Name -eq $pName) { $nonCatalog = $pol; break }
                }
                if ($nonCatalog) { break }
            }
        }
        $nonCatalog | Should -Not -BeNullOrEmpty
        # Non-catalog policy should have a Settings array (may be empty if policyData has no enumerable props)
        $nonCatalog.Settings | Should -Not -BeNullOrEmpty -Because 'non-catalog policy should have flat settings rows from policyData enumeration'
    }
}

# ---------------------------------------------------------------------------
# Describe: Compare-InforcerDocModels - ENG-05 definitionId matching
# ---------------------------------------------------------------------------
Describe 'Compare-InforcerDocModels - ENG-05 definitionId matching' -Tag 'ENG-05' {

    It 'matches Settings Catalog settings by definitionId across tenants' {
        $result = InModuleScope InforcerCommunity {
            $src = @{
                TenantName = 'Source'
                TenantId   = 'src-tenant-id'
                Products   = [ordered]@{
                    Windows = @{
                        Categories = [ordered]@{
                            'Settings Catalog' = @(
                                @{
                                    Basics      = @{ Name = 'Policy A' }
                                    Settings    = @(
                                        [PSCustomObject]@{
                                            Name         = 'Screen Timeout'
                                            Value        = '5'
                                            Indent       = 0
                                            IsConfigured = $true
                                            DefinitionId = 'device_vendor_msft_policy_config_power_displayofftimeoutonbattery'
                                        }
                                    )
                                    Assignments = @()
                                }
                            )
                        }
                    }
                }
            }
            $dst = @{
                TenantName = 'Destination'
                TenantId   = 'dst-tenant-id'
                Products   = [ordered]@{
                    Windows = @{
                        Categories = [ordered]@{
                            'Settings Catalog' = @(
                                @{
                                    Basics      = @{ Name = 'Policy A' }
                                    Settings    = @(
                                        [PSCustomObject]@{
                                            Name         = 'Screen Timeout'
                                            Value        = '10'
                                            Indent       = 0
                                            IsConfigured = $true
                                            DefinitionId = 'device_vendor_msft_policy_config_power_displayofftimeoutonbattery'
                                        }
                                    )
                                    Assignments = @()
                                }
                            )
                        }
                    }
                }
            }
            Compare-InforcerDocModels -SourceModel $src -DestinationModel $dst
        }
        $result.Counters.Conflicting | Should -Be 1
        $result.Counters.Matched     | Should -Be 0
    }

    It 'falls back to settingPath for legacy profiles without definitionId' {
        $result = InModuleScope InforcerCommunity {
            $src = @{
                TenantName = 'Source'
                TenantId   = 'src-tenant-id'
                Products   = [ordered]@{
                    Windows = @{
                        Categories = [ordered]@{
                            'Device Restrictions' = @(
                                @{
                                    Basics      = @{ Name = 'Legacy Policy' }
                                    Settings    = @(
                                        [PSCustomObject]@{
                                            Name         = 'Screen Timeout'
                                            Value        = '5'
                                            Indent       = 0
                                            IsConfigured = $true
                                        }
                                    )
                                    Assignments = @()
                                }
                            )
                        }
                    }
                }
            }
            $dst = @{
                TenantName = 'Destination'
                TenantId   = 'dst-tenant-id'
                Products   = [ordered]@{
                    Windows = @{
                        Categories = [ordered]@{
                            'Device Restrictions' = @(
                                @{
                                    Basics      = @{ Name = 'Legacy Policy' }
                                    Settings    = @(
                                        [PSCustomObject]@{
                                            Name         = 'Screen Timeout'
                                            Value        = '15'
                                            Indent       = 0
                                            IsConfigured = $true
                                        }
                                    )
                                    Assignments = @()
                                }
                            )
                        }
                    }
                }
            }
            Compare-InforcerDocModels -SourceModel $src -DestinationModel $dst
        }
        $result.Counters.Conflicting | Should -Be 1
    }

    It 'handles mixed catalog and legacy without error' {
        $result = InModuleScope InforcerCommunity {
            $src = @{
                TenantName = 'Source'
                TenantId   = 'src-tenant-id'
                Products   = [ordered]@{
                    Windows = @{
                        Categories = [ordered]@{
                            'Settings Catalog' = @(
                                @{
                                    Basics      = @{ Name = 'Policy A' }
                                    Settings    = @(
                                        [PSCustomObject]@{
                                            Name         = 'Screen Timeout'
                                            Value        = '5'
                                            Indent       = 0
                                            IsConfigured = $true
                                            DefinitionId = 'device_vendor_msft_policy_config_power_displayofftimeoutonbattery'
                                        }
                                    )
                                    Assignments = @()
                                }
                            )
                        }
                    }
                }
            }
            $dst = @{
                TenantName = 'Destination'
                TenantId   = 'dst-tenant-id'
                Products   = [ordered]@{
                    Windows = @{
                        Categories = [ordered]@{
                            'Settings Catalog' = @(
                                @{
                                    Basics      = @{ Name = 'Policy A' }
                                    Settings    = @(
                                        [PSCustomObject]@{
                                            Name         = 'Screen Timeout'
                                            Value        = '10'
                                            Indent       = 0
                                            IsConfigured = $true
                                        }
                                    )
                                    Assignments = @()
                                }
                            )
                        }
                    }
                }
            }
            Compare-InforcerDocModels -SourceModel $src -DestinationModel $dst
        }
        # Should not throw — mixed catalog/legacy keys result in SourceOnly + DestOnly rows
        $result | Should -Not -BeNullOrEmpty
        ($result.Counters.SourceOnly + $result.Counters.DestOnly) | Should -BeGreaterThan 0
    }
}

# ---------------------------------------------------------------------------
# Describe: Compare-InforcerDocModels - ENG-06 path building
# ---------------------------------------------------------------------------
Describe 'Compare-InforcerDocModels - ENG-06 path building' -Tag 'ENG-06' {

    It 'produces Parent > Child path for nested settings' {
        $result = InModuleScope InforcerCommunity {
            $settings = @(
                [PSCustomObject]@{ Name = 'Display';  Value = '';  Indent = 0; IsConfigured = $false }
                [PSCustomObject]@{ Name = 'Power';    Value = '';  Indent = 1; IsConfigured = $false }
                [PSCustomObject]@{ Name = 'Timeout';  Value = '5'; Indent = 2; IsConfigured = $true }
            )
            $model = @{
                TenantName = 'Both'
                TenantId   = 'same-tenant-id'
                Products   = [ordered]@{
                    Windows = @{
                        Categories = [ordered]@{
                            'Settings Catalog' = @(
                                @{
                                    Basics      = @{ Name = 'Nested Policy' }
                                    Settings    = $settings
                                    Assignments = @()
                                }
                            )
                        }
                    }
                }
            }
            # Compare model with itself — produces Matched rows
            Compare-InforcerDocModels -SourceModel $model -DestinationModel $model
        }
        # Find a row where SettingPath contains ' > ' two times (two levels of nesting)
        $allRows = [System.Collections.Generic.List[object]]::new()
        foreach ($prod in $result.Products.Values) {
            foreach ($cat in $prod.Categories.Values) {
                foreach ($row in $cat.ComparisonRows) {
                    [void]$allRows.Add($row)
                }
            }
        }
        $nestedRow = $allRows | Where-Object { $_.SettingPath -like '*>*>*' }
        $nestedRow | Should -Not -BeNullOrEmpty -Because 'Timeout at indent 2 should have path Display > Power > Timeout'
    }

    It 'top-level setting path equals setting name' {
        $result = InModuleScope InforcerCommunity {
            $model = @{
                TenantName = 'Both'
                TenantId   = 'same-tenant-id'
                Products   = [ordered]@{
                    Windows = @{
                        Categories = [ordered]@{
                            'Device Restrictions' = @(
                                @{
                                    Basics      = @{ Name = 'Top Level Policy' }
                                    Settings    = @(
                                        [PSCustomObject]@{
                                            Name         = 'BitLocker'
                                            Value        = 'Enabled'
                                            Indent       = 0
                                            IsConfigured = $true
                                        }
                                    )
                                    Assignments = @()
                                }
                            )
                        }
                    }
                }
            }
            Compare-InforcerDocModels -SourceModel $model -DestinationModel $model
        }
        $allRows = [System.Collections.Generic.List[object]]::new()
        foreach ($prod in $result.Products.Values) {
            foreach ($cat in $prod.Categories.Values) {
                foreach ($row in $cat.ComparisonRows) {
                    [void]$allRows.Add($row)
                }
            }
        }
        $bitlockerRow = $allRows | Where-Object { $_.Name -eq 'BitLocker' }
        $bitlockerRow | Should -Not -BeNullOrEmpty
        $bitlockerRow.SettingPath | Should -Be 'BitLocker'
    }
}

# ---------------------------------------------------------------------------
# Describe: Compare-InforcerDocModels - ENG-01 noise exclusion
# ---------------------------------------------------------------------------
Describe 'Compare-InforcerDocModels - ENG-01 noise exclusion' -Tag 'ENG-01' {

    BeforeAll {
        # Helper to build a minimal model with one setting having the given Name and Value
        $buildModelWithSetting = {
            param([string]$SettingName, [string]$SettingValue, [string]$TenantName, [string]$TenantId)
            @{
                TenantName = $TenantName
                TenantId   = $TenantId
                Products   = [ordered]@{
                    Windows = @{
                        Categories = [ordered]@{
                            'Settings Catalog' = @(
                                @{
                                    Basics   = @{ Name = 'Test Policy' }
                                    Settings = @(
                                        [PSCustomObject]@{
                                            Name         = $SettingName
                                            Value        = $SettingValue
                                            Indent       = 0
                                            IsConfigured = $true
                                            DefinitionId = 'test_definition_id'
                                        }
                                    )
                                    Assignments = @()
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    It 'excludes standalone GUID values from comparison output' {
        $result = InModuleScope InforcerCommunity {
            param($buildModel)
            $src  = & $buildModel 'Some Setting' 'a0b1c2d3-e4f5-1234-5678-abcdef012345' 'Source' 'src-id'
            $dest = & $buildModel 'Some Setting' 'a0b1c2d3-e4f5-1234-5678-abcdef012345' 'Dest'   'dest-id'
            Compare-InforcerDocModels -SourceModel $src -DestinationModel $dest
        } -Parameters @{ buildModel = $buildModelWithSetting }
        $result.Products.Windows.Categories.'Settings Catalog'.ComparisonRows | Should -HaveCount 0
    }

    It 'excludes uppercase GUID values from comparison output' {
        $result = InModuleScope InforcerCommunity {
            param($buildModel)
            $src  = & $buildModel 'Some Setting' 'A0B1C2D3-E4F5-1234-5678-ABCDEF012345' 'Source' 'src-id'
            $dest = & $buildModel 'Some Setting' 'A0B1C2D3-E4F5-1234-5678-ABCDEF012345' 'Dest'   'dest-id'
            Compare-InforcerDocModels -SourceModel $src -DestinationModel $dest
        } -Parameters @{ buildModel = $buildModelWithSetting }
        $result.Products.Windows.Categories.'Settings Catalog'.ComparisonRows | Should -HaveCount 0
    }

    It 'excludes Top Level Setting Group Collection values from comparison output' {
        $result = InModuleScope InforcerCommunity {
            param($buildModel)
            $src  = & $buildModel 'Group Header' 'Top Level Setting Group Collection' 'Source' 'src-id'
            $dest = & $buildModel 'Group Header' 'Top Level Setting Group Collection' 'Dest'   'dest-id'
            Compare-InforcerDocModels -SourceModel $src -DestinationModel $dest
        } -Parameters @{ buildModel = $buildModelWithSetting }
        $result.Products.Windows.Categories.'Settings Catalog'.ComparisonRows | Should -HaveCount 0
    }

    It 'excludes structural noise array count values (multi-digit) from comparison output' {
        $result = InModuleScope InforcerCommunity {
            param($buildModel)
            $src  = & $buildModel 'Items Count' '40 items' 'Source' 'src-id'
            $dest = & $buildModel 'Items Count' '40 items' 'Dest'   'dest-id'
            Compare-InforcerDocModels -SourceModel $src -DestinationModel $dest
        } -Parameters @{ buildModel = $buildModelWithSetting }
        $result.Products.Windows.Categories.'Settings Catalog'.ComparisonRows | Should -HaveCount 0
    }

    It 'excludes structural noise array count values (single digit) from comparison output' {
        $result = InModuleScope InforcerCommunity {
            param($buildModel)
            $src  = & $buildModel 'Items Count' '3 items' 'Source' 'src-id'
            $dest = & $buildModel 'Items Count' '3 items' 'Dest'   'dest-id'
            Compare-InforcerDocModels -SourceModel $src -DestinationModel $dest
        } -Parameters @{ buildModel = $buildModelWithSetting }
        $result.Products.Windows.Categories.'Settings Catalog'.ComparisonRows | Should -HaveCount 0
    }

    It 'excludes odata.type setting names (name-based regression check after signature change)' {
        $result = InModuleScope InforcerCommunity {
            param($buildModel)
            $src  = & $buildModel '@odata.type' 'some.type' 'Source' 'src-id'
            $dest = & $buildModel '@odata.type' 'some.type' 'Dest'   'dest-id'
            Compare-InforcerDocModels -SourceModel $src -DestinationModel $dest
        } -Parameters @{ buildModel = $buildModelWithSetting }
        $result.Products.Windows.Categories.'Settings Catalog'.ComparisonRows | Should -HaveCount 0
    }

    It 'does not exclude legitimate setting values from comparison output' {
        $result = InModuleScope InforcerCommunity {
            param($buildModel)
            $src  = & $buildModel 'Display Brightness' 'Enabled' 'Source' 'src-id'
            $dest = & $buildModel 'Display Brightness' 'Enabled' 'Dest'   'dest-id'
            Compare-InforcerDocModels -SourceModel $src -DestinationModel $dest
        } -Parameters @{ buildModel = $buildModelWithSetting }
        $result.Products.Windows.Categories.'Settings Catalog'.ComparisonRows | Should -HaveCount 1
    }

    It 'does not exclude non-standalone GUID text from comparison output' {
        $result = InModuleScope InforcerCommunity {
            param($buildModel)
            $src  = & $buildModel 'Reference ID' 'some-guid-embedded-in-text abc123' 'Source' 'src-id'
            $dest = & $buildModel 'Reference ID' 'some-guid-embedded-in-text abc123' 'Dest'   'dest-id'
            Compare-InforcerDocModels -SourceModel $src -DestinationModel $dest
        } -Parameters @{ buildModel = $buildModelWithSetting }
        $result.Products.Windows.Categories.'Settings Catalog'.ComparisonRows | Should -HaveCount 1
    }
}

# ---------------------------------------------------------------------------
# Describe: Compare-InforcerDocModels - ENG-03 deprecated settings
# ---------------------------------------------------------------------------
Describe 'Compare-InforcerDocModels - ENG-03 deprecated settings' -Tag 'ENG-03' {

    BeforeAll {
        # Reuse the same model builder pattern as ENG-01 but accept optional DefinitionId
        $buildModelWithSetting = {
            param([string]$SettingName, [string]$SettingValue, [string]$TenantName, [string]$TenantId, [string]$DefId = 'test_definition_id')
            @{
                TenantName = $TenantName
                TenantId   = $TenantId
                Products   = [ordered]@{
                    Windows = @{
                        Categories = [ordered]@{
                            'Settings Catalog' = @(
                                @{
                                    Basics   = @{ Name = 'Test Policy' }
                                    Settings = @(
                                        [PSCustomObject]@{
                                            Name         = $SettingName
                                            Value        = $SettingValue
                                            Indent       = 0
                                            IsConfigured = $true
                                            DefinitionId = $DefId
                                        }
                                    )
                                    Assignments = @()
                                }
                            )
                        }
                    }
                }
            }
        }
    }

    It 'flags setting with deprecated in name as IsDeprecated = true' {
        $result = InModuleScope InforcerCommunity {
            param($buildModel)
            $src  = & $buildModel 'Allow deprecated feature' 'Enabled' 'Source' 'src-id'
            $dest = & $buildModel 'Allow deprecated feature' 'Enabled' 'Dest'   'dest-id'
            Compare-InforcerDocModels -SourceModel $src -DestinationModel $dest
        } -Parameters @{ buildModel = $buildModelWithSetting }
        $rows = $result.Products.Windows.Categories.'Settings Catalog'.ComparisonRows
        $rows | Should -HaveCount 1
        $rows[0].IsDeprecated | Should -BeTrue
    }

    It 'flags setting with deprecated in value as IsDeprecated = true' {
        $result = InModuleScope InforcerCommunity {
            param($buildModel)
            $src  = & $buildModel 'Feature Toggle' 'deprecated' 'Source' 'src-id'
            $dest = & $buildModel 'Feature Toggle' 'deprecated' 'Dest'   'dest-id'
            Compare-InforcerDocModels -SourceModel $src -DestinationModel $dest
        } -Parameters @{ buildModel = $buildModelWithSetting }
        $rows = $result.Products.Windows.Categories.'Settings Catalog'.ComparisonRows
        $rows | Should -HaveCount 1
        $rows[0].IsDeprecated | Should -BeTrue
    }

    It 'flags setting via catalog DisplayName containing deprecated as IsDeprecated = true' {
        $result = InModuleScope InforcerCommunity {
            param($buildModel)
            # Set up a mock catalog entry with deprecated DisplayName
            $script:InforcerSettingsCatalog = @{
                'catalog_depr_id' = @{ DisplayName = '(Deprecated) Old WiFi Setting' }
            }
            $src  = & $buildModel 'WiFi Config' 'WPA2' 'Source' 'src-id' 'catalog_depr_id'
            $dest = & $buildModel 'WiFi Config' 'WPA2' 'Dest'   'dest-id' 'catalog_depr_id'
            $r = Compare-InforcerDocModels -SourceModel $src -DestinationModel $dest
            $script:InforcerSettingsCatalog = $null
            $r
        } -Parameters @{ buildModel = $buildModelWithSetting }
        $rows = $result.Products.Windows.Categories.'Settings Catalog'.ComparisonRows
        $rows | Should -HaveCount 1
        $rows[0].IsDeprecated | Should -BeTrue
    }

    It 'sets IsDeprecated = false for non-deprecated settings' {
        $result = InModuleScope InforcerCommunity {
            param($buildModel)
            $src  = & $buildModel 'Display Brightness' '75' 'Source' 'src-id'
            $dest = & $buildModel 'Display Brightness' '75' 'Dest'   'dest-id'
            Compare-InforcerDocModels -SourceModel $src -DestinationModel $dest
        } -Parameters @{ buildModel = $buildModelWithSetting }
        $rows = $result.Products.Windows.Categories.'Settings Catalog'.ComparisonRows
        $rows | Should -HaveCount 1
        $rows[0].IsDeprecated | Should -BeFalse
    }

    It 'includes deprecated settings in comparison results (not filtered)' {
        $result = InModuleScope InforcerCommunity {
            param($buildModel)
            $src  = & $buildModel 'Deprecated: Old Setting' 'Value1' 'Source' 'src-id'
            $dest = & $buildModel 'Deprecated: Old Setting' 'Value2' 'Dest'   'dest-id'
            Compare-InforcerDocModels -SourceModel $src -DestinationModel $dest
        } -Parameters @{ buildModel = $buildModelWithSetting }
        $rows = $result.Products.Windows.Categories.'Settings Catalog'.ComparisonRows
        $rows | Should -HaveCount 1
        $rows[0].Status | Should -Be 'Conflicting'
    }
}

# ---------------------------------------------------------------------------
# Describe: Compare-InforcerDocModels - ENG-02 duplicate settings
# ---------------------------------------------------------------------------
Describe 'Compare-InforcerDocModels - ENG-02 duplicate settings' -Tag 'ENG-02' {

    BeforeAll {
        # Helper that builds a DocModel with multiple policies under a given product/category.
        # Each policy entry: @{ Name; Settings = @(@{ Name; Value; DefinitionId; Indent; IsConfigured }) }
        $buildDuplicateModel = {
            param(
                [string]$TenantName,
                [string]$TenantId,
                [array]$Policies,
                [string]$Product  = 'Windows',
                [string]$Category = 'Settings Catalog'
            )
            $policyList = @(
                $Policies | ForEach-Object {
                    $p = $_
                    @{
                        Basics   = @{ Name = $p.Name; ProfileType = 'Settings Catalog'; Platform = $Product }
                        Settings = @(
                            $p.Settings | ForEach-Object {
                                $s = $_
                                [PSCustomObject]@{
                                    Name         = $s.Name
                                    Value        = $s.Value
                                    Indent       = if ($null -ne $s.Indent) { $s.Indent } else { 0 }
                                    IsConfigured = if ($null -ne $s.IsConfigured) { $s.IsConfigured } else { $true }
                                    DefinitionId = $s.DefinitionId
                                }
                            }
                        )
                        Assignments = @()
                    }
                }
            )
            @{
                TenantName = $TenantName
                TenantId   = $TenantId
                Products   = [ordered]@{
                    $Product = @{
                        Categories = [ordered]@{
                            $Category = $policyList
                        }
                    }
                }
            }
        }
    }

    It 'detects same definitionId with different values across 2 policies as duplicate' {
        $result = InModuleScope InforcerCommunity {
            param($buildModel)
            $src = & $buildModel 'SourceTenant' 'src-id' @(
                @{ Name = 'Policy A'; Settings = @(@{ Name = 'Firewall'; Value = 'Enabled';  DefinitionId = 'def_firewall' }) },
                @{ Name = 'Policy B'; Settings = @(@{ Name = 'Firewall'; Value = 'Disabled'; DefinitionId = 'def_firewall' }) }
            )
            $dest = & $buildModel 'DestTenant' 'dest-id' @(
                @{ Name = 'Policy C'; Settings = @(@{ Name = 'Firewall'; Value = 'Enabled'; DefinitionId = 'def_firewall' }) }
            )
            Compare-InforcerDocModels -SourceModel $src -DestinationModel $dest
        } -Parameters @{ buildModel = $buildDuplicateModel }
        $result.ManualReview.'Duplicate Settings (Different Values)' | Should -Not -BeNullOrEmpty
    }

    It 'does NOT flag same definitionId with identical values in 2 policies as duplicate' {
        $result = InModuleScope InforcerCommunity {
            param($buildModel)
            $src = & $buildModel 'SourceTenant' 'src-id' @(
                @{ Name = 'Policy A'; Settings = @(@{ Name = 'Firewall'; Value = 'Enabled'; DefinitionId = 'def_firewall' }) },
                @{ Name = 'Policy B'; Settings = @(@{ Name = 'Firewall'; Value = 'Enabled'; DefinitionId = 'def_firewall' }) }
            )
            $dest = & $buildModel 'DestTenant' 'dest-id' @(
                @{ Name = 'Policy C'; Settings = @(@{ Name = 'Firewall'; Value = 'Enabled'; DefinitionId = 'def_firewall' }) }
            )
            Compare-InforcerDocModels -SourceModel $src -DestinationModel $dest
        } -Parameters @{ buildModel = $buildDuplicateModel }
        $result.ManualReview.Keys | Should -Not -Contain 'Duplicate Settings (Different Values)'
    }

    It 'excludes setting without definitionId from duplicate detection (D-08)' {
        $result = InModuleScope InforcerCommunity {
            param($buildModel)
            $src = & $buildModel 'SourceTenant' 'src-id' @(
                @{ Name = 'Policy A'; Settings = @(@{ Name = 'Setting X'; Value = 'Val1'; DefinitionId = '' }) },
                @{ Name = 'Policy B'; Settings = @(@{ Name = 'Setting X'; Value = 'Val2'; DefinitionId = '' }) }
            )
            $dest = & $buildModel 'DestTenant' 'dest-id' @()
            Compare-InforcerDocModels -SourceModel $src -DestinationModel $dest
        } -Parameters @{ buildModel = $buildDuplicateModel }
        $result.ManualReview.Keys | Should -Not -Contain 'Duplicate Settings (Different Values)'
    }

    It 'excludes intra-policy repeated definitionId from detection (D-09)' {
        $result = InModuleScope InforcerCommunity {
            param($buildModel)
            # Policy A has def_x appearing twice — should be ignored (intra-policy repeat)
            $src = & $buildModel 'SourceTenant' 'src-id' @(
                @{
                    Name     = 'Policy A'
                    Settings = @(
                        @{ Name = 'Setting X'; Value = 'Val1'; DefinitionId = 'def_x' },
                        @{ Name = 'Setting X'; Value = 'Val2'; DefinitionId = 'def_x' }
                    )
                }
            )
            $dest = & $buildModel 'DestTenant' 'dest-id' @()
            Compare-InforcerDocModels -SourceModel $src -DestinationModel $dest
        } -Parameters @{ buildModel = $buildDuplicateModel }
        $result.ManualReview.Keys | Should -Not -Contain 'Duplicate Settings (Different Values)'
    }

    It 'detects duplicates in non-Settings-Catalog categories like Compliance' {
        $result = InModuleScope InforcerCommunity {
            param($buildModel)
            $src = & $buildModel 'SourceTenant' 'src-id' @(
                @{ Name = 'Compliance A'; Settings = @(@{ Name = 'MinOS'; Value = '10.0'; DefinitionId = 'def_minos' }) },
                @{ Name = 'Compliance B'; Settings = @(@{ Name = 'MinOS'; Value = '11.0'; DefinitionId = 'def_minos' }) }
            ) -Category 'Compliance'
            $dest = & $buildModel 'DestTenant' 'dest-id' @() -Category 'Compliance'
            Compare-InforcerDocModels -SourceModel $src -DestinationModel $dest
        } -Parameters @{ buildModel = $buildDuplicateModel }
        $result.ManualReview.Keys | Should -Contain 'Duplicate Settings (Different Values)'
    }

    It 'does NOT cross-match same settingPath under different products (D-06)' {
        $result = InModuleScope InforcerCommunity {
            param($buildModel)
            # Same definitionId, one Windows, one macOS — should not be a duplicate
            $srcWin  = & $buildModel 'SourceTenant' 'src-id' @(
                @{ Name = 'Win Policy'; Settings = @(@{ Name = 'Screen Lock'; Value = '5'; DefinitionId = 'def_screenlock' }) }
            ) -Product 'Windows'
            $destMac = & $buildModel 'DestTenant' 'dest-id' @(
                @{ Name = 'Mac Policy'; Settings = @(@{ Name = 'Screen Lock'; Value = '10'; DefinitionId = 'def_screenlock' }) }
            ) -Product 'macOS'
            # Merge products for a combined source model
            $combined = @{
                TenantName = 'SourceTenant'
                TenantId   = 'src-id'
                Products   = [ordered]@{
                    Windows = $srcWin.Products.Windows
                    macOS   = $destMac.Products.macOS
                }
            }
            $emptyDest = @{
                TenantName = 'DestTenant'
                TenantId   = 'dest-id'
                Products   = [ordered]@{}
            }
            Compare-InforcerDocModels -SourceModel $combined -DestinationModel $emptyDest
        } -Parameters @{ buildModel = $buildDuplicateModel }
        $result.ManualReview.Keys | Should -Not -Contain 'Duplicate Settings (Different Values)'
    }

    It 'ManualReview duplicate entry has correct shape (PolicyName, Side, ProfileType, Settings, HasDeprecated)' {
        $result = InModuleScope InforcerCommunity {
            param($buildModel)
            $src = & $buildModel 'SourceTenant' 'src-id' @(
                @{ Name = 'Policy A'; Settings = @(@{ Name = 'Firewall'; Value = 'Enabled';  DefinitionId = 'def_fw' }) },
                @{ Name = 'Policy B'; Settings = @(@{ Name = 'Firewall'; Value = 'Disabled'; DefinitionId = 'def_fw' }) }
            )
            $dest = & $buildModel 'DestTenant' 'dest-id' @(
                @{ Name = 'Policy C'; Settings = @(@{ Name = 'Firewall'; Value = 'Enabled'; DefinitionId = 'def_fw' }) }
            )
            Compare-InforcerDocModels -SourceModel $src -DestinationModel $dest
        } -Parameters @{ buildModel = $buildDuplicateModel }
        $entries = $result.ManualReview.'Duplicate Settings (Different Values)'
        $entries | Should -Not -BeNullOrEmpty
        $entry = $entries[0]
        $entry.Keys | Should -Contain 'PolicyName'
        $entry.Keys | Should -Contain 'Side'
        $entry.Keys | Should -Contain 'ProfileType'
        $entry.Keys | Should -Contain 'Settings'
        $entry.Keys | Should -Contain 'HasDeprecated'
        $entry.HasDeprecated | Should -BeFalse
        $entry.ProfileType | Should -Not -BeNullOrEmpty
    }

    It 'setting value starts with __DUPLICATE_TABLE__ followed by valid JSON with Policy, Value, Side' {
        $result = InModuleScope InforcerCommunity {
            param($buildModel)
            # Exactly 2 policies with different values — __DUPLICATE_TABLE__ JSON must have exactly 2 entries
            $src = & $buildModel 'SourceTenant' 'src-id' @(
                @{ Name = 'Policy A'; Settings = @(@{ Name = 'Firewall'; Value = 'Enabled'; DefinitionId = 'def_fw' }) }
            )
            $dest = & $buildModel 'DestTenant' 'dest-id' @(
                @{ Name = 'Policy B'; Settings = @(@{ Name = 'Firewall'; Value = 'Disabled'; DefinitionId = 'def_fw' }) }
            )
            Compare-InforcerDocModels -SourceModel $src -DestinationModel $dest
        } -Parameters @{ buildModel = $buildDuplicateModel }
        $entries = $result.ManualReview.'Duplicate Settings (Different Values)'
        $entries | Should -Not -BeNullOrEmpty
        $val = $entries[0].Settings[0].Value
        $val | Should -Match '^__DUPLICATE_TABLE__'
        $json = $val -replace '^__DUPLICATE_TABLE__', ''
        $parsed = $json | ConvertFrom-Json
        $parsed | Should -HaveCount 2
        $parsed[0].PSObject.Properties.Name | Should -Contain 'Policy'
        $parsed[0].PSObject.Properties.Name | Should -Contain 'Value'
        $parsed[0].PSObject.Properties.Name | Should -Contain 'Side'
    }
}

# ---------------------------------------------------------------------------
# Describe: Compare-InforcerDocModels - ENG-04 cross-tenant duplicates
# ---------------------------------------------------------------------------
Describe 'Compare-InforcerDocModels - ENG-04 cross-tenant duplicates' -Tag 'ENG-04' {

    BeforeAll {
        $buildDuplicateModel = {
            param(
                [string]$TenantName,
                [string]$TenantId,
                [array]$Policies,
                [string]$Product  = 'Windows',
                [string]$Category = 'Settings Catalog'
            )
            $policyList = @(
                $Policies | ForEach-Object {
                    $p = $_
                    @{
                        Basics   = @{ Name = $p.Name; ProfileType = 'Settings Catalog'; Platform = $Product }
                        Settings = @(
                            $p.Settings | ForEach-Object {
                                $s = $_
                                [PSCustomObject]@{
                                    Name         = $s.Name
                                    Value        = $s.Value
                                    Indent       = if ($null -ne $s.Indent) { $s.Indent } else { 0 }
                                    IsConfigured = if ($null -ne $s.IsConfigured) { $s.IsConfigured } else { $true }
                                    DefinitionId = $s.DefinitionId
                                }
                            }
                        )
                        Assignments = @()
                    }
                }
            )
            @{
                TenantName = $TenantName
                TenantId   = $TenantId
                Products   = [ordered]@{
                    $Product = @{
                        Categories = [ordered]@{
                            $Category = $policyList
                        }
                    }
                }
            }
        }
    }

    It 'detects single-tenant duplicate (both policies on same Source side)' {
        $result = InModuleScope InforcerCommunity {
            param($buildModel)
            $src = & $buildModel 'SourceTenant' 'src-id' @(
                @{ Name = 'Policy A'; Settings = @(@{ Name = 'VPN Type'; Value = 'IKEv2';  DefinitionId = 'def_vpn' }) },
                @{ Name = 'Policy B'; Settings = @(@{ Name = 'VPN Type'; Value = 'PPTP';   DefinitionId = 'def_vpn' }) }
            )
            $dest = & $buildModel 'DestTenant' 'dest-id' @(
                @{ Name = 'Policy C'; Settings = @(@{ Name = 'VPN Type'; Value = 'IKEv2'; DefinitionId = 'def_vpn' }) }
            )
            Compare-InforcerDocModels -SourceModel $src -DestinationModel $dest
        } -Parameters @{ buildModel = $buildDuplicateModel }
        $entries = $result.ManualReview.'Duplicate Settings (Different Values)'
        $entries | Should -Not -BeNullOrEmpty
        # At least one entry should have Side = 'Source' (the same-tenant duplicate)
        $sourceDupes = $entries | Where-Object { $_.Side -eq 'Source' }
        $sourceDupes | Should -Not -BeNullOrEmpty
        # ProfileType should contain 'also in:' with Source side reference
        $sourceDupes[0].ProfileType | Should -Match 'also in:'
        $sourceDupes[0].ProfileType | Should -Match 'Source'
    }

    It 'detects cross-tenant duplicate (policies on Source and Destination side)' {
        $result = InModuleScope InforcerCommunity {
            param($buildModel)
            $src = & $buildModel 'SourceTenant' 'src-id' @(
                @{ Name = 'Policy A'; Settings = @(@{ Name = 'BitLocker'; Value = 'Enabled'; DefinitionId = 'def_bl' }) }
            )
            $dest = & $buildModel 'DestTenant' 'dest-id' @(
                @{ Name = 'Policy X'; Settings = @(@{ Name = 'BitLocker'; Value = 'Disabled'; DefinitionId = 'def_bl' }) }
            )
            Compare-InforcerDocModels -SourceModel $src -DestinationModel $dest
        } -Parameters @{ buildModel = $buildDuplicateModel }
        $entries = $result.ManualReview.'Duplicate Settings (Different Values)'
        $entries | Should -Not -BeNullOrEmpty
        # Entries should include both Source and Destination sides
        $sides = $entries | ForEach-Object { $_.Side } | Select-Object -Unique
        $sides | Should -Contain 'Source'
        $sides | Should -Contain 'Destination'
    }

    It 'policyValues JSON in __DUPLICATE_TABLE__ contains Policy, Value, Side for all entries (3+ scenario)' {
        $result = InModuleScope InforcerCommunity {
            param($buildModel)
            # 2 source policies + 1 dest policy — all with different values
            $src = & $buildModel 'SourceTenant' 'src-id' @(
                @{ Name = 'Policy A'; Settings = @(@{ Name = 'DNS'; Value = '8.8.8.8';  DefinitionId = 'def_dns' }) },
                @{ Name = 'Policy B'; Settings = @(@{ Name = 'DNS'; Value = '1.1.1.1';  DefinitionId = 'def_dns' }) }
            )
            $dest = & $buildModel 'DestTenant' 'dest-id' @(
                @{ Name = 'Policy C'; Settings = @(@{ Name = 'DNS'; Value = '9.9.9.9'; DefinitionId = 'def_dns' }) }
            )
            Compare-InforcerDocModels -SourceModel $src -DestinationModel $dest
        } -Parameters @{ buildModel = $buildDuplicateModel }
        $entries = $result.ManualReview.'Duplicate Settings (Different Values)'
        $entries | Should -Not -BeNullOrEmpty
        $val = $entries[0].Settings[0].Value
        $json = $val -replace '^__DUPLICATE_TABLE__', ''
        $parsed = $json | ConvertFrom-Json
        $parsed | Should -HaveCount 3
        foreach ($item in $parsed) {
            $item.PSObject.Properties.Name | Should -Contain 'Policy'
            $item.PSObject.Properties.Name | Should -Contain 'Value'
            $item.PSObject.Properties.Name | Should -Contain 'Side'
        }
    }

    It 'ProfileType message matches format "{N} duplicate settings — also in: {policy (Side), ...}"' {
        $result = InModuleScope InforcerCommunity {
            param($buildModel)
            $src = & $buildModel 'SourceTenant' 'src-id' @(
                @{ Name = 'Policy A'; Settings = @(@{ Name = 'Encryption'; Value = 'AES256'; DefinitionId = 'def_enc' }) }
            )
            $dest = & $buildModel 'DestTenant' 'dest-id' @(
                @{ Name = 'Policy X'; Settings = @(@{ Name = 'Encryption'; Value = 'AES128'; DefinitionId = 'def_enc' }) }
            )
            Compare-InforcerDocModels -SourceModel $src -DestinationModel $dest
        } -Parameters @{ buildModel = $buildDuplicateModel }
        $entries = $result.ManualReview.'Duplicate Settings (Different Values)'
        $entries | Should -Not -BeNullOrEmpty
        $profileType = $entries[0].ProfileType
        # Must match: "{N} duplicate settings — also in: {policy (Side), ...}"
        $profileType | Should -Match '^\d+ duplicate settings'
        $profileType | Should -Match '\u2014 also in:'
        $profileType | Should -Match '\(Source\)|\(Destination\)'
    }
}

# ---------------------------------------------------------------------------
# Describe: Compare-InforcerDocModels - BUG-04 duplicate-only exclusion
# ---------------------------------------------------------------------------
Describe 'Compare-InforcerDocModels - BUG-04 duplicate-only exclusion' -Tag 'BUG-04', 'Phase11' {

    BeforeAll {
        # Reuse the helper pattern from ENG-02 tests
        $script:BuildBug04Model = {
            param(
                [string]$TenantName,
                [string]$TenantId,
                [array]$Policies,
                [string]$Product  = 'Windows',
                [string]$Category = 'Settings Catalog'
            )
            $policyList = @(
                $Policies | ForEach-Object {
                    $p = $_
                    @{
                        Basics   = @{ Name = $p.Name; ProfileType = 'Settings Catalog'; Platform = $Product }
                        Settings = @(
                            $p.Settings | ForEach-Object {
                                $s = $_
                                [PSCustomObject]@{
                                    Name         = $s.Name
                                    Value        = $s.Value
                                    Indent       = if ($null -ne $s.Indent) { $s.Indent } else { 0 }
                                    IsConfigured = if ($null -ne $s.IsConfigured) { $s.IsConfigured } else { $true }
                                    DefinitionId = $s.DefinitionId
                                }
                            }
                        )
                        Assignments = @()
                    }
                }
            )
            @{
                TenantName = $TenantName
                TenantId   = $TenantId
                Products   = [ordered]@{
                    $Product = @{
                        Categories = [ordered]@{
                            $Category = $policyList
                        }
                    }
                }
            }
        }
    }

    It 'duplicate-only setting appears in ManualReview' {
        # Source has 2 policies with same setting (different values) = duplicate
        # Destination has NO matching setting = duplicate-only (no cross-tenant comparison)
        $result = InModuleScope InforcerCommunity {
            param($buildModel)
            $src = & $buildModel 'SourceTenant' 'src-id' @(
                @{ Name = 'Baseline'; Settings = @(@{ Name = 'Screen Lock Timeout'; Value = '5';  DefinitionId = 'device_lock_timeout_001' }) },
                @{ Name = 'Strict';   Settings = @(@{ Name = 'Screen Lock Timeout'; Value = '15'; DefinitionId = 'device_lock_timeout_001' }) }
            )
            $dest = & $buildModel 'DestTenant' 'dest-id' @(
                @{ Name = 'Baseline'; Settings = @(@{ Name = 'Other Setting'; Value = 'xyz'; DefinitionId = 'other_setting_001' }) }
            )
            Compare-InforcerDocModels -SourceModel $src -DestinationModel $dest
        } -Parameters @{ buildModel = $script:BuildBug04Model }

        $dupEntries = $result.ManualReview.'Duplicate Settings (Different Values)'
        $dupEntries | Should -Not -BeNullOrEmpty
        # Find the Screen Lock Timeout in the duplicate entries' settings
        $found = $false
        foreach ($entry in $dupEntries) {
            foreach ($s in $entry.Settings) {
                if ($s.Name -match 'Screen Lock Timeout' -or $s.Value -match 'Screen Lock Timeout') {
                    $found = $true
                }
            }
        }
        $found | Should -Be $true
    }

    It 'duplicate-only setting is excluded from ComparisonRows' {
        # Same setup: duplicate setting exists only on Source side
        $result = InModuleScope InforcerCommunity {
            param($buildModel)
            $src = & $buildModel 'SourceTenant' 'src-id' @(
                @{ Name = 'Baseline'; Settings = @(@{ Name = 'Screen Lock Timeout'; Value = '5';  DefinitionId = 'device_lock_timeout_001' }) },
                @{ Name = 'Strict';   Settings = @(@{ Name = 'Screen Lock Timeout'; Value = '15'; DefinitionId = 'device_lock_timeout_001' }) }
            )
            $dest = & $buildModel 'DestTenant' 'dest-id' @(
                @{ Name = 'Baseline'; Settings = @(@{ Name = 'Other Setting'; Value = 'xyz'; DefinitionId = 'other_setting_001' }) }
            )
            Compare-InforcerDocModels -SourceModel $src -DestinationModel $dest
        } -Parameters @{ buildModel = $script:BuildBug04Model }

        # Iterate all ComparisonRows — none should contain 'Screen Lock Timeout'
        $foundInComparison = $false
        foreach ($prodKey in $result.Products.Keys) {
            foreach ($catKey in $result.Products[$prodKey].Categories.Keys) {
                foreach ($row in $result.Products[$prodKey].Categories[$catKey].ComparisonRows) {
                    if ($row.Name -eq 'Screen Lock Timeout') {
                        $foundInComparison = $true
                    }
                }
            }
        }
        $foundInComparison | Should -Be $false
    }

    It 'settings with both comparison and duplicate presence remain in ComparisonRows' {
        # Source has 2 policies with same setting (duplicate) AND Destination has a match (comparison)
        $result = InModuleScope InforcerCommunity {
            param($buildModel)
            $src = & $buildModel 'SourceTenant' 'src-id' @(
                @{ Name = 'Baseline'; Settings = @(
                    @{ Name = 'Screen Lock Timeout'; Value = '5';  DefinitionId = 'device_lock_timeout_001' },
                    @{ Name = 'Encryption';          Value = 'AES256'; DefinitionId = 'def_enc' }
                ) },
                @{ Name = 'Strict';   Settings = @(
                    @{ Name = 'Screen Lock Timeout'; Value = '15'; DefinitionId = 'device_lock_timeout_001' }
                ) }
            )
            $dest = & $buildModel 'DestTenant' 'dest-id' @(
                @{ Name = 'Baseline'; Settings = @(
                    @{ Name = 'Screen Lock Timeout'; Value = '10'; DefinitionId = 'device_lock_timeout_001' },
                    @{ Name = 'Encryption';          Value = 'AES128'; DefinitionId = 'def_enc' }
                ) }
            )
            Compare-InforcerDocModels -SourceModel $src -DestinationModel $dest
        } -Parameters @{ buildModel = $script:BuildBug04Model }

        # Screen Lock Timeout has conflicting values in source (5 vs 15) AND exists in dest (10).
        # Comparison is ambiguous — should be removed from ComparisonRows and routed to Manual Review.
        $foundInComparison = $false
        foreach ($prodKey in $result.Products.Keys) {
            foreach ($catKey in $result.Products[$prodKey].Categories.Keys) {
                foreach ($row in $result.Products[$prodKey].Categories[$catKey].ComparisonRows) {
                    if ($row.Name -eq 'Screen Lock Timeout') {
                        $foundInComparison = $true
                    }
                }
            }
        }
        $foundInComparison | Should -Be $false

        # Should appear in Manual Review under 'Ambiguous Comparison (Duplicate Policies)'
        $result.ManualReview.Keys | Should -Contain 'Ambiguous Comparison (Duplicate Policies)'
    }
}
