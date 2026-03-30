function Resolve-InforcerTenantId {
    <#
    .SYNOPSIS
        Resolves a tenant identifier to client tenant ID (integer).
    .DESCRIPTION
        Accepts a numeric Client Tenant ID, a Microsoft Tenant ID (GUID), or a tenant name
        (matched against tenantFriendlyName and tenantDnsName, case-insensitive).
        Returns the resolved client tenant ID as an integer.
    .PARAMETER TenantId
        Client Tenant ID (integer), Microsoft Tenant ID (GUID), or tenant name (string).
    .PARAMETER TenantData
        Optional. Pre-fetched array of tenant objects (e.g. from GET /beta/tenants). When provided,
        resolution is done from this data instead of calling the API.
    .OUTPUTS
        System.Int32 - The resolved client tenant ID.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [object]$TenantId,

        [Parameter(Mandatory = $false)]
        [object[]]$TenantData
    )

    process {
        $tenantIdString = $TenantId.ToString().Trim()

        # Numeric Client Tenant ID — return directly
        if ($tenantIdString -match '^\d+$') {
            $resolved = [int]$tenantIdString
            Write-Verbose "Client Tenant ID detected: $resolved"
            return $resolved
        }

        # GUID or tenant name — both require tenant list lookup
        $tenantsToUse = $TenantData
        if ($null -eq $tenantsToUse -or $tenantsToUse.Count -eq 0) {
            $tenantsToUse = @(Invoke-InforcerApiRequest -Endpoint '/beta/tenants' -Method GET -OutputType PowerShellObject)
        }
        $tenants = if ($tenantsToUse -is [array]) { $tenantsToUse } else { @($tenantsToUse) }

        # GUID — match on msTenantId
        if ($tenantIdString -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
            Write-Verbose "Microsoft Tenant ID (GUID) detected: $tenantIdString. Looking up client tenant ID..."
            foreach ($t in $tenants) {
                $msId = $t.PSObject.Properties['msTenantId'].Value
                if ($msId -and $msId.ToString() -eq $tenantIdString) {
                    $clientId = $t.PSObject.Properties['clientTenantId'].Value
                    if ($null -ne $clientId) {
                        $resolved = [int]$clientId
                        Write-Verbose "Found matching tenant. Client Tenant ID: $resolved"
                        return $resolved
                    }
                }
            }
            throw [System.InvalidOperationException]::new("No tenant found with Microsoft Tenant ID: $tenantIdString")
        }

        # Tenant name — match on tenantFriendlyName or tenantDnsName (case-insensitive)
        Write-Verbose "Tenant name detected: '$tenantIdString'. Looking up by name..."
        $foundTenants = @()
        foreach ($t in $tenants) {
            $friendlyName = $t.PSObject.Properties['tenantFriendlyName'].Value
            $dnsName = $t.PSObject.Properties['tenantDnsName'].Value
            if (($friendlyName -and $friendlyName -eq $tenantIdString) -or
                ($dnsName -and $dnsName -eq $tenantIdString)) {
                $foundTenants += $t
            }
        }

        if ($foundTenants.Count -eq 1) {
            $clientId = $foundTenants[0].PSObject.Properties['clientTenantId'].Value
            if ($null -ne $clientId) {
                $resolved = [int]$clientId
                Write-Verbose "Found tenant '$tenantIdString'. Client Tenant ID: $resolved"
                return $resolved
            }
        }

        if ($foundTenants.Count -gt 1) {
            $ids = ($foundTenants | ForEach-Object { $_.PSObject.Properties['clientTenantId'].Value }) -join ', '
            throw [System.InvalidOperationException]::new("Multiple tenants match name '$tenantIdString' (IDs: $ids). Use the numeric Client Tenant ID instead.")
        }

        throw [System.InvalidOperationException]::new("No tenant found with name '$tenantIdString'. Use Get-InforcerTenant to list available tenants.")
    }
}
