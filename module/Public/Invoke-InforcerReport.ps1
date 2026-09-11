<#
.SYNOPSIS
    Queues one or more Inforcer reports, waits for completion, and saves the outputs.

    Required API scope(s): Reports.Read, Reports.Run
.DESCRIPTION
    POST /beta/reports/runs submits a batch of (ReportType, OutputFormat) pairs against the
    target tenants. By default the cmdlet runs synchronously: it polls the outputs endpoint
    until each run is terminal, downloads every output to the current directory (or -OutputPath),
    and emits a result object per saved file.

    Use -NoWait to return immediately after queueing (no polling, no download); use -NoSave
    to poll and return outputs metadata without writing files.

    Zip/broadcast rules for -ReportType / -OutputFormat:
      N reports + 1 format  → broadcast (format applied to every report)
      N reports + N formats → paired by index
      N reports + M formats → error (M ≠ 1 and M ≠ N)
      1 report  + N formats → error (would trigger duplicate-report-render bug)

    Client-side guards (verified empirically against the Inforcer Reports API):
      * Duplicate (type, outputFormat) pairs are removed before POST — known server-side bug
        otherwise renders all duplicates in the last-listed format.
      * -Collate is rejected when the catalog reports collatable:false on the type.
      * Unknown -Parameter keys are rejected — the server would otherwise silently ignore them.
      * Each tenant identifier is validated and resolved to a numeric Client Tenant ID before POST.
.PARAMETER ReportType
    One or more report type keys (e.g. CopilotAdoption, TenantAuditReport, Assessment). Case-
    insensitive. Get-InforcerReportType lists every available key. Pipeline-bindable by
    property name.
.PARAMETER OutputFormat
    One or more output formats (csv, json, pdf, html, xlsx, ...). Must be supported by every
    paired report type or the cmdlet errors before submitting. Case-insensitive.
.PARAMETER TenantId
    One or more tenant identifiers (numeric Client Tenant ID, Microsoft Tenant GUID, or tenant
    friendly/DNS name). Resolved via Resolve-InforcerTenantId.
.PARAMETER ReportPeriod
    Optional integer days — applied as the report-period parameter when supported.
    CopilotAdoption and ShadowAiDetection auto-default to 30 when omitted.
.PARAMETER AssessmentId
    Required when ReportType is 'Assessment'. The assessment identifier — an opaque
    alphanumeric string (NOT a GUID, e.g. 'l1f8wd29pl44pp1j66r9'). Tab completion
    accepts the friendly name and inserts the ID. Get-InforcerAssessment lists available
    IDs.
.PARAMETER Parameter
    Escape hatch for future API parameters not covered by typed switches. Hashtable; keys
    must match the catalog's accepted parameter keys.
.PARAMETER Collate
    Request a single cross-tenant output for collatable report types. Server silently
    ignores this flag on non-collatable types — this cmdlet errors instead.
.PARAMETER NoWait
    Return immediately after POST with run identifiers. Skip polling and download.
.PARAMETER NoSave
    Poll until terminal but do not download the output bytes. Returns outputs metadata.
.PARAMETER Open
    After each output is saved, launch it with the OS default handler (Invoke-Item).
    Ignored when -NoWait or -NoSave is set (nothing was saved to open). Aliases: -Show, -ShowResult.
.PARAMETER OutputPath
    Directory where downloaded outputs are written. Defaults to the current working directory.
    Created if it doesn't exist.
.PARAMETER TimeoutSeconds
    Maximum total time to wait for any run to become terminal. Default: 600 (10 minutes).
.PARAMETER PollIntervalSeconds
    Initial poll interval. Doubles up to a 15-second cap. Default: 2.
.PARAMETER Format
    Raw (default). Reserved.
.PARAMETER OutputType
    PowerShellObject (default) or JsonObject. Affects pipeline output only; the saved files
    are unchanged.
.EXAMPLE
    Invoke-InforcerReport -ReportType ActiveUserCount -OutputFormat csv -TenantId 482
    Queues, waits, and saves ActiveUserCount.csv to the current directory.
.EXAMPLE
    Invoke-InforcerReport -ReportType TenantAuditReport, ActiveUserCount -OutputFormat pdf, csv -TenantId 482
    Pairs by index: TenantAuditReport→pdf, ActiveUserCount→csv.
.EXAMPLE
    Invoke-InforcerReport -ReportType CopilotAdoption -OutputFormat csv -TenantId 482, 139 -NoWait
    Submits and returns immediately with the RunIds.
.EXAMPLE
    Invoke-InforcerReport -ReportType Assessment -AssessmentId l1f8wd29pl44pp1j66r9 -OutputFormat pdf -TenantId 482
    Runs a specific assessment as a report.
.EXAMPLE
    Get-InforcerReportType -Tag Security | Invoke-InforcerReport -OutputFormat csv -TenantId 482
    Pipeline-discover-then-run: each catalog entry's 'Key' alias binds to -ReportType
    via ValueFromPipelineByPropertyName, so every Security-tagged type is queued in
    one call.
.EXAMPLE
    Invoke-InforcerReport -Key TenantAuditReport -OutputFormat html -TenantId 482 -Open
    Runs the report, saves it, and immediately opens the HTML in the default browser.
.EXAMPLE
    Invoke-InforcerReport -ReportType ActiveUserCount -OutputFormat csv -TenantId 482 -OutputType JsonObject
    Returns the run result as a JSON string (depth 100) instead of objects.

