function Get-InforcerRole {
    <#
    .SYNOPSIS
        Retrieves directory role definitions from an Inforcer tenant.

        Required API scope(s): Tenants.Roles.Read + Tenants.Read (only when -TenantId is a GUID or tenant name)
        (API key); Entra Dashboard + Tenants (only for a tenant name) permission (API client, unconfirmed).

    .DESCRIPTION
        Gets the list of Entra ID directory role definitions for a tenant from the Inforcer API.
        Returns role definitions including display name, description, and whether the role is
        built-in, enabled, or privileged.

    .PARAMETER TenantId
        The Inforcer tenant ID. Accepts numeric ID (API-key login only), Microsoft tenant GUID, or tenant name. Supports pipeline input.

    .PARAMETER OutputType
        Output type: 'PowerShellObject' (default) or 'JsonObject'.
        JSON is always an array with client credentials. Piped tenants: each role carries TenantId and
        JsonObject returns one array for all tenants.

    .EXAMPLE
        Get-InforcerRole -TenantId 'Contoso'

        Lists all directory role definitions in the tenant Contoso.

    .EXAMPLE
        Get-InforcerRole -TenantId 'Contoso' | Where-Object IsPrivileged -eq $true

        Lists only privileged roles in the tenant Contoso.

    .EXAMPLE
        Get-InforcerTenant -TenantId 'Contoso' | Get-InforcerRole

        Lists all roles in the piped tenant.

    .EXAMPLE
        Get-InforcerRole -TenantId 'Contoso' -OutputType JsonObject

        Returns roles as a JSON string.

    .OUTPUTS
        PSObject or String (when -OutputType JsonObject)

    .LINK
        https://github.com/royklo/InforcerCommunity/blob/main/docs/CMDLET-REFERENCE.md#get-inforcerrole

    .LINK
        Connect-Inforcer
    #>
    [CmdletBinding()]
    [OutputType([PSObject], [string])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('ClientTenantId', 'MsTenantId')]
        [object]$TenantId,

        [Parameter(Mandatory = $false)]
        [ValidateSet('PowerShellObject', 'JsonObject')]
        [string]$OutputType = 'PowerShellObject'
    )

    begin { $pipedJson = [System.Collections.Generic.List[object]]::new() }

    process {
        if (-not (Test-InforcerSession)) {
            Write-Error -Message "Not connected to Inforcer. Use Connect-Inforcer first." -ErrorId 'NotConnected' -Category ConnectionError
            return
        }

        try {
            $resolvedTenantId = Resolve-InforcerTenantId -TenantId $TenantId
        } catch {
            Write-Error -Message $_.Exception.Message -ErrorId 'InvalidTenantId' -Category InvalidArgument
            return
        }

        $endpoint = "/tenants/$resolvedTenantId/roles"
        Write-Verbose "Retrieving role definitions for tenant $resolvedTenantId..."

        $isV1 = $script:InforcerSession.ApiVersion -eq 'v1'
        $piped = $PSCmdlet.MyInvocation.ExpectingInput
        $apiErr = $null
        $roleData = @(Invoke-InforcerApiRequest -Endpoint $endpoint -Method GET -OutputType PowerShellObject -ObjectType Role -ErrorVariable apiErr)
        if ($apiErr) { return }
        if ($piped) {
            foreach ($item in $roleData) {
                if ($item -is [PSObject] -and -not $item.PSObject.Properties['TenantId']) {
                    $item.PSObject.Properties.Add([System.Management.Automation.PSNoteProperty]::new('TenantId', $resolvedTenantId))
                }
            }
        }

        if ($OutputType -eq 'JsonObject') {
            if ($piped) { $pipedJson.AddRange([object[]]$roleData); return }
            if ($isV1) { return ConvertTo-Json -InputObject $roleData -Depth 100 }
            if ($roleData.Count -eq 0) { return }
            return ($roleData | ConvertTo-Json -Depth 100)
        }

        foreach ($item in $roleData) {
            if ($item -is [PSObject]) {
                $null = Add-InforcerPropertyAliases -InputObject $item -ObjectType Role
                $item.PSObject.TypeNames.Insert(0, 'InforcerCommunity.Role')
                $item
            }
        }
    }

    end {
        if ($PSCmdlet.MyInvocation.ExpectingInput -and $OutputType -eq 'JsonObject' -and (Test-InforcerSession)) {
            ConvertTo-Json -InputObject @($pipedJson) -Depth 100
        }
    }
}
