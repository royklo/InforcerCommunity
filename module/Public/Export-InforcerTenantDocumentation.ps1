<#
.SYNOPSIS
    Generates comprehensive tenant documentation across all M365 products managed via Inforcer.
.DESCRIPTION
    Export-InforcerTenantDocumentation collects configuration data for the specified tenant by calling
    Get-InforcerBaseline, Get-InforcerTenant, and Get-InforcerTenantPolicies (each using
    -OutputType JsonObject), normalizes the raw API data into a format-agnostic DocModel via
    ConvertTo-InforcerDocModel, and renders the DocModel to one or more output formats.

    Intune Settings Catalog settingDefinitionIDs are resolved to friendly names and descriptions
    using a settings.json catalog sourced from the IntuneSettingsCatalogData GitHub repository.
    By default, the catalog is downloaded and cached at runtime (unless SettingsCatalogPath is
    provided). If the catalog cannot be loaded, Settings Catalog policies show raw
    settingDefinitionId values instead.

    Before calling this cmdlet, you must be connected via Connect-Inforcer. If no active session
    exists, the cmdlet emits a non-terminating error and returns immediately.

    Output files are written to the specified OutputPath directory and auto-named as
    {TenantName}-Documentation.{ext} (e.g., Contoso-Documentation.html).
.PARAMETER Format
    Output format(s) to generate. Accepted values: Html, Markdown, Excel. Multiple formats
    can be specified as a comma-separated list or array. Defaults to Html. Excel format
    creates an .xlsx workbook with one sheet per product (requires ImportExcel module).
.PARAMETER TenantId
    Tenant to document. Accepts a numeric ID, GUID, or tenant name. Required.
.PARAMETER OutputPath
    Directory to write output files to. Files are auto-named {TenantName}-Documentation.{ext}.
    When a single format is specified and this path has a file extension, it is treated as an
    explicit output file path. Defaults to the current directory.
.PARAMETER SettingsCatalogPath
    Path to a local settings.json file for Settings Catalog resolution. When omitted, the cmdlet
    automatically downloads and caches the latest data from the IntuneSettingsCatalogData GitHub
    repository (~65 MB, cached at ~/.inforcercommunity/data/settings.json with a 24-hour TTL).
    If download fails and no cached copy exists, Settings Catalog policies show raw
    settingDefinitionId values and a warning is emitted.
.PARAMETER FetchGraphData
    When specified, uses Invoke-MgGraphRequest to enrich the documentation with live data from
    Microsoft Graph. Currently resolves assignment group/user ObjectIDs to their display names
    via the /directoryObjects endpoint. Requires the Microsoft.Graph.Authentication module and
    an active Graph session (Connect-MgGraph). If Graph is not connected, falls back to raw
    ObjectIDs with a warning.
.PARAMETER Baseline
    Filter to only policies that belong to a specific baseline. Accepts a baseline GUID or
    friendly name (e.g., "Inforcer Blueprint Baseline - Tier 1 - Foundations"). Uses the
    Inforcer alignment details API to retrieve the list of policies in the baseline, then
    filters the documentation to only those policies. The baseline name is shown in the header.
.PARAMETER Tag
    Filter to only policies that have a specific Inforcer tag (e.g., "IAM - Core", "Tier 1").
    Matches against the tag name property on each policy (case-insensitive, contains match).
.OUTPUTS
    System.IO.FileInfo. Returns FileInfo objects for each exported file.
.EXAMPLE
    Export-InforcerTenantDocumentation -TenantId 482 -Format Html

    Writes Contoso-Documentation.html to the current directory.
.EXAMPLE
    Export-InforcerTenantDocumentation -TenantId 482 -Format Html,Markdown,Excel -OutputPath C:\Reports

    Writes three documentation files to C:\Reports.
.EXAMPLE
    Export-InforcerTenantDocumentation -TenantId "Contoso" -Format Html -SettingsCatalogPath .\settings.json

    Uses an explicit settings.json path for Settings Catalog resolution.
.EXAMPLE
    Export-InforcerTenantDocumentation -TenantId 139 -Baseline "Inforcer Blueprint Baseline - Tier 1 - Foundations" -Format Html

    Exports only the policies that belong to the specified baseline.
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
    [ValidateSet('Html', 'Markdown', 'Excel')]
    [string[]]$Format = @('Html'),

    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [Alias('ClientTenantId')]
    [object]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = '.',

    [Parameter(Mandatory = $false)]
    [string]$SettingsCatalogPath,

    [Parameter(Mandatory = $false)]
    [switch]$FetchGraphData,

    [Parameter(Mandatory = $false)]
    [string]$Baseline,

    [Parameter(Mandatory = $false)]
    [string]$Tag
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

