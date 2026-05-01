function Resolve-InforcerAssignments {
    <#
    .SYNOPSIS
        Normalizes raw assignment data into human-readable rows with proper type labels.
    .DESCRIPTION
        Translates @odata.type values to friendly names (All Devices, All Users, Group Include,
        Group Exclude). When -FetchGraphData is true and Graph is connected, resolves group
        ObjectIDs to display names and filter IDs to filter names via Invoke-InforcerGraphRequest.

        Based on the assignment resolution pattern from RKSolutions-Module IntuneEnrollmentFlows.ps1.
    .PARAMETER RawAssignments
        The raw assignments array from the API (policy.policyData.assignments or policy.assignments).
    .PARAMETER GroupNameMap
        Pre-built hashtable of groupId -> displayName (populated once, shared across policies).
    .PARAMETER FilterMap
        Pre-built hashtable of filterId -> filter object (populated once, shared across policies).
    #>
    [CmdletBinding()]
    param(
        [Parameter()][object]$RawAssignments,
        [Parameter()][hashtable]$GroupNameMap,
        [Parameter()][hashtable]$FilterMap
    )

    $results = [System.Collections.Generic.List[object]]::new()
    if ($null -eq $RawAssignments) { return $results.ToArray() }

    # Assignment type mapping (from RKSolutions pattern)
    $typeMap = @{
        '#microsoft.graph.allDevicesAssignmentTarget'        = 'All Devices'
        '#microsoft.graph.allLicensedUsersAssignmentTarget'  = 'All Users'
        '#microsoft.graph.groupAssignmentTarget'             = 'Group (Include)'
        '#microsoft.graph.exclusionGroupAssignmentTarget'    = 'Group (Exclude)'
    }

    foreach ($assignment in @($RawAssignments)) {
        if ($null -eq $assignment) { continue }
        $target = $assignment.target
        if ($null -eq $target) { $target = $assignment }

        $odataType  = $target.'@odata.type'
        $groupId    = $target.groupId
        # Fallback: extract groupId from the assignment id (format: "policyId:groupId")
        if ([string]::IsNullOrWhiteSpace($groupId) -and $assignment.id -match ':(.+)$') {
            $candidateId = $Matches[1]
            # Only use if it looks like a GUID and the type is a group assignment
            if ($candidateId -match '^[0-9a-f]{8}-' -and $odataType -match 'group') {
                $groupId = $candidateId
            }
        }
        # Filter properties may live on target (Graph standard) or assignment level (some API wrappers)
        $filterId   = $target.deviceAndAppManagementAssignmentFilterId
        if ([string]::IsNullOrWhiteSpace($filterId)) {
            $filterId = $assignment.deviceAndAppManagementAssignmentFilterId
        }
        $filterMode = $target.deviceAndAppManagementAssignmentFilterType
        if ([string]::IsNullOrWhiteSpace($filterMode)) {
            $filterMode = $assignment.deviceAndAppManagementAssignmentFilterType
        }

        # Resolve assignment type to friendly name
        $typeName = if ($null -ne $odataType -and $typeMap.ContainsKey($odataType)) { $typeMap[$odataType] }
                    elseif ($odataType) { $odataType -replace '#microsoft\.graph\.', '' -replace 'AssignmentTarget$', '' }
                    else { '' }

        # Resolve target name (specific patterns first to avoid double-match)
        $targetName = switch -Wildcard ($odataType) {
            '*allDevicesAssignmentTarget'       { 'All Devices'; break }
            '*allLicensedUsersAssignmentTarget'  { 'All Users'; break }
            '*exclusionGroupAssignmentTarget'    {
                if ($GroupNameMap -and $groupId -and $GroupNameMap.ContainsKey($groupId)) { $GroupNameMap[$groupId] }
                elseif ($groupId) { $groupId }
                else { '' }
                break
            }
            '*groupAssignmentTarget'             {
                if ($GroupNameMap -and $groupId -and $GroupNameMap.ContainsKey($groupId)) { $GroupNameMap[$groupId] }
                elseif ($groupId) { $groupId }
                else { '' }
                break
            }
            default { $groupId }
        }

        # Resolve filter
        $filterName = ''
        $filterRule = ''
        if (-not [string]::IsNullOrWhiteSpace($filterId) -and $filterId -ne '00000000-0000-0000-0000-000000000000') {
            if ($FilterMap -and $FilterMap.ContainsKey($filterId)) {
                $f = $FilterMap[$filterId]
                $filterName = $f.displayName
                $filterRule = $f.rule
            } else {
                $filterName = $filterId
            }
        }

        # Normalize filter mode
        $filterModeDisplay = switch ($filterMode) {
            'include' { 'Include' }
            'exclude' { 'Exclude' }
            'none'    { '' }
            default   { $filterMode }
        }

        [void]$results.Add([PSCustomObject]@{
            Target     = $targetName
            Type       = $typeName
            Filter     = $filterName
            FilterMode = $filterModeDisplay
        })
    }

    $results.ToArray()
}
