# Project Research Summary

**Project:** Export-InforcerDocumentation
**Domain:** PowerShell M365/Intune tenant documentation export cmdlet
**Researched:** 2026-04-01
**Confidence:** HIGH

## Executive Summary

`Export-InforcerDocumentation` is a PowerShell 7 cmdlet that exports Inforcer-managed tenant configuration to HTML, Markdown, JSON, and CSV — with no external module dependencies. The established pattern in this space (M365Documentation, IntuneManagement, IntuneCD) is a collect-normalize-render pipeline. Research confirms a working reference implementation already exists in `docs-feature/` and the primary task is lifting those battle-tested patterns into the module with proper structure, caching, and consistency-contract compliance.

The recommended approach is a four-stage linear pipeline — Collect, Normalize, Render, Emit — where the public cmdlet orchestrates private helpers and renderers are pure functions. All data fetching happens once in Stage 1 using existing public cmdlets with `-OutputType JsonObject`. The 17,785-entry settings catalog is resolved via a `$script:`-scoped hashtable loaded once per session. HTML output uses `[System.Text.StringBuilder]` with embedded CSS and native `<details>/<summary>` elements — no JavaScript frameworks, no CDN, no external files.

The most significant risks are performance-related (string concatenation in HTML loops, and re-loading the 62.5 MB `settings.json` per invocation), data-correctness-related (missing `@odata.type` handlers for 4 of 5 settingInstance types silently drop settings from output), and packaging-related (bundling `settings.json` makes the module 62.5 MB — unacceptable for a Gallery module). All three risks have clear, documented mitigations from the reference implementation.

## Key Findings

### Recommended Stack

Everything required is built into PowerShell 7.0+ and .NET 8. No external modules are permitted or needed. The critical technique choices are: `[System.Text.StringBuilder]` for all HTML assembly (55x faster than `+=` at scale), `ConvertFrom-Json -AsHashtable` for loading the settings catalog with O(1) lookup, native `<details>/<summary>` HTML5 elements for collapsible UI (no JavaScript, no CDN), and `ConvertTo-Json -Depth 100` for JSON output (the existing module convention). CSV output requires explicit flat `[PSCustomObject]` projection before piping to `Export-Csv` — raw policy objects with nested arrays serialize as `System.Object[]`.

**Core technologies:**
- `[System.Text.StringBuilder]`: HTML assembly — eliminates O(n²) string allocation in policy/setting loops
- `ConvertFrom-Json -AsHashtable` + re-key by `id`: settings catalog lookup — O(1) vs O(n) per-policy iteration
- `<details>/<summary>` HTML5: collapsible TOC and per-policy sections — no JavaScript dependency, offline-safe
- `ConvertTo-Html -Fragment`: individual flat settings tables inside policy sections — not for page skeleton
- `ConvertTo-Json -Depth 100`: JSON output — module convention, max supported depth
- `Export-Csv -NoTypeInformation -Encoding UTF8`: CSV output with explicit flat row projection
- Here-strings (`@' '@` / `@" "`): CSS embedding and Markdown template composition

### Expected Features

The ecosystem survey confirms competing tools (M365Documentation, IntuneManagement, IntuneCD) all share a common table-stakes set, and the `docs-feature` reference implementation has already raised the bar with differentiators none of them offer. The MVP scope is well-defined: four formats (HTML, Markdown, JSON, CSV) with settings catalog name resolution, product/category grouping, assignments display, and scope tag badges. DOCX and PDF are explicitly deferred — both require either external dependencies or fragile custom implementations.

**Must have (table stakes):**
- Per-policy setting name + value with friendly-name resolution — raw `settingDefinitionId` GUIDs are unacceptable
- Product/category grouping (Product → PrimaryGroup hierarchy) — ungrouped output is unusable at scale
- Policy metadata: name, description, platform, created/modified dates
- Assignments section per policy — required for audits ("who does this apply to?")
- Scope tags display — required for MSP multi-tenant environments
- HTML output (self-contained single file, no CDN)
- Markdown output (GFM-compatible, anchor TOC)
- JSON output (depth 100, structured not raw passthrough)
- CSV output (flattened rows: Product, Category, PolicyName, SettingName, Value)
- Generation timestamp and tenant name in all outputs
- Graceful handling of unknown settingDefinitionIds (fallback to raw ID, no error)

