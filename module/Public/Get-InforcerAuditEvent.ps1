<#
.SYNOPSIS
    Retrieves audit events from the Inforcer API.
.DESCRIPTION
    POST /beta/auditEvents/search. When -DateFrom and -DateTo are omitted, uses a wide default range (10 years ago to now).
    When -EventType is not specified, uses all event types from the API (or fallback authentication, failedAuthentication).
.PARAMETER EventType
    Event types to include. Omit for all types (tab-complete with supported event types).
.PARAMETER DateFrom
    Start of date/time range (inclusive). Omit with DateTo = 10 years ago to now; if only DateTo set = 30 days before DateTo.
.PARAMETER DateTo
    End of date/time range (inclusive). Omit with DateFrom = now (UTC).
.PARAMETER PageSize
    Page size per API request. Default 100.
.PARAMETER MaxResults
    Maximum events to return. 0 = no limit (default).
.PARAMETER Format
    Raw (default).
.PARAMETER OutputType
    PowerShellObject (default) or JsonObject. JSON output uses Depth 100.
.EXAMPLE
    Get-InforcerAuditEvent
.EXAMPLE
    Get-InforcerAuditEvent -DateFrom (Get-Date).AddDays(-7) -DateTo (Get-Date)
.EXAMPLE
    Get-InforcerAuditEvent -EventType authentication,failedAuthentication -DateFrom $from -DateTo $to
.EXAMPLE
    Get-InforcerAuditEvent -OutputType JsonObject
    Returns a JSON array string; output objects do not include a metadata property (flattened to top-level fields).
.OUTPUTS
    PSObject or String (JSON array when -OutputType JsonObject)
.LINK
    Connect-Inforcer
#>

