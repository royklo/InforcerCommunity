# GraphResolution.Tests.ps1
# Pester 5.x tests for Graph resolution fixes (issue #11).
# Run from repo root: Invoke-Pester ./Tests/GraphResolution.Tests.ps1

$ErrorActionPreference = 'Stop'

BeforeAll {
    Remove-Module -Name 'InforcerCommunity' -ErrorAction SilentlyContinue
    $here = $PSScriptRoot
    $manifestPath = Join-Path $here '..' 'module' 'InforcerCommunity.psd1'
    $manifestPath = [System.IO.Path]::GetFullPath($manifestPath)
    Import-Module $manifestPath -Force -ErrorAction Stop
}

# ---------------------------------------------------------------------------
# Resolve-InforcerAssignments: filter fallback to assignment level
# ---------------------------------------------------------------------------
Describe 'Resolve-InforcerAssignments — filter on assignment level' {

    It 'resolves filter when properties are on target (standard Graph structure)' {
        $result = InModuleScope InforcerCommunity {
            $filterMap = @{
                'f1111111-1111-1111-1111-111111111111' = [PSCustomObject]@{
                    displayName = 'Corporate devices'
                    rule        = '(device.manufacturer -eq "Microsoft")'
                }
            }
            Resolve-InforcerAssignments -RawAssignments @(
                [PSCustomObject]@{
                    target = [PSCustomObject]@{
                        '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget'
                        deviceAndAppManagementAssignmentFilterId   = 'f1111111-1111-1111-1111-111111111111'
                        deviceAndAppManagementAssignmentFilterType = 'include'
                    }
                }
            ) -FilterMap $filterMap
        }
        $result | Should -HaveCount 1
        $result[0].Target | Should -Be 'All Devices'
        $result[0].Filter | Should -Be 'Corporate devices'
        $result[0].FilterMode | Should -Be 'Include'
    }

    It 'resolves filter when properties are on assignment (API wrapper variant)' {
        $result = InModuleScope InforcerCommunity {
            $filterMap = @{
                'f2222222-2222-2222-2222-222222222222' = [PSCustomObject]@{
                    displayName = 'BYOD filter'
                    rule        = '(device.isPersonal -eq "True")'
                }
            }
            Resolve-InforcerAssignments -RawAssignments @(
                [PSCustomObject]@{
                    target = [PSCustomObject]@{
                        '@odata.type' = '#microsoft.graph.allLicensedUsersAssignmentTarget'
                    }
                    deviceAndAppManagementAssignmentFilterId   = 'f2222222-2222-2222-2222-222222222222'
                    deviceAndAppManagementAssignmentFilterType = 'exclude'
                }
            ) -FilterMap $filterMap
        }
        $result | Should -HaveCount 1
        $result[0].Target | Should -Be 'All Users'
        $result[0].Filter | Should -Be 'BYOD filter'
        $result[0].FilterMode | Should -Be 'Exclude'
    }

    It 'shows no filter when neither target nor assignment has filter properties' {
        $result = InModuleScope InforcerCommunity {
            Resolve-InforcerAssignments -RawAssignments @(
                [PSCustomObject]@{
                    target = [PSCustomObject]@{
                        '@odata.type' = '#microsoft.graph.allDevicesAssignmentTarget'
                    }
                }
            ) -FilterMap @{}
        }
        $result | Should -HaveCount 1
        $result[0].Filter | Should -BeNullOrEmpty
    }
}

