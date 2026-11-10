function Set-InforcerUser {
    <#
    .SYNOPSIS
        Updates a Microsoft Entra user's profile, manager or sign-in in a tenant.

        Required API scope(s): none; the API-key (beta) API cannot update users.
        Required permission: User & Group Management (API client, unconfirmed which grant).

    .DESCRIPTION
        Updates a user with PATCH /tenants/{msTenantId}/users/{userId}. Needs a login with an API client
        (Connect-Inforcer -ClientId -ClientSecret); an API-key login gets the error RequiresApiClient.

        Only the parameters you pass are changed; everything else stays as it is. Pass an empty string
        ('') or $null to clear a field, such as -JobTitle '' or -ManagerId '' to remove the manager.
        DisplayName, MailNickname, UserPrincipalName and Mail cannot be cleared.

        -AccountEnabled $false blocks sign-in, but existing sessions last until their tokens expire.
        A change can take a few seconds to show in Get-InforcerUser. Returns nothing.

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

        [string]$ManagerId
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

        $body = ConvertTo-InforcerUserBody -BoundParameters $PSBoundParameters
        if ($body.Count -eq 0) {
            Write-Error -Message 'Nothing to change: pass at least one property, such as -Department or -AccountEnabled.' -ErrorId 'NoChangeSpecified' -Category InvalidArgument
            return
        }

        try {
            $resolvedTenantId = Resolve-InforcerTenantId -TenantId $TenantId
        } catch {
            Write-Error -Message $_.Exception.Message -ErrorId 'InvalidTenantId' -Category InvalidArgument
            return
        }

        if (-not $PSCmdlet.ShouldProcess("user $UserId in tenant $resolvedTenantId", "Update $(@($body.Keys) -join ', ')")) { return }

        $json = $body | ConvertTo-Json -Depth 100 -Compress
        $null = Invoke-InforcerApiRequest -Endpoint "/tenants/$resolvedTenantId/users/$([System.Uri]::EscapeDataString($UserId))" -Method PATCH -Body $json
    }
}
