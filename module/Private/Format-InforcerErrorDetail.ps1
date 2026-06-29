function Format-InforcerErrorDetail {
    <#
    .SYNOPSIS
        Renders the structured `errors[]` array from an Inforcer API envelope into a single
        human-readable string suitable for appending to a top-level error message.
    .DESCRIPTION
        The Inforcer app-layer envelope shape is `{ success, message, errors[], errorCode }`.
        On validation failures the top-level `message` is often a generic placeholder
        ("Validation failed, see errors for details") and the actionable information lives
        in the `errors[]` array. Each entry can be:

          * a plain string                                           → kept verbatim
          * an object with field/property/name + message/detail + code/errorCode
                                                                     → rendered as "field (code) message"

        Returns $null when the array is missing, empty, or contains no usable detail.
    .PARAMETER Errors
        The parsed `errors` array (whatever ConvertFrom-Json produced for that property).
    .OUTPUTS
        String (semicolon-joined) or $null.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        $Errors
    )

    if ($null -eq $Errors) { return $null }
    $entries = @($Errors)
    if ($entries.Count -eq 0) { return $null }

    $rendered = [System.Collections.Generic.List[string]]::new()
    foreach ($e in $entries) {
        if ($null -eq $e) { continue }
        if ($e -is [string]) {
            $rendered.Add($e.Trim())
            continue
        }
        if (-not ($e.PSObject -and $e.PSObject.Properties)) { continue }

        $field   = ($e.PSObject.Properties['field'].Value -as [string])
        if (-not $field) { $field = ($e.PSObject.Properties['property'].Value -as [string]) }
        if (-not $field) { $field = ($e.PSObject.Properties['name'].Value     -as [string]) }
        $message = ($e.PSObject.Properties['message'].Value -as [string])
        if (-not $message) { $message = ($e.PSObject.Properties['detail'].Value -as [string]) }
        $code    = ($e.PSObject.Properties['code'].Value -as [string])
        if (-not $code) { $code = ($e.PSObject.Properties['errorCode'].Value -as [string]) }

        $parts = [System.Collections.Generic.List[string]]::new()
        if ($field)   { $parts.Add($field) }
        if ($code)    { $parts.Add("($code)") }
        if ($message) { $parts.Add($message) }
        if ($parts.Count -gt 0) {
            $rendered.Add(($parts -join ' '))
        } else {
            # Nothing we recognize — dump JSON so the user still sees something useful.
            # Serialization can fail for objects with circular refs or COM types; in that case
            # we drop the entry silently (the top-level message will still surface).
            try {
                $rendered.Add(($e | ConvertTo-Json -Compress -Depth 5))
            } catch {
                Write-Verbose "Format-InforcerErrorDetail: skipping unserializable entry ($($_.Exception.Message))"
            }
        }
    }

    if ($rendered.Count -eq 0) { return $null }
    return ($rendered -join '; ')
}
