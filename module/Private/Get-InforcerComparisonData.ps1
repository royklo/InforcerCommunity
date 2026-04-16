function Get-InforcerComparisonData {
    <#
    .SYNOPSIS
        Fetches and normalizes data from two tenants for comparison.
    .DESCRIPTION
        Stage 1 of the Compare-InforcerEnvironments pipeline. Collects data from both
        environments via Get-InforcerDocData and normalizes through ConvertTo-InforcerDocModel
        with -ComparisonMode, producing two DocModels ready for diffing.
    .PARAMETER SourceTenantId
        Source tenant identifier. Accepts numeric ID, GUID, or tenant name.
    .PARAMETER DestinationTenantId
        Destination tenant identifier. Accepts numeric ID, GUID, or tenant name.
    .PARAMETER SourceSession
        Inforcer session hashtable for the source tenant. Defaults to $script:InforcerSession.
    .PARAMETER DestinationSession
        Inforcer session hashtable for the destination tenant. Defaults to $script:InforcerSession.
    .PARAMETER SettingsCatalogPath
        Optional explicit path to settings.json. Auto-discovers if omitted.
    .PARAMETER IncludingAssignments
        When specified, policy assignment data is included in the collected policies.
    .PARAMETER FetchGraphData
        When specified, connects to Microsoft Graph to resolve group ObjectIDs and assignment
        filter IDs to friendly display names. Requires Microsoft.Graph.Authentication module
        and interactive sign-in for each tenant.
    .OUTPUTS
        Hashtable with keys: SourceModel, DestinationModel, SourceName, DestinationName,
        IncludingAssignments, CollectedAt
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$SourceTenantId,

        [Parameter(Mandatory)]
        [object]$DestinationTenantId,

        [Parameter()]
        [hashtable]$SourceSession,

        [Parameter()]
        [hashtable]$DestinationSession,

        [Parameter()]
        [string]$SettingsCatalogPath,

        [Parameter()]
        [switch]$IncludingAssignments,

        [Parameter()]
        [switch]$FetchGraphData
    )

    if ($null -eq $SourceSession) { $SourceSession = $script:InforcerSession }
    if ($null -eq $DestinationSession) { $DestinationSession = $script:InforcerSession }

    $originalSession = $script:InforcerSession

    $docDataParams = @{}
    if (-not [string]::IsNullOrEmpty($SettingsCatalogPath)) {
        $docDataParams['SettingsCatalogPath'] = $SettingsCatalogPath
    }

    try {
        # ── Source ──
        Write-Host 'Collecting source tenant data...' -ForegroundColor Gray
        $script:InforcerSession = $SourceSession
        $sourceDocData = Get-InforcerDocData -TenantId $SourceTenantId @docDataParams
        if ($null -eq $sourceDocData -or $null -eq $sourceDocData.Policies) {
            Write-Error -Message "Failed to collect data for source tenant '$SourceTenantId'. The API may be unavailable — try again later." `
                -ErrorId 'SourceDataCollectionFailed' -Category ConnectionError
            return $null
        }

        # ── Destination ──
        Write-Host 'Collecting destination tenant data...' -ForegroundColor Gray
        $script:InforcerSession = $DestinationSession
        $destDocData = Get-InforcerDocData -TenantId $DestinationTenantId @docDataParams
        if ($null -eq $destDocData -or $null -eq $destDocData.Policies) {
            Write-Error -Message "Failed to collect data for destination tenant '$DestinationTenantId'. The API may be unavailable — try again later." `
                -ErrorId 'DestDataCollectionFailed' -Category ConnectionError
            return $null
        }
    } finally {
        $script:InforcerSession = $originalSession
    }

    # ── Graph enrichment (resolve group names and assignment filters) ──
    $srcGraphMaps = @{ GroupNameMap = $null; FilterMap = $null; ScopeTagMap = $null }
    $dstGraphMaps = @{ GroupNameMap = $null; FilterMap = $null; ScopeTagMap = $null }

    if ($FetchGraphData) {
        Write-Host 'Connecting to Microsoft Graph for assignment resolution...' -ForegroundColor Cyan

        # Always sign in separately for each tenant to ensure correct Azure AD context
        $srcTenantName = if ($sourceDocData.Tenant.tenantFriendlyName) { $sourceDocData.Tenant.tenantFriendlyName } else { $SourceTenantId }
        $dstTenantName = if ($destDocData.Tenant.tenantFriendlyName) { $destDocData.Tenant.tenantFriendlyName } else { $DestinationTenantId }

        Write-Host "  Sign in for SOURCE tenant: $srcTenantName" -ForegroundColor Yellow
        $srcGraphMaps = Resolve-InforcerGraphEnrichment -DocData $sourceDocData -Label "Source ($srcTenantName)"

        Write-Host "  Sign in for DESTINATION tenant: $dstTenantName" -ForegroundColor Yellow
        $dstGraphMaps = Resolve-InforcerGraphEnrichment -DocData $destDocData -Label "Destination ($dstTenantName)"
    }

    # ── Helper: inject compliance rules and link discovery scripts ──
    # Shared by both source and destination pipelines
    $enrichComplianceData = {
        param([object[]]$Policies, [hashtable]$GraphMaps, [string]$Label)

        # Inject rulesContent for policies that DON'T have a linked script
        $linkedPolicyIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($p in $Policies) {
            if ($p.policyData -and -not [string]::IsNullOrWhiteSpace($p.policyData.deviceComplianceScriptId)) {
                [void]$linkedPolicyIds.Add($p.policyData.id)
            }
        }
        if ($GraphMaps.ComplianceRulesMap -and $GraphMaps.ComplianceRulesMap.Count -gt 0) {
            $injected = 0
            foreach ($policy in $Policies) {
                if ($null -eq $policy.policyData -or $null -eq $policy.policyData.id) { continue }
                $pid = $policy.policyData.id
                if ($GraphMaps.ComplianceRulesMap.ContainsKey($pid) -and -not $linkedPolicyIds.Contains($pid)) {
                    $policy.policyData | Add-Member -NotePropertyName 'rulesContent' -NotePropertyValue $GraphMaps.ComplianceRulesMap[$pid] -Force
                    $injected++
                }
            }
            if ($injected -gt 0) { Write-Host "  Injected compliance rules into $injected $Label policies" -ForegroundColor Gray }
        }

        # Link compliance discovery scripts to their parent compliance policies
        $scriptById = @{}
        foreach ($p in $Policies) {
            if ($p.policyTypeId -eq 104 -and $p.policyData -and $p.policyData.id) {
                $scriptById[$p.policyData.id] = $p
            }
        }
        if ($scriptById.Count -gt 0) {
            foreach ($policy in $Policies) {
                if ($null -eq $policy.policyData -or $null -eq $policy.policyData.id) { continue }
                if ($policy.policyTypeId -eq 104) { continue }
                $policyId = $policy.policyData.id
                # Priority 1: Graph-based link
                $scriptId = $null
                if ($GraphMaps.ComplianceScriptLinkMap -and $GraphMaps.ComplianceScriptLinkMap.ContainsKey($policyId)) {
                    $scriptId = $GraphMaps.ComplianceScriptLinkMap[$policyId]
                }
                # Priority 2: Inforcer API deviceComplianceScriptId (often empty — API limitation)
                if (-not $scriptId) {
                    $infoScriptId = "$($policy.policyData.deviceComplianceScriptId)"
                    if ($infoScriptId -match '^[0-9a-f]{8}-') { $scriptId = $infoScriptId }
                }
                if (-not $scriptId -or -not $scriptById.ContainsKey($scriptId)) { continue }
                $scriptPolicy = $scriptById[$scriptId]
                $policyName = if ($policy.displayName) { $policy.displayName } else { $policy.name }
                Write-Host "  Linked script ($Label): '$policyName' -> '$($scriptPolicy.displayName)'" -ForegroundColor Green
                $scriptData = @{
                    scriptName = if ($scriptPolicy.displayName) { $scriptPolicy.displayName }
                                 elseif ($scriptPolicy.name) { $scriptPolicy.name }
                                 else { $scriptPolicy.policyData.displayName }
                }
                foreach ($prop in $scriptPolicy.policyData.PSObject.Properties) {
                    $propName = $prop.Name
                    if ($propName -match '@odata|^id$|^createdDateTime|^lastModifiedDateTime|^version|^displayName|^description|^roleScopeTagIds') { continue }
                    $val = $prop.Value
                    if ($propName -match '(?i)scriptContent|detectionScriptContent|remediationScriptContent' -and $val -is [string] -and $val.Length -gt 20) {
                        try { $val = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($val)) } catch {}
                    }
                    $scriptData[$propName] = $val
                }
                $scriptJson = $scriptData | ConvertTo-Json -Depth 5 -Compress
                $policy.policyData | Add-Member -NotePropertyName 'linkedComplianceScript' -NotePropertyValue $scriptJson -Force
                $scriptPolicy | Add-Member -NotePropertyName '_claimedByCompliancePolicy' -NotePropertyValue $true -Force
            }
        }
    }

    & $enrichComplianceData @($sourceDocData.Policies) $srcGraphMaps 'source'
    & $enrichComplianceData @($destDocData.Policies) $dstGraphMaps 'destination'

    # ── Build DocModels ──
    foreach ($entry in @(
        @{ DocData = $sourceDocData; Maps = $srcGraphMaps; Var = 'sourceModel' },
        @{ DocData = $destDocData;   Maps = $dstGraphMaps; Var = 'destModel' }
    )) {
        $params = @{ DocData = $entry.DocData; ComparisonMode = $true }
        foreach ($key in @('GroupNameMap', 'FilterMap', 'ScopeTagMap')) {
            if ($entry.Maps[$key]) { $params[$key] = $entry.Maps[$key] }
        }
        Set-Variable -Name $entry.Var -Value (ConvertTo-InforcerDocModel @params)
    }

    @{
        SourceModel          = $sourceModel
        DestinationModel     = $destModel
        SourceName           = $sourceModel.TenantName
        DestinationName      = $destModel.TenantName
        IncludingAssignments = $IncludingAssignments.IsPresent
        CollectedAt          = [datetime]::UtcNow
    }
}
