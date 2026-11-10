function New-InforcerUser {
    <#
    .SYNOPSIS
        Creates a Microsoft Entra user in a tenant.

        Required API scope(s): none; the API-key (beta) API cannot create users.
        Required permission: User & Group Management (API client, unconfirmed which grant).

    .DESCRIPTION
        Creates a user with POST /tenants/{msTenantId}/users. Needs a login with an API client
        (Connect-Inforcer -ClientId -ClientSecret); an API-key login gets the error RequiresApiClient.

        The user can sign in by default (-AccountEnabled $true) and must change the password at the
        first sign-in (-ForceChangePasswordNextSignIn $true). -MailNickname defaults to the part of
        -UserPrincipalName before the @. The password must meet the tenant's password policy.

        Returns the new user's id with the tenant, display name and user principal name, so the result
        can be piped to Set-InforcerUser. A new user can take a few seconds to show in Get-InforcerUser.

    .PARAMETER TenantId
        The tenant's Microsoft tenant GUID or tenant name. Supports pipeline input by property name.

    .PARAMETER DisplayName
        The name shown for the user.

    .PARAMETER UserPrincipalName
        The sign-in name, such as jo.bloggs@contoso.com. The domain must be verified in the tenant.

    .PARAMETER Password
        The initial password as a SecureString. It must meet the tenant's password policy.

    .PARAMETER MailNickname
        The mail alias. Defaults to the part of -UserPrincipalName before the @.

    .PARAMETER ForceChangePasswordNextSignIn
        Whether the user must change the password at the first sign-in. Default: $true.

    .PARAMETER AccountEnabled
        Whether the user can sign in. Default: $true.

    .PARAMETER GivenName
        First name.

    .PARAMETER Surname
        Last name.

    .PARAMETER JobTitle
        Job title.

    .PARAMETER Department
        Department.

    .PARAMETER OfficeLocation
        Office location.

    .PARAMETER StreetAddress
        Street address.

    .PARAMETER City
        City.

    .PARAMETER State
        State or province.

    .PARAMETER PostalCode
        Postal code.

    .PARAMETER Country
        Country or region.

    .PARAMETER MobilePhone
        Mobile phone number.

    .PARAMETER UsageLocation
        Two-letter country code (ISO 3166) where the user's licences are used, such as GB. Needed before
        licences can be assigned.

    .PARAMETER PreferredLanguage
        Preferred language, such as en-GB.

    .PARAMETER CompanyName
        Company name.

    .PARAMETER EmployeeId
        Employee id (at most 16 characters).

    .PARAMETER EmployeeType
        Employee type, such as Employee or Contractor.

    .PARAMETER Mail
        Email address.

    .PARAMETER BusinessPhones
        Business phone number. Microsoft Entra allows one.

    .PARAMETER OtherMails
        Other email addresses.

    .PARAMETER ManagerId
        The Microsoft Entra object id of the user's manager.

    .PARAMETER OutputType
        Output type: 'PowerShellObject' (default) or 'JsonObject' (JSON string, depth 100).
        Piped tenants with JsonObject return one array for all of them.

    .EXAMPLE
        $password = Read-Host -AsSecureString -Prompt 'Initial password'
        New-InforcerUser -TenantId 'Contoso' -DisplayName 'Jo Bloggs' -UserPrincipalName 'jo.bloggs@contoso.com' -Password $password

        Creates Jo Bloggs in the tenant Contoso. Jo must change the password at the first sign-in.

    .EXAMPLE
        New-InforcerUser -TenantId 'Contoso' -DisplayName 'Jo Bloggs' -UserPrincipalName 'jo.bloggs@contoso.com' -Password $password -GivenName 'Jo' -Surname 'Bloggs' -Department 'Sales' -UsageLocation 'GB' -AccountEnabled $false

        Creates the user with profile details, but blocked from signing in until enabled with Set-InforcerUser.

    .EXAMPLE
        New-InforcerUser -TenantId 'Contoso' -DisplayName 'Jo Bloggs' -UserPrincipalName 'jo.bloggs@contoso.com' -Password $password -WhatIf

        Shows what would be created without creating it.

    .EXAMPLE
        New-InforcerUser -TenantId 'Contoso' -DisplayName 'Jo Bloggs' -UserPrincipalName 'jo.bloggs@contoso.com' -Password $password -OutputType JsonObject

        Returns the new user's id, tenant, display name and user principal name as a JSON string.

    .OUTPUTS
        PSObject or String (when -OutputType JsonObject)

    .LINK
        https://github.com/royklo/InforcerCommunity/blob/main/docs/CMDLET-REFERENCE.md#new-inforceruser

    .LINK
        Set-InforcerUser

    .LINK
        Get-InforcerUser
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([PSObject], [string])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('ClientTenantId', 'MsTenantId')]
        [object]$TenantId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DisplayName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$UserPrincipalName,

        [Parameter(Mandatory)]
        [System.Security.SecureString]$Password,

        [ValidateNotNullOrEmpty()]
        [string]$MailNickname,

        [bool]$ForceChangePasswordNextSignIn = $true,

        [bool]$AccountEnabled = $true,

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
        [string]$Mail,
        [string[]]$BusinessPhones,
        [string[]]$OtherMails,
        [string]$ManagerId,

        [ValidateSet('PowerShellObject', 'JsonObject')]
        [string]$OutputType = 'PowerShellObject'
    )

    begin { $pipedJson = [System.Collections.Generic.List[object]]::new() }

    process {
        if (-not (Test-InforcerSession)) {
            Write-Error -Message 'Not connected to Inforcer. Use Connect-Inforcer first.' -ErrorId 'NotConnected' -Category ConnectionError
            return
        }
        if ($script:InforcerSession.ApiVersion -ne 'v1') {
            Write-Error -Message 'Creating users needs a login with an API client (Connect-Inforcer -ClientId -ClientSecret). The API-key (beta) API cannot create users.' -ErrorId 'RequiresApiClient' -Category InvalidOperation
            return
        }

        try {
            $resolvedTenantId = Resolve-InforcerTenantId -TenantId $TenantId
        } catch {
            Write-Error -Message $_.Exception.Message -ErrorId 'InvalidTenantId' -Category InvalidArgument
            return
        }

        if (-not $PSCmdlet.ShouldProcess("$UserPrincipalName in tenant $resolvedTenantId", 'Create user')) { return }

        $body = ConvertTo-InforcerUserBody -BoundParameters $PSBoundParameters
        $body['accountEnabled'] = $AccountEnabled
        if (-not $body['mailNickname']) { $body['mailNickname'] = ($UserPrincipalName -split '@')[0] }
        $body['passwordProfile'] = [ordered]@{
            password                      = ConvertFrom-InforcerSecureString -SecureString $Password
            forceChangePasswordNextSignIn = $ForceChangePasswordNextSignIn
        }
        try {
            $json = $body | ConvertTo-Json -Depth 100 -Compress
            $body = $null
            $response = Invoke-InforcerApiRequest -Endpoint "/tenants/$resolvedTenantId/users" -Method POST -Body $json -PreserveStructure
        } finally {
            $json = $null
            $body = $null
        }
        if ($null -eq $response) { return }

        foreach ($p in ([ordered]@{ TenantId = $resolvedTenantId; displayName = $DisplayName; userPrincipalName = $UserPrincipalName }).GetEnumerator()) {
            if (-not $response.PSObject.Properties[$p.Key]) {
                $response.PSObject.Properties.Add([System.Management.Automation.PSNoteProperty]::new($p.Key, $p.Value))
            }
        }

        if ($OutputType -eq 'JsonObject') {
            if ($PSCmdlet.MyInvocation.ExpectingInput) { $pipedJson.Add($response); return }
            return $response | ConvertTo-Json -Depth 100
        }
        $response.PSObject.TypeNames.Insert(0, 'InforcerCommunity.CreatedUser')
        $response
    }

    end {
        if ($PSCmdlet.MyInvocation.ExpectingInput -and $OutputType -eq 'JsonObject' -and $pipedJson.Count -gt 0) {
            ConvertTo-Json -InputObject @($pipedJson) -Depth 100
        }
    }
}
