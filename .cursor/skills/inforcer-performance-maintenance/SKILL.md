---
name: inforcer-performance-maintenance
description: How to keep the Inforcer PowerShell module efficient and avoid performance regressions. Use when reviewing code for redundant API calls, duplicate code, or inefficiencies.
---

# Inforcer Performance Maintenance

Use this skill when **reviewing or changing** the Inforcer PowerShell module for **performance**: avoiding redundant API calls, duplicate code, and inefficient patterns. The rules below encode learnings from past efficiency improvements (see FINDINGS.md and the module efficiency improvements plan).

## When to use

- Adding or changing code that calls the Inforcer API
- Refactoring cmdlets or private helpers
- Reviewing PRs for performance impact
- Investigating "slow" behavior or unnecessary network calls

## Anti-patterns to avoid

### 1. Redundant API calls

- **Single resource by ID:** When the API supports `GET /resource/{id}`, use it. Do not call `GET /resource` and filter client-side (e.g. Get-InforcerTenant -TenantId 142 should use `GET /beta/tenants/142`, not fetch all tenants).
- **Skip calls when data is already present:** If the caller already has tenant data (e.g. from a prior `/beta/tenants` call), pass it into helpers (e.g. `Resolve-InforcerTenantId -TenantData $allTenants`) so the helper does not call the API again.
- **Conditional tenant fetch:** Get-InforcerAlignmentScore Table format should only call `/beta/tenants` when needed (nested alignment format, or -TenantId, or -Tag). When the API returns flat alignment data and no filter is applied, do not call `/beta/tenants` (flat items already include tenantFriendlyName).

### 2. Duplicate code

- **Shared helpers:** Use private helpers instead of copying the same logic (e.g. `ConvertFrom-InforcerSecureString` for SecureString→plain text; `ConvertTo-InforcerArray` for normalizing to array; `FormatAlignmentScore` or similar for repeated formatting).
- **Event types:** Use `Get-InforcerAuditEventType` (which caches) for audit event type resolution; do not duplicate event-type parsing or inline API fetch in Get-InforcerAuditEvent.
- **Tenant predicate/filter:** Build once and reuse for both JsonObject and PowerShellObject branches instead of duplicating the same predicate logic.
- **PolicyName:** Set only in Add-InforcerPropertyAliases for ObjectType Policy; do not also set it in EnrichPolicyObject or other enrichment.

### 3. Inefficiencies

- **Lookups:** Use hashtable indexing (e.g. `$regionMap[$Region.ToLowerInvariant()]`) for region→base URL or ID→object lookups, not `Where-Object` over collections.
- **Disposable resources:** Ensure StreamReader and other disposables are disposed in a `finally` block so they are always closed on exception.
- **Sensitive data:** Do not log API keys or secrets to the host; use Write-Verbose so they appear only with -Verbose.

### 4. Edge cases and robustness

- **Filter-InforcerResponse (JsonObject):** Wrap `ConvertFrom-Json` in try/catch; handle invalid JSON with a clear error. When JSON parses to $null (e.g. input `"null"`), return `'null'` without invoking the filter script. When filtering arrays, skip null elements.

## Checklist when changing API-related code

- [ ] Am I fetching a single resource by ID? If yes, use the single-resource endpoint if the API supports it.
- [ ] Am I passing data the caller already has into a helper that would otherwise call the API again? If not, add a parameter (e.g. -TenantData) and use it.
- [ ] Am I calling /beta/tenants (or any list endpoint) when I could skip it (e.g. flat format and no filter)?
- [ ] Did I introduce duplicate logic that already exists in a private helper? If yes, call the helper.
- [ ] Am I using Where-Object for a single lookup? If yes, consider a hashtable or direct index.
- [ ] Are disposables (StreamReader, etc.) disposed in finally?
- [ ] After my change, did I run `scripts/Test-AllCmdlets.ps1` to verify behavior?

## Key files and references

| Topic | Location |
|-------|----------|
| Efficiency and robustness rules | `.cursor/skills/inforcer-unified-guardian/SKILL.md` (Efficiency and robustness rules) |
| What was fixed and how to test | `FINDINGS.md` (Module efficiency Phases 1–4 and others) |
| Consistency contract | `.cursor/agents/inforcer-unified-guardian.md` |
| Cmdlet verification script | `scripts/Test-AllCmdlets.ps1` |

## Workflow

1. **Before merging** code that touches API calls or shared logic: run the performance checklist above.
2. **Run verification:** `pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Test-AllCmdlets.ps1` from repo root to ensure all cmdlets still work.
3. **Document:** If you fixed a performance issue or added a new pattern, update FINDINGS.md with "What was done" and "How to test" so future changes do not reintroduce the anti-pattern.

## Related

- **Unified guardian (consistency + efficiency rules):** [.cursor/skills/inforcer-unified-guardian/SKILL.md](../inforcer-unified-guardian/SKILL.md)
- **Findings log:** [FINDINGS.md](../../FINDINGS.md)
