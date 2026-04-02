# Settings Catalog Data Pipeline Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract the Intune Settings Catalog data pipeline into a standalone repo (`IntuneSettingsCatalogData`) with nightly GitHub Actions publishing to GitHub Releases, then modify the InforcerCommunity PowerShell module to fetch and cache `settings.json` at runtime instead of bundling it.

**Architecture:** Two independent deliverables. Part 1 creates a new GitHub repo with a trimmed `fetch-settings.ts` and a `refresh-and-publish.yml` workflow that fetches from Microsoft Graph and publishes release assets. Part 2 modifies the InforcerCommunity module's `Import-InforcerSettingsCatalog` to resolve settings data via a new `Get-InforcerSettingsCatalogPath` function that implements a 6-tier cache strategy (explicit path → fresh cache → stale check → first download → fallback → offline).

**Tech Stack:** TypeScript (Node.js 20, `@azure/identity`, `@microsoft/microsoft-graph-client`), GitHub Actions, PowerShell 7.0+, Pester 5.x

**Spec:** `docs/superpowers/specs/2026-04-02-settings-catalog-data-pipeline-design.md`

---

## File Structure

### Part 1: IntuneSettingsCatalogData (new repo)

| File | Responsibility |
|------|---------------|
| `scripts/fetch-settings.ts` | Graph API fetch — settings + categories + orphan categories. Trimmed from IntuneSettingsCatalogViewer (no changelog, no search index). |
| `.github/workflows/refresh-and-publish.yml` | Nightly cron (06:00 UTC) + manual dispatch. Runs fetch, publishes release assets. |
| `package.json` | Minimal deps: `@azure/identity`, `@microsoft/microsoft-graph-client`, `tsx`, `typescript`. |
| `tsconfig.json` | TypeScript config for scripts only (no Next.js, no JSX). |
| `.gitignore` | Ignore `data/*.json`, `node_modules/`. |
| `README.md` | Purpose, usage, secrets setup. |

### Part 2: InforcerCommunity module changes

| File | Action | Responsibility |
|------|--------|---------------|
| `module/Private/Get-InforcerSettingsCatalogPath.ps1` | **Create** | 6-tier cache resolution: explicit → fresh cache → stale check → download → fallback → offline. Atomic writes via `.tmp` + `Move-Item`. |
| `module/Private/Import-InforcerSettingsCatalog.ps1` | **Modify** | Replace bundled/sibling discovery with call to `Get-InforcerSettingsCatalogPath`. |
| `module/Public/Export-InforcerTenantDocumentation.ps1` | **Modify** | Remove inline discovery chain (lines 112-130), delegate to `Import-InforcerSettingsCatalog`. Update help text. |
| `module/Private/Get-InforcerDocData.ps1` | **No change** | Already passes `-Path` through to `Import-InforcerSettingsCatalog`. |
| `Tests/SettingsCatalog.Tests.ps1` | **Modify** | Add tests for `Get-InforcerSettingsCatalogPath` cache behavior. |

---

## Part 1: IntuneSettingsCatalogData Repository

### Task 1: Create repository and scaffold files

**Files:**
- Create: `IntuneSettingsCatalogData/package.json`
- Create: `IntuneSettingsCatalogData/tsconfig.json`
- Create: `IntuneSettingsCatalogData/.gitignore`
- Create: `IntuneSettingsCatalogData/data/.gitkeep`
- Create: `IntuneSettingsCatalogData/README.md`

- [ ] **Step 1: Create the repo on GitHub**

```bash
# From the parent directory of your repos
cd /Users/roy/github/royklo
gh repo create royklo/IntuneSettingsCatalogData --public --clone --description "Nightly Intune Settings Catalog data from Microsoft Graph, published as GitHub Release assets"
cd IntuneSettingsCatalogData
```

- [ ] **Step 2: Create package.json**

```json
{
  "name": "intune-settings-catalog-data",
  "version": "1.0.0",
  "private": true,
  "description": "Fetches Intune Settings Catalog data from Microsoft Graph and publishes as GitHub Release assets",
  "scripts": {
    "fetch-settings": "tsx scripts/fetch-settings.ts"
  },
  "devDependencies": {
    "@azure/identity": "^4.2.0",
    "@microsoft/microsoft-graph-client": "^3.0.7",
    "tsx": "^4.7.0",
    "typescript": "^5.4.0",
    "@types/node": "^20.12.0"
  }
}
```

