function Resolve-InforcerSettingName {
    <#
    .SYNOPSIS
        Resolves a settingDefinitionId to its friendly display name and optional choice option label.
    .DESCRIPTION
        Looks up the given settingDefinitionId in $script:InforcerSettingsCatalog and returns a
        hashtable with DisplayName, Description, and ValueLabel.

        When the catalog entry is missing or has no DisplayName, extracts a readable name from
        the settingDefinitionId structure (ADMX path segments, app names).
    .PARAMETER SettingDefinitionId
        The Intune settingDefinitionId to resolve.
    .PARAMETER ChoiceValue
        Optional itemId of the selected choice option.
    .OUTPUTS
        Hashtable with keys: DisplayName, Description, ValueLabel
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$SettingDefinitionId,

        [Parameter()]
        [string]$ChoiceValue
    )

    $result = @{
        DisplayName = $SettingDefinitionId
        Description = ''
        ValueLabel  = ''
    }

    if ([string]::IsNullOrEmpty($SettingDefinitionId)) {
        $result.DisplayName = ''
        return $result
    }

    # Catalog not loaded — use fallback
    if ($null -eq $script:InforcerSettingsCatalog) {
        $result.DisplayName = Get-InforcerFriendlySettingName -SettingDefinitionId $SettingDefinitionId
        return $result
    }

    $entry = $script:InforcerSettingsCatalog[$SettingDefinitionId]

    if ($null -eq $entry -or [string]::IsNullOrWhiteSpace($entry.DisplayName)) {
        # Not in catalog or empty DisplayName — extract readable name from ID
        $result.DisplayName = Get-InforcerFriendlySettingName -SettingDefinitionId $SettingDefinitionId
        if ($null -ne $entry) { $result.Description = $entry.Description }
        return $result
    }

    $result.DisplayName = $entry.DisplayName
    $result.Description = $entry.Description

    if (-not [string]::IsNullOrEmpty($ChoiceValue)) {
        $label = $entry.Options[$ChoiceValue]
        $result.ValueLabel = if ($label) { $label } else { $ChoiceValue }
    }

    return $result
}

function Get-InforcerFriendlySettingName {
    <#
    .SYNOPSIS
        Extracts a readable display name from a raw settingDefinitionId.
    .DESCRIPTION
        When the settings catalog doesn't have a friendly name, parses the ID structure
        to produce a human-readable label. Handles ADMX-backed IDs (containing ~policy~),
        Office app codes (excel16v2 → Excel), and general vendor_msft patterns.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$SettingDefinitionId)

    # Known app code → friendly name mapping
    $appNames = @{
        'excel16v2' = 'Excel'; 'excel16v8' = 'Excel'; 'word16v2' = 'Word'
        'ppt16v2' = 'PowerPoint'; 'access16v2' = 'Access'; 'outlk16v2' = 'Outlook'
        'visio16v2' = 'Visio'; 'proj16v2' = 'Project'; 'pub16v2' = 'Publisher'
        'onent16v2' = 'OneNote'; 'office16v2' = 'Office'; 'office16v8' = 'Office'
        'chromeintunev1' = 'Chrome'
    }

    # Strip user/device vendor prefix
    $stripped = $SettingDefinitionId -replace '^(user|device)_vendor_msft_policy_config_', ''
    if ($stripped -eq $SettingDefinitionId) {
        # Not an ADMX pattern — strip generic vendor prefix
        $stripped = $SettingDefinitionId -replace '^(user|device)_vendor_msft_', ''
    }

    # Extract app name
    $appLabel = ''
    foreach ($code in $appNames.Keys) {
        if ($stripped -match "^${code}[~_]") {
            $appLabel = $appNames[$code]
            $stripped = $stripped.Substring($code.Length).TrimStart('~', '_')
            break
        }
    }

    # Split on ~ to get ADMX template segments
    $segments = $stripped -split '[~]' | Where-Object { $_ -ne '' -and $_ -ne 'policy' }

    # Within each segment, split on _l_ (ADMX leaf separator)
    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($seg in $segments) {
        foreach ($p in ($seg -split '_l_')) {
            $s = $p.Trim('_')
            # Strip ADMX prefixes
            $s = $s -replace '^l_', ''
            # Strip noise suffixes
            $s = $s -replace '_?empty\d*$', ''
            $s = $s -replace 'dropid$', ''
            $s = $s -replace '_?enum$', ''
            # Strip known noise patterns
            $s = $s -replace '^microsoftoffice\w+$', ''
            $s = $s -replace '^\w+options$', ''
            $s = $s -replace '_v\d+$', ''
            $s = $s -replace '^securitysettings$', 'Security'
            $s = $s -replace '^trustcenter$', 'Trust Center'
            $s = $s -replace '^fileblocksettings$', 'File Block Settings'
            $s = $s -replace '^protectedview$', 'Protected View'
            $s = $s -replace '^cryptography$', 'Cryptography'
            if ([string]::IsNullOrWhiteSpace($s) -or $s.Length -lt 3) { continue }
            # Known compound words → readable form
            $s = $s -replace 'vbawarningspolicy', 'VBA Warnings Policy'
            $s = $s -replace 'setdefaultfileblockbehavior', 'Default File Block Behavior'
            $s = $s -replace 'macroruntimescanscope', 'Macro Runtime Scan Scope'
            $s = $s -replace 'blockxllfrominternet', 'Block XLL From Internet'
            $s = $s -replace 'retrievingcrlscertificaterevocationlists', 'Retrieving CRLs'
            $s = $s -replace 'signaturestatusdialog', 'Signature Status Dialog'
            $s = $s -replace 'setdocumentbehavioriffilevalidationfails', 'Document Behavior If File Validation Fails'
            $s = $s -replace 'publisherautomationsecuritylevel', 'Automation Security Level'
            $s = $s -replace 'determinewhethertoforceencrypted\w+', 'Force Encrypted Macros Scan'
            $s = $s -replace 'webcontentwarninglevel\w*', 'Web Content Warning Level'
            $s = $s -replace 'forcefileextenstionstomatch', 'Force File Extensions To Match'
            # Split on underscores, then camelCase to spaces
            $s = $s -replace '_', ' '
            $s = $s -creplace '([a-z])([A-Z])', '$1 $2'
            $s = (Get-Culture).TextInfo.ToTitleCase($s.ToLower())
            [void]$parts.Add($s)
        }
    }
    # Deduplicate consecutive identical parts
    $deduped = [System.Collections.Generic.List[string]]::new()
    $prev = ''
    foreach ($p in $parts) {
        if ($p -ne $prev) { [void]$deduped.Add($p); $prev = $p }
    }
    $parts = $deduped

    # Build: "App > last 2 meaningful parts"
    $tail = if ($parts.Count -gt 2) { @($parts[$parts.Count - 2], $parts[$parts.Count - 1]) }
            elseif ($parts.Count -gt 0) { $parts.ToArray() }
            else { @() }
    $display = @()
    if ($appLabel) { $display += $appLabel }
    $display += $tail
    if ($display.Count -gt 0) { return ($display -join ' > ') }
    return $SettingDefinitionId
}
