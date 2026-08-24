# Changelog

All notable changes to this project will be documented in this file.

The format follows [Conventional Commits](https://www.conventionalcommits.org/). Versioning deviates from strict SemVer: every shipped change (feat / fix / perf / non-breaking refactor) bumps MINOR; docs/tests/chore-only commits don't bump. While the module is pre-1.0 a breaking change also bumps MINOR and is called out under a **Breaking Changes** heading — 1.0.0 is reserved for the point the public surface is declared stable, after which breaking changes bump MAJOR. There is intentionally no `[Unreleased]` section — every entry is dated at ship time.

## [0.7.0] - 2026-08-24

### Breaking Changes

- **`Compare-InforcerEnvironments` and `Export-InforcerTenantDocumentation` no longer write files by default, and no longer open a browser.** Both had `$OutputPath = '.'` plus an unconditional `Start-Process` on the rendered HTML, so neither could run without dropping a file into the caller's working directory and spawning a browser window. In a CI pipeline or a container that is wrong twice over: the file is litter, and there is nothing to open it with.
  - Writing now happens only when `-OutputPath` is given. There is no default. `-OutputPath`'s presence *is* the opt-in — a separate `-Export` switch would carry no information the path does not already carry.
  - Opening a browser now requires the new `-Show` switch.
  - **Without `-OutputPath` the cmdlets return the model instead of `System.IO.FileInfo`** — the comparison hashtable from `Compare-InforcerEnvironments`, the DocModel hashtable from `Export-InforcerTenantDocumentation`. This makes it possible to read alignment scores or tenant configuration without producing artefacts.
  - **Migration:** add `-OutputPath <dir>` to any call that relied on files appearing in the working directory, and `-Show` to any call that relied on the browser opening. Scripts consuming the `FileInfo` return value need `-OutputPath` to keep that return type.

### Bug Fixes

- **`Invoke-InforcerAssessment` could never reach the API.** Every call failed with `400 ValidationFailure — "Unspecified content type application/json is not allowed."` `POST /beta/tenants/{id}/assessments/{assessmentId}/runs` accepts no request body and rejects *any* `Content-Type`. Removing the header from the hashtable was not enough: `Invoke-RestMethod` supplies `application/x-www-form-urlencoded` on a bodyless POST, which is rejected the same way. Now sends `-ContentType ''`, which suppresses it entirely.
- **`Invoke-InforcerAssessment -MultiTenant` crashed instead of reporting when every tenant failed.** The run loop fell through to renderers whose `-TenantResults` is mandatory, producing `Cannot bind argument to parameter 'TenantResults' because it is an empty collection` — a parameter-binding error that said nothing about why the runs failed. A single guard after the loop now covers the JSON, HTML and CSV paths and emits `NoAssessmentResults`.
- **`Compare-InforcerEnvironments -SourceBaselineId` reported a meaningless alignment score.** Scoping the source left the destination at its full policy set, so N baseline policies were compared against the destination's entire estate and every destination-only policy counted as a deviation: a 3-policy baseline against a 756-policy tenant scored **0.2%** where Inforcer's own alignment for the same pair is 100%. The docstring advertised exactly that one-sided form as an example. The destination now inherits `-SourceBaselineId` unless `-DestinationBaselineId` overrides it (same pair now scores 100% over 3 items). When the destination genuinely is not a member of the baseline it falls back to its full policy set with a warning naming the consequence, rather than erroring; an explicitly passed `-DestinationBaselineId` that fails is still an error.
- **`Compare-InforcerEnvironments -ExcludeOS` was a no-op for every value its own documentation gave as an example.** It matched only the product name (`Entra`, `Intune`, `Defender`, …), while the OS lives in the category key built from `primaryGroup` (`Windows`, `macOS`, `iOS/iPadOS`, `Android`). `-ExcludeOS 'macOS','iOS'` removed 0 of 2229 items while reporting success. It now matches the category key as well as the product name, so `-ExcludeOS 'macOS','iOS'` removes 720 items and passing a product name still works.
- **`-FetchGraphData` silently installed a module onto the machine.** `Connect-InforcerGraph` ran `Install-Module Microsoft.Graph.Authentication -Scope CurrentUser -Force -AllowClobber` with no consent when the module was absent. `-Force` suppresses the untrusted-repository prompt and `-AllowClobber` permits overwriting commands owned by other modules — neither is appropriate for a read-only reporting module, and on a locked-down or offline host it failed with a PowerShellGet error rather than saying what was missing. It now detects and reports, naming the install command, matching how the `ImportExcel` dependency is already handled. A **warning**, not an error: every caller already falls back to raw ObjectIDs on a null Graph context, and `Write-Error` would have terminated that graceful path under `$ErrorActionPreference = 'Stop'`.

- **`Export-InforcerTenantDocumentation -Tag` rendered an empty document when nothing matched.** A 0.1 KB file and exit 0 reads as "nothing in this tenant is tagged that way" when the likelier cause is a tag name that does not exist. It now emits `TagMatchedNothing` and names the tags that do exist, writing no file.

### Refactor

- **Removed 229 no-op property-alias calls from `Add-InforcerPropertyAliases`.** Every call whose alias differed from the API name only by case did nothing: the "does this alias already exist" guard uses `$o.PSObject.Properties[$aliasName]`, which is a case-**insensitive** lookup, so `ClientTenantId` found the existing `clientTenantId` and bailed. 229 of 238 calls were affected; the 9 genuine renames (`BaselineId<-id`, `BaselineName<-name`, `PolicyId<-id`, `OutputFormats<-supportedOutputFormats`, `Parameters<-requiredParameters`, `Id<-runId`, `OutputId<-id`, `OutputFormat<-format`, `FileSize<-sizeBytes`) are unaffected and still fire.

  They were deleted rather than repaired, because making them work would have been worse than leaving them broken:
  - PowerShell member access is already case-insensitive. `$tenant.ClientTenantId` — and `$tenant.TENANTFRIENDLYNAME` — resolve today with no alias present.
  - An alias **is** serialised. The 9 real renames already emit both `"id"` and `"BaselineId"` in `ConvertTo-Json`, and two separate `Export-Csv` columns. Adding 229 more would have doubled every key and column, the same value in two casings.
  - `-OutputType JsonObject` returns before the helper runs, deliberately, so the JSON surface is the raw API shape and never carried PascalCase to begin with.

  **No behaviour change.** Property access, `Select-Object`, `ConvertTo-Json`, `Export-Csv` and every `Format.ps1xml` view produce identical output before and after. The `-ObjectType` ValidateSet is unchanged so all 13 call sites still work; types needing no normalisation simply have no branch.

### Documentation

- `-OutputPath`, the new `-Show` switch, and the changed return types documented in `Get-Help` and `docs/CMDLET-REFERENCE.md` for both affected cmdlets.
- `-ExcludeOS` help now states that matching applies to both product names and platform category keys.
- `-SourceBaselineId` help documents destination inheritance and the non-member fallback; the stale example claiming a one-sided comparison against "all Fabrikam policies" corrected.
- Versioning note above clarified: pre-1.0, breaking changes bump MINOR under a **Breaking Changes** heading rather than MAJOR.

## [0.6.0] - 2026-07-06

### Features

- **New cmdlet: `Get-InforcerSecureScore`** — retrieves the current and historic Microsoft Secure Score for a tenant from `GET /beta/tenants/{tenantId}/secureScores`. Returns the current score, max score, licensed user count, enabled services, up to 90 days of daily score history, per-category scores, and actionable control profiles with remediation guidance. `-TenantId` accepts numeric ID, GUID, or tenant name (name/GUID resolution via `Resolve-InforcerTenantId`). Supports `-OutputType JsonObject`. Required scopes: `Tenants.SecureScores.Read` + `Tenants.Read` (only when `-TenantId` is a GUID or tenant name). PSTypeName `InforcerCommunity.SecureScore` with a ListControl default view showing:
  - `CurrentScore` / `MaxScore` / `CurrentScorePercentage` (capped at 2 decimals for display) / `LicensedUserCount` / `EnabledServices` (joined).
  - `ScoreHistory` — day count + `first → last` ISO 8601 date range + latest score. Culture-safe: dates use InvariantCulture so nl-NL / de-DE etc. all read the same as en-US.
  - `ControlCategoryScores` — every category inline, e.g. `Identity: 49.13/71, Apps: 177/198, Data: 7/9, Device: 769.75/989`.
  - `ControlProfilesCount` and `TopRecommendations` — the 3 highest-`scoreDifference` open controls, so "what do I fix next" is on-screen without drilling.
  - `Hint` — points to `.ControlProfiles | Sort-Object ScoreDifference -Descending`, `.Scores`, and `.ControlCategoryScores[0].HistoricScores` for the full data.
- **New nested PSTypeName: `InforcerCommunity.SecureScoreControlProfile`** — every item in `.ControlProfiles` gets this type inserted, so `$s.ControlProfiles | Format-List` renders a compact view (`Title`, `ControlCategory`, `Service`, current/max score with potential gain, `RemediationImpact`, `ActionUrl`, `Id`) instead of dumping the giant HTML `remediation` blob. The full remediation HTML is still on the object as `.remediation` when needed.
- **`Get-InforcerAuditEvent -User <string>`** — new parameter that server-side filters audit events by the specified user (matches the `user` field in the `POST /beta/auditEvents/search` request body). Previously users had to fetch all events and filter client-side.
- **`Id` alias on audit event output** — `AuditEvent` objects now expose the raw `id` field as PascalCase `Id`, consistent with every other object type in the module.
- **Dynamic `-EventType` tab completion** — the completer on `Get-InforcerAuditEvent -EventType` now reads `$global:InforcerCachedEventTypes`, which `Get-InforcerSupportedEventType` refreshes with the live server-side list on any authenticated call. New event types the API adds appear in tab completion automatically after the next `Get-InforcerSupportedEventType` call — no module release required. A static fallback list (currently 80 event types) covers the pre-connect case.
- **`Get-InforcerSecureScore` nested aliasing extended** — `.ControlCategoryScores` and its inner `.historicScores` now get PascalCase aliases too (previously only top-level, `.Scores`, and `.ControlProfiles` were aliased).

### Documentation

- **`Required API scope(s):` line added to `Get-Help` output for 13 cmdlets** — `Compare-InforcerEnvironments`, `Export-InforcerTenantDocumentation`, `Get-InforcerAlignmentDetails`, `Get-InforcerAssessment`, `Get-InforcerAuditEvent`, `Get-InforcerBaseline`, `Get-InforcerGroup`, `Get-InforcerRole`, `Get-InforcerSupportedEventType`, `Get-InforcerTenant`, `Get-InforcerTenantPolicies`, `Get-InforcerUser`, `Invoke-InforcerAssessment`. Users no longer need to leave PowerShell and open `docs/API-REFERENCE.md` to learn which scope a cmdlet needs. Follows the pattern already used by the Reports cmdlets.
- **Removed stale `PolicyDiffFormatted` mention** in `docs/CMDLET-REFERENCE.md` — the property was removed from the module in an earlier version (see FINDINGS #63) but one line in the docs was missed.
- Added `Get-InforcerSecureScore` section to `docs/CMDLET-REFERENCE.md`; endpoint description, schemas (`TenantSecureScoreDetails`, `TenantSecureScoreHistoryPoint`, `TenantSecureScoreControlProfile`), and scope-mapping row added to `docs/API-REFERENCE.md`; cmdlet added to the README public-surface table.
- Expanded the `Get-InforcerSecureScore` docs and `Get-Help` examples with 10 drill-in patterns: sort recommendations by score gap, filter by control `Id`, group open work by category with total potential gain, drill into a category's daily history, `Export-Csv` for a remediation ticket, `Start-Process` on the top `ActionUrl`, etc.

### Bug Fixes

- **`Get-InforcerUser -UserId` was returning the wrong shape.** Live-API verification exposed this: without `-PreserveStructure`, `Invoke-InforcerApiRequest`'s "unwrap first array property of `.data`" convenience was unwrapping the user object's nested arrays (e.g. `groups`, `assignedLicenses`), so the cmdlet returned an array of group memberships instead of the user detail. `PSTypeName` was never applied. Fix: added `-PreserveStructure` to the API call.
- **New `Get-InforcerSecureScore` needed the same fix on first flight** — same root cause, same defense (`-PreserveStructure` added). Live-verified: cmdlet now returns a single `InforcerCommunity.SecureScore` object with 90-day history, control profiles, and category scores populated as documented.

## [0.5.0] - 2026-06-30

### Features

- **New cmdlet: `Get-InforcerReportType`** — lists all available report types (Active User Count, Tenant Audit Report, Copilot Adoption, etc.) from `GET /beta/reports/types`. Filters by `-Key`, `-Tag`, and `-OutputFormat`. Results cached client-side and reused by tab completion; `-Force` refetches.
- **New cmdlet: `Invoke-InforcerReport`** — queues one or more report runs via `POST /beta/reports/runs`, polls until each run is complete, and saves the outputs to disk. Key capabilities:
  - **Three execution modes** — default is sync + save to the current directory (or `-OutputPath`); `-NoWait` queues and returns immediately with the run IDs; `-NoSave` polls until terminal without writing files.
  - **Auto-open with `-Open`** (aliases `-Show`, `-ShowResult`) — launches each saved file with the OS default handler (HTML → browser, PDF → viewer, CSV/XLSX → spreadsheet). Extensions are allowlisted so the server can't dictate launching an executable.
  - **Pipeline-bindable** — `Get-InforcerReportType -Tag Security | Invoke-InforcerReport -OutputFormat csv -TenantId 482` batches every piped report type into one POST.
  - **Three-phase progress bar** — queue → poll (with elapsed time and poll count) → download → complete.
  - **Friendly input** — `-TenantId` accepts numeric IDs, GUIDs, or tenant names. Unknown report types trigger one auto-refresh of the catalog before failing, so new types ship without forcing a disconnect/reconnect.
  - **Required scopes** — `Reports.Read` + `Reports.Run` (+ `Tenants.Read` only when `-TenantId` is a GUID or tenant name).
- **New cmdlet: `Get-InforcerReportRun`** — lists report runs from `GET /beta/reports/runs` (server caps the result at 500 items / last 7 days). `-Wait` with `-RunId` polls until the run is complete and bypasses a ~4-minute lag between completion and list visibility. `-IncludeOutputs` embeds each run's outputs.
- **New cmdlet: `Save-InforcerReportOutput`** — downloads a specific report output to disk via `GET /beta/reports/runs/{runId}/outputs/{outputId}`. Pipeline-friendly with `Invoke-InforcerReport -NoSave` and `Get-InforcerReportRun -IncludeOutputs`. Uses the server's `Content-Disposition` filename (with full Unicode support); `-FileName` overrides. Sanitizes Windows reserved names (`CON`, `PRN`, `AUX`, etc.) and caps length at 200 characters while preserving the extension. Accepts optional `-ReportType`, `-OutputFormat`, and `-TenantId` (alias `-ClientTenantId`) pipeline-bindable pass-through parameters so the emitted result matches the `InforcerCommunity.ReportRunResult` format view when piped from upstream cmdlets.
- **Dynamic tab completion for `-AssessmentId` on `Invoke-InforcerReport`** — three permission-aware states: not connected (hint to run `Connect-Inforcer`), connected without scope (hint about `Assessments.Read`, denial cached so subsequent TABs are instant), connected with scope (friendly names in the dropdown, opaque assessment ID inserted on selection, `name — id` shown as the tooltip).
- **`Connect-Inforcer` primes the Reports catalog cache** on a successful connect (best-effort, 4-second budget, silent on missing scope) so tab completion on `Invoke-InforcerReport -ReportType` shows live keys on the very first attempt.
- **API errors now include field-level details.** When the server returns a structured `errors[]` array, each entry is rendered into the error text — `Invoke-InforcerReport` against a tenant outside the key's scope now reads *"Validation failed — tenants.includeTenants contains tenant X that is not in the API key's scope"* instead of the generic *"see errors for details"* placeholder. The `x-correlation-id` response header is also captured (visible in verbose output and included in error records) for support tickets.

### Documentation

- Sections for all four Reports cmdlets added to `docs/CMDLET-REFERENCE.md`; Reports endpoints and schemas added to `docs/API-REFERENCE.md`; the new cmdlets (plus `Get-InforcerSupportedEventType`, which was missing) added to the README public surface table.

### Bug Fixes

- **`Connect-Inforcer` now reports a meaningful error on HTTP 401 in PowerShell 7.** Previously the error handler only fired on the PowerShell 5.1 exception type, so PS7 users saw an empty error message when the API key was rejected. Now extracts the status code and message from either exception path.
- **`Connect-Inforcer` accepts any valid API key, regardless of scope.** Customers with keys scoped only to `Reports.Read`, `Assessments.Read`, or `Audit.Read` previously couldn't connect because the validation probe required `Baselines.Read` / `Tenants.Read` and a 403 was treated as failure. The cmdlet now distinguishes "key rejected" from "key valid but scope missing" and accepts the latter.
- **`-AssessmentId` dynamic completer caches denial on HTTP 401 as well as 403.** The gateway returns 401 for both subscription-level rejection and missing scopes; previously only 403 was cached, so the second TAB still hit the network. Both are now cached.
- **JSON depth 100 enforced** in three pre-existing helpers (`Get-InforcerComparisonData`, `Compare-InforcerDocModels`, `Resolve-InforcerGraphEnrichment`) and two cache-metadata writes in `Get-InforcerSettingsCatalogPath` that had no explicit depth — prevents truncation on deep policy structures.
- **`Invoke-InforcerReport -AssessmentId ''` now throws a clear local error** instead of forwarding `assessment-id=''` to the server (which produced a generic validation failure). Empty / whitespace-only values are rejected up front with a hint to run `Get-InforcerAssessment`.

### Tests

- 6 new Pester tests for the `errors[]` array renderer covering field/code/message rendering, plain-string entries, alternate property aliases, null/empty inputs, and unrecognized object shapes. Total suite: 394 pass / 0 fail / 2 legit skips.
- Pre-merge live smoke harness (`Tests/Manual/Live-ApiSmoke.ps1`, gitignored) verified all four Reports cmdlets end-to-end against the DEV API: 24/24 PASS.

## [0.4.0] - 2026-05-15

### Features

- **New cmdlet: `Get-InforcerAssessment`** — lists all available assessments (Copilot Readiness, CIS Benchmarks, Essential Eight, etc.) from `GET /beta/assessments`. Returns assessment name, ID, description, tags, type, and dates.
- **New cmdlet: `Invoke-InforcerAssessment`** — runs an assessment against one or more tenants via `POST /beta/tenants/{id}/assessments/{id}/runs`. Key capabilities:
  - **Friendly name resolution** — `-AssessmentId "Copilot Readiness"` resolves to the assessment ID automatically. `-TenantId` supports numeric IDs, GUIDs, and tenant names.
  - **Async execution with progress** — runs in a background runspace with 10-second progress updates and human-readable elapsed time (e.g., "3m 16s").
  - **Per-check pipeline output** — each check emits as a pipeline object with Status, Scores, Violations, Warnings, Passes arrays for automation.
  - **Multi-tenant mode** — `-MultiTenant` runs against all tenants; `-TenantId "Contoso","Fabrikam"` runs against a subset. Shows per-tenant compliance summary and total elapsed time.
  - **HTML export** — `-OutputPath report.html` generates an interactive single-tenant report with collapsible checks, per-object expandable cards, markdown-rendered descriptions/remediation, and CIS benchmark-style design.
  - **Multi-tenant HTML matrix** — `-MultiTenant -OutputPath matrix.html` generates a full-viewport matrix report with sticky check column, horizontal scroll for 100+ tenants, tenant filter dropdown, search, status filters, slide-out detail panel, and category grouping.
  - **CSV export** — `-OutputPath report.csv` exports flat data with UTF-8 no-BOM encoding. Multi-tenant CSV includes a Tenant column.
  - **JSON output** — `-OutputType JsonObject` returns structured JSON for automation pipelines, both single and multi-tenant.
- **New private helpers** — `Resolve-InforcerAssessmentId` (name/ID resolution), `Invoke-InforcerAssessmentRun` (async single-tenant runner), `ConvertTo-InforcerAssessmentHtml` (single-tenant report), `ConvertTo-InforcerAssessmentMatrixHtml` (multi-tenant matrix).

### Bug Fixes

- **Cross-category DefinitionId reconciliation** — when one tenant uses Endpoint Security templates and another uses Settings Catalog for the same settings, they now reconcile correctly as Matched or Conflicting instead of SourceOnly/DestOnly.
- **Excluded Deployed App Count from comparison** — tenant-specific metadata in App Protection Policies no longer causes false conflicts.
- **Whitespace heuristic replaced with HasDefinitionId flag** — prevents false cross-category reconciliation of single-word setting paths.
- **Dead code removed** — unused `$extraSrc`/`$extraDst` lists, vestigial `DeprecatedSettings` output property.
- **O(n^2) optimization** — setting key union building uses HashSet for O(1) lookups.
- **Where-Object replaced with foreach** — setting count loops follow module conventions.

### Tests

- Added 6 new consistency tests for assessment cmdlets (no-session, parameter binding, JSON output).
- Updated expected cmdlet count from 14 to 16.
- Added cross-category reconciliation tests and Deployed App Count noise exclusion test.

## [0.3.2] - 2026-05-14

### Bug Fixes

- **Cross-category DefinitionId reconciliation** — when one tenant uses Endpoint Security templates (Disk Encryption, Antivirus, Firewall) and another uses Settings Catalog for the same settings, they land in different categories and were never compared. Added a reconciliation pass that matches unmatched settings by DefinitionId across categories, reclassifying them as Matched or Conflicting instead of SourceOnly/DestOnly.
- **Excluded Deployed App Count from comparison** — the "Deployed App Count" setting in App Protection Policies is a tenant-specific metadata value that nobody controls. It was causing false conflicts when comparing identical MAM policies across tenants.

### Tests

- Added cross-category reconciliation tests (4 scenarios: matched, conflicting, no-defId fallback, same-category untouched).
- Added noise exclusion test for Deployed App Count filtering.

## [0.3.1] - 2026-05-01

### Features

- **Baseline-scoped comparison** — `Compare-InforcerEnvironments` now supports `-SourceBaselineId` and `-DestinationBaselineId` parameters. Compare only the policies that belong to a specific baseline instead of the entire tenant. All four modes work: tenant vs tenant, baseline vs tenant, tenant vs baseline, and baseline vs baseline. The report header and filename automatically reflect which baselines are active.
- **Auto-resolve baseline owner tenant** — `-SourceTenantId` and `-DestinationTenantId` are no longer mandatory. When a baseline ID is provided without a tenant ID, the baseline owner tenant is resolved automatically from the API. Example: `Compare-InforcerEnvironments -SourceBaselineId "Tier 1 - Foundations" -DestinationTenantId 14506`.
- **Shared baseline filtering** — extracted the baseline policy filtering logic from `Export-InforcerTenantDocumentation` into a reusable `Select-InforcerBaselinePolicies` private helper. Both Export and Compare now share the same filtering pipeline, reducing code duplication by ~95 lines.

### Bug Fixes

- **Duplicate detection was cross-tenant** — Phase 2 duplicate scan mixed Source and Destination entries into the same bucket, falsely flagging normal cross-tenant value differences (e.g., ASR "Block" vs "Audit") as duplicates. Fixed by scoping detection per-side so only true within-tenant duplicates are detected.
- **Duplicate settings no longer appear in Comparison tab** — settings shown in the Duplicates tab are now fully removed from the Comparison tab (all statuses), using DefinitionId-based matching for reliable identification.
- **Opposite-side context in Duplicates tab** — duplicate entries now show what the other tenant has configured for the same setting, giving full cross-tenant context without leaving the tab.
- **Duplicate detection scoped by platform** — prevents cross-OS false matches (e.g., Windows Edge vs macOS Edge settings).
- **Duplicate detection scoped by DefinitionId** — uses DefinitionId as grouping key instead of display name, preventing false matches on same-named settings from different templates.
- **Duplicate detection scoped by ProfileType and category** — prevents cross-template false matches (e.g., macOS plist "Rules > Comment" for Edge vs Office).
- **Cross-category duplicate detection** — Phase 3 detects the same DefinitionId appearing in different categories (e.g., ASR settings delivered via Endpoint Security AND Settings Catalog profiles).
- **Ambiguous comparisons routed to Manual Review** — when within-side duplicates exist, affected comparisons are sent to Manual Review with structured setting fields instead of showing unreliable results.
- **Manual Review cards not expanding** — `overflow: hidden` on `.mr-split-cell` and `.mr-body` prevented `<details>` elements from opening. Changed to `overflow-x: hidden; overflow-y: visible`.
- **Manual Review layout push-down** — expanding a policy card on one side pushed all cards on the other side down because matched pairs shared a CSS grid row. Replaced with independent column layout so each side flows vertically on its own.
- **API response handling** — improved null/empty response handling and `[char]0` null char splitting in single-quoted strings.

### Improvements

- **Duplicates summary bar** — stats display inline with separators instead of stacking vertically.

## [0.3.0] - 2026-04-16

### Features

- **New cmdlet: `Compare-InforcerEnvironments`** — compares two tenants' Intune configuration and generates an interactive HTML comparison report with 4 tabs: Comparison (flat table with sortable columns, status filters, category dropdown, advanced filters), Manual Review (50/50 source/destination layout with matching policies aligned side-by-side), Duplicates (settings in 2+ policies with different values), and Deprecated (settings flagged by Microsoft). Animated configuration match score with confetti at 100%.
- **New cmdlet: `Get-InforcerGroup`** — retrieves Entra ID groups from an Inforcer tenant. Supports list with search/pagination (GroupSummary) and detail by name or GUID via `-Group` (Group with members). Parameters: `-TenantId`, `-Group`, `-Search`, `-Filter`, `-MaxResults`, `-OutputType`.
- **New cmdlet: `Get-InforcerRole`** — retrieves Entra ID directory role definitions from an Inforcer tenant. Shows display name, description, and whether each role is built-in, enabled, or privileged. Parameters: `-TenantId`, `-OutputType`.
- **`Connect-Inforcer -PassThru`** — returns the session hashtable to the pipeline for cross-account comparison workflows.
- **Script/rules decoding:** Base64-encoded detection scripts, remediation scripts, and compliance rules (`rulesContent`) are automatically decoded and rendered as collapsible code blocks with syntax highlighting (PowerShell blue, Bash red, JSON indigo) in both Export and Compare HTML reports.
- **Friendly setting names:** Non-Settings-Catalog property names are converted from camelCase to Title Case (e.g., `allowBluetooth` → "Allow Bluetooth") across both Export and Compare reports.
- **Graph compliance rules:** When `-FetchGraphData` is specified, compliance policy detection rules (`rulesContent`) are fetched individually from Graph and discovery scripts are linked to parent compliance policies.
- **GitHub issues link:** Both Export and Compare HTML reports include a footer link to report bugs or missing information.

### Bug Fixes

- **Baseline filter matching:** Alignment API uses friendly names (e.g., "Default User Role Permissions") while tenant policies store internal names (e.g., "DefUserRolePerms"). Filter now checks all name fields (`displayName`, `friendlyName`, `name`, `policyData.displayName`, `policyData.name`) and GUID fields independently. Fixes issue where only 31 of 48 baseline policies matched. ([#15](https://github.com/royklo/InforcerCommunity/issues/15))
- **Baseline filter scope:** Excluded `additionalInSubjectUnaccepted` from baseline policy collection — these are tenant-only policies not in the baseline.
- **Intune assignment filters for All Users/All Devices:** Filter properties (`deviceAndAppManagementAssignmentFilterId`/`Type`) are now checked on both the `target` object and the `assignment` level, fixing resolution when API wrappers place filter data at the assignment level. ([#11](https://github.com/royklo/InforcerCommunity/issues/11))
- **Conditional Access GUID resolution:** Group, role, named location, and application GUIDs in CA policy conditions are now resolved to display names via Microsoft Graph when `-FetchGraphData` is used. ([#11](https://github.com/royklo/InforcerCommunity/issues/11))
- **Settings Catalog deferred loading:** Catalog (~65 MB) is only loaded when policyTypeId 10 (Intune/Defender) policies are present. Baselines without Intune policies skip the load entirely.
- **Error messages:** Improved tenant access error messages with specific guidance for 403 (permission) and 404 (not found) failures.
- **Export tenant name in Graph prompt:** Shows tenant friendly name during Graph sign-in (e.g., "Connecting to Microsoft Graph for Contoso...").

### Improvements

- **Friendly CA property names:** 50+ camelCase property names mapped to human-readable labels (e.g., `includeGroups` → "Include Groups", `builtInControls` → "Built-in Controls").
- **Auth combination labels:** camelCase values like `windowsHelloForBusiness` → "Windows Hello for Business", `password,softwareOath` → "Password + Software OATH Token".
- **ISO 8601 duration conversion:** Values like `PT0S` → "0 (immediate)", `P30D` → "30 days", `PT24H` → "24 hours" across all policy types.
- **Well-known app ID resolution:** 22 pre-mapped Microsoft application IDs (Intune, Graph, Teams, etc.) with Graph fallback for unknown IDs.
- **HTML multi-value display:** Comma-separated values render as vertical lists. Lists with 10+ items show first 10 with a "+ N more" expand button.
- **HTML hide empty fields by default:** Empty fields are hidden on page load (toggle still available in sidebar).
- **HTML search filtering:** Search now hides empty product sections and category headers with no matching policies.
- **HTML description visibility:** Long description fields show ~8 lines before requiring expand (previously ~2 lines).
- **Settings Catalog load performance:** Uses `-AsHashtable` for faster JSON parsing with visible progress message and timing.
- **Code quality:** Extracted shared helpers (`$enrichComplianceData`, `$resolveGuid`, `$getSettingPathHtml`), removed ~90 lines of dead code and duplication across 8 files, consolidated GUID resolution patterns, removed unused CSS classes.

### Tests

- Added `Tests/DocModel.Tests.ps1` with 61 tests covering noise exclusion, deprecated detection, duplicate detection (single-tenant, cross-tenant, duplicate-only exclusion), and setting path building.
- Added `Tests/Renderers.Tests.ps1` with 128 tests covering HTML structure, value display, assignments, table enhancements, filtering/navigation, manual review content, duplicate tab, and deprecated badge rendering.
- Added `Tests/GraphResolution.Tests.ps1` with 8 tests covering assignment filter fallback, CA GUID resolution (groups, roles, locations), multi-value handling, and non-GUID value preservation.
- Added consistency tests for `Get-InforcerGroup` and `Get-InforcerRole`: exported cmdlet count, parameter validation, no-silent-failure, parameter binding, and property alias tests for GroupSummary, Group, and Role object types.
- Updated `Tests/SettingsCatalog.Tests.ps1` for friendly setting names, DefinitionId property, and unknown ID handling.

---

## [0.2.0] - 2026-04-02

### Features

- **New cmdlet: `Export-InforcerTenantDocumentation`** — generates comprehensive, human-readable documentation of an entire M365 tenant's configuration. Supports HTML, Markdown, and Excel output formats. Parameters: `-Format`, `-TenantId`, `-OutputPath`, `-SettingsCatalogPath`, `-FetchGraphData`, `-Baseline`, `-Tag`.
- **Settings Catalog runtime fetch:** The module now automatically downloads and caches the Intune Settings Catalog data (~65 MB) from [IntuneSettingsCatalogData](https://github.com/royklo/IntuneSettingsCatalogData) GitHub Releases. Replaces the bundled static `settings.json`. Cache stored at `~/.inforcercommunity/data/` with 24-hour TTL, atomic writes, single retry, and offline fallback.
- **HTML output:** Modern 2025 admin dashboard design with glassmorphism sidebar, collapsible Product > Category > Policy navigation, tag filter pills (AND/OR), real-time search with text highlighting, dark/light mode toggle (localStorage persistence), hide empty fields toggle, show metadata toggle, back-to-top button, notch-style status bar, collapsible long values. Self-contained with embedded CSS and JavaScript (no CDN dependencies).
- **Excel export (`-Format Excel`):** Replaces CSV. Creates an `.xlsx` workbook with one sheet per product, auto-sized columns, filters, and frozen header row. Requires the `ImportExcel` module.
- **Graph integration (`-FetchGraphData`):** Resolves group ObjectIDs to display names, assignment filter IDs to names, and scope tag IDs to names via Microsoft Graph. Validates Graph tenant matches Inforcer tenant.
- **Baseline and tag filtering:** `-Baseline` filters to policies in a specific baseline via alignment details API. `-Tag` filters by Inforcer tag name (case-insensitive).
- **`Connect-Inforcer` updated:** Added `-FetchGraphData` switch to simultaneously connect to Microsoft Graph alongside Inforcer API.
- **`Disconnect-Inforcer` updated:** Now also disconnects Microsoft Graph session when active.

### New Private Functions

- `Get-InforcerSettingsCatalogPath` — 6-tier cache resolution strategy: explicit path → fresh cache → stale remote check → first-time download → fallback → offline with stale cache.
- `Export-InforcerDocExcel` — Renders DocModel to multi-sheet Excel workbook via ImportExcel.
- `Get-InforcerPolicyDisplayInfo` — maps API internal names to Microsoft admin portal categories (Entra 21 settings, SharePoint 11, M365 Admin Center 3).
- `Resolve-InforcerAssignments` — translates assignment `@odata.type` to friendly names (All Devices, All Users, Group Include/Exclude).
- `Connect-InforcerGraph` — auto-installs `Microsoft.Graph.Authentication`, handles Graph sign-in with tenant targeting.
- `Invoke-InforcerGraphRequest` — wraps `Invoke-MgGraphRequest` with retry logic and automatic paging.

### Changes

- `Import-InforcerSettingsCatalog` now delegates path resolution to `Get-InforcerSettingsCatalogPath` instead of looking for bundled/sibling files.
- `Export-InforcerTenantDocumentation` removed inline discovery chain (bundled → sibling → warn). `-SettingsCatalogPath` parameter now documents the auto-download behavior.
- `Export-InforcerTenantDocumentation` `-Format` replaced `Csv` with `Excel`. Removed `ConvertTo-InforcerDocCsv` renderer.
- Removed `module/data/.gitkeep` — settings catalog data is no longer bundled with the module.

### Improvements

- Object arrays (apps, approvedKeyboards) now display item count plus individual items instead of comma-separated empty strings.
- Categories sorted alphabetically and grouped by platform (e.g., Windows > subcategories).
- "All /" prefix stripped from category display names.
- Policy tags shown inline as blue-bordered badges; "None" shown for policies without assignments.
- Progress reporting during export; auto-opens HTML in browser after export.
- Returns `FileInfo` objects for exported files.

## [0.1.0] - 2026-03-30

### Features

- **New cmdlet: `Get-InforcerUser`** — list/search users or get full user detail by ID. Two ParameterSets (List, ById), auto-pagination via continuationToken, server-side `-Search`, `-MaxResults` cap, dual output types (UserSummary, User). Streams results to pipeline immediately.
- **New cmdlet: `Get-InforcerAlignmentDetails`** — replaces `Get-InforcerAlignmentScore`. Supports `-BaselineId` for per-policy alignment detail (matched, deviated, missing). Table and Raw formats. Baseline owner detection auto-includes aligned tenants.
- **New cmdlet: `Get-InforcerSupportedEventType`** — returns supported audit event types (moved from private helper to public cmdlet).
- **Tenant name resolution** — `-TenantId` now accepts tenant name (matched on `tenantFriendlyName` or `tenantDnsName`) in addition to numeric ID and GUID. Works across all cmdlets.
- **Pipeline support** — all cmdlets with `-TenantId` now support `ValueFromPipelineByPropertyName` with `[Alias('ClientTenantId')]` for proper piping (e.g. `Get-InforcerTenant | Get-InforcerUser`).

### Performance

- Switched `Invoke-InforcerApiRequest` from `Invoke-WebRequest` + `ConvertFrom-Json` to `Invoke-RestMethod` for faster API calls across all cmdlets.
- `Get-InforcerTenant` fetches tenant list once and reuses for both name/GUID resolution and output (no duplicate API call).
- `Get-InforcerTenant` JsonObject path filters PSObjects before JSON conversion (no serialize/deserialize round-trip).
- `Resolve-InforcerTenantId` uses `TryParse` instead of regex for numeric and GUID detection.
- All cmdlets use `$null =` instead of `| Out-Null`; removed `ForEach-Object { $_ }` output no-ops.

### Fixes

- `Get-InforcerUser` ById path only emits `UserNotFound` on actual 404 (not on 401/403/500).
- `Get-InforcerUser` JsonObject output no longer includes duplicate PascalCase alias fields.
- `Invoke-InforcerApiRequest` validates response type — non-JSON responses (e.g. HTML from misconfigured BaseUrl) get a clear `NonJsonResponse` error instead of crashing.
- `Invoke-InforcerApiRequest` error responses include HTTP status code in `ErrorId` (e.g. `ApiRequestFailed_404`) for programmatic handling.
- Rate limit detection (HTTP 429 and quota/throttle messages) with friendly error.
- API key redaction uses compiled regex for better performance.

### Documentation

- Added Get-InforcerUser to README, CMDLET-REFERENCE, API-REFERENCE (endpoints + UserSummary/User/UserLicense schemas), and module directory tree.
- Updated all TenantId parameter descriptions to reflect tenant name support.
- Format.ps1xml ListControl views for all object types (Tenant, Baseline, Policy, AlignmentScore, AlignmentDetailPolicy, AuditEvent, UserSummary, User).

### Tests

- 54 consistency tests (was 17): covers all cmdlets, private helpers (Resolve-InforcerTenantId, Add-InforcerPropertyAliases, Filter-InforcerResponse, ConvertTo-InforcerArray), both ParameterSets for Get-InforcerUser, no-silent-failure, JsonObject output.

## [0.0.3] - 2026-03-06

### Features

- PowerShell Gallery–ready metadata.
- README Quick start: example for showing policy changes per tenant.


### Documentation

- README, CONTRIBUTING, and LICENSE wording aligned; CONTRIBUTING.

### Refactoring

- Clearer error messages when API returns forbidden or no data; safer examples in docs.

### Tests

- Help coverage check (Synopsis and Example per cmdlet); parameter binding tests.

## [0.0.2] - 2026-03-06

### Improvements

- Various documentation updates, and test improvements.
- Consistency and no-silent-failure behaviour for all Get-* cmdlets.
- Clearer API error handling and alignment score filtering.

## [0.0.1] - 2026-03-05

### Features

- Initial release of the InforcerCommunity PowerShell module.
- Cmdlets: Connect-Inforcer, Disconnect-Inforcer, Test-InforcerConnection, Get-InforcerTenant, Get-InforcerBaseline, Get-InforcerTenantPolicies, Get-InforcerAlignmentScore, Get-InforcerAuditEvent.
- Tab completion for audit event types (-EventType on Get-InforcerAuditEvent).
- Region support (uk, eu, us, anz) and custom BaseUrl.
- Output types: PowerShellObject and JsonObject (depth 100).

