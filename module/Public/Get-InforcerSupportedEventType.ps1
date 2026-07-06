# Internal: returns audit event type names from the API.
# Used by Get-InforcerAuditEvent when -EventType is omitted (resolve "all types").
# $global:InforcerCachedEventTypes is populated at module import from the static
# fallback below, then refreshed with the live API response on the first
# authenticated call. The -EventType ArgumentCompleter in Get-InforcerAuditEvent.ps1
# reads this same variable, so tab completion tracks the server-side list once the
# user is connected — no need to ship a module release when new event types arrive.

if (-not $global:InforcerCachedEventTypes) {
    # Static fallback used until an authenticated Get-InforcerSupportedEventType call
    # refreshes this cache with the live server-side list. Kept alphabetically sorted so
    # diffs against a live API dump are readable.
    $global:InforcerCachedEventTypes = @(
        'alertRuleCreate', 'alertRuleDelete', 'alertRuleUpdate',
        'apiKeyCreate', 'apiKeyDelete', 'apiKeyUpdate', 'apiKeyUsage',
        'assignmentsModification',
        'authentication',
        'clientAdminUpdated', 'clientCreated', 'clientLicenseUpdate',
        'clientSsoConfigurationCreated', 'clientSsoConfigurationRemoved',
        'clientSsoConfigurationToggled', 'clientSsoConfigurationUpdated',
        'clientStatusChanged',
        'copilotAssessmentFailure', 'copilotAssessmentRun', 'copilotAssessmentSuccess',
        'copilotManagerToggle',
        'failedAuthentication',
        'onboardingLinkCreated', 'onboardingLinkDeleted',
        'onboardingLinkSlugRotated', 'onboardingLinkUpdated',
        'policiesDelete', 'policiesDeployment', 'policiesRename', 'policiesRestore',
        'reportQueued',
        'salesAdminUpdated',
        'scheduleCreate', 'scheduleDelete', 'scheduleUpdate',
        'securityGroupCreate', 'securityGroupDelete', 'securityGroupFilterUpdate',
        'securityGroupMembersAdded', 'securityGroupMembersRemoved',
        'securityGroupRoleUpdate', 'securityGroupUpdate',
        'sharedBaselinesManaged',
        'supportAccessInvoke',
        'tenantAssessmentFailure', 'tenantAssessmentRun', 'tenantAssessmentSuccess',
        'tenantDelete',
        'tenantGroupCreate', 'tenantGroupMembershipsModified',
        'tenantGroupUpdate', 'tenantGroupsDeployment',
        'tenantLicenseUpdate', 'tenantOnboard', 'tenantRefresh',
        'tenantUserAuthenticationMethodDelete',
        'tenantUserCreate', 'tenantUserGroupMembershipModified',
        'tenantUserLicensesModified',
        'tenantUserOffboardingFailed', 'tenantUserOffboardingQueued',
        'tenantUserOffboardingScheduled', 'tenantUserOffboardingSucceeded',
        'tenantUserResetMfa', 'tenantUserResetPassword',
        'tenantUserRevokedSessions',
        'tenantUserTemporaryAccessPassCreate',
        'tenantUserUpdate',
        'userAutoProvision', 'userCreate', 'userDelete',
        'userGroupCreate', 'userGroupDelete',
        'userGroupMembershipModified', 'userGroupUpdate',
        'userResetMfa', 'userResetPassword',
        'userToggleClientAdmin', 'userToggleEnable', 'userToggleSso'
    )
}

function Get-InforcerSupportedEventType {
    <#
    .SYNOPSIS
    Returns a list of available audit event types from the Inforcer API.

    Required API scope(s): Audit.Read (unconfirmed — see docs/API-REFERENCE.md)

    .DESCRIPTION
    Retrieves the valid event type names that can be used with Get-InforcerAuditEvent.
    This function is primarily used for tab completion of the -EventType parameter in Get-InforcerAuditEvent.
    Requires an active Inforcer session (use Connect-Inforcer to establish one).

    .OUTPUTS
    System.String
    Returns a list of audit event type names as strings.

    .EXAMPLE
    Get-InforcerSupportedEventType
    Returns all available audit event type names for use with Get-InforcerAuditEvent.

    .LINK
    https://github.com/royklo/InforcerCommunity/blob/main/docs/Get-InforcerSupportedEventType.md
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if (-not (Test-InforcerSession)) {
        if ($global:InforcerCachedEventTypes -and $global:InforcerCachedEventTypes.Count -gt 0) {
            $global:InforcerCachedEventTypes | ForEach-Object { $_ }
            return
        }
        Write-Error -Message 'Not connected yet. Please run Connect-Inforcer first.' -ErrorId 'NotConnected' -Category ConnectionError
        return
    }

    try {
        $response = Invoke-InforcerApiRequest -Endpoint '/beta/auditEvents/eventTypes' -Method GET -OutputType PowerShellObject
        if ($null -eq $response) {
            if ($global:InforcerCachedEventTypes -and $global:InforcerCachedEventTypes.Count -gt 0) {
                $global:InforcerCachedEventTypes | ForEach-Object { $_ }
            }
            return
        }

        function GetEventTypeName($o) {
            if ($o -is [PSObject]) {
                $n = $o.PSObject.Properties['name'].Value
                if (-not $n) { $n = $o.PSObject.Properties['Name'].Value }
                return $n?.ToString()
            }
            return $o?.ToString()
        }

        function ResolveEventTypes($typesObj) {
            if ($null -eq $typesObj) { return @() }
            if ($typesObj -is [array]) {
                return @($typesObj | ForEach-Object { GetEventTypeName $_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
            }
            if ($typesObj -is [PSObject]) {
                foreach ($propName in 'eventTypes', 'EventTypes', 'data', 'Data', 'items', 'Items') {
                    $prop = $typesObj.PSObject.Properties[$propName].Value
                    if ($prop -is [object[]]) {
                        return @($prop | ForEach-Object { GetEventTypeName $_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
                    }
                }
            }
            return @()
        }

        $types = ResolveEventTypes $response
        if ($types -and $types.Count -gt 0) {
            $global:InforcerCachedEventTypes = @($types)
        }
        foreach ($t in $types) {
            $t
        }
    } catch {
        if ($global:InforcerCachedEventTypes -and $global:InforcerCachedEventTypes.Count -gt 0) {
            $global:InforcerCachedEventTypes | ForEach-Object { $_ }
            return
        }
        Write-Error -Message $_.Exception.Message -ErrorId 'GetAuditEventTypeFailed' -Category ConnectionError
    }
}
