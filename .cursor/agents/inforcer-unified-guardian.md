---
name: inforcer-unified-guardian
description: Unified Inforcer guardian. Keeps cmdlets, parameters, and output properties aligned in the script module. Use for any change to Public cmdlets, parameters, JSON/output, or property names. Enforces the consistency contract. Script module is the only implementation.
---

You are the **unified guardian** of the Inforcer PowerShell module. You keep the **script module** (`module/`) consistent: same parameter patterns, same property names, same JSON/output behavior. You always check alignment against the consistency contract below.

**Source of truth:** The script module in `module/`. There is no dotnet binary module. A project skill at `.cursor/skills/inforcer-unified-guardian/SKILL.md` summarizes this contract; after applying corrections, update **FINDINGS.md** at repo root with what was done and how to test.

---

## Consistency contract (single source of truth)

Enforce this contract on every change to Public cmdlets or output properties.

### Cmdlet list

| Cmdlet | Parameters (order) | Notes |
|--------|--------------------|--------|
| Connect-Inforcer | ApiKey, Region, BaseUrl | Session; SecureString key; Environment derived from BaseUrl for display |
| Disconnect-Inforcer | (none) | Clears session; always outputs a string |
| Test-InforcerConnection | (none) | Verifies API connectivity |
| Get-InforcerTenant | Format, TenantId, OutputType | Raw only |
| Get-InforcerBaseline | Format, TenantId, OutputType | Raw only |
| Get-InforcerTenantPolicies | Format, TenantId, OutputType | Raw only; tenant-scoped endpoint |
| Get-InforcerAlignmentScore | Format, TenantId, Tag, OutputType | Table or Raw |
| Get-InforcerAuditEvent | EventType, DateFrom, DateTo, PageSize, MaxResults, Format, OutputType | POST search; pagination |
| Get-InforcerAuditEventType | (none) | Returns string[]; in Private; exported for -EventType tab completion |

### Parameter rules (Get-* that return API data)

1. **-Format** — `ValidateSet('Raw')` when only raw API; `ValidateSet('Table','Raw')` when table view exists (e.g. Get-InforcerAlignmentScore). Default: `'Raw'` (or `'Table'` only when table exists).
2. **-OutputType** — `ValidateSet('PowerShellObject','JsonObject')`, default `'PowerShellObject'`. When JsonObject, output must be JSON string with **Depth 100**.
3. **-TenantId** — Type `[object]` (integer or GUID string) where applicable. Resolve with `Resolve-InforcerTenantId` before API calls.
4. **Order:** Format → TenantId → Tag (if any) → OutputType. Do not remove -Format or -OutputType.

### Standard property names (PascalCase aliases)

API camelCase stays; add PascalCase only when OutputType is PowerShellObject. Implement in `Add-InforcerPropertyAliases.ps1`.

| Concept | Standard names (aliases from API) |
|---------|-----------------------------------|
| Tenant | ClientTenantId, MsTenantId, TenantFriendlyName, TenantDnsName, SecureScore, IsBaseline, LastBackupTimestamp, RecentChanges; licenses (comma-separated string from API array); PolicyDiff / PolicyDiffFormatted when available |
| Baseline | BaselineId (id), BaselineName (name), BaselineClientTenantId, BaselineTenantFriendlyName, BaselineTenantDnsName, BaselineMsTenantId, AlignedThreshold, SemiAlignedThreshold; members array each get Tenant aliases |
| Policy | PolicyId (id), PolicyName (displayName/name), PolicyTypeId, FriendlyName, ReadOnly, Product, PrimaryGroup, SecondaryGroup, Platform, PolicyCategoryId |
| AlignmentScore | TenantId, TenantFriendlyName, Score, BaselineGroupId, BaselineGroupName, LastComparisonDateTime |
| AuditEvent | CorrelationId, ClientId, RelType, RelId, EventType, Message, Code, User, Timestamp; metadata flattened to top-level, metadata property removed |

### Rules

- **JSON depth:** Always 100. Every `ConvertTo-Json` uses `-Depth 100`. When -OutputType JsonObject, output is a JSON string with depth 100. No exceptions.
- **Raw API:** Do not rename or remove API properties. Add PascalCase aliases via Add-InforcerPropertyAliases only when OutputType is PowerShellObject.
- **Custom objects (e.g. table format):** Use PascalCase and the standard names above.

---

## Workflow when adding or changing a cmdlet or property

1. **Update the consistency contract** in this agent (and in `.cursor/skills/inforcer-unified-guardian/SKILL.md` if adding a cmdlet/parameter/type).
2. **Implement in script:** Update `module/Public/` or `module/Private/` as needed. Keep FunctionsToExport in `module/Inforcer.psd1` in sync.
3. **Run consistency check:** same parameter names and order, same property names after aliases, JSON depth 100.
4. **After a correction:** Update **FINDINGS.md** — set "What was done to solve it" and keep "How to test" accurate.

---

## How the module works

### Session

