function ConvertTo-InforcerSettingRows {
    <#
    .SYNOPSIS
        Recursively traverses a Settings Catalog settingInstance tree into flat Name/Value rows.
    .DESCRIPTION
        Handles all 5 settingInstance @odata.type variants:
          - choiceSettingInstance
          - simpleSettingInstance
          - simpleSettingCollectionInstance
          - groupSettingCollectionInstance
          - choiceSettingCollectionInstance

        Each output row is a [PSCustomObject] with exactly 4 properties:
          Name         - friendly displayName resolved via Resolve-InforcerSettingName
          Value        - resolved choice label, literal value, comma-joined collection, or '' for headers
          Indent       - nesting depth (0 = top-level, increments for each recursive level)
          IsConfigured - $true for value-bearing rows, $false for group headers / unhandled types

        Unknown @odata.type values produce a warning and an "(unhandled type: ...)" value row.
    .PARAMETER SettingInstance
        A settingInstance object from a Settings Catalog policy (policyTypeId 10).
    .PARAMETER Depth
        Current nesting depth (recursion accumulator). Default 0.
    .EXAMPLE
        ConvertTo-InforcerSettingRows -SettingInstance $settingInstance
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $SettingInstance,

        [Parameter()]
        [int]$Depth = 0
    )

    $rows = [System.Collections.Generic.List[object]]::new()
    $odataType = $SettingInstance.'@odata.type'
    $defId = $SettingInstance.settingDefinitionId
    $resolved = Resolve-InforcerSettingName -SettingDefinitionId $defId

    switch -Wildcard ($odataType) {

        '*choiceSettingInstance' {
            $csv = $SettingInstance.choiceSettingValue
            $choiceLabel = ''
            if ($csv -and $csv.value) {
                $choiceLabel = (Resolve-InforcerSettingName -SettingDefinitionId $defId -ChoiceValue $csv.value).ValueLabel
            }
            [void]$rows.Add([PSCustomObject]@{
                Name        = $resolved.DisplayName
                Value       = $choiceLabel
                Indent      = $Depth
                IsConfigured = $true
            })
            if ($csv -and $csv.children) {
                foreach ($child in @($csv.children)) {
                    if ($null -ne $child) {
                        foreach ($r in (ConvertTo-InforcerSettingRows -SettingInstance $child -Depth ($Depth + 1))) {
                            [void]$rows.Add($r)
                        }
                    }
                }
            }
        }

        '*simpleSettingInstance' {
            $value = $SettingInstance.simpleSettingValue.value
            [void]$rows.Add([PSCustomObject]@{
                Name        = $resolved.DisplayName
                Value       = $value
                Indent      = $Depth
                IsConfigured = $true
            })
        }

        '*simpleSettingCollectionInstance' {
            $values = @($SettingInstance.simpleSettingCollectionValue | ForEach-Object { $_.value }) -join ', '
            [void]$rows.Add([PSCustomObject]@{
                Name        = $resolved.DisplayName
                Value       = $values
                Indent      = $Depth
                IsConfigured = $true
            })
        }

        '*groupSettingCollectionInstance' {
            [void]$rows.Add([PSCustomObject]@{
                Name        = $resolved.DisplayName
                Value       = ''
                Indent      = $Depth
                IsConfigured = $false
            })
            foreach ($group in @($SettingInstance.groupSettingCollectionValue)) {
                if ($null -ne $group -and $group.children) {
                    foreach ($child in @($group.children)) {
                        if ($null -ne $child) {
                            foreach ($r in (ConvertTo-InforcerSettingRows -SettingInstance $child -Depth ($Depth + 1))) {
                                [void]$rows.Add($r)
                            }
                        }
                    }
                }
            }
        }

        '*choiceSettingCollectionInstance' {
            foreach ($item in @($SettingInstance.choiceSettingCollectionValue)) {
                if ($null -ne $item) {
                    $label = (Resolve-InforcerSettingName -SettingDefinitionId $defId -ChoiceValue $item.value).ValueLabel
                    [void]$rows.Add([PSCustomObject]@{
                        Name        = $resolved.DisplayName
                        Value       = $label
                        Indent      = $Depth
                        IsConfigured = $true
                    })
                }
            }
        }

        default {
            Write-Warning "Unhandled settingInstance type: $odataType for '$defId'"
            [void]$rows.Add([PSCustomObject]@{
                Name        = $defId
                Value       = "(unhandled type: $odataType)"
                Indent      = $Depth
                IsConfigured = $false
            })
        }
    }

    $rows
}

function ConvertTo-FlatSettingRows {
    <#
    .SYNOPSIS
        Enumerates a policyData object's properties as flat Name/Value rows.
    .DESCRIPTION
        Used for non-Settings Catalog policy types (policyTypeId != 10). Iterates over all
        properties of the policyData object, skipping reserved/metadata properties, and
        produces Name/Value rows. Nested PSObject values are recursed with incrementing Indent
        (up to depth 2 to avoid unbounded recursion on complex graph objects).

        Each output row is a [PSCustomObject] with 4 properties:
          Name, Value, Indent, IsConfigured

        Skipped property names: @odata.type, id, createdDateTime, lastModifiedDateTime,
        roleScopeTagIds, version, templateId, displayName, description, assignments, settings
    .PARAMETER PolicyData
        The policyData object from a non-catalog policy. May be $null (returns empty list).
    .PARAMETER Depth
        Current nesting depth (recursion accumulator). Default 0.
    .EXAMPLE
        ConvertTo-FlatSettingRows -PolicyData $policy.policyData
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        $PolicyData,

        [Parameter()]
        [int]$Depth = 0
    )

    $rows = [System.Collections.Generic.List[object]]::new()
    if ($null -eq $PolicyData) { return $rows }

    $skip = @(
        '@odata.type', '@odata.context', 'id', 'createdDateTime', 'lastModifiedDateTime',
        'roleScopeTagIds', 'version', 'templateId', 'displayName',
        'description', 'assignments', 'settings', 'name', 'deletedDateTime'
    )

    foreach ($prop in $PolicyData.PSObject.Properties) {
        if ($prop.Name -in $skip) { continue }
        $val = $prop.Value
        if ($val -is [PSObject] -and $val.PSObject.Properties.Count -gt 0 -and $Depth -lt 2) {
            [void]$rows.Add([PSCustomObject]@{
                Name        = $prop.Name
                Value       = ''
                Indent      = $Depth
                IsConfigured = $false
            })
            foreach ($r in (ConvertTo-FlatSettingRows -PolicyData $val -Depth ($Depth + 1))) {
                [void]$rows.Add($r)
            }
        } else {
            $strVal = if ($null -eq $val) { '' } elseif ($val -is [array]) { $val -join ', ' } else { $val.ToString() }
            [void]$rows.Add([PSCustomObject]@{
                Name        = $prop.Name
                Value       = $strVal
                Indent      = $Depth
                IsConfigured = $true
            })
        }
    }

    $rows
}
