# Compare-InforcerEnvironments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a cmdlet that compares two M365 environments (tenant/baseline) and produces a self-contained HTML comparison report with alignment score, conflict detection, and manual review classification.

**Architecture:** Three-stage pipeline mirroring `Export-InforcerTenantDocumentation`: Stage 1 collects policy data from both environments via session swapping, Stage 2 builds a comparison model with setting-level matching for Intune Settings Catalog and policy-level matching for everything else, Stage 3 renders a self-contained HTML report with animated score, tabbed layout, and dark/light mode.

**Tech Stack:** PowerShell 7.0+, `[System.Text.StringBuilder]` for HTML assembly, embedded CSS/JS, `ConvertFrom-Json -AsHashtable`, existing module helpers (`Resolve-InforcerTenantId`, `Import-InforcerSettingsCatalog`, etc.)

**Spec:** `docs/superpowers/specs/2026-04-02-compare-inforcer-environments-design.md`

**HTML mockup reference:** `.superpowers/brainstorm/89384-1775162215/report-mockup-v4.html`

---

## File Structure

| Action | Path | Responsibility |
|--------|------|----------------|
| Modify | `module/Public/Connect-Inforcer.ps1` | Add `-PassThru` switch |
| Create | `module/Private/Get-InforcerComparisonData.ps1` | Stage 1: fetch policies from both environments |
| Create | `module/Private/ConvertTo-InforcerComparisonModel.ps1` | Stage 2: comparison engine (setting-level + policy-level) |
| Create | `module/Private/ConvertTo-InforcerComparisonHtml.ps1` | Stage 3: HTML renderer |
| Create | `module/Public/Compare-InforcerEnvironments.ps1` | Public cmdlet orchestrating the pipeline |
| Modify | `module/InforcerCommunity.psd1` | Add `Compare-InforcerEnvironments` to `FunctionsToExport` |
| Modify | `Tests/Consistency.Tests.ps1` | Add test entries for new cmdlet + Connect-Inforcer `-PassThru` |
| Create | `Tests/ComparisonModel.Tests.ps1` | Unit tests for the comparison engine |

---

### Task 1: Add `-PassThru` to Connect-Inforcer

**Files:**
- Modify: `module/Public/Connect-Inforcer.ps1`
- Modify: `Tests/Consistency.Tests.ps1`

- [ ] **Step 1: Add `-PassThru` parameter to Connect-Inforcer**

In `module/Public/Connect-Inforcer.ps1`, add the `PassThru` switch after the `FetchGraphData` parameter (around line 56):

```powershell
    [Parameter(Mandatory = $false)]
    [switch]$FetchGraphData,

    [Parameter(Mandatory = $false)]
    [switch]$PassThru
)
```

- [ ] **Step 2: Update Connect-Inforcer help block**

Add `.PARAMETER PassThru` documentation and update `.OUTPUTS` in the comment-based help at the top of the function:

```powershell
.PARAMETER PassThru
    When specified, returns the session hashtable to the pipeline in addition to
    storing it in the module-scoped session variable. Use this to capture sessions
    for cross-account comparison with Compare-InforcerEnvironments.
```

- [ ] **Step 3: Add PassThru output logic**

After the session is stored in `$script:InforcerSession` (around line 132) and before the existing output block (line 145), add:

```powershell
if ($PassThru) {
    # Return a clone of the session hashtable so callers have an independent copy
    $sessionCopy = @{
        ApiKey      = $script:InforcerSession.ApiKey
        BaseUrl     = $script:InforcerSession.BaseUrl
        Region      = $script:InforcerSession.Region
        ConnectedAt = $script:InforcerSession.ConnectedAt
    }
    Write-Output $sessionCopy
}
```

- [ ] **Step 4: Update consistency test expected parameters**

In `Tests/Consistency.Tests.ps1`, find the `expectedParameters` hashtable (line 41) and update the Connect-Inforcer entry:

```powershell
'Connect-Inforcer'              = @('ApiKey', 'Region', 'BaseUrl', 'FetchGraphData', 'PassThru')
```

- [ ] **Step 5: Run consistency tests**

Run: `pwsh -Command "Invoke-Pester ./Tests/Consistency.Tests.ps1 -Output Detailed"`
Expected: All tests pass (Connect-Inforcer now has PassThru in expected params)

- [ ] **Step 6: Commit**

```bash
git add module/Public/Connect-Inforcer.ps1 Tests/Consistency.Tests.ps1
git commit -m "feat: add -PassThru switch to Connect-Inforcer for cross-session comparison"
```

---

### Task 2: Create Get-InforcerComparisonData (Stage 1 — Data Collection)

**Files:**
- Create: `module/Private/Get-InforcerComparisonData.ps1`

- [ ] **Step 1: Create the data collection function**

Create `module/Private/Get-InforcerComparisonData.ps1`:

```powershell
function Get-InforcerComparisonData {
    <#
    .SYNOPSIS
        Collects policy data from two environments for comparison.
    .DESCRIPTION
        Fetches policies from a source and destination environment (each can be a tenant
        or baseline) using session swapping to support cross-account comparison. Returns
        a hashtable bundle consumed by ConvertTo-InforcerComparisonModel.
    .PARAMETER SourceTenantId
        Source tenant identifier (numeric ID, GUID, or name). Mutually exclusive with SourceBaselineId.
    .PARAMETER DestinationTenantId
        Destination tenant identifier. Mutually exclusive with DestinationBaselineId.
    .PARAMETER SourceBaselineId
        Source baseline GUID or name. When provided, fetches the baseline's tenant policies.
    .PARAMETER DestinationBaselineId
        Destination baseline GUID or name.
    .PARAMETER SourceSession
        Session hashtable from Connect-Inforcer -PassThru for the source environment.
        If omitted, uses $script:InforcerSession.
    .PARAMETER DestinationSession
        Session hashtable for the destination environment.
        If omitted, uses $script:InforcerSession.
    .PARAMETER SettingsCatalogPath
        Path to settings.json. Auto-discovers if omitted.
    .PARAMETER IncludingAssignments
        When set, includes assignment data from policyData (informational only).
    .OUTPUTS
        Hashtable with keys: SourcePolicies, DestinationPolicies, SourceName, DestinationName,
        SourceType, DestinationType, SettingsCatalog, IncludingAssignments, CollectedAt
    #>
    [CmdletBinding()]
    param(
        [Parameter()] [object]$SourceTenantId,
        [Parameter()] [object]$DestinationTenantId,
        [Parameter()] [string]$SourceBaselineId,
        [Parameter()] [string]$DestinationBaselineId,
        [Parameter()] [hashtable]$SourceSession,
        [Parameter()] [hashtable]$DestinationSession,
        [Parameter()] [string]$SettingsCatalogPath,
        [Parameter()] [switch]$IncludingAssignments
    )

    # Default sessions to current connection
    if (-not $SourceSession) { $SourceSession = $script:InforcerSession }
    if (-not $DestinationSession) { $DestinationSession = $script:InforcerSession }

    # Load Settings Catalog (session-independent)
    Import-InforcerSettingsCatalog -Path $SettingsCatalogPath

    $originalSession = $script:InforcerSession

    try {
        # --- Source side ---
        $script:InforcerSession = $SourceSession
        $sourceType = 'Tenant'
        $sourceName = ''

        if (-not [string]::IsNullOrWhiteSpace($SourceBaselineId)) {
            $sourceType = 'Baseline'
            Write-Host '  Resolving source baseline...' -ForegroundColor Gray
            $resolvedBaselineId = Resolve-InforcerBaselineId -BaselineId $SourceBaselineId
            $baselineJson = Get-InforcerBaseline -OutputType JsonObject
            $baselines = $baselineJson | ConvertFrom-Json -Depth 100
            $baselineObj = $baselines | Where-Object { $_.id -eq $resolvedBaselineId } | Select-Object -First 1
            if (-not $baselineObj) {
                throw "Source baseline '$SourceBaselineId' not found."
            }
            $sourceName = $baselineObj.name
            $sourceTenantIdResolved = $baselineObj.baselineTenantId
        } else {
            $sourceTenantIdResolved = Resolve-InforcerTenantId -TenantId $SourceTenantId
            # Get tenant name
            $tenantJson = Get-InforcerTenant -TenantId $sourceTenantIdResolved -OutputType JsonObject
            $tenantObj = $tenantJson | ConvertFrom-Json -Depth 100
            if ($tenantObj -is [array]) { $tenantObj = $tenantObj | Select-Object -First 1 }
            $sourceName = if ($tenantObj.tenantFriendlyName) { $tenantObj.tenantFriendlyName } else { "Tenant $sourceTenantIdResolved" }
        }

        Write-Host "  Collecting source policies ($sourceName)..." -ForegroundColor Gray
        $sourcePoliciesJson = Get-InforcerTenantPolicies -TenantId $sourceTenantIdResolved -OutputType JsonObject
        $sourcePolicies = $sourcePoliciesJson | ConvertFrom-Json -Depth 100

        # --- Destination side ---
        $script:InforcerSession = $DestinationSession
        $destType = 'Tenant'
        $destName = ''

        if (-not [string]::IsNullOrWhiteSpace($DestinationBaselineId)) {
            $destType = 'Baseline'
            Write-Host '  Resolving destination baseline...' -ForegroundColor Gray
            $resolvedDestBaselineId = Resolve-InforcerBaselineId -BaselineId $DestinationBaselineId
            $destBaselineJson = Get-InforcerBaseline -OutputType JsonObject
            $destBaselines = $destBaselineJson | ConvertFrom-Json -Depth 100
            $destBaselineObj = $destBaselines | Where-Object { $_.id -eq $resolvedDestBaselineId } | Select-Object -First 1
            if (-not $destBaselineObj) {
                throw "Destination baseline '$DestinationBaselineId' not found."
            }
            $destName = $destBaselineObj.name
            $destTenantIdResolved = $destBaselineObj.baselineTenantId
        } else {
            $destTenantIdResolved = Resolve-InforcerTenantId -TenantId $DestinationTenantId
            $destTenantJson = Get-InforcerTenant -TenantId $destTenantIdResolved -OutputType JsonObject
            $destTenantObj = $destTenantJson | ConvertFrom-Json -Depth 100
            if ($destTenantObj -is [array]) { $destTenantObj = $destTenantObj | Select-Object -First 1 }
            $destName = if ($destTenantObj.tenantFriendlyName) { $destTenantObj.tenantFriendlyName } else { "Tenant $destTenantIdResolved" }
        }

        Write-Host "  Collecting destination policies ($destName)..." -ForegroundColor Gray
        $destPoliciesJson = Get-InforcerTenantPolicies -TenantId $destTenantIdResolved -OutputType JsonObject
        $destPolicies = $destPoliciesJson | ConvertFrom-Json -Depth 100

    } finally {
        $script:InforcerSession = $originalSession
    }

    @{
        SourcePolicies        = @($sourcePolicies)
        DestinationPolicies   = @($destPolicies)
        SourceName            = $sourceName
        DestinationName       = $destName
        SourceType            = $sourceType
        DestinationType       = $destType
        SettingsCatalog       = $script:InforcerSettingsCatalog
        IncludingAssignments  = $IncludingAssignments.IsPresent
        CollectedAt           = [datetime]::UtcNow
    }
}
```

