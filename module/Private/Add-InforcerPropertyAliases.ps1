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
        [ValidateSet('Tenant', 'Baseline', 'Policy', 'AlignmentScore', 'AlignmentDetail', 'AuditEvent')]
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
            'AlignmentScore' {
                AddAliasIfExists $obj 'TenantId' 'tenantId'
                AddAliasIfExists $obj 'TenantFriendlyName' 'tenantFriendlyName'
                AddAliasIfExists $obj 'Score' 'score'
                AddAliasIfExists $obj 'BaselineGroupId' 'baselineGroupId'
                AddAliasIfExists $obj 'BaselineGroupName' 'baselineGroupName'
                AddAliasIfExists $obj 'LastComparisonDateTime' 'lastComparisonDateTime'
            }
            'AlignmentDetail' {
                # Top-level alignment properties
                AddAliasIfExists $obj 'AlignmentScore' 'alignmentScore'
                AddAliasIfExists $obj 'BaselineTenantId' 'baselineTenantId'
                AddAliasIfExists $obj 'SubjectTenantId' 'subjectTenantId'
                AddAliasIfExists $obj 'SubjectDataTimestamp' 'subjectDataTimestamp'
                AddAliasIfExists $obj 'BaselineDataTimestamp' 'baselineDataTimestamp'
                AddAliasIfExists $obj 'CompletedAt' 'completedAt'
                # Metrics
                $metricsProp = $obj.PSObject.Properties['metrics']
                if ($metricsProp -and $null -ne $metricsProp.Value -and $metricsProp.Value -is [PSObject]) {
                    $m = $metricsProp.Value
                    AddAliasIfExists $m 'TotalPolicies' 'totalPolicies'
                    AddAliasIfExists $m 'MatchedPolicies' 'matchedPolicies'
                    AddAliasIfExists $m 'MatchedWithAcceptedDeviations' 'matchedWithAcceptedDeviations'
                    AddAliasIfExists $m 'DeviatedPolicies' 'deviatedPolicies'
                    AddAliasIfExists $m 'RecommendedPoliciesFromBaseline' 'recommendedPoliciesFromBaseline'
                    AddAliasIfExists $m 'CustomerOnlyPolicies' 'customerOnlyPolicies'
                }
                # Per-policy aliases (matchedPolicies and deviatedUnaccepted arrays)
                $alignPropCached = $obj.PSObject.Properties['alignment']
                if ($alignPropCached -and $null -ne $alignPropCached.Value) {
                    $alignVal = $alignPropCached.Value
                }
                foreach ($arrayName in @('matchedPolicies', 'matchedWithAcceptedDeviations', 'deviatedUnaccepted', 'missingFromSubjectUnaccepted', 'additionalInSubjectUnaccepted')) {
                    if ($null -eq $alignVal) { continue }
                    $policyArrayProp = $alignVal.PSObject.Properties[$arrayName]
                    if (-not $policyArrayProp -or $null -eq $policyArrayProp.Value) { continue }
                    foreach ($policy in @($policyArrayProp.Value)) {
                        if (-not ($policy -is [PSObject])) { continue }
                        AddAliasIfExists $policy 'PolicyName' 'policyName'
                        AddAliasIfExists $policy 'Product' 'product'
                        AddAliasIfExists $policy 'PrimaryGroup' 'primaryGroup'
                        AddAliasIfExists $policy 'SecondaryGroup' 'secondaryGroup'
                        AddAliasIfExists $policy 'Platform' 'platform'
                        AddAliasIfExists $policy 'PolicyTypeId' 'policyTypeId'
                        AddAliasIfExists $policy 'InforcerPolicyTypeName' 'inforcerPolicyTypeName'
                        AddAliasIfExists $policy 'PolicyCategoryId' 'policyCategoryId'
                        AddAliasIfExists $policy 'IsDeviation' 'isDeviation'
                        AddAliasIfExists $policy 'IsMissingFromSubject' 'isMissingFromSubject'
                        AddAliasIfExists $policy 'IsAdditionalInSubject' 'isAdditionalInSubject'
                        AddAliasIfExists $policy 'ReadOnly' 'readOnly'
                    }
                }
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
        }

        $obj
    }
}