**Should have (competitive differentiators):**
- Collapsible HTML with product tabs — key UX gap vs all competing tools
- Dark/light mode toggle in HTML — CSS custom properties, trivial once CSS is structured
- "Configured" vs "not configured" distinction per setting row
- Per-policy setting count badge in collapsed header
- Choice option resolution — shows "Require MFA" not `block_mfa_true_0`
- Category breadcrumb (requires `categories.json`)
- Multi-format in a single command invocation (`-Format Html,Csv,Markdown`)

**Defer (v2+):**
- DOCX — requires PSWriteOffice (external dep) or fragile custom Open XML generator
- PDF — headless browser dependency, unreliable in CI and headless environments
- Group name resolution via Graph API — requires second auth context
- Tag filter JS in HTML — low effort but adds JavaScript; add after core HTML is stable

### Architecture Approach

The public cmdlet (`Export-InforcerDocumentation`) is a pure orchestrator — it validates parameters, guards the session, reports progress, and wires the pipeline. No rendering or transformation logic lives in the public file. Eight private helpers cover: data collection, settings catalog import, setting name resolution, model normalization, HTML rendering, Markdown rendering, and CSV flattening. JSON output requires no helper — inline `ConvertTo-Json -Depth 100` in the orchestrator. The key invariant is that renderers are pure functions: they receive `$DocModel` and return a string, with no API calls, no file I/O, and no state mutation.

**Major components:**
1. `Get-InforcerDocData` — calls existing public cmdlets with `-OutputType JsonObject`; returns raw data bundle
2. `Import-InforcerSettingsCatalog` / `Resolve-InforcerSettingName` — loads settings.json once to `$script:` scope; O(1) lookup by `settingDefinitionId`
3. `ConvertTo-InforcerDocModel` — deserializes raw JSON, applies product/group categorization, resolves all setting names; format-agnostic output
4. `ConvertTo-InforcerHtmlDoc` / `ConvertTo-InforcerMarkdownDoc` / `ConvertTo-InforcerCsvRows` — pure renderers; each consumes `$DocModel`, returns string or object array
5. `Export-InforcerDocumentation` (public) — orchestrates stages; writes to `-OutputPath` or returns to pipeline

### Critical Pitfalls

1. **String concatenation for HTML (`$html +=` in loops)** — use `[System.Text.StringBuilder]` exclusively; measured 55x speedup; the reference implementation already does this correctly
2. **Loading settings.json per invocation** — cache in `$script:InforcerSettingsCatalog` (mirrors `$script:InforcerSession` pattern); measured cold-start is ~2 seconds; second call should be ~0ms
3. **Missing `@odata.type` handlers (4 of 5 settingInstance types)** — `ChoiceSettingInstance` is 91% but `SimpleSettingCollectionInstance`, `SimpleSettingInstance`, and `GroupSettingCollectionInstance` exist in real data; missing handlers cause silent data loss
4. **Bundling settings.json in the module** — the file is 62.5 MB; use `-SettingsCatalogPath` parameter with sibling-repo auto-discovery and graceful degradation; never bundle
5. **Null `displayName` on Intune policies** — 96% of real-data policies have null `platform`; many have null `displayName`; implement fallback chain: `displayName → name → friendlyName → "Policy $id"`

## Implications for Roadmap

Based on research, the dependency graph is clear: settings catalog infrastructure must precede normalization, which must precede rendering. The reference implementation in `docs-feature/` validates this order and de-risks implementation significantly.

### Phase 1: Foundation — Data Pipeline and Normalization

