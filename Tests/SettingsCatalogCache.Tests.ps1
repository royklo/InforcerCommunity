# SettingsCatalogCache.Tests.ps1
# Tests for the settings catalog cache resolution (Get-InforcerSettingsCatalogPath).
# Run: Invoke-Pester ./Tests/SettingsCatalogCache.Tests.ps1

$ErrorActionPreference = 'Stop'

BeforeAll {
    Remove-Module -Name 'InforcerCommunity' -ErrorAction SilentlyContinue
    $manifestPath = Join-Path $PSScriptRoot '..' 'module' 'InforcerCommunity.psd1'
    $manifestPath = [System.IO.Path]::GetFullPath($manifestPath)
    Import-Module $manifestPath -Force -ErrorAction Stop
}

Describe 'Get-InforcerSettingsCatalogPath' {

    BeforeEach {
        # Create isolated temp cache directory per test
        $script:testCacheDir = Join-Path ([System.IO.Path]::GetTempPath()) "inforcertest-$([guid]::NewGuid().ToString('N').Substring(0,8))"
        New-Item -ItemType Directory -Path $script:testCacheDir -Force | Out-Null
    }

    AfterEach {
        Remove-Item -Path $script:testCacheDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'returns explicit path when -ExplicitPath is provided and file exists' {
        $tmpFile = Join-Path $script:testCacheDir 'explicit-settings.json'
        '[]' | Set-Content -Path $tmpFile -Encoding UTF8

        $result = InModuleScope InforcerCommunity -Parameters @{ ExplicitPath = $tmpFile; CacheDir = $script:testCacheDir } {
            Get-InforcerSettingsCatalogPath -ExplicitPath $ExplicitPath -CacheDirectory $CacheDir
        }
        $result | Should -Be $tmpFile
    }

    It 'returns null when explicit path does not exist' {
        $result = InModuleScope InforcerCommunity -Parameters @{ CacheDir = $script:testCacheDir } {
            Get-InforcerSettingsCatalogPath -ExplicitPath 'C:\DoesNotExist\settings.json' -CacheDirectory $CacheDir
        }
        $result | Should -BeNullOrEmpty
    }

    It 'returns cached path when cache is fresh (< 24h)' {
        # Create cached file + fresh meta
        $cachedFile = Join-Path $script:testCacheDir 'settings.json'
        '[]' | Set-Content -Path $cachedFile -Encoding UTF8
        $meta = @{
            lastChecked      = ([datetime]::UtcNow.AddHours(-1)).ToString('o')
            releaseTimestamp  = '2026-04-01T06:00:00Z'
            schemaVersion    = 1
        }
        $meta | ConvertTo-Json | Set-Content -Path (Join-Path $script:testCacheDir 'cache-meta.json') -Encoding UTF8

        $result = InModuleScope InforcerCommunity -Parameters @{ CacheDir = $script:testCacheDir } {
            Get-InforcerSettingsCatalogPath -CacheDirectory $CacheDir
        }
        $result | Should -Be $cachedFile
    }

    It 'returns null when no cache and download fails' {
        # Empty cache dir, bogus URL => download will fail, no cache to fall back to
        $result = InModuleScope InforcerCommunity -Parameters @{ CacheDir = $script:testCacheDir } {
            Get-InforcerSettingsCatalogPath -CacheDirectory $CacheDir -BaseUrl 'https://localhost:1/nonexistent'
        }
        $result | Should -BeNullOrEmpty
    }

    It 'returns stale cache path when download fails but cache exists' {
        # Create cached file + stale meta (> 24h old)
        $cachedFile = Join-Path $script:testCacheDir 'settings.json'
        '[]' | Set-Content -Path $cachedFile -Encoding UTF8
        $meta = @{
            lastChecked      = ([datetime]::UtcNow.AddHours(-48)).ToString('o')
            releaseTimestamp  = '2026-03-30T06:00:00Z'
            schemaVersion    = 1
        }
        $meta | ConvertTo-Json | Set-Content -Path (Join-Path $script:testCacheDir 'cache-meta.json') -Encoding UTF8

        $result = InModuleScope InforcerCommunity -Parameters @{ CacheDir = $script:testCacheDir } {
            Get-InforcerSettingsCatalogPath -CacheDirectory $CacheDir -BaseUrl 'https://localhost:1/nonexistent'
        }
        $result | Should -Be $cachedFile
    }

    It 'does not re-download when cache has no meta but file exists and download fails' {
        # Cache file exists but no metadata — stale fallback
        $cachedFile = Join-Path $script:testCacheDir 'settings.json'
        '[]' | Set-Content -Path $cachedFile -Encoding UTF8

        $result = InModuleScope InforcerCommunity -Parameters @{ CacheDir = $script:testCacheDir } {
            Get-InforcerSettingsCatalogPath -CacheDirectory $CacheDir -BaseUrl 'https://localhost:1/nonexistent'
        }
        $result | Should -Be $cachedFile
    }
}
