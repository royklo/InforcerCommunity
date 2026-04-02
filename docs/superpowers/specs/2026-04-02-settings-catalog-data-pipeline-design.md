# Settings Catalog Data Pipeline & Runtime Fetch Integration

**Date:** 2026-04-02
**Status:** Approved
**Scope:** New `IntuneSettingsCatalogData` repository + InforcerCommunity module integration

## Problem

The InforcerCommunity module bundles a 62.5MB `settings.json` file for resolving Intune Settings Catalog definition IDs to friendly names. This file is static at ship time, becomes stale immediately, and is too large to include in the module package. The source data lives in `IntuneSettingsCatalogViewer`, which is a full Next.js web application — overkill for just the data pipeline.

## Solution

1. Extract the data-fetching pipeline into a dedicated public repo (`IntuneSettingsCatalogData`)
2. Publish `settings.json` and `categories.json` as GitHub Release assets nightly
3. Modify the PowerShell module to fetch and cache these files at runtime with a 24h TTL

## Part 1: New Repository — IntuneSettingsCatalogData

### Purpose

Dedicated public repo that fetches Intune Settings Catalog data from Microsoft Graph daily and publishes it as GitHub Release assets.

### What Gets Extracted from IntuneSettingsCatalogViewer

- `scripts/fetch-settings.ts` — Graph API fetch with pagination + 429 throttling
- `package.json` dependencies: `@azure/identity`, `@microsoft/microsoft-graph-client`, `tsx`
- GitHub Actions workflow (adapted from `refresh-and-deploy.yml`)

### What Gets Dropped

- `generate-changelog.ts` — viewer concern
- `build-search-index.ts` — viewer concern (search index, category tree, settings-browse.json)
- `fetch-oib-data.ts` — viewer concern (OpenIntuneBaseline)
- All frontend code (`src/`, `public/`, Next.js config, Tailwind, etc.)

### Repository Structure

```
IntuneSettingsCatalogData/
├── scripts/
│   └── fetch-settings.ts        # Copied + trimmed (no changelog/index logic)
├── data/                         # Working directory (gitignored)
│   └── .gitkeep
├── .github/workflows/
│   └── refresh-and-publish.yml   # Nightly cron -> fetch -> GitHub Release
├── package.json                  # Minimal deps
├── tsconfig.json
├── .gitignore                    # data/*.json ignored (large files)
└── README.md
```

### Modifications to fetch-settings.ts

- Remove changelog generation calls
- Remove search index / category tree generation
- Keep: Graph auth, pagination, 429 throttling with Retry-After, orphan category fetch
- Output: `data/settings.json` and `data/categories.json`

### GitHub Actions Workflow: refresh-and-publish.yml

**Triggers:**
- Cron: `0 6 * * *` (06:00 UTC daily)
- Manual dispatch (`workflow_dispatch`)

**Steps:**
1. Checkout repo
2. Setup Node.js 20 + `npm ci`
3. Run `fetch-settings.ts` → produces `data/settings.json` + `data/categories.json`
4. Generate `data/last-updated.json` with ISO timestamp
5. Skip-if-unchanged check: `fetch-settings.ts` already compares fetched data against previous snapshot and reports whether data changed. If no changes detected, skip steps 6-7.
6. Create/update a rolling GitHub Release tagged `latest`:
   - `settings.json` (release asset, ~65MB)
   - `categories.json` (release asset, ~561KB)
   - `last-updated.json` (release asset, ~40 bytes — contains ISO timestamp and `schemaVersion`)
7. Also create a dated tag release (`v2026-04-02`) for historical snapshots. If the tag already exists (e.g., manual re-run after cron), overwrite the existing dated release.

**last-updated.json schema:**
```json
{
  "updatedAt": "2026-04-02T06:26:40Z",
  "schemaVersion": 1
}
```
The `schemaVersion` field allows the PS module to detect incompatible data format changes. The module checks this value before accepting a download — if it encounters an unknown schema version, it warns and falls back to cached data or raw IDs.

### Secrets Required

| Secret | Purpose |
|--------|---------|
| `AZURE_TENANT_ID` | Azure AD tenant for Graph API auth |
| `AZURE_CLIENT_ID` | Service principal client ID |
| `AZURE_CLIENT_SECRET` | Service principal client secret |

Same app registration as IntuneSettingsCatalogViewer. Required permission: `DeviceManagementConfiguration.Read.All` (Application).

### Release Asset URLs (Public, No Auth)

```
https://github.com/royklo/IntuneSettingsCatalogData/releases/latest/download/settings.json
https://github.com/royklo/IntuneSettingsCatalogData/releases/latest/download/categories.json
https://github.com/royklo/IntuneSettingsCatalogData/releases/latest/download/last-updated.json
```

## Part 2: PowerShell Module Integration

### Goal

Replace the bundled/sibling settings.json discovery with a GitHub-first approach that caches locally. All settings catalog management is internal — no new public cmdlets.

### New Private Function: Get-InforcerSettingsCatalogPath

Replaces the current 3-tier discovery chain with:

1. **Explicit path** — if `-SettingsCatalogPath` was passed to the calling cmdlet, use it directly
2. **Local cache (fresh)** — `~/.inforcercommunity/data/settings.json` exists and `cache-meta.json` shows `lastChecked` < 24h ago → use cached file, no network call
3. **Local cache (stale)** — cache exists but older than 24h → lightweight GET of `last-updated.json` from GitHub Release (~40 bytes):
   - If `releaseTimestamp` differs from cached → download new `settings.json` + `categories.json`
   - If same → update `lastChecked` in `cache-meta.json`, use cached file