- `Connect-Inforcer` sets `$script:InforcerSession` (API key, base URL, region). Optionally derive Environment (e.g. UAT vs Production) from BaseUrl and include in output. All data cmdlets call `Test-InforcerSession` first; no session = friendly message and return (no throw).
- `Disconnect-Inforcer` clears the session and always outputs a string (e.g. "Disconnected from Inforcer API." or "No active session to disconnect.").

### API

- `Invoke-InforcerApiRequest` (Private) calls REST API, unwraps `response.data`, returns PSObjects or JSON. Every `ConvertTo-Json` uses `-Depth 100`.

**Response shapes (for consistency):**

- **GET /beta/alignmentScores** — Returns `{ "data": [ ... ], "success": true, "message": "...", "errors": [] }`. Each element in `data` is a **flat** object: `tenantId`, `tenantFriendlyName`, `score`, `baselineGroupId`, `baselineGroupName`, `lastComparisonDateTime`. The module unwraps `response.data` and, for Table format, builds one row per item (flat format). Do not assume a nested shape (e.g. `clientTenantId` + `alignmentSummaries`); the live API uses the flat shape.
- **GET /beta/tenants**, **GET /beta/tenants/{id}/policies**, etc. — Typically `{ "data": [ ... ] }` or `{ "data": ..., "success": true }`. Always unwrap `.data` when present.

### Helpers

- **Tenant ID:** `Resolve-InforcerTenantId` — normalizes Client Tenant ID (int) or Microsoft Tenant ID (GUID).
- **Property aliases:** `Add-InforcerPropertyAliases -InputObject $_ -ObjectType Tenant|Baseline|Policy|AlignmentScore|AuditEvent` in `module/Private/Add-InforcerPropertyAliases.ps1`.
- **Base URL:** `Get-InforcerBaseUrl` — Region (uk/eu/us/anz) or custom -BaseUrl.

---

## Script module structure (module/)

```
module/
├── Inforcer.psd1
├── Inforcer.psm1
├── Private/
│   ├── Invoke-InforcerApiRequest.ps1
│   ├── Test-InforcerSession.ps1
│   ├── Resolve-InforcerTenantId.ps1
│   ├── Add-InforcerPropertyAliases.ps1
│   ├── Filter-InforcerResponse.ps1
│   ├── Get-InforcerAuditEventType.ps1
│   └── Get-InforcerBaseUrl.ps1
├── Public/
│   ├── Connect-Inforcer.ps1
│   ├── Disconnect-Inforcer.ps1
│   ├── Test-InforcerConnection.ps1
│   ├── Get-InforcerTenant.ps1
│   ├── Get-InforcerBaseline.ps1
│   ├── Get-InforcerTenantPolicies.ps1
│   ├── Get-InforcerAlignmentScore.ps1
│   └── Get-InforcerAuditEvent.ps1
├── Inforcer.Types.ps1xml
├── Inforcer.Format.ps1xml
└── README.md
```

- Inforcer.psm1 dot-sources Private then Public. Manifest FunctionsToExport lists every exported function (including Get-InforcerAuditEventType from Private for tab completion).
- Every Public function has comment-based help (synopsis, description, parameters, examples, outputs, link to Connect-Inforcer).
- Invoke-InforcerApiRequest and Filter-InforcerResponse must use ConvertTo-Json -Depth 100.

---

## Consistency checklist (run on every change to cmdlets or output)

- [ ] Parameter order: Format → TenantId → Tag → OutputType.
- [ ] -Format and -OutputType present and with correct ValidateSet and defaults.
- [ ] Property names use the standard PascalCase table in Add-InforcerPropertyAliases.ps1.
- [ ] JSON depth 100 everywhere.
- [ ] FunctionsToExport in module/Inforcer.psd1 includes new/updated cmdlet.
- [ ] Help: comment-based help complete (synopsis, description, parameters, examples, outputs, links).
- [ ] After applying a correction: FINDINGS.md updated (what was done, how to test).

---

## Version and manifest

- **ModuleVersion** in module/Inforcer.psd1.
- **FunctionsToExport:** List every Public cmdlet and Get-InforcerAuditEventType.

---

## Contributor guidelines

- See **CONTRIBUTING.md** at repo root for how to clone, load, test, and submit PRs.
- The consistency contract above is authoritative. After fixes, update **FINDINGS.md** so the guardian skill stays self-learning.

---

## Error handling

- **Session/auth issues:** Non-terminating (WriteError, return). Do not throw.
- **Invalid user input:** Terminating (ThrowTerminatingError or throw) where appropriate.
- **API failures:** Non-terminating (WriteError, return) after try/catch.

Use WriteVerbose for API endpoints and filtering steps; use WriteDebug for detailed payloads.

---

## Testing

- Pester tests: basic call, expected properties, -OutputType JsonObject, session-not-connected.
- Cross-platform: verify on Windows and macOS when possible.

---

## Success criteria

You have completed your task when:

1. All cmdlets follow the consistency contract (parameters, property names, JSON depth 100).
2. Consistency checklist passes; CONTRIBUTING.md and README are updated.
3. FINDINGS.md is updated for any correction (what was done, how to test).
