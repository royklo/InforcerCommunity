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

# Build Graph enrichment maps before DocModel (so assignments resolve during normalization)
if ($FetchGraphData) {
    # Extract Azure AD tenant GUID and friendly name for Graph sign-in
    $msTenantId = $null
    $tenantLabel = ''
    if ($docData.Tenant) {
        if ($docData.Tenant.PSObject.Properties['msTenantId']) { $msTenantId = $docData.Tenant.msTenantId }
        if ($docData.Tenant.PSObject.Properties['tenantFriendlyName'] -and $docData.Tenant.tenantFriendlyName) {
            $tenantLabel = " for $($docData.Tenant.tenantFriendlyName)"
        }
    }
    Write-Host "Connecting to Microsoft Graph$tenantLabel..." -ForegroundColor Cyan
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

        # Collect all unique group/role ObjectIDs from raw policy data
        $objectIds    = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $roleIds      = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $locationIds  = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $appIds       = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($policy in @($docData.Policies)) {
            # Standard Intune assignments
            $rawAssign = $policy.policyData.assignments
            if ($null -eq $rawAssign) { $rawAssign = $policy.assignments }
            if ($null -ne $rawAssign) {
                foreach ($a in @($rawAssign)) {
                    $t = $a.target; if ($null -eq $t) { $t = $a }
                    if ($t.groupId -and $t.groupId -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') {
                        [void]$objectIds.Add($t.groupId)
                    }
                }
            }

            # Conditional Access conditions — collect group and role IDs
            $conditions = $policy.policyData.conditions
            if ($null -ne $conditions -and $null -ne $conditions.users) {
                $caUsers = $conditions.users
                foreach ($prop in @('includeGroups', 'excludeGroups')) {
                    $ids = $caUsers.$prop
                    if ($ids) { foreach ($id in @($ids)) { if ($id -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') { [void]$objectIds.Add($id) } } }
                }
                foreach ($prop in @('includeRoles', 'excludeRoles')) {
                    $ids = $caUsers.$prop
                    if ($ids) { foreach ($id in @($ids)) { if ($id -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') { [void]$roleIds.Add($id) } } }
                }
            }
            if ($null -ne $conditions.locations) {
                $caLocations = $conditions.locations
                foreach ($prop in @('includeLocations', 'excludeLocations')) {
                    $ids = $caLocations.$prop
                    if ($ids) { foreach ($id in @($ids)) { if ($id -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') { [void]$locationIds.Add($id) } } }
                }
            }
            if ($null -ne $conditions.applications) {
                $caApps = $conditions.applications
                foreach ($prop in @('includeApplications', 'excludeApplications')) {
                    $ids = $caApps.$prop
                    if ($ids) { foreach ($id in @($ids)) { if ($id -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') { [void]$appIds.Add($id) } } }
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

        # Fetch directory role definitions for CA policy resolution
        $roleNameMap = @{}
        if ($roleIds.Count -gt 0) {
            Write-Host "  Resolving $($roleIds.Count) unique role IDs..." -ForegroundColor Gray
            $roleTemplates = Invoke-InforcerGraphRequest -Uri 'https://graph.microsoft.com/v1.0/directoryRoleTemplates'
            if ($roleTemplates) {
                foreach ($rt in $roleTemplates) { $roleNameMap[$rt.id] = $rt.displayName }
            }
            $resolvedRoles = @($roleIds | Where-Object { $roleNameMap.ContainsKey($_) }).Count
            Write-Host "  Resolved $resolvedRoles of $($roleIds.Count) role names" -ForegroundColor Gray
        }

        # Fetch named locations for CA policy resolution
        $locationNameMap = @{}
        if ($locationIds.Count -gt 0) {
            Write-Host "  Resolving $($locationIds.Count) unique named location IDs..." -ForegroundColor Gray
            $namedLocations = Invoke-InforcerGraphRequest -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/namedLocations'
            if ($namedLocations) {
                foreach ($nl in $namedLocations) { $locationNameMap[$nl.id] = $nl.displayName }
            }
            $resolvedLocations = @($locationIds | Where-Object { $locationNameMap.ContainsKey($_) }).Count
            Write-Host "  Resolved $resolvedLocations of $($locationIds.Count) named location names" -ForegroundColor Gray
        }

        # Resolve application IDs for CA policies (well-known + Graph fallback)
        $appNameMap = @{
            '0000000a-0000-0000-c000-000000000000' = 'Microsoft Intune'
            '00000002-0000-0000-c000-000000000000' = 'Azure Active Directory Graph (Legacy)'
            '00000002-0000-0ff1-ce00-000000000000' = 'Office 365 Exchange Online'
            '00000003-0000-0000-c000-000000000000' = 'Microsoft Graph'
            '00000003-0000-0ff1-ce00-000000000000' = 'Office 365 SharePoint Online'
            '00000004-0000-0ff1-ce00-000000000000' = 'Office 365 Skype for Business'
            '0000000c-0000-0000-c000-000000000000' = 'Microsoft App Access Panel'
            '00000007-0000-0000-c000-000000000000' = 'Dynamics CRM Online'
            '00000006-0000-0ff1-ce00-000000000000' = 'Microsoft Office 365 Portal'
            '00000009-0000-0000-c000-000000000000' = 'Power BI Service'
            '00000015-0000-0000-c000-000000000000' = 'Microsoft Dynamics ERP'
            '01cb2876-7ebd-4aa4-9cc9-d28bd4d359a9' = 'Microsoft Entra Internet Access / Global Secure Access'
            'd4ebce55-015a-49b5-a083-c84d1797ae8c' = 'Microsoft 365 / Office (Desktop Client)'
            'fc780465-2017-40d4-a0c5-307022471b92' = 'Windows Sign In'
            '04b07795-8ddb-461a-bbee-02f9e1bf7b46' = 'Azure CLI'
            '1950a258-227b-4e31-a9cf-717495945fc2' = 'Azure PowerShell'
            'fb78d390-0c51-40cd-8e17-fdbfab77341b' = 'Microsoft Exchange REST API'
            'de8bc8b5-d9f9-48b1-a8ad-b748da725064' = 'Microsoft Graph Command Line Tools'
            '1fec8e78-bce4-4aaf-ab1b-5451cc387264' = 'Microsoft Teams'
            'cc15fd57-2c6c-4117-a88c-83b1d56b4bbe' = 'Microsoft Teams Web Client'
            '27922004-5251-4030-b22d-91ecd9a37ea4' = 'Outlook Mobile'
            '4765445b-32c6-49b0-83e6-1d93765276ca' = 'Microsoft 365 Defender'
        }
        if ($appIds.Count -gt 0) {
            $unresolvedApps = @($appIds | Where-Object { -not $appNameMap.ContainsKey($_) })
            if ($unresolvedApps.Count -gt 0) {
                Write-Host "  Resolving $($unresolvedApps.Count) application IDs via Graph..." -ForegroundColor Gray
                foreach ($appId in $unresolvedApps) {
                    $sp = Invoke-InforcerGraphRequest -Uri "https://graph.microsoft.com/v1.0/servicePrincipals(appId='$appId')" -SingleObject
                    if ($sp -and $sp.displayName) {
                        $appNameMap[$appId] = $sp.displayName
                    }
                }
            }
            $resolvedApps = @($appIds | Where-Object { $appNameMap.ContainsKey($_) }).Count
            Write-Host "  Resolved $resolvedApps of $($appIds.Count) application names" -ForegroundColor Gray
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
if ($groupNameMap)              { $docModelParams['GroupNameMap']  = $groupNameMap }
if ($filterMap)                 { $docModelParams['FilterMap']     = $filterMap }
if ($roleNameMap)               { $docModelParams['RoleNameMap']   = $roleNameMap }
if ($locationNameMap)           { $docModelParams['LocationNameMap'] = $locationNameMap }
if ($appNameMap)                { $docModelParams['AppNameMap']    = $appNameMap }
if ($script:InforcerScopeTagMap) { $docModelParams['ScopeTagMap'] = $script:InforcerScopeTagMap }
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
    }

    $fileInfo = Get-Item -LiteralPath $filePath
    $sizeKb = [math]::Round($fileInfo.Length / 1KB, 1)
    Write-Host "  Exported: $filePath ($sizeKb KB)" -ForegroundColor Green
    $fileInfo
}

# Auto-open HTML output in the default browser (cross-platform)
$htmlFile = $Format | Where-Object { $_ -eq 'Html' } | ForEach-Object {
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
