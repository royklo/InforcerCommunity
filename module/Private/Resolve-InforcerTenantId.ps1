function Resolve-InforcerTenantId {
    <#
    .SYNOPSIS
        Resolves a tenant ID (GUID or numeric) to client tenant ID (integer).
    .DESCRIPTION
        If the value is a numeric string or integer, returns it as int.
        If it is a GUID (Microsoft Tenant ID), resolves to client tenant ID using -TenantData when provided,
        otherwise calls the API to fetch tenants.
    .PARAMETER TenantId
        Client Tenant ID (integer) or Microsoft Tenant ID (GUID string).
    .PARAMETER TenantData
        Optional. Pre-fetched array of tenant objects (e.g. from GET /beta/tenants). When provided and TenantId is a GUID,
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

        $guidResult = [guid]::Empty
        if ([guid]::TryParse($tenantIdString, [ref]$guidResult)) {
            Write-Verbose "Microsoft Tenant ID (GUID) detected: $tenantIdString. Looking up client tenant ID..."
            $tenantsToUse = $TenantData
            if ($null -eq $tenantsToUse -or $tenantsToUse.Count -eq 0) {
                $tenantsToUse = @(Invoke-InforcerApiRequest -Endpoint '/beta/tenants' -Method GET -OutputType PowerShellObject)
            }
            $tenants = if ($tenantsToUse -is [array]) { $tenantsToUse } else { @($tenantsToUse) }
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

        $parsedInt = 0
        if ([int]::TryParse($tenantIdString, [ref]$parsedInt)) {
            $resolved = $parsedInt
            Write-Verbose "Client Tenant ID detected: $resolved"
            return $resolved
        }

        throw [System.ArgumentException]::new(
            "Invalid TenantId format. Must be either a numeric Client Tenant ID or a Microsoft Tenant ID GUID. Received: $tenantIdString",
            'TenantId'
        )
    }
}
