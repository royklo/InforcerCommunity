function Connect-InforcerGraph {
    <#
    .SYNOPSIS
        Connects to Microsoft Graph for documentation enrichment (group name resolution etc.).
    .DESCRIPTION
        Always performs a fresh interactive sign-in to Microsoft Graph. This ensures the session
        is current each time the module is used. Auto-installs Microsoft.Graph.Authentication
        if not present.

        The Graph session is stored in $script:InforcerGraphConnected so Disconnect-Inforcer
        knows to also disconnect Graph.

        Based on the Connect-ToMgGraph pattern from RKSolutions-Module.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string[]]$RequiredScopes = @('Directory.Read.All')
    )

    # Auto-install Microsoft.Graph.Authentication if missing
    $graphModule = Get-Module -ListAvailable -Name 'Microsoft.Graph.Authentication'
    if (-not $graphModule) {
        Write-Host '  Installing Microsoft.Graph.Authentication module...' -ForegroundColor Yellow
        Install-Module -Name 'Microsoft.Graph.Authentication' -Scope CurrentUser -Force -AllowClobber -SkipPublisherCheck
    }

    if (-not (Get-Module -Name 'Microsoft.Graph.Authentication')) {
        Import-Module -Name 'Microsoft.Graph.Authentication' -Force -ErrorAction Stop
    }

    # Always do a fresh sign-in so the session is current
    try {
        Connect-MgGraph -Scopes $RequiredScopes -NoWelcome -ErrorAction Stop
        $newContext = Get-MgContext
        if ($newContext) {
            $script:InforcerGraphConnected = $true
            return $newContext
        }
        throw 'Connection attempt completed but unable to confirm connection'
    } catch {
        Write-Error "Error connecting to Microsoft Graph: $_"
        $script:InforcerGraphConnected = $false
        return $null
    }
}