.OUTPUTS
    PSObject or String. The shape depends on the mode:
      -NoWait        → one object per run with { RunId, Status='queued', TenantId, ReportType, ... }
      -NoSave        → one object per output with { RunId, OutputId, FileName, FileSize, ... }
      default        → one object per saved output with { RunId, OutputId, FilePath, FileName, ... }
.LINK
    https://github.com/royklo/InforcerCommunity/blob/main/docs/CMDLET-REFERENCE.md#invoke-inforcerreport
.LINK
    Get-InforcerReportType
.LINK
    Get-InforcerReportRun
.LINK
    Save-InforcerReportOutput
#>
function Invoke-InforcerReport {
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
[OutputType([PSObject], [string])]
param(
    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true, Position = 0)]
    [ArgumentCompleter({
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        # ArgumentCompleter scriptblocks run in the *caller's* session state, NOT the module's,
        # so $script:* is invisible from here — bounce through the module to read both the live
        # catalog cache and the canonical static-key fallback.
        $module = Get-Module InforcerCommunity
        $candidates = if ($module) {
            & $module {
                if ($script:InforcerReportTypeCache) {
                    $tmp = [System.Collections.Generic.List[string]]::new()
                    foreach ($entry in $script:InforcerReportTypeCache) {
                        if ($entry -isnot [PSObject]) { continue }
                        $keyProp = $entry.PSObject.Properties['key']
                        if (-not $keyProp) { continue }
                        $v = $keyProp.Value -as [string]
                        if ($v) { [void]$tmp.Add($v) }
                    }
                    if ($tmp.Count -eq 0) { ,$script:InforcerReportTypeStaticKeys } else { ,$tmp.ToArray() }
                } else {
                    ,$script:InforcerReportTypeStaticKeys
                }
            }
        } else { @() }
        $matched = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($c in $candidates) { if ($c -like "$wordToComplete*") { [void]$matched.Add($c) } }
        foreach ($c in $matched) {
            [System.Management.Automation.CompletionResult]::new($c, $c, 'ParameterValue', $c)
        }
    })]
    [Alias('Key')]
    [string[]]$ReportType,

    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [ArgumentCompleter({
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        # Bounce through the module so $script:InforcerReportTypeCache is visible (completers
        # otherwise run in the caller's session state where module $script: vars are invisible).
        $boundReport = @($fakeBoundParameters['ReportType'])
        $module = Get-Module InforcerCommunity
        $formats = [System.Collections.Generic.List[string]]::new()
        if ($module -and $boundReport.Count -gt 0) {
            $collected = & $module {
                param($bound)
                $out = [System.Collections.Generic.List[string]]::new()
                if (-not $script:InforcerReportTypeCache) { return ,$out.ToArray() }
                foreach ($rt in $bound) {
                    $rtStr = $rt -as [string]
                    $entry = $null
                    foreach ($e in $script:InforcerReportTypeCache) {
                        if ($null -eq $e -or $e -isnot [PSObject]) { continue }
                        $keyProp = $e.PSObject.Properties['key']
                        if ($keyProp -and (($keyProp.Value -as [string]) -ieq $rtStr)) { $entry = $e; break }
                    }
                    if ($entry) {
                        foreach ($p in 'supportedOutputFormats','outputFormats','supportedFormats','formats') {
                            if ($entry.PSObject.Properties[$p]) {
                                foreach ($f in @($entry.PSObject.Properties[$p].Value)) {
                                    $fStr = $f -as [string]
                                    if ($fStr) { [void]$out.Add($fStr) }
                                }
                                break
                            }
                        }
                    }
                }
                ,$out.ToArray()
            } $boundReport
            foreach ($f in $collected) { [void]$formats.Add($f) }
        }
        if ($formats.Count -eq 0) { $formats = [System.Collections.Generic.List[string]]@('csv','json','html','pdf','xlsx') }
        $matched = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($f in $formats) { if ($f -like "$wordToComplete*") { [void]$matched.Add($f) } }
        foreach ($f in $matched) {
            [System.Management.Automation.CompletionResult]::new($f, $f, 'ParameterValue', $f)
        }
    })]
    [string[]]$OutputFormat,

    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [Alias('ClientTenantId')]
    [object[]]$TenantId,

    [Parameter(Mandatory = $false)]
    [ArgumentCompleter({
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        $boundReport = @($fakeBoundParameters['ReportType'])
        $values = if ($boundReport -contains 'CopilotAdoption') { 7, 30, 90 }
                  elseif ($boundReport -contains 'ShadowAiDetection') { 30, 90 }
                  else { @() }
        $values | Where-Object { "$_" -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new("$_", "$_", 'ParameterValue', "$_")
        }
    })]
    [ValidateRange(1, 365)]
    [int]$ReportPeriod,

    [Parameter(Mandatory = $false)]
    [ArgumentCompleter({
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)

        # If the user has explicitly typed -ReportType <something other than Assessment>,
        # the completer is irrelevant — return empty.
        $bound = @($fakeBoundParameters['ReportType'])
        if ($bound.Count -gt 0) {
            $hasAssessment = $false
            foreach ($t in $bound) {
                if (($t -as [string]) -ieq 'Assessment') { $hasAssessment = $true; break }
            }
            if (-not $hasAssessment) { return @() }
        }

        $module = Get-Module InforcerCommunity
        if (-not $module) {
            return @(
                [System.Management.Automation.CompletionResult]::new(
                    "''", '<InforcerCommunity not imported>', 'ParameterValue',
                    'Run Import-Module InforcerCommunity first.'
                )
            )
        }

        # Snapshot session + cache + denial sentinel inside module scope.
        $state = & $module {
            [PSCustomObject]@{
                Connected = [bool]($script:InforcerSession -and $script:InforcerSession.ApiKey -and $script:InforcerSession.BaseUrl)
                Cache     = $script:InforcerAssessmentCache
                Denied    = $script:InforcerAssessmentCacheDeniedAt
                BaseUrl   = if ($script:InforcerSession) { $script:InforcerSession.BaseUrl } else { $null }
                ApiKey    = if ($script:InforcerSession) { $script:InforcerSession.ApiKey } else { $null }
            }
        }

        if (-not $state.Connected) {
            return @(
                [System.Management.Automation.CompletionResult]::new(
                    "''", '<Run Connect-Inforcer first>', 'ParameterValue',
                    'No active Inforcer session. Run Connect-Inforcer to enable assessment ID completion.'
                )
            )
        }

        if ($state.Denied) {
            return @(
                [System.Management.Automation.CompletionResult]::new(
                    "''", '<Assessments.Read API scope required>', 'ParameterValue',
                    'The current API key lacks the Assessments.Read scope. Re-key with sufficient scope, then re-run Connect-Inforcer.'
                )
            )
        }

        # Build completion results from a cached list, falling back to a lazy fetch.
        $items = $state.Cache
        if (-not $items) {
            # Lazy fetch with a tight 2-second budget so TAB never hangs.
            try {
                $secure = $state.ApiKey
                $bstr   = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
                try   { $apiKeyPlain = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
                finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }

                $uri = $state.BaseUrl + '/beta/assessments'
                $hdr = @{ 'Inf-Api-Key' = $apiKeyPlain; 'Accept' = 'application/json' }
                $resp = Invoke-RestMethod -Uri $uri -Method GET -Headers $hdr -TimeoutSec 2 -ErrorAction Stop
                $items = @($resp.data)
                & $module ([scriptblock]::Create('$script:InforcerAssessmentCache = $args[0]')) $items
            } catch {
                # 401 (APIM gateway) or 403 → cache denial so subsequent TABs are instant.
                $sc = 0
                if ($_.Exception.Response) {
                    # Intentional empty catch — best-effort status-code extraction inside a TAB
                    # completer must never throw. Falling back to $sc=0 → "not 401/403" branch.
                    try { $sc = [int]$_.Exception.Response.StatusCode } catch { $null }
                }
                if ($sc -eq 401 -or $sc -eq 403) {
                    & $module { $script:InforcerAssessmentCacheDeniedAt = Get-Date }
                    return @(
                        [System.Management.Automation.CompletionResult]::new(
                            "''", '<Assessments.Read API scope required>', 'ParameterValue',
                            'The current API key lacks the Assessments.Read scope (or APIM rejected the subscription).'
                        )
                    )
                }
                # Transient: empty completion, no caching, retry on next TAB.
                return @()
            }
        }

        # Filter + shape results: GUID as CompletionText, friendly name as ListItemText.
        $needle = $wordToComplete
        if (-not $needle) { $needle = '' }
        $filtered = foreach ($a in @($items)) {
            # Skip null entries and non-PSObject items defensively — PowerShell silently swallows
            # any exception from a completer scriptblock, which would manifest as "TAB does nothing".
            if ($null -eq $a -or $a -isnot [PSObject]) { continue }
            $idVal   = $a.PSObject.Properties['Id']
            if (-not $idVal)   { $idVal   = $a.PSObject.Properties['id'] }
            $nameVal = $a.PSObject.Properties['Name']
            if (-not $nameVal) { $nameVal = $a.PSObject.Properties['name'] }
            $id   = if ($idVal)   { $idVal.Value -as [string] }   else { $null }
            $name = if ($nameVal) { $nameVal.Value -as [string] } else { $null }
            if (-not $id) { continue }
            # Match either ID prefix or substring on name (case-insensitive).
            if ($id -like "${needle}*" -or ($name -and $name -like "*${needle}*")) {
                $listItem = if ($name) { $name } else { $id }
                $tooltip  = if ($name) { "$name — $id" } else { $id }
                [System.Management.Automation.CompletionResult]::new($id, $listItem, 'ParameterValue', $tooltip)
            }
        }
        @($filtered)
    })]
    [string]$AssessmentId,

    [Parameter(Mandatory = $false)]
    [hashtable]$Parameter,

    [Parameter(Mandatory = $false)]
    [switch]$Collate,

    [Parameter(Mandatory = $false)]
    [switch]$NoWait,

    [Parameter(Mandatory = $false)]
    [switch]$NoSave,

    [Parameter(Mandatory = $false)]
    [Alias('Show', 'ShowResult')]
    [switch]$Open,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = $PWD.Path,

    [Parameter(Mandatory = $false)]
    [ValidateRange(10, 3600)]
    [int]$TimeoutSeconds = 600,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 60)]
    [int]$PollIntervalSeconds = 2,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Raw')]
    [string]$Format = 'Raw',

    [Parameter(Mandatory = $false)]
    [ValidateSet('PowerShellObject', 'JsonObject')]
    [string]$OutputType = 'PowerShellObject'
)

