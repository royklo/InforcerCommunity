function Add-InforcerPropertyAliases {
    <#
    .SYNOPSIS
        Normalises an API response object: real property renames plus per-type shape fixes (Private helper).
    .DESCRIPTION
        Adds an alias only where the API's own name is ambiguous or awkward — `id` on a baseline
        becomes `BaselineId`, `sizeBytes` becomes `FileSize`. Nine such renames exist.

        It deliberately does NOT add PascalCase aliases for properties that differ from the API
        name only by case. There used to be 229 of those calls and every one of them was a no-op:
        `$o.PSObject.Properties['ClientTenantId']` is a case-INSENSITIVE lookup, so it found the
        existing `clientTenantId` and the "does the alias already exist" guard bailed every time.

        That turned out to be the right behaviour arrived at by accident, so the calls were removed
        rather than repaired:
          - PowerShell member access is already case-insensitive. `$tenant.ClientTenantId` and even
            `$tenant.TENANTFRIENDLYNAME` resolve today with no alias present. There is nothing to fix.
          - An alias IS serialised. The nine real renames already emit both `"id"` and `"BaselineId"`
            in ConvertTo-Json and as two separate Export-Csv columns. Adding 229 more would have
            doubled every key and column in two casings — the same value, twice.
          - `-OutputType JsonObject` returns before this helper runs, on purpose, so the JSON surface
            is the raw API shape and never carried PascalCase in the first place.

        Some -ObjectType values now have no branch at all. That is intentional: the type needs no
        normalisation, and a missing branch is a no-op. Keep passing the type from the cmdlet so
        there is somewhere obvious to put a rename if the API ever needs one.
    .PARAMETER InputObject
        The PSObject to normalise (e.g. from API).
    .PARAMETER ObjectType
        Type of object, selecting which normalisation to apply.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Tenant', 'Baseline', 'Policy', 'AlignmentScore', 'AlignmentDetail', 'AuditEvent', 'UserSummary', 'User', 'GroupSummary', 'Group', 'Role', 'Assessment', 'ReportType', 'ReportRun', 'ReportOutput', 'SecureScore')]
        [string]$ObjectType
    )

    process {
        if ($null -eq $InputObject) { return }

        $obj = $InputObject

        function AddAliasIfExists {
            param([PSObject]$o, [string]$aliasName, [string]$sourceName)
            if ($null -eq $o) { return }
            $src = $o.PSObject.Properties[$sourceName]
            $al = $o.PSObject.Properties[$aliasName]
            if ($src -and -not $al) {
                $o.PSObject.Properties.Add([System.Management.Automation.PSAliasProperty]::new($aliasName, $sourceName))
            }
        }

        switch ($ObjectType) {
            'Tenant' {
                # Licenses: replace array with comma-separated string (e.g. sku values or item ToString())
                $licensesProp = $obj.PSObject.Properties['licenses']
                if ($licensesProp -and $null -ne $licensesProp.Value) {
                    $arr = @($licensesProp.Value)
                    $parts = [System.Collections.Generic.List[string]]::new($arr.Count)
                    foreach ($x in $arr) {
                        if ($null -eq $x) { continue }
                        $val = $null
                        if ($x -is [PSObject] -and $x.PSObject.Properties['sku']) {
                            $val = $x.PSObject.Properties['sku'].Value -as [string]
                        } elseif ($x -is [PSObject] -and $x.PSObject.Properties['name']) {
                            $val = $x.PSObject.Properties['name'].Value -as [string]
                        } else {
                            $val = $x.ToString().Trim()
                        }
                        if (-not [string]::IsNullOrWhiteSpace($val)) { [void]$parts.Add($val) }
                    }
                    $licensesStr = $parts -join ', '
                    $licensesProp.Value = $licensesStr
                }
            }
            'Baseline' {
                # 'id' and 'name' are ambiguous on an object that also carries baselineTenant* fields.
                AddAliasIfExists $obj 'BaselineId' 'id'
                AddAliasIfExists $obj 'BaselineName' 'name'
            }
            'Policy' {
                AddAliasIfExists $obj 'PolicyId' 'id'
                # PolicyName: always set from displayName, name, or friendlyName (in that order); fallback "Policy {id}"
                $policyNameVal = $obj.PSObject.Properties['displayName'].Value -as [string]
                if ([string]::IsNullOrWhiteSpace($policyNameVal)) { $policyNameVal = $obj.PSObject.Properties['name'].Value -as [string] }
                if ([string]::IsNullOrWhiteSpace($policyNameVal)) { $policyNameVal = $obj.PSObject.Properties['friendlyName'].Value -as [string] }
                if ([string]::IsNullOrWhiteSpace($policyNameVal)) {
                    $idVal = $obj.PSObject.Properties['id'].Value
                    $policyNameVal = "Policy $(if ($null -ne $idVal) { $idVal } else { 'Unknown' })"
                }
                $pnProp = $obj.PSObject.Properties['PolicyName']
                if ($pnProp) { $pnProp.Value = $policyNameVal }
                else { $obj.PSObject.Properties.Add([System.Management.Automation.PSNoteProperty]::new('PolicyName', $policyNameVal)) }
                # Hide redundant name, displayName, friendlyName so only PolicyName is shown
                foreach ($hide in @('name', 'displayName', 'friendlyName')) {
                    if ($obj.PSObject.Properties[$hide]) { $obj.PSObject.Properties.Remove($hide) }
                }
                # Add FriendlyName alias AFTER removing originals (PSObject.Properties is case-insensitive)
                if (-not $obj.PSObject.Properties['FriendlyName']) {
                    $obj.PSObject.Properties.Add([System.Management.Automation.PSAliasProperty]::new('FriendlyName', 'PolicyName'))
                }
            }
            'AuditEvent' {
                # Flatten metadata onto the event so it works directly in the cmdlet output (no need to pipe .metadata)
                $meta = $obj.PSObject.Properties['metadata'].Value
                if ($null -ne $meta -and $meta -is [PSObject]) {
                    $metaProps = $meta.PSObject.Properties
                    # Only IPv4 and IPv6 (skip generic clientIp to avoid duplicating when same as clientIpv4)
                    foreach ($pn in @('clientIpv4','clientIpv6')) {
                        $noteName = $pn.Substring(0,1).ToUpper() + $pn.Substring(1)
                        $p = $metaProps[$pn]
                        if ($null -eq $p) { $p = $metaProps[$noteName] }
                        if (-not $obj.PSObject.Properties[$noteName]) {
                            $val = if ($p -and $null -ne $p.Value) { $p.Value } else { '' }
                            $obj.PSObject.Properties.Add([System.Management.Automation.PSNoteProperty]::new($noteName, $val))
                        }
                    }
                    $nameLookup = $metaProps['nameLookup'].Value
                    if ($null -ne $nameLookup) {
                        $username = $null
                        $displayName = $null
                        if ($nameLookup -is [PSObject]) {
                            foreach ($kp in $nameLookup.PSObject.Properties) {
                                $k = $kp.Name; $v = $kp.Value
                                # Only match user: prefixed keys (e.g. "user:username:763", "user:displayName:763")
                                # Skip non-user keys like "alertRuleConfig:displayName:..."
                                if ($k -like 'user:username:*') { $username = $v }
                                if ($k -like 'user:displayName:*') { $displayName = $v }
                            }
                        }
                        if ($username -and -not $obj.PSObject.Properties['UserName']) {
                            $obj.PSObject.Properties.Add([System.Management.Automation.PSNoteProperty]::new('UserName', $username))
                        }
                        if ($displayName -and -not $obj.PSObject.Properties['UserDisplayName']) {
                            $obj.PSObject.Properties.Add([System.Management.Automation.PSNoteProperty]::new('UserDisplayName', $displayName))
                        }
                    }
                }
                # Keep metadata on the object — Format.ps1xml controls default view.
                # Metadata contains event-type-specific data (e.g. alertRuleCreate has createAlertRuleConfigCommand)
                # accessible via $event.metadata or Select-Object *.
            }
            'ReportType' {
                # API uses 'supportedOutputFormats' (confirmed against api-uk.inforcer.com beta).
                AddAliasIfExists $obj 'OutputFormats' 'supportedOutputFormats'
                AddAliasIfExists $obj 'Parameters' 'requiredParameters'
                # Note: raw 'tags' shape is left intact (array OR comma-separated string from the
                # API); downstream filters (e.g. Get-InforcerReportType -Tag) rely on the raw shape,
                # and the Format.ps1xml view joins for display.
            }
            'ReportRun' {
                # API uses 'runId'. 'Id' is what every other object type calls its identifier, so
                # the alias keeps `$run.Id` working across types.
                AddAliasIfExists $obj 'Id' 'runId'
            }
            'ReportOutput' {
                # Output record uses: id (output id), reportType, tenantId, format, sizeBytes
                AddAliasIfExists $obj 'OutputId' 'id'
                AddAliasIfExists $obj 'OutputFormat' 'format'
                AddAliasIfExists $obj 'FileSize' 'sizeBytes'
            }
            # AlignmentScore, AlignmentDetail, UserSummary, User, GroupSummary, Group, Role,
            # Assessment and SecureScore need no normalisation: every property they carry is
            # already reachable case-insensitively under the API's own name.
        }

        $obj
    }
}
