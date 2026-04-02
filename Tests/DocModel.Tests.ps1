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
