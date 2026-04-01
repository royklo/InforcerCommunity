<#
.SYNOPSIS
    Generates comprehensive tenant documentation across all M365 products managed via Inforcer.
.DESCRIPTION
    Export-InforcerTenantDocumentation collects configuration data for the specified tenant by calling
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
.PARAMETER ResolveGroupNames
    When specified, connects to Microsoft Graph to resolve assignment group ObjectIDs to their
    display names. Requires the Microsoft.Graph.Groups module and an active Graph session
    (Connect-MgGraph). If Graph is not connected, falls back to raw ObjectIDs with a warning.
.OUTPUTS
    System.IO.FileInfo. Returns FileInfo objects for each exported file.
.EXAMPLE
    Export-InforcerTenantDocumentation -TenantId 482 -Format Html

    Writes Contoso-Documentation.html to the current directory.
.EXAMPLE
    Export-InforcerTenantDocumentation -TenantId 482 -Format Html,Markdown,Json,Csv -OutputPath C:\Reports

    Writes four documentation files to C:\Reports.
.EXAMPLE
    Export-InforcerTenantDocumentation -TenantId "Contoso" -Format Html -SettingsCatalogPath .\settings.json

    Uses an explicit settings.json path for Settings Catalog resolution.
.LINK
    https://github.com/royklo/InforcerCommunity/blob/main/docs/CMDLET-REFERENCE.md#export-inforcertenantdocumentation
.LINK
    Connect-Inforcer
#>
function Export-InforcerTenantDocumentation {
[CmdletBinding()]
[OutputType([System.IO.FileInfo])]
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
    [string]$SettingsCatalogPath,

    [Parameter(Mandatory = $false)]
    [switch]$ResolveGroupNames
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
Write-Host 'Collecting tenant data...' -ForegroundColor Cyan
$docDataParams = @{ TenantId = $clientTenantId }
if (-not [string]::IsNullOrEmpty($resolvedCatalogPath)) {
    $docDataParams['SettingsCatalogPath'] = $resolvedCatalogPath
}
$docData = Get-InforcerDocData @docDataParams
if ($null -eq $docData) { return }

Write-Host 'Building documentation model...' -ForegroundColor Cyan
$docModel = ConvertTo-InforcerDocModel -DocData $docData
if ($null -eq $docModel) { return }

$policyCount = 0
foreach ($product in $docModel.Products.Values) {
    foreach ($policies in $product.Categories.Values) { $policyCount += @($policies).Count }
}
Write-Host "  Found $policyCount policies across $($docModel.Products.Count) products" -ForegroundColor Gray

# Resolve group ObjectIDs to display names via Microsoft Graph
if ($ResolveGroupNames) {
    Write-Host 'Resolving group names via Microsoft Graph...' -ForegroundColor Cyan

    # Check Graph availability
    $graphAvailable = $false
    if (Get-Module -ListAvailable -Name 'Microsoft.Graph.Groups' -ErrorAction SilentlyContinue) {
        try {
            $ctx = Get-MgContext -ErrorAction Stop
            if ($null -ne $ctx) { $graphAvailable = $true }
        } catch {
            # Not connected
        }
    }

    if (-not $graphAvailable) {
        Write-Warning 'Microsoft Graph not available. Install Microsoft.Graph.Groups and run Connect-MgGraph first. Falling back to raw ObjectIDs.'
    } else {
        # Collect all unique group IDs across all assignments
        $groupIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($product in $docModel.Products.Values) {
            foreach ($policies in $product.Categories.Values) {
                foreach ($policy in @($policies)) {
                    foreach ($assignment in @($policy.Assignments)) {
                        $gid = $assignment.Group
                        if (-not [string]::IsNullOrWhiteSpace($gid) -and $gid -match '^[0-9a-f]{8}-') {
                            [void]$groupIds.Add($gid)
                        }
                    }
                }
            }
        }

        if ($groupIds.Count -gt 0) {
            Write-Host "  Resolving $($groupIds.Count) unique group IDs..." -ForegroundColor Gray
            $groupNameMap = @{}
            foreach ($gid in $groupIds) {
                try {
                    $group = Get-MgGroup -GroupId $gid -Property 'displayName' -ErrorAction Stop
                    $groupNameMap[$gid] = $group.DisplayName
                } catch {
                    $groupNameMap[$gid] = $gid  # Keep raw ID on failure
                }
            }

            # Replace group IDs in assignments with display names
            foreach ($product in $docModel.Products.Values) {
                foreach ($policies in $product.Categories.Values) {
                    foreach ($policy in @($policies)) {
                        foreach ($assignment in @($policy.Assignments)) {
                            $gid = $assignment.Group
                            if ($groupNameMap.ContainsKey($gid)) {
                                $assignment.Group = $groupNameMap[$gid]
                            }
                        }
                    }
                }
            }
            Write-Host "  Resolved $($groupNameMap.Count) group names" -ForegroundColor Gray
        }
    }
}

# Render each requested format and write to disk
$extensionMap = @{ Html = 'html'; Markdown = 'md'; Json = 'json'; Csv = 'csv' }
$formatIndex = 0

foreach ($fmt in $Format) {
    $formatIndex++
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

    Write-Host "Rendering $fmt ($formatIndex/$($Format.Count))..." -ForegroundColor Cyan
    $content = switch ($fmt) {
        'Html'     { ConvertTo-InforcerHtml     -DocModel $docModel }
        'Markdown' { ConvertTo-InforcerMarkdown -DocModel $docModel }
        'Json'     { ConvertTo-InforcerDocJson  -DocModel $docModel }
        'Csv'      { ConvertTo-InforcerDocCsv   -DocModel $docModel }
    }

    Set-Content -Path $filePath -Value $content -Encoding UTF8
    $fileInfo = Get-Item -LiteralPath $filePath
    $sizeKb = [math]::Round($fileInfo.Length / 1KB, 1)
    Write-Host "  Exported: $filePath ($sizeKb KB)" -ForegroundColor Green
    $fileInfo
}

# Auto-open HTML output in the default browser (cross-platform)
$htmlFile = $Format | Where-Object { $_ -eq 'Html' } | ForEach-Object {
    $safeName = $docModel.TenantName -replace '[^\w\-]', '-'
    if ($Format.Count -eq 1 -and [System.IO.Path]::HasExtension($OutputPath)) { $OutputPath }
    else { Join-Path $OutputPath "$safeName-Documentation.html" }
}
if ($htmlFile -and (Test-Path -LiteralPath $htmlFile)) {
    $fullHtmlPath = (Resolve-Path -LiteralPath $htmlFile).Path
    if ($IsMacOS) { Start-Process 'open' -ArgumentList $fullHtmlPath }
    elseif ($IsWindows) { Start-Process $fullHtmlPath }
    elseif ($IsLinux) { Start-Process 'xdg-open' -ArgumentList $fullHtmlPath }
}

Write-Host "Done. $($Format.Count) file(s) exported for tenant '$($docModel.TenantName)'." -ForegroundColor Cyan
}