**Rationale:** All rendering depends on a correct `$DocModel`. The two most critical correctness pitfalls (null displayName, ordered grouping) live here. This phase has no rendering risk — it is pure data transformation, fully testable with Pester fixtures from `docs-feature/out/all-settings.json`.

**Delivers:** `Get-InforcerDocData`, `Import-InforcerSettingsCatalog`, `Resolve-InforcerSettingName`, `ConvertTo-InforcerDocModel` — a validated `$DocModel` from any tenant

**Addresses features:** product/category grouping, policy metadata, assignment data, scope tags, friendly-name resolution

**Avoids:** Pitfall 5 (null displayName), Pitfall 2 (settings.json re-load), Pitfall 14 (non-deterministic ordering), Pitfall 13 (null platform), Pitfall 4 (missing settingInstance type handlers)

### Phase 2: Output Formats — HTML, Markdown, JSON, CSV

**Rationale:** With a validated `$DocModel` from Phase 1, all four renderers can be built and tested independently. Renderers are pure functions — no API access needed. The reference implementation provides working HTML and Markdown renderers to port. Critical HTML pitfalls (string concat, HTML encoding) must be addressed here.

**Delivers:** `ConvertTo-InforcerHtmlDoc`, `ConvertTo-InforcerMarkdownDoc`, `ConvertTo-InforcerCsvRows`, inline JSON output — all four formats working

**Uses:** `[System.Text.StringBuilder]`, `<details>/<summary>`, embedded CSS, `[System.Web.HttpUtility]::HtmlEncode`, GFM table escaping, `ConvertTo-Json -Depth 100`, flat `[PSCustomObject]` CSV rows

**Implements:** Stage 3 (Rendering) of the Collect → Normalize → Render → Emit pipeline

**Avoids:** Pitfall 1 (string concat), Pitfall 6 (HTML special chars), Pitfall 7 (UTF-8 BOM), Pitfall 8 (Markdown pipe chars), Pitfall 9 (JSON depth truncation), Pitfall 12 (CSV embedded newlines), Pitfall 15 (HTML anchor collisions)

### Phase 3: Public Cmdlet, Module Integration, and Packaging

**Rationale:** The public cmdlet is the last piece — it wires Phase 1 and Phase 2 together and must comply with the InforcerCommunity consistency contract (parameter order, `Add-InforcerPropertyAliases`, session guard). Module integration (`.psd1` update, session cleanup) and packaging decisions (settings.json path strategy) belong here.

**Delivers:** `Export-InforcerDocumentation` public cmdlet; `.psd1` updated; `Disconnect-Inforcer` clears `$script:InforcerSettingsCatalog`; `-SettingsCatalogPath` with sibling-repo auto-discovery

**Avoids:** Pitfall 3 (settings.json bundling — 62.5 MB), Pitfall 7 (UTF-8 BOM at file write), consistency-contract violations

### Phase Ordering Rationale

- Phase 1 before Phase 2: renderers are pure consumers of `$DocModel`; building them before the model is validated produces untestable code
- Settings catalog infrastructure (Phase 1) before model normalization (also Phase 1): `ConvertTo-InforcerDocModel` calls `Resolve-InforcerSettingName` which requires the catalog to be loaded
- Public cmdlet last (Phase 3): module manifest stays clean during development; public surface is stable before it is exported
- DOCX/PDF deferred entirely: both require external dependencies or fragile implementations; the four core formats fully satisfy the use case

### Research Flags

Phases likely needing deeper research during planning:
- **Phase 2 (HTML renderer):** The `<details>/<summary>` accordion with tab switching involves non-trivial CSS interaction; the reference implementation is the research — review it closely before writing the module version
- **Phase 2 (settingInstance type handlers):** `GroupSettingCollectionInstance` requires recursive traversal; the reference implementation in `docs-feature/Document-InforcerTenant-Helpers.ps1` has the working pattern — copy it verbatim, do not re-derive

