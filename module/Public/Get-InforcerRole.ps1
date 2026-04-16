function Get-InforcerRole {
    <#
    .SYNOPSIS
        Retrieves directory role definitions from an Inforcer tenant.

    .DESCRIPTION
        Gets the list of Entra ID directory role definitions for a tenant from the Inforcer API.
        Returns role definitions including display name, description, and whether the role is
        built-in, enabled, or privileged.

    .PARAMETER TenantId
        The Inforcer tenant ID. Accepts numeric ID, GUID, or tenant name. Supports pipeline input.

    .PARAMETER OutputType
        Output type: 'PowerShellObject' (default) or 'JsonObject'.

    .EXAMPLE
        Get-InforcerRole -TenantId 139

        Lists all directory role definitions in tenant 139.

    .EXAMPLE
        Get-InforcerRole -TenantId 139 | Where-Object IsPrivileged -eq $true

        Lists only privileged roles in tenant 139.

    .EXAMPLE
        Get-InforcerTenant -TenantId 139 | Get-InforcerRole

        Lists all roles in the piped tenant.

    .EXAMPLE
        Get-InforcerRole -TenantId 139 -OutputType JsonObject

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
        [Alias('ClientTenantId')]
        [object]$TenantId,

        [Parameter(Mandatory = $false)]
        [ValidateSet('PowerShellObject', 'JsonObject')]
        [string]$OutputType = 'PowerShellObject'
    )

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

        $endpoint = "/beta/tenants/$resolvedTenantId/roles"
        Write-Verbose "Retrieving role definitions for tenant $resolvedTenantId..."

        $response = Invoke-InforcerApiRequest -Endpoint $endpoint -Method GET -OutputType PowerShellObject
        if ($null -eq $response) { return }
        $roleData = @($response)
        if ($roleData.Count -eq 0) { return }

        if ($OutputType -eq 'JsonObject') {
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
}
