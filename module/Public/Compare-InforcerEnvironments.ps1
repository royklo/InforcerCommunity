<#
.SYNOPSIS
    Compares the policy configuration of two M365 environments and generates an HTML report.
.DESCRIPTION
    Fetches policies from a source and destination environment (each can be a tenant or baseline),
    compares them at the Intune Settings Catalog setting level (settingDefinitionId matching),
    and produces a self-contained HTML report showing alignment score, matches, conflicts,
    and source-only/destination-only items.

    For cross-account comparison, use Connect-Inforcer -PassThru to obtain session objects
    and pass them via -SourceSession / -DestinationSession.
.PARAMETER SourceTenantId
    Source tenant identifier: numeric ID, Microsoft Tenant ID GUID, or friendly name.
.PARAMETER DestinationTenantId
    Destination tenant identifier: numeric ID, Microsoft Tenant ID GUID, or friendly name.
.PARAMETER SourceSession
    Session hashtable from Connect-Inforcer -PassThru. If omitted, uses the current session.
.PARAMETER DestinationSession
    Session hashtable from Connect-Inforcer -PassThru. If omitted, uses the current session.
.PARAMETER SourceBaselineId
    Source baseline GUID or friendly name. Use instead of -SourceTenantId for baseline comparison.
.PARAMETER DestinationBaselineId
    Destination baseline GUID or friendly name. Use instead of -DestinationTenantId.
.PARAMETER IncludingAssignments
    When specified, fetches and displays Graph assignment data in the report.
    Assignments are informational only and do not affect the alignment score.
.PARAMETER SettingsCatalogPath
    Path to the IntuneSettingsCatalogViewer settings.json file.
    Auto-discovers from sibling repo if omitted.
.PARAMETER OutputPath
    Directory where the HTML report will be written. Defaults to current directory.
.OUTPUTS
    System.IO.FileInfo. Returns a FileInfo object for the exported HTML report.
.EXAMPLE
    Connect-Inforcer -ApiKey $key
    Compare-InforcerEnvironments -SourceTenantId 'Contoso' -DestinationTenantId 'Fabrikam'
.EXAMPLE
    $src = Connect-Inforcer -ApiKey $key1 -Region uk -PassThru
    $dst = Connect-Inforcer -ApiKey $key2 -Region eu -PassThru
    Compare-InforcerEnvironments -SourceTenantId 'Contoso' -DestinationTenantId 'Fabrikam' -SourceSession $src -DestinationSession $dst
.EXAMPLE
    Compare-InforcerEnvironments -SourceBaselineId 'Production Baseline' -DestinationTenantId 482 -IncludingAssignments
.LINK
    https://github.com/royklo/InforcerCommunity/blob/main/docs/CMDLET-REFERENCE.md#compare-inforcerenvironments
.LINK
    Connect-Inforcer
