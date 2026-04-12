---
name: inforcer-unified-guardian
description: >
  MANDATORY for ANY change to the InforcerCommunity PowerShell module. Enforces the consistency contract
  for Public cmdlets, parameters, output properties, JSON output, and script module alignment.
  Use when working on cmdlets, parameters, JSON depth, property aliases, API shapes, or module
  structure. This is the BASELINE skill — it runs for every code change in InforcerCommunity.
---

# Inforcer Unified Guardian

> **Authority:** This skill is the baseline for every code change in the InforcerCommunity module.
> When chaining with other skills, this skill runs **first**. Typical chain:
> 1. **inforcer-unified-guardian** (this skill) — enforce consistency
> 2. **inforcer-performance-maintenance** — verify no performance regressions
> 3. **inforcer-docs-maintenance** — update docs if cmdlet/parameter/output changed
>
> For docs-only changes, skip this skill.

## Triggers

Activate when the user mentions or the task involves:
- Changing, adding, or removing a Public cmdlet
- Adding or changing parameters (order, names, ValidateSet)
- Changing output property names, shapes, or aliases
- Changing JSON serialization (OutputType JsonObject, depth)
- Aligning behavior across the script module
- "Consistency check", "parameter order", "property alignment", "JSON depth"

## Consistency Contract

### Architecture

- **Script module only.** Implementation lives in `module/`. No dotnet binary module.
- Session-based auth: `Connect-Inforcer` sets `$script:InforcerSession`. All data cmdlets call `Test-InforcerSession` first; no session → friendly message and return (no throw).

### Cmdlet List

| Cmdlet | Parameters (order) | Notes |
|--------|--------------------|-------|
| Connect-Inforcer | ApiKey, Region, BaseUrl | Session; SecureString key; validates via GET /beta/baselines |
| Disconnect-Inforcer | (none) | Clears session; always outputs a string |
| Test-InforcerConnection | (none) | Verifies API connectivity |
| Get-InforcerTenant | Format, TenantId, OutputType | Raw only |
| Get-InforcerBaseline | Format, TenantId, OutputType | Raw only |
| Get-InforcerTenantPolicies | Format, TenantId, OutputType | Raw only; tenant-scoped |
| Get-InforcerAlignmentDetails | Format, TenantId, BaselineId, Tag, OutputType | Table or Raw; -BaselineId alone → pick first member (baseline policies are same for all members); -TenantId + -BaselineId → single tenant details; without -BaselineId → alignment scores summary |
| Get-InforcerAuditEvent | EventType, DateFrom, DateTo, PageSize, MaxResults, Format, OutputType | POST search; pagination |
| Get-InforcerSupportedEventType | (none) | Returns string[]; Public; used for tab completion |
| Get-InforcerUser | Format, TenantId, Search, MaxResults, UserId, OutputType | ParameterSets: List (default), ById; auto-pagination; streaming output |
| Export-InforcerTenantDocumentation | Format, TenantId, OutputPath, SettingsCatalogPath, FetchGraphData, Baseline, Tag | Utility cmdlet; outputs FileInfo[]; Format accepts Html/Markdown/Excel (array); uses DocModel pipeline |
| Compare-InforcerEnvironments | SourceTenantId, DestinationTenantId, SourceSession, DestinationSession, IncludingAssignments, SettingsCatalogPath, OutputPath | Utility cmdlet; outputs FileInfo; uses DocModel pipeline with -ComparisonMode; session swapping for cross-account |

### Parameter Rules

1. **-Format** — `ValidateSet('Raw')` when only raw; `ValidateSet('Table','Raw')` when table exists. Default: `'Raw'` (or `'Table'` when table exists).
2. **-OutputType** — `ValidateSet('PowerShellObject','JsonObject')`, default `'PowerShellObject'`. JsonObject → JSON string with **Depth 100**.
3. **-TenantId** — Type `[object]` with `[Alias('ClientTenantId')]` (numeric ID, GUID, or tenant name). Use `ValueFromPipelineByPropertyName` only (not `ValueFromPipeline`). Resolve with `Resolve-InforcerTenantId`. Pass `-TenantData` when caller already has tenant list to avoid duplicate API calls.
4. **Order:** Format → TenantId → BaselineId (if any) → Tag (if any) → OutputType. Never remove -Format or -OutputType.
5. **Utility cmdlets** (`Export-*`, `Compare-*`) output `[System.IO.FileInfo]` instead of PSObjects. They don't follow the Format/TenantId/OutputType pattern — their -Format parameter controls output file format (Html/Markdown/Excel), not data format. No PSTypeName or Format.ps1xml needed.

