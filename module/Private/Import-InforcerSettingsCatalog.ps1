function Import-InforcerSettingsCatalog {
    <#
    .SYNOPSIS
        Loads the Settings Catalog definition data into a session-scoped cache.
    .DESCRIPTION
        Reads settings.json (a bundled copy of the IntuneSettingsCatalogViewer dataset) and
        populates $script:InforcerSettingsCatalog as a hashtable keyed by settingDefinitionId.
        Each entry contains DisplayName, Description, and an Options hashtable (itemId -> label).

        The catalog is loaded once per session. Subsequent calls are no-ops unless -Force is used.
    .PARAMETER Path
        Path to settings.json. Defaults to module/data/settings.json relative to the Private directory.
    .PARAMETER Force
        Reload the catalog even if it is already cached.
    .EXAMPLE
        Import-InforcerSettingsCatalog
        # Loads from default path (module/data/settings.json) the first time; no-op on subsequent calls.
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

    # Default path: module/data/settings.json (Private/ -> data/)
    if ([string]::IsNullOrEmpty($Path)) {
        $Path = Join-Path $PSScriptRoot '..' 'data' 'settings.json'
        $Path = [System.IO.Path]::GetFullPath($Path)
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Error -Message "Settings catalog file not found: $Path. Copy settings.json from IntuneSettingsCatalogViewer to module/data/settings.json" `
            -ErrorId 'SettingsCatalogNotFound' -Category ObjectNotFound
        return
    }

    Write-Verbose "Loading Settings Catalog from $Path..."
    $raw = Get-Content -Path $Path -Raw -Encoding UTF8
    $entries = $raw | ConvertFrom-Json -Depth 100

    $catalog = @{}
    foreach ($entry in $entries) {
        $id = $entry.id
        if ([string]::IsNullOrEmpty($id)) { continue }

        $options = @{}
        foreach ($opt in @($entry.options)) {
            if ($opt -and $opt.itemId) { $options[$opt.itemId] = $opt.displayName }
        }

        $catalog[$id] = @{
            DisplayName = $entry.displayName
            Description = $entry.description
            Options     = $options
        }
    }

    $script:InforcerSettingsCatalog = $catalog
    Write-Verbose "Settings Catalog loaded: $($catalog.Count) entries"
}
