function Set-InforcerUser {
    <#
    .SYNOPSIS
        Updates a Microsoft Entra user's profile, manager, sign-in, licences or group memberships, changes their Exchange Online mailbox (shared or user, online archive, address lists, email addresses, automatic replies, forwarding, permissions, calendar sharing, mail groups, inbox rules, mail apps), resets their password, removes sign-in methods (or all of them, to reset MFA), issues a Temporary Access Pass or signs them out everywhere.

        Required API scope(s): none; the API-key (beta) API cannot update users.
        Required permission: User & Group Management (API client, unconfirmed which grant).

    .DESCRIPTION
        Updates a user with PATCH /tenants/{msTenantId}/users/{userId}. Needs a login with an API client
        (Connect-Inforcer -ClientId -ClientSecret); an API-key login gets the error RequiresApiClient.

        Only the parameters you pass are changed; everything else stays as it is. Pass an empty string
        ('') or $null to clear a field, such as -JobTitle '' or -ManagerId '' to remove the manager.
        DisplayName, MailNickname, UserPrincipalName, Mail and UserType cannot be cleared.
        Microsoft Entra refuses most changes to a user synced from on-premises Active Directory; change them there.

        -AddLicense and -RemoveLicense change the user's licences in one request
        (POST .../users/{userId}/assignLicenses); if one licence is refused, nothing changes.
        -AddGroup and -RemoveGroup change the user's Microsoft Entra group memberships
        (POST .../users/{userId}/groups). Adding runs first and removing only after every add succeeded, so a
        user moved between groups is never left in neither. A group the user is already in, or not in, counts
        as done.
        Mailbox changes (-MailboxType, -EnableArchive, -HiddenFromAddressLists, -AddEmailAddress, -PrimaryEmailAddress,
        -RemoveEmailAddress, -AutoReply, -ForwardTo, -RemoveForwarding, -GrantMailboxPermission,
        -RemoveMailboxPermission, -GrantCalendarAccess, -RemoveCalendarAccess, -AddMailGroup, -RemoveMailGroup,
        -RemoveInboxRule, -RemoveAllInboxRules, -AllowMailApp, -BlockMailApp)
        each go to .../users/{userId}/mailbox/... and are queued in Exchange Online, which applies one change
        to a mailbox at a time, about a minute each. The cmdlet waits for each to succeed or fail (at most
        5 minutes per change; a change still queued then stops the steps after it, while Exchange carries on)
        before the next step. Read the mailbox with Get-InforcerUser -IncludeMailbox. A Global Administrator's mailbox is refused.
        -Password sets a new password (POST /tenants/{msTenantId}/users/{userId}/password); the user must
        change it when they next sign in unless you pass -ForceChangePasswordNextSignIn $false.
        -RemoveAuthenticationMethod deletes registered sign-in methods, such as a phone or Microsoft
        Authenticator (DELETE .../users/{userId}/authenticationMethods/{methodId}); take the ids from
        Get-InforcerUser -IncludeAuthenticationMethods, where only methods with deletable true can be removed.
        -ResetMfa deletes every method with deletable true in one request (DELETE .../users/{userId}/mfa),
        in the order Microsoft Entra needs, so the user must register MFA again; the password is kept.
        -TemporaryAccessPass creates a Temporary Access Pass (POST .../authenticationMethods/temporaryAccessPasses)
        and returns it; the pass cannot be read again, and it replaces a pass the user already has.
        -RevokeSessions signs the user out of every session (POST .../users/{userId}/revokeSessions);
        access tokens already issued stay valid until they expire, typically within 90 minutes.
        In one call the steps run in this order: profile update, licences (when -AddLicense is given), adding
        to groups, removing from groups, mailbox
        type, online archive, address lists, adding email addresses, primary email address, removing email addresses,
        automatic replies, forwarding, granting and removing mailbox permissions, sharing and unsharing the
        calendar, adding to and removing from mail groups, removing inbox rules, mail apps, licences (when
        only -RemoveLicense is given, so a mailbox is converted to shared before its licence goes), password reset, removing sign-in methods, MFA reset,
        sign-out, Temporary Access Pass (last, so a failed step never hides the pass). When a step fails, the later steps
        are skipped and the error says which steps were already done.

        -AccountEnabled $false blocks sign-in, but existing sessions last until their tokens expire;
        add -RevokeSessions to end them.
        Get-InforcerUser can show the old values for up to about five minutes, because the API caches users. Returns nothing, except the pass with -TemporaryAccessPass.

        When the manager could not be changed but the other changes were saved, the error lists
        each step and whether it was applied.

    .PARAMETER TenantId
        The tenant's Microsoft tenant GUID or tenant name. Supports pipeline input by property name.

    .PARAMETER UserId
        The user's Microsoft Entra object id. Supports pipeline input by property name (also from id),
        so users from Get-InforcerUser or New-InforcerUser can be piped in.

    .PARAMETER AccountEnabled
        Whether the user can sign in.

    .PARAMETER DisplayName
        The name shown for the user. Cannot be cleared.

    .PARAMETER MailNickname
        The mail alias. Cannot be cleared.

    .PARAMETER UserPrincipalName
        The sign-in name, such as jo.bloggs@contoso.com. Cannot be cleared.

    .PARAMETER GivenName
        First name. '' clears it.

    .PARAMETER Surname
        Last name. '' clears it.

    .PARAMETER JobTitle
        Job title. '' clears it.

    .PARAMETER Department
        Department. '' clears it.

    .PARAMETER OfficeLocation
        Office location. '' clears it.

    .PARAMETER StreetAddress
        Street address. '' clears it.

    .PARAMETER City
        City. '' clears it.

    .PARAMETER State
        State or province. '' clears it.

    .PARAMETER PostalCode
        Postal code. '' clears it.

    .PARAMETER Country
        Country or region. '' clears it.

    .PARAMETER MobilePhone
        Mobile phone number. '' clears it.

    .PARAMETER UsageLocation
        Two-letter country code (ISO 3166) where the user's licences are used, such as GB. '' clears it.

    .PARAMETER PreferredLanguage
        Preferred language, such as en-GB. '' clears it.

    .PARAMETER CompanyName
        Company name. '' clears it.

    .PARAMETER EmployeeId
        Employee id (at most 16 characters). '' clears it.

    .PARAMETER EmployeeType
        Employee type, such as Employee or Contractor. '' clears it.

    .PARAMETER Mail
        Email address. Cannot be cleared.

    .PARAMETER BusinessPhones
        Business phone number. Microsoft Entra allows one. @() clears it.

    .PARAMETER OtherMails
        Other email addresses. Replaces the whole list; @() clears it.

    .PARAMETER ManagerId
        The Microsoft Entra object id of the user's manager. '' removes the manager.

    .PARAMETER UserType
        Member or Guest. Cannot be cleared.

    .PARAMETER AddLicense
        The skuId of one or more licences to give the user, from Get-InforcerTenant -IncludeSubscriptions
        (which also shows free seats) or assignedLicenses of Get-InforcerUser -UserId.
        A licence with no free seat, not subscribed to, or conflicting with the user's other licences is
        refused. The user needs a usage location (-UsageLocation, set in the same call if needed).

    .PARAMETER RemoveLicense
        The skuId of one or more licences to take from the user. A licence the user gets through a group
        is refused; one the user does not have is ignored.

    .PARAMETER AddGroup
        The object id of one or more Microsoft Entra groups (at most 20) to add the user to.
        Role-assignable groups, dynamic groups, distribution lists and mail-enabled security groups are refused.

    .PARAMETER RemoveGroup
        The object id of one or more Microsoft Entra groups (at most 20) to remove the user from. Runs only
        after -AddGroup succeeded. Role-assignable groups, dynamic groups, distribution lists and mail-enabled security groups are refused.

    .PARAMETER HiddenFromAddressLists
        $true hides the user's mailbox from the address lists (the global address list in Outlook), $false
        shows it again. The user needs a mailbox; a Global Administrator's mailbox is refused.

    .PARAMETER MailboxType
        User or Shared. Converts the mailbox to a shared mailbox (for a leaver, before the licence is
        removed) or back to a user mailbox. User needs a licence with Exchange Online (-AddLicense in the
        same call runs before the mailbox steps); without one the step fails with MailboxLicenseMissing and
        nothing changes. A new licence can take a few minutes to reach Exchange.

    .PARAMETER EnableArchive
        Turns on the mailbox's online archive. It cannot be turned off here; one already on is left as it is.
        Mail moves into the archive under the tenant's retention policy, not straight away. Refused for a
        user synced from on-premises Active Directory.

    .PARAMETER AutoReply
        The automatic replies, as a hashtable or the autoReply object Get-InforcerUser -IncludeMailbox
        returns (null values and simplified are left out). status is always needed: disabled, alwaysEnabled
        or scheduled. alwaysEnabled and scheduled also need internalReplyMessage and externalAudience (none,
        contactsOnly or all), externalReplyMessage unless externalAudience is none, and scheduled needs
        scheduledStartDateTime and scheduledEndDateTime. Exchange sets the replies as a whole, so a property
        left out is not kept. Messages keep only bold, italic, underline and text size.

    .PARAMETER ForwardTo
        Forwards the user's mail to another user in the tenant (their Microsoft Entra object id) or to an
        address on one of the tenant's verified domains. Replaces any earlier forwarding.

    .PARAMETER KeepForwardedCopy
        Keeps a copy of forwarded mail in the mailbox. Only with -ForwardTo.

    .PARAMETER RemoveForwarding
        Stops forwarding the user's mail.

    .PARAMETER GrantMailboxPermission
        One or more permissions to give another user on this mailbox, each with permission (fullAccess,
        sendAs or sendOnBehalf) and trusteeId (the other user's object id), and for fullAccess optionally
        automapping ($true adds the mailbox to their Outlook).

    .PARAMETER RemoveMailboxPermission
        One or more permissions to take away, each with permission and trusteeId, such as entries of
        mailbox.permissions from Get-InforcerUser -IncludeMailbox. An inherited permission cannot be removed.

    .PARAMETER GrantCalendarAccess
        One or more users to share the calendar with, each with trusteeId (a member of the tenant, not a
        guest) and role: reviewer (sees events), editor (also creates, changes and deletes them) or delegate
        (an editor who also receives meeting requests). A user who already has access gets the new role.

    .PARAMETER RemoveCalendarAccess
        The object id of one or more users whose access to the calendar is taken away, whatever their
        role, such as trusteeId of mailbox.calendarAccess from Get-InforcerUser -IncludeMailbox.

    .PARAMETER AddMailGroup
        The object id of one or more distribution lists or mail-enabled security groups to add the user to.
        Microsoft 365 groups and groups synced from on-premises Active Directory are refused.

    .PARAMETER RemoveMailGroup
        The object id of one or more distribution lists or mail-enabled security groups to remove the user from.

    .PARAMETER AddEmailAddress
        One or more email addresses to add to the mailbox, on domains verified in the tenant. Refused for
        a user synced from on-premises Active Directory.

    .PARAMETER PrimaryEmailAddress
        Adds this address if needed and makes it the mailbox's main address. Runs after -AddEmailAddress
        and before -RemoveEmailAddress, so the old main address can be removed in the same call.

    .PARAMETER RemoveEmailAddress
        One or more email addresses to remove from the mailbox. The main address and the sign-in address
        are refused.

    .PARAMETER RemoveInboxRule
        The id of one or more inbox rules to remove, from mailbox.inboxRules of Get-InforcerUser
        -IncludeMailbox. A rule with deletable false cannot be removed.

    .PARAMETER RemoveAllInboxRules
        Removes every inbox rule Exchange can remove; rules such as the junk filter are kept.

    .PARAMETER AllowMailApp
        Mail apps the mailbox may connect with: OutlookWeb (also the new Outlook for Windows),
        OutlookDesktop (classic Outlook for Windows), OutlookMac (the new Outlook for Mac),
        ExchangeWebServices, Imap, Pop, OutlookApp (iOS and Android) and OtherMailApps (Exchange
        ActiveSync, such as iPhone Mail). A tenant-wide policy can still block an app. Apps not named keep
        their setting; see mailbox.mailApps from Get-InforcerUser -IncludeMailbox.

    .PARAMETER BlockMailApp
        Mail apps the mailbox may no longer connect with, with the names of -AllowMailApp. Allowing and
        blocking happen in one change.

    .PARAMETER Password
        A new password as a SecureString. It must meet the tenant's password policy.
        inforcer does not store or log it. Refused for a user synced from on-premises Active Directory.

    .PARAMETER ForceChangePasswordNextSignIn
        Whether the user must change the new password when they next sign in. Default $true.
        Only together with -Password.

    .PARAMETER RemoveAuthenticationMethod
        The id of one or more registered sign-in methods to delete, from the authenticationMethods that
        Get-InforcerUser -IncludeAuthenticationMethods returns. Only methods with deletable true can be
        removed; Microsoft Entra can also refuse one, such as the default method while another phone remains.

    .PARAMETER ResetMfa
        Deletes every sign-in method the user registered that can be deleted (phones, Microsoft
        Authenticator, passkeys, ...), so they must register MFA again at the next sign-in. The password is kept.

    .PARAMETER TemporaryAccessPass
        Creates a Temporary Access Pass and returns it as an object with temporaryAccessPass, id,
        startDateTime, lifetimeInMinutes, usableOnce and userId. The pass is shown only this once.
        It runs after -ResetMfa, which would otherwise delete it.

    .PARAMETER TemporaryAccessPassLifetime
        How long the pass lasts, in minutes (10 to 43200, and within the tenant's policy). Without it the
        tenant's default applies. Only with -TemporaryAccessPass.

    .PARAMETER TemporaryAccessPassUsableOnce
        Whether the pass can be used only once. Without it the tenant's policy decides. Only with
        -TemporaryAccessPass.

    .PARAMETER RevokeSessions
        Signs the user out of every session by revoking their refresh tokens and session cookies.

    .EXAMPLE
        Set-InforcerUser -TenantId 'Contoso' -UserId '00000000-0000-0000-0000-000000000005' -Department 'Sales' -JobTitle 'Account Manager'

        Changes the department and job title. Every other field stays as it is.

    .EXAMPLE
        Set-InforcerUser -TenantId 'Contoso' -UserId '00000000-0000-0000-0000-000000000005' -AccountEnabled $false

        Blocks the user from signing in.

    .EXAMPLE
        Get-InforcerUser -TenantId 'Contoso' -Search 'Adele' | Set-InforcerUser -TenantId 'Contoso' -ManagerId ''

        Removes the manager of every user matching "Adele".

    .EXAMPLE
        $password = Read-Host -AsSecureString -Prompt 'New password'
        Set-InforcerUser -TenantId 'Contoso' -UserId '00000000-0000-0000-0000-000000000005' -Password $password -RevokeSessions

        Resets the password (the user must change it at the next sign-in) and signs the user out everywhere.

    .EXAMPLE
        Set-InforcerUser -TenantId 'Contoso' -UserId '00000000-0000-0000-0000-000000000005' -AccountEnabled $false -RevokeSessions

        Blocks sign-in and ends the user's existing sessions.

    .EXAMPLE
        Set-InforcerUser -TenantId 'Contoso' -UserId '00000000-0000-0000-0000-000000000005' -Password $password -ResetMfa -RevokeSessions

        Locks out a compromised account: new password, every removable sign-in method deleted, signed out everywhere.

    .EXAMPLE
        Set-InforcerUser -TenantId 'Contoso' -UserId '00000000-0000-0000-0000-000000000005' -ResetMfa -TemporaryAccessPass -TemporaryAccessPassLifetime 60 -TemporaryAccessPassUsableOnce $true

        Resets MFA and returns a one-time pass, valid for an hour, so the user can register new sign-in methods.

    .EXAMPLE
        Set-InforcerUser -TenantId 'Contoso' -UserId '00000000-0000-0000-0000-000000000005' -UsageLocation 'GB' -AddLicense '00000000-0000-0000-0000-0000000000b1'

        Sets the usage location, then gives the user a licence.

    .EXAMPLE
        $user = Get-InforcerUser -TenantId 'Contoso' -UserId '00000000-0000-0000-0000-000000000005' -IncludeAuthenticationMethods
        $lost = @($user.authenticationMethods | Where-Object { $_.phoneNumber -eq '+44 7700 900000' }).id
        Set-InforcerUser -TenantId 'Contoso' -UserId $user.id -RemoveAuthenticationMethod $lost

        Removes one lost phone and keeps the user's other sign-in methods.

    .EXAMPLE
        Set-InforcerUser -TenantId 'Contoso' -UserId '00000000-0000-0000-0000-000000000005' -AccountEnabled $false -HiddenFromAddressLists $true -RevokeSessions

        Offboards a leaver: blocks sign-in, hides the mailbox from the address book and ends every session.

    .EXAMPLE
        $reply = @{ status = 'alwaysEnabled'; externalAudience = 'all'; internalReplyMessage = 'Jo has left Contoso. Please contact sales@contoso.com.'; externalReplyMessage = 'Jo has left Contoso. Please contact sales@contoso.com.' }
        Set-InforcerUser -TenantId 'Contoso' -UserId '00000000-0000-0000-0000-000000000005' -AccountEnabled $false -MailboxType Shared -AutoReply $reply -GrantMailboxPermission @{ permission = 'fullAccess'; trusteeId = '00000000-0000-0000-0000-000000000006' } -RemoveLicense '00000000-0000-0000-0000-0000000000b1' -RevokeSessions

        Offboards a leaver and keeps their mail: blocks sign-in, converts the mailbox to shared, sets an
        automatic reply, gives the manager full access, then removes the licence and ends every session.

    .EXAMPLE
        $mailbox = (Get-InforcerUser -TenantId 'Contoso' -UserId '00000000-0000-0000-0000-000000000005' -IncludeMailbox).mailbox
        Set-InforcerUser -TenantId 'Contoso' -UserId '00000000-0000-0000-0000-000000000005' -RemoveForwarding -RemoveInboxRule @($mailbox.inboxRules | Where-Object forwardsExternally).id

        Stops a compromised mailbox from sending mail out: removes its forwarding and every inbox rule that forwards outside the tenant.

    .EXAMPLE
        Set-InforcerUser -TenantId 'Contoso' -UserId '00000000-0000-0000-0000-000000000005' -BlockMailApp Imap, Pop -GrantCalendarAccess @{ trusteeId = '00000000-0000-0000-0000-000000000006'; role = 'delegate' }

        Blocks IMAP and POP for the mailbox and makes another user a delegate of its calendar.

    .EXAMPLE
        Set-InforcerUser -TenantId 'Contoso' -UserId '00000000-0000-0000-0000-000000000005' -AddGroup '00000000-0000-0000-0000-0000000000c2' -RemoveGroup '00000000-0000-0000-0000-0000000000c1'

        Moves the user to another group: adds them to the new group, then removes them from the old one.

    .EXAMPLE
        Set-InforcerUser -TenantId 'Contoso' -UserId '00000000-0000-0000-0000-000000000005' -UsageLocation 'GB' -WhatIf

        Shows what would change without changing it.

    .OUTPUTS
        None, or with -TemporaryAccessPass the created pass (PSCustomObject).

    .LINK
        https://github.com/royklo/InforcerCommunity/blob/main/docs/CMDLET-REFERENCE.md#set-inforceruser

    .LINK
        New-InforcerUser

    .LINK
        Get-InforcerUser
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([void], [pscustomobject])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('ClientTenantId', 'MsTenantId')]
        [object]$TenantId,

        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('Id')]
        [ValidateNotNullOrEmpty()]
        [string]$UserId,

        [bool]$AccountEnabled,

        [ValidateNotNullOrEmpty()]
        [string]$DisplayName,

        [ValidateNotNullOrEmpty()]
        [string]$MailNickname,

        [ValidateNotNullOrEmpty()]
        [string]$UserPrincipalName,

        [string]$GivenName,
        [string]$Surname,
        [string]$JobTitle,
        [string]$Department,
        [string]$OfficeLocation,
        [string]$StreetAddress,
        [string]$City,
        [string]$State,
        [string]$PostalCode,
        [string]$Country,
        [string]$MobilePhone,
        [string]$UsageLocation,
        [string]$PreferredLanguage,
        [string]$CompanyName,
        [string]$EmployeeId,
        [string]$EmployeeType,

        [ValidateNotNullOrEmpty()]
        [string]$Mail,

        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$BusinessPhones,

        [AllowNull()]
        [AllowEmptyCollection()]
        [string[]]$OtherMails,

        [string]$ManagerId,

        [ValidateSet('Member', 'Guest')]
        [string]$UserType,

        [ValidateNotNullOrEmpty()]
        [guid[]]$AddLicense,

        [ValidateNotNullOrEmpty()]
        [guid[]]$RemoveLicense,

        [ValidateCount(1, 20)]
        [guid[]]$AddGroup,

        [ValidateCount(1, 20)]
        [guid[]]$RemoveGroup,

        [bool]$HiddenFromAddressLists,

        [ValidateSet('User', 'Shared')]
        [string]$MailboxType,

        [switch]$EnableArchive,

        [ValidateNotNull()]
        [object]$AutoReply,

        [ValidateNotNullOrEmpty()]
        [string]$ForwardTo,

        [switch]$KeepForwardedCopy,

        [switch]$RemoveForwarding,

        [ValidateNotNullOrEmpty()]
        [object[]]$GrantMailboxPermission,

        [ValidateNotNullOrEmpty()]
        [object[]]$RemoveMailboxPermission,

        [ValidateNotNullOrEmpty()]
        [object[]]$GrantCalendarAccess,

        [ValidateNotNullOrEmpty()]
        [guid[]]$RemoveCalendarAccess,

        [ValidateNotNullOrEmpty()]
        [guid[]]$AddMailGroup,

        [ValidateNotNullOrEmpty()]
        [guid[]]$RemoveMailGroup,

        [ValidateNotNullOrEmpty()]
        [string[]]$AddEmailAddress,

        [ValidateNotNullOrEmpty()]
        [string]$PrimaryEmailAddress,

        [ValidateNotNullOrEmpty()]
        [string[]]$RemoveEmailAddress,

        [ValidateNotNullOrEmpty()]
        [string[]]$RemoveInboxRule,

        [switch]$RemoveAllInboxRules,

        [ValidateSet('OutlookWeb', 'OutlookDesktop', 'OutlookMac', 'ExchangeWebServices', 'Imap', 'Pop', 'OutlookApp', 'OtherMailApps')]
        [string[]]$AllowMailApp,

        [ValidateSet('OutlookWeb', 'OutlookDesktop', 'OutlookMac', 'ExchangeWebServices', 'Imap', 'Pop', 'OutlookApp', 'OtherMailApps')]
        [string[]]$BlockMailApp,

        [System.Security.SecureString]$Password,

        [bool]$ForceChangePasswordNextSignIn = $true,

        [ValidateNotNullOrEmpty()]
        [string[]]$RemoveAuthenticationMethod,

        [switch]$ResetMfa,

        [switch]$TemporaryAccessPass,

        [ValidateRange(10, 43200)]
        [int]$TemporaryAccessPassLifetime,

        [bool]$TemporaryAccessPassUsableOnce,

        [switch]$RevokeSessions
    )

    process {
        if (-not (Test-InforcerSession)) {
            Write-Error -Message 'Not connected to Inforcer. Use Connect-Inforcer first.' -ErrorId 'NotConnected' -Category ConnectionError
            return
        }
        if ($script:InforcerSession.ApiVersion -ne 'v1') {
            Write-Error -Message 'Updating users needs a login with an API client (Connect-Inforcer -ClientId -ClientSecret). The API-key (beta) API cannot update users.' -ErrorId 'RequiresApiClient' -Category InvalidOperation
            return
        }

        if ($PSBoundParameters.ContainsKey('ForceChangePasswordNextSignIn') -and -not $Password) {
            Write-Error -Message '-ForceChangePasswordNextSignIn only works together with -Password.' -ErrorId 'PasswordRequired' -Category InvalidArgument
            return
        }
        if (-not $TemporaryAccessPass -and ($PSBoundParameters.ContainsKey('TemporaryAccessPassLifetime') -or $PSBoundParameters.ContainsKey('TemporaryAccessPassUsableOnce'))) {
            Write-Error -Message '-TemporaryAccessPassLifetime and -TemporaryAccessPassUsableOnce only work together with -TemporaryAccessPass.' -ErrorId 'TemporaryAccessPassRequired' -Category InvalidArgument
            return
        }
        if ($ForwardTo -and $RemoveForwarding) {
            Write-Error -Message 'Use -ForwardTo or -RemoveForwarding, not both.' -ErrorId 'ConflictingForwarding' -Category InvalidArgument
            return
        }
        if ($KeepForwardedCopy -and -not $ForwardTo) {
            Write-Error -Message '-KeepForwardedCopy only works together with -ForwardTo.' -ErrorId 'ForwardToRequired' -Category InvalidArgument
            return
        }
        foreach ($p in @($GrantMailboxPermission) + @($RemoveMailboxPermission)) {
            if ($null -ne $p -and (-not $p.permission -or -not $p.trusteeId)) {
                Write-Error -Message 'Each mailbox permission needs permission (fullAccess, sendAs or sendOnBehalf) and trusteeId, such as @{ permission = ''fullAccess''; trusteeId = ''<user id>'' }.' -ErrorId 'InvalidMailboxPermission' -Category InvalidArgument
                return
            }
        }
        foreach ($c in $GrantCalendarAccess) {
            if ($null -ne $c -and (-not $c.trusteeId -or $c.role -notin 'reviewer', 'editor', 'delegate')) {
                Write-Error -Message 'Each calendar share needs trusteeId and role (reviewer, editor or delegate), such as @{ trusteeId = ''<user id>''; role = ''reviewer'' }.' -ErrorId 'InvalidCalendarAccess' -Category InvalidArgument
                return
            }
        }
        $bothWays = @($AllowMailApp | Where-Object { $_ -in $BlockMailApp })
        if ($bothWays) {
            Write-Error -Message "Allow or block a mail app, not both: $($bothWays -join ', ')." -ErrorId 'ConflictingMailApp' -Category InvalidArgument
            return
        }
        $groupBothWays = @($AddGroup | Where-Object { $_ -in $RemoveGroup })
        if ($groupBothWays) {
            Write-Error -Message "Add the user to a group or remove them from it, not both: $($groupBothWays -join ', ')." -ErrorId 'ConflictingGroup' -Category InvalidArgument
            return
        }
        $body = ConvertTo-InforcerUserBody -BoundParameters $PSBoundParameters
        $steps = [System.Collections.Generic.List[string]]::new()
        # Mailbox steps: name -> request. Each is queued in Exchange Online and awaited before the next step.
        $mailboxCalls = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
        $addMailboxStep = {
            param([string]$Name, [string]$Path, [string]$Method, $Json)
            if ($mailboxCalls.ContainsKey($Name)) { return }  # the same change asked twice runs once
            $steps.Add($Name)
            $mailboxCalls[$Name] = @{ Path = $Path; Method = $Method; Body = $(if ($null -ne $Json) { $Json | ConvertTo-Json -Depth 100 -Compress }) }
        }
        if ($body.Count -gt 0) { $steps.Add("update $(@($body.Keys) -join ', ')") }
        # Licences are one request (so a swap is atomic). Removing only runs after the mailbox steps,
        # so a mailbox is converted to shared before its licence goes.
        $licenceFirst = [bool]$AddLicense
        if ($licenceFirst) { $steps.Add('change licences') }
        if ($AddGroup) { $steps.Add('add to groups') }
        if ($RemoveGroup) { $steps.Add('remove from groups') }
        if ($MailboxType) { & $addMailboxStep "convert mailbox to $($MailboxType.ToLower())" 'type' PATCH @{ type = $MailboxType.ToLower() } }
        if ($EnableArchive) { & $addMailboxStep 'turn on the online archive' 'archive' PATCH @{ enabled = $true } }
        if ($PSBoundParameters.ContainsKey('HiddenFromAddressLists')) {
            & $addMailboxStep $(if ($HiddenFromAddressLists) { 'hide mailbox from address lists' } else { 'show mailbox in address lists' }) 'addressListVisibility' PATCH @{ hidden = $HiddenFromAddressLists }
        }
        foreach ($address in $AddEmailAddress | Select-Object -Unique) { & $addMailboxStep "add email address $address" 'emailAddresses' POST @{ address = $address } }
        if ($PrimaryEmailAddress) { & $addMailboxStep "make $PrimaryEmailAddress the primary email address" 'emailAddresses' POST ([ordered]@{ address = $PrimaryEmailAddress; primary = $true }) }
        foreach ($address in $RemoveEmailAddress | Select-Object -Unique) { & $addMailboxStep "remove email address $address" "emailAddresses/$([System.Uri]::EscapeDataString($address))" DELETE $null }
        if ($PSBoundParameters.ContainsKey('AutoReply')) {
            $reply = [ordered]@{}
            $source = if ($AutoReply -is [System.Collections.IDictionary]) { [pscustomobject]$AutoReply } else { $AutoReply }
            foreach ($p in $source.PSObject.Properties) {
                # A read can be sent back: nulls and the read-only simplified are left out, dates get an offset.
                if ($null -eq $p.Value -or $p.Name -eq 'simplified') { continue }
                $reply[$p.Name] = if ($p.Value -is [datetime] -or $p.Value -is [datetimeoffset]) { $p.Value.ToUniversalTime().ToString("yyyy-MM-dd'T'HH:mm:ss'Z'", [cultureinfo]::InvariantCulture) } else { $p.Value }
            }
            if ($reply['status'] -eq 'disabled') { $reply = [ordered]@{ status = 'disabled' } }
            & $addMailboxStep $(if ($reply['status'] -eq 'disabled') { 'turn off automatic replies' } else { 'set automatic replies' }) 'autoReply' PATCH $reply
        }
        if ($ForwardTo) {
            $forward = [ordered]@{}
            $forward[$(if ($ForwardTo -as [guid]) { 'recipientUserId' } else { 'smtpAddress' })] = $ForwardTo
            $forward['keepCopy'] = $KeepForwardedCopy.IsPresent
            & $addMailboxStep "forward mail to $ForwardTo" 'forwarding' PATCH $forward
        }
        if ($RemoveForwarding) { & $addMailboxStep 'stop forwarding mail' 'forwarding' DELETE $null }
        # The API's spelling (fullAccess) whatever casing was typed, as for the calendar role.
        $permissionName = { param($n) if ("$n") { "$n".Substring(0, 1).ToLowerInvariant() + "$n".Substring(1) } }
        foreach ($p in $GrantMailboxPermission) {
            $grant = [ordered]@{ trusteeId = "$($p.trusteeId)"; permission = (& $permissionName $p.permission) }
            if ($null -ne $p.automapping) { $grant['automapping'] = [bool]$p.automapping }
            & $addMailboxStep "grant $($grant.permission) to $($p.trusteeId)" 'permissions' POST $grant
        }
        foreach ($p in $RemoveMailboxPermission) {
            $name = & $permissionName $p.permission
            & $addMailboxStep "remove $name from $($p.trusteeId)" "permissions/$([System.Uri]::EscapeDataString("$name"))/$([System.Uri]::EscapeDataString("$($p.trusteeId)"))" DELETE $null
        }
        foreach ($c in $GrantCalendarAccess) {
            & $addMailboxStep "share calendar with $($c.trusteeId) as $("$($c.role)".ToLower())" 'calendarAccess' POST ([ordered]@{ trusteeId = "$($c.trusteeId)"; role = "$($c.role)".ToLower() })
        }
        foreach ($trusteeId in $RemoveCalendarAccess | Select-Object -Unique) { & $addMailboxStep "remove calendar access of $trusteeId" "calendarAccess/$trusteeId" DELETE $null }
        foreach ($groupId in $AddMailGroup | Select-Object -Unique) { & $addMailboxStep "add to mail group $groupId" 'mailGroups' POST @{ groupId = "$groupId" } }
        foreach ($groupId in $RemoveMailGroup | Select-Object -Unique) { & $addMailboxStep "remove from mail group $groupId" "mailGroups/$groupId" DELETE $null }
        foreach ($ruleId in $RemoveInboxRule | Select-Object -Unique) { & $addMailboxStep "remove inbox rule $ruleId" "inboxRules/$([System.Uri]::EscapeDataString($ruleId))" DELETE $null }
        if ($RemoveAllInboxRules) { & $addMailboxStep 'remove every inbox rule' 'inboxRules?all=true' DELETE $null }
        if ($AllowMailApp -or $BlockMailApp) {
            # A case-insensitive lookup gives the API's spelling whatever casing was typed.
            $apiName = @{}
            foreach ($n in 'outlookWeb', 'outlookDesktop', 'outlookMac', 'exchangeWebServices', 'imap', 'pop', 'outlookApp', 'otherMailApps') { $apiName[$n] = $n }
            $apps = [ordered]@{}
            foreach ($app in $AllowMailApp) { $apps[$apiName[$app]] = $true }
            foreach ($app in $BlockMailApp) { $apps[$apiName[$app]] = $false }
            & $addMailboxStep "$(@(if ($AllowMailApp) { "allow $($AllowMailApp -join ', ')" }; if ($BlockMailApp) { "block $($BlockMailApp -join ', ')" }) -join ' and ')" 'mailApps' PATCH $apps
        }
        if ($RemoveLicense -and -not $licenceFirst) { $steps.Add('change licences') }
        if ($Password) { $steps.Add('reset password') }
        foreach ($methodId in $RemoveAuthenticationMethod | Select-Object -Unique) { $steps.Add("remove authentication method $methodId") }
        if ($ResetMfa) { $steps.Add('reset MFA') }
        if ($RevokeSessions) { $steps.Add('sign out of every session') }
        # Last, so no later failure can end the call before the pass (shown only once) is returned.
        if ($TemporaryAccessPass) { $steps.Add('create Temporary Access Pass') }
        if ($steps.Count -eq 0) {
            Write-Error -Message 'Nothing to change: pass at least one property, such as -Department or -AccountEnabled, or -AddLicense, -RemoveLicense, -AddGroup, -RemoveGroup, a mailbox change (such as -MailboxType, -AutoReply, -ForwardTo, -GrantCalendarAccess or -BlockMailApp), -Password, -RemoveAuthenticationMethod, -ResetMfa, -TemporaryAccessPass or -RevokeSessions.' -ErrorId 'NoChangeSpecified' -Category InvalidArgument
            return
        }

        try {
            $resolvedTenantId = Resolve-InforcerTenantId -TenantId $TenantId
        } catch {
            Write-Error -Message $_.Exception.Message -ErrorId 'InvalidTenantId' -Category InvalidArgument
            return
        }

        if (-not $PSCmdlet.ShouldProcess("user $UserId in tenant $resolvedTenantId", ($steps -join '; '))) { return }

        $userEndpoint = "/tenants/$resolvedTenantId/users/$([System.Uri]::EscapeDataString($UserId))"
        $done = [System.Collections.Generic.List[string]]::new()
        # One step: its error is the answer. Several: hold it back and report what was and wasn't done.
        $errorHandling = @{ ErrorVariable = 'stepErr' }
        if ($steps.Count -gt 1) { $errorHandling['ErrorAction'] = 'SilentlyContinue' }
        foreach ($step in $steps) {
            $stepErr = $null
            # An unexpected exception counts as this step failing, so the done/not-done report survives it.
            try {
                if ($step -eq 'reset password') {
                    $json = [ordered]@{
                        password                      = ConvertFrom-InforcerSecureString -SecureString $Password
                        forceChangePasswordNextSignIn = $ForceChangePasswordNextSignIn
                    } | ConvertTo-Json -Depth 100 -Compress
                    try {
                        $null = Invoke-InforcerApiRequest -Endpoint "$userEndpoint/password" -Method POST -Body $json @errorHandling
                    } finally { $json = $null }
                } elseif ($step -like 'remove authentication method *') {
                    $methodId = $step.Substring('remove authentication method '.Length)
                    $null = Invoke-InforcerApiRequest -Endpoint "$userEndpoint/authenticationMethods/$([System.Uri]::EscapeDataString($methodId))" -Method DELETE @errorHandling
                } elseif ($step -eq 'change licences') {
                    $json = [ordered]@{}
                    if ($AddLicense) { $json['addSkuIds'] = @($AddLicense | Select-Object -Unique | ForEach-Object { "$_" }) }
                    if ($RemoveLicense) { $json['removeSkuIds'] = @($RemoveLicense | Select-Object -Unique | ForEach-Object { "$_" }) }
                    $null = Invoke-InforcerApiRequest -Endpoint "$userEndpoint/assignLicenses" -Method POST -Body ($json | ConvertTo-Json -Depth 100 -Compress) @errorHandling
                } elseif ($step -in 'add to groups', 'remove from groups') {
                    $groups = @(if ($step -eq 'add to groups') { $AddGroup } else { $RemoveGroup }) | Select-Object -Unique | ForEach-Object { "$_" }
                    $json = @{ $(if ($step -eq 'add to groups') { 'add' } else { 'remove' }) = @($groups) } | ConvertTo-Json -Depth 100 -Compress
                    $null = Invoke-InforcerApiRequest -Endpoint "$userEndpoint/groups" -Method POST -Body $json @errorHandling
                } elseif ($mailboxCalls.ContainsKey($step)) {
                    $call = $mailboxCalls[$step]
                    $request = @{ Endpoint = "$userEndpoint/mailbox/$($call.Path)"; Method = $call.Method }
                    if ($call.Body) { $request['Body'] = $call.Body }
                    $action = Invoke-InforcerApiRequest @request @errorHandling
                    if (-not $stepErr) { Wait-InforcerMailboxAction -UserEndpoint $userEndpoint -ActionId $action.actionId -Step $step -UserId $UserId @errorHandling }
                } elseif ($step -eq 'create Temporary Access Pass') {
                    $json = [ordered]@{}
                    if ($PSBoundParameters.ContainsKey('TemporaryAccessPassLifetime')) { $json['lifetimeInMinutes'] = $TemporaryAccessPassLifetime }
                    if ($PSBoundParameters.ContainsKey('TemporaryAccessPassUsableOnce')) { $json['usableOnce'] = $TemporaryAccessPassUsableOnce }
                    $pass = Invoke-InforcerApiRequest -Endpoint "$userEndpoint/authenticationMethods/temporaryAccessPasses" -Method POST -Body ($json | ConvertTo-Json -Depth 100 -Compress) @errorHandling
                    # Emitted at once: the pass cannot be read again, so a later failing step must not lose it.
                    if (-not $stepErr -and $pass) {
                        $pass | Add-Member -NotePropertyName userId -NotePropertyValue $UserId -Force
                        $pass
                    }
                    $pass = $null
                } elseif ($step -eq 'reset MFA') {
                    $null = Invoke-InforcerApiRequest -Endpoint "$userEndpoint/mfa" -Method DELETE @errorHandling
                } elseif ($step -eq 'sign out of every session') {
                    $null = Invoke-InforcerApiRequest -Endpoint "$userEndpoint/revokeSessions" -Method POST @errorHandling
                } else {
                    $null = Invoke-InforcerApiRequest -Endpoint $userEndpoint -Method PATCH -Body ($body | ConvertTo-Json -Depth 100 -Compress) @errorHandling
                }
            } catch {
                $stepErr = @($_)
                if ($steps.Count -eq 1) { Write-Error -ErrorRecord $_ }
            }
            if (-not $stepErr) { $done.Add($step); continue }

            if ($steps.Count -eq 1) { return }
            $last = $stepErr[-1]
            $skipped = @($steps | Select-Object -Skip ($done.Count + 1))
            $message = "Could not $step for user $UserId. $($last.Exception.Message)" +
                $(if ($done.Count) { " Already done: $($done -join '; ')." } else { '' }) +
                $(if ($skipped.Count) { " Not done: $($skipped -join '; ')." } else { '' })
            Write-Error -Message $message -ErrorId 'UserUpdatePartlyApplied' -Category $last.CategoryInfo.Category
            return
        }
    }
}