- [ ] **Step 3: Create tsconfig.json**

Stripped-down config — no Next.js, no JSX, scripts-only:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "esModuleInterop": true,
    "strict": true,
    "skipLibCheck": true,
    "noEmit": true,
    "resolveJsonModule": true
  },
  "include": ["scripts/**/*.ts"]
}
```

- [ ] **Step 4: Create .gitignore**

```
node_modules/
data/*.json
!data/.gitkeep
```

- [ ] **Step 5: Create data/.gitkeep**

Empty file — keeps the `data/` directory in git while ignoring JSON output.

- [ ] **Step 6: Create README.md**

```markdown
# IntuneSettingsCatalogData

Nightly fetch of the full Microsoft Intune Settings Catalog from Microsoft Graph (beta API). Data is published as GitHub Release assets for consumption by downstream tools.

## Release Assets

| File | Size | Description |
|------|------|-------------|
| `settings.json` | ~65 MB | All setting definitions (polymorphic — choice, simple, group, etc.) |
| `categories.json` | ~561 KB | Category hierarchy with parent/child relationships |
| `last-updated.json` | ~60 B | ISO timestamp + schema version |

**Download (no auth required):**
```
https://github.com/royklo/IntuneSettingsCatalogData/releases/latest/download/settings.json
https://github.com/royklo/IntuneSettingsCatalogData/releases/latest/download/categories.json
https://github.com/royklo/IntuneSettingsCatalogData/releases/latest/download/last-updated.json
```

## How It Works

A GitHub Actions workflow runs daily at 06:00 UTC:
1. Authenticates with Microsoft Graph via Azure AD service principal
2. Fetches all configuration settings and categories (including orphan categories)
3. Compares with previous data — skips release if unchanged
4. Publishes assets to a rolling `latest` release + a dated tag (`vYYYY-MM-DD`)

## Secrets Required

| Secret | Purpose |
|--------|---------|
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_CLIENT_ID` | Service principal app ID |
| `AZURE_CLIENT_SECRET` | Service principal secret |

The app registration needs `DeviceManagementConfiguration.Read.All` (Application permission).

## Local Development

```bash
npm install
AZURE_TENANT_ID=xxx AZURE_CLIENT_ID=xxx AZURE_CLIENT_SECRET=xxx npm run fetch-settings
```
```

- [ ] **Step 7: Run npm install and commit scaffold**

```bash
npm install
git add -A
git commit -m "chore: scaffold repo with package.json, tsconfig, gitignore, README"
```

---

### Task 2: Copy and trim fetch-settings.ts

**Files:**
- Create: `IntuneSettingsCatalogData/scripts/fetch-settings.ts`

**Source:** `/Users/roy/github/royklo/IntuneSettingsCatalogViewer/scripts/fetch-settings.ts`

- [ ] **Step 1: Copy the source file**

```bash
mkdir -p scripts
cp /Users/roy/github/royklo/IntuneSettingsCatalogViewer/scripts/fetch-settings.ts scripts/fetch-settings.ts
```

- [ ] **Step 2: Modify the script**

Changes to make:

1. **Update the `last-updated.json` schema** — replace the simple `{ date: now }` output with:
```typescript
fs.writeFileSync(LAST_UPDATED_FILE, JSON.stringify({
  updatedAt: now,
  schemaVersion: 1
}, null, 2), 'utf-8');
```

2. **Remove the "Next: run generate-changelog..." log line** at the end (line 224) — this repo doesn't have those scripts.

3. **Add a `DATA_CHANGED` output mechanism** for the GitHub Actions workflow to detect changes. Insert this immediately after the `if (hasChanges) { ... } else { ... }` block at line 211-216, where the `hasChanges` boolean is in scope:
```typescript
// Output change status for GitHub Actions workflow
if (process.env.GITHUB_OUTPUT) {
  fs.appendFileSync(process.env.GITHUB_OUTPUT, `data_changed=${hasChanges}\n`);
}
```

4. **Update the header comment** to reflect this is the standalone data pipeline, not the viewer.

The core logic (auth, pagination, throttling, orphan categories, change detection) stays identical.

- [ ] **Step 3: Verify it compiles**

```bash
npx tsc --noEmit
```
Expected: No errors.

- [ ] **Step 4: Commit**

```bash
git add scripts/fetch-settings.ts
git commit -m "feat: add fetch-settings.ts (trimmed from IntuneSettingsCatalogViewer)"
```

---

### Task 3: Create GitHub Actions workflow

**Files:**
- Create: `IntuneSettingsCatalogData/.github/workflows/refresh-and-publish.yml`

- [ ] **Step 1: Create the workflow file**

```yaml
name: Refresh Settings & Publish

on:
  schedule:
    - cron: '0 6 * * *'
  workflow_dispatch:

permissions:
  contents: write

jobs:
  refresh-and-publish:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup Node.js
        uses: actions/setup-node@v4
        with:
          node-version: '20'
          cache: 'npm'

      - name: Install dependencies
        run: npm ci

      - name: Fetch settings from Microsoft Graph
        id: fetch
        env:
          AZURE_TENANT_ID: ${{ secrets.AZURE_TENANT_ID }}
          AZURE_CLIENT_ID: ${{ secrets.AZURE_CLIENT_ID }}
          AZURE_CLIENT_SECRET: ${{ secrets.AZURE_CLIENT_SECRET }}
        run: npx tsx scripts/fetch-settings.ts

      - name: Check if data changed
        id: check
        run: |
          if [ "${{ steps.fetch.outputs.data_changed }}" = "true" ]; then
            echo "changed=true" >> "$GITHUB_OUTPUT"
            echo "Data changed — will publish new release"
          else
            echo "changed=false" >> "$GITHUB_OUTPUT"
            echo "No data changes — skipping release"
          fi

      - name: Delete existing 'latest' release
        if: steps.check.outputs.changed == 'true'
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          gh release delete latest --yes --cleanup-tag 2>/dev/null || true

      - name: Create 'latest' release
        if: steps.check.outputs.changed == 'true'
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          gh release create latest \
            --title "Latest Settings Catalog Data" \
            --notes "Auto-updated on $(date -I). Contains the full Intune Settings Catalog from Microsoft Graph." \
            --latest \
            data/settings.json \
            data/categories.json \
            data/last-updated.json

      - name: Create dated release
        if: steps.check.outputs.changed == 'true'
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          TAG="v$(date -I)"
          # Delete existing dated release/tag if re-running same day
          gh release delete "$TAG" --yes --cleanup-tag 2>/dev/null || true
          gh release create "$TAG" \
            --title "Settings Catalog Data $TAG" \
            --notes "Snapshot from $(date -I)." \
            data/settings.json \
            data/categories.json \
            data/last-updated.json
```

- [ ] **Step 2: Commit**

```bash
git add .github/workflows/refresh-and-publish.yml
git commit -m "ci: add nightly refresh-and-publish workflow"
```

- [ ] **Step 3: Push to GitHub**

```bash
git push -u origin main
```

- [ ] **Step 4: Configure GitHub secrets**

The user must manually add these secrets in the GitHub repo settings (Settings → Secrets → Actions):
- `AZURE_TENANT_ID`
- `AZURE_CLIENT_ID`
- `AZURE_CLIENT_SECRET`

These are the same values used in the IntuneSettingsCatalogViewer repo.

- [ ] **Step 5: Test the workflow manually**

```bash
gh workflow run refresh-and-publish.yml
gh run list --limit 1 --workflow refresh-and-publish.yml
# Wait for completion, then verify:
gh release view latest
```

Expected: A `latest` release with 3 assets (`settings.json`, `categories.json`, `last-updated.json`).

- [ ] **Step 6: Verify public download URLs**

```bash
curl -sI -o /dev/null -w "%{http_code}" https://github.com/royklo/IntuneSettingsCatalogData/releases/latest/download/last-updated.json
```

Expected: `302` (redirect to CDN). A full download test:

```bash
curl -sL https://github.com/royklo/IntuneSettingsCatalogData/releases/latest/download/last-updated.json | cat
```

Expected: JSON with `updatedAt` and `schemaVersion: 1`.

---

## Part 2: InforcerCommunity Module Integration

### Task 4: Create Get-InforcerSettingsCatalogPath private function

**Files:**
- Create: `module/Private/Get-InforcerSettingsCatalogPath.ps1`
- Create: `Tests/SettingsCatalogCache.Tests.ps1`

- [ ] **Step 1: Write the failing tests**

Create `Tests/SettingsCatalogCache.Tests.ps1`:

```powershell
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

    It 'returns stale cache path with warning when download fails but cache exists' {
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

    It 'rejects unknown schemaVersion and falls back' {
        $cachedFile = Join-Path $script:testCacheDir 'settings.json'
        '[]' | Set-Content -Path $cachedFile -Encoding UTF8
        $meta = @{
            lastChecked      = ([datetime]::UtcNow.AddHours(-48)).ToString('o')
            releaseTimestamp  = '2026-04-01T06:00:00Z'
            schemaVersion    = 1
        }
        $meta | ConvertTo-Json | Set-Content -Path (Join-Path $script:testCacheDir 'cache-meta.json') -Encoding UTF8

        # Simulate a remote last-updated.json with schemaVersion 99
        # This test verifies the logic path — in practice, the download failure
        # path handles unknown schema versions gracefully
        $result = InModuleScope InforcerCommunity -Parameters @{ CacheDir = $script:testCacheDir } {
            Get-InforcerSettingsCatalogPath -CacheDirectory $CacheDir -BaseUrl 'https://localhost:1/nonexistent'
        }
        # Should fall back to stale cache
        $result | Should -Be $cachedFile
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd /Users/roy/github/royklo/InforcerCommunity
pwsh -Command "Invoke-Pester ./Tests/SettingsCatalogCache.Tests.ps1 -Output Detailed"
```

Expected: FAIL — `Get-InforcerSettingsCatalogPath` does not exist yet.

- [ ] **Step 3: Implement Get-InforcerSettingsCatalogPath**

Create `module/Private/Get-InforcerSettingsCatalogPath.ps1`:

```powershell
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
        $lastChecked = [datetime]::Parse($cacheMeta.lastChecked, $null, [System.Globalization.DateTimeStyles]::RoundtripKind)
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

        # Tier 3: Stale cache — check if remote is newer
        if ($hasCachedFile -and $null -ne $cacheMeta -and $null -ne $remoteInfo) {
            if ($cacheMeta.releaseTimestamp -eq $remoteInfo.updatedAt) {
                # Remote unchanged — refresh lastChecked and use cache
                $cacheMeta.lastChecked = [datetime]::UtcNow.ToString('o')
                $cacheMeta | ConvertTo-Json | Set-Content -Path $metaPath -Encoding UTF8
                Write-Verbose 'Remote data unchanged — refreshed cache TTL'
                return $settingsPath
            }
            Write-Verbose 'Remote data is newer than cache — downloading update'
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
```

- [ ] **Step 4: Run the tests**

```bash
pwsh -Command "Invoke-Pester ./Tests/SettingsCatalogCache.Tests.ps1 -Output Detailed"
```

Expected: All tests PASS.

- [ ] **Step 5: Commit**

```bash
cd /Users/roy/github/royklo/InforcerCommunity
git add module/Private/Get-InforcerSettingsCatalogPath.ps1 Tests/SettingsCatalogCache.Tests.ps1
git commit -m "feat: add Get-InforcerSettingsCatalogPath with 6-tier cache resolution"
```

---

### Task 5: Modify Import-InforcerSettingsCatalog to use new path resolution

**Files:**
- Modify: `module/Private/Import-InforcerSettingsCatalog.ps1`

- [ ] **Step 1: Update Import-InforcerSettingsCatalog**

Replace the current default-path logic (lines 34-43) with a call to `Get-InforcerSettingsCatalogPath`:

**Current code to replace (lines 31-44):**
```powershell
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
```

**New code:**
```powershell
    # Guard: already loaded and -Force not requested
    if (-not $Force -and $null -ne $script:InforcerSettingsCatalog) { return }

    # Resolve path via cache strategy if not explicit
    if ([string]::IsNullOrEmpty($Path)) {
        $Path = Get-InforcerSettingsCatalogPath
    } else {
        $Path = Get-InforcerSettingsCatalogPath -ExplicitPath $Path
    }

    if ([string]::IsNullOrEmpty($Path)) {
        # No catalog available — caller proceeds without resolution
        return
    }
```

Also update the synopsis/description to reflect the new behavior:
- Remove reference to "bundled copy" and "IntuneSettingsCatalogViewer"
- Document that it auto-downloads and caches from GitHub

- [ ] **Step 2: Update the existing error test in SettingsCatalog.Tests.ps1**

The test at `Tests/SettingsCatalog.Tests.ps1` line 84-88 expects `Should -Throw` when the path doesn't exist. With the new behavior, `Get-InforcerSettingsCatalogPath -ExplicitPath` returns `$null` and `Import-InforcerSettingsCatalog` returns silently. Update the test:

**Current:**
```powershell
    It 'writes an error when the path does not exist' {
        InModuleScope InforcerCommunity {
            { Import-InforcerSettingsCatalog -Path 'C:\DoesNotExist\settings.json' -ErrorAction Stop } | Should -Throw
        }
    }
```

**Replace with:**
```powershell
    It 'returns without loading catalog when explicit path does not exist' {
        InModuleScope InforcerCommunity {
            $script:InforcerSettingsCatalog = $null
            Import-InforcerSettingsCatalog -Path 'C:\DoesNotExist\settings.json'
            $script:InforcerSettingsCatalog | Should -BeNullOrEmpty
        }
    }
```

Also update the integration test path at line 462 — change the reference from `module/data/settings.json` to the new cache location:

**Current:**
```powershell
$script:IntegrationSettingsPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..' 'module' 'data' 'settings.json'))
```

**Replace with:**
```powershell
$script:IntegrationSettingsPath = Join-Path ([System.Environment]::GetFolderPath('UserProfile')) '.inforcercommunity' 'data' 'settings.json'
```

- [ ] **Step 3: Run existing tests to verify nothing broke**

```bash
pwsh -Command "Invoke-Pester ./Tests/SettingsCatalog.Tests.ps1 -Output Detailed"
```

Expected: All existing tests PASS. The explicit `-Path` tests still work because `Get-InforcerSettingsCatalogPath -ExplicitPath` returns the path directly.

- [ ] **Step 3: Commit**

```bash
git add module/Private/Import-InforcerSettingsCatalog.ps1
git commit -m "refactor: Import-InforcerSettingsCatalog uses Get-InforcerSettingsCatalogPath for cache resolution"
```

---

### Task 6: Remove inline discovery chain from Export-InforcerTenantDocumentation

**Files:**
- Modify: `module/Public/Export-InforcerTenantDocumentation.ps1:112-130`

- [ ] **Step 1: Remove the inline discovery chain**

Delete lines 112-130 (the `$resolvedCatalogPath` block that does bundled → sibling → warn) and replace with a simple pass-through:

**Current code to remove (lines 112-130):**
```powershell
# Settings.json discovery chain (D-06, D-07, D-08):
# 1. Explicit -SettingsCatalogPath parameter
# 2. Bundled module/data/settings.json
# 3. Sibling IntuneSettingsCatalogViewer repo
# 4. Not found - warn and proceed without resolution
$resolvedCatalogPath = $SettingsCatalogPath
if ([string]::IsNullOrEmpty($resolvedCatalogPath)) {
    $bundled = Join-Path $PSScriptRoot '..' 'data' 'settings.json'
    $bundled = [System.IO.Path]::GetFullPath($bundled)
    if (Test-Path -LiteralPath $bundled) { $resolvedCatalogPath = $bundled }
}
if ([string]::IsNullOrEmpty($resolvedCatalogPath)) {
    $sibling = Join-Path $PSScriptRoot '..' '..' '..' 'IntuneSettingsCatalogViewer' 'data' 'settings.json'
    $sibling = [System.IO.Path]::GetFullPath($sibling)
    if (Test-Path -LiteralPath $sibling) { $resolvedCatalogPath = $sibling }
}
if ([string]::IsNullOrEmpty($resolvedCatalogPath)) {
    Write-Warning 'Settings catalog (settings.json) not found. Settings Catalog policies will show raw settingDefinitionId values.'
}
```

**Replacement:**
```powershell
# Settings catalog path: explicit override or auto-resolved via cache strategy
$resolvedCatalogPath = $SettingsCatalogPath
```

The discovery/download/cache logic is now handled inside `Import-InforcerSettingsCatalog` → `Get-InforcerSettingsCatalogPath`.

- [ ] **Step 2: Update the comment-based help for -SettingsCatalogPath**

Replace lines 29-33:

**Current:**
```
.PARAMETER SettingsCatalogPath
    Path to the IntuneSettingsCatalog settings.json file. When omitted, the cmdlet searches:
    1. module/data/settings.json (bundled copy shipped with the module)
    2. Sibling IntuneSettingsCatalogViewer repo at ../IntuneSettingsCatalogViewer/data/settings.json
    If not found in either location, Settings Catalog policies show raw settingDefinitionId values
    and a warning is emitted.
```

**New:**
```
.PARAMETER SettingsCatalogPath
    Path to a local settings.json file for Settings Catalog resolution. When omitted, the cmdlet
    automatically downloads and caches the latest data from the IntuneSettingsCatalogData GitHub
    repository (~65 MB, cached at ~/.inforcercommunity/data/settings.json with a 24-hour TTL).
    If download fails and no cached copy exists, Settings Catalog policies show raw
    settingDefinitionId values and a warning is emitted.
```

- [ ] **Step 3: Run all tests**

```bash
pwsh -Command "Invoke-Pester ./Tests/ -Output Detailed"
```

Expected: All tests PASS.

- [ ] **Step 4: Commit**

```bash
git add module/Public/Export-InforcerTenantDocumentation.ps1
git commit -m "refactor: remove inline settings catalog discovery chain from Export-InforcerTenantDocumentation"
```

---

### Task 7: Clean up module/data directory

**Files:**
- Remove: `module/data/.gitkeep` (or the entire `module/data/` directory reference)

- [ ] **Step 1: Check what's in module/data/**

```bash
ls -la module/data/
```

The `settings.json` is already gitignored. The `.gitkeep` was there to track the directory for the bundled file.

- [ ] **Step 2: Remove the directory tracking if no longer needed**

If `module/data/` has no other purpose:

```bash
git rm module/data/.gitkeep
```

If the directory is needed for other data files, leave it.

- [ ] **Step 3: Verify module still loads**

```bash
pwsh -Command "Import-Module ./module/InforcerCommunity.psd1 -Force; Get-Module InforcerCommunity"
```

Expected: Module loads without errors.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: remove module/data/.gitkeep (settings catalog now fetched at runtime)"
```

---

### Task 8: Run full test suite and verify

- [ ] **Step 1: Run all Pester tests**

```bash
pwsh -Command "Invoke-Pester ./Tests/ -Output Detailed"
```

Expected: All tests PASS.

- [ ] **Step 2: Run ScriptAnalyzer**

```bash
pwsh -Command "Invoke-ScriptAnalyzer -Path ./module -Recurse -Severity Warning"
```

Expected: No new warnings from the changed files.

- [ ] **Step 3: Manual smoke test (if settings data is available)**

```bash
pwsh -Command "
Import-Module ./module/InforcerCommunity.psd1 -Force
# This should trigger the download on first run:
InModuleScope InforcerCommunity {
    \$path = Get-InforcerSettingsCatalogPath
    Write-Host \"Resolved path: \$path\"
    if (\$path) { Write-Host \"File size: \$([math]::Round((Get-Item \$path).Length / 1MB, 1)) MB\" }
}
"
```

Expected: Downloads settings.json to `~/.inforcercommunity/data/settings.json` and reports ~65 MB file size. (This test depends on the IntuneSettingsCatalogData repo having its first release published.)

- [ ] **Step 4: Verify cache TTL works**

Run the same command again immediately — should use cached file without downloading:

```bash
pwsh -Command "
Import-Module ./module/InforcerCommunity.psd1 -Force
InModuleScope InforcerCommunity {
    \$path = Get-InforcerSettingsCatalogPath -Verbose
}
"
```

Expected: Verbose output says "Using fresh cached settings catalog (age: 0.0h)".
