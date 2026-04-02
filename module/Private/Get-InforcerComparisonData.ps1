function Get-InforcerComparisonData {
    <#
    .SYNOPSIS
        Fetches policies from two environments (tenants or baselines) for comparison.
    .DESCRIPTION
        Stage 1 of the Compare-InforcerEnvironments pipeline. Collects raw policy data from
        a source and destination environment by swapping $script:InforcerSession as needed to
        support cross-account comparison. Sessions are always restored in a finally block.

        Each environment can be identified as a tenant (via TenantId) or a baseline (via
        BaselineId). When a baseline is specified, the function resolves the baseline to its
        owning tenant and fetches that tenant's policies.

        The Settings Catalog is loaded once, session-independently, before any API calls.
    .PARAMETER SourceTenantId
        Source environment tenant identifier. Accepts numeric ID, GUID, or tenant name.
        Mutually exclusive intent with SourceBaselineId (specify one or the other per side).
    .PARAMETER DestinationTenantId
        Destination environment tenant identifier. Accepts numeric ID, GUID, or tenant name.
    .PARAMETER SourceBaselineId
        Source environment baseline identifier. Accepts a baseline GUID or friendly name.
        When specified, the baseline's owning tenant policies are fetched.
    .PARAMETER DestinationBaselineId
        Destination environment baseline identifier. Accepts a baseline GUID or friendly name.
    .PARAMETER SourceSession
        Inforcer session hashtable for the source environment. When omitted, defaults to
        the current $script:InforcerSession.
    .PARAMETER DestinationSession
        Inforcer session hashtable for the destination environment. When omitted, defaults to
        the current $script:InforcerSession.
    .PARAMETER SettingsCatalogPath
        Optional explicit path to settings.json. When omitted, the catalog is resolved
        automatically via Get-InforcerSettingsCatalogPath (auto-download with 24h TTL).
    .PARAMETER IncludingAssignments
        When specified, policy assignment data is included in the collected policies.
    .OUTPUTS
        Hashtable with keys: SourcePolicies, DestinationPolicies, SourceName, DestinationName,
        SourceType, DestinationType, SettingsCatalog, IncludingAssignments, CollectedAt
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [object]$SourceTenantId,

        [Parameter()]
        [object]$DestinationTenantId,

        [Parameter()]
        [string]$SourceBaselineId,

        [Parameter()]
        [string]$DestinationBaselineId,

        [Parameter()]
        [hashtable]$SourceSession,

        [Parameter()]
        [hashtable]$DestinationSession,

        [Parameter()]
        [string]$SettingsCatalogPath,

        [Parameter()]
        [switch]$IncludingAssignments
    )

    # Default sessions to $script:InforcerSession if not provided
    if ($null -eq $SourceSession) {
        $SourceSession = $script:InforcerSession
    }
    if ($null -eq $DestinationSession) {
        $DestinationSession = $script:InforcerSession
    }

    # Load Settings Catalog once, session-independently
    $catalogParams = @{}
    if (-not [string]::IsNullOrEmpty($SettingsCatalogPath)) {
        $catalogParams['Path'] = $SettingsCatalogPath
    }
    Import-InforcerSettingsCatalog @catalogParams

    # Save original session for restoration in finally
    $originalSession = $script:InforcerSession

    $sourcePolicies   = $null
    $destPolicies     = $null
    $sourceName       = $null
    $destName         = $null
    $sourceType       = $null
    $destType         = $null

    try {
        # ── Source ──────────────────────────────────────────────────────────────
        Write-Host 'Collecting source environment data...' -ForegroundColor Gray
        $script:InforcerSession = $SourceSession

        if (-not [string]::IsNullOrEmpty($SourceBaselineId)) {
            # Baseline mode: resolve baseline → get its owning tenant → fetch policies
            $sourceType = 'Baseline'
            $resolvedSourceBaselineId = Resolve-InforcerBaselineId -BaselineId $SourceBaselineId

            $sourceBaselineJson = Get-InforcerBaseline -OutputType JsonObject
            $sourceBaselines    = $sourceBaselineJson | ConvertFrom-Json -Depth 100

            $sourceBaseline = $sourceBaselines | Where-Object { $_.id -eq $resolvedSourceBaselineId } | Select-Object -First 1
            if ($null -eq $sourceBaseline) {
                throw [System.InvalidOperationException]::new("Source baseline not found: $resolvedSourceBaselineId")
            }

            $sourceName            = $sourceBaseline.name
            $sourceBaselineTenant  = $sourceBaseline.baselineTenantId

            Write-Host "  Source baseline: $sourceName (tenant $sourceBaselineTenant)" -ForegroundColor Gray
            $sourcePoliciesJson = Get-InforcerTenantPolicies -TenantId $sourceBaselineTenant -OutputType JsonObject
            $sourcePolicies     = $sourcePoliciesJson | ConvertFrom-Json -Depth 100
        } else {
            # Tenant mode: resolve tenant ID → get tenant name → fetch policies
            $sourceType = 'Tenant'
            $resolvedSourceTenantId = Resolve-InforcerTenantId -TenantId $SourceTenantId

            $sourceTenantJson = Get-InforcerTenant -OutputType JsonObject
            $sourceTenants    = $sourceTenantJson | ConvertFrom-Json -Depth 100
            $sourceTenant     = $sourceTenants | Where-Object { $_.clientTenantId -eq $resolvedSourceTenantId } | Select-Object -First 1
            $sourceName = ''
            if ($sourceTenant) {
                $sourceName = $sourceTenant.tenantFriendlyName
                if ([string]::IsNullOrWhiteSpace($sourceName)) { $sourceName = $sourceTenant.tenantDnsName }
            }
            if ([string]::IsNullOrWhiteSpace($sourceName)) { $sourceName = "$resolvedSourceTenantId" }

            Write-Host "  Source tenant: $sourceName ($resolvedSourceTenantId)" -ForegroundColor Gray
            $sourcePoliciesJson = Get-InforcerTenantPolicies -TenantId $resolvedSourceTenantId -OutputType JsonObject
            $sourcePolicies     = $sourcePoliciesJson | ConvertFrom-Json -Depth 100
        }

        # ── Destination ──────────────────────────────────────────────────────────
        Write-Host 'Collecting destination environment data...' -ForegroundColor Gray
        $script:InforcerSession = $DestinationSession

        if (-not [string]::IsNullOrEmpty($DestinationBaselineId)) {
            # Baseline mode
            $destType = 'Baseline'
            $resolvedDestBaselineId = Resolve-InforcerBaselineId -BaselineId $DestinationBaselineId

            $destBaselineJson = Get-InforcerBaseline -OutputType JsonObject
            $destBaselines    = $destBaselineJson | ConvertFrom-Json -Depth 100

            $destBaseline = $destBaselines | Where-Object { $_.id -eq $resolvedDestBaselineId } | Select-Object -First 1
            if ($null -eq $destBaseline) {
                throw [System.InvalidOperationException]::new("Destination baseline not found: $resolvedDestBaselineId")
            }

            $destName           = $destBaseline.name
            $destBaselineTenant = $destBaseline.baselineTenantId

            Write-Host "  Destination baseline: $destName (tenant $destBaselineTenant)" -ForegroundColor Gray
            $destPoliciesJson = Get-InforcerTenantPolicies -TenantId $destBaselineTenant -OutputType JsonObject
            $destPolicies     = $destPoliciesJson | ConvertFrom-Json -Depth 100
        } else {
            # Tenant mode
            $destType = 'Tenant'
            $resolvedDestTenantId = Resolve-InforcerTenantId -TenantId $DestinationTenantId

            $destTenantJson = Get-InforcerTenant -OutputType JsonObject
            $destTenants    = $destTenantJson | ConvertFrom-Json -Depth 100
            $destTenant     = $destTenants | Where-Object { $_.clientTenantId -eq $resolvedDestTenantId } | Select-Object -First 1
            $destName = ''
            if ($destTenant) {
                $destName = $destTenant.tenantFriendlyName
                if ([string]::IsNullOrWhiteSpace($destName)) { $destName = $destTenant.tenantDnsName }
            }
            if ([string]::IsNullOrWhiteSpace($destName)) { $destName = "$resolvedDestTenantId" }

            Write-Host "  Destination tenant: $destName ($resolvedDestTenantId)" -ForegroundColor Gray
            $destPoliciesJson = Get-InforcerTenantPolicies -TenantId $resolvedDestTenantId -OutputType JsonObject
            $destPolicies     = $destPoliciesJson | ConvertFrom-Json -Depth 100
        }
    } finally {
        # Always restore the original session
        $script:InforcerSession = $originalSession
    }

    @{
        SourcePolicies       = @($sourcePolicies)
        DestinationPolicies  = @($destPolicies)
        SourceName           = $sourceName
        DestinationName      = $destName
        SourceType           = $sourceType
        DestinationType      = $destType
        SettingsCatalog      = $script:InforcerSettingsCatalog
        IncludingAssignments = $IncludingAssignments.IsPresent
        CollectedAt          = [datetime]::UtcNow
    }
}
