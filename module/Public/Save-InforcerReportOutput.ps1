<#
.SYNOPSIS
    Downloads a report output to disk.

    Required API scope(s): Reports.Read
.DESCRIPTION
    GET /beta/reports/runs/{runId}/outputs/{outputId} returns the raw bytes plus a
    Content-Disposition filename. This cmdlet writes those bytes to -OutDir using the
    server-suggested filename (sanitized) and emits a result object per saved file.

    Pipeline-friendly: pipe output records from Invoke-InforcerReport -NoSave or
    Get-InforcerReportRun -IncludeOutputs and every output is downloaded.
.PARAMETER RunId
    The run identifier (GUID). Pipeline-bindable by property name.
.PARAMETER OutputId
    The output identifier (string) — the id field on each output record. Pipeline-bindable
    by property name (also accepts -Id as an alias).
.PARAMETER OutDir
    Directory where downloaded outputs are written. Defaults to the current working directory.
    Created if it doesn't exist.
.PARAMETER FileName
    Override the server-suggested filename. Sanitized for cross-platform safety.
.PARAMETER OutputType
    PowerShellObject (default) or JsonObject.
.EXAMPLE
    Save-InforcerReportOutput -RunId <run> -OutputId <output>
    Saves a single output to the current directory.
.EXAMPLE
    Invoke-InforcerReport -ReportType ActiveUserCount -OutputFormat csv -TenantId 14436 -NoSave |
        Save-InforcerReportOutput -OutDir ./reports
    Queues + polls a report without saving, then downloads every output to ./reports.
.EXAMPLE
    Get-InforcerReportRun -IncludeOutputs |
        ForEach-Object { $_.outputs } |
        Save-InforcerReportOutput -OutDir ./bulk
    Bulk-downloads every output from every visible run.
.OUTPUTS
    PSObject or String — per saved file, with { RunId, OutputId, FilePath, FileName, FileSize, ContentType, CorrelationId }
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

    [Parameter(Mandatory = $false)]
    [string]$OutDir = $PWD.Path,

    [Parameter(Mandatory = $false)]
    [string]$FileName,

    [Parameter(Mandatory = $false)]
    [ValidateSet('PowerShellObject', 'JsonObject')]
    [string]$OutputType = 'PowerShellObject'
)

begin {
    # PowerShell quirk: `return` inside `begin` does NOT prevent `process` from firing for
    # piped items. Gate `process` on a "begin succeeded" flag instead.
    $script:_SaveBeginOk = $false
    $script:_SaveOutDir  = $null

    if (-not (Test-InforcerSession)) {
        Write-Error -Message 'Not connected yet. Please run Connect-Inforcer first.' `
            -ErrorId 'NotConnected' -Category ConnectionError
        return
    }
    try {
        if (-not (Test-Path -LiteralPath $OutDir -PathType Container)) {
            $null = New-Item -Path $OutDir -ItemType Directory -Force -ErrorAction Stop
        }
        $script:_SaveOutDir = (Resolve-Path -LiteralPath $OutDir).Path
    } catch {
        Write-Error -Message "Cannot prepare output directory '$OutDir': $($_.Exception.Message)" `
            -ErrorId 'OutDirFailed' -Category InvalidArgument
        return
    }
    $script:_SaveBeginOk = $true
}

process {
    if (-not $script:_SaveBeginOk) { return }
    if ([string]::IsNullOrWhiteSpace($OutputId)) {
        Write-Error -Message 'OutputId is empty.' -ErrorId 'InvalidOutputId' -Category InvalidArgument
        return
    }

    $runIdStr = $RunId.ToString()
    $endpoint = "/beta/reports/runs/$runIdStr/outputs/$OutputId"

    # When -FileName is supplied the user's choice wins (after filesystem-safety sanitization).
    # Otherwise the server's Content-Disposition filename is used (via Invoke-InforcerRawDownload).
    $userSuppliedName = $PSBoundParameters.ContainsKey('FileName')
    $defaultName = if ($userSuppliedName) { $FileName } else { ('{0}-{1}' -f $runIdStr, $OutputId) }

    $target = "$runIdStr / $OutputId → $script:_SaveOutDir"
    if (-not $PSCmdlet.ShouldProcess($target, 'Download report output')) { return }

    Write-Verbose "Downloading: $endpoint"
    try {
        $download = Invoke-InforcerRawDownload -Endpoint $endpoint -DefaultFileName $defaultName -ErrorAction Stop
    } catch {
        Write-Error -Message "Failed to download output ${OutputId}: $($_.Exception.Message)" `
            -ErrorId 'DownloadFailed' -Category ReadError
        return
    }
    if ($null -eq $download) { return }

    $effectiveName = if ($userSuppliedName) {
        # User override: sanitize through the same path the Content-Disposition parser uses
        # to guarantee filesystem safety.
        Resolve-InforcerReportOutputFileName -ContentDisposition $null -DefaultName $FileName
    } else {
        $download.FileName
    }

    $filePath = Join-Path -Path $script:_SaveOutDir -ChildPath $effectiveName
    try {
        [System.IO.File]::WriteAllBytes($filePath, $download.Bytes)
    } catch {
        Write-Error -Message "Failed to write '$filePath': $($_.Exception.Message)" `
            -ErrorId 'WriteFailed' -Category WriteError
        return
    }

    $result = [PSCustomObject][ordered]@{
        RunId         = $runIdStr
        OutputId      = $OutputId
        FilePath      = $filePath
        FileName      = $effectiveName
        FileSize      = $download.Bytes.Length
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