begin {
    # Accumulators for pipeline-bound inputs. When the cmdlet is called with arrays directly
    # (no pipe), process{} fires once and we use the bound values as-is. When called via
    # Get-InforcerReportType | Invoke-InforcerReport, each piped object brings one ReportType
    # (alias 'Key' from the catalog entry) — we collect them here and process the whole batch
    # in end{}.
    #
    # Locals (NOT $script:*) — these persist across begin/process/end of the same invocation
    # and stay isolated between concurrent calls in the same runspace.
    $pipedTypes   = [System.Collections.Generic.List[string]]::new()
    $pipedFormats = [System.Collections.Generic.List[string]]::new()
    $pipedTenants = [System.Collections.Generic.List[object]]::new()
    $fromPipeline = $false
}

process {
    # Only accumulate when actually piped (avoids duplicate collection when invoked directly).
    if ($PSCmdlet.MyInvocation.ExpectingInput) {
        $fromPipeline = $true
        foreach ($v in $ReportType)   { if (-not [string]::IsNullOrWhiteSpace(($v -as [string]))) { [void]$pipedTypes.Add(($v -as [string])) } }
        foreach ($v in $OutputFormat) { if (-not [string]::IsNullOrWhiteSpace(($v -as [string]))) { [void]$pipedFormats.Add(($v -as [string])) } }
        foreach ($v in $TenantId)     { [void]$pipedTenants.Add($v) }
    }
}

