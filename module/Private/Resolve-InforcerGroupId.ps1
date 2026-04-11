function Resolve-InforcerGroupId {
    <#
    .SYNOPSIS
        Resolves a group identifier (GUID or display name) to a group GUID.
    .DESCRIPTION
        If the value is a GUID string, returns it directly.
        If it is a display name, searches the tenant's groups via the API and resolves
        to the group GUID. Prefers exact case match, falls back to case-insensitive.
    .PARAMETER GroupId
        Group GUID or display name.
    .PARAMETER TenantId
        Resolved Inforcer tenant ID (numeric). Required for API lookup when resolving by name.
    .OUTPUTS
        System.String - The resolved group GUID.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$GroupId,

        [Parameter(Mandatory = $true)]
        [int]$TenantId
    )

    process {
        $groupIdString = $GroupId.Trim()

        $guidResult = [guid]::Empty
        if ([guid]::TryParse($groupIdString, [ref]$guidResult)) {
            Write-Verbose "Group GUID detected: $groupIdString"
            return $groupIdString
        }

        Write-Verbose "Group name detected: '$groupIdString'. Searching for group..."
        $endpoint = "/beta/tenants/$TenantId/groups?search=$([System.Uri]::EscapeDataString($groupIdString))"
        $response = Invoke-InforcerApiRequest -Endpoint $endpoint -Method GET -OutputType PowerShellObject -PreserveFullResponse

        $items = $null
        if ($null -ne $response -and $null -ne $response.PSObject.Properties['data']) {
            $items = @($response.data)
        }

        if ($null -eq $items -or $items.Count -eq 0) {
            throw [System.InvalidOperationException]::new("No group found with name: $groupIdString")
        }

        $exactMatch = $null
        $caseInsensitiveMatch = $null
        foreach ($g in $items) {
            if (-not ($g -is [PSObject])) { continue }
            $nameProp = $g.PSObject.Properties['displayName']
            if (-not $nameProp -or $null -eq $nameProp.Value) { continue }
            $gName = $nameProp.Value.ToString().Trim()
            if ($gName -ceq $groupIdString) {
                $idProp = $g.PSObject.Properties['id']
                if ($idProp -and $null -ne $idProp.Value) {
                    $exactMatch = $idProp.Value.ToString()
                    break
                }
            } elseif ($null -eq $caseInsensitiveMatch -and $gName.Equals($groupIdString, [StringComparison]::OrdinalIgnoreCase)) {
                $idProp = $g.PSObject.Properties['id']
                if ($idProp -and $null -ne $idProp.Value) {
                    $caseInsensitiveMatch = $idProp.Value.ToString()
                }
            }
        }

        $resolved = if ($exactMatch) { $exactMatch } else { $caseInsensitiveMatch }
        if ($resolved) {
            Write-Verbose "Found matching group. GUID: $resolved"
            return $resolved
        }

        throw [System.InvalidOperationException]::new("No group found with name: $groupIdString")
    }
}
