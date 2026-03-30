function Get-InforcerUser {
    <#
    .SYNOPSIS
        Retrieves users from an Inforcer tenant.

    .DESCRIPTION
        Gets a list of users or a single user by ID from the Inforcer API.
        When called without -UserId, returns all users (UserSummary objects) with optional search filtering and auto-pagination.
        When called with -UserId, returns the full user detail (User object) including groups, roles, devices, and risk information.

    .PARAMETER Format
        Output format. Currently only 'Raw' is supported.

    .PARAMETER TenantId
        The Inforcer tenant ID. Accepts numeric ID, GUID, or tenant name. Supports pipeline input.

    .PARAMETER Search
        Server-side search filter for the user list. Only available in the List parameter set.

    .PARAMETER MaxResults
        Maximum number of users to return. 0 (default) means no limit. Only available in the List parameter set.

    .PARAMETER UserId
        The user ID (GUID) to retrieve full details for. Only available in the ById parameter set.

    .PARAMETER OutputType
        Output type: 'PowerShellObject' (default) or 'JsonObject'.

    .EXAMPLE
        Get-InforcerUser -TenantId 139

        Lists all users in tenant 139.

    .EXAMPLE
        Get-InforcerUser -TenantId 139 -Search "Adele"

        Searches for users matching "Adele" in tenant 139.

    .EXAMPLE
        Get-InforcerUser -TenantId 139 -UserId "8e61ce11-a45b-42a6-8ca4-1d881781566d"

        Gets full detail for a specific user.

    .EXAMPLE
        Get-InforcerTenant -TenantId 139 | Get-InforcerUser

        Lists all users in the piped tenant.
    #>
    [CmdletBinding(DefaultParameterSetName = 'List')]
    param(
        [Parameter(ParameterSetName = 'List')]
        [Parameter(ParameterSetName = 'ById')]
        [ValidateSet('Raw')]
        [string]$Format = 'Raw',

        [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'List')]
        [Parameter(Mandatory, ValueFromPipelineByPropertyName, ParameterSetName = 'ById')]
        [Alias('ClientTenantId')]
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
            # --- ById: single user detail ---
            $endpoint = "/beta/tenants/$resolvedTenantId/users/$UserId"
            $response = Invoke-InforcerApiRequest -Endpoint $endpoint -Method GET -OutputType PowerShellObject

            if ($null -eq $response) {
                Write-Error -Message "User '$UserId' not found in tenant '$resolvedTenantId'." -ErrorId 'UserNotFound' -Category ObjectNotFound
                return
            }

            if ($OutputType -eq 'JsonObject') {
                return $response | ConvertTo-Json -Depth 100
            }

            $null = Add-InforcerPropertyAliases -InputObject $response -ObjectType User
            $response.PSObject.TypeNames.Insert(0, 'InforcerCommunity.User')
            return $response
        }

        # --- List: paginated user list ---
        $jsonBuffer = if ($OutputType -eq 'JsonObject') { [System.Collections.ArrayList]::new() } else { $null }
        $continuationToken = $null
        $pageCount = 0
        $itemCount = 0

        do {
            $pageCount++
            $endpoint = "/beta/tenants/$resolvedTenantId/users"
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
                    $itemCount++

                    if ($OutputType -eq 'JsonObject') {
                        # Buffer raw items without aliases for clean JSON
                        [void]$jsonBuffer.Add($item)
                    } else {
                        # Stream to pipeline immediately
                        $null = Add-InforcerPropertyAliases -InputObject $item -ObjectType UserSummary
                        $item.PSObject.TypeNames.Insert(0, 'InforcerCommunity.UserSummary')
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
