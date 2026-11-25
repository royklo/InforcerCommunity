function Get-InforcerAutoContainment {
    <#
    .SYNOPSIS
        Retrieves whether auto-containment is on for a tenant, and the settings that limit what it may do.

        Required API scope(s): none; the API-key (beta) API has no TDR endpoints.
        Required permission: Threats, view auto remediation (API client, tdr:auto_remediation:view).

    .DESCRIPTION
        GET /tenants/{msTenantId}/tdr/autoContainment, once per tenant. Auto-containment lets inforcer's
        threat detection and response (TDR) act on a tenant by itself, such as blocking a user's sign-in.
        A tenant where it was never set up returns configured and enabled false and settings null.
        A tenant outside the API client's scope, or without a TDR licence, is an error (404).

        The module adds msTenantId to each result, so piped tenants can be told apart.

        Needs a login with an API client (Connect-Inforcer -ClientId -ClientSecret); an API-key login
        gets the error RequiresApiClient.

    .PARAMETER Format
        Raw (default).

    .PARAMETER TenantId
        The tenant: Microsoft tenant ID (GUID) or tenant name. Supports pipeline input.

    .PARAMETER OutputType
        PowerShellObject (default) or JsonObject. JSON output uses Depth 100.

    .EXAMPLE
        Get-InforcerAutoContainment -TenantId 'Contoso'

        Whether auto-containment is on for Contoso, and its settings.

    .EXAMPLE
        Get-InforcerTenant | Get-InforcerAutoContainment -ErrorAction SilentlyContinue | Where-Object enabled

        The tenants where auto-containment is on (tenants without TDR are skipped).

    .EXAMPLE
        Get-InforcerAutoContainment -TenantId 'Contoso' -OutputType JsonObject

        The same as JSON, for a script or a change log.

    .OUTPUTS
        PSObject (InforcerCommunity.AutoContainment), or a JSON string with -OutputType JsonObject.

    .LINK
        https://github.com/royklo/InforcerCommunity/blob/main/docs/CMDLET-REFERENCE.md#get-inforcerautocontainment

    .LINK
        Set-InforcerAutoContainment
    #>
    [CmdletBinding()]
    [OutputType([PSObject], [string])]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateSet('Raw')]
        [string]$Format = 'Raw',

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('ClientTenantId', 'MsTenantId')]
        [object]$TenantId,

        [Parameter(Mandatory = $false)]
        [ValidateSet('PowerShellObject', 'JsonObject')]
        [string]$OutputType = 'PowerShellObject'
    )

    process {
        if (-not (Test-InforcerSession)) {
            Write-Error -Message 'Not connected yet. Please run Connect-Inforcer first.' -ErrorId 'NotConnected' -Category ConnectionError
            return
        }
        if ($script:InforcerSession.ApiVersion -ne 'v1') {
            Write-Error -Message 'Auto-containment needs a login with an API client (Connect-Inforcer -ClientId -ClientSecret). The API-key (beta) API has no threat detection and response endpoints.' -ErrorId 'RequiresApiClient' -Category InvalidOperation
            return
        }
        try {
            $resolvedTenantId = Resolve-InforcerTenantId -TenantId $TenantId
        } catch {
            Write-Error -Message $_.Exception.Message -ErrorId 'InvalidTenantId' -Category InvalidArgument
            return
        }

        $result = Invoke-InforcerApiRequest -Endpoint "/tenants/$resolvedTenantId/tdr/autoContainment" -Method GET -PreserveStructure
        if ($null -eq $result) { return }
        ConvertTo-InforcerAutoContainment -Result $result -TenantId $resolvedTenantId -OutputType $OutputType
    }
}