Phases with standard patterns (skip research-phase):
- **Phase 1 (data collection):** Calls existing public cmdlets with documented parameters — no unknowns
- **Phase 1 (settings catalog caching):** Mirrors the `$script:InforcerSession` pattern already in the module — established convention
- **Phase 3 (module integration):** Follows existing cmdlet conventions exactly — no novelty
- **Phase 2 (JSON/CSV output):** Fully documented patterns in STACK.md with no ambiguity

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | All techniques verified against official PS 7.5 docs, MDN, and measured benchmarks from real data |
| Features | HIGH | Table stakes and differentiators confirmed by direct comparison with M365Documentation, IntuneManagement, IntuneCD, and the `docs-feature` reference implementation |
| Architecture | HIGH | Patterns derived from existing module source and the working reference implementation; component boundaries are unambiguous |
| Pitfalls | HIGH | All findings verified against live code, real tenant data (194 policies), and measured benchmarks — not theoretical |

**Overall confidence:** HIGH

### Gaps to Address

- **settings.json path strategy:** The architecture research flags this as unresolved. Recommendation is sibling-repo auto-discovery with `-SettingsCatalogPath` override and graceful degradation. This decision must be made before Phase 3 begins and should be documented in the cmdlet help. No functional blocker for Phases 1-2.
- **`categories.json` for breadcrumbs:** FEATURES.md lists category breadcrumbs as a differentiator requiring `categories.json` from IntuneSettingsCatalogViewer. Whether to include this in Phase 2 or defer depends on whether the sibling-repo path strategy is resolved first. Treat as Phase 2 stretch goal.
- **MSP/consultant needs:** FEATURES.md notes MEDIUM confidence on MSP-specific requirements (inferred from community discussion, no direct user interviews). The core feature set is unaffected; this gap affects prioritization of differentiators like tag filtering only.

## Sources

### Primary (HIGH confidence)
- `docs-feature/Document-InforcerTenant-Helpers.ps1` — settingInstance resolver patterns, GroupSettingCollectionInstance recursive handler
- `docs-feature/Document-InforcerTenant-Html.ps1` — StringBuilder HTML assembly, HtmlEncode usage, reference output quality bar
- `docs-feature/out/all-settings.json` — real tenant data: 194 policies, null displayName distribution, settingInstance type distribution
- `IntuneSettingsCatalogViewer/data/settings.json` — 62.5 MB, 17,785 entries, type distribution measured
- `module/Public/Get-InforcerTenantPolicies.ps1` — existing null-displayName handling via `Add-InforcerPropertyAliases`
- `docs/api-schema-snapshot.json` — API response shapes
- [ConvertTo-Html — Microsoft Learn (PS 7.5)](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/convertto-html?view=powershell-7.5)
- [ConvertFrom-Json — Microsoft Learn (PS 7.5)](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/convertfrom-json?view=powershell-7.5)
- [HTML Details Exclusive Accordions — MDN Blog](https://developer.mozilla.org/en-US/blog/html-details-exclusive-accordions/)
- [Export-Csv — Microsoft Learn (PS 7.5)](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/export-csv?view=powershell-7.5)

### Secondary (MEDIUM confidence)
- [M365Documentation GitHub](https://github.com/ThomasKur/M365Documentation) — competing tool feature set and limitations
- [IntuneManagement GitHub (Micke-K)](https://github.com/Micke-K/IntuneManagement) — documentation feature capabilities
- [IntuneCD GitHub (almenscorner)](https://github.com/almenscorner/IntuneCD) — Git-centric workflow pattern
- [Speeding Up String Manipulation — powershell.one](https://powershell.one/tricks/performance/strings) — StringBuilder speedup claims (consistent with .NET fundamentals)
- [Automate Intune As-Built Documentation - stealthpuppy](https://stealthpuppy.com/automate-intune-documentation-github/) — MSP/consultant use cases

### Tertiary (LOW confidence)
- [Best Intune Configuration Tools 2026 - AwesomeIntune](https://www.awesomeintune.com/best/configuration-tools) — ecosystem overview

---
*Research completed: 2026-04-01*
*Ready for roadmap: yes*
