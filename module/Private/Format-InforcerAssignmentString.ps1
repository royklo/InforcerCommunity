function Format-InforcerAssignmentString {
    <#
    .SYNOPSIS
        Converts a DocModel assignments array to a semicolon-joined display string.
    .DESCRIPTION
        Takes the structured assignment array from Resolve-InforcerAssignments
        (as stored in DocModel policy.Assignments) and produces a human-readable
        string for comparison report display.
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

        switch ($type) {
            'All Devices'    { [void]$parts.Add('All Devices') }
            'All Users'      { [void]$parts.Add('All Users') }
            'Group (Include)' { [void]$parts.Add("Include:$target") }
            'Group (Exclude)' { [void]$parts.Add("Exclude:$target") }
            default {
                if ($target) { [void]$parts.Add($target) }
                elseif ($type) { [void]$parts.Add($type) }
            }
        }
    }
    return ($parts -join '; ')
}