4. **First-time download** — no cache exists → download both files from GitHub Release
5. **Fallback** — download fails and no cache exists → warn and proceed without resolution (raw IDs shown)
6. **Offline with stale cache** — download fails but cache exists → use stale cache with warning

Same logic applies for `categories.json`. Note: `categories.json` (561KB) has no current consumer in the module — it is downloaded and cached alongside `settings.json` for future use by `Compare-InforcerBaselines` and potential category-aware documentation features. The 561KB overhead is negligible alongside the 65MB settings download.

### Cache Directory Structure

```
~/.inforcercommunity/
└── data/
    ├── settings.json       # 65MB cached
    ├── categories.json     # 561KB cached
    └── cache-meta.json     # Freshness metadata
```

### cache-meta.json Schema

```json
{
  "lastChecked": "2026-04-02T08:30:00Z",
  "releaseTimestamp": "2026-04-02T06:26:40Z",
  "schemaVersion": 1
}
```

- `lastChecked` — when the module last checked GitHub for updates (used for 24h TTL)
- `releaseTimestamp` — the `updatedAt` value from the release's `last-updated.json` (used for staleness comparison)
- `schemaVersion` — the data format version from the release (used for compatibility check)

### Download Implementation

```powershell
$ProgressPreference = 'SilentlyContinue'  # Disable progress bar (massive perf overhead)
$url = 'https://github.com/royklo/IntuneSettingsCatalogData/releases/latest/download/settings.json'
$tmpPath = "$cachePath.tmp"
Invoke-WebRequest -Uri $url -OutFile $tmpPath -UseBasicParsing
Move-Item -Path $tmpPath -Destination $cachePath -Force
```

**Key implementation notes:**
- `Invoke-WebRequest -OutFile` streams to disk without buffering the full 65MB in memory
- `$ProgressPreference = 'SilentlyContinue'` is critical — the PowerShell progress bar adds 10-100x overhead on large downloads
- **Atomic write pattern:** Download to `.tmp` file first, then `Move-Item` to final path. This prevents concurrent sessions from reading a partially-written file. If the download fails, the `.tmp` is left behind (cleaned up on next attempt) and the existing cache remains intact.
- **Redirect handling:** GitHub release asset URLs return a 302 redirect to the CDN. `Invoke-WebRequest` in PowerShell 7 follows redirects by default — no special handling needed.
- **Single retry:** If the download fails, retry once after a 2-second delay before falling back to cache/raw IDs.

### Changes to Import-InforcerSettingsCatalog

- Replace the current path discovery (bundled → sibling → warn) with call to `Get-InforcerSettingsCatalogPath`
- Remove sibling repo fallback (`../IntuneSettingsCatalogViewer/data/settings.json`)
- Keep `-Path` parameter for explicit override (passed through from calling cmdlet)
- Keep `-Force` for session reload
- Keep the O(1) hashtable indexing by `id` into `$script:InforcerSettingsCatalog`

### Changes to Export-InforcerTenantDocumentation

- Keep `-SettingsCatalogPath` parameter as an advanced override
- Internally passes it through to `Import-InforcerSettingsCatalog`
- Update comment-based help for `-SettingsCatalogPath` to document the new cache behavior (replaces the old 3-tier discovery description)
- No other changes — the pipeline stages (collect → normalize → render) are unchanged

### What Gets Removed from the Module

- `module/data/settings.json` bundled file reference from the discovery chain
- Sibling repo discovery path (`../IntuneSettingsCatalogViewer/data/settings.json`)
- `module/data/` directory can be removed entirely (`.gitkeep` no longer needed)

### What Stays Unchanged

- `Resolve-InforcerSettingName` — still O(1) hashtable lookup
- `ConvertTo-InforcerSettingRows` — unchanged
- All renderers (HTML, Markdown, JSON, CSV) — unchanged
- `Connect-Inforcer` / auth flow — unchanged
- `Export-InforcerTenantDocumentation` pipeline stages 1-3 — unchanged

## Out of Scope

- `Compare-InforcerBaselines` cmdlet — future work, separate design (will reuse the same cache infrastructure)
- Changelog in the data repo — stays in the IntuneSettingsCatalogViewer
- Changes to IntuneSettingsCatalogViewer — continues working as-is independently
- Module manifest changes — no new public cmdlets

## Implementation Order

### Step 1: IntuneSettingsCatalogData Repository
1. Create repo on GitHub (public)
2. Copy and trim `fetch-settings.ts` from IntuneSettingsCatalogViewer
3. Set up minimal `package.json` with required dependencies
4. Create `refresh-and-publish.yml` workflow
5. Configure GitHub secrets (AZURE_TENANT_ID, AZURE_CLIENT_ID, AZURE_CLIENT_SECRET)
6. Test workflow manually → verify release assets are published
7. Verify download URLs work without auth

### Step 2: InforcerCommunity Module Integration
1. Create `Get-InforcerSettingsCatalogPath` private function (cache logic)
2. Modify `Import-InforcerSettingsCatalog` to use new path resolution
3. Remove bundled file and sibling repo references
4. Update/add tests for cache behavior (mock HTTP calls)
5. Test end-to-end: fresh download, cached hit, stale refresh, offline fallback