#>
function Compare-InforcerEnvironments {
[CmdletBinding()]
[OutputType([System.IO.FileInfo])]
param(
    [Parameter(Mandatory = $false)]
    [object]$SourceTenantId,

    [Parameter(Mandatory = $false)]
    [object]$DestinationTenantId,

    [Parameter(Mandatory = $false)]
    [hashtable]$SourceSession,

    [Parameter(Mandatory = $false)]
    [hashtable]$DestinationSession,

    [Parameter(Mandatory = $false)]
    [string]$SourceBaselineId,

    [Parameter(Mandatory = $false)]
    [string]$DestinationBaselineId,

    [Parameter(Mandatory = $false)]
    [switch]$IncludingAssignments,

    [Parameter(Mandatory = $false)]
    [string]$SettingsCatalogPath,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = '.'
)

# Session guard: require an active session unless both explicit sessions are provided
$hasExplicitSessions = ($null -ne $SourceSession) -and ($null -ne $DestinationSession)
if (-not $hasExplicitSessions -and -not (Test-InforcerSession)) {
    Write-Error -Message 'Not connected yet. Please run Connect-Inforcer first.' `
        -ErrorId 'NotConnected' -Category ConnectionError
    return
}

# Source validation: must supply either SourceTenantId or SourceBaselineId
$hasSource = ($null -ne $SourceTenantId -and -not [string]::IsNullOrWhiteSpace("$SourceTenantId")) -or
             (-not [string]::IsNullOrWhiteSpace($SourceBaselineId))
if (-not $hasSource) {
    Write-Error -Message 'You must specify either -SourceTenantId or -SourceBaselineId.' `
        -ErrorId 'MissingSource' -Category InvalidArgument
    return
}

# Destination validation: must supply either DestinationTenantId or DestinationBaselineId
$hasDest = ($null -ne $DestinationTenantId -and -not [string]::IsNullOrWhiteSpace("$DestinationTenantId")) -or
           (-not [string]::IsNullOrWhiteSpace($DestinationBaselineId))
if (-not $hasDest) {
    Write-Error -Message 'You must specify either -DestinationTenantId or -DestinationBaselineId.' `
        -ErrorId 'MissingDestination' -Category InvalidArgument
    return
}

# Warn that assignments are informational only
if ($IncludingAssignments) {
    Write-Warning 'Assignment data is informational only and does not affect the alignment score.'
}

# ── Stage 1: Collect data from both environments ─────────────────────────────
Write-Host 'Stage 1: Collecting environment data...' -ForegroundColor Cyan

$compDataParams = @{}
if ($null -ne $SourceTenantId -and -not [string]::IsNullOrWhiteSpace("$SourceTenantId")) {
    $compDataParams['SourceTenantId'] = $SourceTenantId
}
if ($null -ne $DestinationTenantId -and -not [string]::IsNullOrWhiteSpace("$DestinationTenantId")) {
    $compDataParams['DestinationTenantId'] = $DestinationTenantId
}
if ($null -ne $SourceSession)         { $compDataParams['SourceSession']      = $SourceSession }
if ($null -ne $DestinationSession)    { $compDataParams['DestinationSession'] = $DestinationSession }
if (-not [string]::IsNullOrWhiteSpace($SourceBaselineId))      { $compDataParams['SourceBaselineId']      = $SourceBaselineId }
if (-not [string]::IsNullOrWhiteSpace($DestinationBaselineId)) { $compDataParams['DestinationBaselineId'] = $DestinationBaselineId }
if (-not [string]::IsNullOrWhiteSpace($SettingsCatalogPath))   { $compDataParams['SettingsCatalogPath']   = $SettingsCatalogPath }
if ($IncludingAssignments) { $compDataParams['IncludingAssignments'] = $true }

$compData = $null
try {
    $compData = Get-InforcerComparisonData @compDataParams
} catch {
    Write-Error -Message "Failed to collect comparison data: $($_.Exception.Message)" `
        -ErrorId 'DataCollectionFailed' -Category ConnectionError
    return
}

if ($null -eq $compData) {
    Write-Error -Message 'Get-InforcerComparisonData returned no data.' `
        -ErrorId 'DataCollectionFailed' -Category InvalidResult
    return
}

Write-Host "  Source:      $($compData.SourceName) ($($compData.SourceType)), $(@($compData.SourcePolicies).Count) policies" -ForegroundColor Gray
Write-Host "  Destination: $($compData.DestinationName) ($($compData.DestinationType)), $(@($compData.DestinationPolicies).Count) policies" -ForegroundColor Gray

# ── Stage 2: Build comparison model ──────────────────────────────────────────
Write-Host 'Stage 2: Building comparison model...' -ForegroundColor Cyan

$model = ConvertTo-InforcerComparisonModel -ComparisonData $compData

if ($null -eq $model) {
    Write-Error -Message 'ConvertTo-InforcerComparisonModel returned no model.' `
        -ErrorId 'ModelBuildFailed' -Category InvalidResult
    return
}

Write-Host "  Alignment score: $($model.AlignmentScore)%" -ForegroundColor Gray
Write-Host "  Total items:     $($model.TotalItems)" -ForegroundColor Gray

# ── Stage 3: Render HTML report ───────────────────────────────────────────────
Write-Host 'Stage 3: Rendering HTML report...' -ForegroundColor Cyan

$htmlContent = ConvertTo-InforcerComparisonHtml -ComparisonModel $model

if ([string]::IsNullOrEmpty($htmlContent)) {
    Write-Error -Message 'ConvertTo-InforcerComparisonHtml returned empty content.' `
        -ErrorId 'RenderFailed' -Category InvalidResult
    return
}

# ── Write output file ─────────────────────────────────────────────────────────
if (-not (Test-Path -LiteralPath $OutputPath)) {
    [void](New-Item -ItemType Directory -Force -Path $OutputPath)
}

$timestamp  = (Get-Date).ToString('yyyy-MM-dd-HHmm')
$safeSrc    = ($compData.SourceName      -replace '[^\w\-]', '-') -replace '-{2,}', '-'
$safeDst    = ($compData.DestinationName -replace '[^\w\-]', '-') -replace '-{2,}', '-'
$fileName   = "comparison-$safeSrc-vs-$safeDst-$timestamp.html"
$filePath   = Join-Path $OutputPath $fileName

Set-Content -Path $filePath -Value $htmlContent -Encoding UTF8

$fileInfo = Get-Item -LiteralPath $filePath
$sizeKb   = [math]::Round($fileInfo.Length / 1KB, 1)
Write-Host "  Exported: $filePath ($sizeKb KB)" -ForegroundColor Green

# Auto-open HTML output in the default browser (cross-platform)
$fullPath = (Resolve-Path -LiteralPath $filePath).Path
if ($IsMacOS) { Start-Process 'open' -ArgumentList $fullPath }
elseif ($IsWindows) { Start-Process $fullPath }
elseif ($IsLinux) { Start-Process 'xdg-open' -ArgumentList $fullPath }

Write-Host "Done. Comparison report generated for '$($compData.SourceName)' vs '$($compData.DestinationName)'." -ForegroundColor Cyan

$fileInfo
}
