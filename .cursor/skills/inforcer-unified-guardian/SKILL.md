---
name: inforcer-unified-guardian
description: Keeps the Inforcer PowerShell module consistent. Use when changing Public cmdlets, parameters, output properties, or JSON output. Enforces the consistency contract for the script module. Use when working on the Inforcer PowerShell module, Public cmdlets, parameters, JSON output, consistency contract, or script module alignment.
---

# Inforcer Unified Guardian

Use this skill when changing **Public cmdlets**, **parameters**, **output properties**, or **JSON output** in the Inforcer PowerShell module. It enforces the consistency contract so the script module stays predictable and testable.

## When to use

- Adding or changing any Public cmdlet in `module/Public/*.ps1`
- Changing parameters (order, names, ValidateSet)
- Changing output property names or shapes (aliases, table format)
- Changing JSON serialization (-OutputType JsonObject, depth)
- Aligning behavior across the script module

## Consistency contract (summary)

- **Script module only:** The implementation lives in `module/`. No dotnet binary module.
- **Cmdlets:** Connect-Inforcer, Disconnect-Inforcer, Test-InforcerConnection, Get-InforcerTenant, Get-InforcerBaseline, Get-InforcerTenantPolicies, Get-InforcerAlignmentScore, Get-InforcerAuditEvent; Get-InforcerAuditEventType (Private, exported for tab completion).
- **Parameter order:** Format → TenantId → Tag (if any) → OutputType. Use `ValidateSet('Raw')` or `ValidateSet('Table','Raw')` for -Format; `ValidateSet('PowerShellObject','JsonObject')` for -OutputType.
- **Property names:** Use PascalCase aliases from Add-InforcerPropertyAliases (Tenant, Baseline, Policy, AlignmentScore, AuditEvent). Do not rename or remove API properties; only add aliases when OutputType is PowerShellObject.
- **JSON depth:** Always 100. Every `ConvertTo-Json` uses `-Depth 100`. No exceptions for -OutputType JsonObject.
- **API shapes — alignmentScores:** GET /beta/alignmentScores returns `{ "data": [ { "tenantId", "tenantFriendlyName", "score", "baselineGroupId", "baselineGroupName", "lastComparisonDateTime" }, ... ], "success", "message", "errors" }`. Treat `data` as a **flat** array (do not assume `clientTenantId` or `alignmentSummaries`). Invoke-InforcerApiRequest unwraps `response.data` when present. Get-InforcerAlignmentScore (Table) must detect flat format (first item has `tenantId` and `score`, no `alignmentSummaries`) and build **one row per item**; -TenantId/-Tag filter via `$tenantIds`. **Baseline owner:** When -TenantId is a baseline owner (not scored itself), also include tenants aligned TO that baseline (via `alignmentSummaries.alignedBaselineTenantId` from /beta/tenants). If this is wrong, Get-InforcerAlignmentScore returns no output — see FINDINGS.md.
- **API shapes — other endpoints:** Responses like `{ "data": [ ... ] }` or `{ "data": ..., "success": true }`. Always unwrap `.data` in Invoke-InforcerApiRequest when present.

## Efficiency and robustness rules (avoid reintroducing)

- **Tenant API:** When a single tenant is needed by ID, use `GET /beta/tenants/{id}` (e.g. Get-InforcerTenant -TenantId &lt;numeric&gt; or after resolving GUID via Resolve-InforcerTenantId). Do not fetch all tenants and filter client-side when the API supports a single-tenant endpoint.
- **Skip /beta/tenants when not needed:** Get-InforcerAlignmentScore Table format should only call `/beta/tenants` when required: nested alignment format, or -TenantId, or -Tag. When the API returns flat alignment data and no filter is applied, do not call `/beta/tenants` (flat items already include tenantFriendlyName).
- **Pre-fetched tenant data:** Resolve-InforcerTenantId accepts optional `-TenantData` (array of tenant objects). When the caller already has tenant data (e.g. from a prior `/beta/tenants` call), pass it so Resolve-InforcerTenantId does not call the API again for GUID resolution.
- **Region lookup:** Use hashtable indexing (e.g. `$regionMap[$Region.ToLowerInvariant()]`) for region→base URL lookup, not `Where-Object` on keys.
- **SecureString to plain text:** Use the private helper `ConvertFrom-InforcerSecureString`; do not duplicate the BSTR marshal pattern in multiple cmdlets.
- **Event types:** Use Get-InforcerAuditEventType (which caches) for audit event type resolution; do not duplicate event-type parsing or inline API fetch in Get-InforcerAuditEvent.
- **PolicyName:** Set only in Add-InforcerPropertyAliases for ObjectType Policy; do not also set it in EnrichPolicyObject or other enrichment.
- **Filter-InforcerResponse (JsonObject):** Wrap `ConvertFrom-Json` in try/catch and handle invalid JSON with a clear error. When JSON parses to $null (e.g. input `"null"`), return `'null'` without invoking the filter script. When filtering arrays, skip null elements (do not pass $null to the filter script).
- **StreamReader / disposable resources:** In Invoke-InforcerApiRequest, ensure StreamReader is disposed in a finally block so it is always closed on exception.
- **Sensitive data:** Do not log API key or secret details to the host; use Write-Verbose so they appear only with -Verbose.
- **JSON depth:** All ConvertTo-Json in the module use -Depth 100; document this in comment-based help for every cmdlet that supports -OutputType JsonObject.

