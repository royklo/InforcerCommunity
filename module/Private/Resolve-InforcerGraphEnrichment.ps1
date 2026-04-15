function Resolve-InforcerGraphEnrichment {
    <#
    .SYNOPSIS
        Connects to Microsoft Graph and resolves group names, assignment filters, scope tags, and compliance rules for a tenant.
    .DESCRIPTION
        Extracts unique group ObjectIDs from raw policy data, connects to Graph targeting the tenant's
        Azure AD, and resolves IDs to display names. Also fetches compliance policy detection rules
        (rulesContent) that the Inforcer API does not return. Returns a hashtable with GroupNameMap,
        FilterMap, ScopeTagMap, and ComplianceRulesMap ready for ConvertTo-InforcerDocModel.

        Always performs a fresh Graph sign-in to ensure the correct Azure AD tenant context.

        Shared by Export-InforcerTenantDocumentation and Get-InforcerComparisonData to avoid duplicating
        Graph enrichment logic.
    .PARAMETER DocData
        Hashtable from Get-InforcerDocData containing Tenant and Policies.
    .PARAMETER Label
        Display label for progress messages (e.g., 'Source', 'Destination').
    .OUTPUTS
        Hashtable with keys: GroupNameMap, FilterMap, ScopeTagMap, ComplianceRulesMap. Values are $null if Graph connection fails.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$DocData,

        [Parameter()]
        [string]$Label = ''
    )

    $prefix = if ($Label) { "  [$Label] " } else { '  ' }

    # Extract Azure AD tenant GUID from the Inforcer tenant data so Graph targets the correct tenant
    $msTenantId = $null
    if ($DocData.Tenant -and $DocData.Tenant.PSObject.Properties['msTenantId']) {
        $msTenantId = $DocData.Tenant.msTenantId
    }

    $graphConnectParams = @{ RequiredScopes = @('Directory.Read.All', 'DeviceManagementConfiguration.Read.All') }
    if ($msTenantId) { $graphConnectParams['TenantId'] = $msTenantId }
    $graphCtx = Connect-InforcerGraph @graphConnectParams

    if (-not $graphCtx) {
        Write-Warning "${prefix}Microsoft Graph connection failed. Falling back to raw ObjectIDs."
        return @{ GroupNameMap = $null; FilterMap = $null; ScopeTagMap = $null; ComplianceRulesMap = $null }
    }

    Write-Host "${prefix}Graph connected as: $($graphCtx.Account)" -ForegroundColor Green

    # Validate Graph is connected to the correct tenant
    if ($msTenantId -and $graphCtx.TenantId -and $graphCtx.TenantId -ne $msTenantId) {
        $tenantName = if ($DocData.Tenant.tenantFriendlyName) { $DocData.Tenant.tenantFriendlyName } else { $msTenantId }
        Write-Warning "${prefix}Graph signed into tenant $($graphCtx.TenantId) but target tenant is '$tenantName' ($msTenantId). Group names may not resolve correctly."
    }

    # Collect all unique group ObjectIDs from raw policy data
    $objectIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($policy in @($DocData.Policies)) {
        $rawAssign = $policy.policyData.assignments
        if ($null -eq $rawAssign) { $rawAssign = $policy.assignments }
        if ($null -eq $rawAssign) { continue }
        foreach ($a in @($rawAssign)) {
            $t = $a.target; if ($null -eq $t) { $t = $a }
            if ($t.groupId -and $t.groupId -match '^[0-9a-f]{8}-') {
                [void]$objectIds.Add($t.groupId)
            }
        }
    }

    $groupNameMap = @{}
    if ($objectIds.Count -gt 0) {
        Write-Host "${prefix}Resolving $($objectIds.Count) unique group/object IDs..." -ForegroundColor Gray
        $resolved = 0
        # Use batch endpoint to resolve all IDs in one call (max 1000 per request)
        $idList = @($objectIds)
        try {
            $body = @{ ids = $idList; types = @('group','user','device','servicePrincipal') } | ConvertTo-Json -Depth 10 -Compress
            $response = Invoke-MgGraphRequest -Uri 'https://graph.microsoft.com/v1.0/directoryObjects/getByIds' `
                -Method POST -Body $body -ContentType 'application/json' -OutputType PSObject -ErrorAction Stop
            if ($response -and $response.value) {
                foreach ($obj in $response.value) {
                    if ($obj.id -and $obj.displayName) {
                        $groupNameMap[$obj.id] = $obj.displayName
                        $resolved++
                    } elseif ($obj.id) {
                        $groupNameMap[$obj.id] = $obj.id
                    }
                }
            }
        } catch {
            Write-Warning "${prefix}Batch resolve failed: $($_.Exception.Message). Falling back to individual lookups."
            foreach ($oid in $idList) {
                $obj = Invoke-InforcerGraphRequest -Uri "https://graph.microsoft.com/v1.0/directoryObjects/$oid" -SingleObject
                if ($obj -and $obj.displayName) {
                    $groupNameMap[$oid] = $obj.displayName
                    $resolved++
                } else {
                    $groupNameMap[$oid] = $oid
                }
            }
        }
        # Fill any IDs not returned by the batch (deleted objects, etc.)
        foreach ($oid in $idList) {
            if (-not $groupNameMap.ContainsKey($oid)) { $groupNameMap[$oid] = $oid }
        }
        Write-Host "${prefix}Resolved $resolved of $($objectIds.Count) group names" -ForegroundColor Gray
    }

    # Fetch assignment filters from Intune
    Write-Host "${prefix}Fetching assignment filters..." -ForegroundColor Gray
    $rawFilters = Invoke-InforcerGraphRequest -Uri 'https://graph.microsoft.com/beta/deviceManagement/assignmentFilters'
    $filterMap = @{}
    if ($rawFilters) {
        foreach ($f in $rawFilters) { $filterMap[$f.id] = $f }
        Write-Host "${prefix}Loaded $($filterMap.Count) assignment filters" -ForegroundColor Gray
    }

    # Fetch scope tags from Intune
    Write-Host "${prefix}Fetching scope tags..." -ForegroundColor Gray
    $rawScopeTags = Invoke-InforcerGraphRequest -Uri 'https://graph.microsoft.com/beta/deviceManagement/roleScopeTags'
    $scopeTagMap = @{}
    if ($rawScopeTags) {
        foreach ($st in $rawScopeTags) { $scopeTagMap[$st.id.ToString()] = $st.displayName }
        Write-Host "${prefix}Loaded $($scopeTagMap.Count) scope tags" -ForegroundColor Gray
    }

    # Fetch compliance rules (rulesContent) via Graph $expand — supplements Inforcer API gap
    Write-Host "${prefix}Fetching compliance rules..." -ForegroundColor Gray
    $complianceRulesMap = @{}
    try {
        # Fetch compliance policy IDs from raw DocData (matching IntuneLens approach:
        # the list endpoint doesn't return deviceCompliancePolicyScript, so we must
        # GET each policy individually to retrieve the custom compliance rules)
        $compPolicyIds = @($DocData.Policies | Where-Object {
            $_.policyData -and $_.policyData.id -and
            $_.policyData.'@odata.type' -match 'CompliancePolicy'
        } | ForEach-Object { @{ Id = $_.policyData.id; Name = $_.displayName } })
        Write-Host "${prefix}Checking $($compPolicyIds.Count) compliance policies for custom rules..." -ForegroundColor Gray
        foreach ($cpInfo in $compPolicyIds) {
            try {
                $cpFull = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies('$($cpInfo.Id)')" `
                    -Method GET -OutputType PSObject -ErrorAction Stop
                if ($cpFull.deviceCompliancePolicyScript -and $cpFull.deviceCompliancePolicyScript.rulesContent) {
                    $rulesB64 = $cpFull.deviceCompliancePolicyScript.rulesContent
                    try {
                        $decoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($rulesB64))
                        $complianceRulesMap[$cpInfo.Id] = $decoded
                        Write-Host "${prefix}  Compliance rules found: $($cpInfo.Name)" -ForegroundColor Green
                    } catch {
                        $complianceRulesMap[$cpInfo.Id] = $rulesB64
                    }
                }
            } catch {
                Write-Verbose "${prefix}  Failed to fetch: $($cpInfo.Name) — $($_.Exception.Message)"
            }
        }
        Write-Host "${prefix}Found compliance rules for $($complianceRulesMap.Count) of $($compPolicyIds.Count) policies" -ForegroundColor Gray
    } catch {
        Write-Warning "${prefix}Failed to fetch compliance rules: $($_.Exception.Message)"
    }

    @{
        GroupNameMap       = $groupNameMap
        FilterMap          = $filterMap
        ScopeTagMap        = $scopeTagMap
        ComplianceRulesMap = $complianceRulesMap
    }
}