end {

# Replay accumulated piped values into the same parameter vars the body uses.
if ($fromPipeline) {
    $ReportType   = $pipedTypes.ToArray()
    $OutputFormat = $pipedFormats.ToArray()
    if ($pipedTenants.Count -gt 0) {
        $TenantId = $pipedTenants.ToArray()
    }
    # If every piped item carried the same OutputFormat / TenantId (the common case), collapse
    # to a single value so the zip/broadcast logic below treats it as a 1→N broadcast instead
    # of an N→N pairing.
    $uniqueFormats = $OutputFormat | Sort-Object -Unique
    if ($uniqueFormats.Count -eq 1) { $OutputFormat = @($uniqueFormats) }
    $uniqueTenants = $TenantId | ForEach-Object { $_ -as [string] } | Sort-Object -Unique
    if ($uniqueTenants.Count -eq 1) {
        $TenantId = @($TenantId[0])
    } elseif ($uniqueTenants.Count -gt 1) {
        # User piped different tenants per row — semantics here are cross-product, not row-wise
        # pairing (PowerShell pipeline binding for array params can't express row-wise across
        # multiple parameters cleanly). Warn so they know they're getting every type × every tenant.
        Write-Warning ("Piped {0} different tenant IDs alongside {1} report types — every report will be queued against every tenant (cross-product). To target specific (type, tenant) pairs, call Invoke-InforcerReport separately for each pairing or use a ForEach-Object loop." -f $uniqueTenants.Count, $pipedTypes.Count)
    }
}

if (-not (Test-InforcerSession)) {
    Write-Error -Message 'Not connected yet. Please run Connect-Inforcer first.' `
        -ErrorId 'NotConnected' -Category ConnectionError
    return
}

# Per-invocation progress ID — avoids collision with caller-side bars that may use -Id 1.
# Uses a monotonically-increasing counter (atomic via Interlocked) so concurrent invocations
# in the same runspace are guaranteed unique IDs. Random would have ~12% collision at 50
# concurrent calls. The seed is initialised at module load (InforcerCommunity.psm1) so two
# parallel runspaces don't race on lazy-init. The defensive null-check below covers the case
# where a future refactor accidentally clears the seed mid-runtime.
if ($null -eq $script:InforcerProgressIdSeed) { $script:InforcerProgressIdSeed = 10000 }
$progressId = [System.Threading.Interlocked]::Increment([ref]$script:InforcerProgressIdSeed)

# -Open only makes sense in default sync+save mode — nothing is saved to open when -NoWait
# (returns immediately) or -NoSave (polls but doesn't write files) is also set.
if ($Open.IsPresent -and ($NoWait.IsPresent -or $NoSave.IsPresent)) {
    Write-Warning '-Open is ignored when -NoWait or -NoSave is set (no files are saved to launch).'
}

# --- Validate and zip ReportType / OutputFormat ---
$reportTypes = @($ReportType | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$outputFormats = @($OutputFormat | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

if ($reportTypes.Count -eq 0) {
    Write-Error -Message '-ReportType must contain at least one non-empty value.' `
        -ErrorId 'InvalidReportType' -Category InvalidArgument
    return
}
if ($outputFormats.Count -eq 0) {
    Write-Error -Message '-OutputFormat must contain at least one non-empty value.' `
        -ErrorId 'InvalidOutputFormat' -Category InvalidArgument
    return
}

$pairs = [System.Collections.Generic.List[PSObject]]::new()
if ($outputFormats.Count -eq 1) {
    foreach ($rt in $reportTypes) {
        [void]$pairs.Add([PSCustomObject]@{ ReportType = $rt; OutputFormat = $outputFormats[0] })
    }
} elseif ($outputFormats.Count -eq $reportTypes.Count) {
    if ($reportTypes.Count -eq 1) {
        Write-Error -Message "Cannot pair 1 ReportType with $($outputFormats.Count) OutputFormats. Specify one OutputFormat per ReportType, or repeat the type." `
            -ErrorId 'InvalidPairing' -Category InvalidArgument
        return
    }
    for ($i = 0; $i -lt $reportTypes.Count; $i++) {
        [void]$pairs.Add([PSCustomObject]@{ ReportType = $reportTypes[$i]; OutputFormat = $outputFormats[$i] })
    }
} else {
    Write-Error -Message "Cannot pair $($reportTypes.Count) ReportType(s) with $($outputFormats.Count) OutputFormat(s). Provide 1 format (broadcast) or N formats (paired by index)." `
        -ErrorId 'InvalidPairing' -Category InvalidArgument
    return
}

# --- Resolve every pair through the schema validator ---
$entries = [System.Collections.Generic.List[hashtable]]::new()
$entryKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

foreach ($pair in $pairs) {
    $resolverArgs = @{
        ReportType   = $pair.ReportType
        OutputFormat = $pair.OutputFormat
    }
    if ($PSBoundParameters.ContainsKey('Parameter'))    { $resolverArgs['Parameter']    = $Parameter }
    if ($PSBoundParameters.ContainsKey('ReportPeriod')) { $resolverArgs['ReportPeriod'] = $ReportPeriod }
    if ($PSBoundParameters.ContainsKey('AssessmentId')) { $resolverArgs['AssessmentId'] = $AssessmentId }
    if ($Collate.IsPresent)                             { $resolverArgs['Collate']      = $true }

    try {
        $resolved = Resolve-InforcerReportTypeSchema @resolverArgs
    } catch {
        Write-Error -Message $_.Exception.Message -ErrorId 'SchemaValidationFailed' -Category InvalidArgument
        return
    }

    # Client-side dedup — drop exact (type, outputFormat) duplicates before POST (bug #1).
    $dedupKey = ('{0}|{1}' -f $resolved.TypeKey.ToLowerInvariant(), $resolved.OutputFormat.ToLowerInvariant())
    if (-not $entryKeys.Add($dedupKey)) {
        Write-Verbose "Skipping duplicate ($($resolved.TypeKey), $($resolved.OutputFormat)) — already in batch."
        continue
    }

    [void]$entries.Add([hashtable]$resolved.Entry)
}

if ($entries.Count -eq 0) {
    Write-Error -Message 'No valid report entries to submit.' -ErrorId 'NoEntries' -Category InvalidArgument
    return
}

# --- Resolve tenants ---
# Reject obviously-wrong tenant types up-front. $true, hashtables, and arbitrary objects
# would otherwise stringify to "True" / "System.Collections.Hashtable" and trigger a
# needless /beta/tenants lookup just to fail.
$invalidTenants = @($TenantId | Where-Object {
    $_ -isnot [int] -and $_ -isnot [long] -and $_ -isnot [string] -and $_ -isnot [guid]
})
if ($invalidTenants.Count -gt 0) {
    $badTypes = ($invalidTenants | ForEach-Object { $_.GetType().Name } | Sort-Object -Unique) -join ', '
    Write-Error -Message "Tenant identifiers must be numeric Client Tenant ID, GUID, or tenant name (string). Received unsupported type(s): $badTypes." `
        -ErrorId 'InvalidTenantIdType' -Category InvalidArgument
    return
}

