<#
.SYNOPSIS
    Downloads a report output to disk.

    Required API scope(s): Reports.Read (API key); Reports permission (API client, unconfirmed).
.DESCRIPTION
    GET /reports/runs/{runId}/outputs/{outputId} (legacy API for an API-key login, v1 API for a
    client ID and secret login) returns the raw bytes plus a
    Content-Disposition filename. This cmdlet writes those bytes to -OutputPath using the
    server-suggested filename (sanitized) and emits a result object per saved file.

    The server's name is reduced to a plain file name (a leading dot becomes '_', so '.csv' is
    saved as '_.csv'), an existing file is never overwritten, and on Windows saved files are marked
    as downloaded from the internet. A redirect fails instead of being followed, and a throttled
    (429) download is not retried.

    Pipeline-friendly: pipe output records from Invoke-InforcerReport -NoSave or
    Get-InforcerReportRun -IncludeOutputs and every output is downloaded.
.PARAMETER RunId
    The run identifier (GUID). Pipeline-bindable by property name.
.PARAMETER OutputId
    The output identifier (string) — the id field on each output record. Pipeline-bindable
    by property name (also accepts -Id as an alias).
.PARAMETER ReportType
    Pipeline-bindable. When piped from Invoke-InforcerReport -NoSave or Get-InforcerReportRun
    -IncludeOutputs, this is auto-populated from the upstream record and surfaced on the
    result object so output formatting matches Invoke-InforcerReport. Otherwise $null.
.PARAMETER OutputFormat
    Pipeline-bindable. Same as ReportType — propagated from the upstream record when piped.
.PARAMETER TenantId
    Pipeline-bindable. Same as ReportType — propagated from the upstream record when piped.
    API key: numeric Client Tenant ID; client ID and secret: Microsoft tenant ID (GUID). Collated
    outputs carry no tenant ($null). Aliases: -ClientTenantId, -MsTenantId.
.PARAMETER OutputPath
    Directory where downloaded outputs are written. Defaults to the current working directory.
    Created if it doesn't exist. Existing files are never overwritten: when the name is taken,
    the output is saved as 'name (1).ext', 'name (2).ext', and so on.
.PARAMETER FileName
    Override the server-suggested filename. Sanitized for cross-platform safety. The file is
    written under this name directly; the server's name is not used at all. An existing file of
    this name is kept and the output is saved as 'name (1).ext'.
.PARAMETER OutputType
    PowerShellObject (default) or JsonObject.
.EXAMPLE
    Save-InforcerReportOutput -RunId 00000000-0000-0000-0000-000000000009 -OutputId out-1
    Saves a single output to the current directory.
.EXAMPLE
    Invoke-InforcerReport -ReportType ActiveUserCount -OutputFormat csv -TenantId 'Contoso' -NoSave |
        Save-InforcerReportOutput -OutputPath ./reports
    Queues + polls a report without saving, then downloads every output to ./reports.
.EXAMPLE
    Get-InforcerReportRun -IncludeOutputs |
        ForEach-Object { $_.outputs } |
        Save-InforcerReportOutput -OutputPath ./bulk
    Bulk-downloads every output from every visible run.
.EXAMPLE
    Save-InforcerReportOutput -RunId 00000000-0000-0000-0000-000000000009 -OutputId out-1 -OutputPath ./out -OutputType JsonObject
    Returns the saved-file result as a JSON string (depth 100) instead of objects.

.OUTPUTS
    PSObject or String — per saved file, with { RunId, OutputId, TenantId, ReportType,
    OutputFormat, FilePath, FileName, FileSize, ContentType, CorrelationId }. TenantId,
    ReportType, and OutputFormat are $null unless populated via pipeline binding.
.LINK
    https://github.com/royklo/InforcerCommunity/blob/main/docs/CMDLET-REFERENCE.md#save-inforcerreportoutput
.LINK
    Invoke-InforcerReport
.LINK
    Get-InforcerReportRun
