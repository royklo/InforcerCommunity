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
        $names = [System.Collections.Generic.List[string]]::new()
        if ($arr -is [object[]]) {
            foreach ($t in $arr) {
                if ($t -is [PSObject] -and $t.PSObject.Properties['name']) {
                    [void]$names.Add($t.name)
                } else {
                    [void]$names.Add($t.ToString())
                }
            }
        }
        $tagsString = $names -join ', '
        $tagsProp.Value = $tagsString
        $tagsPropUpper = $pso.PSObject.Properties['Tags']
        if ($tagsPropUpper) { $tagsPropUpper.Value = $tagsString }
        else { $pso.PSObject.Properties.Add([System.Management.Automation.PSNoteProperty]::new('Tags', $tagsString)) }
        if (-not $pso.PSObject.Properties['TagsArray']) {
            $pso.PSObject.Properties.Add([System.Management.Automation.PSNoteProperty]::new('TagsArray', $arr))
        }
    } else {
        $existingTags = $pso.PSObject.Properties['tags']
        if ($existingTags) { $existingTags.Value = '' }
        else { $pso.PSObject.Properties.Add([System.Management.Automation.PSNoteProperty]::new('tags', '')) }
        $existingTagsUpper = $pso.PSObject.Properties['Tags']
        if ($existingTagsUpper) { $existingTagsUpper.Value = '' }
        else { $pso.PSObject.Properties.Add([System.Management.Automation.PSNoteProperty]::new('Tags', '')) }
    }
    $null = Add-InforcerPropertyAliases -InputObject $pso -ObjectType Policy
    $pso.PSObject.TypeNames.Insert(0, 'InforcerCommunity.Policy')
}

<#
.SYNOPSIS
    Retrieves policies for a tenant from the Inforcer API.

    Required API scope(s): tenants.policies.Read + Tenants.Read (only when -TenantId is a GUID or tenant name)
    (API key); Policies + Tenants (only for a tenant name) permission (API client, unconfirmed).
.DESCRIPTION
    Gets all policies for the specified tenant. TenantId accepts a numeric ID (API-key login only), Microsoft tenant GUID, or tenant name.
    Works with both login types. With client credentials, policy types inforcer could not read are named
    in one warning (the API's failedPolicyTypes).
    Output is normalized to use PolicyName (from displayName or name) so properties are consistent across all rows.
.PARAMETER Format
    Raw (default).
.PARAMETER TenantId
    Tenant to get policies for (required). Numeric ID (API-key login only), Microsoft tenant GUID, or tenant name.
.PARAMETER OutputType
    PowerShellObject (default) or JsonObject. JSON output is an array and uses Depth 100.
    Piped tenants: each policy carries TenantId and JsonObject returns one array for all tenants.
.EXAMPLE
    Get-InforcerTenantPolicies -TenantId 'Contoso'
.EXAMPLE
    Get-InforcerTenantPolicies -TenantId 101   # API key only (numeric Client Tenant ID)
.EXAMPLE
    Get-InforcerTenantPolicies -TenantId "00000000-0000-0000-0000-000000000003" -OutputType JsonObject
.NOTES
    Always use the PolicyName property for the policy display name; it is populated from displayName or name for consistency.
.OUTPUTS
    PSObject or String
.LINK
    https://github.com/royklo/InforcerCommunity/blob/main/docs/CMDLET-REFERENCE.md#get-inforcertenantpolicies
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

    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [Alias('ClientTenantId', 'MsTenantId')]
    [object]$TenantId,

    [Parameter(Mandatory = $false)]
    [ValidateSet('PowerShellObject', 'JsonObject')]
    [string]$OutputType = 'PowerShellObject'
)

begin { $pipedJson = [System.Collections.Generic.List[object]]::new() }

process {

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

$endpoint = "/tenants/$clientTenantId/policies"
$piped = $PSCmdlet.MyInvocation.ExpectingInput
$addTenantId = {
    param($item)
    if ($piped -and $item -is [PSObject] -and -not $item.PSObject.Properties['TenantId']) {
        $item.PSObject.Properties.Add([System.Management.Automation.PSNoteProperty]::new('TenantId', $clientTenantId))
    }
}

if ($script:InforcerSession.ApiVersion -eq 'v1') {
    $apiErr = $null
    $policies = @(Invoke-InforcerApiRequest -Endpoint $endpoint -Method GET -OutputType PowerShellObject -ObjectType Policy -ErrorVariable apiErr)
    if ($apiErr) { return }

    foreach ($item in $policies) { & $addTenantId $item }
    if ($OutputType -eq 'JsonObject') {
        if ($piped) { $pipedJson.AddRange([object[]]$policies); return }
        return ConvertTo-Json -InputObject $policies -Depth 100
    }
    foreach ($item in $policies) {
        if ($item -is [PSObject]) { EnrichPolicyObject $item }
    }
    return $policies
}

if ($piped -and $OutputType -eq 'JsonObject') {
    $apiErr = $null
    $policies = @(Invoke-InforcerApiRequest -Endpoint $endpoint -Method GET -OutputType PowerShellObject -PreserveStructure -ErrorVariable apiErr)
    if ($apiErr) { return }
    foreach ($item in $policies) { & $addTenantId $item; $pipedJson.Add($item) }
    return
}

$response = Invoke-InforcerApiRequest -Endpoint $endpoint -Method GET -OutputType $OutputType
if ($null -eq $response) { return }

if ($OutputType -eq 'JsonObject') {
    return $response
}

$result = $response
if ($result -is [array]) {
    foreach ($item in $result) {
        if ($item -is [PSObject]) { & $addTenantId $item; EnrichPolicyObject $item }
    }
} elseif ($result -is [PSObject]) {
    & $addTenantId $result
    EnrichPolicyObject $result
}

$result
}

end {
    if ($PSCmdlet.MyInvocation.ExpectingInput -and $OutputType -eq 'JsonObject' -and (Test-InforcerSession)) {
        ConvertTo-Json -InputObject @($pipedJson) -Depth 100
    }
}
}
