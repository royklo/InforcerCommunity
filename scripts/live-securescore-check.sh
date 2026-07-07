#!/usr/bin/env zsh
# live-securescore-check.sh — quick smoke test for the new SecureScore
# ListControl view against the live Inforcer API. rm after use.
#
# Requires: $INFORCER_API_KEY set in the current shell.
# Optional: pass region as $1 (uk|eu|us|anz), defaults to uk.

set -u
REGION="${1:-uk}"

ROOT="${0:A:h:h}"
cd "$ROOT"

KEYFILE="$ROOT/.inforcer-key.local"
if [[ -z "${INFORCER_API_KEY:-}" && -f "$KEYFILE" ]]; then
    INFORCER_API_KEY="$(tr -d ' \t\n\r' < "$KEYFILE")"
    export INFORCER_API_KEY
    print -P "%F{cyan}Loaded key from .inforcer-key.local%f"
fi

if [[ -z "${INFORCER_API_KEY:-}" ]]; then
    print -P "%F{red}INFORCER_API_KEY not set.%f Options:"
    print -P "  1. Inline:    %F{cyan}INFORCER_API_KEY=... scripts/live-securescore-check.sh%f"
    print -P "  2. Key file:  %F{cyan}echo '<key>' > .inforcer-key.local%f  (gitignored)"
    exit 1
fi

pwsh -NoProfile -Command "
    Import-Module ./module/InforcerCommunity.psd1 -Force
    \$k = ConvertTo-SecureString \$env:INFORCER_API_KEY -AsPlainText -Force
    Connect-Inforcer -ApiKey \$k -Region '$REGION' | Out-Null
    \$t = Get-InforcerTenant | Select-Object -First 1
    if (-not \$t) { Write-Error 'No tenant returned - check region or key.'; exit 1 }
    \$tid = \$t.ClientTenantId
    \$tname = \$t.TenantFriendlyName
    Write-Host ('Tenant: {0} - {1}' -f \$tid, \$tname)

    \$s = Get-InforcerSecureScore -TenantId \$tid
    Write-Host ''
    Write-Host '=== default view (Format-List) ===' -ForegroundColor Cyan
    \$s | Format-List | Out-Host

    Write-Host '=== drill-in checks ===' -ForegroundColor Cyan
    Write-Host ('Scores            : {0} entries, latest {1} on {2}' -f @(\$s.Scores).Count, \$s.Scores[0].CurrentScore, \$s.Scores[0].CreatedDateTime)
    if (\$s.ControlCategoryScores) {
        \$c = \$s.ControlCategoryScores[0]
        Write-Host ('CategoryScores[0]: {0} - {1}/{2}, {3} historic points' -f \$c.ControlCategory, \$c.CurrentScore, \$c.MaxScore, @(\$c.HistoricScores).Count)
    }
    Write-Host ('ControlProfiles   : {0} entries' -f @(\$s.ControlProfiles).Count)

    Write-Host ''
    Write-Host '=== top recommendation (Format-List on ControlProfile) ===' -ForegroundColor Cyan
    \$s.ControlProfiles | Where-Object { \$_.scoreDifference -gt 0 } | Sort-Object scoreDifference -Descending | Select-Object -First 1 | Format-List | Out-Host
"
