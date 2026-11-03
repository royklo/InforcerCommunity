function Resolve-InforcerGraphEnrichment {
    <#
    .SYNOPSIS
        Connects to Microsoft Graph and resolves the IDs in a tenant's policies to display names.
    .DESCRIPTION
        Connects to Graph for the tenant's Azure AD (Connect-InforcerGraph may reuse a matching
        context) and builds fresh maps for this tenant only:
          GroupNameMap  assignment groups (and, with -ConditionalAccess, CA include/exclude groups),
                        via directoryObjects/getByIds (up to 1000 ids per call)
          FilterMap     assignment filters
          ScopeTagMap   Intune scope tags
        With -ConditionalAccess also RoleNameMap (roleDefinitions: built-in and custom roles),
        LocationNameMap (named locations) and AppNameMap (servicePrincipals filtered by appId, 15 ids
        per call; a small static map only names first-party apps the tenant has no service principal for).
        With -ComplianceRules also ComplianceRulesMap and ComplianceScriptLinkMap (one GET per
        compliance policy: the list endpoint does not return deviceCompliancePolicyScript).

        Shared by Export-InforcerTenantDocumentation and Get-InforcerComparisonData.
    .PARAMETER DocData
        Hashtable from Get-InforcerDocData containing Tenant and Policies.
    .PARAMETER Label
        Display label for progress messages (e.g., 'Source', 'Destination').
    .PARAMETER ConditionalAccess
        Also resolve Conditional Access groups, roles, named locations and applications.
    .PARAMETER ComplianceRules
        Also fetch custom compliance rules and linked discovery scripts.
    .OUTPUTS
        Hashtable of maps. Empty when the Graph connection fails.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$DocData,

        [Parameter()]
        [string]$Label = '',

        [Parameter()]
        [switch]$ConditionalAccess,

        [Parameter()]
        [switch]$ComplianceRules
    )

    $prefix = if ($Label) { "  [$Label] " } else { '  ' }

    $msTenantId = $null
    if ($DocData.Tenant -and $DocData.Tenant.PSObject.Properties['msTenantId']) {
        $msTenantId = $DocData.Tenant.msTenantId
    }

    $graphConnectParams = @{}
    if ($msTenantId) { $graphConnectParams['TenantId'] = $msTenantId }
    $graphCtx = Connect-InforcerGraph @graphConnectParams

    if (-not $graphCtx) {
        Write-Warning "${prefix}Microsoft Graph connection failed. Falling back to raw ObjectIDs."
        return @{}
    }

    Write-Host "${prefix}Graph connected as: $($graphCtx.Account)" -ForegroundColor Green

    if ($msTenantId -and $graphCtx.TenantId -and $graphCtx.TenantId -ne $msTenantId) {
        $tenantName = if ($DocData.Tenant.tenantFriendlyName) { $DocData.Tenant.tenantFriendlyName } else { $msTenantId }
        Write-Warning "${prefix}Graph signed into tenant $($graphCtx.TenantId) but target tenant is '$tenantName' ($msTenantId). Names may not resolve correctly; sign in with an account of that tenant or skip -FetchGraphData."
    }

    $guidPattern = '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    $objectIds   = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $roleIds     = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $locationIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $appIds      = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $addIds = {
        param($Set, $Values)
        foreach ($v in @($Values)) { if ($v -and "$v" -match $guidPattern) { [void]$Set.Add("$v") } }
    }

    foreach ($policy in @($DocData.Policies)) {
        $rawAssign = $policy.policyData.assignments
        if ($null -eq $rawAssign) { $rawAssign = $policy.assignments }
        foreach ($a in @($rawAssign)) {
            if ($null -eq $a) { continue }
            $t = $a.target; if ($null -eq $t) { $t = $a }
            & $addIds $objectIds $t.groupId
        }
        if (-not $ConditionalAccess) { continue }
        $conditions = $policy.policyData.conditions
        if ($null -eq $conditions) { continue }
        if ($conditions.users) {
            & $addIds $objectIds $conditions.users.includeGroups
            & $addIds $objectIds $conditions.users.excludeGroups
            & $addIds $roleIds $conditions.users.includeRoles
            & $addIds $roleIds $conditions.users.excludeRoles
        }
        if ($conditions.locations) {
            & $addIds $locationIds $conditions.locations.includeLocations
            & $addIds $locationIds $conditions.locations.excludeLocations
        }
        if ($conditions.applications) {
            & $addIds $appIds $conditions.applications.includeApplications
            & $addIds $appIds $conditions.applications.excludeApplications
        }
    }

    $maps = @{}

    $groupNameMap = @{}
    if ($objectIds.Count -gt 0) {
        Write-Host "${prefix}Resolving $($objectIds.Count) unique group/object IDs..." -ForegroundColor Gray
        $idList = [string[]]@($objectIds)
        for ($i = 0; $i -lt $idList.Count; $i += 1000) {
            $chunk = $idList[$i..([Math]::Min($i + 999, $idList.Count - 1))]
            $body = @{ ids = $chunk; types = @('group', 'user', 'device', 'servicePrincipal') } | ConvertTo-Json -Depth 100 -Compress
            $response = Invoke-InforcerGraphRequest -Uri 'https://graph.microsoft.com/v1.0/directoryObjects/getByIds' -Method POST -Body $body -SingleObject
            foreach ($obj in @($response.value)) {
                if ($obj.id -and $obj.displayName) { $groupNameMap[$obj.id] = $obj.displayName }
            }
        }
        $resolved = $groupNameMap.Count
        foreach ($oid in $idList) { if (-not $groupNameMap.ContainsKey($oid)) { $groupNameMap[$oid] = $oid } }
        Write-Host "${prefix}Resolved $resolved of $($objectIds.Count) group names" -ForegroundColor Gray
    }
    $maps['GroupNameMap'] = $groupNameMap

    Write-Host "${prefix}Fetching assignment filters..." -ForegroundColor Gray
    $filterMap = @{}
    foreach ($f in @(Invoke-InforcerGraphRequest -Uri 'https://graph.microsoft.com/beta/deviceManagement/assignmentFilters')) {
        if ($f.id) { $filterMap[$f.id] = $f }
    }
    Write-Host "${prefix}Loaded $($filterMap.Count) assignment filters" -ForegroundColor Gray
    $maps['FilterMap'] = $filterMap

    Write-Host "${prefix}Fetching scope tags..." -ForegroundColor Gray
    $scopeTagMap = @{}
    foreach ($st in @(Invoke-InforcerGraphRequest -Uri 'https://graph.microsoft.com/beta/deviceManagement/roleScopeTags')) {
        if ($null -ne $st.id) { $scopeTagMap[$st.id.ToString()] = $st.displayName }
    }
    Write-Host "${prefix}Loaded $($scopeTagMap.Count) scope tags" -ForegroundColor Gray
    $maps['ScopeTagMap'] = $scopeTagMap

    if ($ConditionalAccess) {
        $roleNameMap = @{}
        if ($roleIds.Count -gt 0) {
            Write-Host "${prefix}Resolving $($roleIds.Count) unique role IDs..." -ForegroundColor Gray
            foreach ($rd in @(Invoke-InforcerGraphRequest -Uri 'https://graph.microsoft.com/v1.0/roleManagement/directory/roleDefinitions?$select=id,displayName')) {
                if ($rd.id) { $roleNameMap[$rd.id] = $rd.displayName }
            }
            $resolvedRoles = @($roleIds | Where-Object { $roleNameMap.ContainsKey($_) }).Count
            Write-Host "${prefix}Resolved $resolvedRoles of $($roleIds.Count) role names" -ForegroundColor Gray
        }
        $maps['RoleNameMap'] = $roleNameMap

        $locationNameMap = @{}
        if ($locationIds.Count -gt 0) {
            Write-Host "${prefix}Resolving $($locationIds.Count) unique named location IDs..." -ForegroundColor Gray
            foreach ($nl in @(Invoke-InforcerGraphRequest -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/namedLocations?$select=id,displayName')) {
                if ($nl.id) { $locationNameMap[$nl.id] = $nl.displayName }
            }
            $resolvedLocations = @($locationIds | Where-Object { $locationNameMap.ContainsKey($_) }).Count
            Write-Host "${prefix}Resolved $resolvedLocations of $($locationIds.Count) named location names" -ForegroundColor Gray
        }
        $maps['LocationNameMap'] = $locationNameMap

        $appNameMap = @{}
        if ($appIds.Count -gt 0) {
            Write-Host "${prefix}Resolving $($appIds.Count) application IDs..." -ForegroundColor Gray
            $appList = [string[]]@($appIds)
            for ($i = 0; $i -lt $appList.Count; $i += 15) {
                $chunk = $appList[$i..([Math]::Min($i + 14, $appList.Count - 1))]
                $filter = [uri]::EscapeDataString("appId in ('" + ($chunk -join "','") + "')")
                $uri = "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=$filter&`$select=appId,displayName"
                foreach ($sp in @(Invoke-InforcerGraphRequest -Uri $uri)) {
                    if ($sp.appId -and $sp.displayName) { $appNameMap[$sp.appId] = $sp.displayName }
                }
            }
            # ponytail: fallback only for first-party apps with no service principal in this tenant; never overrides Graph.
            $knownApps = @{
                '0000000a-0000-0000-c000-000000000000' = 'Microsoft Intune'
                '00000002-0000-0000-c000-000000000000' = 'Windows Azure Active Directory'
                '00000002-0000-0ff1-ce00-000000000000' = 'Office 365 Exchange Online'
                '00000003-0000-0000-c000-000000000000' = 'Microsoft Graph'
                '00000003-0000-0ff1-ce00-000000000000' = 'Office 365 SharePoint Online'
                '00000004-0000-0ff1-ce00-000000000000' = 'Skype for Business Online'
                '0000000c-0000-0000-c000-000000000000' = 'Microsoft App Access Panel'
                '00000007-0000-0000-c000-000000000000' = 'Dataverse'
                '00000006-0000-0ff1-ce00-000000000000' = 'Microsoft Office 365 Portal'
                '00000009-0000-0000-c000-000000000000' = 'Power BI'
                '00000015-0000-0000-c000-000000000000' = 'Microsoft Dynamics ERP'
                '01cb2876-7ebd-4aa4-9cc9-d28bd4d359a9' = 'Device Registration Service'
                'd4ebce55-015a-49b5-a083-c84d1797ae8c' = 'Microsoft Intune Enrollment'
                'fc780465-2017-40d4-a0c5-307022471b92' = 'Windows Sign In'
                '04b07795-8ddb-461a-bbee-02f9e1bf7b46' = 'Microsoft Azure CLI'
                '1950a258-227b-4e31-a9cf-717495945fc2' = 'Microsoft Azure PowerShell'
                'fb78d390-0c51-40cd-8e17-fdbfab77341b' = 'Microsoft Exchange REST API'
                'de8bc8b5-d9f9-48b1-a8ad-b748da725064' = 'Graph Explorer'
                '1fec8e78-bce4-4aaf-ab1b-5451cc387264' = 'Microsoft Teams'
                'cc15fd57-2c6c-4117-a88c-83b1d56b4bbe' = 'Microsoft Teams Services'
                '27922004-5251-4030-b22d-91ecd9a37ea4' = 'Outlook Mobile'
                '4765445b-32c6-49b0-83e6-1d93765276ca' = 'OfficeHome'
            }
            foreach ($appId in $appList) {
                if (-not $appNameMap.ContainsKey($appId) -and $knownApps.ContainsKey($appId)) { $appNameMap[$appId] = $knownApps[$appId] }
            }
            $resolvedApps = @($appList | Where-Object { $appNameMap.ContainsKey($_) }).Count
            Write-Host "${prefix}Resolved $resolvedApps of $($appIds.Count) application names" -ForegroundColor Gray
        }
        $maps['AppNameMap'] = $appNameMap
    }

    if ($ComplianceRules) {
        Write-Host "${prefix}Fetching compliance rules..." -ForegroundColor Gray
        $complianceRulesMap = @{}
        $complianceScriptLinkMap = @{}
        $compPolicyIds = @($DocData.Policies | Where-Object {
            $_.policyData -and $_.policyData.id -and
            $_.policyData.'@odata.type' -match 'CompliancePolicy'
        } | ForEach-Object { @{ Id = $_.policyData.id; Name = $_.displayName } })
        Write-Host "${prefix}Checking $($compPolicyIds.Count) compliance policies for custom rules..." -ForegroundColor Gray
        foreach ($cpInfo in $compPolicyIds) {
            try {
                $cpFull = Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/deviceCompliancePolicies('$($cpInfo.Id)')" `
                    -Method GET -OutputType PSObject -ErrorAction Stop
            } catch {
                Write-Verbose "${prefix}  Failed to fetch: $($cpInfo.Name) - $($_.Exception.Message)"
                continue
            }
            $cpScript = $cpFull.deviceCompliancePolicyScript
            if ($cpScript -and $cpScript.rulesContent) {
                try {
                    $complianceRulesMap[$cpInfo.Id] = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($cpScript.rulesContent))
                    Write-Host "${prefix}  Compliance rules found: $($cpInfo.Name)" -ForegroundColor Green
                } catch {
                    $complianceRulesMap[$cpInfo.Id] = $cpScript.rulesContent
                }
            }
            if ($cpScript -and $cpScript.deviceComplianceScriptId) {
                $complianceScriptLinkMap[$cpInfo.Id] = $cpScript.deviceComplianceScriptId
            }
        }
        Write-Host "${prefix}Found compliance rules for $($complianceRulesMap.Count) of $($compPolicyIds.Count) policies" -ForegroundColor Gray
        $maps['ComplianceRulesMap'] = $complianceRulesMap
        $maps['ComplianceScriptLinkMap'] = $complianceScriptLinkMap
    }

    $maps
}
