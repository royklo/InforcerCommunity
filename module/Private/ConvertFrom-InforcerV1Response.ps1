$script:InforcerV1MetadataKeys = @('continuationToken', 'userCount', 'groupCount', 'memberCount', 'failedPolicyTypes')
$script:InforcerV1CollectionKeys = @('tenants', 'policies', 'users', 'groups', 'members', 'roles', 'baselines', 'alignmentScores',
    'assessments', 'reportRuns', 'outputs', 'reportTypes', 'auditEvents', 'eventTypes')

# Rename: v1 name -> canonical (beta) name. Nested: v1 property name -> map applied to its value(s).
# Flatten: v1 object property -> its child properties lifted onto the parent under canonical names.
$script:InforcerV1Map = @{
    Tenant            = @{ Rename = @{ name = 'tenantFriendlyName'; dnsName = 'tenantDnsName' }; Nested = @{ alignmentSummaries = 'AlignmentSummary' } }
    AlignmentSummary  = @{ Rename = @{ lastAlignmentTimestamp = 'lastAlignmentDateTime' } }
    Policy            = @{ Rename = @{ policyTypeName = 'inforcerPolicyTypeName' } }
    Baseline          = @{
        Flatten = @{ baselineTenant = [ordered]@{ msTenantId = 'baselineMsTenantId'; name = 'baselineTenantFriendlyName'; dnsName = 'baselineTenantDnsName' } }
        Nested  = @{ members = 'BaselineMember'; items = 'BaselineItem' }
    }
    BaselineMember    = @{ Rename = @{ name = 'tenantFriendlyName'; dnsName = 'tenantDnsName' } }
    BaselineItem      = @{ Rename = @{ product = 'policyCategoryProduct'; primaryGroup = 'policyCategoryPrimaryGroup'; secondaryGroup = 'policyCategorySecondaryGroup' } }
    AlignmentScore    = @{ Rename = @{ tenantName = 'tenantFriendlyName'; alignedBaselineId = 'baselineGroupId'; alignedBaselineName = 'baselineGroupName'; alignmentScore = 'score'; lastAlignmentTimestamp = 'lastComparisonDateTime' } }
    AlignmentMetrics  = @{ Rename = @{ matched = 'matchedPolicies'; deviated = 'deviatedPolicies'; missingFromTenant = 'recommendedPoliciesFromBaseline'; additionalInTenant = 'customerOnlyPolicies' } }
    ComparedPolicy    = @{
        Rename = @{ displayName = 'policyName'; policyTypeName = 'inforcerPolicyTypeName'; tags = 'policyTags'; tenantPolicies = 'matchingSubjectPolicies'; variables = 'matchingVariables' }
        Nested = @{ tenantPolicies = 'TenantPolicyMatch'; variables = 'Variable'; acceptedDeviations = 'AcceptedDeviation'; similarPolicies = 'SimilarPolicy' }
    }
    TenantPolicyMatch = @{ Rename = @{ tags = 'policyTags' }; Nested = @{ policyDataDiff = 'PolicyDiff'; policyAssignmentsDiff = 'PolicyDiff'; acceptedDeviations = 'AcceptedDeviation' } }
    PolicyDiff        = @{ Rename = @{ tenantValue = 'subjectValue' } }
    Variable          = @{ Rename = @{ name = 'variableName'; tenantValue = 'subjectValue' } }
    AcceptedDeviation = @{ Rename = @{ acceptedTimestamp = 'acceptedDateTime'; reason = 'acceptedReason' }; Nested = @{ policyDataDiff = 'PolicyDiff'; policyAssignmentsDiff = 'PolicyDiff' } }
    SimilarPolicy     = @{ Rename = @{ name = 'policyName'; categoryName = 'policyCategoryName' }; Nested = @{ policyDataDiff = 'PolicyDiff'; policyAssignmentsDiff = 'PolicyDiff' } }
    User              = @{ Rename = @{ groupCount = 'groups'; roleCount = 'roles' } }
    AssessmentRun     = @{ Rename = @{ assessmentId = 'assessment' } }
    ReportRun         = @{ Rename = @{ reportRunId = 'runId' } }
    ReportOutput      = @{ Rename = @{ msTenantId = 'tenantId' } }
}

$script:InforcerV1AlignmentBuckets = [ordered]@{
    matched                       = 'matchedPolicies'
    matchedWithAcceptedDeviations = 'matchedWithAcceptedDeviations'
    deviated                      = 'deviatedUnaccepted'
    missingFromTenant             = 'missingFromSubjectUnaccepted'
    additionalInTenant            = 'additionalInSubjectUnaccepted'
}

function ConvertFrom-InforcerV1Response {
    <#
    .SYNOPSIS
        Maps v1 API objects to the module's canonical (beta) property names (Private helper).
    .DESCRIPTION
        Pure function: returns new objects, never calls the API. Renamed v1 keys are removed (no
        duplicate keys); v1-only properties are kept; property order is preserved. When a v1 object
        already carries the canonical name, that value wins and the v1 duplicate is dropped.
        Types without renames (Group, GroupMember, Role, SecureScore, Assessment, ReportType,
        AuditEvent, AuditEventType) are returned unchanged.
    .PARAMETER InputObject
        One or more v1 objects (collection items, or a single-object response).
    .PARAMETER ObjectType
        The kind of object, selecting the mapping.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [AllowNull()]
        [AllowEmptyCollection()]
        [object[]]$InputObject,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Tenant', 'Policy', 'Baseline', 'AlignmentScore', 'AlignmentDetails', 'User', 'Group', 'GroupMember', 'Role',
            'SecureScore', 'Assessment', 'AssessmentRun', 'ReportType', 'ReportRun', 'ReportOutput', 'AuditEvent', 'AuditEventType')]
        [string]$ObjectType
    )

    process {
        foreach ($item in $InputObject) {
            if ($null -eq $item) { continue }
            if ($ObjectType -eq 'AlignmentDetails') { ConvertFrom-InforcerV1AlignmentDetail $item }
            elseif ($script:InforcerV1Map.ContainsKey($ObjectType)) { ConvertFrom-InforcerV1Object $item $ObjectType }
            else { $item }
        }
    }
}

