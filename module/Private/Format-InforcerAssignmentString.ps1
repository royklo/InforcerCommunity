function Format-InforcerAssignmentString {
    <#
    .SYNOPSIS
        Converts a DocModel assignments array to a semicolon-joined display string.
    .DESCRIPTION
        Takes the structured assignment array from Resolve-InforcerAssignments
        (as stored in DocModel policy.Assignments) and produces a human-readable
        string for comparison report display.

        Include-type groups emit just the group name (no prefix).
        Exclude-type groups emit "Exclude: <target>".
        When Filter and FilterMode are set, appends a parenthetical suffix:
        "<baseText> (<filterMode>: <filter>)".
    .PARAMETER Assignments
        Array of assignment objects from DocModel (each with Type, Target, Filter, FilterMode).
    #>
    [CmdletBinding()]
    param([Parameter()]$Assignments)

    if ($null -eq $Assignments -or @($Assignments).Count -eq 0) { return '' }

    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($a in @($Assignments)) {
        $type   = $a.Type
        $target = $a.Target
        $baseText = switch ($type) {
            'All Devices'     { 'All Devices' }
            'All Users'       { 'All Users' }
            'Group (Include)' { $target }
            'Group (Exclude)' { "Exclude: $target" }
            default {
                if ($target) { $target }
                elseif ($type) { $type }
                else { $null }
            }
        }
        if ($null -eq $baseText) { continue }
        if ($a.Filter -and $a.FilterMode) {
            $baseText = "$baseText ($($a.FilterMode.ToLower()): $($a.Filter))"
        }
        [void]$parts.Add($baseText)
    }
    return ($parts -join '; ')
}
