function Set-InforcerTdrAutoContainment {
    <#
    .SYNOPSIS
        Turns auto-containment on or off for a tenant and changes the settings that limit what it may do.

        Required API scope(s): none; the API-key (beta) API has no TDR endpoints.
        Required permission: Threats, manage auto remediation (API client, tdr:auto_remediation:manage).

    .DESCRIPTION
        PATCH /tenants/{msTenantId}/tdr/autoContainment. Only the parameters you pass change; the rest is
        kept. Turning auto-containment on lets inforcer act on the tenant by itself, such as blocking a
        user's sign-in, so the cmdlet asks for confirmation by default (-Confirm:$false skips it).

        On a tenant where auto-containment was never set up, passing any setting sets it up, and it stays
        off unless you also pass -Enabled $true. -Enabled $true alone on such a tenant is refused (409), so
        it is never turned on with settings nobody chose. Settings you leave out then take their
        defaults: severity critical and every list empty.

        An empty list (@()) means: every user and app action (-AllowedAction), no device action
        (-AllowedDeviceAction), any account (-AllowedTarget), no excluded account (-DeniedTarget).

        Returns the tenant's auto-containment after the change. Needs a login with an API client
        (Connect-Inforcer -ClientId -ClientSecret); an API-key login gets the error RequiresApiClient.

    .PARAMETER TenantId
        The tenant: Microsoft tenant ID (GUID) or tenant name. Supports pipeline input.

    .PARAMETER Enabled
        $true turns auto-containment on, $false turns it off.

    .PARAMETER SeverityThreshold
        The lowest threat severity auto-containment acts on: critical or high.

    .PARAMETER AllowedAction
        The actions it may take on users and apps. inforcer accepts: blockUser, disableServicePrincipal, removeAppCredentials, removeMailRule, removePhishingEmail, removeRole, removeSiteAdmin, revokeAllSessions, revokeConsent. @() allows all.

    .PARAMETER AllowedDeviceAction
        The actions it may take on devices: isolateDevice, quarantineFile, fullScanClean. @() allows none.

    .PARAMETER AllowedTarget
        The accounts it may act on, by user principal name, object id or app id; a trailing * matches every
        value that starts with the rest. At most 50. @() allows any account.

    .PARAMETER DeniedTarget
        The accounts it must never act on, written as -AllowedTarget. These win over -AllowedTarget. At most 50.

    .PARAMETER OutputType
        PowerShellObject (default) or JsonObject. JSON output uses Depth 100.

    .EXAMPLE
        Set-InforcerTdrAutoContainment -TenantId 'Contoso' -SeverityThreshold critical -AllowedAction blockUser -DeniedTarget 'breakglass@contoso.com'

        Sets up auto-containment for critical threats, only blocking sign-in and never for the break-glass
        account. It stays off.

    .EXAMPLE
        Set-InforcerTdrAutoContainment -TenantId 'Contoso' -Enabled $true

        Turns on auto-containment that is already set up (asks for confirmation).

    .EXAMPLE
        Set-InforcerTdrAutoContainment -TenantId 'Contoso' -Enabled $false -Confirm:$false

        Turns it off without asking.

    .EXAMPLE
        Set-InforcerTdrAutoContainment -TenantId 'Contoso' -AllowedDeviceAction isolateDevice -OutputType JsonObject

        Lets it isolate devices too, and returns the result as JSON (asks for confirmation).

    .OUTPUTS
        PSObject (InforcerCommunity.TdrAutoContainment), or a JSON string with -OutputType JsonObject.

    .LINK
        https://github.com/royklo/InforcerCommunity/blob/main/docs/CMDLET-REFERENCE.md#set-inforcertdrautocontainment

    .LINK
        Get-InforcerTdrAutoContainment
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    [OutputType([PSObject], [string])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('ClientTenantId', 'MsTenantId')]
        [object]$TenantId,

        [bool]$Enabled,

        [ValidateSet('critical', 'high')]
        [string]$SeverityThreshold,

        [AllowEmptyCollection()]
        [ValidateCount(0, 50)]
        [string[]]$AllowedAction,

        [AllowEmptyCollection()]
        [ValidateSet('isolateDevice', 'quarantineFile', 'fullScanClean')]
        [string[]]$AllowedDeviceAction,

        [AllowEmptyCollection()]
        [ValidateCount(0, 50)]
        [string[]]$AllowedTarget,

        [AllowEmptyCollection()]
        [ValidateCount(0, 50)]
        [string[]]$DeniedTarget,

        [Parameter(Mandatory = $false)]
        [ValidateSet('PowerShellObject', 'JsonObject')]
        [string]$OutputType = 'PowerShellObject'
    )

    process {
        if (-not (Test-InforcerSession)) {
            Write-Error -Message 'Not connected to Inforcer. Use Connect-Inforcer first.' -ErrorId 'NotConnected' -Category ConnectionError
            return
        }
        if ($script:InforcerSession.ApiVersion -ne 'v1') {
            Write-Error -Message 'Auto-containment needs a login with an API client (Connect-Inforcer -ClientId -ClientSecret). The API-key (beta) API has no threat detection and response endpoints.' -ErrorId 'RequiresApiClient' -Category InvalidOperation
            return
        }

        $settings = [ordered]@{}
        $map = [ordered]@{ SeverityThreshold = 'severityThreshold'; AllowedAction = 'allowedActions'; AllowedDeviceAction = 'allowedDeviceActions'; AllowedTarget = 'allowedTargets'; DeniedTarget = 'deniedTargets' }
        foreach ($name in $map.Keys) {
            if (-not $PSBoundParameters.ContainsKey($name)) { continue }
            $value = $PSBoundParameters[$name]
            $settings[$map[$name]] = if ($name -eq 'SeverityThreshold') { $value } else { , @($value | Select-Object -Unique) }
        }
        $body = [ordered]@{}
        if ($PSBoundParameters.ContainsKey('Enabled')) { $body['enabled'] = $Enabled }
        if ($settings.Count) { $body['settings'] = $settings }
        if (-not $body.Count) {
            Write-Error -Message 'Nothing to change: pass -Enabled or at least one setting.' -ErrorId 'NoChangeSpecified' -Category InvalidArgument
            return
        }

        try {
            $resolvedTenantId = Resolve-InforcerTenantId -TenantId $TenantId
        } catch {
            Write-Error -Message $_.Exception.Message -ErrorId 'InvalidTenantId' -Category InvalidArgument
            return
        }

        $change = @(
            if ($body.Contains('enabled')) { if ($Enabled) { 'turn auto-containment ON (inforcer may act on the tenant by itself)' } else { 'turn auto-containment off' } }
            if ($settings.Count) { "change $(@($settings.Keys) -join ', ')" }
        ) -join '; '
        if (-not $PSCmdlet.ShouldProcess("tenant $resolvedTenantId", $change)) { return }

        $result = Invoke-InforcerApiRequest -Endpoint "/tenants/$resolvedTenantId/tdr/autoContainment" -Method PATCH -Body ($body | ConvertTo-Json -Depth 100 -Compress) -PreserveStructure
        if ($null -eq $result) { return }
        ConvertTo-InforcerTdrAutoContainment -Result $result -TenantId $resolvedTenantId -OutputType $OutputType
    }
}