# Fast path: if every -TenantId is already a numeric Client Tenant ID, skip the
# /beta/tenants lookup entirely (it needs Tenants.Read scope which a Reports-only
# key won't have). Only when the user passes a name or GUID do we need the list.
$tenantData = $null
$resolvedTenants = [System.Collections.Generic.List[int]]::new()
[int]$tenantParseTmp = 0
$needsLookup = $false
foreach ($t in $TenantId) {
    if ($t -isnot [int] -and -not [int]::TryParse(($t -as [string]), [ref]$tenantParseTmp)) {
        $needsLookup = $true; break
    }
}
if ($needsLookup) {
    $tenantData = @(Invoke-InforcerApiRequest -Endpoint '/beta/tenants' -Method GET -OutputType PowerShellObject -ErrorVariable tenantListErr -ErrorAction SilentlyContinue)
    if (-not $tenantData -or $tenantData.Count -eq 0) {
        $apiErr = if ($tenantListErr) { $tenantListErr[-1].Exception.Message } else { 'no response' }
        $isAuthFail = ($tenantListErr -and $tenantListErr.FullyQualifiedErrorId -match 'ApiRequestFailed_(401|403)')
        # Only blame the values that actually need a lookup — passing numeric IDs alongside
        # names should not have the user "re-pass numeric IDs" when they already did.
        $unresolvable = @($TenantId | Where-Object { $_ -isnot [int] -and -not [int]::TryParse(($_ -as [string]), [ref]$tenantParseTmp) })
        $numericCount = @($TenantId).Count - $unresolvable.Count
        $unresolvableList = $unresolvable -join "', '"
        $mixedHint = if ($numericCount -gt 0) {
            "$numericCount numeric tenant ID(s) were also provided and would have worked on their own; only the name/GUID inputs need Tenants.Read for resolution."
        } else { '' }
        $hint = if ($isAuthFail) {
            "The API key was rejected when looking up tenant '$unresolvableList' against GET /beta/tenants (this endpoint requires the Tenants.Read scope, which a Reports-only key does not include). Pass the numeric Client Tenant ID for that tenant directly, or re-key with Tenants.Read to enable name / GUID resolution. $mixedHint".Trim()
        } else {
            "Could not retrieve the tenant list to resolve '$unresolvableList'. Underlying error: $apiErr. $mixedHint".Trim()
        }
        Write-Error -Message $hint -ErrorId 'TenantLookupUnavailable' -Category PermissionDenied
        return
    }
}
foreach ($t in $TenantId) {
    try {
        $resolvedId = if ($tenantData) {
            Resolve-InforcerTenantId -TenantId $t -TenantData $tenantData
        } else {
            Resolve-InforcerTenantId -TenantId $t
        }
        if ($null -ne $resolvedId) { [void]$resolvedTenants.Add([int]$resolvedId) }
    } catch {
        Write-Error -Message $_.Exception.Message -ErrorId 'TenantResolutionFailed' -Category InvalidArgument
        return
    }
}