### Standard Property Names (PascalCase Aliases)

API camelCase stays; PascalCase added only when OutputType is PowerShellObject via `Add-InforcerPropertyAliases`. **Skip aliases for JsonObject output** — ConvertTo-Json serializes both originals and aliases, causing duplicate fields.

For full property tables per object type (Tenant, Baseline, Policy, AlignmentScore, AuditEvent), see [references/contract-details.md](references/contract-details.md).

### API Shapes

- **GET /beta/alignmentScores** — `{ "data": [...], "success", "message", "errors" }`. Each element is **flat**: `tenantId`, `tenantFriendlyName`, `score`, `baselineGroupId`, `baselineGroupName`, `lastComparisonDateTime`. Do not assume nested format.
- **GET /beta/tenants** — Always use the list endpoint. Do **not** use `GET /beta/tenants/{id}` (it can return the full list with duplicates). Filter client-side with Where-Object.
- **GET /beta/tenants/{id}/alignmentDetails?customBaselineId={guid}** — `{ "data": { "metrics": {...}, "completedAt": "...", "alignment": {...} } }`. Returns detailed per-policy alignment including metrics, matched policies, deviations, diffs, variables, and tags. Alignment arrays: `matchedPolicies`, `matchedWithAcceptedDeviations`, `deviatedUnaccepted`, `missingFromSubjectUnaccepted`, `additionalInSubjectUnaccepted`. BaselineId can be resolved from friendly name via `Resolve-InforcerBaselineId`. When -TenantId is omitted, member tenants are discovered from `GET /beta/baselines` members array.
- **GET /beta/tenants/{id}/users** — `{ "data": [...], "continuationToken": "...", "totalCount": 33, "success": true }`. Pagination metadata is at **response root** (sibling of `.data`), not inside it. Use `-PreserveFullResponse` (not `-PreserveStructure`). Stream items to pipeline; only buffer for JsonObject.
- **GET /beta/tenants/{id}/users/{userId}** — `{ "data": {...}, "success": true }`. Single user detail with groups, roles, devices, risk, on-premises info.
- **Other endpoints** — `{ "data": [...] }` or `{ "data": ..., "success": true }`. Always unwrap `.data` in Invoke-InforcerApiRequest.

### PSTypeNames and Format.ps1xml

Every cmdlet output object must have a PSTypeName inserted so Format.ps1xml views control the default display. The Format.ps1xml hides noisy blob properties (policyDiff, tags, alignmentSummaries, policyData, members, items) from default output — they remain accessible via dot notation or `Select-Object *`.

| PSTypeName | Cmdlet | View |
|------------|--------|------|
| InforcerCommunity.Tenant | Get-InforcerTenant | ListControl: ClientTenantId, MsTenantId, TenantFriendlyName, TenantDnsName, licenses, SecureScore, IsBaseline, LastBackupTimestamp |
| InforcerCommunity.Baseline | Get-InforcerBaseline | ListControl: BaselineName, BaselineId, Owner, OwnerTenantId, Members (tenant names with IDs), AlignedThreshold, SemiAlignedThreshold, Mode |
| InforcerCommunity.Policy | Get-InforcerTenantPolicies | ListControl: PolicyName, Product, PrimaryGroup, SecondaryGroup, Platform, ReadOnly, Tags, PolicyData (compact JSON) |
| InforcerCommunity.AlignmentScore | Get-InforcerAlignmentDetails (Table) | ListControl: Tenant, TenantId, AlignmentScore, BaselineName, LastComparisonDateTime |
| InforcerCommunity.AlignmentScoreRaw | Get-InforcerAlignmentDetails (Raw) | No view (shows all properties) |
| InforcerCommunity.AlignmentDetailPolicy | Get-InforcerAlignmentDetails -BaselineId | ListControl: PolicyName, AlignmentStatus, Product, PrimaryGroup, SecondaryGroup, InforcerPolicyTypeName, Tags |
| InforcerCommunity.AuditEvent | Get-InforcerAuditEvent | ListControl: EventType, Code, User, Timestamp, Message, ClientIpv4, UserName, UserDisplayName |
| InforcerCommunity.UserSummary | Get-InforcerUser (List) | ListControl: DisplayName, UserPrincipalName, UserType, Department, AssignedLicenses, IsGlobalAdmin, IsMfaCapable |
| InforcerCommunity.User | Get-InforcerUser (ById) | ListControl: DisplayName, UserPrincipalName, UserType, Department, Mail, AccountEnabled, IsGlobalAdmin, IsCloudOnly, IsMfaRegistered, RiskLevel |

