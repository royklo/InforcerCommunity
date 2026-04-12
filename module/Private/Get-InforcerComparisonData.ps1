function Get-InforcerComparisonData {
    <#
    .SYNOPSIS
        Fetches and normalizes data from two tenants for comparison.
    .DESCRIPTION
        Stage 1 of the Compare-InforcerEnvironments pipeline. Collects data from both
        environments via Get-InforcerDocData and normalizes through ConvertTo-InforcerDocModel
        with -ComparisonMode, producing two DocModels ready for diffing.
    .PARAMETER SourceTenantId
        Source tenant identifier. Accepts numeric ID, GUID, or tenant name.
    .PARAMETER DestinationTenantId
        Destination tenant identifier. Accepts numeric ID, GUID, or tenant name.
    .PARAMETER SourceSession
        Inforcer session hashtable for the source tenant. Defaults to $script:InforcerSession.
    .PARAMETER DestinationSession
        Inforcer session hashtable for the destination tenant. Defaults to $script:InforcerSession.
    .PARAMETER SettingsCatalogPath
        Optional explicit path to settings.json. Auto-discovers if omitted.
    .PARAMETER IncludingAssignments
        When specified, policy assignment data is included in the collected policies.
    .PARAMETER FetchGraphData
        When specified, connects to Microsoft Graph to resolve group ObjectIDs and assignment
        filter IDs to friendly display names. Requires Microsoft.Graph.Authentication module
        and interactive sign-in for each tenant.
    .OUTPUTS
        Hashtable with keys: SourceModel, DestinationModel, SourceName, DestinationName,
        IncludingAssignments, CollectedAt
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$SourceTenantId,

        [Parameter(Mandatory)]
        [object]$DestinationTenantId,

        [Parameter()]
        [hashtable]$SourceSession,

        [Parameter()]
        [hashtable]$DestinationSession,

        [Parameter()]
        [string]$SettingsCatalogPath,

        [Parameter()]
        [switch]$IncludingAssignments,

        [Parameter()]
        [switch]$FetchGraphData
    )

    if ($null -eq $SourceSession) { $SourceSession = $script:InforcerSession }
    if ($null -eq $DestinationSession) { $DestinationSession = $script:InforcerSession }

    $originalSession = $script:InforcerSession

    $docDataParams = @{}
    if (-not [string]::IsNullOrEmpty($SettingsCatalogPath)) {
        $docDataParams['SettingsCatalogPath'] = $SettingsCatalogPath
    }

    try {
        # ── Source ──
        Write-Host 'Collecting source tenant data...' -ForegroundColor Gray
        $script:InforcerSession = $SourceSession
        $sourceDocData = Get-InforcerDocData -TenantId $SourceTenantId @docDataParams
        if ($null -eq $sourceDocData -or $null -eq $sourceDocData.Policies) {
            Write-Error -Message "Failed to collect data for source tenant '$SourceTenantId'. The API may be unavailable — try again later." `
                -ErrorId 'SourceDataCollectionFailed' -Category ConnectionError
            return $null
        }

        # ── Destination ──
        Write-Host 'Collecting destination tenant data...' -ForegroundColor Gray
        $script:InforcerSession = $DestinationSession
        $destDocData = Get-InforcerDocData -TenantId $DestinationTenantId @docDataParams
        if ($null -eq $destDocData -or $null -eq $destDocData.Policies) {
            Write-Error -Message "Failed to collect data for destination tenant '$DestinationTenantId'. The API may be unavailable — try again later." `
                -ErrorId 'DestDataCollectionFailed' -Category ConnectionError
            return $null
        }
    } finally {
        $script:InforcerSession = $originalSession
    }

    # ── Graph enrichment (resolve group names and assignment filters) ──
    $srcGraphMaps = @{ GroupNameMap = $null; FilterMap = $null; ScopeTagMap = $null }
    $dstGraphMaps = @{ GroupNameMap = $null; FilterMap = $null; ScopeTagMap = $null }

    if ($FetchGraphData) {
        Write-Host 'Connecting to Microsoft Graph for assignment resolution...' -ForegroundColor Cyan

        # Always sign in separately for each tenant to ensure correct Azure AD context
        $srcTenantName = if ($sourceDocData.Tenant.tenantFriendlyName) { $sourceDocData.Tenant.tenantFriendlyName } else { $SourceTenantId }
        $dstTenantName = if ($destDocData.Tenant.tenantFriendlyName) { $destDocData.Tenant.tenantFriendlyName } else { $DestinationTenantId }

        Write-Host "  Sign in for SOURCE tenant: $srcTenantName" -ForegroundColor Yellow
        $srcGraphMaps = Resolve-InforcerGraphEnrichment -DocData $sourceDocData -Label "Source ($srcTenantName)"

        Write-Host "  Sign in for DESTINATION tenant: $dstTenantName" -ForegroundColor Yellow
        $dstGraphMaps = Resolve-InforcerGraphEnrichment -DocData $destDocData -Label "Destination ($dstTenantName)"
    }

    # ── Build DocModels ──
    $srcModelParams = @{ DocData = $sourceDocData; ComparisonMode = $true }
    if ($srcGraphMaps.GroupNameMap) { $srcModelParams['GroupNameMap'] = $srcGraphMaps.GroupNameMap }
    if ($srcGraphMaps.FilterMap)    { $srcModelParams['FilterMap']    = $srcGraphMaps.FilterMap }
    if ($srcGraphMaps.ScopeTagMap)  { $srcModelParams['ScopeTagMap']  = $srcGraphMaps.ScopeTagMap }
    $sourceModel = ConvertTo-InforcerDocModel @srcModelParams

    $dstModelParams = @{ DocData = $destDocData; ComparisonMode = $true }
    if ($dstGraphMaps.GroupNameMap) { $dstModelParams['GroupNameMap'] = $dstGraphMaps.GroupNameMap }
    if ($dstGraphMaps.FilterMap)    { $dstModelParams['FilterMap']    = $dstGraphMaps.FilterMap }
    if ($dstGraphMaps.ScopeTagMap)  { $dstModelParams['ScopeTagMap']  = $dstGraphMaps.ScopeTagMap }
    $destModel = ConvertTo-InforcerDocModel @dstModelParams

    @{
        SourceModel          = $sourceModel
        DestinationModel     = $destModel
        SourceName           = $sourceModel.TenantName
        DestinationName      = $destModel.TenantName
        IncludingAssignments = $IncludingAssignments.IsPresent
        CollectedAt          = [datetime]::UtcNow
    }
}
