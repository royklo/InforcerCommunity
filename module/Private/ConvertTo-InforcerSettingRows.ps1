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
                Name         = $resolved.DisplayName
                Value        = $choiceLabel
                Indent       = $Depth
                IsConfigured = $true
                DefinitionId = $defId
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
                Name         = $resolved.DisplayName
                Value        = $value
                Indent       = $Depth
                IsConfigured = $true
                DefinitionId = $defId
            })
        }

        '*simpleSettingCollectionInstance' {
            $values = @($SettingInstance.simpleSettingCollectionValue | ForEach-Object { $_.value }) -join ', '
            [void]$rows.Add([PSCustomObject]@{
                Name         = $resolved.DisplayName
                Value        = $values
                Indent       = $Depth
                IsConfigured = $true
                DefinitionId = $defId
            })
        }

        '*groupSettingCollectionInstance' {
            [void]$rows.Add([PSCustomObject]@{
                Name         = $resolved.DisplayName
                Value        = ''
                Indent       = $Depth
                IsConfigured = $false
                DefinitionId = $defId
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
                        Name         = $resolved.DisplayName
                        Value        = $label
                        Indent       = $Depth
                        IsConfigured = $true
                        DefinitionId = $defId
                    })
                }
            }
        }

        default {
            Write-Warning "Unhandled settingInstance type: $odataType for '$defId'"
            [void]$rows.Add([PSCustomObject]@{
                Name         = $defId
                Value        = "(unhandled type: $odataType)"
                Indent       = $Depth
                IsConfigured = $false
                DefinitionId = $defId
            })
        }
    }

    $rows
}

