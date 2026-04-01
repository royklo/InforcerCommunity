# Phase 1: Data Pipeline and Normalization - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-01
**Phase:** 01-data-pipeline-and-normalization
**Areas discussed:** Settings.json path, Policy categorization, Data collection script, DocModel shape

---

## Settings.json Path Strategy

| Option | Description | Selected |
|--------|-------------|----------|
| -SettingsCatalogPath param | User provides path explicitly. Auto-discover sibling repo as default | |
| Bundle a copy | Ship a copy of settings.json inside the module's data/ folder | ✓ |
| Module-local data/ | Store in module's data/ folder, user runs Update cmdlet to download | |

**User's choice:** Bundle a copy
**Notes:** User plans to automate nightly refresh from IntuneSettingsCatalogViewer repo in a future milestone. For v1, a static bundled copy is sufficient.

---

## Policy Categorization

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, API has fields | The JSON includes product/category classification fields | ✓ |
| Not sure | Need to check — generate data collection script first | |
| No, needs mapping | API doesn't classify — derive from policy type or name | |

**User's choice:** User provided JSON output directly for inspection
**Notes:** Real data confirmed `product`, `primaryGroup`, `secondaryGroup` fields on every policy. 8 products found: Entra, Intune, Defender, Exchange, SharePoint, Teams, M365 Admin Center, Purview. No custom mapping needed.

---

## Data Collection Script

**User's choice:** Script created at scripts/Collect-InforcerData.ps1
**Notes:** Fixed connection check issue (Test-InforcerConnection writes to host but doesn't return boolean). Script successfully collected 194 policies from tenant 142.

---

## DocModel Shape

**User's choice:** Claude's discretion — nested tree structure
**Notes:** Structure mirrors output hierarchy: TenantInfo → Products → Categories → Policies → (Basics, Settings, Assignments). Real data analysis confirmed 4 distinct policyData shapes that normalization must handle.

---

## Claude's Discretion

- Internal data structures and helper function signatures
- Performance optimization for settings.json parsing
- Error handling granularity

## Deferred Ideas

- Nightly automation to refresh settings.json from IntuneSettingsCatalogViewer repo
- Category breadcrumbs using categories.json
