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
        $typeName = if ($typeMap.ContainsKey($odataType)) { $typeMap[$odataType] }
                    elseif ($odataType) { $odataType -replace '#microsoft\.graph\.', '' -replace 'AssignmentTarget$', '' }
                    else { '' }

        # Resolve target name
        $targetName = switch -Wildcard ($odataType) {
            '*allDevicesAssignmentTarget'       { 'All Devices' }
            '*allLicensedUsersAssignmentTarget'  { 'All Users' }
            '*groupAssignmentTarget'             {
                if ($GroupNameMap -and $GroupNameMap.ContainsKey($groupId)) { $GroupNameMap[$groupId] }
                elseif ($groupId) { $groupId }
                else { '' }
            }
            '*exclusionGroupAssignmentTarget'    {
                if ($GroupNameMap -and $GroupNameMap.ContainsKey($groupId)) { $GroupNameMap[$groupId] }
                elseif ($groupId) { $groupId }
                else { '' }
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