- [ ] **Step 2: Verify the file loads without errors**

Run: `pwsh -Command "Import-Module ./module/InforcerCommunity.psd1 -Force -ErrorAction Stop; Write-Host 'OK'"`
Expected: `OK` (no parse errors)

- [ ] **Step 3: Commit**

```bash
git add module/Private/Get-InforcerComparisonData.ps1
git commit -m "feat: add Get-InforcerComparisonData for cross-environment policy collection"
```

---

### Task 3: Create ConvertTo-InforcerComparisonModel (Stage 2 — Comparison Engine)

**Files:**
- Create: `module/Private/ConvertTo-InforcerComparisonModel.ps1`
- Create: `Tests/ComparisonModel.Tests.ps1`

- [ ] **Step 1: Write unit tests for the comparison model**

Create `Tests/ComparisonModel.Tests.ps1`:

```powershell
BeforeAll {
    $modulePath = Join-Path $PSScriptRoot '..' 'module' 'InforcerCommunity.psd1'
    Import-Module $modulePath -Force
}

Describe 'ConvertTo-InforcerComparisonModel' {

    BeforeAll {
        # Minimal Settings Catalog for testing
        $script:InforcerSettingsCatalog = @{
            'device_vendor_msft_bitlocker_requiredeviceencryption' = @{
                DisplayName = 'Require Device Encryption'
                Description = ''
                Options     = @{ '1' = 'Enabled'; '0' = 'Disabled' }
            }
            'device_vendor_msft_policy_config_defender_allowrealtimemonitoring' = @{
                DisplayName = 'Allow Realtime Monitoring'
                Description = ''
                Options     = @{ '1' = 'Allowed'; '0' = 'Not Allowed' }
            }
            'device_vendor_msft_policy_config_pinlength' = @{
                DisplayName = 'Minimum PIN Length'
                Description = ''
                Options     = @{}
            }
        }
    }

    Context 'Settings Catalog — setting-level matching' {

        It 'Marks identical settings as Matched even when in different policies' {
            $compData = @{
                SourcePolicies = @(
                    [PSCustomObject]@{
                        policyTypeId = 10; product = 'Intune'; primaryGroup = 'Device Configuration'
                        secondaryGroup = 'Security'; displayName = 'Policy A'
                        policyData = [PSCustomObject]@{
                            settingDefinitions = @(
                                [PSCustomObject]@{
                                    settingInstance = [PSCustomObject]@{
                                        settingDefinitionId = 'device_vendor_msft_bitlocker_requiredeviceencryption'
                                        '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                                        choiceSettingValue = [PSCustomObject]@{
                                            value = 'device_vendor_msft_bitlocker_requiredeviceencryption_1'
                                            children = @()
                                        }
                                    }
                                }
                            )
                        }
                    }
                )
                DestinationPolicies = @(
                    [PSCustomObject]@{
                        policyTypeId = 10; product = 'Intune'; primaryGroup = 'Device Configuration'
                        secondaryGroup = 'Security'; displayName = 'Policy B'
                        policyData = [PSCustomObject]@{
                            settingDefinitions = @(
                                [PSCustomObject]@{
                                    settingInstance = [PSCustomObject]@{
                                        settingDefinitionId = 'device_vendor_msft_bitlocker_requiredeviceencryption'
                                        '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                                        choiceSettingValue = [PSCustomObject]@{
                                            value = 'device_vendor_msft_bitlocker_requiredeviceencryption_1'
                                            children = @()
                                        }
                                    }
                                }
                            )
                        }
                    }
                )
                SourceName = 'Source'; DestinationName = 'Dest'
                SourceType = 'Tenant'; DestinationType = 'Tenant'
                SettingsCatalog = $script:InforcerSettingsCatalog
                IncludingAssignments = $false
                CollectedAt = [datetime]::UtcNow
            }

            $model = ConvertTo-InforcerComparisonModel -ComparisonData $compData
            $model.Counters.Matched | Should -Be 1
            $model.Counters.Conflicting | Should -Be 0
            $model.AlignmentScore | Should -Be 100
        }

        It 'Marks settings with different values as Conflicting' {
            $compData = @{
                SourcePolicies = @(
                    [PSCustomObject]@{
                        policyTypeId = 10; product = 'Intune'; primaryGroup = 'Device Configuration'
                        secondaryGroup = 'Security'; displayName = 'Source Policy'
                        policyData = [PSCustomObject]@{
                            settingDefinitions = @(
                                [PSCustomObject]@{
                                    settingInstance = [PSCustomObject]@{
                                        settingDefinitionId = 'device_vendor_msft_policy_config_pinlength'
                                        '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance'
                                        simpleSettingValue = [PSCustomObject]@{
                                            '@odata.type' = '#microsoft.graph.deviceManagementConfigurationIntegerSettingValue'
                                            value = 6
                                        }
                                    }
                                }
                            )
                        }
                    }
                )
                DestinationPolicies = @(
                    [PSCustomObject]@{
                        policyTypeId = 10; product = 'Intune'; primaryGroup = 'Device Configuration'
                        secondaryGroup = 'Security'; displayName = 'Dest Policy'
                        policyData = [PSCustomObject]@{
                            settingDefinitions = @(
                                [PSCustomObject]@{
                                    settingInstance = [PSCustomObject]@{
                                        settingDefinitionId = 'device_vendor_msft_policy_config_pinlength'
                                        '@odata.type' = '#microsoft.graph.deviceManagementConfigurationSimpleSettingInstance'
                                        simpleSettingValue = [PSCustomObject]@{
                                            '@odata.type' = '#microsoft.graph.deviceManagementConfigurationIntegerSettingValue'
                                            value = 4
                                        }
                                    }
                                }
                            )
                        }
                    }
                )
                SourceName = 'Source'; DestinationName = 'Dest'
                SourceType = 'Tenant'; DestinationType = 'Tenant'
                SettingsCatalog = $script:InforcerSettingsCatalog
                IncludingAssignments = $false
                CollectedAt = [datetime]::UtcNow
            }

            $model = ConvertTo-InforcerComparisonModel -ComparisonData $compData
            $model.Counters.Conflicting | Should -Be 1
            $model.Counters.Matched | Should -Be 0
        }

        It 'Classifies source-only and dest-only settings correctly' {
            $compData = @{
                SourcePolicies = @(
                    [PSCustomObject]@{
                        policyTypeId = 10; product = 'Intune'; primaryGroup = 'Device Configuration'
                        secondaryGroup = 'Security'; displayName = 'Source Only Policy'
                        policyData = [PSCustomObject]@{
                            settingDefinitions = @(
                                [PSCustomObject]@{
                                    settingInstance = [PSCustomObject]@{
                                        settingDefinitionId = 'device_vendor_msft_bitlocker_requiredeviceencryption'
                                        '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                                        choiceSettingValue = [PSCustomObject]@{
                                            value = 'device_vendor_msft_bitlocker_requiredeviceencryption_1'
                                            children = @()
                                        }
                                    }
                                }
                            )
                        }
                    }
                )
                DestinationPolicies = @(
                    [PSCustomObject]@{
                        policyTypeId = 10; product = 'Intune'; primaryGroup = 'Device Configuration'
                        secondaryGroup = 'Security'; displayName = 'Dest Only Policy'
                        policyData = [PSCustomObject]@{
                            settingDefinitions = @(
                                [PSCustomObject]@{
                                    settingInstance = [PSCustomObject]@{
                                        settingDefinitionId = 'device_vendor_msft_policy_config_defender_allowrealtimemonitoring'
                                        '@odata.type' = '#microsoft.graph.deviceManagementConfigurationChoiceSettingInstance'
                                        choiceSettingValue = [PSCustomObject]@{
                                            value = 'device_vendor_msft_policy_config_defender_allowrealtimemonitoring_1'
                                            children = @()
                                        }
                                    }
                                }
                            )
                        }
                    }
                )
                SourceName = 'Source'; DestinationName = 'Dest'
                SourceType = 'Tenant'; DestinationType = 'Tenant'
                SettingsCatalog = $script:InforcerSettingsCatalog
                IncludingAssignments = $false
                CollectedAt = [datetime]::UtcNow
            }

            $model = ConvertTo-InforcerComparisonModel -ComparisonData $compData
            $model.Counters.SourceOnly | Should -Be 1
            $model.Counters.DestOnly | Should -Be 1
            $model.Counters.Matched | Should -Be 0
            $model.AlignmentScore | Should -Be 0
        }
    }

    Context 'Policy-level matching (non-Settings-Catalog)' {

        It 'Matches non-SC policies by PolicyTypeId + Product + PrimaryGroup + Name' {
            $compData = @{
                SourcePolicies = @(
                    [PSCustomObject]@{
                        policyTypeId = 2; product = 'Entra ID'; primaryGroup = 'Conditional Access'
                        secondaryGroup = ''; displayName = 'Require MFA for Admins'
                        policyData = [PSCustomObject]@{ state = 'enabled' }
                    }
                )
                DestinationPolicies = @(
                    [PSCustomObject]@{
                        policyTypeId = 2; product = 'Entra ID'; primaryGroup = 'Conditional Access'
                        secondaryGroup = ''; displayName = 'Require MFA for Admins'
                        policyData = [PSCustomObject]@{ state = 'enabled' }
                    }
                )
                SourceName = 'Source'; DestinationName = 'Dest'
                SourceType = 'Tenant'; DestinationType = 'Tenant'
                SettingsCatalog = @{}
                IncludingAssignments = $false
                CollectedAt = [datetime]::UtcNow
            }

            $model = ConvertTo-InforcerComparisonModel -ComparisonData $compData
            $model.Counters.Matched | Should -Be 1
            $model.AlignmentScore | Should -Be 100
        }
    }

    Context 'Alignment score calculation' {

        It 'Excludes manual review items from score' {
            # Score = matched / (matched + conflicting + sourceOnly + destOnly)
            # Manual items are NOT in the denominator
            $compData = @{
                SourcePolicies = @(
                    [PSCustomObject]@{
                        policyTypeId = 2; product = 'Entra ID'; primaryGroup = 'CA'
                        secondaryGroup = ''; displayName = 'Policy A'
                        policyData = [PSCustomObject]@{ state = 'enabled' }
                    }
                )
                DestinationPolicies = @(
                    [PSCustomObject]@{
                        policyTypeId = 2; product = 'Entra ID'; primaryGroup = 'CA'
                        secondaryGroup = ''; displayName = 'Policy A'
                        policyData = [PSCustomObject]@{ state = 'enabled' }
                    }
                )
                SourceName = 'Source'; DestinationName = 'Dest'
                SourceType = 'Tenant'; DestinationType = 'Tenant'
                SettingsCatalog = @{}
                IncludingAssignments = $false
                CollectedAt = [datetime]::UtcNow
            }

            $model = ConvertTo-InforcerComparisonModel -ComparisonData $compData
            $model.AlignmentScore | Should -Be 100
        }
    }

    Context 'Empty environments' {

        It 'Handles empty destination — all source-only' {
            $compData = @{
                SourcePolicies = @(
                    [PSCustomObject]@{
                        policyTypeId = 2; product = 'Entra ID'; primaryGroup = 'CA'
                        secondaryGroup = ''; displayName = 'Policy A'
                        policyData = [PSCustomObject]@{ state = 'enabled' }
                    }
                )
                DestinationPolicies = @()
                SourceName = 'Source'; DestinationName = 'Dest'
                SourceType = 'Tenant'; DestinationType = 'Tenant'
                SettingsCatalog = @{}
                IncludingAssignments = $false
                CollectedAt = [datetime]::UtcNow
            }

            $model = ConvertTo-InforcerComparisonModel -ComparisonData $compData
            $model.Counters.SourceOnly | Should -Be 1
            $model.Counters.Matched | Should -Be 0
            $model.AlignmentScore | Should -Be 0
        }
    }

    Context 'ComparisonModel structure' {

        It 'Returns all required top-level keys' {
            $compData = @{
                SourcePolicies = @(); DestinationPolicies = @()
                SourceName = 'S'; DestinationName = 'D'
                SourceType = 'Tenant'; DestinationType = 'Tenant'
                SettingsCatalog = @{}; IncludingAssignments = $false
                CollectedAt = [datetime]::UtcNow
            }

            $model = ConvertTo-InforcerComparisonModel -ComparisonData $compData
            $model.SourceName | Should -Be 'S'
            $model.DestinationName | Should -Be 'D'
            $model.SourceType | Should -Be 'Tenant'
            $model.DestinationType | Should -Be 'Tenant'
            $model.Keys | Should -Contain 'AlignmentScore'
            $model.Keys | Should -Contain 'TotalItems'
            $model.Keys | Should -Contain 'Counters'
            $model.Keys | Should -Contain 'Products'
            $model.Keys | Should -Contain 'ManualReview'
            $model.Keys | Should -Contain 'IncludingAssignments'
        }
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `pwsh -Command "Invoke-Pester ./Tests/ComparisonModel.Tests.ps1 -Output Detailed"`
Expected: All tests FAIL — `ConvertTo-InforcerComparisonModel` does not exist yet

- [ ] **Step 3: Create the comparison model function**

Create `module/Private/ConvertTo-InforcerComparisonModel.ps1`. This is the largest and most complex file. Key logic:

```powershell
function ConvertTo-InforcerComparisonModel {
    <#
    .SYNOPSIS
        Builds a comparison model from two sets of policies.
    .DESCRIPTION
        Implements two comparison strategies:
        - Strategy A: Intune Settings Catalog policies — setting-level matching by settingDefinitionId
        - Strategy B: All other policies — policy-level matching by PolicyTypeId + Product + PrimaryGroup + Name

        Administrative Templates are compared against other Admin Templates using Strategy B.
        Manual review is only triggered for cross-structure mismatches (Settings Catalog vs Admin Template).
    .PARAMETER ComparisonData
        Hashtable from Get-InforcerComparisonData containing SourcePolicies, DestinationPolicies,
        SettingsCatalog, and metadata.
    .OUTPUTS
        Hashtable — the ComparisonModel (see spec for structure).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ComparisonData
    )

    $catalog = $ComparisonData.SettingsCatalog
    $includingAssignments = $ComparisonData.IncludingAssignments

    # --- Helper: detect if a policy is Settings Catalog ---
    function Test-SettingsCatalogPolicy {
        param([object]$Policy)
        if ($null -eq $Policy.policyData) { return $false }
        $pd = $Policy.policyData
        # Settings Catalog policies have a settingDefinitions array with settingInstance objects
        if ($pd.PSObject.Properties['settingDefinitions'] -and $pd.settingDefinitions -is [array] -and $pd.settingDefinitions.Count -gt 0) {
            foreach ($def in $pd.settingDefinitions) {
                if ($def.PSObject.Properties['settingInstance'] -and
                    $def.settingInstance.PSObject.Properties['settingDefinitionId'] -and
                    -not [string]::IsNullOrWhiteSpace($def.settingInstance.settingDefinitionId)) {
                    return $true
                }
            }
        }
        return $false
    }

    # --- Helper: extract setting value from a settingInstance ---
    function Get-SettingValue {
        param([object]$SettingInstance)
        $type = $SettingInstance.'@odata.type'
        switch -Wildcard ($type) {
            '*choiceSettingInstance' {
                $val = $SettingInstance.choiceSettingValue.value
                return [string]$val
            }
            '*simpleSettingInstance' {
                return [string]$SettingInstance.simpleSettingValue.value
            }
            '*simpleSettingCollectionInstance' {
                $vals = @($SettingInstance.simpleSettingCollectionValue | ForEach-Object { $_.value })
                return ($vals -join ', ')
            }
            default {
                return [string]($SettingInstance | ConvertTo-Json -Depth 5 -Compress)
            }
        }
    }

    # --- Helper: build category key ---
    function Get-CategoryKey {
        param([object]$Policy)
        $primary = [string]$Policy.primaryGroup
        $secondary = [string]$Policy.secondaryGroup
        if ([string]::IsNullOrWhiteSpace($primary)) { $primary = 'Uncategorized' }
        if ([string]::IsNullOrWhiteSpace($secondary) -or $secondary -eq $primary -or $secondary -eq 'All') {
            return $primary
        }
        return "$primary / $secondary"
    }

    # --- Helper: build policy-level match key ---
    function Get-PolicyMatchKey {
        param([object]$Policy)
        $typeId = [string]$Policy.policyTypeId
        $product = [string]$Policy.product
        $primary = [string]$Policy.primaryGroup
        $name = [string]$Policy.displayName
        return "$typeId|$product|$primary|$name".ToLowerInvariant()
    }

    # --- Helper: get assignment string from a policy ---
    function Get-AssignmentString {
        param([object]$Policy)
        if (-not $includingAssignments) { return $null }
        $assignments = $null
        if ($Policy.policyData -and $Policy.policyData.PSObject.Properties['assignments']) {
            $assignments = $Policy.policyData.assignments
        } elseif ($Policy.PSObject.Properties['assignments']) {
            $assignments = $Policy.assignments
        }
        if ($null -eq $assignments -or @($assignments).Count -eq 0) { return '' }
        $targets = @()
        foreach ($a in @($assignments)) {
            $target = $a.target
            if ($null -eq $target) { continue }
            $type = $target.'@odata.type'
            $groupId = $target.groupId
            if ($type -match 'allLicensedUsers') { $targets += 'All Users' }
            elseif ($type -match 'allDevices') { $targets += 'All Devices' }
            elseif ($groupId) { $targets += $groupId }
            else { $targets += 'Unknown' }
        }
        return ($targets -join ', ')
    }

    # --- Classify policies by type ---
    $sourceSC = [System.Collections.Generic.List[object]]::new()
    $sourceNonSC = [System.Collections.Generic.List[object]]::new()
    $destSC = [System.Collections.Generic.List[object]]::new()
    $destNonSC = [System.Collections.Generic.List[object]]::new()

    foreach ($p in @($ComparisonData.SourcePolicies)) {
        if (Test-SettingsCatalogPolicy $p) { [void]$sourceSC.Add($p) }
        else { [void]$sourceNonSC.Add($p) }
    }
    foreach ($p in @($ComparisonData.DestinationPolicies)) {
        if (Test-SettingsCatalogPolicy $p) { [void]$destSC.Add($p) }
        else { [void]$destNonSC.Add($p) }
    }

    # --- Initialize model ---
    $products = [ordered]@{}
    $manualReview = [ordered]@{}
    $counters = @{ Matched = 0; Conflicting = 0; SourceOnly = 0; DestOnly = 0; Manual = 0 }

    # --- Helper: ensure product/category exists ---
    function Ensure-ProductCategory {
        param([string]$Product, [string]$Category, [hashtable]$Target)
        if (-not $Target.Contains($Product)) {
            $Target[$Product] = @{
                Counters   = @{ Matched = 0; Conflicting = 0; SourceOnly = 0; DestOnly = 0 }
                Categories = [ordered]@{}
            }
        }
        if (-not $Target[$Product].Categories.Contains($Category)) {
            $Target[$Product].Categories[$Category] = @{ ComparisonRows = [System.Collections.Generic.List[hashtable]]::new() }
        }
    }

    function Ensure-ManualCategory {
        param([string]$Product, [string]$Category)
        if (-not $manualReview.Contains($Product)) {
            $manualReview[$Product] = @{ Count = 0; Categories = [ordered]@{} }
        }
        if (-not $manualReview[$Product].Categories.Contains($Category)) {
            $manualReview[$Product].Categories[$Category] = [System.Collections.Generic.List[hashtable]]::new()
        }
    }

    # =====================================================
    # STRATEGY A: Settings Catalog — setting-level matching
    # =====================================================
    $sourceSettings = @{}  # settingDefId -> @{ Value; PolicyName; Product; Category; Assignment }
    $destSettings = @{}

    foreach ($p in $sourceSC) {
        $product = [string]$p.product
        $category = Get-CategoryKey $p
        $assignment = Get-AssignmentString $p
        foreach ($def in @($p.policyData.settingDefinitions)) {
            $si = $def.settingInstance
            if ($null -eq $si -or [string]::IsNullOrWhiteSpace($si.settingDefinitionId)) { continue }
            $defId = $si.settingDefinitionId
            $val = Get-SettingValue $si
            if (-not $sourceSettings.ContainsKey($defId)) {
                $sourceSettings[$defId] = @{
                    Value      = $val
                    PolicyName = [string]$p.displayName
                    Product    = $product
                    Category   = $category
                    Assignment = $assignment
                }
            }
        }
    }

    foreach ($p in $destSC) {
        $product = [string]$p.product
        $category = Get-CategoryKey $p
        $assignment = Get-AssignmentString $p
        foreach ($def in @($p.policyData.settingDefinitions)) {
            $si = $def.settingInstance
            if ($null -eq $si -or [string]::IsNullOrWhiteSpace($si.settingDefinitionId)) { continue }
            $defId = $si.settingDefinitionId
            $val = Get-SettingValue $si
            if (-not $destSettings.ContainsKey($defId)) {
                $destSettings[$defId] = @{
                    Value      = $val
                    PolicyName = [string]$p.displayName
                    Product    = $product
                    Category   = $category
                    Assignment = $assignment
                }
            }
        }
    }

    # Compare all unique settingDefinitionIds
    $allDefIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($k in $sourceSettings.Keys) { [void]$allDefIds.Add($k) }
    foreach ($k in $destSettings.Keys) { [void]$allDefIds.Add($k) }

    foreach ($defId in $allDefIds) {
        $inSource = $sourceSettings.ContainsKey($defId)
        $inDest = $destSettings.ContainsKey($defId)

        # Resolve friendly name
        $friendlyName = $defId
        if ($catalog -and $catalog.ContainsKey($defId)) {
            $friendlyName = $catalog[$defId].DisplayName
        }

        $srcInfo = if ($inSource) { $sourceSettings[$defId] } else { $null }
        $dstInfo = if ($inDest) { $destSettings[$defId] } else { $null }
        $product = if ($srcInfo) { $srcInfo.Product } else { $dstInfo.Product }
        $category = if ($srcInfo) { $srcInfo.Category } else { $dstInfo.Category }

        Ensure-ProductCategory $product $category $products

        $row = @{
            ItemType       = 'Setting'
            Name           = $friendlyName
            SourcePolicy   = if ($srcInfo) { $srcInfo.PolicyName } else { $null }
            SourceValue    = if ($srcInfo) { $srcInfo.Value } else { $null }
            DestPolicy     = if ($dstInfo) { $dstInfo.PolicyName } else { $null }
            DestValue      = if ($dstInfo) { $dstInfo.Value } else { $null }
        }
        if ($includingAssignments) {
            $row.SourceAssignment = if ($srcInfo) { $srcInfo.Assignment } else { $null }
            $row.DestAssignment   = if ($dstInfo) { $dstInfo.Assignment } else { $null }
        }

        if ($inSource -and $inDest) {
            if ($srcInfo.Value -eq $dstInfo.Value) {
                $row.Status = 'Matched'
                $counters.Matched++
                $products[$product].Counters.Matched++
            } else {
                $row.Status = 'Conflicting'
                $counters.Conflicting++
                $products[$product].Counters.Conflicting++
            }
        } elseif ($inSource) {
            $row.Status = 'SourceOnly'
            $counters.SourceOnly++
            $products[$product].Counters.SourceOnly++
        } else {
            $row.Status = 'DestOnly'
            $counters.DestOnly++
            $products[$product].Counters.DestOnly++
        }

        [void]$products[$product].Categories[$category].ComparisonRows.Add($row)
    }

    # =====================================================
    # STRATEGY B: Non-SC policies — policy-level matching
    # =====================================================
    $sourceByKey = [ordered]@{}
    $destByKey = [ordered]@{}

    foreach ($p in $sourceNonSC) {
        $key = Get-PolicyMatchKey $p
        if (-not $sourceByKey.Contains($key)) { $sourceByKey[$key] = $p }
    }
    foreach ($p in $destNonSC) {
        $key = Get-PolicyMatchKey $p
        if (-not $destByKey.Contains($key)) { $destByKey[$key] = $p }
    }

    # Collect all unique keys
    $allPolicyKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($k in $sourceByKey.Keys) { [void]$allPolicyKeys.Add($k) }
    foreach ($k in $destByKey.Keys) { [void]$allPolicyKeys.Add($k) }

    # Track which product/categories have SC policies (for manual review detection)
    $scAreas = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($p in ($sourceSC + $destSC)) {
        $areaKey = "$([string]$p.product)|$(Get-CategoryKey $p)".ToLowerInvariant()
        [void]$scAreas.Add($areaKey)
    }

    foreach ($key in $allPolicyKeys) {
        $inSource = $sourceByKey.Contains($key)
        $inDest = $destByKey.Contains($key)

        $srcPol = if ($inSource) { $sourceByKey[$key] } else { $null }
        $dstPol = if ($inDest) { $destByKey[$key] } else { $null }
        $refPol = if ($srcPol) { $srcPol } else { $dstPol }

        $product = [string]$refPol.product
        $category = Get-CategoryKey $refPol
        $policyName = [string]$refPol.displayName
        $areaKey = "$product|$category".ToLowerInvariant()

        # Check if this is an unmatched non-SC policy in an area that also has SC policies → manual review
        $isAdminTemplate = ($refPol.policyTypeId -eq 10 -or [string]$refPol.inforcerPolicyTypeName -match 'admin|template')
        $areaHasSC = $scAreas.Contains($areaKey)

        if ((-not $inSource -or -not $inDest) -and $isAdminTemplate -and $areaHasSC) {
            # Manual review: unmatched admin template in area with SC policies
            $env = if ($inSource) { 'Source' } else { 'Destination' }
            Ensure-ManualCategory $product $category
            [void]$manualReview[$product].Categories[$category].Add(@{
                Environment = $env
                PolicyName  = $policyName
                PolicyType  = 'Administrative Template'
                Reason      = 'Administrative Template in area with Settings Catalog policies — cannot auto-compare across structures'
            })
            $manualReview[$product].Count++
            $counters.Manual++
            continue
        }

        # Normal policy-level comparison
        Ensure-ProductCategory $product $category $products

        $row = @{
            ItemType     = 'Policy'
            Name         = $policyName
            SourcePolicy = if ($srcPol) { $policyName } else { $null }
            DestPolicy   = if ($dstPol) { $policyName } else { $null }
        }
        if ($includingAssignments) {
            $row.SourceAssignment = if ($srcPol) { Get-AssignmentString $srcPol } else { $null }
            $row.DestAssignment   = if ($dstPol) { Get-AssignmentString $dstPol } else { $null }
        }

        if ($inSource -and $inDest) {
            # Compare policyData as JSON for equivalence
            $srcJson = $srcPol.policyData | ConvertTo-Json -Depth 50 -Compress
            $dstJson = $dstPol.policyData | ConvertTo-Json -Depth 50 -Compress
            if ($srcJson -eq $dstJson) {
                $row.Status = 'Matched'
                $row.SourceValue = 'Configured'
                $row.DestValue = 'Configured'
                $counters.Matched++
                $products[$product].Counters.Matched++
            } else {
                $row.Status = 'Conflicting'
                $row.SourceValue = 'Configured (differs)'
                $row.DestValue = 'Configured (differs)'
                $counters.Conflicting++
                $products[$product].Counters.Conflicting++
            }
        } elseif ($inSource) {
            $row.Status = 'SourceOnly'
            $row.SourceValue = 'Configured'
            $row.DestValue = $null
            $counters.SourceOnly++
            $products[$product].Counters.SourceOnly++
        } else {
            $row.Status = 'DestOnly'
            $row.SourceValue = $null
            $row.DestValue = 'Configured'
            $counters.DestOnly++
            $products[$product].Counters.DestOnly++
        }

        [void]$products[$product].Categories[$category].ComparisonRows.Add($row)
    }

    # --- Calculate alignment score ---
    $totalItems = $counters.Matched + $counters.Conflicting + $counters.SourceOnly + $counters.DestOnly
    $alignmentScore = if ($totalItems -gt 0) {
        [math]::Round(($counters.Matched / $totalItems) * 100, 1)
    } else { 0 }

    # --- Return model ---
    @{
        SourceName            = $ComparisonData.SourceName
        DestinationName       = $ComparisonData.DestinationName
        SourceType            = $ComparisonData.SourceType
        DestinationType       = $ComparisonData.DestinationType
        GeneratedAt           = $ComparisonData.CollectedAt
        AlignmentScore        = $alignmentScore
        TotalItems            = $totalItems
        Counters              = $counters
        Products              = $products
        ManualReview          = $manualReview
        IncludingAssignments  = $includingAssignments
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `pwsh -Command "Invoke-Pester ./Tests/ComparisonModel.Tests.ps1 -Output Detailed"`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add module/Private/ConvertTo-InforcerComparisonModel.ps1 Tests/ComparisonModel.Tests.ps1
git commit -m "feat: add comparison engine with setting-level and policy-level matching"
```

---

### Task 4: Create ConvertTo-InforcerComparisonHtml (Stage 3 — HTML Renderer)

**Files:**
- Create: `module/Private/ConvertTo-InforcerComparisonHtml.ps1`

This is a large file (~600 lines). The HTML mockup at `.superpowers/brainstorm/89384-1775162215/report-mockup-v4.html` is the reference implementation for the CSS and HTML structure.

- [ ] **Step 1: Create the HTML renderer**

Create `module/Private/ConvertTo-InforcerComparisonHtml.ps1`. This is the largest file (~600 lines). The implementation follows the exact same StringBuilder pattern as `ConvertTo-InforcerHtml.ps1` and uses the HTML mockup at `.superpowers/brainstorm/89384-1775162215/report-mockup-v4.html` as the pixel-perfect reference.

**Source files to reference:**
- **CSS**: Copy the entire `<style>` block from `report-mockup-v4.html` as a PowerShell here-string `$cssBlock`. This includes all CSS custom properties (light/dark themes), comparison-specific styles (status badges, score card, summary tiles, tabs, manual review tables), and responsive breakpoints.
- **HTML structure**: Convert the static HTML from `report-mockup-v4.html` into dynamic StringBuilder assembly
- **JavaScript**: Copy the `<script>` block from `report-mockup-v4.html`, parameterizing the hardcoded values with model data

The function skeleton and key assembly loops:

```powershell
function ConvertTo-InforcerComparisonHtml {
    <#
    .SYNOPSIS
        Renders a ComparisonModel as a self-contained HTML document.
    .DESCRIPTION
        Produces a single self-contained HTML file matching the visual style of
        Export-InforcerTenantDocumentation, with comparison-specific features:
        animated alignment score, status tiles, tabbed comparison/manual-review layout.
    .PARAMETER ComparisonModel
        Hashtable from ConvertTo-InforcerComparisonModel.
    .OUTPUTS
        System.String — complete HTML document.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ComparisonModel
    )

    # --- CSS block: copy ENTIRE <style> content from report-mockup-v4.html ---
    $cssBlock = @'
    ... (copy the full CSS from report-mockup-v4.html lines 4-240)
'@

    # --- Helper: HTML-encode ---
    function Esc { param([string]$s) [System.Net.WebUtility]::HtmlEncode($s) }

    # --- StringBuilder assembly ---
    $sb = [System.Text.StringBuilder]::new(65536)

    $sourceNameEsc = Esc $ComparisonModel.SourceName
    $destNameEsc   = Esc $ComparisonModel.DestinationName
    $generatedAt   = $ComparisonModel.GeneratedAt.ToString('yyyy-MM-dd HH:mm')
    $c = $ComparisonModel.Counters
    $score = $ComparisonModel.AlignmentScore
    $totalItems = $ComparisonModel.TotalItems
    $inclAssign = $ComparisonModel.IncludingAssignments

    # --- HTML head ---
    [void]$sb.AppendLine('<!DOCTYPE html>')
    [void]$sb.AppendLine('<html lang="en"><head><meta charset="UTF-8">')
    [void]$sb.AppendLine('<meta name="viewport" content="width=device-width, initial-scale=1.0">')
    [void]$sb.AppendLine("<title>Comparison — $sourceNameEsc vs $destNameEsc</title>")
    [void]$sb.AppendLine('<style>')
    [void]$sb.AppendLine($cssBlock)
    [void]$sb.AppendLine('</style></head><body><div id="top"></div>')

    # --- Notch bar (same pattern as ConvertTo-InforcerHtml.ps1 line 641) ---
    [void]$sb.AppendLine("<div class=`"notch-bar`">Environment Comparison<span class=`"notch-warn`">$totalItems items compared &middot; $($c.Manual) require manual review</span></div>")

    # --- Header (centered, from mockup) ---
    [void]$sb.AppendLine('<div class="header"><h1>Environment Comparison Report</h1>')
    [void]$sb.AppendLine('<div class="header-meta">')
    [void]$sb.AppendLine("<div class=`"env-row`"><strong>$sourceNameEsc</strong><span class=`"env-arrow`">&#10132;</span><strong>$destNameEsc</strong></div>")
    [void]$sb.AppendLine("<div class=`"env-row`" style=`"font-size:0.75rem;color:var(--muted)`"><span>$($ComparisonModel.SourceType)</span><span class=`"env-arrow`" style=`"visibility:hidden`">&#10132;</span><span>$($ComparisonModel.DestinationType)</span></div>")
    [void]$sb.AppendLine("<div class=`"generated`">Generated $generatedAt UTC</div>")
    [void]$sb.AppendLine('</div></div>')

    # --- Score card ---
    $barClass = if ($score -ge 70) { 'green' } elseif ($score -ge 40) { 'yellow' } else { 'red' }
    [void]$sb.AppendLine('<div class="score-card">')
    [void]$sb.AppendLine('<div class="score-value" id="scoreNum">0%</div>')
    [void]$sb.AppendLine("<div class=`"score-label`">Overall Alignment &mdash; <span id=`"scoreDetail`">0 of $totalItems items matched</span></div>")
    [void]$sb.AppendLine("<div class=`"score-bar-track`"><div class=`"score-bar-fill $barClass`" id=`"scoreBar`"></div></div>")
    [void]$sb.AppendLine('</div>')

    # --- Summary tiles (5-column grid) ---
    [void]$sb.AppendLine('<div class="summary-grid">')
    [void]$sb.AppendLine("<div class=`"summary-tile matched`"><div class=`"count`" id=`"countMatched`">0</div><div class=`"label`">Matched</div></div>")
    [void]$sb.AppendLine("<div class=`"summary-tile conflicting`"><div class=`"count`" id=`"countConflicting`">0</div><div class=`"label`">Conflicting</div></div>")
    [void]$sb.AppendLine("<div class=`"summary-tile source-only`"><div class=`"count`" id=`"countSource`">0</div><div class=`"label`">Source Only</div></div>")
    [void]$sb.AppendLine("<div class=`"summary-tile dest-only`"><div class=`"count`" id=`"countDest`">0</div><div class=`"label`">Destination Only</div></div>")
    [void]$sb.AppendLine("<div class=`"summary-tile manual`"><div class=`"count`" id=`"countManual`">0</div><div class=`"label`">Manual Review</div></div>")
    [void]$sb.AppendLine('</div>')

    # --- Search bar ---
    [void]$sb.AppendLine('<div class="search-bar"><input type="text" id="search-input" placeholder="Search policies, settings, values..." oninput="searchAll(this.value)"></div>')

    # --- Tabs ---
    [void]$sb.AppendLine('<div class="tabs">')
    [void]$sb.AppendLine('<button class="tab active" onclick="switchTab(this,''comparison'')">Comparison</button>')
    [void]$sb.AppendLine("<button class=`"tab`" onclick=`"switchTab(this,'manual')`">Manual Review <span class=`"badge`">$($c.Manual)</span></button>")
    [void]$sb.AppendLine('</div>')

    # ===== COMPARISON TAB =====
    [void]$sb.AppendLine('<div class="tab-content active" id="tab-comparison">')

    foreach ($prodName in $ComparisonModel.Products.Keys) {
        $prod = $ComparisonModel.Products[$prodName]
        $pc = $prod.Counters
        $prodEsc = Esc $prodName

        [void]$sb.AppendLine('<details class="product-section">')
        [void]$sb.AppendLine("<summary><span class=`"product-title`">$prodEsc</span>")
        [void]$sb.AppendLine("<span class=`"status-badge status-matched`">&#10003; $($pc.Matched)</span>")
        [void]$sb.AppendLine("<span class=`"status-badge status-conflicting`">&#10007; $($pc.Conflicting)</span>")
        [void]$sb.AppendLine("<span class=`"status-badge status-source-only`">Source $($pc.SourceOnly)</span>")
        [void]$sb.AppendLine("<span class=`"status-badge status-dest-only`">Dest $($pc.DestOnly)</span>")
        [void]$sb.AppendLine('</summary><div class="product-content">')

        foreach ($catName in $prod.Categories.Keys) {
            $catEsc = Esc $catName
            $rows = $prod.Categories[$catName].ComparisonRows

            [void]$sb.AppendLine("<h3>$catEsc</h3>")
            [void]$sb.AppendLine('<div class="table-wrap"><table>')

            # Determine table layout from first row
            $isSetting = $rows.Count -gt 0 -and $rows[0].ItemType -eq 'Setting'

            # Table header
            [void]$sb.AppendLine('<thead><tr>')
            [void]$sb.AppendLine('<th style="width:4%">Status</th>')
            if ($isSetting) {
                [void]$sb.AppendLine('<th>Setting</th><th>Source Policy</th><th>Source Value</th>')
                if ($inclAssign) { [void]$sb.AppendLine('<th>Source Assignment</th>') }
                [void]$sb.AppendLine('<th>Dest Policy</th><th>Dest Value</th>')
                if ($inclAssign) { [void]$sb.AppendLine('<th>Dest Assignment</th>') }
            } else {
                [void]$sb.AppendLine('<th>Policy</th><th>Source</th>')
                if ($inclAssign) { [void]$sb.AppendLine('<th>Source Assignment</th>') }
                [void]$sb.AppendLine('<th>Destination</th>')
                if ($inclAssign) { [void]$sb.AppendLine('<th>Dest Assignment</th>') }
            }
            [void]$sb.AppendLine('</tr></thead><tbody>')

            # Table rows
            foreach ($row in $rows) {
                [void]$sb.AppendLine('<tr>')

                # Status badge
                switch ($row.Status) {
                    'Matched'     { [void]$sb.AppendLine('<td><span class="status-badge status-matched">&#10003;</span></td>') }
                    'Conflicting' { [void]$sb.AppendLine('<td><span class="status-badge status-conflicting">&#10007;</span></td>') }
                    'SourceOnly'  { [void]$sb.AppendLine('<td><span class="status-badge status-source-only">Source Only</span></td>') }
                    'DestOnly'    { [void]$sb.AppendLine('<td><span class="status-badge status-dest-only">Dest Only</span></td>') }
                }

                $nameEsc = Esc $row.Name
                $srcValEsc = if ($row.SourceValue) { Esc $row.SourceValue } else { '<span style="color:var(--muted);font-style:italic">Not configured</span>' }
                $dstValEsc = if ($row.DestValue) { Esc $row.DestValue } else { '<span style="color:var(--muted);font-style:italic">Not configured</span>' }
                $dstClass = if ($row.Status -eq 'Conflicting') { ' class="value-cell value-diff"' } else { ' class="value-cell"' }

                if ($isSetting) {
                    $srcPolEsc = if ($row.SourcePolicy) { Esc $row.SourcePolicy } else { '' }
                    $dstPolEsc = if ($row.DestPolicy) { Esc $row.DestPolicy } else { '' }

                    if ($row.Status -eq 'SourceOnly') {
                        [void]$sb.AppendLine("<td class=`"setting-name`">$nameEsc</td><td>$srcPolEsc</td><td class=`"value-cell`">$srcValEsc</td>")
                        if ($inclAssign) { [void]$sb.AppendLine("<td>$(Esc $row.SourceAssignment)</td>") }
                        $colspan = if ($inclAssign) { 3 } else { 2 }
                        [void]$sb.AppendLine("<td colspan=`"$colspan`" style=`"color:var(--muted);font-style:italic`">Not configured</td>")
                    } elseif ($row.Status -eq 'DestOnly') {
                        $colspan = if ($inclAssign) { 3 } else { 2 }
                        [void]$sb.AppendLine("<td class=`"setting-name`">$nameEsc</td><td colspan=`"$colspan`" style=`"color:var(--muted);font-style:italic`">Not configured</td>")
                        [void]$sb.AppendLine("<td>$dstPolEsc</td><td$dstClass>$dstValEsc</td>")
                        if ($inclAssign) { [void]$sb.AppendLine("<td>$(Esc $row.DestAssignment)</td>") }
                    } else {
                        [void]$sb.AppendLine("<td class=`"setting-name`">$nameEsc</td><td>$srcPolEsc</td><td class=`"value-cell`">$srcValEsc</td>")
                        if ($inclAssign) { [void]$sb.AppendLine("<td>$(Esc $row.SourceAssignment)</td>") }
                        [void]$sb.AppendLine("<td>$dstPolEsc</td><td$dstClass>$dstValEsc</td>")
                        if ($inclAssign) { [void]$sb.AppendLine("<td>$(Esc $row.DestAssignment)</td>") }
                    }
                } else {
                    # Policy-level row (4/6 columns)
                    if ($row.Status -eq 'SourceOnly') {
                        [void]$sb.AppendLine("<td class=`"policy-name`">$nameEsc</td><td class=`"value-cell`">$srcValEsc</td>")
                        if ($inclAssign) { [void]$sb.AppendLine("<td>$(Esc $row.SourceAssignment)</td>") }
                        [void]$sb.AppendLine('<td style="color:var(--muted);font-style:italic">Not configured</td>')
                        if ($inclAssign) { [void]$sb.AppendLine('<td></td>') }
                    } elseif ($row.Status -eq 'DestOnly') {
                        [void]$sb.AppendLine("<td class=`"policy-name`">$nameEsc</td><td style=`"color:var(--muted);font-style:italic`">Not configured</td>")
                        if ($inclAssign) { [void]$sb.AppendLine('<td></td>') }
                        [void]$sb.AppendLine("<td$dstClass>$dstValEsc</td>")
                        if ($inclAssign) { [void]$sb.AppendLine("<td>$(Esc $row.DestAssignment)</td>") }
                    } else {
                        [void]$sb.AppendLine("<td class=`"policy-name`">$nameEsc</td><td class=`"value-cell`">$srcValEsc</td>")
                        if ($inclAssign) { [void]$sb.AppendLine("<td>$(Esc $row.SourceAssignment)</td>") }
                        [void]$sb.AppendLine("<td$dstClass>$dstValEsc</td>")
                        if ($inclAssign) { [void]$sb.AppendLine("<td>$(Esc $row.DestAssignment)</td>") }
                    }
                }

                [void]$sb.AppendLine('</tr>')
            }

            [void]$sb.AppendLine('</tbody></table></div>')
        }

        [void]$sb.AppendLine('</div></details>')
    }
    [void]$sb.AppendLine('</div>')

    # ===== MANUAL REVIEW TAB =====
    [void]$sb.AppendLine('<div class="tab-content" id="tab-manual">')

    if ($c.Manual -gt 0) {
        [void]$sb.AppendLine("<div class=`"card`" style=`"background:var(--manual-bg);border-color:var(--manual)`"><p style=`"font-size:0.875rem;color:var(--text)`"><strong>$($c.Manual) items require manual review.</strong> These policies use structures that cannot be automatically compared.</p></div>")
    }

    foreach ($prodName in $ComparisonModel.ManualReview.Keys) {
        $mrProd = $ComparisonModel.ManualReview[$prodName]
        $prodEsc = Esc $prodName

        [void]$sb.AppendLine('<details class="product-section" open>')
        [void]$sb.AppendLine("<summary><span class=`"product-title`">$prodEsc</span><span class=`"status-badge status-manual`">&#9888; $($mrProd.Count) policies</span></summary>")
        [void]$sb.AppendLine('<div class="product-content">')

        foreach ($catName in $mrProd.Categories.Keys) {
            $catEsc = Esc $catName
            $items = $mrProd.Categories[$catName]

            [void]$sb.AppendLine("<h3>$catEsc</h3>")
            [void]$sb.AppendLine('<div class="table-wrap"><table class="manual-table">')
            [void]$sb.AppendLine('<thead><tr><th style="width:10%">Environment</th><th style="width:30%">Policy Name</th><th style="width:18%">Policy Type</th><th style="width:42%">Reason</th></tr></thead><tbody>')

            foreach ($item in $items) {
                $envClass = if ($item.Environment -eq 'Source') { 'env-source' } else { 'env-dest' }
                $envLabel = $item.Environment.ToUpper().Substring(0,1) + $item.Environment.Substring(1)
                [void]$sb.AppendLine('<tr>')
                [void]$sb.AppendLine("<td><span class=`"env-label $envClass`">$(Esc $envLabel)</span></td>")
                [void]$sb.AppendLine("<td class=`"policy-name`">$(Esc $item.PolicyName)</td>")
                [void]$sb.AppendLine("<td><span class=`"policy-type-badge type-admin`">$(Esc $item.PolicyType)</span></td>")
                [void]$sb.AppendLine("<td class=`"manual-reason`">$(Esc $item.Reason)</td>")
                [void]$sb.AppendLine('</tr>')
            }

            [void]$sb.AppendLine('</tbody></table></div>')
        }

        [void]$sb.AppendLine('</div></details>')
    }
    [void]$sb.AppendLine('</div>')

    # --- Footer ---
    [void]$sb.AppendLine('<div class="footer">Generated by Compare-InforcerEnvironments &middot; InforcerCommunity Module</div>')

    # --- Floating buttons (same as ConvertTo-InforcerHtml.ps1 lines 778-788) ---
    [void]$sb.AppendLine('<div class="fab-group">')
    [void]$sb.AppendLine('<button class="fab fab-top" id="btn-top" onclick="scrollToTop()" aria-label="Back to top"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><path d="M18 15l-6-6-6 6"/></svg></button>')
    [void]$sb.AppendLine('<button class="fab fab-theme" id="btn-theme" onclick="toggleTheme()" aria-label="Toggle dark/light mode"><svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="5"/><line x1="12" y1="1" x2="12" y2="3"/><line x1="12" y1="21" x2="12" y2="23"/><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/><line x1="1" y1="12" x2="3" y2="12"/><line x1="21" y1="12" x2="23" y2="12"/><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/></svg></button>')
    [void]$sb.AppendLine('</div>')

    # --- JavaScript (parameterized from mockup-v4.html <script> block) ---
    [void]$sb.AppendLine('<script>')
    [void]$sb.AppendLine("(function(){var T=$score,M=$($c.Matched),C=$($c.Conflicting),S=$($c.SourceOnly),D=$($c.DestOnly),MR=$($c.Manual),TI=$totalItems;")
    # Copy the animation/tab/theme/search JS from report-mockup-v4.html,
    # replacing hardcoded values with the variables above
    [void]$sb.AppendLine(@'
var DUR=1500,INT=16,steps=Math.ceil(DUR/INT),step=0;
var eS=document.getElementById('scoreNum'),eB=document.getElementById('scoreBar'),eD=document.getElementById('scoreDetail');
var eM=document.getElementById('countMatched'),eC=document.getElementById('countConflicting');
var eSo=document.getElementById('countSource'),eDo=document.getElementById('countDest'),eMr=document.getElementById('countManual');
function ease(t){return t<.5?2*t*t:-1+(4-2*t)*t}
setTimeout(function(){var timer=setInterval(function(){step++;var p=ease(Math.min(step/steps,1));var pct=T*p;
eS.textContent=Math.round(pct*10)/10+'%';eB.style.width=pct+'%';
eD.textContent=Math.round(M*p)+' of '+TI+' items matched';
eM.textContent=Math.round(M*p);eC.textContent=Math.round(C*p);
eSo.textContent=Math.round(S*p);eDo.textContent=Math.round(D*p);eMr.textContent=Math.round(MR*p);
if(step>=steps){clearInterval(timer);eS.textContent=T+'%';eB.style.width=T+'%';
eD.textContent=M+' of '+TI+' items matched';eM.textContent=M;eC.textContent=C;eSo.textContent=S;eDo.textContent=D;eMr.textContent=MR}
},INT)},300)})();
function switchTab(b,id){document.querySelectorAll('.tab').forEach(function(t){t.classList.remove('active')});
document.querySelectorAll('.tab-content').forEach(function(c){c.classList.remove('active')});
b.classList.add('active');document.getElementById('tab-'+id).classList.add('active')}
function scrollToTop(){document.getElementById('top').scrollIntoView({behavior:'smooth'})}
window.addEventListener('scroll',function(){var b=document.getElementById('btn-top');
if(window.scrollY>300)b.classList.add('visible');else b.classList.remove('visible')});
function toggleTheme(){var r=document.documentElement;
if(r.classList.contains('dark')){r.classList.remove('dark');r.classList.add('light');localStorage.setItem('theme','light')}
else{r.classList.remove('light');r.classList.add('dark');localStorage.setItem('theme','dark')}}
(function(){var s=localStorage.getItem('theme');if(s==='dark')document.documentElement.classList.add('dark');
else if(s==='light')document.documentElement.classList.add('light')})();
function searchAll(q){q=q.toLowerCase().trim();document.querySelectorAll('.product-section').forEach(function(s){
if(!q){s.classList.remove('search-hidden');return}s.classList.toggle('search-hidden',s.textContent.toLowerCase().indexOf(q)<0)})}
'@)
    [void]$sb.AppendLine('</script>')

    [void]$sb.AppendLine('</body></html>')
    $sb.ToString()
}
```

**Key implementation notes:**
- The `$cssBlock` here-string must contain the FULL CSS from `report-mockup-v4.html` (lines 4-240 of that file). Copy it verbatim — it has all theme variables, comparison-specific styles, responsive breakpoints.
- The `Esc` helper prevents XSS by HTML-encoding all dynamic values
- The JS block uses an IIFE with the model's counter values injected as JS variables at the top
- The `$row.SourceAssignment`/`$row.DestAssignment` columns are only rendered when `$inclAssign` is true

- [ ] **Step 2: Verify the file loads without errors**

Run: `pwsh -Command "Import-Module ./module/InforcerCommunity.psd1 -Force -ErrorAction Stop; Write-Host 'OK'"`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add module/Private/ConvertTo-InforcerComparisonHtml.ps1
git commit -m "feat: add HTML renderer for environment comparison report"
```

---

### Task 5: Create Compare-InforcerEnvironments (Public Cmdlet)

**Files:**
- Create: `module/Public/Compare-InforcerEnvironments.ps1`

- [ ] **Step 1: Create the public cmdlet**

```powershell
<#
.SYNOPSIS
    Compares the policy configuration of two M365 environments and generates an HTML report.
.DESCRIPTION
    Fetches policies from a source and destination environment (each can be a tenant or baseline),
    compares them at the setting level (Intune Settings Catalog) or policy level (everything else),
    and produces a self-contained HTML report showing alignment score, matches, conflicts,
    source-only/destination-only items, and policies requiring manual review.

    For cross-account comparison, use Connect-Inforcer -PassThru to obtain session objects
    and pass them via -SourceSession / -DestinationSession.
.PARAMETER SourceTenantId
    Source tenant identifier: numeric ID, Microsoft Tenant ID GUID, or friendly name.
.PARAMETER DestinationTenantId
    Destination tenant identifier: numeric ID, Microsoft Tenant ID GUID, or friendly name.
.PARAMETER SourceSession
    Session hashtable from Connect-Inforcer -PassThru. If omitted, uses the current session.
.PARAMETER DestinationSession
    Session hashtable from Connect-Inforcer -PassThru. If omitted, uses the current session.
.PARAMETER SourceBaselineId
    Source baseline GUID or friendly name. Use instead of -SourceTenantId for baseline comparison.
.PARAMETER DestinationBaselineId
    Destination baseline GUID or friendly name. Use instead of -DestinationTenantId.
.PARAMETER IncludingAssignments
    When specified, fetches and displays Graph assignment data in the report.
    Assignments are informational only and do not affect the alignment score.
.PARAMETER SettingsCatalogPath
    Path to the IntuneSettingsCatalogViewer settings.json file.
    Auto-discovers from sibling repo if omitted.
.PARAMETER OutputPath
    Directory where the HTML report will be written. Defaults to current directory.
.EXAMPLE
    Connect-Inforcer -ApiKey $key
    Compare-InforcerEnvironments -SourceTenantId 'Contoso' -DestinationTenantId 'Fabrikam'
.EXAMPLE
    $src = Connect-Inforcer -ApiKey $key1 -Region uk -PassThru
    $dst = Connect-Inforcer -ApiKey $key2 -Region eu -PassThru
    Compare-InforcerEnvironments -SourceTenantId 'Contoso' -DestinationTenantId 'Fabrikam' -SourceSession $src -DestinationSession $dst
.EXAMPLE
    Compare-InforcerEnvironments -SourceBaselineId 'Production Baseline' -DestinationTenantId 482 -IncludingAssignments
.LINK
    https://github.com/royklo/InforcerCommunity/blob/main/docs/CMDLET-REFERENCE.md#compare-inforcerenvironments
.LINK
    Connect-Inforcer
#>
function Compare-InforcerEnvironments {
[CmdletBinding()]
[OutputType([System.IO.FileInfo])]
param(
    [Parameter(Mandatory = $false)]
    [object]$SourceTenantId,

    [Parameter(Mandatory = $false)]
    [object]$DestinationTenantId,

    [Parameter(Mandatory = $false)]
    [hashtable]$SourceSession,

    [Parameter(Mandatory = $false)]
    [hashtable]$DestinationSession,

    [Parameter(Mandatory = $false)]
    [string]$SourceBaselineId,

    [Parameter(Mandatory = $false)]
    [string]$DestinationBaselineId,

    [Parameter(Mandatory = $false)]
    [switch]$IncludingAssignments,

    [Parameter(Mandatory = $false)]
    [string]$SettingsCatalogPath,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = '.'
)

# --- Validation ---
if (-not (Test-InforcerSession)) {
    # Allow if both sessions are explicitly provided
    if (-not $SourceSession -or -not $DestinationSession) {
        Write-Error -Message 'Not connected yet. Please run Connect-Inforcer first, or provide both -SourceSession and -DestinationSession.' `
            -ErrorId 'NotConnected' -Category ConnectionError
        return
    }
}

# Validate source: must have either TenantId or BaselineId
$hasSourceTenant = $null -ne $SourceTenantId -and $SourceTenantId -ne ''
$hasSourceBaseline = -not [string]::IsNullOrWhiteSpace($SourceBaselineId)
if (-not $hasSourceTenant -and -not $hasSourceBaseline) {
    Write-Error -Message 'Specify either -SourceTenantId or -SourceBaselineId.' -ErrorId 'MissingSource' -Category InvalidArgument
    return
}

# Validate destination
$hasDestTenant = $null -ne $DestinationTenantId -and $DestinationTenantId -ne ''
$hasDestBaseline = -not [string]::IsNullOrWhiteSpace($DestinationBaselineId)
if (-not $hasDestTenant -and -not $hasDestBaseline) {
    Write-Error -Message 'Specify either -DestinationTenantId or -DestinationBaselineId.' -ErrorId 'MissingDestination' -Category InvalidArgument
    return
}

if ($IncludingAssignments) {
    Write-Warning 'Assignment data is informational only and does not affect the alignment score.'
}

# --- Stage 1: Collect data ---
Write-Host 'Collecting environment data...' -ForegroundColor Cyan
$comparisonDataParams = @{
    SettingsCatalogPath  = $SettingsCatalogPath
    IncludingAssignments = $IncludingAssignments
}
if ($SourceSession) { $comparisonDataParams.SourceSession = $SourceSession }
if ($DestinationSession) { $comparisonDataParams.DestinationSession = $DestinationSession }
if ($hasSourceTenant) { $comparisonDataParams.SourceTenantId = $SourceTenantId }
if ($hasSourceBaseline) { $comparisonDataParams.SourceBaselineId = $SourceBaselineId }
if ($hasDestTenant) { $comparisonDataParams.DestinationTenantId = $DestinationTenantId }
if ($hasDestBaseline) { $comparisonDataParams.DestinationBaselineId = $DestinationBaselineId }

try {
    $compData = Get-InforcerComparisonData @comparisonDataParams
} catch {
    Write-Error -Message "Data collection failed: $($_.Exception.Message)" -ErrorId 'DataCollectionFailed' -Category InvalidOperation
    return
}

Write-Host "  Source: $($compData.SourceName) ($($compData.SourceType)) — $(@($compData.SourcePolicies).Count) policies" -ForegroundColor Gray
Write-Host "  Destination: $($compData.DestinationName) ($($compData.DestinationType)) — $(@($compData.DestinationPolicies).Count) policies" -ForegroundColor Gray

# --- Stage 2: Build comparison model ---
Write-Host 'Building comparison model...' -ForegroundColor Cyan
$model = ConvertTo-InforcerComparisonModel -ComparisonData $compData

Write-Host "  Alignment: $($model.AlignmentScore)% — $($model.Counters.Matched) matched, $($model.Counters.Conflicting) conflicting, $($model.Counters.SourceOnly) source-only, $($model.Counters.DestOnly) dest-only, $($model.Counters.Manual) manual review" -ForegroundColor Gray

# --- Stage 3: Render HTML ---
Write-Host 'Rendering HTML report...' -ForegroundColor Cyan
$html = ConvertTo-InforcerComparisonHtml -ComparisonModel $model

# --- Write output ---
$resolvedPath = Resolve-Path -Path $OutputPath -ErrorAction SilentlyContinue
if (-not $resolvedPath) {
    New-Item -Path $OutputPath -ItemType Directory -Force | Out-Null
    $resolvedPath = Resolve-Path -Path $OutputPath
}

$safeName = ($compData.SourceName + '-vs-' + $compData.DestinationName) -replace '[^\w\-]', '_'
$fileName = "comparison-$safeName-$(Get-Date -Format 'yyyy-MM-dd-HHmm').html"
$filePath = Join-Path -Path $resolvedPath.Path -ChildPath $fileName

Set-Content -Path $filePath -Value $html -Encoding UTF8 -Force
$fileInfo = Get-Item -Path $filePath

Write-Host "Report saved: $filePath" -ForegroundColor Green
Write-Output $fileInfo
}
```

- [ ] **Step 2: Verify the file loads without errors**

Run: `pwsh -Command "Import-Module ./module/InforcerCommunity.psd1 -Force -ErrorAction Stop; Write-Host 'OK'"`
Expected: `OK`

- [ ] **Step 3: Commit**

```bash
git add module/Public/Compare-InforcerEnvironments.ps1
git commit -m "feat: add Compare-InforcerEnvironments public cmdlet"
```

---

### Task 6: Update Module Manifest and Consistency Tests

**Files:**
- Modify: `module/InforcerCommunity.psd1`
- Modify: `Tests/Consistency.Tests.ps1`

- [ ] **Step 1: Add to module manifest**

In `module/InforcerCommunity.psd1`, add `'Compare-InforcerEnvironments'` to the `FunctionsToExport` array (after `'Export-InforcerTenantDocumentation'`).

- [ ] **Step 2: Update consistency tests — expected count**

In `Tests/Consistency.Tests.ps1`, find `$script:expectedCount = 11` (line 33) and change it to `12`.

- [ ] **Step 3: Update consistency tests — expected names**

Add `'Compare-InforcerEnvironments'` to the `$script:expectedNames` array (after `'Export-InforcerTenantDocumentation'`).

- [ ] **Step 4: Update consistency tests — expected parameters**

Add to `$script:expectedParameters`:

```powershell
'Compare-InforcerEnvironments'  = @('SourceTenantId', 'DestinationTenantId', 'SourceSession', 'DestinationSession', 'SourceBaselineId', 'DestinationBaselineId', 'IncludingAssignments', 'SettingsCatalogPath', 'OutputPath')
```

- [ ] **Step 5: Run all consistency tests**

Run: `pwsh -Command "Invoke-Pester ./Tests/Consistency.Tests.ps1 -Output Detailed"`
Expected: All tests pass including the new cmdlet

- [ ] **Step 6: Run comparison model tests**

Run: `pwsh -Command "Invoke-Pester ./Tests/ComparisonModel.Tests.ps1 -Output Detailed"`
Expected: All tests pass

- [ ] **Step 7: Commit**

```bash
git add module/InforcerCommunity.psd1 Tests/Consistency.Tests.ps1
git commit -m "feat: register Compare-InforcerEnvironments in manifest and consistency tests"
```

---

### Task 7: Integration Smoke Test

This task is a manual verification step — run the full pipeline against a connected session to verify end-to-end functionality.

- [ ] **Step 1: Verify module loads cleanly**

Run: `pwsh -Command "Import-Module ./module/InforcerCommunity.psd1 -Force; Get-Command -Module InforcerCommunity | Select-Object Name | Sort-Object Name"`
Expected: `Compare-InforcerEnvironments` appears in the list (13 cmdlets total)

- [ ] **Step 2: Verify help is available**

Run: `pwsh -Command "Import-Module ./module/InforcerCommunity.psd1 -Force; Get-Help Compare-InforcerEnvironments"`
Expected: Synopsis, description, parameters, and examples are displayed

- [ ] **Step 3: Verify parameter validation without connection**

Run: `pwsh -Command "Import-Module ./module/InforcerCommunity.psd1 -Force; Compare-InforcerEnvironments -ErrorAction SilentlyContinue -ErrorVariable err; Write-Host \`$err"`
Expected: Error about missing source/connection

- [ ] **Step 4: Run all tests**

Run: `pwsh -Command "Invoke-Pester ./Tests/ -Output Detailed"`
Expected: All test files pass

- [ ] **Step 5: Commit if any fixes were needed**

```bash
git add -A && git commit -m "fix: address integration test findings"
```