function ConvertFrom-InforcerV1Object {
    param($Object, [string]$MapName)

    if ($Object -isnot [System.Management.Automation.PSCustomObject]) { return $Object }
    $map = $script:InforcerV1Map[$MapName]
    $rename = $map.Rename; $nested = $map.Nested; $flatten = $map.Flatten

    $sourceNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($p in $Object.PSObject.Properties) { [void]$sourceNames.Add($p.Name) }

    $out = [ordered]@{}
    foreach ($p in $Object.PSObject.Properties) {
        $value = $p.Value
        if ($nested -and $nested.ContainsKey($p.Name)) { $value = ConvertFrom-InforcerV1Value $value $nested[$p.Name] }

        if ($flatten -and $flatten.ContainsKey($p.Name)) {
            if ($value -is [System.Management.Automation.PSCustomObject]) {
                $childMap = $flatten[$p.Name]
                foreach ($c in $value.PSObject.Properties) {
                    $target = if ($childMap.Contains($c.Name)) { $childMap[$c.Name] } else { "$($p.Name)$($c.Name.Substring(0,1).ToUpperInvariant())$($c.Name.Substring(1))" }
                    if (-not $sourceNames.Contains($target) -and -not $out.Contains($target)) { $out[$target] = $c.Value }
                }
            } else {
                foreach ($target in $flatten[$p.Name].Values) {
                    if (-not $sourceNames.Contains($target) -and -not $out.Contains($target)) { $out[$target] = $null }
                }
            }
            continue
        }

        $name = $p.Name
        if ($rename -and $rename.ContainsKey($name)) {
            $target = $rename[$name]
            # The canonical name already exists on the source object: keep that one, drop the v1 duplicate.
            if ($sourceNames.Contains($target) -and -not $rename.ContainsKey($target)) { continue }
            $name = $target
        }
        if (-not $out.Contains($name)) { $out[$name] = $value }
    }
    [PSCustomObject]$out
}

function ConvertFrom-InforcerV1Value {
    param($Value, [string]$MapName)

    if ($null -eq $Value) { return $null }
    if ($Value -is [array]) {
        $list = [System.Collections.Generic.List[object]]::new($Value.Count)
        foreach ($v in $Value) { $list.Add((ConvertFrom-InforcerV1Object $v $MapName)) }
        return , $list.ToArray()
    }
    ConvertFrom-InforcerV1Object $Value $MapName
}

function ConvertFrom-InforcerV1AlignmentDetail {
    param($Object)

    if ($Object -isnot [System.Management.Automation.PSCustomObject]) { return $Object }
    $consumed = @{ alignmentScore = 'alignmentScore'; baselineDataTimestamp = 'baselineDataTimestamp'; tenantDataTimestamp = 'subjectDataTimestamp'; policies = $null }

    $alignment = [ordered]@{}
    foreach ($key in 'alignmentScore', 'baselineDataTimestamp', 'tenantDataTimestamp') {
        $prop = $Object.PSObject.Properties[$key]
        if ($prop) { $alignment[$consumed[$key]] = $prop.Value }
    }
    $policies = $Object.PSObject.Properties['policies'].Value
    if ($policies -is [System.Management.Automation.PSCustomObject]) {
        foreach ($bucket in $policies.PSObject.Properties) {
            $target = if ($script:InforcerV1AlignmentBuckets.Contains($bucket.Name)) { $script:InforcerV1AlignmentBuckets[$bucket.Name] } else { $bucket.Name }
            $alignment[$target] = ConvertFrom-InforcerV1Value $bucket.Value 'ComparedPolicy'
        }
    }

    $out = [ordered]@{}
    foreach ($p in $Object.PSObject.Properties) {
        if ($consumed.ContainsKey($p.Name)) {
            $out['alignment'] = [PSCustomObject]$alignment
            continue
        }
        if ($out.Contains($p.Name)) { continue }
        $out[$p.Name] = $p.Value
        if ($p.Name -eq 'metrics') { $out[$p.Name] = ConvertFrom-InforcerV1Value $p.Value 'AlignmentMetrics' }
    }
    [PSCustomObject]$out
}

function Get-InforcerV1CollectionName {
    <#
    .SYNOPSIS
        Returns the name of the single collection property of a v1 list response, or $null for a single object (Private helper).
    .DESCRIPTION
        v1 list responses are an object with exactly one collection plus optional metadata keys
        (continuationToken, userCount, groupCount, memberCount, failedPolicyTypes). Single-object
        responses are returned bare and never count as a collection, even when they hold arrays.
    #>
    param($Response)

    if ($Response -isnot [System.Management.Automation.PSCustomObject]) { return $null }
    $c = $null
    foreach ($p in $Response.PSObject.Properties) {
        if ($p.Name -in $script:InforcerV1MetadataKeys) { continue }
        if ($c) { return $null }
        $c = $p
    }
    if (-not $c) { return $null }
    if ($c.Value -is [array] -or ($null -eq $c.Value -and $c.Name -in $script:InforcerV1CollectionKeys)) { return $c.Name }
    $null
}
