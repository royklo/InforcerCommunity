# Inforcer Tenant Documentation Cmdlet

## What This Is

A PowerShell cmdlet (`Export-InforcerDocumentation`) for the InforcerCommunity module that generates comprehensive, human-readable documentation of an entire M365 tenant's configuration as managed through the Inforcer API. It pulls data from existing cmdlets (Get-InforcerBaseline, Get-InforcerTenant, Get-InforcerTenantPolicies), resolves Intune Settings Catalog settingDefinitionIDs to friendly names using the IntuneSettingsCatalogViewer dataset, and outputs in multiple formats (HTML, Markdown, JSON, CSV). The HTML output features a modern, collapsible table of contents with products and subcategories, clearly displaying settings and their values.

## Core Value

IT admins can generate a complete, readable snapshot of their tenant's policy configuration across all M365 products in one command — no manual assembly required.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] Data collection from Get-InforcerBaseline, Get-InforcerTenant, Get-InforcerTenantPolicies via -OutputType JsonObject
- [ ] Intune Settings Catalog resolution: map settingDefinitionIDs to friendly names/descriptions using IntuneSettingsCatalogViewer/data/settings.json
- [ ] Product categorization: group policies by M365 product area (Intune, Conditional Access, etc.) with subcategories
- [ ] HTML output with modern styling, collapsible TOC (collapsed by default), product sections with subcategories, clear setting name/value display
- [ ] Markdown output with equivalent structure (TOC, product sections, settings tables)
- [ ] JSON output (structured, full-depth)
- [ ] CSV output (flattened settings with context columns)
- [ ] Per-policy sections showing: Basics (name, description, profile type, platform, dates, scope tags), Settings (name/value pairs with hierarchy), Assignments (groups, filters)
- [ ] Script/helper to run all data-collection cmdlets and capture raw JSON for development/testing
- [ ] Follow InforcerCommunity module conventions (parameter order, property aliases, session auth, JSON depth 100)

### Out of Scope

- DOCX output — deferred to v2 (requires external library)
- Real-time API calls for settings catalog resolution — use bundled/offline settings.json data
- Diff/comparison between tenants — separate feature
- Scheduling/automated documentation runs — user can wrap in their own automation

## Context

- **Existing module**: InforcerCommunity v0.1.0 with 10 public cmdlets, session-based auth via Connect-Inforcer
- **Data sources**: 3 cmdlets provide all needed data when using `-OutputType JsonObject`
- **Settings resolution**: IntuneSettingsCatalogViewer repo at `../IntuneSettingsCatalogViewer/data/settings.json` contains settingDefinitionID → friendly name mappings with hierarchy (rootDefinitionId, childIds, dependentOn)
- **Reference implementation**: Existing "inforcer Blueprint Library" MD/HTML export (9,200 lines) shows per-policy tables with Basics/Settings/Assignments sections — works but dated styling, no collapsible TOC, limited to Settings Catalog only
- **Module conventions**: Parameter order Format → TenantId → Tag → OutputType, PascalCase property aliases via Add-InforcerPropertyAliases, JSON depth 100, session-based auth

## Constraints

- **Tech stack**: PowerShell 7.0+, no external module dependencies for core formats (HTML/MD/JSON/CSV)
- **Module conventions**: Must follow InforcerCommunity consistency contract (parameter patterns, error handling, type names)
- **Settings data**: IntuneSettingsCatalogViewer settings.json is the lookup source — must handle missing/unknown settingDefinitionIDs gracefully
- **Output quality**: HTML must be modern (not the table-heavy 2026 reference style) with collapsible elements, clear visual hierarchy

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Use existing 3 cmdlets as data source | API already exposes everything via JsonObject output | — Pending |
| Bundle settings.json or reference external path | Need to decide: ship with module or reference sibling repo | — Pending |
| DOCX deferred to v2 | Requires external library dependency, not core value | ✓ Good |
| No new Get-* cmdlets needed | Existing cmdlets cover all M365 product data | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd:transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-04-01 after initialization*
