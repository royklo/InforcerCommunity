function Connect-InforcerGraph {
    <#
    .SYNOPSIS
        Ensures Microsoft Graph is connected with required scopes for documentation enrichment.
    .DESCRIPTION
        Checks for an existing Graph session and validates scopes. If missing scopes are detected,
        reconnects interactively. If no session exists, launches interactive sign-in.
        Auto-installs Microsoft.Graph.Authentication if not present.

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

    $contextInfo = Get-MgContext -ErrorAction SilentlyContinue
    $reconnect = $false

    if ($contextInfo) {
        $currentScopes = $contextInfo.Scopes
        $missingScopes = $RequiredScopes | Where-Object { $_ -notin $currentScopes }
        if ($missingScopes) {
            Write-Host "  Missing required scopes ($($missingScopes -join ', ')); reconnecting..." -ForegroundColor Yellow
            $reconnect = $true
        } else {
            Write-Verbose 'Already connected to Graph with required scopes.'
            return $contextInfo
        }
    } else {
        $reconnect = $true
    }

    if ($reconnect) {
        try {
            Connect-MgGraph -Scopes $RequiredScopes -NoWelcome -ErrorAction Stop
            $newContext = Get-MgContext
            if ($newContext) { return $newContext }
            throw 'Connection attempt completed but unable to confirm connection'
        } catch {
            Write-Error "Error connecting to Microsoft Graph: $_"
            return $null
        }
    }

    return $contextInfo
}