# Settings catalog path: explicit override or auto-resolved via cache strategy
$resolvedCatalogPath = $SettingsCatalogPath

# Collect data from the 3 source cmdlets and build DocModel
Write-Host 'Collecting tenant data...' -ForegroundColor Cyan
$docDataParams = @{ TenantId = $clientTenantId }
if (-not [string]::IsNullOrEmpty($resolvedCatalogPath)) {
    $docDataParams['SettingsCatalogPath'] = $resolvedCatalogPath
}
$docData = Get-InforcerDocData @docDataParams
if ($null -eq $docData) { return }

# Filter to baseline policies if -Baseline specified
$baselineFilterName = $null
if (-not [string]::IsNullOrWhiteSpace($Baseline)) {
    Write-Host "Filtering to baseline: $Baseline" -ForegroundColor Cyan

    # Resolve baseline name to GUID
    $baselineGuid = $null
    $guidTest = [guid]::Empty
    if ([guid]::TryParse($Baseline.Trim(), [ref]$guidTest)) {
        $baselineGuid = $Baseline.Trim()
    } else {
        # Fetch baselines and resolve by name
        $allBaselines = @(Invoke-InforcerApiRequest -Endpoint '/beta/baselines' -Method GET -OutputType PowerShellObject)
        $baselineGuid = Resolve-InforcerBaselineId -BaselineId $Baseline -BaselineData $allBaselines
        # Find the baseline name for display
        foreach ($bl in $allBaselines) {
            if ($bl.id -eq $baselineGuid) { $baselineFilterName = $bl.name; break }
        }
    }
    if (-not $baselineFilterName) { $baselineFilterName = $Baseline }

    # Get alignment details to find which policies are in the baseline
    Write-Host '  Retrieving alignment details...' -ForegroundColor Gray
    $alignEndpoint = "/beta/tenants/$clientTenantId/alignmentDetails?customBaselineId=$baselineGuid"
    $alignResponse = Invoke-InforcerApiRequest -Endpoint $alignEndpoint -Method GET -OutputType PowerShellObject -ErrorAction SilentlyContinue

    if ($null -eq $alignResponse) {
        Write-Warning "Could not retrieve alignment details for baseline. Exporting all policies."
    } else {
        # Collect all policy names from all alignment status arrays
        $baselinePolicyNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $alignment = $alignResponse.alignment
        if ($null -ne $alignment) {
            $statusArrays = @('matchedPolicies', 'matchedWithAcceptedDeviations', 'deviatedUnaccepted', 'missingFromSubjectUnaccepted', 'additionalInSubjectUnaccepted')
            foreach ($arrayName in $statusArrays) {
                $arr = $alignment.PSObject.Properties[$arrayName]
                if ($arr -and $null -ne $arr.Value) {
                    foreach ($p in @($arr.Value)) {
                        if ($p -is [PSObject] -and $p.PSObject.Properties['policyName']) {
                            [void]$baselinePolicyNames.Add($p.policyName)
                        }
                    }
                }
            }
        }

        if ($baselinePolicyNames.Count -gt 0) {
            # Filter docData.Policies to only those in the baseline
            $originalCount = @($docData.Policies).Count
            $docData.Policies = @($docData.Policies | Where-Object {
                $name = $_.displayName
                if ([string]::IsNullOrWhiteSpace($name)) { $name = $_.friendlyName }
                if ([string]::IsNullOrWhiteSpace($name)) { $name = $_.name }
                $baselinePolicyNames.Contains($name)
            })
            Write-Host "  Filtered to $(@($docData.Policies).Count) of $originalCount policies in baseline" -ForegroundColor Gray
        } else {
            Write-Warning 'No policies found in baseline alignment data. Exporting all policies.'
        }
    }
}

# Filter by tag if -Tag specified
if (-not [string]::IsNullOrWhiteSpace($Tag)) {
    Write-Host "Filtering to tag: $Tag" -ForegroundColor Cyan
    $originalCount = @($docData.Policies).Count
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
}