#>
function Save-InforcerReportOutput {
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
[OutputType([PSObject], [string])]
param(
    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true, Position = 0)]
    [guid]$RunId,

    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true, Position = 1)]
    [Alias('Id')]
    [string]$OutputId,

    # Pipeline pass-through properties from upstream cmdlets (Invoke-InforcerReport -NoSave,
    # Get-InforcerReportRun -IncludeOutputs). Surfaced on the result so it matches the
    # InforcerCommunity.ReportRunResult format view; left $null when called standalone.
    [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
    [string]$ReportType,

    [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
    [string]$OutputFormat,

    [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
    [Alias('ClientTenantId', 'MsTenantId')]
    [object]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = $PWD.Path,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$FileName,

    [Parameter(Mandatory = $false)]
    [ValidateSet('PowerShellObject', 'JsonObject')]
    [string]$OutputType = 'PowerShellObject'
)

begin {
    # PowerShell quirk: `return` inside `begin` does NOT prevent `process` from firing for
    # piped items. Gate `process` on a "begin succeeded" flag instead.
    # Locals (NOT $script:*) so two parallel invocations sharing one module import don't
    # clobber each other's OutputPath.
    $beginOk = $false
    $resolvedOutputPath = $null

    if (-not (Test-InforcerSession)) {
        Write-Error -Message 'Not connected yet. Please run Connect-Inforcer first.' `
            -ErrorId 'NotConnected' -Category ConnectionError
        return
    }
    try {
        # Defense-in-depth: refuse system paths.
        $null = Test-InforcerSafeOutputPath -Path $OutputPath
        if (-not (Test-Path -LiteralPath $OutputPath -PathType Container)) {
            $null = New-Item -Path $OutputPath -ItemType Directory -Force -ErrorAction Stop
        }
        if (Test-Path -LiteralPath $OutputPath -PathType Container) {
            $resolvedOutputPath = (Resolve-Path -LiteralPath $OutputPath).Path
        } elseif (-not $WhatIfPreference) {
            throw "Output directory '$OutputPath' was not created."
        }
    } catch {
        Write-Error -Message "Cannot prepare output directory '$OutputPath': $($_.Exception.Message)" `
            -ErrorId 'OutputPathFailed' -Category InvalidArgument
        return
    }
    $beginOk = $true
}

process {
    if (-not $beginOk) { return }
    if ([string]::IsNullOrWhiteSpace($OutputId)) {
        Write-Error -Message 'OutputId is empty.' -ErrorId 'InvalidOutputId' -Category InvalidArgument
        return
    }

    $runIdStr = $RunId.ToString()
    $endpoint = "/reports/runs/$runIdStr/outputs/$OutputId"

    # -FileName wins over the server's Content-Disposition name; the helper sanitizes either one.
    $downloadParams = @{ Endpoint = $endpoint; DefaultFileName = ('{0}-{1}' -f $runIdStr, $OutputId); DestinationDirectory = $resolvedOutputPath }
    if (-not [string]::IsNullOrWhiteSpace($FileName)) { $downloadParams['FileName'] = $FileName }

    $target = "$runIdStr / $OutputId → $resolvedOutputPath"
    if (-not $PSCmdlet.ShouldProcess($target, 'Download report output')) { return }

    Write-Verbose "Downloading: $endpoint"
    try {
        # Stream straight to disk so multi-GB report outputs don't materialize in memory.
        $download = Invoke-InforcerRawDownload @downloadParams -ErrorAction Stop
    } catch {
        Write-Error -Message "Failed to download output ${OutputId}: $($_.Exception.Message)" `
            -ErrorId 'DownloadFailed' -Category ReadError
        return
    }
    if ($null -eq $download) { return }

    $filePath = $download.FilePath
    $effectiveName = $download.FileName

    $fileSize = if ($download.PSObject.Properties['FileSize']) { $download.FileSize } else { (Get-Item -LiteralPath $filePath -ErrorAction SilentlyContinue).Length }

    $result = [PSCustomObject][ordered]@{
        RunId         = $runIdStr
        OutputId      = $OutputId
        TenantId      = if ($PSBoundParameters.ContainsKey('TenantId')) { $TenantId } else { $null }
        ReportType    = if ($PSBoundParameters.ContainsKey('ReportType')) { $ReportType } else { $null }
        OutputFormat  = if ($PSBoundParameters.ContainsKey('OutputFormat')) { $OutputFormat } else { $null }
        FilePath      = $filePath
        FileName      = $effectiveName
        FileSize      = $fileSize
        ContentType   = $download.ContentType
        CorrelationId = $download.CorrelationId
    }
    $result.PSObject.TypeNames.Insert(0, 'InforcerCommunity.ReportRunResult')

    if ($OutputType -eq 'JsonObject') {
        $result | ConvertTo-Json -Depth 100
    } else {
        $result
    }
}
}