When adding a new cmdlet or changing output shape: add PSTypeName, add/update Format.ps1xml ListControl view, verify default output is clean.

**AlignmentDetails with -BaselineId:** Metrics summary is displayed via `Write-Host` (not pipeline), so it doesn't interfere with `| ft` or variable capture. Only per-policy rows hit the pipeline. Inaccessible baselines (e.g. shared baselines where user lacks access to baseline tenant) show a friendly `Write-Warning`. When `-BaselineId` is specified without `-TenantId`, only the first member tenant is queried (baseline policies are identical across all members — the alignment status may differ but the policy set is the same).

### Security (non-negotiable)

- **Never commit environment URLs.** DEV, UAT, staging, or sandbox base URLs (hostnames, full URLs, or domain names) must never appear in committed code, docs, snapshots, comments, examples, or FINDINGS. Use placeholders like `https://api-{region}.inforcer.com/api` in examples. Only production `.inforcer.com` URLs are allowed in committed files.
- **Never commit API keys or secrets.** Use GitHub Secrets or environment variables. Do not hardcode in source, workflow files, or documentation.
- **Snapshot files** (`docs/api-schema-snapshot.json`) must not contain `generatedFrom` or any field that reveals the environment URL.

### Rules (non-negotiable)

- **JSON depth:** Always 100. Every `ConvertTo-Json` uses `-Depth 100`. No exceptions.
- **Raw API:** Do not rename/remove API properties. Add PascalCase aliases only when OutputType is PowerShellObject.
- **Format.ps1xml:** Every output object must have a PSTypeName. **All views use ListControl** — no TableControl for default output. Users can pipe to `| ft` for tables. Default views must show only useful properties. Blob properties hidden from default but accessible.
- **Error handling:** Session/auth → non-terminating (WriteError, return). Invalid input → terminating. API failures → non-terminating. Rate limits (HTTP 429 or 403 with quota message) → "API rate limit: {message}". Error catch blocks must handle both PS5.1 (`[System.Net.WebException]`) and PS7 (`$_.ErrorDetails.Message`) — use generic `catch` block, not type-specific.
- **Suppress function output:** Always use `$null = Add-InforcerPropertyAliases ...` to prevent duplicate output.
- **AuditEvent metadata:** Keep metadata on the object (do not remove). Format.ps1xml controls default view. Flattened fields (ClientIpv4, UserName, UserDisplayName) are added as top-level properties. nameLookup key matching must use `user:username:*` and `user:displayName:*` patterns only (not broad regex).

## Efficiency Rules (avoid reintroducing)

> Full optimization rules and file-specific patterns: see `inforcer-performance-maintenance` skill and its `references/optimization-patterns.md`.

**API calls:**
- Single resource by ID: use single-resource endpoint when supported — **except** Get-InforcerTenant (always list + filter).
- Skip `/beta/tenants` when not needed (flat alignment data + no filter).
- Pass pre-fetched data via `-TenantData` to avoid redundant API calls.

**Memory & allocation:**
- Never `+=` on arrays in loops — use `[System.Collections.Generic.List[object]]`.
- Property replacement: set `.Value` directly, don't Remove+Add.
- Cache `PSObject.Properties[]` lookups when accessing same property multiple times.

**Lookups & iteration:**
- Hashtable indexing for lookups, not `Where-Object` on keys.
- Single-pass over collections — don't iterate same data in separate loops.
- `[int]::TryParse()` / `[guid]::TryParse()` over regex for type validation.

**Pipeline & output:**
- `[void]` or `$null =` instead of `| Out-Null`.
- `foreach` statement for in-memory collections; `ForEach-Object` only for pipeline streaming.

