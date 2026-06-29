<#
.SYNOPSIS
    Lists report runs from the Inforcer Reports API, with optional polling and outputs embedding.

    Required API scope(s): Reports.Read
.DESCRIPTION
    GET /beta/reports/runs returns the most recent runs (server-side cap: 500 items, 7-day window;
    query parameters are silently ignored at the time of writing — filter client-side).

    Two known characteristics worth calling out before relying on this endpoint:

      * Propagation lag: a newly-queued run does not appear in the list response for ~4 minutes.
        For freshly-queued work, use Invoke-InforcerReport (which polls the outputs endpoint
        directly) rather than -RunId here.
      * No filter support: server ignores ?status=, ?since=, ?limit=, etc. Filtering happens
        in this cmdlet.

    Polling and outputs embedding are opt-in: -Wait polls the outputs endpoint (which 404s
    until terminal, then 200s — bypasses the list-endpoint lag); -IncludeOutputs fetches
    /runs/{id}/outputs once per returned run and attaches the outputs array.
.PARAMETER RunId
    Filter to a single run by GUID. Combined with -Wait, polls that run until terminal.
.PARAMETER Wait
    Poll runs via GET /runs/{id}/outputs until terminal (200) or -TimeoutSeconds elapses.
    Requires -RunId.
.PARAMETER IncludeOutputs
    For each returned run, fetch GET /runs/{id}/outputs and embed the array on .outputs. Adds
    one API call per run; use sparingly on large result sets.
.PARAMETER TimeoutSeconds
    Maximum total wait when -Wait is used. Default: 600.
.PARAMETER PollIntervalSeconds
    Initial poll interval (doubles up to a 15-second cap). Default: 2.
.PARAMETER Format
    Raw (default). Reserved.
.PARAMETER OutputType
    PowerShellObject (default) or JsonObject. JSON uses Depth 100.
.EXAMPLE
    Get-InforcerReportRun
    Lists every visible run (up to 500, last 7 days).
.EXAMPLE
    Get-InforcerReportRun -RunId 094a49ed-b9b8-492b-870f-0f76fd3b2954
    Returns metadata for a single run (subject to the list-endpoint propagation lag).
.EXAMPLE
    Get-InforcerReportRun -RunId 094a49ed-b9b8-492b-870f-0f76fd3b2954 -Wait
    Polls the run until terminal and returns its metadata with outputs embedded.
.EXAMPLE
    Get-InforcerReportRun -IncludeOutputs
    Returns every run with its outputs array embedded (1 extra API call per run).
.OUTPUTS
    PSObject or String
.LINK
    https://github.com/royklo/InforcerCommunity/blob/main/docs/CMDLET-REFERENCE.md#get-inforcerreportrun
.LINK
    Invoke-InforcerReport
.LINK
    Save-InforcerReportOutput