# Build Graph enrichment maps before DocModel (so assignments resolve during normalization)
$groupNameMap = $null
$filterMap = $null
if ($FetchGraphData) {
    Write-Host 'Connecting to Microsoft Graph...' -ForegroundColor Cyan
    # Extract Azure AD tenant GUID from the Inforcer tenant data so Graph targets the correct tenant
    $msTenantId = $null
    if ($docData.Tenant -and $docData.Tenant.PSObject.Properties['msTenantId']) {
        $msTenantId = $docData.Tenant.msTenantId
    }
    $graphConnectParams = @{ RequiredScopes = @('Directory.Read.All') }
    if ($msTenantId) { $graphConnectParams['TenantId'] = $msTenantId }
    $graphCtx = Connect-InforcerGraph @graphConnectParams

    if (-not $graphCtx) {
        Write-Warning 'Microsoft Graph connection failed. Falling back to raw ObjectIDs.'
    } else {
        Write-Host "  Graph connected as: $($graphCtx.Account)" -ForegroundColor Green

        # Validate Graph is connected to the correct tenant
        if ($msTenantId -and $graphCtx.TenantId -and $graphCtx.TenantId -ne $msTenantId) {
            $tenantName = $docData.Tenant.tenantFriendlyName
            Write-Warning "Graph signed into tenant $($graphCtx.TenantId) but exporting tenant '$tenantName' ($msTenantId). Group names and filters may not resolve correctly."
            Write-Warning "Sign in with an account that has access to tenant '$tenantName' or skip -FetchGraphData."
        }

        # Collect all unique group ObjectIDs from raw policy data
        $objectIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($policy in @($docData.Policies)) {
            $rawAssign = $policy.policyData.assignments
            if ($null -eq $rawAssign) { $rawAssign = $policy.assignments }
            if ($null -eq $rawAssign) { continue }
            foreach ($a in @($rawAssign)) {
                $t = $a.target; if ($null -eq $t) { $t = $a }
                if ($t.groupId -and $t.groupId -match '^[0-9a-f]{8}-') {
                    [void]$objectIds.Add($t.groupId)
                }
            }
        }

        if ($objectIds.Count -gt 0) {
            Write-Host "  Resolving $($objectIds.Count) unique group/object IDs..." -ForegroundColor Gray
            $groupNameMap = @{}
            $resolved = 0
            foreach ($oid in $objectIds) {
                $obj = Invoke-InforcerGraphRequest -Uri "https://graph.microsoft.com/v1.0/directoryObjects/$oid" -SingleObject
                if ($obj -and $obj.displayName) {
                    $groupNameMap[$oid] = $obj.displayName
                    $resolved++
                } else {
                    $groupNameMap[$oid] = $oid
                }
            }
            Write-Host "  Resolved $resolved of $($objectIds.Count) group names" -ForegroundColor Gray
        }

        # Fetch assignment filters from Intune
        Write-Host '  Fetching assignment filters...' -ForegroundColor Gray
        $rawFilters = Invoke-InforcerGraphRequest -Uri 'https://graph.microsoft.com/beta/deviceManagement/assignmentFilters'
        $filterMap = @{}
        if ($rawFilters) {
            foreach ($f in $rawFilters) { $filterMap[$f.id] = $f }
            Write-Host "  Loaded $($filterMap.Count) assignment filters" -ForegroundColor Gray
        }

        # Fetch scope tags from Intune and build ID -> displayName map
        Write-Host '  Fetching scope tags...' -ForegroundColor Gray
        $rawScopeTags = Invoke-InforcerGraphRequest -Uri 'https://graph.microsoft.com/beta/deviceManagement/roleScopeTags'
        $script:InforcerScopeTagMap = @{}
        if ($rawScopeTags) {
            foreach ($st in $rawScopeTags) { $script:InforcerScopeTagMap[$st.id.ToString()] = $st.displayName }
            Write-Host "  Loaded $($script:InforcerScopeTagMap.Count) scope tags" -ForegroundColor Gray
        }
    }
}

Write-Host 'Building documentation model...' -ForegroundColor Cyan
$docModelParams = @{ DocData = $docData }
if ($groupNameMap)                   { $docModelParams['GroupNameMap'] = $groupNameMap }
if ($filterMap)                      { $docModelParams['FilterMap'] = $filterMap }
if ($script:InforcerScopeTagMap)     { $docModelParams['ScopeTagMap'] = $script:InforcerScopeTagMap }
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

# Render each requested format and write to disk
$extensionMap = @{ Html = 'html'; Markdown = 'md'; Excel = 'xlsx' }
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
    }

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
