function Set-InforcerGroup {
    <#
    .SYNOPSIS
        Adds users to a Microsoft Entra group and removes others from it, in one request.

        Required API scope(s): none; the API-key (beta) API cannot change groups.
        Required permission: User & Group Management (API client, unconfirmed which grant).

    .DESCRIPTION
        Changes a group's members with POST /tenants/{msTenantId}/groups/{groupId}/members. Needs a login
        with an API client (Connect-Inforcer -ClientId -ClientSecret); an API-key login gets the error
        RequiresApiClient.

        inforcer changes each user on its own, so a user who cannot be added does not stop the removals.
        A user already in the group, or not in it, counts as done, so the same command can safely run again.
        When some users changed and others did not, the error lists each user ("Steps: ...").
        Role-assignable groups, dynamic groups, distribution lists and mail-enabled security groups cannot
        be changed this way.

        To change the groups of one user, use Set-InforcerUser -AddGroup/-RemoveGroup.

    .PARAMETER TenantId
        The tenant: Microsoft tenant ID (GUID) or tenant name. Supports pipeline input.

    .PARAMETER Group
        The group: its Microsoft Entra object id or its display name.

    .PARAMETER AddMember
        The Microsoft Entra object ids of the users to add, at most 20.

    .PARAMETER RemoveMember
        The Microsoft Entra object ids of the users to remove, at most 20.

    .EXAMPLE
        Set-InforcerGroup -TenantId 'Contoso' -Group 'Sales' -AddMember '00000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000006'

        Adds two users to the group Sales.

    .EXAMPLE
        Set-InforcerGroup -TenantId 'Contoso' -Group '00000000-0000-0000-0000-0000000000c1' -AddMember '00000000-0000-0000-0000-000000000005' -RemoveMember '00000000-0000-0000-0000-000000000006' -WhatIf

        Shows the change without making it.

    .OUTPUTS
        None.

    .LINK
        https://github.com/royklo/InforcerCommunity/blob/main/docs/CMDLET-REFERENCE.md#set-inforcergroup

    .LINK
        Get-InforcerGroup

    .LINK
        Set-InforcerUser
    #>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([void])]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias('ClientTenantId', 'MsTenantId')]
        [object]$TenantId,

        [Parameter(Mandatory)]
        [Alias('GroupId')]
        [string]$Group,

        [ValidateCount(1, 20)]
        [guid[]]$AddMember,

        [ValidateCount(1, 20)]
        [guid[]]$RemoveMember
    )

    process {
        if (-not (Test-InforcerSession)) {
            Write-Error -Message 'Not connected to Inforcer. Use Connect-Inforcer first.' -ErrorId 'NotConnected' -Category ConnectionError
            return
        }
        if ($script:InforcerSession.ApiVersion -ne 'v1') {
            Write-Error -Message 'Changing group members needs a login with an API client (Connect-Inforcer -ClientId -ClientSecret). The API-key (beta) API cannot change groups.' -ErrorId 'RequiresApiClient' -Category InvalidOperation
            return
        }
        if (-not $AddMember -and -not $RemoveMember) {
            Write-Error -Message 'Nothing to change: pass -AddMember, -RemoveMember or both.' -ErrorId 'NoChangeSpecified' -Category InvalidArgument
            return
        }
        $bothWays = @($AddMember | Where-Object { $_ -in $RemoveMember })
        if ($bothWays) {
            Write-Error -Message "Add a user to the group or remove them from it, not both: $($bothWays -join ', ')." -ErrorId 'ConflictingMember' -Category InvalidArgument
            return
        }

        try {
            $resolvedTenantId = Resolve-InforcerTenantId -TenantId $TenantId
            $resolvedGroupId = Resolve-InforcerGroupId -GroupId $Group -TenantId $resolvedTenantId
        } catch {
            Write-Error -Message $_.Exception.Message -ErrorId 'InvalidTarget' -Category InvalidArgument
            return
        }

        $body = [ordered]@{}
        if ($AddMember) { $body['add'] = @($AddMember | Select-Object -Unique | ForEach-Object { "$_" }) }
        if ($RemoveMember) { $body['remove'] = @($RemoveMember | Select-Object -Unique | ForEach-Object { "$_" }) }
        $change = @(
            if ($body.Contains('add')) { "add $($body['add'].Count) member(s)" }
            if ($body.Contains('remove')) { "remove $($body['remove'].Count) member(s)" }
        ) -join '; '
        if (-not $PSCmdlet.ShouldProcess("group $resolvedGroupId in tenant $resolvedTenantId", $change)) { return }

        $null = Invoke-InforcerApiRequest -Endpoint "/tenants/$resolvedTenantId/groups/$resolvedGroupId/members" -Method POST -Body ($body | ConvertTo-Json -Depth 100 -Compress)
    }
}
