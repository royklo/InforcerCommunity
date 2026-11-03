function Resolve-InforcerTenantId {
    <#
    .SYNOPSIS
        Resolves a tenant identifier to the id the current API expects.
    .DESCRIPTION
        API-key session (beta): accepts a numeric Client Tenant ID, a Microsoft Tenant ID (GUID) or a
        tenant name, and returns the Client Tenant ID as [int].
        Client-credentials session (v1): accepts a Microsoft Tenant ID (GUID) or a tenant name, and
        returns the Microsoft Tenant ID as a string. Numeric ids exist only on the beta API and are
        refused with ErrorId TenantIdNumericNotSupportedOnV1.
        Names match tenantFriendlyName or tenantDnsName, case-insensitive.
    .PARAMETER TenantId
        Client Tenant ID (beta only), Microsoft Tenant ID (GUID), or tenant name.
    .PARAMETER TenantData
        Optional pre-fetched tenant objects. When provided, resolution uses them instead of
        Get-InforcerTenantList.
    .OUTPUTS
        System.Int32 (beta) or System.String (v1).
    #>
    [CmdletBinding()]
    [OutputType([int], [string])]
    param(
        [Parameter(Mandatory = $true, ValueFromPipeline = $true, ValueFromPipelineByPropertyName = $true)]
        [object]$TenantId,

        [Parameter(Mandatory = $false)]
        [object[]]$TenantData
    )

    process {
        $isV1 = $script:InforcerSession -and $script:InforcerSession.ApiVersion -eq 'v1'
        $tenantIdString = $TenantId.ToString().Trim()

        $parsedInt = 0
        if ([int]::TryParse($tenantIdString, [ref]$parsedInt)) {
            if ($isV1) {
                throw ([System.Management.Automation.ErrorRecord]::new(
                    [System.ArgumentException]::new("Numeric tenant id '$tenantIdString' only works when you connect with an API key. With client credentials, pass the Microsoft tenant ID (GUID) or the tenant name; run Get-InforcerTenant to list them."),
                    'TenantIdNumericNotSupportedOnV1',
                    [System.Management.Automation.ErrorCategory]::InvalidArgument,
                    $TenantId))
            }
            Write-Verbose "Client Tenant ID detected: $parsedInt"
            return $parsedInt
        }

        $guidResult = [guid]::Empty
        $isGuid = [guid]::TryParse($tenantIdString, [ref]$guidResult)
        if ($isGuid -and $isV1) {
            Write-Verbose "Microsoft Tenant ID (GUID) detected: $guidResult"
            return $guidResult.ToString()
        }

        $tenants = if ($null -ne $TenantData -and $TenantData.Count -gt 0) { $TenantData } else { @(Get-InforcerTenantList) }

        if ($isGuid) {
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

        Write-Verbose "Tenant name detected: '$tenantIdString'. Looking up by name..."
        $foundTenants = [System.Collections.Generic.List[object]]::new()
        foreach ($t in $tenants) {
            $props = $t.PSObject.Properties
            $friendlyName = $props['tenantFriendlyName'].Value
            if ($null -eq $friendlyName) { $friendlyName = $props['name'].Value }
            $dnsName = $props['tenantDnsName'].Value
            if ($null -eq $dnsName) { $dnsName = $props['dnsName'].Value }
            if (($friendlyName -and $friendlyName -eq $tenantIdString) -or
                ($dnsName -and $dnsName -eq $tenantIdString)) {
                $foundTenants.Add($t)
            }
        }

        if ($foundTenants.Count -eq 1) {
            $idProperty = if ($isV1) { 'msTenantId' } else { 'clientTenantId' }
            $resolvedId = $foundTenants[0].PSObject.Properties[$idProperty].Value
            if ($null -ne $resolvedId) {
                $resolved = if ($isV1) { $resolvedId.ToString() } else { [int]$resolvedId }
                Write-Verbose "Found tenant '$tenantIdString'. Tenant ID: $resolved"
                return $resolved
            }
        }

        if ($foundTenants.Count -gt 1) {
            # Don't list the matching tenants' ids: in shared-MSP setups that reveals other accounts.
            $count = $foundTenants.Count
            $idHint = if ($isV1) { 'Microsoft tenant ID (GUID)' } else { 'numeric Client Tenant ID' }
            throw [System.InvalidOperationException]::new("$count tenants match name '$tenantIdString'. Pass the $idHint for the one you want; run Get-InforcerTenant to list available tenants.")
        }

        throw [System.InvalidOperationException]::new("No tenant found with name '$tenantIdString'. Use Get-InforcerTenant to list available tenants.")
    }
}
