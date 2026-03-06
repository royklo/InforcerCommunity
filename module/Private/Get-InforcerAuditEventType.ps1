# Internal: returns audit event type names from the API.
# Used by Get-InforcerAuditEvent when -EventType is omitted (resolve "all types").
# Tab completion for -EventType uses the static list in Get-InforcerAuditEvent.ps1 so it always works.
# Uses global cache for API response so "all types" resolution is consistent.

if (-not $global:InforcerCachedEventTypes) {
    $global:InforcerCachedEventTypes = @(
        'authentication', 'failedAuthentication', 'supportAccessInvoke', 'userGroupCreate', 'userGroupUpdate',
        'userGroupDelete', 'userGroupMembershipModified', 'clientStatusChanged', 'clientCreated', 'salesAdminUpdated',
        'clientAdminUpdated', 'sharedBaselinesManaged', 'alertRuleCreate', 'alertRuleUpdate', 'alertRuleDelete',
        'apiKeyCreate', 'apiKeyDelete', 'apiKeyUsage', 'tenantUserCreate', 'tenantUserUpdate', 'tenantUserResetMfa',
        'tenantUserResetPassword', 'tenantUserRevokedSessions', 'tenantUserGroupMembershipModified', 'tenantUserOffboardingQueued',
        'tenantUserLicensesModified', 'tenantOnboard', 'tenantRefresh', 'tenantDelete', 'userCreate', 'userDelete',
        'userResetPassword', 'userResetMfa', 'userToggleEnable', 'userAutoProvision', 'userToggleSso',
        'tenantGroupCreate', 'tenantGroupUpdate', 'tenantGroupMembershipsModified', 'tenantGroupsDeployment',
        'policiesDeployment', 'policiesRestore', 'policiesRename', 'policiesDelete', 'tenantAssessmentRun',
        'tenantAssessmentSuccess', 'tenantAssessmentFailure', 'copilotAssessmentRun', 'copilotAssessmentSuccess', 'copilotAssessmentFailure',
        'tenantLicenseUpdate', 'clientLicenseUpdate'
    )
}

function Get-InforcerAuditEventType {
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
