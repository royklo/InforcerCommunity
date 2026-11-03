function Get-InforcerDocData {
    <#
    .SYNOPSIS
        Collects raw data from existing Inforcer cmdlets for documentation generation.
    .DESCRIPTION
        Calls Get-InforcerTenant -TenantId and Get-InforcerBaseline (-OutputType JsonObject, parsed
        back) and fetches the policies directly with Invoke-InforcerApiRequest -ObjectType Policy (the
        same raw objects, without a JSON round trip of the largest payload). Returns a hashtable bundle.
        This is Stage 1 of the documentation pipeline -- no normalization, just collection.
        Works with both login types. On v1, when the policies hold no Intune policy, it warns once
        and the bundle carries a Notes entry that the documents show.
    .PARAMETER TenantId
        Tenant to collect data for. Accepts numeric ID, GUID, or tenant name.
    .PARAMETER SettingsCatalogPath
        Optional path to a settings catalog JSON file. If omitted, the catalog path
        is resolved automatically at runtime via Get-InforcerSettingsCatalogPath.
    .OUTPUTS
        Hashtable with keys: Tenant ($null when it could not be loaded), Baselines, Policies,
        TenantId (int on beta, Microsoft tenant ID on v1), CollectedAt, and Notes (v1 only, when set).
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

    $isV1 = $script:InforcerSession.ApiVersion -eq 'v1'
    try {
        $resolvedTenantId = Resolve-InforcerTenantId -TenantId $TenantId
    } catch {
        Write-Error -Message $_.Exception.Message -ErrorId 'InvalidTenantId' -Category InvalidArgument
        return
    }

    # -TenantId returns this tenant only (the detailed object on v1), never another tenant's.
    Write-Verbose 'Collecting tenant data...'
    $tenantErr = @()
    $tenantJson = Get-InforcerTenant -TenantId $resolvedTenantId -OutputType JsonObject `
        -ErrorVariable tenantErr -ErrorAction SilentlyContinue
    $tenant = if ($tenantJson) { $tenantJson | ConvertFrom-Json -Depth 100 | Select-Object -First 1 } else { $null }

    Write-Verbose 'Collecting baseline data...'
    $baselineJson = Get-InforcerBaseline -OutputType JsonObject
    $baselines = $baselineJson | ConvertFrom-Json -Depth 100

    Write-Verbose 'Collecting tenant policies...'
    $policiesApiErr = @()
    $policies = @(Invoke-InforcerApiRequest -Endpoint "/tenants/$resolvedTenantId/policies" -Method GET `
        -OutputType PowerShellObject -ObjectType Policy -ErrorVariable policiesApiErr -ErrorAction SilentlyContinue)
    if ($policiesApiErr.Count -gt 0) {
        $errMsg = $policiesApiErr[-1].Exception.Message
        if ([string]::IsNullOrWhiteSpace($errMsg)) { $errMsg = $policiesApiErr[-1].ToString() }
        # Extract clean error details from the API response
        $statusCode = $null
        $activityId = $null
        if ($errMsg -match '"statusCode"\s*:\s*(\d+)') { $statusCode = $Matches[1] }
        if ($errMsg -match '"activityId"\s*:\s*"([^"]+)"') { $activityId = $Matches[1] }
        if ($errMsg -match '403|permission|forbidden') {
            Write-Error -Message "Failed to retrieve policies for tenant '$resolvedTenantId': access denied. Please check your Inforcer $(if ($isV1) { 'client' } else { 'API key' }) has permission to this tenant." `
                -ErrorId 'AccessDenied' -Category PermissionDenied
        } elseif ($errMsg -match '404|not found') {
            Write-Error -Message "Tenant '$resolvedTenantId' not found. Please verify the TenantId is correct." `
                -ErrorId 'TenantNotFound' -Category ObjectNotFound
        } elseif ($statusCode -eq '500') {
            $activityRef = if ($activityId) { " (Activity ID: $activityId)" } else { '' }
            Write-Error -Message "The Inforcer API returned a server error (HTTP 500) while retrieving policies for tenant '$resolvedTenantId'$activityRef. This is typically a temporary issue — please try again in a few minutes. If the problem persists, contact Inforcer support with the activity ID." `
                -ErrorId 'ServerError' -Category ResourceUnavailable
        } else {
            Write-Error -Message "Failed to retrieve policies for tenant '$resolvedTenantId'. Error: $errMsg" `
                -ErrorId 'PolicyRetrievalFailed' -Category InvalidOperation
        }
        return
    }
    $hasPolicies = $policies.Count -gt 0
    # Kept $null for an empty list, as the JSON round trip used to produce.
    if (-not $hasPolicies) { $policies = $null } elseif ($policies.Count -eq 1) { $policies = $policies[0] }

    if ($null -eq $tenant) {
        $reason = if ($tenantErr.Count -gt 0) { " $($tenantErr[-1].Exception.Message)" } else { '' }
        Write-Warning "Could not load details for tenant '$resolvedTenantId'; it is shown by its id.$reason"
    }

    $docData = @{
        Tenant      = $tenant
        Baselines   = $baselines
        Policies    = $policies
        TenantId    = $resolvedTenantId
        CollectedAt = [datetime]::UtcNow
    }
    if ($isV1 -and -not @($policies).Where({ $_.product -eq 'Intune' }, 'First')) {
        Write-Warning "The v1 API currently returns no Intune policies for this tenant (a known gap in inforcer's v1 API). Connecting with an API key still returns them."
        $docData['Notes'] = @('The inforcer v1 API (client-credentials login) currently returns no Intune policies and no Defender settings catalog policies, so they are missing here. Connect with an API key (Connect-Inforcer -ApiKey) to include them.')
    }
    $docData
}