**Helpers (use, don't duplicate):**
- `ConvertFrom-InforcerSecureString` for BSTR pattern.
- `Get-InforcerSupportedEventType` (caches) for event types.
- `ConvertTo-InforcerArray` for array normalization.
- PolicyName set only in `Add-InforcerPropertyAliases` for ObjectType Policy.
- `ConvertTo-InforcerDocModel` for normalizing tenant policy data (DocModel pipeline). Never re-implement setting extraction.
- `ConvertTo-InforcerSettingRows` / `ConvertTo-FlatSettingRows` for setting extraction from policies.
- `Import-InforcerSettingsCatalog` loads settings.json + categories.json; `Resolve-InforcerSettingName` for settingDefinitionId → friendly name.
- `Compare-InforcerDocModels` for diffing two DocModels. Never build custom comparison logic outside this.

**Safety:**
- Dispose StreamReader / BSTR in `finally` block.
- Never log secrets to host; use Write-Verbose.
- Session validation: check `SecureString.Length`, not plaintext conversion.

## Workflow

1. **Update this contract** if adding a cmdlet, parameter, or object type.
2. **Change the script** in `module/`: Public/*.ps1 for cmdlets; Private/*.ps1 for helpers.
3. **Run consistency checklist:** parameter order, -Format/-OutputType present, property names match, JSON depth 100, FunctionsToExport in psd1, comment-based help complete.
4. **After a correction:** Update [FINDINGS.md](../../FINDINGS.md) — set "What was done" and keep "How to test" accurate.
5. **End-of-change verification:** Load the module and run all public cmdlets. See checklist below.

## End-of-Change Verification

1. `Import-Module .\module\InforcerCommunity.psd1 -Force`
2. Run each public cmdlet and confirm expected behavior (Disconnect, Test-InforcerConnection, Connect, Get-InforcerTenant, Get-InforcerBaseline, Get-InforcerTenantPolicies, Get-InforcerAlignmentDetails, Get-InforcerAuditEvent, Get-InforcerSupportedEventType, Get-InforcerUser, Export-InforcerTenantDocumentation, Compare-InforcerEnvironments).
3. `Get-Help` for each cmdlet shows help; no syntax errors with `-?`.

If any cmdlet errors unexpectedly, fix the regression before marking the change done.

## Consistency Checklist

- [ ] Parameter order: Format → TenantId → BaselineId → Tag → OutputType
- [ ] -Format and -OutputType present with correct ValidateSet and defaults
- [ ] Property names use standard PascalCase table in Add-InforcerPropertyAliases
- [ ] JSON depth 100 everywhere
- [ ] PSTypeName set on output objects; Format.ps1xml view defined for clean default display
- [ ] FunctionsToExport in InforcerCommunity.psd1 includes new/updated cmdlet
- [ ] Comment-based help complete (synopsis, description, parameters, examples, outputs, links)
- [ ] FINDINGS.md updated (what was done, how to test)
- [ ] No DEV/UAT/staging URLs or API keys in committed files (only production `.inforcer.com` allowed)

## Key Files

| Purpose | Path |
|---------|------|
| Public cmdlets | `module/Public/*.ps1` |
| Format views | `module/InforcerCommunity.Format.ps1xml` |
| Type extensions | `module/InforcerCommunity.Types.ps1xml` |
| Property aliases | `module/Private/Add-InforcerPropertyAliases.ps1` |
| API requests | `module/Private/Invoke-InforcerApiRequest.ps1` |
| Settings Catalog cache | `module/Private/Get-InforcerSettingsCatalogPath.ps1` (6-tier cache: explicit → fresh cache 24h → stale check → download from github.com/royklo/IntuneSettingsCatalogData → fallback → offline). Cache at `~/.inforcercommunity/data/`. |
| Settings Catalog loader | `module/Private/Import-InforcerSettingsCatalog.ps1` (delegates to `Get-InforcerSettingsCatalogPath` for resolution) |
| Session / base URL | `module/Private/Test-InforcerSession.ps1`, `module/Private/Get-InforcerBaseUrl.ps1` |
| Findings (self-learning) | `.claude/FINDINGS.md` |
| Detailed contract tables | `.claude/skills/inforcer-unified-guardian/references/contract-details.md` |
| API schema drift detection | `scripts/Test-ApiSchemaChanges.ps1` (nightly workflow runs against UAT) |
| API schema snapshot | `docs/api-schema-snapshot.json` (generated from UAT — must not contain environment URLs) |

## Self-Learning

When fixing a bug or implementing a finding from FINDINGS.md:
1. Implement the fix in the script module.
2. In FINDINGS.md, replace "(Pending)" with a short description.
3. Ensure "How to test" is accurate so future sessions can verify.
