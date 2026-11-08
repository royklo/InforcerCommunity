function Get-InforcerUser {
    <#
    .SYNOPSIS
        Retrieves users from an Inforcer tenant.

        Required API scope(s): Tenants.Users.Read + Tenants.Read (only when -TenantId is a GUID or tenant name)
        (API key); User & Group Management + Tenants (only for a tenant name) permission (API client, unconfirmed).

    .DESCRIPTION
        Gets a list of users or a single user by ID from the Inforcer API. Works with both login types (API key and client credentials).
        When called without -UserId, returns all users (UserSummary objects) with optional search filtering and auto-pagination.
        When called with -UserId, returns the full user detail (User object) including groups, roles, devices, and risk information.

    .PARAMETER Format
        Output format. Currently only 'Raw' is supported.

    .PARAMETER TenantId
        The Inforcer tenant ID. Accepts numeric ID (API-key login only), Microsoft tenant GUID, or tenant name. Supports pipeline input.

    .PARAMETER Search
        Server-side search filter for the user list. Only available in the List parameter set.

    .PARAMETER MaxResults
        Maximum number of users to return. 0 (default) means no limit. Only available in the List parameter set.

    .PARAMETER UserId
        The user ID (GUID) to retrieve full details for. Only available in the ById parameter set.

    .PARAMETER OutputType
        Output type: 'PowerShellObject' (default) or 'JsonObject'. Depth 100; the v1 list is always a JSON array.
        Piped tenants: each user carries TenantId and JsonObject returns one array for all tenants.

    .EXAMPLE
        Get-InforcerUser -TenantId 'Contoso'

        Lists all users in the tenant Contoso.

    .EXAMPLE
        Get-InforcerUser -TenantId 'Contoso' -Search "Adele"

        Searches for users matching "Adele" in the tenant Contoso.

    .EXAMPLE
        Get-InforcerUser -TenantId 'Contoso' -UserId "00000000-0000-0000-0000-000000000005"

        Gets full detail for a specific user.

    .EXAMPLE
        Get-InforcerTenant -TenantId 'Contoso' | Get-InforcerUser

        Lists all users in the piped tenant.

    .EXAMPLE
        Get-InforcerUser -TenantId 'Contoso' -OutputType JsonObject

        Returns the users as a JSON string (depth 100) instead of objects.

    .OUTPUTS
        PSObject or String (when -OutputType JsonObject)

    .LINK
        https://github.com/royklo/InforcerCommunity/blob/main/docs/CMDLET-REFERENCE.md#get-inforceruser

    .LINK
        Connect-Inforcer
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    [OutputType([PSObject], [string])]
    param(
        [Parameter(ParameterSetName = 'List')]
        [Parameter(ParameterSetName = 'ById')]
        [ValidateSet('Raw')]
        [string]$Format = 'Raw',

        [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'List')]
        [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'ById')]
        [Alias('ClientTenantId', 'MsTenantId')]
        [object]$TenantId,

        [Parameter(ParameterSetName = 'List')]
        [string]$Search,

        [Parameter(ParameterSetName = 'List')]
        [int]$MaxResults = 0,

        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [string]$UserId,

        [Parameter(ParameterSetName = 'List')]
        [Parameter(ParameterSetName = 'ById')]
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

        $piped = $PSCmdlet.MyInvocation.ExpectingInput
        $addTenantId = {
            param($item)
            if ($piped -and $item -is [PSObject] -and -not $item.PSObject.Properties['TenantId']) {
                $item.PSObject.Properties.Add([System.Management.Automation.PSNoteProperty]::new('TenantId', $resolvedTenantId))
            }
        }

        if ($PSCmdlet.ParameterSetName -eq 'ById') {
            # --- ById: single user detail ---
            $endpoint = "/tenants/$resolvedTenantId/users/$UserId"
            $err = $null
            # -PreserveStructure: user detail response is a single object with many nested arrays
            # (groups, roles, devices, appRoleAssignments, assignedLicenses, businessPhones, ...).
            # Without it, Invoke-InforcerApiRequest would unwrap to the first array property.
            $response = Invoke-InforcerApiRequest -Endpoint $endpoint -Method GET -OutputType PowerShellObject -PreserveStructure -ObjectType User -ErrorVariable err -ErrorAction SilentlyContinue

            if ($null -eq $response) {
                if (-not $err -or $err[-1].FullyQualifiedErrorId -like 'ApiRequestFailed_404*') {
                    Write-Error -Message "User '$UserId' not found in tenant '$resolvedTenantId'." -ErrorId 'UserNotFound' -Category ObjectNotFound
                } else {
                    Write-Error -ErrorRecord $err[-1]
                }
                return
            }

            & $addTenantId $response
            if ($OutputType -eq 'JsonObject') {
                if ($piped) { $pipedJson.Add($response); return }
                return $response | ConvertTo-Json -Depth 100
            }

            $null = Add-InforcerPropertyAliases -InputObject $response -ObjectType User
            $response.PSObject.TypeNames.Insert(0, 'InforcerCommunity.User')
            return $response
        }

        # --- List: paginated user list ---
        $endpoint = "/tenants/$resolvedTenantId/users"
        if ($Search) { $endpoint += '?search=' + [System.Uri]::EscapeDataString($Search) }

        if ($OutputType -eq 'JsonObject') {
            $users = @(Invoke-InforcerPagedRequest -Endpoint $endpoint -ObjectType User -MaxResults $MaxResults -ErrorVariable listErr)
            if ($listErr) { return }
            if ($piped) { foreach ($u in $users) { & $addTenantId $u; $pipedJson.Add($u) }; return }
            if ($script:InforcerSession.ApiVersion -eq 'v1') { return ConvertTo-Json -InputObject $users -Depth 100 }
            return $users | ConvertTo-Json -Depth 100
        }

        Invoke-InforcerPagedRequest -Endpoint $endpoint -ObjectType User -MaxResults $MaxResults | ForEach-Object {
            & $addTenantId $_
            $null = Add-InforcerPropertyAliases -InputObject $_ -ObjectType UserSummary
            $_.PSObject.TypeNames.Insert(0, 'InforcerCommunity.UserSummary')
            $_
        }
    }

    end {
        if ($PSCmdlet.MyInvocation.ExpectingInput -and $OutputType -eq 'JsonObject' -and (Test-InforcerSession)) {
            ConvertTo-Json -InputObject @($pipedJson) -Depth 100
        }
    }
}
