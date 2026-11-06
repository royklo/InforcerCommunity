function Get-InforcerSecureScore {
    <#
    .SYNOPSIS
        Retrieves the current and historic secure score for an Inforcer tenant.

        Required API scope(s): Tenants.SecureScores.Read + Tenants.Read (only when -TenantId is a GUID or tenant name)
        (API key); Entra Dashboard + Tenants (only for a tenant name) permission (API client, unconfirmed).

    .DESCRIPTION
        Gets secure score data for a tenant from GET /tenants/{tenantId}/secureScores (beta or v1, by login type).
        Returns the current score, max score, licensed user count, enabled services, up to
        90 days of daily score history, per-category scores, and actionable control profiles
        with remediation guidance.

    .PARAMETER TenantId
        The Inforcer tenant ID. Accepts numeric ID (API-key login only), Microsoft tenant GUID, or tenant name. Supports pipeline input.

    .PARAMETER OutputType
        Output type: 'PowerShellObject' (default) or 'JsonObject'.
        Piped tenants: each result carries TenantId and JsonObject returns one array for all tenants.

    .EXAMPLE
        Get-InforcerSecureScore -TenantId 'Contoso'

        Returns the secure score summary for the tenant Contoso.

    .EXAMPLE
        (Get-InforcerSecureScore -TenantId 'Contoso').Scores

        Returns the 90-day daily score history.

    .EXAMPLE
        (Get-InforcerSecureScore -TenantId 'Contoso').ControlProfiles | Sort-Object ScoreDifference -Descending | Select-Object -First 10

        Lists the 10 controls with the largest gap between current and max score.

    .EXAMPLE
        $s = Get-InforcerSecureScore -TenantId 'Contoso'
        $s.ControlProfiles | Where-Object ScoreDifference -gt 0 |
            Group-Object ControlCategory |
            Select-Object Name, Count, @{n='TotalGain';e={($_.Group | Measure-Object ScoreDifference -Sum).Sum}}

        Groups open recommendations by category with total potential score gain per category.

    .EXAMPLE
        $s = Get-InforcerSecureScore -TenantId 'Contoso'
        ($s.ControlCategoryScores | Where-Object ControlCategory -eq 'Identity').HistoricScores |
            Format-Table CreatedDateTime, CurrentScore, MaxScore, CurrentScorePercentage -AutoSize

        Shows the daily Identity category history for the tenant.

    .EXAMPLE
        Get-InforcerTenant -TenantId 'Contoso' | Get-InforcerSecureScore

        Retrieves secure scores for the piped tenant.

    .EXAMPLE
        Get-InforcerSecureScore -TenantId 'Contoso' -OutputType JsonObject

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

        $endpoint = "/tenants/$resolvedTenantId/secureScores"
        Write-Verbose "Retrieving secure score for tenant $resolvedTenantId..."

        # -PreserveStructure prevents Invoke-InforcerApiRequest from unwrapping the first array
        # property of .data. The secure-score payload is a single object whose interesting
        # content sits in its `scores`, `controlProfiles`, and `controlCategoryScores` arrays —
        # without -PreserveStructure the caller would receive one of those inner arrays instead
        # of the top-level tenantSecureScoreDetails object.
        $response = Invoke-InforcerApiRequest -Endpoint $endpoint -Method GET -OutputType PowerShellObject -PreserveStructure -ObjectType SecureScore
        if ($null -eq $response) { return }

        $piped = $PSCmdlet.MyInvocation.ExpectingInput
        if ($piped -and $response -is [PSObject] -and -not $response.PSObject.Properties['TenantId']) {
            $response.PSObject.Properties.Add([System.Management.Automation.PSNoteProperty]::new('TenantId', $resolvedTenantId))
        }

        if ($OutputType -eq 'JsonObject') {
            if ($piped) { $pipedJson.Add($response); return }
            return ($response | ConvertTo-Json -Depth 100)
        }

        if ($response -is [PSObject]) {
            $null = Add-InforcerPropertyAliases -InputObject $response -ObjectType SecureScore
            $response.PSObject.TypeNames.Insert(0, 'InforcerCommunity.SecureScore')
            foreach ($cp in @($response.controlProfiles)) {
                if ($cp -is [PSObject]) { $cp.PSObject.TypeNames.Insert(0, 'InforcerCommunity.SecureScoreControlProfile') }
            }
        }
        $response
    }

    end {
        if ($PSCmdlet.MyInvocation.ExpectingInput -and $OutputType -eq 'JsonObject' -and (Test-InforcerSession)) {
            ConvertTo-Json -InputObject @($pipedJson) -Depth 100
        }
    }
}