function ConvertTo-FriendlySettingName {
    <#
    .SYNOPSIS
        Converts camelCase property names to human-readable titles.
    .DESCRIPTION
        Splits camelCase/PascalCase identifiers into space-separated words with title casing.
        Preserves known acronyms (VPN, DNS, PIN, etc.) as uppercase. Names that already
        contain spaces are returned unchanged.
    .PARAMETER Name
        The camelCase property name to convert.
    .EXAMPLE
        ConvertTo-FriendlySettingName -Name 'activeHoursEnd'
        # Returns: Active Hours End
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    # Skip if already friendly (contains spaces) or is empty
    if ([string]::IsNullOrWhiteSpace($Name) -or $Name.Contains(' ')) {
        return $Name
    }

    # Dotted paths are handled by ConvertTo-FlatSettingRows (folder structure)
    # If called directly with a dotted name, convert each segment individually
    if ($Name.Contains('.')) {
        $segments = $Name -split '\.'
        $friendlySegments = foreach ($seg in $segments) {
            if (-not [string]::IsNullOrWhiteSpace($seg)) {
                ConvertTo-FriendlySettingName -Name $seg
            }
        }
        return ($friendlySegments -join ' > ')
    }

    # Known acronyms to preserve as uppercase
    $acronyms = @('MAM','MDM','VPN','DNS','URL','OMA','URI','SSID','WIFI','UUID','PIN','USB','DMA','TPM','VBA','MFA','AAD','DLP','OS','IP','ID','IT','UI','HTTP','HTTPS','API','SSO','SMS','OTP','TCP','UDP','SSL','TLS','LDAP','SCEP','PKCS','EAP','PEAP','WPA','WEP','NAT','DHCP','FQDN','IOS','MACOS','P2P')

    # Insert space before each uppercase letter that follows a lowercase letter
    # Also insert space before a run of uppercase followed by lowercase (e.g. "PINReset" -> "PIN Reset")
    $result = [System.Text.RegularExpressions.Regex]::Replace($Name, '(?<=[a-z])(?=[A-Z])', ' ')
    $result = [System.Text.RegularExpressions.Regex]::Replace($result, '(?<=[A-Z])(?=[A-Z][a-z])', ' ')

    # Title-case each word, then restore known acronyms
    $words = $result -split '\s+'
    $output = [System.Collections.Generic.List[string]]::new()
    foreach ($word in $words) {
        if ([string]::IsNullOrWhiteSpace($word)) { continue }
        $upper = $word.ToUpperInvariant()
        # Check if this word (case-insensitive) matches a known acronym
        $matched = $false
        foreach ($acr in $acronyms) {
            if ($upper -eq $acr) {
                [void]$output.Add($acr)
                $matched = $true
                break
            }
        }
        if (-not $matched) {
            # Title case: first letter upper, rest as-is (preserve casing in mixed words)
            [void]$output.Add($word.Substring(0,1).ToUpperInvariant() + $word.Substring(1))
        }
    }
    return ($output -join ' ')
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

    # Track emitted dotted-path parent rows to avoid duplicates (only init at top level)
    if ($Depth -eq 0) {
        $script:_emittedDotParents = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    }

    $skip = @(
        '@odata.type', '@odata.context', 'id', 'createdDateTime', 'lastModifiedDateTime',
        'roleScopeTagIds', 'version', 'templateId', 'displayName',
        'description', 'assignments', 'inforcerAssignments', 'settings', 'name', 'deletedDateTime',
        'policyGuid'
    )

    foreach ($prop in $PolicyData.PSObject.Properties) {
        if ($prop.Name -in $skip) { continue }
        if ($prop.Name -match '@odata') { continue }
        # Skip internal flags (but keep linkedComplianceScript — it's rendered by MR card)
        if ($prop.Name -eq '_claimedByCompliancePolicy') { continue }
        if ($prop.Name -eq 'Length' -and $prop.Value -is [int]) { continue }
        $val = $prop.Value
        if ($val -is [PSObject] -and $val.PSObject.Properties.Count -gt 0 -and $Depth -lt 2) {
            [void]$rows.Add([PSCustomObject]@{
                Name        = (ConvertTo-FriendlySettingName -Name $prop.Name)
                Value       = ''
                Indent      = $Depth
                IsConfigured = $false
            })
            foreach ($r in (ConvertTo-FlatSettingRows -PolicyData $val -Depth ($Depth + 1))) {
                [void]$rows.Add($r)
            }
        } elseif ($val -is [array] -and $val.Count -gt 0 -and $val[0] -is [PSObject] -and $Depth -lt 2) {
            # Array of objects — show count + extract display names (original behavior)
            # Special handling: recurse into scheduledActionConfigurations for compliance rules
            $propLower = $prop.Name.ToLowerInvariant()
            if ($propLower -eq 'scheduledactionsforrule' -or $propLower -eq 'scheduledactionconfigurations') {
                # Compliance: recurse to extract actionType, gracePeriodHours, rulesContent etc.
                [void]$rows.Add([PSCustomObject]@{
                    Name        = (ConvertTo-FriendlySettingName -Name $prop.Name)
                    Value       = ''
                    Indent      = $Depth
                    IsConfigured = $false
                })
                foreach ($item in $val) {
                    if ($item -is [PSObject]) {
                        foreach ($r in (ConvertTo-FlatSettingRows -PolicyData $item -Depth ($Depth + 1))) {
                            [void]$rows.Add($r)
                        }
                    }
                }
            } else {
                [void]$rows.Add([PSCustomObject]@{
                    Name        = (ConvertTo-FriendlySettingName -Name $prop.Name)
                    Value       = "$($val.Count) items"
                    Indent      = $Depth
                    IsConfigured = $true
                })
                foreach ($item in $val) {
                    if ($item -is [PSObject]) {
                        $itemName = $null
                        foreach ($nameField in @('displayName', 'name', 'id', 'bundleId', 'packageId')) {
                            $nv = $item.PSObject.Properties[$nameField]
                            if ($nv -and $nv.Value) { $itemName = $nv.Value.ToString(); break }
                        }
                        # Fallback: check nested mobileAppIdentifier (MAM app protection policies)
                        if (-not $itemName) {
                            $mai = $item.PSObject.Properties['mobileAppIdentifier']
                            if ($mai -and $mai.Value -is [PSObject]) {
                                foreach ($nameField in @('bundleId', 'packageId')) {
                                    $nv2 = $mai.Value.PSObject.Properties[$nameField]
                                    if ($nv2 -and $nv2.Value) { $itemName = $nv2.Value.ToString(); break }
                                }
                            }
                        }
                        if ($itemName) {
                            [void]$rows.Add([PSCustomObject]@{
                                Name        = $itemName
                                Value       = ''
                                Indent      = $Depth + 1
                                IsConfigured = $true
                            })
                        }
                    }
                }
            }
        } else {
            $strVal = if ($null -eq $val) { '' }
                      elseif ($val -is [array]) {
                          $joined = @($val | ForEach-Object { if ($_ -is [string] -or $_ -is [ValueType]) { $_.ToString() } }) -join ', '
                          if ([string]::IsNullOrWhiteSpace($joined) -and $val.Count -gt 0) { "$($val.Count) items" } else { $joined }
                      } else { $val.ToString() }
            # Decode base64-encoded content (scripts and rulesContent JSON)
            if ($prop.Name -match '(?i)scriptContent|detectionScriptContent|remediationScriptContent|rulesContent' -and
                $strVal -is [string] -and $strVal.Length -gt 20 -and $strVal -notmatch '\s') {
                try {
                    $decoded = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($strVal))
                    $strVal = "__SCRIPT_CODE__$decoded"
                } catch { <# not valid base64, keep original #> }
            }
            # Dotted property names (e.g. Entra settings): emit parent folder rows with indentation
            if ($prop.Name.Contains('.')) {
                $segments = $prop.Name -split '\.'
                for ($i = 0; $i -lt $segments.Count - 1; $i++) {
                    $parentName = ConvertTo-FriendlySettingName -Name $segments[$i]
                    # Only emit parent row if it hasn't been emitted yet (track via a script-scoped set)
                    $parentKey = ($segments[0..$i] -join '.').ToLowerInvariant()
                    if (-not $script:_emittedDotParents.Contains($parentKey)) {
                        [void]$script:_emittedDotParents.Add($parentKey)
                        [void]$rows.Add([PSCustomObject]@{
                            Name        = $parentName
                            Value       = ''
                            Indent      = $Depth + $i
                            IsConfigured = $false
                        })
                    }
                }
                $leafName = ConvertTo-FriendlySettingName -Name $segments[-1]
                [void]$rows.Add([PSCustomObject]@{
                    Name        = $leafName
                    Value       = $strVal
                    Indent      = $Depth + $segments.Count - 1
                    IsConfigured = $true
                })
            } else {
                [void]$rows.Add([PSCustomObject]@{
                    Name        = (ConvertTo-FriendlySettingName -Name $prop.Name)
                    Value       = $strVal
                    Indent      = $Depth
                    IsConfigured = $true
                })
            }
        }
    }

    $rows
}
