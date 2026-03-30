<#
.SYNOPSIS
    (Internal) Enriches a policy object with normalized properties and aliases.
#>
function EnrichPolicyObject {
    param([PSObject]$pso)
    # PolicyName is set by Add-InforcerPropertyAliases -ObjectType Policy; only handle tags here
    $tagsProp = $pso.PSObject.Properties['tags']
    if ($null -ne $tagsProp -and $null -ne $tagsProp.Value) {
        $arr = $tagsProp.Value
        $names = @()
        if ($arr -is [object[]]) {
            foreach ($t in $arr) {
                if ($t -is [PSObject] -and $t.PSObject.Properties['name']) {
                    $names += $t.name
                } else {
                    $names += $t.ToString()
                }
            }
        }
        $tagsString = $names -join ', '
        $pso.PSObject.Properties.Remove('tags')
        $pso.PSObject.Properties.Add([System.Management.Automation.PSNoteProperty]::new('tags', $tagsString))
        if ($pso.PSObject.Properties['Tags']) { $pso.PSObject.Properties.Remove('Tags') }
        $pso.PSObject.Properties.Add([System.Management.Automation.PSNoteProperty]::new('Tags', $tagsString))
        $pso.PSObject.Properties.Add([System.Management.Automation.PSNoteProperty]::new('TagsArray', $tagsProp.Value))
    } else {
        if ($pso.PSObject.Properties['tags']) { $pso.PSObject.Properties.Remove('tags') }
        $pso.PSObject.Properties.Add([System.Management.Automation.PSNoteProperty]::new('tags', ''))
        if ($pso.PSObject.Properties['Tags']) { $pso.PSObject.Properties.Remove('Tags') }
        $pso.PSObject.Properties.Add([System.Management.Automation.PSNoteProperty]::new('Tags', ''))
    }
    Add-InforcerPropertyAliases -InputObject $pso -ObjectType Policy | Out-Null
}

<#
.SYNOPSIS
    Retrieves policies for a tenant from the Inforcer API.
.DESCRIPTION
    Gets all policies for the specified tenant. TenantId accepts a numeric ID, GUID, or tenant name.
    Output is normalized to use PolicyName (from displayName or name) so properties are consistent across all rows.
.PARAMETER Format
    Raw (default).
.PARAMETER TenantId
    Tenant to get policies for (required). Numeric ID, GUID, or tenant name.
.PARAMETER OutputType
    PowerShellObject (default) or JsonObject. JSON output uses Depth 100.
.EXAMPLE
    Get-InforcerTenantPolicies -TenantId 482
.EXAMPLE
    Get-InforcerTenantPolicies -TenantId "bb3b1f9d-d866-4b5a-abad-69d6a26bc446" -OutputType JsonObject
.NOTES
    Always use the PolicyName property for the policy display name; it is populated from displayName or name for consistency.
.OUTPUTS
    PSObject or String
.LINK
    Connect-Inforcer
#>
function Get-InforcerTenantPolicies {
[CmdletBinding()]
[OutputType([PSObject], [string])]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('Raw')]
    [string]$Format = 'Raw',

    [Parameter(Mandatory = $true)]
    [object]$TenantId,

    [Parameter(Mandatory = $false)]
    [ValidateSet('PowerShellObject', 'JsonObject')]
    [string]$OutputType = 'PowerShellObject'
)

if (-not (Test-InforcerSession)) {
    Write-Error -Message 'Not connected yet. Please run Connect-Inforcer first.' -ErrorId 'NotConnected' -Category ConnectionError
    return
}

try {
    $clientTenantId = Resolve-InforcerTenantId -TenantId $TenantId
} catch {
    Write-Error -Message $_.Exception.Message -ErrorId 'InvalidTenantId' -Category InvalidArgument
    return
}

Write-Verbose "Retrieving policies for tenant ID: $clientTenantId"

$endpoint = "/beta/tenants/$clientTenantId/policies"
$response = Invoke-InforcerApiRequest -Endpoint $endpoint -Method GET -OutputType $OutputType
if ($null -eq $response) { return }

if ($OutputType -eq 'JsonObject') {
    return $response
}

$result = $response
if ($result -is [array]) {
    foreach ($item in $result) {
        if ($item -is [PSObject]) { EnrichPolicyObject $item }
    }
} elseif ($result -is [PSObject]) {
    EnrichPolicyObject $result
}

if ($result -is [array]) {
    $result | ForEach-Object { $_ }
} else {
    $result
}
}
