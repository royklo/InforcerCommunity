function Resolve-InforcerSettingName {
    <#
    .SYNOPSIS
        Resolves a settingDefinitionId to its friendly display name and optional choice option label.
    .DESCRIPTION
        Looks up the given settingDefinitionId in $script:InforcerSettingsCatalog and returns a
        hashtable with DisplayName, Description, and ValueLabel.

        - If the catalog is not loaded, the raw ID is returned as DisplayName.
        - If the ID is unknown, a Write-Warning is emitted and the raw ID is returned.
        - If ChoiceValue is provided, the matching option label is returned in ValueLabel.
        - If the SettingDefinitionId is null/empty, DisplayName is returned as ''.
    .PARAMETER SettingDefinitionId
        The Intune settingDefinitionId to resolve (e.g., "sirisettings_enabled").
    .PARAMETER ChoiceValue
        Optional itemId of the selected choice option (e.g., "sirisettings_enabled_false").
    .OUTPUTS
        Hashtable with keys: DisplayName, Description, ValueLabel
    .EXAMPLE
        Resolve-InforcerSettingName -SettingDefinitionId 'sirisettings_enabled'
        # Returns @{ DisplayName = 'Enabled'; Description = '...'; ValueLabel = '' }
    .EXAMPLE
        Resolve-InforcerSettingName -SettingDefinitionId 'sirisettings_enabled' -ChoiceValue 'sirisettings_enabled_false'
        # Returns @{ DisplayName = 'Enabled'; Description = '...'; ValueLabel = 'Disabled' }
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

    # Null or empty ID
    if ([string]::IsNullOrEmpty($SettingDefinitionId)) {
        $result.DisplayName = ''
        return $result
    }

    # Catalog not loaded — return raw ID
    if ($null -eq $script:InforcerSettingsCatalog) { return $result }

    $entry = $script:InforcerSettingsCatalog[$SettingDefinitionId]
    if ($null -eq $entry) {
        Write-Warning "Settings Catalog: unknown settingDefinitionId '$SettingDefinitionId'"
        return $result
    }

    $result.DisplayName = if ($entry.DisplayName) { $entry.DisplayName } else { $SettingDefinitionId }
    $result.Description = $entry.Description

    if (-not [string]::IsNullOrEmpty($ChoiceValue)) {
        $label = $entry.Options[$ChoiceValue]
        $result.ValueLabel = if ($label) { $label } else { $ChoiceValue }
    }

    return $result
}
