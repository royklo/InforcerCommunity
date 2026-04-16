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
        [string[]]$RequiredScopes = @('Directory.Read.All'),

        [Parameter(Mandatory = $false)]
        [string]$TenantId
    )

    # Auto-install Microsoft.Graph.Authentication if missing
    $graphModule = Get-Module -ListAvailable -Name 'Microsoft.Graph.Authentication'
    if (-not $graphModule) {
        Write-Host '  Installing Microsoft.Graph.Authentication module...' -ForegroundColor Yellow
        Install-Module -Name 'Microsoft.Graph.Authentication' -Scope CurrentUser -Force -AllowClobber
    }

    if (-not (Get-Module -Name 'Microsoft.Graph.Authentication')) {
        Import-Module -Name 'Microsoft.Graph.Authentication' -Force -ErrorAction Stop
    }

    # Check if already connected to the correct tenant with sufficient scopes
    $existingCtx = Get-MgContext -ErrorAction SilentlyContinue
    if ($existingCtx -and $existingCtx.Account) {
        $tenantMatch = [string]::IsNullOrWhiteSpace($TenantId) -or $existingCtx.TenantId -eq $TenantId
        $scopesMissing = @($RequiredScopes | Where-Object { $existingCtx.Scopes -notcontains $_ })
        if ($tenantMatch -and $scopesMissing.Count -eq 0) {
            Write-Host "  Reusing existing Graph session: $($existingCtx.Account) (tenant: $($existingCtx.TenantId))" -ForegroundColor Green
            $script:InforcerGraphConnected = $true
            return $existingCtx
        }
    }

    # Fresh sign-in needed (different tenant or missing scopes)
    # Disconnect existing session first to avoid double-prompt when switching tenants
    if ($existingCtx -and $existingCtx.Account) {
        Write-Verbose "  Disconnecting from previous Graph session ($($existingCtx.TenantId))..."
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
    }

    try {
        $connectParams = @{ Scopes = $RequiredScopes; NoWelcome = $true }
        if (-not [string]::IsNullOrWhiteSpace($TenantId)) {
            $connectParams['TenantId'] = $TenantId
            Write-Host "  Targeting Azure AD tenant: $TenantId" -ForegroundColor Gray
        }
        Write-Host '  Complete the sign-in in your browser (Ctrl+C to cancel)...' -ForegroundColor Gray
        Connect-MgGraph @connectParams -ErrorAction Stop
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
