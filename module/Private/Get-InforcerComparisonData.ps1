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

    # ── Inject compliance rules into DocData policies (supplements Inforcer API gap) ──
    # Only inject rulesContent for policies that DON'T have a linked script (avoid duplicate with linkedComplianceScript)
    $srcLinkedPolicyIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($p in @($sourceDocData.Policies)) {
        if ($p.policyData -and -not [string]::IsNullOrWhiteSpace($p.policyData.deviceComplianceScriptId)) {
            [void]$srcLinkedPolicyIds.Add($p.policyData.id)
        }
    }
    if ($srcGraphMaps.ComplianceRulesMap -and $srcGraphMaps.ComplianceRulesMap.Count -gt 0) {
        $injected = 0
        foreach ($policy in @($sourceDocData.Policies)) {
            if ($null -eq $policy.policyData -or $null -eq $policy.policyData.id) { continue }
            $pid = $policy.policyData.id
            if ($srcGraphMaps.ComplianceRulesMap.ContainsKey($pid) -and -not $srcLinkedPolicyIds.Contains($pid)) {
                $policy.policyData | Add-Member -NotePropertyName 'rulesContent' -NotePropertyValue $srcGraphMaps.ComplianceRulesMap[$pid] -Force
                $injected++
            }
        }
        if ($injected -gt 0) { Write-Host "  Injected compliance rules into $injected source policies" -ForegroundColor Gray }
    }

    # Link compliance discovery scripts to their parent compliance policies (source)
    # Strategy: match by deviceComplianceScriptId, then fallback to name similarity
    # (Inforcer API returns deviceComplianceScriptId as empty array — API limitation)
    $srcScriptById = @{}
    $srcScriptByName = @{}
    foreach ($p in @($sourceDocData.Policies)) {
        if ($p.policyTypeId -eq 104 -and $p.policyData -and $p.policyData.id) {
            $srcScriptById[$p.policyData.id] = $p
            $sName = if ($p.displayName) { $p.displayName } elseif ($p.name) { $p.name } else { $p.policyData.displayName }
            if ($sName) { $srcScriptByName[$sName.ToLowerInvariant()] = $p }
        }
    }
    if ($srcScriptById.Count -gt 0) {
        foreach ($policy in @($sourceDocData.Policies)) {
            if ($null -eq $policy.policyData) { continue }
            # Only link compliance policies (not the scripts themselves)
            $odataType = "$($policy.policyData.'@odata.type')"
            if ($odataType -notmatch 'CompliancePolicy' -and $policy.policyTypeId -ne 3) { continue }
            # Try ID match first
            $scriptId = "$($policy.policyData.deviceComplianceScriptId)"
            if ($scriptId -match '^[0-9a-f]{8}-') {
                if ($srcScriptById.ContainsKey($scriptId)) {
                    $scriptPolicy = $srcScriptById[$scriptId]
                    Write-Host "  Linked by ID: $($policy.displayName) -> $($scriptPolicy.displayName)" -ForegroundColor Green
                } else { $scriptPolicy = $null }
            } else {
                # Fallback: name similarity (strip "policy - " prefix)
                $policyName = if ($policy.displayName) { $policy.displayName } elseif ($policy.name) { $policy.name } else { '' }
                $cleanName = ($policyName -replace '^policy\s*-\s*', '').Trim().ToLowerInvariant()
                if ($cleanName -and $srcScriptByName.ContainsKey($cleanName)) {
                    $scriptPolicy = $srcScriptByName[$cleanName]
                    Write-Host "  Linked by name: '$policyName' -> '$($scriptPolicy.displayName)'" -ForegroundColor Green
                } else { $scriptPolicy = $null }
            }
            if ($null -eq $scriptPolicy) { continue }
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
            Write-Verbose "  Linked script '$($scriptData.scriptName)' to compliance policy '$($policy.displayName)'"
        }
    }

    $dstLinkedPolicyIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($p in @($destDocData.Policies)) {
        if ($p.policyData -and -not [string]::IsNullOrWhiteSpace($p.policyData.deviceComplianceScriptId)) {
            [void]$dstLinkedPolicyIds.Add($p.policyData.id)
        }
    }
    if ($dstGraphMaps.ComplianceRulesMap -and $dstGraphMaps.ComplianceRulesMap.Count -gt 0) {
        $injected = 0
        foreach ($policy in @($destDocData.Policies)) {
            if ($null -eq $policy.policyData -or $null -eq $policy.policyData.id) { continue }
            $pid = $policy.policyData.id
            if ($dstGraphMaps.ComplianceRulesMap.ContainsKey($pid) -and -not $dstLinkedPolicyIds.Contains($pid)) {
                $policy.policyData | Add-Member -NotePropertyName 'rulesContent' -NotePropertyValue $dstGraphMaps.ComplianceRulesMap[$pid] -Force
                $injected++
            }
        }
        if ($injected -gt 0) { Write-Host "  Injected compliance rules into $injected destination policies" -ForegroundColor Gray }
    }

    # Link compliance discovery scripts to their parent compliance policies (destination)
    $dstScriptById = @{}
    $dstScriptByName = @{}
    foreach ($p in @($destDocData.Policies)) {
        if ($p.policyTypeId -eq 104 -and $p.policyData -and $p.policyData.id) {
            $dstScriptById[$p.policyData.id] = $p
            $sName = if ($p.displayName) { $p.displayName } elseif ($p.name) { $p.name } else { $p.policyData.displayName }
            if ($sName) { $dstScriptByName[$sName.ToLowerInvariant()] = $p }
        }
    }
    if ($dstScriptById.Count -gt 0) {
        foreach ($policy in @($destDocData.Policies)) {
            if ($null -eq $policy.policyData) { continue }
            $odataType = "$($policy.policyData.'@odata.type')"
            if ($odataType -notmatch 'CompliancePolicy' -and $policy.policyTypeId -ne 3) { continue }
            $scriptId = "$($policy.policyData.deviceComplianceScriptId)"
            if ($scriptId -match '^[0-9a-f]{8}-') {
                $scriptPolicy = if ($dstScriptById.ContainsKey($scriptId)) { $dstScriptById[$scriptId] } else { $null }
                if ($scriptPolicy) { Write-Host "  Linked by ID (dst): $($policy.displayName) -> $($scriptPolicy.displayName)" -ForegroundColor Green }
            } else {
                $policyName = if ($policy.displayName) { $policy.displayName } elseif ($policy.name) { $policy.name } else { '' }
                $cleanName = ($policyName -replace '^policy\s*-\s*', '').Trim().ToLowerInvariant()
                $scriptPolicy = if ($cleanName -and $dstScriptByName.ContainsKey($cleanName)) { $dstScriptByName[$cleanName] } else { $null }
                if ($scriptPolicy) { Write-Host "  Linked by name (dst): '$policyName' -> '$($scriptPolicy.displayName)'" -ForegroundColor Green }
            }
            if ($null -eq $scriptPolicy) { continue }
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

    # ── Build DocModels ──
    $srcModelParams = @{ DocData = $sourceDocData; ComparisonMode = $true }
    if ($srcGraphMaps.GroupNameMap) { $srcModelParams['GroupNameMap'] = $srcGraphMaps.GroupNameMap }
    if ($srcGraphMaps.FilterMap)    { $srcModelParams['FilterMap']    = $srcGraphMaps.FilterMap }
    if ($srcGraphMaps.ScopeTagMap)  { $srcModelParams['ScopeTagMap']  = $srcGraphMaps.ScopeTagMap }
    $sourceModel = ConvertTo-InforcerDocModel @srcModelParams

    $dstModelParams = @{ DocData = $destDocData; ComparisonMode = $true }
    if ($dstGraphMaps.GroupNameMap) { $dstModelParams['GroupNameMap'] = $dstGraphMaps.GroupNameMap }
    if ($dstGraphMaps.FilterMap)    { $dstModelParams['FilterMap']    = $dstGraphMaps.FilterMap }
    if ($dstGraphMaps.ScopeTagMap)  { $dstModelParams['ScopeTagMap']  = $dstGraphMaps.ScopeTagMap }
    $destModel = ConvertTo-InforcerDocModel @dstModelParams

    @{
        SourceModel          = $sourceModel
        DestinationModel     = $destModel
        SourceName           = $sourceModel.TenantName
        DestinationName      = $destModel.TenantName
        IncludingAssignments = $IncludingAssignments.IsPresent
        CollectedAt          = [datetime]::UtcNow
    }
}
