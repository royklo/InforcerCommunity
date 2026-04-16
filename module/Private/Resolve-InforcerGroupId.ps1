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
        $apiErr = @()
        $response = Invoke-InforcerApiRequest -Endpoint $endpoint -Method GET -OutputType PowerShellObject -PreserveFullResponse -ErrorVariable apiErr -ErrorAction SilentlyContinue

        if ($null -eq $response) {
            if ($apiErr.Count -gt 0) {
                throw [System.InvalidOperationException]::new("Failed to search for group '$groupIdString': $($apiErr[0].Exception.Message)")
            }
            throw [System.InvalidOperationException]::new("No group found with name: $groupIdString")
        }

        $items = $null
        if ($null -ne $response.PSObject.Properties['data']) {
            $items = @($response.data)
        }

        if ($null -eq $items -or $items.Count -eq 0) {
            throw [System.InvalidOperationException]::new("No group found with name: $groupIdString")
        }

        $exactMatches = [System.Collections.Generic.List[string]]::new()
        $caseInsensitiveMatches = [System.Collections.Generic.List[string]]::new()
        foreach ($g in $items) {
            if (-not ($g -is [PSObject])) { continue }
            $nameProp = $g.PSObject.Properties['displayName']
            if (-not $nameProp -or $null -eq $nameProp.Value) { continue }
            $gName = $nameProp.Value.ToString().Trim()
            $idProp = $g.PSObject.Properties['id']
            if (-not $idProp -or $null -eq $idProp.Value) { continue }
            $groupGuid = $idProp.Value.ToString()

            if ($gName -ceq $groupIdString) {
                if (-not $exactMatches.Contains($groupGuid)) { $exactMatches.Add($groupGuid) }
            } elseif ($gName.Equals($groupIdString, [StringComparison]::OrdinalIgnoreCase)) {
                if (-not $caseInsensitiveMatches.Contains($groupGuid)) { $caseInsensitiveMatches.Add($groupGuid) }
            }
        }

        if ($exactMatches.Count -gt 1) {
            throw [System.InvalidOperationException]::new("Multiple groups found with name '$groupIdString'. Pass the group GUID instead.")
        }
        if ($exactMatches.Count -eq 1) {
            Write-Verbose "Found matching group. GUID: $($exactMatches[0])"
            return $exactMatches[0]
        }
        if ($caseInsensitiveMatches.Count -gt 1) {
            throw [System.InvalidOperationException]::new("Multiple groups found with name '$groupIdString'. Pass the group GUID instead.")
        }
        if ($caseInsensitiveMatches.Count -eq 1) {
            Write-Verbose "Found matching group. GUID: $($caseInsensitiveMatches[0])"
            return $caseInsensitiveMatches[0]
        }

        throw [System.InvalidOperationException]::new("No group found with name: $groupIdString")
    }
}
