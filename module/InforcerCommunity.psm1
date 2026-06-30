# InforcerCommunity PowerShell Script Module (community project)
# Private helpers (not exported)
$privatePath = Join-Path $PSScriptRoot 'Private'
Get-ChildItem -Path $privatePath -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }
# Public cmdlets (exported via manifest)
$publicPath = Join-Path $PSScriptRoot 'Public'
Get-ChildItem -Path $publicPath -Filter '*.ps1' -Recurse | ForEach-Object { . $_.FullName }

# Eager-initialize the monotonically-increasing progress ID seed used by Invoke-InforcerReport.
# Done here at module load (single-threaded by definition) to eliminate the race where two
# parallel runspaces both observe $null and lazy-init to the same starting value.
$script:InforcerProgressIdSeed = 10000

# Warn users who force-reimport the module mid-session that session and caches are lost.
$ExecutionContext.SessionState.Module.OnRemove = {
    if ($script:InforcerSession -and $script:InforcerSession.ApiKey -and $script:InforcerSession.BaseUrl) {
        Write-Warning 'InforcerCommunity module unloaded — active session and caches are cleared. Re-run Connect-Inforcer to continue.'
    }
}
