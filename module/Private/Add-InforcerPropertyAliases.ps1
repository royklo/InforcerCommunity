function Add-InforcerPropertyAliases {
    <#
    .SYNOPSIS
        Adds PascalCase alias properties to API response objects (Private helper).
    .DESCRIPTION
        Adds PascalCase alias properties to API response objects (Private helper).
        Adds aliases only when the source property exists and the alias does not.
        ObjectType: Tenant, Baseline, Policy, AlignmentScore, AuditEvent.
    .PARAMETER InputObject
        The PSObject to add aliases to (e.g. from API).
    .PARAMETER ObjectType
        Type of object for alias mapping.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Tenant', 'Baseline', 'Policy', 'AlignmentScore', 'AuditEvent')]
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
                AddAliasIfExists $obj 'ClientTenantId' 'clientTenantId'
                AddAliasIfExists $obj 'MsTenantId' 'msTenantId'
                AddAliasIfExists $obj 'TenantFriendlyName' 'tenantFriendlyName'
                AddAliasIfExists $obj 'TenantDnsName' 'tenantDnsName'
                AddAliasIfExists $obj 'SecureScore' 'secureScore'
                AddAliasIfExists $obj 'IsBaseline' 'isBaseline'
                AddAliasIfExists $obj 'LastBackupTimestamp' 'lastBackupTimestamp'
                AddAliasIfExists $obj 'RecentChanges' 'recentChanges'
                AddAliasIfExists $obj 'PolicyDiff' 'policyDiff'
                # Licenses: replace array with comma-separated string (e.g. sku values or item ToString())
                $licensesProp = $obj.PSObject.Properties['licenses']
                if ($licensesProp -and $null -ne $licensesProp.Value) {
                    $arr = @($licensesProp.Value)
                    $parts = @()
                    foreach ($x in $arr) {
                        if ($null -eq $x) { continue }
                        if ($x -is [PSObject] -and $x.PSObject.Properties['sku']) {
                            $parts += $x.PSObject.Properties['sku'].Value -as [string]
                        } elseif ($x -is [PSObject] -and $x.PSObject.Properties['name']) {
                            $parts += $x.PSObject.Properties['name'].Value -as [string]
                        } else {
                            $parts += $x.ToString().Trim()
                        }
                    }
                    $licensesStr = ($parts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join ', '
                    if ($obj.PSObject.Properties['licenses']) { $obj.PSObject.Properties.Remove('licenses') }
                    $obj.PSObject.Properties.Add([System.Management.Automation.PSNoteProperty]::new('licenses', $licensesStr))
                }
                # PolicyDiff formatted from recentChanges when available (structured: Changed / Added / Removed)
                $recentProp = $obj.PSObject.Properties['recentChanges']
                if ($recentProp -and $null -ne $recentProp.Value -and -not $obj.PSObject.Properties['PolicyDiffFormatted']) {
                    $rc = $recentProp.Value
                    $lines = @()
                    if ($rc -is [PSObject]) {
                        foreach ($sectionName in @('changedPolicies','addedPolicies','removedPolicies','changed','added','removed')) {
                            $sectionProp = $rc.PSObject.Properties[$sectionName]
                            if (-not $sectionProp -or $null -eq $sectionProp.Value) { continue }
                            $label = switch -Regex ($sectionName) { 'changed' { 'Changed Policies' } 'added' { 'Added Policies' } 'removed' { 'Removed Policies' } default { $sectionName } }
                            $lines += $label + ':'
                            $items = $sectionProp.Value
                            if ($items -is [object[]]) {
                                foreach ($i in $items) {
                                    $s = if ($i -is [PSObject]) { $i.ToString() } else { $i -as [string] }
                                    if ($s) { $lines += "  - $s" }
                                }
                            } elseif ($items -is [string]) { $lines += "  - $items" }
                        }
                    }
                    if ($lines.Count -gt 0) {
                        $obj.PSObject.Properties.Add([System.Management.Automation.PSNoteProperty]::new('PolicyDiffFormatted', ($lines -join "`n")))
                    }
                }
            }
            'Baseline' {
                AddAliasIfExists $obj 'BaselineClientTenantId' 'baselineClientTenantId'
                AddAliasIfExists $obj 'BaselineId' 'id'
                AddAliasIfExists $obj 'BaselineName' 'name'
                AddAliasIfExists $obj 'BaselineTenantFriendlyName' 'baselineTenantFriendlyName'
                AddAliasIfExists $obj 'BaselineTenantDnsName' 'baselineTenantDnsName'
                AddAliasIfExists $obj 'BaselineMsTenantId' 'baselineMsTenantId'
                AddAliasIfExists $obj 'AlignedThreshold' 'alignedThreshold'
                AddAliasIfExists $obj 'SemiAlignedThreshold' 'semiAlignedThreshold'
                $membersProp = $obj.PSObject.Properties['members']
                if ($membersProp -and $membersProp.Value -is [object[]]) {
                    foreach ($member in $membersProp.Value) {
                        if ($member -is [PSObject]) {
                            AddAliasIfExists $member 'ClientTenantId' 'clientTenantId'
                            AddAliasIfExists $member 'MsTenantId' 'msTenantId'
                            AddAliasIfExists $member 'TenantFriendlyName' 'tenantFriendlyName'
                            AddAliasIfExists $member 'TenantDnsName' 'tenantDnsName'
                            AddAliasIfExists $member 'SecureScore' 'secureScore'
                            AddAliasIfExists $member 'IsBaseline' 'isBaseline'
                            AddAliasIfExists $member 'LastBackupTimestamp' 'lastBackupTimestamp'
                            AddAliasIfExists $member 'RecentChanges' 'recentChanges'
                        }
                    }
                }
            }
            'Policy' {
                AddAliasIfExists $obj 'PolicyId' 'id'
                AddAliasIfExists $obj 'PolicyTypeId' 'policyTypeId'
                AddAliasIfExists $obj 'FriendlyName' 'friendlyName'
                AddAliasIfExists $obj 'ReadOnly' 'readOnly'
                AddAliasIfExists $obj 'Product' 'product'
                AddAliasIfExists $obj 'PrimaryGroup' 'primaryGroup'
                AddAliasIfExists $obj 'SecondaryGroup' 'secondaryGroup'
                AddAliasIfExists $obj 'Platform' 'platform'
                AddAliasIfExists $obj 'PolicyCategoryId' 'policyCategoryId'
                # PolicyName: always set from displayName, name, or friendlyName (in that order); fallback "Policy {id}"
                $policyNameVal = $obj.PSObject.Properties['displayName'].Value -as [string]
                if ([string]::IsNullOrWhiteSpace($policyNameVal)) { $policyNameVal = $obj.PSObject.Properties['name'].Value -as [string] }
                if ([string]::IsNullOrWhiteSpace($policyNameVal)) { $policyNameVal = $obj.PSObject.Properties['friendlyName'].Value -as [string] }
                if ([string]::IsNullOrWhiteSpace($policyNameVal)) {
                    $idVal = $obj.PSObject.Properties['id'].Value
                    $policyNameVal = "Policy $(if ($null -ne $idVal) { $idVal } else { 'Unknown' })"
                }
                if ($obj.PSObject.Properties['PolicyName']) { $obj.PSObject.Properties.Remove('PolicyName') }
                $obj.PSObject.Properties.Add([System.Management.Automation.PSNoteProperty]::new('PolicyName', $policyNameVal))
                if ($obj.PSObject.Properties['FriendlyName']) { $obj.PSObject.Properties.Remove('FriendlyName') }
                $obj.PSObject.Properties.Add([System.Management.Automation.PSAliasProperty]::new('FriendlyName', 'PolicyName'))
                # Hide redundant name, displayName, friendlyName so only PolicyName is shown
                foreach ($hide in @('name', 'displayName', 'friendlyName')) {
                    if ($obj.PSObject.Properties[$hide]) { $obj.PSObject.Properties.Remove($hide) }
                }
            }
            'AlignmentScore' {
                AddAliasIfExists $obj 'TenantId' 'tenantId'
                AddAliasIfExists $obj 'TenantFriendlyName' 'tenantFriendlyName'
                AddAliasIfExists $obj 'Score' 'score'
                AddAliasIfExists $obj 'BaselineGroupId' 'baselineGroupId'
                AddAliasIfExists $obj 'BaselineGroupName' 'baselineGroupName'
                AddAliasIfExists $obj 'LastComparisonDateTime' 'lastComparisonDateTime'
            }
            'AuditEvent' {
                AddAliasIfExists $obj 'CorrelationId' 'correlationId'
                AddAliasIfExists $obj 'ClientId' 'clientId'
                AddAliasIfExists $obj 'RelType' 'relType'
                AddAliasIfExists $obj 'RelId' 'relId'
                AddAliasIfExists $obj 'EventType' 'eventType'
                AddAliasIfExists $obj 'Message' 'message'
                AddAliasIfExists $obj 'Code' 'code'
                AddAliasIfExists $obj 'User' 'user'
                AddAliasIfExists $obj 'Timestamp' 'timestamp'
                # Flatten metadata onto the event so it works directly in the cmdlet output (no need to pipe .metadata)
                $meta = $obj.PSObject.Properties['metadata'].Value
                if ($null -ne $meta -and $meta -is [PSObject]) {
                    $metaProps = $meta.PSObject.Properties
                    # Only IPv4 and IPv6 (skip generic clientIp to avoid duplicating when same as clientIpv4)
                    foreach ($pn in @('clientIpv4','clientIpv6')) {
                        $p = $metaProps[$pn]
                        if ($null -eq $p) { $p = $metaProps[$pn -replace '^c', 'C'] }
                        $noteName = $pn -replace '^c', 'C'
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
                                if ($k -match 'username') { $username = $v }
                                if ($k -match 'displayName') { $displayName = $v }
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
                # Remove metadata property so output only shows flattened top-level fields
                if ($obj.PSObject.Properties['metadata']) {
                    $obj.PSObject.Properties.Remove('metadata')
                }
            }
        }

        $obj
    }
}
