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

    # Load categories.json and build full category chains (parentCategoryId walk)
    $categoryLookup = @{}
    $categoriesPath = Join-Path (Split-Path $Path -Parent) 'categories.json'
    if (Test-Path -LiteralPath $categoriesPath) {
        Write-Verbose "Loading categories from $categoriesPath..."
        $catRaw = Get-Content -Path $categoriesPath -Raw -Encoding UTF8
        $catEntries = $catRaw | ConvertFrom-Json -Depth 10
        # First pass: build raw lookup
        $catById = @{}
        foreach ($cat in $catEntries) {
            if ($cat.id) { $catById[$cat.id] = $cat }
        }
        # Second pass: build full chains by walking parentCategoryId
        foreach ($cat in $catEntries) {
            if (-not $cat.id) { continue }
            $chain = [System.Collections.Generic.List[string]]::new()
            $current = $cat
            $visited = [System.Collections.Generic.HashSet[string]]::new()
            while ($current) {
                if (-not $visited.Add($current.id)) { break }  # cycle protection
                if (-not [string]::IsNullOrWhiteSpace($current.displayName)) {
                    $chain.Insert(0, $current.displayName)
                }
                if ($current.parentCategoryId -and $catById.ContainsKey($current.parentCategoryId)) {
                    $current = $catById[$current.parentCategoryId]
                } else {
                    $current = $null
                }
            }
            $categoryLookup[$cat.id] = ($chain -join ' > ')
        }
        Write-Verbose "Categories loaded: $($categoryLookup.Count) entries with full chains"
    }

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

        # Resolve category name for disambiguation (e.g., "Trusted Sites Zone", "Domain Profile")
        $catName = ''
        if ($entry.categoryId -and $categoryLookup.ContainsKey($entry.categoryId)) {
            $catName = $categoryLookup[$entry.categoryId]
        }

        $catalog[$id] = @{
            DisplayName  = $entry['displayName']
            Description  = $entry['description']
            Options      = $options
            CategoryName = $catName
        }
    }

    $sw.Stop()
    $script:InforcerSettingsCatalog = $catalog
    Write-Host "  Settings Catalog loaded: $($catalog.Count) entries ($([math]::Round($sw.Elapsed.TotalSeconds, 1))s)" -ForegroundColor Gray
}