# Reject non-positive IDs and dedupe — duplicates in includeTenants either 400 server-side
# or silently dedupe, both of which produce confusing telemetry. Validate eagerly.
$invalidIds = @($resolvedTenants | Where-Object { $_ -le 0 })
if ($invalidIds.Count -gt 0) {
    Write-Error -Message ("Tenant ID(s) must be positive integers. Got: {0}." -f ($invalidIds -join ', ')) `
        -ErrorId 'InvalidTenantId' -Category InvalidArgument
    return
}
$beforeDedup = $resolvedTenants.Count
$resolvedTenants = [System.Collections.Generic.List[int]]@($resolvedTenants | Sort-Object -Unique)
if ($resolvedTenants.Count -lt $beforeDedup) {
    Write-Verbose ("Removed {0} duplicate tenant ID(s) before POST." -f ($beforeDedup - $resolvedTenants.Count))
}

if ($resolvedTenants.Count -eq 0) {
    Write-Error -Message 'No tenants resolved.' -ErrorId 'NoTenants' -Category InvalidArgument
    return
}

# --- Validate -OutputPath (only when we actually intend to save) ---
$wantSave = -not $NoWait.IsPresent -and -not $NoSave.IsPresent
if ($wantSave) {
    try {
        # Refuse system paths (defense-in-depth against combining server-controlled filenames
        # with attacker-suggested -OutputPath values like /etc or %WINDIR%).
        $null = Test-InforcerSafeOutputPath -Path $OutputPath
        if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
            # Under -WhatIf, New-Item skips creation but doesn't throw — Resolve-Path would then
            # blow up on the missing dir. Only resolve when the path actually exists post-create.
            $null = New-Item -Path $OutputPath -ItemType Directory -Force -ErrorAction Stop
        }
        if (Test-Path -LiteralPath $OutputPath -PathType Container) {
            $OutputPath = (Resolve-Path -LiteralPath $OutputPath).Path
        } elseif (-not $WhatIfPreference) {
            throw "Output directory '$OutputPath' was not created."
        }
    } catch {
        Write-Error -Message "Cannot prepare output directory '$OutputPath': $($_.Exception.Message)" `
            -ErrorId 'OutputPathFailed' -Category InvalidArgument
        return
    }
}

# --- Build POST body ---
$body = @{
    reports = @($entries)
    tenants = @{ includeTenants = @($resolvedTenants) }
}
$bodyJson = $body | ConvertTo-Json -Depth 100

$summary = "Queue $($entries.Count) report(s) across $($resolvedTenants.Count) tenant(s)"
if (-not $PSCmdlet.ShouldProcess($summary, 'POST /beta/reports/runs')) {
    return
}

Write-Verbose "POST /beta/reports/runs with $($entries.Count) report(s), tenants: $($resolvedTenants -join ', ')"

Write-Progress -Id $progressId -Activity 'Invoke-InforcerReport' `
    -Status "Queuing $($entries.Count) report(s) across $($resolvedTenants.Count) tenant(s)..." `
    -PercentComplete 0

$queueResponse = Invoke-InforcerApiRequest -Endpoint '/beta/reports/runs' -Method POST -Body $bodyJson
if ($null -eq $queueResponse) {
    Write-Progress -Id $progressId -Activity 'Invoke-InforcerReport' -Completed
    return
}

# The POST response is an array of run records (one per run created).
$runs = @($queueResponse)

# --- Branch on mode ---
if ($NoWait.IsPresent) {
    # Close out the "Queuing..." progress bar before returning — otherwise it stays orphaned
    # in the host until the next progress write in the runspace.
    Write-Progress -Id $progressId -Activity 'Invoke-InforcerReport' -Completed
    if ($OutputType -eq 'JsonObject') {
        return ($runs | ConvertTo-Json -Depth 100)
    }
    foreach ($run in $runs) {
        if ($run -is [PSObject]) {
            $null = Add-InforcerPropertyAliases -InputObject $run -ObjectType ReportRun
            if ($run.PSObject.TypeNames[0] -ne 'InforcerCommunity.ReportRun') {
                $run.PSObject.TypeNames.Insert(0, 'InforcerCommunity.ReportRun')
            }
        }
    }
    return $runs
}

# --- Sync mode: poll each run, optionally download ---
$results = [System.Collections.Generic.List[PSObject]]::new()
$totalRuns = $runs.Count
$completedRuns = 0

