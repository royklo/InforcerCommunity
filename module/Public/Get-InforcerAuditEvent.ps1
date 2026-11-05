<#
.SYNOPSIS
    Retrieves audit events from the Inforcer API.

    Required API scope(s): Audit.Read (API key, unconfirmed — see docs/API-REFERENCE.md); Activity
    permission (API client, unconfirmed).
.DESCRIPTION
    POST /auditEvents/search on both login types (API key: /beta, client credentials: /v1). With client credentials the response has no ClientId or Message fields. When -DateFrom and -DateTo are omitted, uses a wide default range (10 years ago to now).
    When -EventType is not specified, no event-type filter is sent and the API searches all types (one search, both login types).
    Events come back in the API's order. The -EventType tab-completion list is not refreshed by this
    cmdlet; run Get-InforcerSupportedEventType for that.
    Use -Id to retrieve a specific event by its event ID. Use -CorrelationId to retrieve all events
    sharing a correlation ID. Both perform a broad search and filter client-side.
.PARAMETER Id
    Retrieve a specific audit event by its event ID (GUID). Searches all event types and filters client-side.
.PARAMETER CorrelationId
    Retrieve all audit events sharing this correlation ID. Searches all event types and filters client-side.
.PARAMETER EventType
    Event types to include. Omit for all types (tab-complete with supported event types).
.PARAMETER DateFrom
    Start of date/time range (inclusive). Omit with DateTo = 10 years ago to now; if only DateTo set = 30 days before DateTo.
.PARAMETER DateTo
    End of date/time range (inclusive). Omit with DateFrom = now (UTC).
.PARAMETER User
    Filter events server-side by this user (matches the `user` field in the API request body).
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
    Get-InforcerAuditEvent -Id "00000000-0000-0000-0000-00000000000a"
    Retrieves a single audit event by its ID.
.EXAMPLE
    Get-InforcerAuditEvent -CorrelationId "00000000-0000-0000-0000-00000000000b"
    Retrieves all audit events sharing a correlation ID.
.EXAMPLE
    Get-InforcerAuditEvent -DateFrom (Get-Date).AddDays(-7) -DateTo (Get-Date)
.EXAMPLE
    Get-InforcerAuditEvent -EventType authentication,failedAuthentication -DateFrom $from -DateTo $to
.EXAMPLE
    Get-InforcerAuditEvent -OutputType JsonObject
    Returns a JSON string (a JSON array on v1 even for zero or one event); output objects do not include a metadata property (flattened to top-level fields).
.OUTPUTS
    PSObject or String (JSON array when -OutputType JsonObject)
.LINK
    https://github.com/royklo/InforcerCommunity/blob/main/docs/CMDLET-REFERENCE.md#get-inforcerauditevent
.LINK
    Connect-Inforcer
#>

function Get-InforcerAuditEvent {
[CmdletBinding()]
[OutputType([PSObject], [string])]
param(
    [Parameter(Mandatory = $false)]
    [string]$Id,

    [Parameter(Mandatory = $false)]
    [string]$CorrelationId,

    [Parameter(Mandatory = $false)]
    [ArgumentCompleter({
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        $prefix = if ($wordToComplete) { $wordToComplete } else { '' }
        if ($prefix -match ',') {
            $prefix = ($prefix -split ',' | ForEach-Object { $_.Trim() })[-1]
        }
        $prefix = $prefix.Trim()
        # Dynamic: read $global:InforcerCachedEventTypes populated by Get-InforcerSupportedEventType.ps1
        # at module import (static fallback) and refreshed with live data after any authenticated
        # Get-InforcerSupportedEventType call. Two-item minimum fallback covers the case where a user
        # somehow imports only Get-InforcerAuditEvent without the sibling file.
        $types = if ($global:InforcerCachedEventTypes -and $global:InforcerCachedEventTypes.Count -gt 0) {
            $global:InforcerCachedEventTypes
        } else {
            @('authentication', 'failedAuthentication')
        }
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
    [string]$User,

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

# No -EventType: eventTypes is omitted and the API searches every type (both logins; checked live on
# beta, where it returns the same events as listing all types).
$isV1 = $script:InforcerSession.ApiVersion -eq 'v1'
$eventTypes = @($EventType | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

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
$dateToStr = $dateToVal.ToUniversalTime().ToString($(if ($isV1) { 'yyyy-MM-ddTHH:mm:ssZ' } else { 'yyyy-MM-ddTHH:mm:ss.fffZ' }))

$allItems = [System.Collections.Generic.List[object]]::new()

$bodyObj = @{
    dateFrom = $dateFromStr
    dateTo   = $dateToStr
    pageSize = $PageSize
}
if ($eventTypes.Count -gt 0) { $bodyObj['eventTypes'] = $eventTypes }
if ($User) { $bodyObj['user'] = $User }

Write-Verbose 'Searching audit events...'
foreach ($item in @(Invoke-InforcerPagedRequest -Endpoint '/auditEvents/search' -Method POST -Body $bodyObj -ObjectType AuditEvent -MaxResults $MaxResults)) {
    if ($item -is [PSObject]) {
        $null = Add-InforcerPropertyAliases -InputObject $item -ObjectType AuditEvent
        $item.PSObject.TypeNames.Insert(0, 'InforcerCommunity.AuditEvent')
        $allItems.Add($item)
    }
}

# Filter by -Id or -CorrelationId when specified
if (-not [string]::IsNullOrWhiteSpace($Id)) {
    $idTrimmed = $Id.Trim()
    $allItems = [System.Collections.Generic.List[object]]@($allItems | Where-Object {
        $idProp = $_.PSObject.Properties['id']
        $idProp -and $idProp.Value -and $idProp.Value.ToString() -eq $idTrimmed
    })
    if ($allItems.Count -eq 0) {
        Write-Warning "No audit event found with ID '$idTrimmed'."
        return
    }
}
if (-not [string]::IsNullOrWhiteSpace($CorrelationId)) {
    $corrTrimmed = $CorrelationId.Trim()
    $allItems = [System.Collections.Generic.List[object]]@($allItems | Where-Object {
        $corrProp = $_.PSObject.Properties['correlationId']
        $corrProp -and $corrProp.Value -and $corrProp.Value.ToString() -eq $corrTrimmed
    })
    if ($allItems.Count -eq 0) {
        Write-Warning "No audit events found with CorrelationId '$corrTrimmed'."
        return
    }
}

if ($OutputType -eq 'JsonObject') {
    if ($isV1) { return ConvertTo-Json -InputObject @($allItems) -Depth 100 }
    return $allItems | ConvertTo-Json -Depth 100
} else {
    $allItems
}
}