function Get-InforcerAuditEvent {
[CmdletBinding()]
[OutputType([PSObject], [string])]
param(
    [Parameter(Mandatory = $false)]
    [ArgumentCompleter({
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        $prefix = if ($wordToComplete) { $wordToComplete } else { '' }
        if ($prefix -match ',') {
            $prefix = ($prefix -split ',' | ForEach-Object { $_.Trim() })[-1]
        }
        $prefix = $prefix.Trim()
        # Inline list so completer never depends on script scope (avoids path completion fallback)
        $types = @(
            'authentication', 'failedAuthentication', 'supportAccessInvoke', 'userGroupCreate', 'userGroupUpdate',
            'userGroupDelete', 'userGroupMembershipModified', 'clientStatusChanged', 'clientCreated', 'salesAdminUpdated',
            'clientAdminUpdated', 'sharedBaselinesManaged', 'alertRuleCreate', 'alertRuleUpdate', 'alertRuleDelete',
            'apiKeyCreate', 'apiKeyDelete', 'apiKeyUsage', 'tenantUserCreate', 'tenantUserUpdate', 'tenantUserResetMfa',
            'tenantUserResetPassword', 'tenantUserRevokedSessions', 'tenantUserGroupMembershipModified', 'tenantUserOffboardingQueued',
            'tenantUserLicensesModified', 'tenantOnboard', 'tenantRefresh', 'tenantDelete', 'userCreate', 'userDelete',
            'userResetPassword', 'userResetMfa', 'userToggleEnable', 'userAutoProvision', 'userToggleSso',
            'tenantGroupCreate', 'tenantGroupUpdate', 'tenantGroupMembershipsModified', 'tenantGroupsDeployment',
            'policiesDeployment', 'policiesRestore', 'policiesRename', 'policiesDelete', 'tenantAssessmentRun',
            'tenantAssessmentSuccess', 'tenantAssessmentFailure', 'copilotAssessmentRun', 'copilotAssessmentSuccess', 'copilotAssessmentFailure',
            'tenantLicenseUpdate', 'clientLicenseUpdate'
        )
        $filterByPrefix = $prefix -and $prefix -notmatch '^[./\\]'
        if ($filterByPrefix) {
            $filtered = @($types | Where-Object { $_ -like "$prefix*" })
            $exactMatch = $filtered | Where-Object { $_ -ceq $prefix }
            if ($exactMatch.Count -ne 1) {
                $types = $filtered
            }
        }
        foreach ($t in $types) {
            [Management.Automation.CompletionResult]::new($t, $t, [Management.Automation.CompletionResultType]::ParameterValue, $t)
        }
    })]
    [string[]]$EventType,

    [Parameter(Mandatory = $false)]
    [DateTime]$DateFrom,

    [Parameter(Mandatory = $false)]
    [DateTime]$DateTo,

    [Parameter(Mandatory = $false)]
    [int]$PageSize = 100,

    [Parameter(Mandatory = $false)]
    [int]$MaxResults = 0,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Raw')]
    [string]$Format = 'Raw',

    [Parameter(Mandatory = $false)]
    [ValidateSet('PowerShellObject', 'JsonObject')]
    [string]$OutputType = 'PowerShellObject'
)

if (-not (Test-InforcerSession)) {
    Write-Error -Message 'Not connected yet. Please run Connect-Inforcer first.' -ErrorId 'NotConnected' -Category ConnectionError
    return
}

# Resolve event types
$eventTypes = @()
if ($null -eq $EventType -or $EventType.Count -eq 0) {
    Write-Verbose 'Fetching all audit event types from API...'
    try {
        $eventTypes = @(Get-InforcerAuditEventType -ErrorAction SilentlyContinue)
    } catch {
        $eventTypes = @()
    }
    if ($eventTypes.Count -eq 0) {
        Write-Verbose 'Event types API failed or returned none; using authentication, failedAuthentication.'
        $eventTypes = @('authentication', 'failedAuthentication')
    } else {
        Write-Verbose "Using all $($eventTypes.Count) event type(s)."
    }
} else {
    $eventTypes = @($EventType)
}

# Date range
$dateFromVal = $DateFrom
$dateToVal = $DateTo
if ($dateFromVal -and -not $dateToVal) { $dateToVal = [DateTime]::UtcNow }
if ($dateToVal -and -not $dateFromVal) { $dateFromVal = $dateToVal.AddDays(-30) }
if (-not $dateFromVal -and -not $dateToVal) {
    $dateToVal = [DateTime]::UtcNow
    $dateFromVal = $dateToVal.AddYears(-10)
}
$dateFromStr = $dateFromVal.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$dateToStr = $dateToVal.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ')

$allItems = [System.Collections.ArrayList]::new()
$hasLimit = $MaxResults -gt 0
$batchSize = 10
$typeBatches = @()
for ($i = 0; $i -lt $eventTypes.Count; $i += $batchSize) {
    $end = [Math]::Min($i + $batchSize, $eventTypes.Count)
    $typeBatches += ,@($eventTypes[$i..($end - 1)])
}

foreach ($batch in $typeBatches) {
    if ($hasLimit -and $allItems.Count -ge $MaxResults) { break }
    $continuationToken = $null
    do {
        $bodyObj = @{
            eventTypes = @($batch)
            dateFrom   = $dateFromStr
            dateTo     = $dateToStr
            pageSize   = $PageSize
        }
        if ($continuationToken) {
            $bodyObj['continuationToken'] = $continuationToken
        }
        $body = $bodyObj | ConvertTo-Json -Depth 100 -Compress

        Write-Verbose 'Searching audit events...'
        $response = Invoke-InforcerApiRequest -Endpoint '/beta/auditEvents/search' -Method POST -Body $body -OutputType PowerShellObject -PreserveStructure
        if ($null -eq $response) { break }

        # After -PreserveStructure, .data is already unwrapped but inner structure (items + continuationToken) is intact
        $root = $response
        $items = $null
        foreach ($propName in 'items', 'Items') {
            $prop = $root.PSObject.Properties[$propName]
            if ($prop -and $null -ne $prop.Value) { $items = $prop.Value; break }
        }

        if ($items) {
            foreach ($item in @($items)) {
                if ($item -is [PSObject]) {
                    Add-InforcerPropertyAliases -InputObject $item -ObjectType AuditEvent | Out-Null
                    [void]$allItems.Add($item)
                    if ($hasLimit -and $allItems.Count -ge $MaxResults) { break }
                }
            }
        }

        $continuationToken = $null
        foreach ($tokenProp in 'continuationToken', 'ContinuationToken') {
            $tp = $root.PSObject.Properties[$tokenProp]
            if ($tp -and $tp.Value) { $continuationToken = $tp.Value; break }
        }
        if ($hasLimit -and $allItems.Count -ge $MaxResults) { break }
    } while ($continuationToken)
}

if ($OutputType -eq 'JsonObject') {
    $json = $allItems | ConvertTo-Json -Depth 100
    return $json
} else {
    $allItems | ForEach-Object { $_ }
}
}
