function Set-InforcerUser {
    <#
    .SYNOPSIS
        Updates a Microsoft Entra user's profile, manager or sign-in, resets their password or signs them out everywhere.

        Required API scope(s): none; the API-key (beta) API cannot update users.
        Required permission: User & Group Management (API client, unconfirmed which grant).

    .DESCRIPTION
        Updates a user with PATCH /tenants/{msTenantId}/users/{userId}. Needs a login with an API client
        (Connect-Inforcer -ClientId -ClientSecret); an API-key login gets the error RequiresApiClient.

        Only the parameters you pass are changed; everything else stays as it is. Pass an empty string
        ('') or $null to clear a field, such as -JobTitle '' or -ManagerId '' to remove the manager.
        DisplayName, MailNickname, UserPrincipalName and Mail cannot be cleared.

        -Password sets a new password (POST /tenants/{msTenantId}/users/{userId}/password); the user must
        change it when they next sign in unless you pass -ForceChangePasswordNextSignIn $false.
        -RevokeSessions signs the user out of every session (POST .../users/{userId}/revokeSessions);
        access tokens already issued stay valid until they expire, typically within 90 minutes.
        In one call the steps run in this order: profile update, password reset, sign-out. When a step
        fails, the later steps are skipped and the error says which steps were already done.

        -AccountEnabled $false blocks sign-in, but existing sessions last until their tokens expire;
        add -RevokeSessions to end them.
        Get-InforcerUser can show the old values for up to about five minutes, because the API caches users. Returns nothing.

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

    .PARAMETER Password
        A new password as a SecureString. It must meet the tenant's password policy.
        inforcer does not store or log it.

    .PARAMETER ForceChangePasswordNextSignIn
        Whether the user must change the new password when they next sign in. Default $true.
        Only together with -Password.

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
        Set-InforcerUser -TenantId 'Contoso' -UserId '00000000-0000-0000-0000-000000000005' -UsageLocation 'GB' -WhatIf

        Shows what would change without changing it.

    .OUTPUTS
        None

    .LINK
        https://github.com/royklo/InforcerCommunity/blob/main/docs/CMDLET-REFERENCE.md#set-inforceruser

    .LINK
        New-InforcerUser

    .LINK
        Get-InforcerUser
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([void])]
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

        [System.Security.SecureString]$Password,

        [bool]$ForceChangePasswordNextSignIn = $true,

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
        $body = ConvertTo-InforcerUserBody -BoundParameters $PSBoundParameters
        $steps = [System.Collections.Generic.List[string]]::new()
        if ($body.Count -gt 0) { $steps.Add("update $(@($body.Keys) -join ', ')") }
        if ($Password) { $steps.Add('reset password') }
        if ($RevokeSessions) { $steps.Add('sign out of every session') }
        if ($steps.Count -eq 0) {
            Write-Error -Message 'Nothing to change: pass at least one property, such as -Department or -AccountEnabled, or -Password or -RevokeSessions.' -ErrorId 'NoChangeSpecified' -Category InvalidArgument
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
            if ($step -eq 'reset password') {
                $json = [ordered]@{
                    password                      = ConvertFrom-InforcerSecureString -SecureString $Password
                    forceChangePasswordNextSignIn = $ForceChangePasswordNextSignIn
                } | ConvertTo-Json -Compress
                try {
                    $null = Invoke-InforcerApiRequest -Endpoint "$userEndpoint/password" -Method POST -Body $json @errorHandling
                } finally { $json = $null }
            } elseif ($step -eq 'sign out of every session') {
                $null = Invoke-InforcerApiRequest -Endpoint "$userEndpoint/revokeSessions" -Method POST @errorHandling
            } else {
                $null = Invoke-InforcerApiRequest -Endpoint $userEndpoint -Method PATCH -Body ($body | ConvertTo-Json -Depth 100 -Compress) @errorHandling
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