## Workflow

1. **Update the contract** in this skill or in `.cursor/agents/inforcer-unified-guardian.md` if you add a cmdlet, parameter, or object type.
2. **Change the script** in `module/`: Public/*.ps1 for cmdlets; Private/*.ps1 for helpers (Invoke-InforcerApiRequest, Add-InforcerPropertyAliases, Resolve-InforcerTenantId, Get-InforcerBaseUrl, etc.).
3. **Run consistency checklist:** parameter order, -Format/-OutputType present, property names match standard table, JSON depth 100, FunctionsToExport in Inforcer.psd1 includes new/updated cmdlet, comment-based help complete. If you changed Get-InforcerAlignmentScore or Invoke-InforcerApiRequest, verify alignmentScores still uses the flat API shape (see API shapes above; FINDINGS.md has the test).
4. **After applying a correction:** Update [FINDINGS.md](../../FINDINGS.md) at repo root: set "What was done to solve it" and keep "How to test" accurate. This keeps the skill self-learning.
5. **End-of-change verification:** Run all public cmdlets to confirm they still work as intended. See "End-of-change verification" below. Do this yourself; do not skip verification.

## End-of-change verification

At the end of any change that touches cmdlets or private helpers, verify the module still works:

1. **Load the module** from the repo (e.g. `Import-Module .\module\Inforcer.psd1 -Force` from repo root).
2. **Run each public cmdlet** and confirm expected behavior:
   - **Disconnect-Inforcer** — runs without error (e.g. "No active session to disconnect" when not connected).
   - **Test-InforcerConnection** — fails with a clear message when not connected; when connected, succeeds (use `-Verbose` to avoid logging secrets to host).
   - **Connect-Inforcer** — requires real credentials; if you cannot connect, at least ensure the function loads and parameters validate.
   - **Get-InforcerTenant** — when not connected: clear error. When connected: returns tenant list or single tenant with -TenantId (numeric or GUID).
   - **Get-InforcerBaseline** — when not connected: error. When connected: returns baselines.
   - **Get-InforcerTenantPolicies** — when not connected: error. When connected: requires -TenantId; returns policies.
   - **Get-InforcerAlignmentScore** — when not connected: error. When connected: Table (default) and Raw work; -TenantId and -Tag filter; -OutputType JsonObject returns JSON.
   - **Get-InforcerAuditEvent** — when not connected: error. When connected: returns events (optional -EventType, -StartDate, -EndDate).
3. **Sanity checks:** Get-Help for each cmdlet shows help; no syntax errors when invoking with `-?` or minimal parameters.

If any cmdlet errors unexpectedly or produces wrong output, fix the regression before considering the change done.

## Key files

| Purpose | Path |
|--------|------|
| Public cmdlets | `module/Public/*.ps1` |
| Property aliases | `module/Private/Add-InforcerPropertyAliases.ps1` |
| API requests | `module/Private/Invoke-InforcerApiRequest.ps1` |
| Session / base URL | `module/Private/Test-InforcerSession.ps1`, `module/Private/Get-InforcerBaseUrl.ps1` |
| Findings (self-learning) | `FINDINGS.md` (repo root) |
| Full contract and checklist | `.cursor/agents/inforcer-unified-guardian.md` |

## Self-learning

When you fix a bug or implement a finding from FINDINGS.md:

1. Implement the fix in the script module.
2. In FINDINGS.md, replace "(Pending)" in "What was done to solve it" with a short description.
3. Ensure "How to test" is accurate so future runs can verify the fix.

This way the skill and FINDINGS.md stay in sync and the agent avoids repeating the same mistakes.

## Additional resources

- Full consistency contract, cmdlet table, and checklist: [.cursor/agents/inforcer-unified-guardian.md](../../.cursor/agents/inforcer-unified-guardian.md)
- Tracked findings and test steps: [FINDINGS.md](../../FINDINGS.md)
