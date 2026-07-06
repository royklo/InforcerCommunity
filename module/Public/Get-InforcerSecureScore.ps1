function Get-InforcerSecureScore {
    <#
    .SYNOPSIS
        Retrieves the current and historic secure score for an Inforcer tenant.

        Required API scope(s): Tenants.SecureScores.Read + Tenants.Read (only when -TenantId is a GUID or tenant name)

    .DESCRIPTION
        Gets secure score data for a tenant from GET /beta/tenants/{tenantId}/secureScores.
        Returns the current score, max score, licensed user count, enabled services, up to
        90 days of daily score history, per-category scores, and actionable control profiles
        with remediation guidance.

    .PARAMETER TenantId
        The Inforcer tenant ID. Accepts numeric ID, GUID, or tenant name. Supports pipeline input.

    .PARAMETER OutputType
        Output type: 'PowerShellObject' (default) or 'JsonObject'.

    .EXAMPLE
        Get-InforcerSecureScore -TenantId 139

        Returns the secure score summary for tenant 139.

    .EXAMPLE
        (Get-InforcerSecureScore -TenantId 139).Scores

        Returns the 90-day daily score history.

    .EXAMPLE
        (Get-InforcerSecureScore -TenantId 139).ControlProfiles | Sort-Object ScoreDifference -Descending | Select-Object -First 10

        Lists the 10 controls with the largest gap between current and max score.

    .EXAMPLE
        Get-InforcerTenant -TenantId 139 | Get-InforcerSecureScore

        Retrieves secure scores for the piped tenant.

    .EXAMPLE
        Get-InforcerSecureScore -TenantId 139 -OutputType JsonObject

        Returns the response as a JSON string.

    .OUTPUTS
        PSObject or String (when -OutputType JsonObject)

    .LINK
        https://github.com/royklo/InforcerCommunity/blob/main/docs/CMDLET-REFERENCE.md#get-inforcersecurescore

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

        $endpoint = "/beta/tenants/$resolvedTenantId/secureScores"
        Write-Verbose "Retrieving secure score for tenant $resolvedTenantId..."

        $response = Invoke-InforcerApiRequest -Endpoint $endpoint -Method GET -OutputType PowerShellObject
        if ($null -eq $response) { return }

        if ($OutputType -eq 'JsonObject') {
            return ($response | ConvertTo-Json -Depth 100)
        }

        if ($response -is [PSObject]) {
            $null = Add-InforcerPropertyAliases -InputObject $response -ObjectType SecureScore
            $response.PSObject.TypeNames.Insert(0, 'InforcerCommunity.SecureScore')
        }
        $response
    }
}
