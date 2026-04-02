function Get-InforcerSettingsCatalogPath {
    <#
    .SYNOPSIS
        Resolves the path to settings.json via a 6-tier cache strategy.
    .DESCRIPTION
        Resolution order:
        1. Explicit path (if provided and file exists)
        2. Fresh local cache (< 24h old)
        3. Stale local cache (> 24h) with remote freshness check
        4. First-time download from GitHub Release
        5. Fallback: no cache, download failed -> $null (caller proceeds without catalog)
        6. Offline with stale cache -> return stale path with warning
    .PARAMETER ExplicitPath
        User-specified path to settings.json. If provided and valid, returned immediately.
    .PARAMETER CacheDirectory
        Override cache directory. Defaults to ~/.inforcercommunity/data.
    .PARAMETER BaseUrl
        Override base URL for GitHub Release assets. For testing.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$ExplicitPath,

        [Parameter()]
        [string]$CacheDirectory,

        [Parameter()]
        [string]$BaseUrl = 'https://github.com/royklo/IntuneSettingsCatalogData/releases/latest/download'
    )

    # Tier 1: Explicit path
    if (-not [string]::IsNullOrEmpty($ExplicitPath)) {
        if (Test-Path -LiteralPath $ExplicitPath) {
            Write-Verbose "Using explicit settings catalog path: $ExplicitPath"
            return $ExplicitPath
        }
        Write-Warning "Explicit settings catalog path not found: $ExplicitPath"
        return $null
    }

    # Resolve cache directory
    if ([string]::IsNullOrEmpty($CacheDirectory)) {
        $CacheDirectory = Join-Path ([System.Environment]::GetFolderPath('UserProfile')) '.inforcercommunity' 'data'
    }
    $settingsPath = Join-Path $CacheDirectory 'settings.json'
    $categoriesPath = Join-Path $CacheDirectory 'categories.json'
    $metaPath = Join-Path $CacheDirectory 'cache-meta.json'
    $hasCachedFile = Test-Path -LiteralPath $settingsPath

    # Read cache metadata
    $cacheMeta = $null
    if (Test-Path -LiteralPath $metaPath) {
        try {
            $cacheMeta = Get-Content -Path $metaPath -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            Write-Verbose "Could not read cache-meta.json: $_"
        }
    }

    # Tier 2: Fresh cache (< 24h)
    if ($hasCachedFile -and $null -ne $cacheMeta -and $cacheMeta.lastChecked) {
        # ConvertFrom-Json may auto-deserialize ISO strings to DateTime objects
        if ($cacheMeta.lastChecked -is [datetime]) {
            $lastChecked = $cacheMeta.lastChecked.ToUniversalTime()
        } else {
            $lastChecked = [datetime]::Parse($cacheMeta.lastChecked, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind)
        }
        $age = [datetime]::UtcNow - $lastChecked
        if ($age.TotalHours -lt 24) {
            Write-Verbose "Using fresh cached settings catalog (age: $([math]::Round($age.TotalHours, 1))h)"
            return $settingsPath
        }
    }

    # Tier 3/4: Need to check remote or download
    $lastUpdatedUrl = "$BaseUrl/last-updated.json"
    $settingsUrl = "$BaseUrl/settings.json"
    $categoriesUrl = "$BaseUrl/categories.json"

    # Save and restore ProgressPreference (disable progress bar for perf)
    $originalProgress = $ProgressPreference
    try {
        $ProgressPreference = 'SilentlyContinue'

        # Check remote freshness
        $remoteInfo = $null
        try {
            $response = Invoke-WebRequest -Uri $lastUpdatedUrl -UseBasicParsing -ErrorAction Stop
            $remoteInfo = $response.Content | ConvertFrom-Json
        } catch {
            Write-Verbose "Could not fetch last-updated.json: $_"
        }

        # Schema version check
        if ($null -ne $remoteInfo -and $remoteInfo.schemaVersion -and $remoteInfo.schemaVersion -ne 1) {
            Write-Warning "Settings catalog data has schema version $($remoteInfo.schemaVersion) but this module supports version 1. Update the InforcerCommunity module for full compatibility."
            if ($hasCachedFile) {
                Write-Warning 'Falling back to cached settings catalog.'
                return $settingsPath
            }
            return $null
        }

        # Tier 3: Stale cache -- check if remote is newer
        if ($hasCachedFile -and $null -ne $cacheMeta -and $null -ne $remoteInfo) {
            if ($cacheMeta.releaseTimestamp -eq $remoteInfo.updatedAt) {
                # Remote unchanged -- refresh lastChecked and use cache
                $cacheMeta.lastChecked = [datetime]::UtcNow.ToString('o')
                $cacheMeta | ConvertTo-Json | Set-Content -Path $metaPath -Encoding UTF8
                Write-Verbose 'Remote data unchanged -- refreshed cache TTL'
                return $settingsPath
            }
            Write-Verbose 'Remote data is newer than cache -- downloading update'
        }

        # Tier 4: Download (first time or update needed)
        if ($null -ne $remoteInfo -or -not $hasCachedFile) {
            if (-not (Test-Path -LiteralPath $CacheDirectory)) {
                New-Item -ItemType Directory -Path $CacheDirectory -Force | Out-Null
            }

            $downloaded = $false
            $maxAttempts = 2  # Single retry
            for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
                try {
                    Write-Host 'Downloading Settings Catalog data...' -ForegroundColor Cyan
                    $tmpSettings = "$settingsPath.tmp"
                    Invoke-WebRequest -Uri $settingsUrl -OutFile $tmpSettings -UseBasicParsing -ErrorAction Stop
                    Move-Item -Path $tmpSettings -Destination $settingsPath -Force

                    # Also download categories
                    $tmpCategories = "$categoriesPath.tmp"
                    Invoke-WebRequest -Uri $categoriesUrl -OutFile $tmpCategories -UseBasicParsing -ErrorAction Stop
                    Move-Item -Path $tmpCategories -Destination $categoriesPath -Force

                    $downloaded = $true
                    break
                } catch {
                    # Clean up partial downloads
                    Remove-Item -Path "$settingsPath.tmp" -Force -ErrorAction SilentlyContinue
                    Remove-Item -Path "$categoriesPath.tmp" -Force -ErrorAction SilentlyContinue

                    if ($attempt -lt $maxAttempts) {
                        Write-Verbose "Download attempt $attempt failed: $_. Retrying in 2s..."
                        Start-Sleep -Seconds 2
                    } else {
                        Write-Verbose "Download failed after $maxAttempts attempts: $_"
                    }
                }
            }

            if ($downloaded) {
                # Update cache metadata
                $newMeta = @{
                    lastChecked     = [datetime]::UtcNow.ToString('o')
                    releaseTimestamp = $(if ($remoteInfo) { $remoteInfo.updatedAt } else { [datetime]::UtcNow.ToString('o') })
                    schemaVersion   = $(if ($remoteInfo) { $remoteInfo.schemaVersion } else { 1 })
                }
                $newMeta | ConvertTo-Json | Set-Content -Path $metaPath -Encoding UTF8
                Write-Host '  Settings Catalog data cached successfully.' -ForegroundColor Green
                return $settingsPath
            }
        }

    } finally {
        $ProgressPreference = $originalProgress
    }

    # Tier 5/6: Download failed
    if ($hasCachedFile) {
        Write-Warning 'Could not refresh Settings Catalog data. Using stale cached version.'
        return $settingsPath
    }

    Write-Warning 'Settings Catalog data not available. Settings Catalog policies will show raw settingDefinitionId values.'
    return $null
}