# ---------------------------------------------------------------------------
# ConvertTo-InforcerDocModel: GUID resolution in CA policy settings
# ---------------------------------------------------------------------------
Describe 'ConvertTo-InforcerDocModel — CA GUID resolution' {

    It 'resolves group GUIDs in flat settings values' {
        $result = InModuleScope InforcerCommunity {
            $groupNameMap = @{
                'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee' = 'Finance Team'
            }
            $docData = @{
                Tenant      = [PSCustomObject]@{ tenantFriendlyName = 'Test' }
                Baselines   = @()
                Policies    = @(
                    [PSCustomObject]@{
                        product     = 'Conditional Access'
                        primaryGroup = 'Policies'
                        secondaryGroup = $null
                        policyTypeId = 99
                        displayName = 'Test CA Policy'
                        inforcerPolicyTypeName = 'conditionalAccessPolicy'
                        tags = @()
                        policyData = [PSCustomObject]@{
                            displayName = 'Test CA Policy'
                            description = ''
                            conditions = [PSCustomObject]@{
                                users = [PSCustomObject]@{
                                    includeGroups = @('aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee')
                                }
                            }
                        }
                    }
                )
                TenantId    = 1
                CollectedAt = [datetime]::UtcNow
            }
            ConvertTo-InforcerDocModel -DocData $docData -GroupNameMap $groupNameMap
        }

        # Find the CA policy and check its settings contain the resolved group name
        $caPolicy = $result.Products.Values | ForEach-Object { $_.Categories.Values } |
            ForEach-Object { $_ } | Where-Object { $_.Basics.Name -eq 'Test CA Policy' }
        $caPolicy | Should -Not -BeNullOrEmpty
        $groupSetting = $caPolicy.Settings | Where-Object { $_.Value -eq 'Finance Team' }
        $groupSetting | Should -Not -BeNullOrEmpty
    }

    It 'resolves role GUIDs in flat settings values' {
        $result = InModuleScope InforcerCommunity {
            $roleNameMap = @{
                '62e90394-69f5-4237-9190-012177145e10' = 'Global Administrator'
            }
            $docData = @{
                Tenant      = [PSCustomObject]@{ tenantFriendlyName = 'Test' }
                Baselines   = @()
                Policies    = @(
                    [PSCustomObject]@{
                        product     = 'Conditional Access'
                        primaryGroup = 'Policies'
                        secondaryGroup = $null
                        policyTypeId = 99
                        displayName = 'MFA for Admins'
                        inforcerPolicyTypeName = 'conditionalAccessPolicy'
                        tags = @()
                        policyData = [PSCustomObject]@{
                            displayName = 'MFA for Admins'
                            description = ''
                            conditions = [PSCustomObject]@{
                                users = [PSCustomObject]@{
                                    includeRoles = @('62e90394-69f5-4237-9190-012177145e10')
                                }
                            }
                        }
                    }
                )
                TenantId    = 1
                CollectedAt = [datetime]::UtcNow
            }
            ConvertTo-InforcerDocModel -DocData $docData -RoleNameMap $roleNameMap
        }

        $caPolicy = $result.Products.Values | ForEach-Object { $_.Categories.Values } |
            ForEach-Object { $_ } | Where-Object { $_.Basics.Name -eq 'MFA for Admins' }
        $caPolicy | Should -Not -BeNullOrEmpty
        $roleSetting = $caPolicy.Settings | Where-Object { $_.Value -eq 'Global Administrator' }
        $roleSetting | Should -Not -BeNullOrEmpty
    }

    It 'resolves comma-separated GUIDs in a single value' {
        $result = InModuleScope InforcerCommunity {
            $groupNameMap = @{
                'aaaaaaaa-1111-2222-3333-444444444444' = 'Group A'
                'bbbbbbbb-1111-2222-3333-444444444444' = 'Group B'
            }
            $docData = @{
                Tenant      = [PSCustomObject]@{ tenantFriendlyName = 'Test' }
                Baselines   = @()
                Policies    = @(
                    [PSCustomObject]@{
                        product     = 'Conditional Access'
                        primaryGroup = 'Policies'
                        secondaryGroup = $null
                        policyTypeId = 99
                        displayName = 'Multi-group CA'
                        inforcerPolicyTypeName = 'conditionalAccessPolicy'
                        tags = @()
                        policyData = [PSCustomObject]@{
                            displayName = 'Multi-group CA'
                            description = ''
                            conditions = [PSCustomObject]@{
                                users = [PSCustomObject]@{
                                    includeGroups = @('aaaaaaaa-1111-2222-3333-444444444444', 'bbbbbbbb-1111-2222-3333-444444444444')
                                }
                            }
                        }
                    }
                )
                TenantId    = 1
                CollectedAt = [datetime]::UtcNow
            }
            ConvertTo-InforcerDocModel -DocData $docData -GroupNameMap $groupNameMap
        }

        $caPolicy = $result.Products.Values | ForEach-Object { $_.Categories.Values } |
            ForEach-Object { $_ } | Where-Object { $_.Basics.Name -eq 'Multi-group CA' }
        $caPolicy | Should -Not -BeNullOrEmpty
        # Both resolved group names should be in one comma-separated value
        $groupSetting = $caPolicy.Settings | Where-Object { $_.Name -eq 'Include Groups' -and $_.Value -match 'Group A' -and $_.Value -match 'Group B' }
        $groupSetting | Should -Not -BeNullOrEmpty
    }

    It 'resolves named location GUIDs in flat settings values' {
        $result = InModuleScope InforcerCommunity {
            $locationNameMap = @{
                '1ae7b9a2-1741-4a96-ae39-6c0edb057049' = 'Trusted corporate network'
            }
            $docData = @{
                Tenant      = [PSCustomObject]@{ tenantFriendlyName = 'Test' }
                Baselines   = @()
                Policies    = @(
                    [PSCustomObject]@{
                        product     = 'Conditional Access'
                        primaryGroup = 'Policies'
                        secondaryGroup = $null
                        policyTypeId = 99
                        displayName = 'Block untrusted locations'
                        inforcerPolicyTypeName = 'conditionalAccessPolicy'
                        tags = @()
                        policyData = [PSCustomObject]@{
                            displayName = 'Block untrusted locations'
                            description = ''
                            conditions = [PSCustomObject]@{
                                locations = [PSCustomObject]@{
                                    excludeLocations = @('1ae7b9a2-1741-4a96-ae39-6c0edb057049')
                                }
                            }
                        }
                    }
                )
                TenantId    = 1
                CollectedAt = [datetime]::UtcNow
            }
            ConvertTo-InforcerDocModel -DocData $docData -LocationNameMap $locationNameMap
        }

        $caPolicy = $result.Products.Values | ForEach-Object { $_.Categories.Values } |
            ForEach-Object { $_ } | Where-Object { $_.Basics.Name -eq 'Block untrusted locations' }
        $caPolicy | Should -Not -BeNullOrEmpty
        $locationSetting = $caPolicy.Settings | Where-Object { $_.Value -eq 'Trusted corporate network' }
        $locationSetting | Should -Not -BeNullOrEmpty
    }

    It 'leaves non-GUID values untouched' {
        $result = InModuleScope InforcerCommunity {
            $groupNameMap = @{ 'aaaaaaaa-1111-2222-3333-444444444444' = 'SomeGroup' }
            $docData = @{
                Tenant      = [PSCustomObject]@{ tenantFriendlyName = 'Test' }
                Baselines   = @()
                Policies    = @(
                    [PSCustomObject]@{
                        product     = 'Conditional Access'
                        primaryGroup = 'Policies'
                        secondaryGroup = $null
                        policyTypeId = 99
                        displayName = 'Simple CA'
                        inforcerPolicyTypeName = 'conditionalAccessPolicy'
                        tags = @()
                        policyData = [PSCustomObject]@{
                            displayName = 'Simple CA'
                            description = ''
                            state = 'enabled'
                        }
                    }
                )
                TenantId    = 1
                CollectedAt = [datetime]::UtcNow
            }
            ConvertTo-InforcerDocModel -DocData $docData -GroupNameMap $groupNameMap
        }

        $caPolicy = $result.Products.Values | ForEach-Object { $_.Categories.Values } |
            ForEach-Object { $_ } | Where-Object { $_.Basics.Name -eq 'Simple CA' }
        $stateSetting = $caPolicy.Settings | Where-Object { $_.Name -eq 'state' }
        $stateSetting.Value | Should -Be 'enabled'
    }
}
