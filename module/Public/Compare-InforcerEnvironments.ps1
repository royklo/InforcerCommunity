<#
.SYNOPSIS
    Compares the Intune policy configuration of two tenants and generates an HTML report.
.DESCRIPTION
    Fetches all policies from two tenants via Get-InforcerTenantPolicies, compares Intune
    Settings Catalog settings at the settingDefinitionId level, and produces a self-contained
    HTML report showing alignment score, matches, conflicts, source-only/destination-only items,
    and non-Settings-Catalog policies for manual review.

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
    Compare-InforcerEnvironments -SourceTenantId 482 -DestinationTenantId 139 -IncludingAssignments
.LINK
    https://github.com/royklo/InforcerCommunity/blob/main/docs/CMDLET-REFERENCE.md#compare-inforcerenvironments
.LINK
    Connect-Inforcer
#>
function Compare-InforcerEnvironments {
[CmdletBinding()]
[OutputType([System.IO.FileInfo])]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [object]$SourceTenantId,

    [Parameter(Mandatory = $true, Position = 1)]
    [object]$DestinationTenantId,

    [Parameter(Mandatory = $false)]
    [hashtable]$SourceSession,

    [Parameter(Mandatory = $false)]
    [hashtable]$DestinationSession,

    [Parameter(Mandatory = $false)]
    [switch]$IncludingAssignments,

    [Parameter(Mandatory = $false)]
    [string]$SettingsCatalogPath,

    [Parameter(Mandatory = $false)]
    [switch]$IgnoreUnassignedPolicies,

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

# Warn that assignments are informational only
if ($IncludingAssignments) {
    Write-Warning 'Assignment data is informational only and does not affect the alignment score.'
}

# ── Stage 1: Collect data from both environments ─────────────────────────────
Write-Host 'Stage 1: Collecting environment data...' -ForegroundColor Cyan

$compDataParams = @{
    SourceTenantId      = $SourceTenantId
    DestinationTenantId = $DestinationTenantId
}
if ($null -ne $SourceSession)       { $compDataParams['SourceSession']      = $SourceSession }
if ($null -ne $DestinationSession)  { $compDataParams['DestinationSession'] = $DestinationSession }
if (-not [string]::IsNullOrWhiteSpace($SettingsCatalogPath)) { $compDataParams['SettingsCatalogPath'] = $SettingsCatalogPath }
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

Write-Host "  Source:      $($compData.SourceName)" -ForegroundColor Gray
Write-Host "  Destination: $($compData.DestinationName)" -ForegroundColor Gray

# ── Stage 2: Build comparison model ──────────────────────────────────────────
Write-Host 'Stage 2: Building comparison model...' -ForegroundColor Cyan

$model = Compare-InforcerDocModels -SourceModel $compData.SourceModel `
    -DestinationModel $compData.DestinationModel `
    -IncludingAssignments:$compData.IncludingAssignments `
    -IgnoreUnassignedPolicies:$IgnoreUnassignedPolicies

if ($null -eq $model) {
    Write-Error -Message 'Compare-InforcerDocModels returned no model.' `
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
