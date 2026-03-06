# Test-AllCmdlets.ps1
# Loads the Inforcer module and runs each exported cmdlet with safe parameters to verify they execute
# without crashing. Run without an active connection; most Get-* cmdlets will produce an error (expected).
# Usage: from repo root: pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Test-AllCmdlets.ps1

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $PSCommandPath
$repoRoot = Split-Path -Parent $scriptDir
$modulePath = Join-Path $repoRoot 'module' 'Inforcer.psd1'

if (-not (Test-Path -LiteralPath $modulePath)) {
    Write-Error "Module not found: $modulePath"
    exit 1
}

Remove-Module -Name 'Inforcer' -ErrorAction SilentlyContinue
Import-Module $modulePath -Force
$exported = (Get-Module -Name 'Inforcer').ExportedCommands.Keys

$failed = 0
foreach ($name in $exported) {
    $err = $null
    $out = $null
    try {
        switch ($name) {
            'Disconnect-Inforcer' {
                $out = & $name
            }
            'Connect-Inforcer' {
                $key = ConvertTo-SecureString -String 'dummy' -AsPlainText -Force
                $out = & $name -ApiKey $key -Region uk -ErrorVariable err -ErrorAction SilentlyContinue
            }
            'Test-InforcerConnection' {
                $out = & $name -ErrorVariable err -ErrorAction SilentlyContinue
            }
            'Get-InforcerTenant' {
                $out = & $name -ErrorVariable err -ErrorAction SilentlyContinue
            }
            'Get-InforcerBaseline' {
                $out = & $name -ErrorVariable err -ErrorAction SilentlyContinue
            }
            'Get-InforcerTenantPolicies' {
                $out = & $name -TenantId 1 -ErrorVariable err -ErrorAction SilentlyContinue
            }
            'Get-InforcerAlignmentScore' {
                $out = & $name -ErrorVariable err -ErrorAction SilentlyContinue
            }
            'Get-InforcerAuditEvent' {
                $out = & $name -ErrorVariable err -ErrorAction SilentlyContinue
            }
            default {
                $out = & $name -ErrorVariable err -ErrorAction SilentlyContinue
            }
        }
        $hasOut = $null -ne $out -and (@($out).Count -ge 0)
        $hasErr = $null -ne $err -and (@($err).Count -gt 0)
        if (-not $hasOut -and -not $hasErr) {
            Write-Warning "$name produced no output and no error (possible silent failure)."
            $failed++
        } else {
            Write-Host "[OK] $name"
        }
    } catch {
        Write-Warning "$name threw: $($_.Exception.Message)"
        $failed++
    }
}

if ($failed -gt 0) {
    Write-Error "$failed cmdlet(s) had issues."
    exit 1
}
Write-Host "All $($exported.Count) cmdlets ran successfully (output or expected error)."
exit 0
