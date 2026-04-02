function Get-InforcerComparisonData {
    <#
    .SYNOPSIS
        Fetches policies from two tenants for comparison.
    .DESCRIPTION
        Stage 1 of the Compare-InforcerEnvironments pipeline. Collects all policies from
        a source and destination tenant via Get-InforcerTenantPolicies, swapping
        $script:InforcerSession as needed for cross-account comparison.
        Sessions are always restored in a finally block.
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
    .OUTPUTS
        Hashtable with keys: SourcePolicies, DestinationPolicies, SourceName, DestinationName,
        SettingsCatalog, IncludingAssignments, CollectedAt
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
        [switch]$IncludingAssignments
    )

    # Default sessions to $script:InforcerSession if not provided
    if ($null -eq $SourceSession) { $SourceSession = $script:InforcerSession }
    if ($null -eq $DestinationSession) { $DestinationSession = $script:InforcerSession }

    # Load Settings Catalog once, session-independently
    $catalogParams = @{}
    if (-not [string]::IsNullOrEmpty($SettingsCatalogPath)) {
        $catalogParams['Path'] = $SettingsCatalogPath
    }
    Import-InforcerSettingsCatalog @catalogParams

    # Helper: resolve tenant name with fallback chain
    function Resolve-TenantName {
        param([object]$TenantObj, [int]$TenantId)
        if ($null -eq $TenantObj) { return "$TenantId" }
        $name = $TenantObj.tenantFriendlyName
        if ([string]::IsNullOrWhiteSpace($name)) { $name = $TenantObj.tenantDnsName }
        if ([string]::IsNullOrWhiteSpace($name)) { $name = "$TenantId" }
        return $name
    }

    # Save original session for restoration
    $originalSession = $script:InforcerSession

    try {
        # ── Source tenant ─────────────────────────────────────────────────────
        Write-Host 'Collecting source tenant data...' -ForegroundColor Gray
        $script:InforcerSession = $SourceSession

        $resolvedSourceId = Resolve-InforcerTenantId -TenantId $SourceTenantId
        $sourceTenantJson = Get-InforcerTenant -OutputType JsonObject
        $sourceTenants    = $sourceTenantJson | ConvertFrom-Json -Depth 100
        $sourceTenant     = $sourceTenants | Where-Object { $_.clientTenantId -eq $resolvedSourceId } | Select-Object -First 1
        $sourceName       = Resolve-TenantName -TenantObj $sourceTenant -TenantId $resolvedSourceId

        Write-Host "  Source: $sourceName ($resolvedSourceId)" -ForegroundColor Gray
        $sourcePoliciesJson = Get-InforcerTenantPolicies -TenantId $resolvedSourceId -OutputType JsonObject
        $sourcePolicies     = $sourcePoliciesJson | ConvertFrom-Json -Depth 100

        # ── Destination tenant ────────────────────────────────────────────────
        Write-Host 'Collecting destination tenant data...' -ForegroundColor Gray
        $script:InforcerSession = $DestinationSession

        $resolvedDestId = Resolve-InforcerTenantId -TenantId $DestinationTenantId
        $destTenantJson = Get-InforcerTenant -OutputType JsonObject
        $destTenants    = $destTenantJson | ConvertFrom-Json -Depth 100
        $destTenant     = $destTenants | Where-Object { $_.clientTenantId -eq $resolvedDestId } | Select-Object -First 1
        $destName       = Resolve-TenantName -TenantObj $destTenant -TenantId $resolvedDestId

        Write-Host "  Destination: $destName ($resolvedDestId)" -ForegroundColor Gray
        $destPoliciesJson = Get-InforcerTenantPolicies -TenantId $resolvedDestId -OutputType JsonObject
        $destPolicies     = $destPoliciesJson | ConvertFrom-Json -Depth 100

    } finally {
        $script:InforcerSession = $originalSession
    }

    @{
        SourcePolicies       = @($sourcePolicies)
        DestinationPolicies  = @($destPolicies)
        SourceName           = $sourceName
        DestinationName      = $destName
        SettingsCatalog      = $script:InforcerSettingsCatalog
        IncludingAssignments = $IncludingAssignments.IsPresent
        CollectedAt          = [datetime]::UtcNow
    }
}
