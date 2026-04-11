function Import-InforcerSettingsCatalog {
    <#
    .SYNOPSIS
        Loads the Settings Catalog definition data into a session-scoped cache.
    .DESCRIPTION
        Resolves settings.json via Get-InforcerSettingsCatalogPath (which auto-downloads and
        caches from the IntuneSettingsCatalogData GitHub repository) and populates
        $script:InforcerSettingsCatalog as a hashtable keyed by settingDefinitionId.
        Each entry contains DisplayName, Description, and an Options hashtable (itemId -> label).

        The catalog is loaded once per session. Subsequent calls are no-ops unless -Force is used.
    .PARAMETER Path
        Explicit path to settings.json. When omitted, uses the cache strategy in
        Get-InforcerSettingsCatalogPath (auto-download from GitHub with 24h TTL).
    .PARAMETER Force
        Reload the catalog even if it is already cached.
    .EXAMPLE
        Import-InforcerSettingsCatalog
        # Auto-resolves settings.json via cache strategy the first time; no-op on subsequent calls.
    .EXAMPLE
        Import-InforcerSettingsCatalog -Force
        # Reloads the catalog even if already cached.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Path,

        [Parameter()]
        [switch]$Force
    )

    # Guard: already loaded and -Force not requested
    if (-not $Force -and $null -ne $script:InforcerSettingsCatalog) { return }

    # Resolve path via cache strategy if not explicit
    if ([string]::IsNullOrEmpty($Path)) {
        $Path = Get-InforcerSettingsCatalogPath
    } else {
        $Path = Get-InforcerSettingsCatalogPath -ExplicitPath $Path
    }

    if ([string]::IsNullOrEmpty($Path)) {
        # No catalog available -- caller proceeds without resolution
        return
    }

    Write-Host '  Loading Settings Catalog...' -ForegroundColor Gray
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $raw = Get-Content -Path $Path -Raw -Encoding UTF8
    $entries = $raw | ConvertFrom-Json -AsHashtable -Depth 100

    $catalog = @{}
    foreach ($entry in $entries) {
        $id = $entry['id']
        if ([string]::IsNullOrEmpty($id)) { continue }

        $options = @{}
        $entryOptions = $entry['options']
        if ($null -ne $entryOptions) {
            foreach ($opt in @($entryOptions)) {
                if ($opt -and $opt['itemId']) { $options[$opt['itemId']] = $opt['displayName'] }
            }
        }

        $catalog[$id] = @{
            DisplayName = $entry['displayName']
            Description = $entry['description']
            Options     = $options
        }
    }

    $sw.Stop()
    $script:InforcerSettingsCatalog = $catalog
    Write-Host "  Settings Catalog loaded: $($catalog.Count) entries ($([math]::Round($sw.Elapsed.TotalSeconds, 1))s)" -ForegroundColor Gray
}