foreach ($run in $runs) {
    # POST response shape is { data: { runId: "<guid>" } } unwrapped by Invoke-InforcerApiRequest;
    # list endpoint also uses runId. Accept either runId or id for forward-compatibility.
    $runIdProp = $run.PSObject.Properties['runId']
    if (-not $runIdProp) { $runIdProp = $run.PSObject.Properties['id'] }
    $runIdValue = if ($runIdProp) { $runIdProp.Value -as [string] } else { $null }
    if (-not $runIdValue) {
        Write-Warning "POST response missing 'runId' on a run record; skipping."
        continue
    }
    $runIdGuid = [guid]::Empty
    if (-not [guid]::TryParse($runIdValue, [ref]$runIdGuid)) {
        Write-Warning "Run id '$runIdValue' is not a valid GUID; skipping."
        continue
    }
    $completedRuns++
    $runProgressPct = [int](($completedRuns - 1) / [Math]::Max($totalRuns, 1) * 100)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $startedAt = Get-Date
    $interval = [Math]::Max($PollIntervalSeconds, 1)
    $outputsObj = $null
    $timedOut = $false
    $pollCount = 0
    while ($true) {
        $pollCount++
        $elapsed = [int]((Get-Date) - $startedAt).TotalSeconds
        # Push a fresh status on every iteration so the user sees the elapsed-time tick.
        Write-Progress -Id $progressId -Activity 'Invoke-InforcerReport' `
            -Status ("Run {0}/{1}: polling {2} (elapsed {3}s, poll #{4})" -f $completedRuns, $totalRuns, $runIdValue, $elapsed, $pollCount) `
            -PercentComplete $runProgressPct

        try {
            $probe = Test-InforcerReportRunTerminal -RunId $runIdGuid -ErrorAction Stop
        } catch {
            Write-Progress -Id $progressId -Activity 'Invoke-InforcerReport' -Completed
            Write-Error -Message "Polling failed for run ${runIdValue}: $($_.Exception.Message)" `
                -ErrorId 'PollFailed' -Category ConnectionError
            return
        }
        if ($probe.IsTerminal) {
            $outputsObj = $probe.Outputs
            break
        }
        if ((Get-Date) -ge $deadline) { $timedOut = $true; break }
        Start-Sleep -Seconds $interval
        $interval = [Math]::Min($interval * 2, 15)
    }

    if ($timedOut) {
        Write-Error -Message "Timed out waiting for run $runIdValue to complete (waited $TimeoutSeconds s). Use Get-InforcerReportRun -RunId $runIdValue to check status." `
            -ErrorId 'PollTimeout' -Category OperationStopped
        continue
    }

    # The outputs response shape (confirmed against api-uk.inforcer.com):
    #   { data: { outputs: [ { id, reportType, tenantId, format, sizeBytes }, ... ] } }
    # Test-InforcerReportRunTerminal unwraps to the inner outputs array.
    $outputs = @($outputsObj)

    if ($outputs.Count -eq 0) {
        Write-Warning "Run $runIdValue is terminal but returned no outputs. Either the report produced no data, or no outputs are within this API key's tenant scope (collated outputs require the key to cover every tenant the run targeted)."
    } elseif ($outputs.Count -lt $entries.Count -and $totalRuns -eq 1) {
        Write-Warning "Run $runIdValue produced $($outputs.Count) output(s) but $($entries.Count) report(s) were requested."
    }

    $outputIndex = 0
    $outputTotal = $outputs.Count
    foreach ($out in $outputs) {
        if ($out -isnot [PSObject]) { continue }
        $outId = $out.PSObject.Properties['id'].Value -as [string]
        if (-not $outId) {
            Write-Warning "Output record missing 'id' on run $runIdValue; skipping."
            continue
        }
        $outputIndex++

        if ($NoSave.IsPresent) {
            # Inject the camelCase 'runId' before aliasing so the 'RunId' PSAliasProperty (added
            # by Add-InforcerPropertyAliases for ObjectType=ReportOutput) resolves to it. Setting
            # the underlying field rather than a separate NoteProperty keeps camel and Pascal in
            # lockstep, matching the alias contract every other cmdlet follows.
            if (-not $out.PSObject.Properties['runId']) {
                $out | Add-Member -NotePropertyName 'runId' -NotePropertyValue $runIdValue -Force
            }
            $null = Add-InforcerPropertyAliases -InputObject $out -ObjectType ReportOutput
            if ($out.PSObject.TypeNames[0] -ne 'InforcerCommunity.ReportOutput') {
                $out.PSObject.TypeNames.Insert(0, 'InforcerCommunity.ReportOutput')
            }
            [void]$results.Add($out)
            continue
        }

        # Surface what's about to be downloaded as the progress status — file name
        # isn't known yet (it comes from Content-Disposition), so use output id + type.
        $outReportType = $out.PSObject.Properties['reportType']
        $outFormat     = $out.PSObject.Properties['format']
        $outLabel      = if ($outReportType -and $outFormat) {
            "{0}.{1}" -f ($outReportType.Value -as [string]), ($outFormat.Value -as [string])
        } else { $outId }
        Write-Progress -Id $progressId -Activity 'Invoke-InforcerReport' `
            -Status ("Run {0}/{1}: downloading output {2}/{3} ({4})" -f $completedRuns, $totalRuns, $outputIndex, $outputTotal, $outLabel) `
            -PercentComplete $runProgressPct

        # Download and save. Output record shape (confirmed):
        #   { id, reportType, tenantId, format, sizeBytes }
        # No server-side fileName — the Content-Disposition header is the source of truth.
        # Streams to disk via -DestinationDirectory so large outputs don't load into memory.
        $downloadEndpoint = "/beta/reports/runs/$runIdValue/outputs/$outId"
        $defaultName = ('{0}-{1}' -f $runIdValue, $outId)
        try {
            $download = Invoke-InforcerRawDownload -Endpoint $downloadEndpoint -DefaultFileName $defaultName `
                -DestinationDirectory $OutputPath -ErrorAction Stop
        } catch {
            Write-Error -Message "Failed to download output $outId for run ${runIdValue}: $($_.Exception.Message)" `
                -ErrorId 'DownloadFailed' -Category ReadError
            continue
        }
        if ($null -eq $download) { continue }

        $filePath = $download.FilePath
        $fileSize = if ($download.PSObject.Properties['FileSize']) { $download.FileSize } else { (Get-Item -LiteralPath $filePath -ErrorAction SilentlyContinue).Length }

        $tenantIdValue = $out.PSObject.Properties['tenantId']
        $reportTypeValue = $out.PSObject.Properties['reportType']
        $formatValue = $out.PSObject.Properties['format']

        # Collated cross-tenant outputs report tenantId as 0, null, or an absent field
        # (server behavior is inconsistent — see Reports-API-Feedback.md §16). When -Collate
        # was requested on the run, OR the record has no positive tenantId, surface 'Collated'
        # as a sentinel so it doesn't collide with the integer tenant-ID space.
        $rawTenantId = $null
        if ($tenantIdValue -and $null -ne $tenantIdValue.Value) {
            $rawTenantId = $tenantIdValue.Value -as [int]
        }
        $tenantOut = if ($Collate.IsPresent -or $null -eq $rawTenantId -or $rawTenantId -le 0) {
            'Collated'
        } else {
            $rawTenantId
        }

        $result = [PSCustomObject][ordered]@{
            RunId         = $runIdValue
            OutputId      = $outId
            TenantId      = $tenantOut
            ReportType    = if ($reportTypeValue) { $reportTypeValue.Value -as [string] } else { $null }
            OutputFormat  = if ($formatValue) { $formatValue.Value -as [string] } else { $null }
            FileName      = $download.FileName
            FilePath      = $filePath
            FileSize      = $fileSize
            ContentType   = $download.ContentType
            CorrelationId = $download.CorrelationId
        }
        $result.PSObject.TypeNames.Insert(0, 'InforcerCommunity.ReportRunResult')
        [void]$results.Add($result)
    }
}

Write-Progress -Id $progressId -Activity 'Invoke-InforcerReport' -Completed

# -Open: launch saved files with the OS default handler. Done AFTER the loop so we can
# decide between launching each file (small N) and opening the parent directory (large N).
# Failure to launch is non-fatal — the files are already saved.
if ($Open.IsPresent -and $results.Count -gt 0) {
    # SECURITY: only auto-launch files with extensions on the allowlist. The Reports API
    # legitimately returns CSV/JSON/HTML/PDF/XLSX/XML/TXT/ZIP; anything else (.command,
    # .app, .lnk, .desktop, .url, .scpt, .sh, .bat, .exe, .vbs, .ps1, .jar, .terminal,
    # .workflow, …) could let a compromised or malicious upstream auto-execute attacker
    # code via the OS file-type association. For non-allowlisted files, open the directory
    # instead so the user can choose what to do with them.
    $openAllowlist = @('.csv','.json','.html','.htm','.pdf','.xlsx','.xls','.xml','.txt','.zip','.md','.tsv')
    $openMax = 5
    $unsafe = @($results | Where-Object {
        $ext = ([System.IO.Path]::GetExtension($_.FilePath) -as [string]).ToLowerInvariant()
        $ext -notin $openAllowlist
    })
    if ($unsafe.Count -gt 0) {
        $unsafeExts = ($unsafe | ForEach-Object { [System.IO.Path]::GetExtension($_.FilePath) } | Sort-Object -Unique) -join ', '
        Write-Warning ("Skipping auto-launch for {0} file(s) with non-allowlisted extension(s) ({1}). Opening the output directory instead — review the files before launching them yourself." -f $unsafe.Count, $unsafeExts)
        try {
            Invoke-Item -LiteralPath $OutputPath -ErrorAction Stop
            Write-Verbose "Opened directory '$OutputPath' with the default handler."
        } catch {
            Write-Warning "Could not open '$OutputPath': $($_.Exception.Message)"
        }
    } elseif ($results.Count -gt $openMax) {
        Write-Warning ("Saved {0} files; opening the output directory instead of every file (-Open caps at {1} simultaneous launches)." -f $results.Count, $openMax)
        try {
            Invoke-Item -LiteralPath $OutputPath -ErrorAction Stop
            Write-Verbose "Opened directory '$OutputPath' with the default handler."
        } catch {
            Write-Warning "Could not open '$OutputPath': $($_.Exception.Message)"
        }
    } else {
        foreach ($r in $results) {
            try {
                Invoke-Item -LiteralPath $r.FilePath -ErrorAction Stop
                Write-Verbose "Opened '$($r.FilePath)' with the default handler."
            } catch {
                Write-Warning "Could not open '$($r.FilePath)': $($_.Exception.Message)"
            }
        }
    }
}

if ($OutputType -eq 'JsonObject') {
    return (,@($results) | ConvertTo-Json -Depth 100)
}
$results

} # end of end{} block
}
