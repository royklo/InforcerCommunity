function Get-InforcerDocData {
    <#
    .SYNOPSIS
        Collects raw data from existing Inforcer cmdlets for documentation generation.
    .DESCRIPTION
        Calls Get-InforcerTenant, Get-InforcerBaseline, and Get-InforcerTenantPolicies
        with -OutputType JsonObject and returns a hashtable bundle of deserialized data.
        This is Stage 1 of the documentation pipeline -- no normalization, just collection.
    .PARAMETER TenantId
        Tenant to collect data for. Accepts numeric ID, GUID, or tenant name.
    .PARAMETER SettingsCatalogPath
        Optional path to settings.json. Defaults to module/data/settings.json.
    .OUTPUTS
        Hashtable with keys: Tenant, Baselines, Policies, TenantId, CollectedAt
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$TenantId,

        [Parameter()]
        [string]$SettingsCatalogPath
    )

    # Session guard (per DATA-01/02/03 -- all 3 cmdlets require session)
    if (-not (Test-InforcerSession)) {
        Write-Error -Message 'Not connected yet. Please run Connect-Inforcer first.' -ErrorId 'NotConnected' -Category ConnectionError
        return
    }

    # Resolve TenantId (reuse existing helper)
    try {
        $clientTenantId = Resolve-InforcerTenantId -TenantId $TenantId
    } catch {
        Write-Error -Message $_.Exception.Message -ErrorId 'InvalidTenantId' -Category InvalidArgument
        return
    }

    # Load Settings Catalog (per SCAT-05 -- loads once, caches in $script: scope)
    $catalogParams = @{}
    if (-not [string]::IsNullOrEmpty($SettingsCatalogPath)) {
        $catalogParams['Path'] = $SettingsCatalogPath
    }
    Import-InforcerSettingsCatalog @catalogParams

    # Collect data from all 3 cmdlets (per DATA-01, DATA-02, DATA-03)
    Write-Verbose 'Collecting tenant data...'
    $tenantJson = Get-InforcerTenant -OutputType JsonObject
    $tenants = $tenantJson | ConvertFrom-Json -Depth 100

    Write-Verbose 'Collecting baseline data...'
    $baselineJson = Get-InforcerBaseline -OutputType JsonObject
    $baselines = $baselineJson | ConvertFrom-Json -Depth 100

    Write-Verbose 'Collecting tenant policies...'
    $policiesJson = Get-InforcerTenantPolicies -TenantId $clientTenantId -OutputType JsonObject
    $policies = $policiesJson | ConvertFrom-Json -Depth 100

    # Find the specific tenant from the tenant list
    $tenant = $tenants | Where-Object { $_.clientTenantId -eq $clientTenantId }
    if ($null -eq $tenant -and $tenants.Count -gt 0) {
        $tenant = $tenants[0]
    }

    @{
        Tenant      = $tenant
        Baselines   = $baselines
        Policies    = $policies
        TenantId    = $clientTenantId
        CollectedAt = [datetime]::UtcNow
    }
}
