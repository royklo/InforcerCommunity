function Get-InforcerGroup {
    <#
    .SYNOPSIS
        Retrieves groups from an Inforcer tenant.

    .DESCRIPTION
        Gets a list of groups or a single group from the Inforcer API.
        When called without -Group, returns all groups (GroupSummary objects) with optional filtering and auto-pagination.
        When called with -Group, resolves the group by GUID or display name and returns the full group detail (Group object) including members.

        Use -Search for server-side prefix filtering (fast, sent to API).
        Use -Filter for client-side wildcard filtering (supports contains, e.g. *comp*).

    .PARAMETER TenantId
        The Inforcer tenant ID. Accepts numeric ID, GUID, or tenant name. Supports pipeline input.

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
        Get-InforcerGroup -TenantId 139 -Group "f44f2f5c-3160-420b-900d-5ecbede954fc"

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
        [Alias('ClientTenantId')]
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

        if ($PSCmdlet.ParameterSetName -eq 'ById') {
            # --- ById: resolve group (GUID or name) and get detail ---
            try {
                $resolvedGroupId = Resolve-InforcerGroupId -GroupId $Group -TenantId $resolvedTenantId
            } catch {
                Write-Error -Message $_.Exception.Message -ErrorId 'InvalidGroupId' -Category InvalidArgument
                return
            }

            $endpoint = "/beta/tenants/$resolvedTenantId/groups/$resolvedGroupId"
            $err = $null
            $response = Invoke-InforcerApiRequest -Endpoint $endpoint -Method GET -OutputType PowerShellObject -PreserveStructure -ErrorVariable err -ErrorAction SilentlyContinue

            if ($null -eq $response) {
                if ($err -and $err[0].FullyQualifiedErrorId -like 'ApiRequestFailed_404*') {
                    Write-Error -Message "Group '$Group' not found in tenant '$resolvedTenantId'." -ErrorId 'GroupNotFound' -Category ObjectNotFound
                } elseif ($err) {
                    Write-Error -ErrorRecord $err[0]
                } else {
                    Write-Error -Message "Group '$Group' not found in tenant '$resolvedTenantId'." -ErrorId 'GroupNotFound' -Category ObjectNotFound
                }
                return
            }

            if ($OutputType -eq 'JsonObject') {
                return $response | ConvertTo-Json -Depth 100
            }

            $null = Add-InforcerPropertyAliases -InputObject $response -ObjectType Group
            $response.PSObject.TypeNames.Insert(0, 'InforcerCommunity.Group')
            return $response
        }

        # --- List: paginated group list ---
        $jsonBuffer = $null
        if ($OutputType -eq 'JsonObject') { $jsonBuffer = [System.Collections.ArrayList]::new() }
        $continuationToken = $null
        $pageCount = 0
        $itemCount = 0

        do {
            $pageCount++
            $endpoint = "/beta/tenants/$resolvedTenantId/groups"
            $queryParams = @()
            if ($Search) { $queryParams += "search=$([System.Uri]::EscapeDataString($Search))" }
            if ($continuationToken) { $queryParams += "continuationToken=$([System.Uri]::EscapeDataString($continuationToken))" }
            if ($queryParams.Count -gt 0) { $endpoint += '?' + ($queryParams -join '&') }

            Write-Verbose "Fetching page $pageCount..."
            $response = Invoke-InforcerApiRequest -Endpoint $endpoint -Method GET -OutputType PowerShellObject -PreserveFullResponse

            if ($null -eq $response) { break }

            # continuationToken is at the response root level (sibling of .data), not inside .data
            $items = if ($null -ne $response.PSObject.Properties['data']) { $response.data } else { $null }
            $newToken = if ($null -ne $response.PSObject.Properties['continuationToken']) { $response.continuationToken } else { $null }

            # Guard against infinite loop: if API returns the same token, stop
            if ($newToken -and $newToken -eq $continuationToken) {
                Write-Verbose "API returned duplicate continuationToken. Stopping pagination."
                break
            }
            $continuationToken = $newToken

            if ($null -ne $items) {
                $itemArray = @($items)
                Write-Verbose "Page $pageCount returned $($itemArray.Count) items."
                foreach ($item in $itemArray) {
                    if ($null -eq $item) { continue }
                    if ($MaxResults -gt 0 -and $itemCount -ge $MaxResults) {
                        $continuationToken = $null
                        break
                    }

                    # Client-side wildcard filter on displayName
                    if ($Filter) {
                        $displayName = $null
                        $dnProp = $item.PSObject.Properties['displayName']
                        if ($dnProp) { $displayName = $dnProp.Value }
                        if (-not $displayName -or $displayName -notlike $Filter) { continue }
                    }

                    $itemCount++

                    if ($OutputType -eq 'JsonObject') {
                        [void]$jsonBuffer.Add($item)
                    } else {
                        $null = Add-InforcerPropertyAliases -InputObject $item -ObjectType GroupSummary
                        $item.PSObject.TypeNames.Insert(0, 'InforcerCommunity.GroupSummary')
                        $item
                    }
                }
            }
        } while ($continuationToken)

        if ($OutputType -eq 'JsonObject') {
            return $jsonBuffer | ConvertTo-Json -Depth 100
        }
    }
}
