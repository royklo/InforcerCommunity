# Reports API Cmdlets — Implementation Handoff

**Status:** Design finalized, API-team feedback received, ready to implement.
**Branch:** TBD (likely new `feature/reports-cmdlets` off `main`).
**Owner:** Roy Klooster.

This document is the complete brief for picking up implementation in a new context. It supersedes nothing in the existing skills/contract — those still apply. Read this in conjunction with:
- `Reports-API-Feedback.md` (issues we filed with the API team)
- `/Users/roy/Downloads/feedback-response.md` (API team's responses)
- `module/CLAUDE.md`, `module/Public/*.ps1` (existing module patterns)

---

## 1. What we're building

Six new beta API endpoints under `/beta/reports/*` need PowerShell cmdlets in `InforcerCommunity`. The endpoints let users discover available report types, queue runs, poll for completion, and download outputs (CSV / HTML / PDF / JSON).

Required API scopes: `Reports.Read` and `Reports.Trigger`. Existing scope-documentation rules apply (see `feedback_api_reference_scopes_mandatory` memory).

---

## 2. Final cmdlet inventory (4 public + 5 private)

### Public

| Cmdlet | Endpoint(s) | Default behavior | Notes |
|--------|-------------|------------------|-------|
| `Get-InforcerReportType` | `GET /reports/types` | Returns catalog | `-Key` to look up a single type, `-Tag` filter, `-OutputFormat` filter. Caches result in `$script:InforcerReportTypeCache`. |
| `Invoke-InforcerReport` | `POST /reports/runs` + `GET /runs/{id}/outputs` + download | **Sync + save to `$PWD`** | `-NoWait` for async (returns RunId), `-NoSave` for metadata only, `-OutDir` overrides save location. |
| `Get-InforcerReportRun` | `GET /reports/runs` (+ optional `GET /runs/{id}/outputs`) | Returns run list (warn: ~4-min lag, 500/7-day cap) | `-RunId` for single run, `-Wait` to poll until terminal, `-IncludeOutputs` embeds outputs (+1 API call per run). |
| `Save-InforcerReportOutput` | `GET /runs/{id}/outputs/{id}` | Downloads output bytes | Default `-OutDir = $PWD`. Accepts output objects via pipeline. Uses server's `Content-Disposition` filename. |

**Removed during design iteration:**
- `Wait-InforcerReportRun` → folded into `Get-InforcerReportRun -Wait`.
- `Get-InforcerReportRunOutput` → folded into `Get-InforcerReportRun -IncludeOutputs`.
- `-Report @(@{...})` hashtable parameter set → replaced with parallel arrays.

### Private helpers (in `module/Private/`)

| Helper | Purpose |
|--------|---------|
| `Resolve-InforcerReportTypeSchema` | Cache catalog + validate user input against it (parameter keys, collate-vs-collatable, OutputFormat support, smart defaults like `report-period=30`). |
| `Test-InforcerReportRunTerminal` | Single-poll probe; returns `$true` / `$false` based on 200 vs 404. Encapsulates the polling state logic. |
| `Resolve-InforcerReportOutputFileName` | Parses `Content-Disposition` including RFC 5987 `filename*=UTF-8''…` form. |
| `Invoke-InforcerRawDownload` | Binary-safe GET; returns bytes + suggested filename + correlation ID. Used by `Save-InforcerReportOutput`. |
| **Extension** of existing `Invoke-InforcerApiRequest` | Recognize all three error envelope shapes; surface `x-correlation-id` in verbose stream + error records. |

### Reuse (already exists)

- `Resolve-InforcerTenantId` — already accepts int / GUID / tenant name. `-TenantId` parameters reuse this directly. Alias: `ClientTenantId`.

---

## 3. Parameter contract for `Invoke-InforcerReport`

```powershell
param(
    [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
    [ArgumentCompleter({ <# catalog-driven, falls back to inline list of 25 keys #> })]
    [Alias('Key')]
    [string[]]$ReportType,

    [Parameter(Mandatory)]
    [ArgumentCompleter({ <# narrows by $fakeBoundParameters['ReportType'] #> })]
    [string[]]$OutputFormat,

    [Parameter(Mandatory)]
    [Alias('ClientTenantId')]
    [object[]]$TenantId,

    [ArgumentCompleter({ <# narrows by ReportType: CopilotAdoption→{7,30,90}, ShadowAi→{30,90} #> })]
    [ValidateRange(1,365)]
    [int]$ReportPeriod,

    [ArgumentCompleter({ <# DYNAMIC — see Section 5 below #> })]
    [guid]$AssessmentId,

    [switch]$Collate,
    [switch]$NoWait,
    [switch]$NoSave,
    [string]$OutDir = $PWD.Path,
    [hashtable]$Parameter,   # escape hatch for future API params

    [ValidateSet('PowerShellObject','JsonObject')]
    [string]$OutputType = 'PowerShellObject'
)
```

**Zip / broadcast rules for `-ReportType` / `-OutputFormat`:**
- N reports + 1 format → broadcast (one format for all)
- N reports + N formats → pair by index
- N reports + M formats (where M ≠ 1 and M ≠ N) → error
- 1 report + N formats → error (would otherwise trigger bug #1)

**Type-specific shortcuts that map to API parameters:**
- `-ReportPeriod 30` → `parameters: { 'report-period': '30' }`
- `-AssessmentId <guid>` → `parameters: { 'assessment-id': '<guid>' }`
- Both validated against the type's catalog entry; clear client-side error if invalid.

**Auto-defaults** (driven by `Resolve-InforcerReportTypeSchema`):
- `CopilotAdoption` without `-ReportPeriod` → injects `report-period=30`
- `ShadowAiDetection` without `-ReportPeriod` → injects `report-period=30`
- `Assessment` without `-AssessmentId` → error (no sensible default)

**Output ordering:** the API sorts by `tenantId` asc then `reportType` alphabetical. Cmdlet returns as-is; don't try to match input order.

---

## 4. Empirically-verified facts to build on

These came from two days of probing. They're already in `Reports-API-Feedback.md` but reproducing the implementation-critical ones here:

| Fact | Implication |
|------|-------------|
| `Inf-Api-Key` header (case-insensitive); WWW-Authenticate header on 401 confirms format | Reuse existing auth path |
| 3 distinct error envelopes: app `{success,message,errors}`, APIM `{statusCode,message}`, RFC 9110 `{type,title,status,traceId}` (415 only) | `Invoke-InforcerApiRequest` extension must handle all three |
| `x-correlation-id` on every response | Capture in verbose, include in error records |
| Outputs endpoint: 404 = not terminal, 200 = terminal. Distinguishable error messages for run-vs-output 404s. | Polling logic in `Test-InforcerReportRunTerminal` |
| Malformed GUID → 401 `auth_failure` (APIM artifact) | Always `[guid]::TryParse` client-side first |
| Downloads: raw bytes, proper MIME, `Content-Disposition: attachment; filename=...; filename*=UTF-8''...` | Use the RFC 5987 filename always |
| No caching headers, no ETag, no Range support | Every download is a full GET; no clever caching |
| Output ordering is server-sorted (tenantId, then reportType) | Don't assume input order |
| Data report JSON: `{title, rows[]}` universal | Document, but cmdlet returns raw bytes anyway |
| Document report JSON: bespoke per type, mixed PascalCase/camelCase keys | Cmdlet does not normalize |
| Retention ≥ 15h confirmed empirically; API team says "no defined policy" | Cmdlet docs say "outputs remain available while the API keeps them" — don't promise a window |
| Run list endpoint: 4-min propagation lag, 500-item / 7-day cap, no working filter params | Help text on `Get-InforcerReportRun` must call this out |
| Concurrent: 10 parallel POSTs / 30 parallel GETs all succeed | No client-side throttling needed |

---

## 5. Tab completion design (the riskiest UX bit)

### Static completion (inline-list fallback + cache, no API call)
- `-ReportType` → 25 known keys, augmented by `$script:InforcerReportTypeCache` after first `Get-InforcerReportType` call.
- `-OutputFormat` → reads `$fakeBoundParameters['ReportType']` to narrow; supports broadcast if `-ReportType` is array.
- `-ReportPeriod` → `7,30,90` for `CopilotAdoption`; `30,90` for `ShadowAiDetection`; empty for others.

Pattern matches `Get-InforcerAuditEvent` (inline list to avoid path-completion fallback).

### Dynamic completion for `-AssessmentId` — needs real implementation care

**Three states the user should see:**
1. Not connected → hint completion `<Run Connect-Inforcer first>`
2. Connected without `Assessments.Read` → hint completion `<Assessments.Read API scope required>` (cached as denial sentinel after first 403)
3. Connected with scope → real assessment IDs with friendly names as `ListItemText`, GUIDs as `CompletionText`, names+GUIDs as `ToolTip`

**Performance contract:**
- First TAB: up to 2-second timeout API call. Cache the result (success or denial sentinel).
- Subsequent TABs: instant cache hit.
- Timeout / transient error: return empty, retry on next TAB (don't cache the transient state).

**Cache plumbing:**
- `$script:InforcerAssessmentCache` populated by either (a) the completer's lazy fetch or (b) a side-effect line in existing `Get-InforcerAssessment.ps1`.
- `Disconnect-Inforcer` clears all `$script:Inforcer*Cache` variables.
- Consider a tiny shared `Set-InforcerCompletionCache` Private helper if more dynamic completers appear later.

### MANDATORY post-implementation step

**After cmdlets are implemented, TEST the assessment tab completion empirically with both permission states:**
1. With an API key that has `Assessments.Read`:
   - Verify first-TAB latency feels acceptable (< 2s)
   - Verify the dropdown shows friendly names with GUID as the inserted value
   - Verify tooltip shows full `name — GUID` pairing
   - Verify subsequent TAB presses are instant (cache hit)
2. With an API key that lacks `Assessments.Read` (or scope it down for testing):
   - Verify the hint completion `<Assessments.Read API scope required>` appears
   - Verify it shows up as non-insertable (empty `CompletionText`)
   - Verify the tooltip explains the resolution
3. Without an active session (after `Disconnect-Inforcer`):
   - Verify `<Run Connect-Inforcer first>` hint appears
4. Edge cases:
   - Verify `Disconnect-Inforcer` clears the cache and re-prompting starts fresh
   - Verify the completer doesn't fire when `-ReportType` is set to anything other than `Assessment`

If the latency feels bad in real use, fall back to "populate cache via `Get-InforcerAssessment` only" — strip the lazy fetch from the completer, keep the side-effect cache.

---

## 6. Known API quirks the cmdlets must defensively handle

| Quirk | Cmdlet response |
|-------|-----------------|
| Bug #1: duplicate `(Type, OutputFormat, Collate)` entries render only the last one | **Client-side dedup** in `Invoke-InforcerReport` before POST |
| `collate:true` on `collatable:false` type silently ignored | **Client-side reject** with clear error |
| Unknown parameter keys silently accepted by API | **Client-side validate** parameter keys against catalog |
| `outputCount=0` + `status=completed` is real (no Copilot data, no risky users, etc.) | Return outputs as-is; `Write-Warning` if count < requested |
| Statuses include `running`, `completed`, `completedWithErrors`, `failed` (only `completed` observed in test) | Best-effort list lookup after terminal; surface status in result. Defensive paths for the unobserved states. |
| 3 different error envelopes | `Invoke-InforcerApiRequest` extension handles all three; surfaces `x-correlation-id` |
| Malformed GUID → 401 not 400 | Client-side `[guid]::TryParse` validation |
| List endpoint 4-min lag | `Get-InforcerReportRun` help text + polling uses outputs endpoint, not list |
| Empty result CSVs are 4-byte BOM (`EF BB BF 0A`) — silent skip for other report types | Document, don't try to disambiguate |

---

## 7. Implementation order (vertical slices)

1. **Private helpers** — `Invoke-InforcerApiRequest` extension (envelope handling + correlation ID), `Invoke-InforcerRawDownload`, `Resolve-InforcerReportOutputFileName`, `Test-InforcerReportRunTerminal`, `Resolve-InforcerReportTypeSchema`. Unit tests for each.
2. **`Get-InforcerReportType`** — smallest end-to-end slice. Validates the new private surface, caching infrastructure, basic tab completion.
3. **`Invoke-InforcerReport`** — the centerpiece. Most complex parameter handling. Implement static tab completion first, dynamic `-AssessmentId` last.
4. **`Get-InforcerReportRun`** — wraps the list endpoint with `-Wait` polling and `-IncludeOutputs`.
5. **`Save-InforcerReportOutput`** — thin wrapper over `Invoke-InforcerRawDownload` with pipeline-friendly object intake.
6. **`Disconnect-Inforcer` modification** — clear cache `$script:Inforcer*Cache` variables.
7. **Tab completion testing** (see Section 5 — mandatory).
8. **Docs updates** — `CMDLET-REFERENCE.md`, `API-REFERENCE.md` (per-endpoint scope tables), README example block. Per `inforcer-docs-maintenance` skill, in the same change set, not deferred.

Each slice ships with: cmdlet implementation + comment-based help (including `Required API scope(s):` line) + Pester tests + doc updates. Per `inforcer-unified-guardian` baseline: parameter order `Format → TenantId → Tag → OutputType`, JSON `-Depth 100`, PascalCase properties with `Add-InforcerPropertyAliases`, session auth via `$script:InforcerSession`.

---

## 8. Skills to invoke during implementation

In order of priority:

1. `inforcer-unified-guardian` — baseline, every change touches it. Consistency contract enforcement.
2. `inforcer-performance-maintenance` — verify no performance regressions, esp. in `Invoke-InforcerReport` batching and caching paths.
3. `inforcer-docs-maintenance` — `CMDLET-REFERENCE.md` + `API-REFERENCE.md` must update in same commit. Per `feedback_docs_always_current`.
4. `inforcer-api-feedback` — after implementation, re-audit the cmdlets for any new API quirks worth reporting that we missed.

---

## 9. Open questions to ask the API team later (not blocking V1)

1. For runs with `status: failed` or `completedWithErrors`, does `GET /runs/{id}/outputs` return 200 (with empty array? partial?) or stay 404 forever?
2. Is `collate: true` planned to be rejected at queue time when type has `collatable: false`?
3. Could the outputs endpoint expose `status` in the response body? Would eliminate the need for a list-endpoint lookup.

Until answered, V1 handles both cases defensively — `Get-InforcerReportRun -Wait` polls outputs (404→200) for terminal detection, then does a best-effort `GET /runs` lookup for exact status. Times out cleanly after `-TimeoutSeconds` (default 600s).

---

## 10. Final sanity check before writing code

Confidence: high.
- All endpoints verified twice across 24+ hours
- API team confirmed status enum, retention story, list endpoint caps
- Cmdlet shape mirrors existing module idioms (no new architecture)
- Open unknowns (`failed` semantics, dynamic completion latency) have clear defensive fallbacks

Risk: the dynamic `-AssessmentId` tab completion is novel for this module. If it doesn't feel right in testing, drop the lazy fetch and rely on `Get-InforcerAssessment` side-effect priming only.
