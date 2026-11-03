function Get-InforcerGroup {
    <#
    .SYNOPSIS
        Retrieves groups from an Inforcer tenant.

        Required API scope(s): Tenants.Groups.Read + Tenants.Read (only when -TenantId is a GUID or tenant name)

    .DESCRIPTION
        Gets a list of groups or a single group from the Inforcer API.
        When called without -Group, returns all groups (GroupSummary objects) with optional filtering and auto-pagination.
        When called with -Group, resolves the group by GUID or display name and returns the full group detail (Group object) including members.

        Works with both login types. With client credentials the members of a single group come from a separate
        paged members call and are attached as the Members property, so the output matches an API-key login.
        That call reads every member page (100 members per page), so a very large group takes one call per 100 members.

        Use -Search for server-side prefix filtering (fast, sent to API).
        Use -Filter for client-side wildcard filtering (supports contains, e.g. *comp*).

        The list shows MembershipRule for dynamic groups. -Group additionally shows
        OnPremisesSyncEnabled.

    .PARAMETER TenantId
        The Inforcer tenant ID. Accepts numeric ID (API-key login only), Microsoft tenant GUID, or tenant name. Supports pipeline input.

    .PARAMETER Group
        The group to retrieve full details for. Accepts a GUID or a display name.
        When a GUID is provided, fetches the group directly.
        When a display name is provided, searches for the group and returns the detail including members.

    .PARAMETER Search
        Server-side search filter (sent to API). The API performs prefix matching on display name.
        For contains/substring matching, use -Filter instead.

    .PARAMETER Filter
        Client-side wildcard filter applied to display name after fetching all groups.
        Supports PowerShell wildcards: *comp* matches "All Company", empl* matches "All Employees".
        Fetches all groups from the API, then filters locally. Slower than -Search for large tenants
        but supports contains matching that the API does not.

    .PARAMETER MaxResults
        Maximum number of groups to return. 0 (default) means no limit. Only available when -Group is not specified.

    .PARAMETER OutputType
        Output type: 'PowerShellObject' (default) or 'JsonObject'.
        Piped tenants: each group carries TenantId and JsonObject returns one array for all tenants.

    .EXAMPLE
        Get-InforcerGroup -TenantId 139

        Lists all groups in tenant 139.

    .EXAMPLE
        Get-InforcerGroup -TenantId 139 -Search "Finance"

        Server-side search for groups starting with "Finance".

    .EXAMPLE
        Get-InforcerGroup -TenantId 139 -Filter "*comp*"

        Client-side filter for groups containing "comp" in the display name (e.g. "All Company").

    .EXAMPLE
        Get-InforcerGroup -TenantId 139 -Group "Tailspin Toys"

        Resolves the group by display name and returns full detail including members.

    .EXAMPLE
        Get-InforcerGroup -TenantId 139 -Group "00000000-0000-0000-0000-000000000006"

        Gets full detail for a specific group by GUID including members.

    .EXAMPLE
        Get-InforcerTenant -TenantId 139 | Get-InforcerGroup

        Lists all groups in the piped tenant.

    .EXAMPLE
        Get-InforcerGroup -TenantId 139 -OutputType JsonObject

        Returns all groups as a JSON string.

    .EXAMPLE
        Get-InforcerGroup -TenantId 139 -Group "Finance" -OutputType JsonObject

        Returns full group detail as a JSON string.

    .OUTPUTS
        PSObject or String (when -OutputType JsonObject)

    .LINK
        https://github.com/royklo/InforcerCommunity/blob/main/docs/CMDLET-REFERENCE.md#get-inforcergroup

    .LINK
        Connect-Inforcer
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    [OutputType([PSObject], [string])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'List')]
        [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'ById')]
        [Alias('ClientTenantId', 'MsTenantId')]
        [object]$TenantId,

        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [Alias('GroupId')]
        [string]$Group,

        [Parameter(ParameterSetName = 'List')]
        [string]$Search,

        [Parameter(ParameterSetName = 'List')]
        [string]$Filter,

        [Parameter(ParameterSetName = 'List')]
        [int]$MaxResults = 0,

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
            # --- ById: resolve group (GUID or name) and get detail ---
            try {
                $resolvedGroupId = Resolve-InforcerGroupId -GroupId $Group -TenantId $resolvedTenantId
            } catch {
                Write-Error -Message $_.Exception.Message -ErrorId 'InvalidGroupId' -Category InvalidArgument
                return
            }

            $endpoint = "/tenants/$resolvedTenantId/groups/$resolvedGroupId"
            $err = $null
            $response = Invoke-InforcerApiRequest -Endpoint $endpoint -Method GET -OutputType PowerShellObject -PreserveStructure -ObjectType Group -ErrorVariable err -ErrorAction SilentlyContinue

            if ($null -eq $response) {
                if ($err -and $err[-1].FullyQualifiedErrorId -like 'ApiRequestFailed_404*') {
                    Write-Error -Message "Group '$Group' not found in tenant '$resolvedTenantId'." -ErrorId 'GroupNotFound' -Category ObjectNotFound
                } elseif ($err) {
                    Write-Error -ErrorRecord $err[-1]
                } else {
                    Write-Error -Message "Group '$Group' not found in tenant '$resolvedTenantId'." -ErrorId 'GroupNotFound' -Category ObjectNotFound
                }
                return
            }

            if ($script:InforcerSession.ApiVersion -eq 'v1') {
                $memberErr = $null
                $members = @(Invoke-InforcerPagedRequest -Endpoint "$endpoint/members" -ObjectType GroupMember -ErrorVariable memberErr -ErrorAction SilentlyContinue)
                if ($memberErr) {
                    Write-Warning "Could not read the members of group '$Group', so members is null: $($memberErr[-1].Exception.Message)"
                    $members = $null
                }
                Add-Member -InputObject $response -NotePropertyName 'members' -NotePropertyValue $members -Force
            }

            & $addTenantId $response
            if ($OutputType -eq 'JsonObject') {
                if ($piped) { $pipedJson.Add($response); return }
                return $response | ConvertTo-Json -Depth 100
            }

            $null = Add-InforcerPropertyAliases -InputObject $response -ObjectType Group
            $response.PSObject.TypeNames.Insert(0, 'InforcerCommunity.Group')
            return $response
        }

        # --- List: paginated group list ---
        $endpoint = "/tenants/$resolvedTenantId/groups"
        if ($Search) { $endpoint += '?search=' + [System.Uri]::EscapeDataString($Search) }

        # Streams; -MaxResults counts matches, so with -Filter it applies after filtering.
        $listGroups = {
            if (-not $Filter) { return Invoke-InforcerPagedRequest -Endpoint $endpoint -ObjectType Group -MaxResults $MaxResults }
            $first = if ($MaxResults -gt 0) { $MaxResults } else { [int]::MaxValue }
            Invoke-InforcerPagedRequest -Endpoint $endpoint -ObjectType Group | Where-Object {
                $dn = $_.PSObject.Properties['displayName'].Value
                $dn -and $dn -like $Filter
            } | Select-Object -First $first
        }

        if ($OutputType -eq 'JsonObject') {
            $groups = @(& $listGroups)
            if ($piped) { foreach ($g in $groups) { & $addTenantId $g; $pipedJson.Add($g) }; return }
            if ($script:InforcerSession.ApiVersion -eq 'v1') { return ConvertTo-Json -InputObject $groups -Depth 100 }
            return $groups | ConvertTo-Json -Depth 100
        }

        & $listGroups | ForEach-Object {
            & $addTenantId $_
            $null = Add-InforcerPropertyAliases -InputObject $_ -ObjectType GroupSummary
            $_.PSObject.TypeNames.Insert(0, 'InforcerCommunity.GroupSummary')
            $_
        }
    }

    end {
        if ($PSCmdlet.MyInvocation.ExpectingInput -and $OutputType -eq 'JsonObject' -and (Test-InforcerSession)) {
            ConvertTo-Json -InputObject @($pipedJson) -Depth 100
        }
    }
}