#>
function Get-InforcerReportRun {
[CmdletBinding()]
[OutputType([PSObject], [string])]
param(
    [Parameter(Mandatory = $false, Position = 0, ValueFromPipelineByPropertyName = $true)]
    [Alias('Id')]
    [guid]$RunId,

    [Parameter(Mandatory = $false)]
    [switch]$Wait,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeOutputs,

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
    $sessionOk = Test-InforcerSession
    if (-not $sessionOk) {
        Write-Error -Message 'Not connected yet. Please run Connect-Inforcer first.' `
            -ErrorId 'NotConnected' -Category ConnectionError
    }
    # Cache the list-endpoint response across process{} iterations so piping N RunIds is
    # one GET, not N GETs. Per-invocation local — not $script:* — so concurrent invocations
    # don't share state.
    $cachedListResponse = $null
    $listResponseFetched = $false
    $polledOutputsByRunId = @{}
}

process {
    if (-not $sessionOk) { return }

if ($Wait.IsPresent -and -not $PSBoundParameters.ContainsKey('RunId')) {
    Write-Error -Message '-Wait requires -RunId. Use Invoke-InforcerReport for batch polling.' `
        -ErrorId 'WaitRequiresRunId' -Category InvalidArgument
    return
}

# --- Optional polling stage (uses outputs endpoint to bypass list-endpoint lag) ---
$polledOutputs = $null
if ($Wait.IsPresent) {
    Write-Verbose "Polling run $RunId until terminal (timeout: ${TimeoutSeconds}s)..."
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $interval = [Math]::Max($PollIntervalSeconds, 1)
    while ($true) {
        try {
            $probe = Test-InforcerReportRunTerminal -RunId $RunId -ErrorAction Stop
        } catch {
            Write-Error -Message $_.Exception.Message -ErrorId 'PollFailed' -Category ConnectionError
            return
        }
        if ($probe.IsTerminal) {
            $polledOutputs = $probe.Outputs
            $polledOutputsByRunId[$RunId.ToString()] = $polledOutputs
            break
        }
        if ((Get-Date) -ge $deadline) {
            Write-Error -Message "Timed out waiting for run $RunId to complete (waited ${TimeoutSeconds}s)." `
                -ErrorId 'PollTimeout' -Category OperationStopped
            return
        }
        Start-Sleep -Seconds $interval
        $interval = [Math]::Min($interval * 2, 15)
    }
}

# --- Fetch list once, reuse for every piped RunId ---
if (-not $listResponseFetched) {
    Write-Verbose 'GET /beta/reports/runs'
    $cachedListResponse = Invoke-InforcerApiRequest -Endpoint '/beta/reports/runs' -Method GET -OutputType PowerShellObject
    $listResponseFetched = $true
}
$response = $cachedListResponse
if ($null -eq $response) { return }

$runs = @($response)

if ($PSBoundParameters.ContainsKey('RunId')) {
    $needle = $RunId.ToString()
    # API uses 'runId' on list records; older code paths used 'id' — match either. Single pass.
    $matched = [System.Collections.Generic.List[object]]::new()
    foreach ($r in $runs) {
        $runIdProp = $r.PSObject.Properties['runId']
        if ($runIdProp -and (($runIdProp.Value -as [string]) -ieq $needle)) { [void]$matched.Add($r); continue }
        $idProp = $r.PSObject.Properties['id']
        if ($idProp -and (($idProp.Value -as [string]) -ieq $needle)) { [void]$matched.Add($r) }
    }
    $runs = $matched.ToArray()
    if ($runs.Count -eq 0) {
        if ($polledOutputs) {
            # Polling confirmed the run is terminal, but the list endpoint hasn't caught up.
            Write-Warning "Run $RunId is terminal but not yet visible in GET /reports/runs (4-minute propagation lag). Returning a synthesized record with outputs embedded."
            $runs = @([PSCustomObject]@{
                runId   = $needle
                status  = 'completed'
                outputs = @($polledOutputs)
            })
        } elseif ($IncludeOutputs.IsPresent) {
            # -IncludeOutputs without -Wait: try a one-shot outputs probe to bypass the list-endpoint lag.
            try {
                $probe = Test-InforcerReportRunTerminal -RunId $RunId -ErrorAction Stop
            } catch {
                Write-Warning "Run $RunId not found in GET /reports/runs and outputs probe failed: $($_.Exception.Message)"
                return
            }
            if ($probe.IsTerminal) {
                Write-Warning "Run $RunId is terminal but not yet visible in GET /reports/runs (4-minute propagation lag). Returning a synthesized record with outputs embedded."
                $runs = @([PSCustomObject]@{
                    runId   = $needle
                    status  = 'completed'
                    outputs = @($probe.Outputs)
                })
            } else {
                Write-Warning "Run $RunId is not yet terminal and not in GET /reports/runs. Try -Wait, or retry once the run completes."
                return
            }
        } else {
            Write-Warning "Run $RunId not found in GET /reports/runs. The list endpoint has a ~4-minute propagation lag; for fresh runs, pass -IncludeOutputs (or -Wait) to bypass via the outputs endpoint."
            return
        }
    } elseif ($polledOutputs) {
        # Attach polled outputs to the (single) matching run.
        foreach ($r in $runs) {
            if (-not $r.PSObject.Properties['outputs']) {
                $r | Add-Member -NotePropertyName 'outputs' -NotePropertyValue @($polledOutputs) -Force
            }
        }
    }
}

# --- Optionally embed outputs for every returned run ---
if ($IncludeOutputs.IsPresent -and -not $polledOutputs) {
    foreach ($r in $runs) {
        $idProp = $r.PSObject.Properties['runId']
        if (-not $idProp) { $idProp = $r.PSObject.Properties['id'] }
        $idValue = if ($idProp) { $idProp.Value -as [string] } else { $null }
        $idGuid = [guid]::Empty
        if (-not [guid]::TryParse($idValue, [ref]$idGuid)) {
            Write-Warning "Run record missing valid runId; cannot embed outputs."
            continue
        }
        # Skip if outputs are already attached (e.g. from synthesized lag-fallback record).
        $existing = $r.PSObject.Properties['outputs']
        if ($existing -and $existing.Value) { continue }
        try {
            $probe = Test-InforcerReportRunTerminal -RunId $idGuid -ErrorAction Stop
            if ($probe.IsTerminal) {
                if (-not $r.PSObject.Properties['outputs']) {
                    $r | Add-Member -NotePropertyName 'outputs' -NotePropertyValue @($probe.Outputs) -Force
                } else {
                    $r.PSObject.Properties['outputs'].Value = @($probe.Outputs)
                }
            } else {
                Write-Verbose "Run $idValue is not yet terminal; skipping outputs embedding."
            }
        } catch {
            Write-Warning "Failed to fetch outputs for run ${idValue}: $($_.Exception.Message)"
        }
    }
}

# --- Shape output ---
if ($OutputType -eq 'JsonObject') {
    return ($runs | ConvertTo-Json -Depth 100)
}

foreach ($r in $runs) {
    if ($r -is [PSObject]) {
        $null = Add-InforcerPropertyAliases -InputObject $r -ObjectType ReportRun
        if ($r.PSObject.TypeNames[0] -ne 'InforcerCommunity.ReportRun') {
            $r.PSObject.TypeNames.Insert(0, 'InforcerCommunity.ReportRun')
        }
    }
}
$runs

} # end of process{} block
}
