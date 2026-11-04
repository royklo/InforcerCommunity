<#
.SYNOPSIS
    Generates comprehensive tenant documentation across all M365 products managed via Inforcer.

    Required API scope(s): Tenants.Read + Baselines.Read + tenants.policies.Read (API key);
    Tenants + Baselines + Policies (+ Align with -Baseline) permission (API client, unconfirmed).
.DESCRIPTION
    Export-InforcerTenantDocumentation collects the tenant, its baselines and its policies (the raw
    API data, as Get-InforcerTenant, Get-InforcerBaseline and Get-InforcerTenantPolicies return it),
    normalizes it into a format-agnostic DocModel via ConvertTo-InforcerDocModel, and renders the
    DocModel to one or more output formats.

    Intune Settings Catalog settingDefinitionIDs are resolved to friendly names and descriptions
    using a settings.json catalog sourced from the IntuneSettingsCatalogData GitHub repository.
    By default, the catalog is downloaded and cached at runtime (unless SettingsCatalogPath is
    provided). If the catalog cannot be loaded, Settings Catalog policies show raw
    settingDefinitionId values instead.

    Before calling this cmdlet, you must be connected via Connect-Inforcer. If no active session
    exists, the cmdlet emits a non-terminating error and returns immediately. Both login types
    work. With client credentials (v1 API) the API currently returns no Intune policies: a warning
    says so, and the document (and the returned DocModel's Notes) carry a visible note. Connect
    with an API key to include them.

    Nothing is written unless -OutputPath is given: without it the DocModel is returned so a
    caller can read the configuration without producing files. With it, output is auto-named
    {TenantName}-Documentation.{ext} (e.g., Contoso-Documentation.html).

    The Profile type column is filled from the policy type id when the API sends no type name.
    Excel: values that start with '=' are written as text with a leading apostrophe, and web
    addresses are not turned into links. Markdown: & < > in cells and headings are encoded.
.PARAMETER Format
    Output format(s) to generate. Accepted values: Html, Markdown, Excel. Multiple formats
    can be specified as a comma-separated list or array. Defaults to Html. Excel format
    creates an .xlsx workbook with one sheet per product (requires ImportExcel module).
.PARAMETER TenantId
    Tenant to document. Accepts a numeric ID (API-key login only), Microsoft tenant ID (GUID), or
    tenant name. Required.
.PARAMETER OutputPath
    Directory to write output files to. Files are auto-named {TenantName}-Documentation.{ext}.
    When a single format is specified and this path has a file extension, it is treated as an
    explicit output file path; that only works for one tenant, so piping a second tenant to a file
    path stops with an OutputPathIsFileForSeveralTenants error before anything is fetched for it.
    Pass a directory when piping several tenants. Omit it and no files are written: the DocModel is
    returned instead. There is no default - writing is always something you asked for.
.PARAMETER Show
    Open the generated HTML in the default browser. Requires -OutputPath and -Format Html — there
    is nothing to open when no file is written. Each HTML file is opened at most once per call, also
    when several tenants are piped in.

    Defaults to ON in an interactive session and OFF on a CI runner (CI, TF_BUILD, GITHUB_ACTIONS
    and similar), so a human who asked for a report gets to look at it while a build agent does
    not try to launch a browser. Pass -Show to force it, -Show:$false to suppress it; an explicit
    value always wins over the detection.
.PARAMETER SettingsCatalogPath
    Path to a local settings.json file for Settings Catalog resolution. When omitted, the cmdlet
    automatically downloads and caches the latest data from the IntuneSettingsCatalogData GitHub
    repository (~65 MB, cached at ~/.inforcercommunity/data/settings.json). After 24 hours it checks
    for a newer release and downloads it; a download that is not a valid catalog, or is larger than
    512 MB, never replaces the cached copy. If download fails and no cached copy exists, Settings
    Catalog policies show raw settingDefinitionId values and a warning is emitted.
.PARAMETER FetchGraphData
    When specified, signs in to Microsoft Graph for the tenant and resolves IDs to names: assignment
    groups and filters, scope tags, and the groups, directory roles (built-in and custom), named
    locations and applications in Conditional Access policies. Requests the read scopes
    Directory.Read.All, Policy.Read.All and DeviceManagementConfiguration.Read.All. Requires the
    Microsoft.Graph.Authentication module. If Graph cannot be reached, or refuses a call for a
    missing permission, the affected names stay as raw IDs with a warning.
.PARAMETER Baseline
    Filter to only policies that belong to a specific baseline. Accepts a baseline GUID or
    friendly name (e.g., "Inforcer Blueprint Baseline - Tier 1 - Foundations"). Uses the
    Inforcer alignment details API to retrieve the list of policies in the baseline, then
    filters the documentation to only those policies. The baseline name is shown in the header.
.PARAMETER Tag
    Filter to only policies that have a specific Inforcer tag (e.g., "IAM - Core", "Tier 1").
    Matches against the tag name property on each policy (case-insensitive, contains match).
.OUTPUTS
    The DocModel (hashtable) when -OutputPath is omitted, otherwise System.IO.FileInfo for each
    exported file.
.EXAMPLE
    Export-InforcerTenantDocumentation -TenantId 'Contoso' -Format Html

    Returns the DocModel. No file is written - pass -OutputPath for that.
.EXAMPLE
    Export-InforcerTenantDocumentation -TenantId 'Contoso' -Format Html -OutputPath ./docs -Show

    Writes Contoso-Documentation.html to ./docs and opens it.
.EXAMPLE
    Export-InforcerTenantDocumentation -TenantId 'Contoso' -Format Html,Markdown,Excel -OutputPath C:\Reports

    Writes three documentation files to C:\Reports.
.EXAMPLE
    Export-InforcerTenantDocumentation -TenantId "Contoso" -Format Html -SettingsCatalogPath .\settings.json

    Uses an explicit settings.json path for Settings Catalog resolution.
.EXAMPLE
    Export-InforcerTenantDocumentation -TenantId 'Contoso' -Baseline "Inforcer Blueprint Baseline - Tier 1 - Foundations" -Format Html

    Exports only the policies that belong to the specified baseline.
.LINK
    https://github.com/royklo/InforcerCommunity/blob/main/docs/CMDLET-REFERENCE.md#export-inforcertenantdocumentation
.LINK
    Connect-Inforcer
#>
function Export-InforcerTenantDocumentation {
[CmdletBinding()]
[OutputType([hashtable], [System.IO.FileInfo])]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Html', 'Markdown', 'Excel')]
    [string[]]$Format = @('Html'),

    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [Alias('ClientTenantId', 'MsTenantId')]
    [object]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    # Defaults ON for a human at a prompt, OFF on a CI runner. -Show / -Show:$false always wins.
    [Parameter(Mandatory = $false)]
    [switch]$Show = (Test-InforcerInteractiveHost),

    [Parameter(Mandatory = $false)]
    [string]$SettingsCatalogPath,

    [Parameter(Mandatory = $false)]
    [switch]$FetchGraphData,

    [Parameter(Mandatory = $false)]
    [string]$Baseline,

    [Parameter(Mandatory = $false)]
    [string]$Tag
)

begin {
    $tenantCount = 0
    $openedHtml = [System.Collections.Generic.HashSet[string]]::new()
}

process {

$tenantCount++
if ($tenantCount -gt 1 -and $Format.Count -eq 1 -and $OutputPath -and [System.IO.Path]::HasExtension($OutputPath)) {
    throw [System.Management.Automation.ErrorRecord]::new(
        [System.ArgumentException]::new("-OutputPath '$OutputPath' is a file, so a second tenant would overwrite the first. Pass a directory when piping several tenants; each gets its own {TenantName}-Documentation file."),
        'OutputPathIsFileForSeveralTenants', [System.Management.Automation.ErrorCategory]::InvalidArgument, $OutputPath)
}

if (-not (Test-InforcerSession)) {
    Write-Error -Message 'Not connected yet. Please run Connect-Inforcer first.' `
        -ErrorId 'NotConnected' -Category ConnectionError
    return
}

try {
    $resolvedTenantId = Resolve-InforcerTenantId -TenantId $TenantId
} catch {
    Write-Error -Message $_.Exception.Message -ErrorId 'InvalidTenantId' -Category InvalidArgument
    return
}

# Settings catalog path: explicit override or auto-resolved via cache strategy
$resolvedCatalogPath = $SettingsCatalogPath

# Collect data from the 3 source cmdlets and build DocModel
Write-Host 'Collecting tenant data...' -ForegroundColor Cyan
$docDataParams = @{ TenantId = $resolvedTenantId }
if (-not [string]::IsNullOrEmpty($resolvedCatalogPath)) {
    $docDataParams['SettingsCatalogPath'] = $resolvedCatalogPath
}
$docData = Get-InforcerDocData @docDataParams
if ($null -eq $docData) { return }

# Filter to baseline policies if -Baseline specified
$baselineFilterName = $null
if (-not [string]::IsNullOrWhiteSpace($Baseline)) {
    Write-Host "Filtering to baseline: $Baseline" -ForegroundColor Cyan
    $baselineFilterName = Select-InforcerBaselinePolicies -DocData $docData -BaselineId $Baseline
    if ($null -eq $baselineFilterName) {
        Write-Warning 'Exporting all policies.'
        $baselineFilterName = $Baseline
    }
}

# Filter by tag if -Tag specified
if (-not [string]::IsNullOrWhiteSpace($Tag)) {
    Write-Host "Filtering to tag: $Tag" -ForegroundColor Cyan
    $originalCount = @($docData.Policies).Count

    # Collected before the filter so a no-match can name the tags that do exist.
    $availableTags = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($pol in @($docData.Policies)) {
        foreach ($t in @($pol.tags)) {
            if ($null -eq $t) { continue }
            $n = if ($t -is [PSObject] -and $t.PSObject.Properties['name']) { $t.name } else { $t.ToString() }
            if (-not [string]::IsNullOrWhiteSpace($n)) { [void]$availableTags.Add($n) }
        }
    }

    $docData.Policies = @($docData.Policies | Where-Object {
        $policyTags = $_.tags
        if ($null -eq $policyTags -or @($policyTags).Count -eq 0) { return $false }
        foreach ($t in @($policyTags)) {
            $tagName = if ($t -is [PSObject] -and $t.PSObject.Properties['name']) { $t.name } else { $t.ToString() }
            if ($tagName -and $tagName.IndexOf($Tag, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) { return $true }
        }
        return $false
    })
    Write-Host "  Filtered to $(@($docData.Policies).Count) of $originalCount policies with tag '$Tag'" -ForegroundColor Gray

    # No match used to render anyway: a 0.1 KB document and exit 0, which reads as "nothing in
    # this tenant is tagged that way" when the likelier cause is a tag name that does not exist.
    # Naming the real tags is the difference between a dead end and a correctable mistake.
    if (@($docData.Policies).Count -eq 0) {
        $known = if ($availableTags.Count -gt 0) { $availableTags -join "', '" } else { $null }
        $detail = if ($known) { "Tags present in this tenant: '$known'." } else { 'No policy in this tenant carries any tag.' }
        Write-Error -Message "No policy matched tag '$Tag', so there is nothing to document. $detail" `
            -ErrorId 'TagMatchedNothing' -Category ObjectNotFound
        return
    }
}

# Load Settings Catalog only if there are Settings Catalog policies (policyTypeId 10)
$hasCatalogPolicies = @($docData.Policies | Where-Object { $_.policyTypeId -eq 10 }).Count -gt 0
if ($hasCatalogPolicies) {
    $catalogParams = @{}
    if (-not [string]::IsNullOrEmpty($resolvedCatalogPath)) {
        $catalogParams['Path'] = $resolvedCatalogPath
    }
    Import-InforcerSettingsCatalog @catalogParams
} else {
    Write-Host '  No Intune/Defender policies found, skipping Settings Catalog load' -ForegroundColor Gray
}

# Graph maps are built fresh for this tenant only; nothing carries over between piped tenants or calls.
$graphMaps = @{}
if ($FetchGraphData) {
    $tenantLabel = if ($docData.Tenant -and $docData.Tenant.tenantFriendlyName) { " for $($docData.Tenant.tenantFriendlyName)" } else { '' }
    Write-Host "Connecting to Microsoft Graph$tenantLabel..." -ForegroundColor Cyan
    $graphMaps = Resolve-InforcerGraphEnrichment -DocData $docData -ConditionalAccess
}

Write-Host 'Building documentation model...' -ForegroundColor Cyan
$docModelParams = @{ DocData = $docData }
foreach ($key in 'GroupNameMap', 'FilterMap', 'RoleNameMap', 'LocationNameMap', 'AppNameMap', 'ScopeTagMap') {
    if ($graphMaps[$key]) { $docModelParams[$key] = $graphMaps[$key] }
}
$docModel = ConvertTo-InforcerDocModel @docModelParams
if ($null -eq $docModel) { return }

# Add filter metadata so renderers can show what's active
if ($baselineFilterName) { $docModel['FilterBaseline'] = $baselineFilterName }
if (-not [string]::IsNullOrWhiteSpace($Tag)) { $docModel['FilterTag'] = $Tag }

$policyCount = 0
foreach ($product in $docModel.Products.Values) {
    foreach ($policies in $product.Categories.Values) { $policyCount += @($policies).Count }
}
Write-Host "  Found $policyCount policies across $($docModel.Products.Count) products" -ForegroundColor Gray

# ── No -OutputPath: hand back the DocModel and touch nothing ───────────────────
# Writing is opt-in even here, where the verb promises a file. The old default put documents in
# whatever directory you happened to be standing in and opened a browser for them, which is
# wrong in a pipeline and wrong for a caller that only wants the model to read.
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    Write-Host 'Done. Pass -OutputPath to write files.' -ForegroundColor Cyan
    return $docModel
}

