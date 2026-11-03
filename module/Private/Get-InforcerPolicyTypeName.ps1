function Get-InforcerPolicyTypeName {
    <#
    .SYNOPSIS
        Returns the inforcer policy type name for a policyTypeId, or '' when it is not known (Private helper).
    .DESCRIPTION
        The beta /tenants/{id}/policies list stopped sending inforcerPolicyTypeName, which left the
        Export "Profile type" column empty. This table puts the name back. Every entry is a name the
        inforcer API itself returned for that id (2026-11-03/04): v1 /tenants/{id}/policies
        policyTypeName first, v1 alignmentDetails policyTypeName for ids the v1 policies list never
        returns (alignmentDetails uses different names for many ids, so it is only the fallback).
        Ids without such evidence are left out on purpose and stay blank.
        Remove this helper and its one caller in ConvertTo-InforcerDocModel once beta sends the field
        again (see .claude/FINDINGS.md).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter()][object]$PolicyTypeId)

    $id = 0
    if ($null -eq $PolicyTypeId -or -not [int]::TryParse("$PolicyTypeId", [ref]$id)) { return '' }
    $name = $script:InforcerPolicyTypeNames[$id]
    if ($name) { $name } else { '' }
}

$script:InforcerPolicyTypeNames = @{
    1     = 'Conditional Access Policy'
    2     = 'Conditional Access Named Location'
    3     = 'Device Compliance'
    4     = 'Device Configuration'
    6     = 'Managed App'
    9     = 'Windows Autopilot Deployment Profile'
    10    = 'Configuration'
    12    = 'Azure AD'
    14    = 'SharePoint'
    15    = 'Exchange'
    16    = 'Organisation'
    17    = 'Conditional Access Authentication Strengths'
    19    = 'Exchange Anti-Phishing'
    20    = 'Exchange Anti-Malware'
    21    = 'Exchange Safe Attachments'
    22    = 'Exchange Safe Links'
    23    = 'Exchange Spam Policy (inbound)'
    24    = 'Exchange Spam Policy (outbound)'
    25    = 'Mail Flow Rules'
    28    = 'Feature Update Profile'
    33    = 'Quarantine Policy'
    35    = 'Intune Script Mac Os'
    40    = 'Teams Meeting Policies'
    60    = 'Intune Settings'
    61    = 'Password Expiration Policy'
    62    = 'Certificate-based authentication'
    70    = 'Self Service Policy'
    72    = 'Password Protection'
    80    = 'Mail Flow Settings'
    83    = 'Exchange Unified Audit Logging'
    90    = 'Purview data loss prevention policy'
    92    = 'Purview Sensitivity Label'
    93    = 'Purview Label Publishing Policy'
    100   = 'Autopilot Esp'
    101   = 'Defender For Endpoint Settings'
    103   = 'Windows Quality Update Policy'
    10224 = 'Intune Windows Store Apps'
    10349 = 'System Preferred Authentication'
    10441 = 'Role Scope Tags'
    20227 = 'Exchange ExternalInOutlook'
    20238 = 'Teams Events Policies'
    20255 = 'Exchange Organization Config'
    20596 = 'Purview Insider Risk Settings'
    24385 = 'Defender custom indicators'
}
