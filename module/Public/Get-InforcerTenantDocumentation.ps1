<#
.SYNOPSIS
    Generates comprehensive tenant documentation across all M365 products managed via Inforcer.
.DESCRIPTION
    Get-InforcerTenantDocumentation collects configuration data for the specified tenant by calling
    Get-InforcerBaseline, Get-InforcerTenant, and Get-InforcerTenantPolicies (each using
    -OutputType JsonObject), normalizes the raw API data into a format-agnostic DocModel via
    ConvertTo-InforcerDocModel, and renders the DocModel to one or more output formats.

    Intune Settings Catalog settingDefinitionIDs are resolved to friendly names and descriptions
    using a settings.json lookup file (from IntuneSettingsCatalogViewer). If the lookup file is
    not found, Settings Catalog policies show raw settingDefinitionId values instead.

    Before calling this cmdlet, you must be connected via Connect-Inforcer. If no active session
    exists, the cmdlet emits a non-terminating error and returns immediately.

    Output files are written to the specified OutputPath directory and auto-named as
    {TenantName}-Documentation.{ext} (e.g., Contoso-Documentation.html).
.PARAMETER Format
    Output format(s) to generate. Accepted values: Html, Markdown, Json, Csv. Multiple formats
    can be specified as a comma-separated list or array. Defaults to Html.
.PARAMETER TenantId
    Tenant to document. Accepts a numeric ID, GUID, or tenant name. Required.
.PARAMETER OutputPath
    Directory to write output files to. Files are auto-named {TenantName}-Documentation.{ext}.
    When a single format is specified and this path has a file extension, it is treated as an
    explicit output file path. Defaults to the current directory.
.PARAMETER SettingsCatalogPath
    Path to the IntuneSettingsCatalog settings.json file. When omitted, the cmdlet searches:
    1. module/data/settings.json (bundled copy shipped with the module)
    2. Sibling IntuneSettingsCatalogViewer repo at ../IntuneSettingsCatalogViewer/data/settings.json
    If not found in either location, Settings Catalog policies show raw settingDefinitionId values
    and a warning is emitted.
.OUTPUTS
    None. Files are written to OutputPath.
.EXAMPLE
    Get-InforcerTenantDocumentation -TenantId 482 -Format Html

    Writes Contoso-Documentation.html to the current directory.
.EXAMPLE
    Get-InforcerTenantDocumentation -TenantId 482 -Format Html,Markdown,Json,Csv -OutputPath C:\Reports

    Writes four documentation files to C:\Reports.
.EXAMPLE
    Get-InforcerTenantDocumentation -TenantId "Contoso" -Format Html -SettingsCatalogPath .\settings.json

    Uses an explicit settings.json path for Settings Catalog resolution.
.LINK
    https://github.com/royklo/InforcerCommunity/blob/main/docs/CMDLET-REFERENCE.md#get-inforcertenantdocumentation
.LINK
    Connect-Inforcer
#>
function Get-InforcerTenantDocumentation {
[CmdletBinding()]
[OutputType([void])]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Html', 'Markdown', 'Json', 'Csv')]
    [string[]]$Format = @('Html'),

    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [Alias('ClientTenantId')]
    [object]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = '.',

    [Parameter(Mandatory = $false)]
    [string]$SettingsCatalogPath
)

if (-not (Test-InforcerSession)) {
    Write-Error -Message 'Not connected yet. Please run Connect-Inforcer first.' `
        -ErrorId 'NotConnected' -Category ConnectionError
    return
}

try {
    $clientTenantId = Resolve-InforcerTenantId -TenantId $TenantId
} catch {
    Write-Error -Message $_.Exception.Message -ErrorId 'InvalidTenantId' -Category InvalidArgument
    return
}

# Settings.json discovery chain (D-06, D-07, D-08):
# 1. Explicit -SettingsCatalogPath parameter
# 2. Bundled module/data/settings.json
# 3. Sibling IntuneSettingsCatalogViewer repo
# 4. Not found - warn and proceed without resolution
$resolvedCatalogPath = $SettingsCatalogPath
if ([string]::IsNullOrEmpty($resolvedCatalogPath)) {
    $bundled = Join-Path $PSScriptRoot '..' 'data' 'settings.json'
    $bundled = [System.IO.Path]::GetFullPath($bundled)
    if (Test-Path -LiteralPath $bundled) { $resolvedCatalogPath = $bundled }
}
if ([string]::IsNullOrEmpty($resolvedCatalogPath)) {
    $sibling = Join-Path $PSScriptRoot '..' '..' '..' 'IntuneSettingsCatalogViewer' 'data' 'settings.json'
    $sibling = [System.IO.Path]::GetFullPath($sibling)
    if (Test-Path -LiteralPath $sibling) { $resolvedCatalogPath = $sibling }
}
if ([string]::IsNullOrEmpty($resolvedCatalogPath)) {
    Write-Warning 'Settings catalog (settings.json) not found. Settings Catalog policies will show raw settingDefinitionId values.'
}

# Collect data from the 3 source cmdlets and build DocModel
$docDataParams = @{ TenantId = $clientTenantId }
if (-not [string]::IsNullOrEmpty($resolvedCatalogPath)) {
    $docDataParams['SettingsCatalogPath'] = $resolvedCatalogPath
}
$docData = Get-InforcerDocData @docDataParams
if ($null -eq $docData) { return }

$docModel = ConvertTo-InforcerDocModel -DocData $docData
if ($null -eq $docModel) { return }

# Render each requested format and write to disk
$extensionMap = @{ Html = 'html'; Markdown = 'md'; Json = 'json'; Csv = 'csv' }

foreach ($fmt in $Format) {
    $ext = $extensionMap[$fmt]

    if ($Format.Count -eq 1 -and [System.IO.Path]::HasExtension($OutputPath)) {
        $filePath = $OutputPath
    } else {
        $safeName = $docModel.TenantName -replace '[^\w\-]', '-'
        $filePath = Join-Path $OutputPath "$safeName-Documentation.$ext"
    }

    $parentDir = Split-Path -Parent $filePath
    if (-not [string]::IsNullOrEmpty($parentDir) -and -not (Test-Path -LiteralPath $parentDir)) {
        [void](New-Item -ItemType Directory -Force -Path $parentDir)
    }

    $content = switch ($fmt) {
        'Html'     { ConvertTo-InforcerHtml     -DocModel $docModel }
        'Markdown' { ConvertTo-InforcerMarkdown -DocModel $docModel }
        'Json'     { ConvertTo-InforcerDocJson  -DocModel $docModel }
        'Csv'      { ConvertTo-InforcerDocCsv   -DocModel $docModel }
    }

    Set-Content -Path $filePath -Value $content -Encoding UTF8
    Write-Verbose "Wrote $fmt documentation to: $filePath"
}
}
