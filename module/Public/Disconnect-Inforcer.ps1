<#
.SYNOPSIS
    Disconnects from the Inforcer API and clears the session.
.DESCRIPTION
    Removes the stored session and clears authentication from memory.
    Always outputs a string: "Disconnected from Inforcer API." when a session was active,
    or "No active session to disconnect." when there was no session.
.EXAMPLE
    Disconnect-Inforcer
    Disconnects when connected; outputs "Disconnected from Inforcer API."
.EXAMPLE
    Disconnect-Inforcer
    When not connected, outputs "No active session to disconnect."
.OUTPUTS
    String (always)
.LINK
    https://github.com/royklo/InforcerCommunity/blob/main/docs/CMDLET-REFERENCE.md#disconnect-inforcer
.LINK
    Connect-Inforcer
#>
function Disconnect-Inforcer {
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
[OutputType([string])]
param()

if ($script:InforcerSession -and $script:InforcerSession.ApiKey -and $script:InforcerSession.BaseUrl) {
    if ($PSCmdlet.ShouldProcess('Inforcer session', 'Disconnect')) {
        $script:InforcerSession = $null
        $script:InforcerSettingsCatalog = $null

        # Also disconnect Microsoft Graph if it was connected via this module
        if ($script:InforcerGraphConnected) {
            try {
                Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
                Write-Verbose 'Disconnected from Microsoft Graph.'
            } catch { }
            $script:InforcerGraphConnected = $false
        }

        Write-Verbose 'Disconnected from Inforcer API. Session cleared.'
        'Disconnected from Inforcer API.'
    }
} else {
    Write-Verbose 'No active session to disconnect.'
    'No active session to disconnect.'
}
}
