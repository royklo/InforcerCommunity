<#
.SYNOPSIS
    Compares the Intune policy configuration of two tenants and generates an HTML report.
.DESCRIPTION
    Fetches all policies from two tenants via Get-InforcerTenantPolicies, compares Intune
    Settings Catalog settings at the settingDefinitionId level, and produces a self-contained
    HTML report showing alignment score, matches, conflicts, source-only/destination-only items,
    and non-Settings-Catalog policies for manual review. When -FetchGraphData is specified,
    also fetches compliance policy detection rules (rulesContent) that the Inforcer API does
    not return.

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
    Optional baseline GUID or friendly name for the source tenant. When specified, the comparison
    is scoped to only policies belonging to this baseline instead of all tenant policies.
.PARAMETER DestinationBaselineId
    Optional baseline GUID or friendly name for the destination tenant. When specified, the comparison
    is scoped to only policies belonging to this baseline instead of all tenant policies.
.PARAMETER IncludingAssignments
    When specified, fetches and displays Graph assignment data in the report.
    Assignments are informational only and do not affect the alignment score.
.PARAMETER SettingsCatalogPath
    Path to the IntuneSettingsCatalogViewer settings.json file.
    Auto-discovers from sibling repo if omitted.
.PARAMETER FetchGraphData
    When specified, connects to Microsoft Graph to enrich comparison data beyond what the
    Inforcer API provides. Requires the Microsoft.Graph.Authentication module and interactive
    sign-in. If tenants are in different Azure AD tenants, you will be prompted for each.
    Requires DeviceManagementConfiguration.Read.All scope for compliance rules.

    Graph supplementations:
    - Assignment group name resolution (ObjectID to display name)
    - Assignment filter resolution (filter ID to filter details)
    - Scope tag resolution (tag ID to display name)
    - Compliance rules for custom compliance policies (rulesContent via $expand)
.PARAMETER ExcludeOS
    Array of OS/platform names to exclude from the comparison. Matching is case-insensitive
    and uses contains logic. Examples: 'macOS', 'iOS', 'Android', 'Windows'.
    Excluded platforms do not affect the alignment score.
.PARAMETER PolicyNameFilter
    Only include policies whose name contains this string (case-insensitive).
    Non-matching policies are excluded from both the report and the alignment score.
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
.EXAMPLE
    Compare-InforcerEnvironments -SourceTenantId 'Contoso' -SourceBaselineId 'Tier 1 Foundations' -DestinationTenantId 'Fabrikam'
    # Compares only policies in the 'Tier 1 Foundations' baseline from Contoso against all Fabrikam policies.
.EXAMPLE
    Compare-InforcerEnvironments -SourceTenantId 'Contoso' -SourceBaselineId 'Tier 1' -DestinationTenantId 'Fabrikam' -DestinationBaselineId 'Tier 2'
    # Compares two baselines from different tenants.
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
    [string]$SourceBaselineId,

    [Parameter(Mandatory = $false)]
    [string]$DestinationBaselineId,

    [Parameter(Mandatory = $false)]
    [switch]$IncludingAssignments,

    [Parameter(Mandatory = $false)]
    [string]$SettingsCatalogPath,

    [Parameter(Mandatory = $false)]
    [switch]$FetchGraphData,

    [Parameter(Mandatory = $false)]
    [string[]]$ExcludeOS,

    [Parameter(Mandatory = $false)]
    [string]$PolicyNameFilter,

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

# ── Load Settings Catalog for friendly name resolution ────────────────────────
$catalogParams = @{}
if (-not [string]::IsNullOrEmpty($SettingsCatalogPath)) { $catalogParams['Path'] = $SettingsCatalogPath }
Import-InforcerSettingsCatalog @catalogParams

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
if ($FetchGraphData) { $compDataParams['FetchGraphData'] = $true }
if (-not [string]::IsNullOrWhiteSpace($SourceBaselineId))      { $compDataParams['SourceBaselineId']      = $SourceBaselineId }
if (-not [string]::IsNullOrWhiteSpace($DestinationBaselineId)) { $compDataParams['DestinationBaselineId'] = $DestinationBaselineId }

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

$sourceDisplay = $compData.SourceName
if ($compData.SourceBaselineName) { $sourceDisplay += " ($($compData.SourceBaselineName))" }
$destDisplay = $compData.DestinationName
if ($compData.DestinationBaselineName) { $destDisplay += " ($($compData.DestinationBaselineName))" }
Write-Host "  Source:      $sourceDisplay" -ForegroundColor Gray
Write-Host "  Destination: $destDisplay" -ForegroundColor Gray

# ── Stage 2: Build comparison model ──────────────────────────────────────────
Write-Host 'Stage 2: Building comparison model...' -ForegroundColor Cyan

$compareParams = @{
    SourceModel          = $compData.SourceModel
    DestinationModel     = $compData.DestinationModel
    IncludingAssignments = $compData.IncludingAssignments
}
if ($ExcludeOS) {
    $compareParams['ExcludeOS'] = $ExcludeOS
    Write-Host "  Excluding products: $($ExcludeOS -join ', ')" -ForegroundColor Gray
}
if ($PolicyNameFilter) {
    $compareParams['PolicyNameFilter'] = $PolicyNameFilter
    Write-Host "  Policy name filter: '$PolicyNameFilter'" -ForegroundColor Gray
}

if ($compData.SourceBaselineName)      { $compareParams['SourceBaselineName']      = $compData.SourceBaselineName }
if ($compData.DestinationBaselineName) { $compareParams['DestinationBaselineName'] = $compData.DestinationBaselineName }

$model = Compare-InforcerDocModels @compareParams

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
$safeSrc = ($compData.SourceName -replace '[^\w\-]', '-') -replace '-{2,}', '-'
if ($compData.SourceBaselineName) {
    $safeBaseline = ($compData.SourceBaselineName -replace '[^\w\-]', '-') -replace '-{2,}', '-'
    if ($safeBaseline.Length -gt 30) { $safeBaseline = $safeBaseline.Substring(0, 30).TrimEnd('-') }
    $safeSrc = "$safeSrc-$safeBaseline"
}
$safeDst = ($compData.DestinationName -replace '[^\w\-]', '-') -replace '-{2,}', '-'
if ($compData.DestinationBaselineName) {
    $safeBaseline = ($compData.DestinationBaselineName -replace '[^\w\-]', '-') -replace '-{2,}', '-'
    if ($safeBaseline.Length -gt 30) { $safeBaseline = $safeBaseline.Substring(0, 30).TrimEnd('-') }
    $safeDst = "$safeDst-$safeBaseline"
}
$fileName = "comparison-$safeSrc-vs-$safeDst-$timestamp.html"
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