# Render each requested format and write to disk
$extensionMap = @{ Html = 'html'; Markdown = 'md'; Excel = 'xlsx' }
$formatIndex = 0
$htmlFile = $null
$safeName = $docModel.TenantName -replace '[^\w\-]', '-'

foreach ($fmt in $Format) {
    $formatIndex++
    $ext = $extensionMap[$fmt]

    if ($Format.Count -eq 1 -and [System.IO.Path]::HasExtension($OutputPath)) {
        $filePath = $OutputPath
    } else {
        $filePath = Join-Path $OutputPath "$safeName-Documentation.$ext"
    }

    $parentDir = Split-Path -Parent $filePath
    if (-not [string]::IsNullOrEmpty($parentDir) -and -not (Test-Path -LiteralPath $parentDir)) {
        [void](New-Item -ItemType Directory -Force -Path $parentDir)
    }

    Write-Host "Rendering $fmt ($formatIndex/$($Format.Count))..." -ForegroundColor Cyan

    if ($fmt -eq 'Excel') {
        # Excel writes directly to disk via ImportExcel
        Export-InforcerDocExcel -DocModel $docModel -FilePath $filePath
        if (-not (Test-Path -LiteralPath $filePath)) { continue }
    } else {
        $content = switch ($fmt) {
            'Html'     { ConvertTo-InforcerHtml     -DocModel $docModel }
            'Markdown' { ConvertTo-InforcerMarkdown -DocModel $docModel }
        }
        Set-Content -Path $filePath -Value $content -Encoding UTF8
        if ($fmt -eq 'Html') { $htmlFile = $filePath }
    }

    $fileInfo = Get-Item -LiteralPath $filePath
    $sizeKb = [math]::Round($fileInfo.Length / 1KB, 1)
    Write-Host "  Exported: $filePath ($sizeKb KB)" -ForegroundColor Green
    $fileInfo
}

# -Show defaults to on interactively and off in CI (Test-InforcerInteractiveHost), so a human
# who asked for a report sees it while a build agent is never handed a browser to open.
if ($Show -and $htmlFile -and (Test-Path -LiteralPath $htmlFile)) {
    $fullHtmlPath = (Resolve-Path -LiteralPath $htmlFile).Path
    if ($openedHtml.Add($fullHtmlPath)) {
        if ($IsMacOS) { Start-Process 'open' -ArgumentList $fullHtmlPath }
        elseif ($IsWindows) { Start-Process $fullHtmlPath }
        elseif ($IsLinux) { Start-Process 'xdg-open' -ArgumentList $fullHtmlPath }
    }
}

Write-Host "Done. $($Format.Count) file(s) exported for tenant '$($docModel.TenantName)'." -ForegroundColor Cyan
}
}
