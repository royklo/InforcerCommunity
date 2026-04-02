function Get-InforcerPolicyDisplayInfo {
    <#
    .SYNOPSIS
        Maps API policy names and types to friendly display names and Microsoft admin portal categories.
    .DESCRIPTION
        The Inforcer API uses internal identifiers (e.g., "MSAuthenticatorConfig", "Fido2Config") and
        generic groupings ("Settings / All"). This function maps them to the names and categories IT
        admins recognise from the Microsoft admin portals.

        Returns a hashtable with FriendlyName and Category. When no mapping exists, returns the
        original name and category unchanged.
    .PARAMETER PolicyName
        The raw policy name from the API (displayName or friendlyName).
    .PARAMETER Product
        The product field from the API (Entra, Intune, SharePoint, etc.).
    .PARAMETER PrimaryGroup
        The primaryGroup field from the API.
    .PARAMETER SecondaryGroup
        The secondaryGroup field from the API.
    .PARAMETER PolicyTypeId
        The policyTypeId field from the API.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PolicyName,
        [Parameter()][string]$Product,
        [Parameter()][string]$PrimaryGroup,
        [Parameter()][string]$SecondaryGroup,
        [Parameter()][int]$PolicyTypeId
    )

    # Entra ID settings (policyTypeId 12) - map internal names to admin portal paths
    $entraSettingsMap = @{
        'AdminAppConsent'           = @{ FriendlyName = 'Admin consent requests';           Category = 'Enterprise applications' }
        'AuthenticatorSetupEnforce' = @{ FriendlyName = 'System-preferred MFA';             Category = 'Authentication methods' }
        'DefSecSettings'            = @{ FriendlyName = 'Security defaults';                Category = 'Properties' }
        'DefUserRolePerms'          = @{ FriendlyName = 'Default user role permissions';    Category = 'User settings' }
        'EmailOTPConfig'            = @{ FriendlyName = 'Email OTP';                        Category = 'Authentication methods' }
        'ExternalUserLeaveConfig'   = @{ FriendlyName = 'External user leave settings';     Category = 'External Identities' }
        'Fido2Config'               = @{ FriendlyName = 'FIDO2 security keys';             Category = 'Authentication methods' }
        'GuestUserAccessConfig'     = @{ FriendlyName = 'Guest user access restrictions';   Category = 'External Identities' }
        'HardwareOathConfig'        = @{ FriendlyName = 'Hardware OATH tokens';             Category = 'Authentication methods' }
        'LocalAdministratorPassword'= @{ FriendlyName = 'Windows LAPS';                    Category = 'Device settings' }
        'MSAuthenticatorConfig'     = @{ FriendlyName = 'Microsoft Authenticator';          Category = 'Authentication methods' }
        'MultiFactorAuthConfig'     = @{ FriendlyName = 'Multifactor authentication';       Category = 'Authentication methods' }
        'QrCodeConfig'              = @{ FriendlyName = 'QR code authentication';           Category = 'Authentication methods' }
        'SelfServicePassConfig'     = @{ FriendlyName = 'Self-service password reset';      Category = 'Password reset' }
        'SmsAuthConfig'             = @{ FriendlyName = 'SMS';                              Category = 'Authentication methods' }
        'SoftwareOathConfig'        = @{ FriendlyName = 'Software OATH tokens';             Category = 'Authentication methods' }
        'TempPasswordConfig'        = @{ FriendlyName = 'Temporary Access Pass';            Category = 'Authentication methods' }
        'UserAllowedToRegister'     = @{ FriendlyName = 'User registration allowed';        Category = 'Device settings' }
        'UserAppConsent'            = @{ FriendlyName = 'User consent settings';            Category = 'Enterprise applications' }
        'UserDeviceQuota'           = @{ FriendlyName = 'Device limit per user';            Category = 'Device settings' }
        'VoiceConfig'               = @{ FriendlyName = 'Voice call';                       Category = 'Authentication methods' }
    }

    # Entra ID other types
    $entraTypeMap = @{
        62 = @{ FriendlyName = $null; Category = 'Authentication methods' }   # Certificate-based authentication
        72 = @{ FriendlyName = $null; Category = 'Authentication methods' }   # Password Protection
        17 = @{ FriendlyName = $null; Category = 'Authentication strengths' } # CA Auth Strengths
    }

    # SharePoint settings (policyTypeId 14)
    $sharepointSettingsMap = @{
        'ActivityBasedTimeout'                 = @{ FriendlyName = 'Idle session sign-out';          Category = 'Access control' }
        'ExternalUserReshare'                  = @{ FriendlyName = 'External user resharing';        Category = 'Sharing' }
        'MacOneDriveSync'                      = @{ FriendlyName = 'Mac OneDrive sync';              Category = 'Sync' }
        'OneDriveDeletedUserDefaultRetention'  = @{ FriendlyName = 'Deleted user data retention';    Category = 'OneDrive' }
        'OneDriveRetention'                    = @{ FriendlyName = 'OneDrive retention';              Category = 'OneDrive' }
        'OneDriveStorageQuota'                 = @{ FriendlyName = 'OneDrive storage quota';          Category = 'OneDrive' }
        'SharePointAllowGuestItemSharing'      = @{ FriendlyName = 'Guest item sharing';             Category = 'Sharing' }
        'SharePointOneDriveSharingLevel'       = @{ FriendlyName = 'External sharing level';         Category = 'Sharing' }
        'SharePointSiteCreation'               = @{ FriendlyName = 'Site creation';                  Category = 'Site creation' }
        'SyncFileExclusions'                   = @{ FriendlyName = 'Sync file exclusions';           Category = 'Sync' }
        'UnmanagedOneDriveSyncRestriction'     = @{ FriendlyName = 'Unmanaged device sync';          Category = 'Sync' }
    }

    # M365 Admin Center settings (policyTypeId 16)
    $m365SettingsMap = @{
        'DirectoryGuestAccess'         = @{ FriendlyName = 'Guest access';                Category = 'Org settings' }
        'OrganizationTechnicalContact' = @{ FriendlyName = 'Organization technical contact'; Category = 'Org settings' }
        'ReportAnonymization'          = @{ FriendlyName = 'Report anonymization';         Category = 'Org settings' }
    }

    $friendlyName = $null
    $category = $null

    if ($Product -eq 'Entra' -and $PolicyTypeId -eq 12 -and $entraSettingsMap.ContainsKey($PolicyName)) {
        $mapping = $entraSettingsMap[$PolicyName]
        $friendlyName = $mapping.FriendlyName
        $category = $mapping.Category
    }
    elseif ($Product -eq 'Entra' -and $entraTypeMap.ContainsKey($PolicyTypeId)) {
        $mapping = $entraTypeMap[$PolicyTypeId]
        if ($mapping.FriendlyName) { $friendlyName = $mapping.FriendlyName }
        $category = $mapping.Category
    }
    elseif ($Product -eq 'SharePoint' -and $PolicyTypeId -eq 14 -and $sharepointSettingsMap.ContainsKey($PolicyName)) {
        $mapping = $sharepointSettingsMap[$PolicyName]
        $friendlyName = $mapping.FriendlyName
        $category = $mapping.Category
    }
    elseif ($Product -eq 'M365 Admin Center' -and $PolicyTypeId -eq 16 -and $m365SettingsMap.ContainsKey($PolicyName)) {
        $mapping = $m365SettingsMap[$PolicyName]
        $friendlyName = $mapping.FriendlyName
        $category = $mapping.Category
    }

    @{
        FriendlyName = $friendlyName
        Category     = $category
    }
}
