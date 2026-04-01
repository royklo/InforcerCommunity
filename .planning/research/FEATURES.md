# Feature Landscape

**Domain:** M365 / Intune tenant documentation export tools
**Researched:** 2026-04-01
**Context:** InforcerCommunity `Export-InforcerDocumentation` cmdlet

---

## Ecosystem Survey

The tenant-documentation ecosystem has three relevant tool families:

| Tool | Status | Output formats | Notes |
|------|--------|---------------|-------|
| IntuneDocumentation (ThomasKur) | Archived Feb 2025 | DOCX only | Deprecated; successor is M365Documentation |
| M365Documentation (ThomasKur) | Active, v3.4.x | DOCX, Markdown, CSV, JSON | Requires PSWriteOffice; PS7 support as of 3.2.2 |
| IntuneManagement (Micke-K) | Active | CSV, DOCX, Markdown (experimental) | GUI-first tool; docs mirror portal Edit-mode language |
| IntuneCD (almenscorner) | Active | YAML/JSON backup + Markdown as-built | Python-based; Git-centric workflow |
| docs-feature reference impl | Internal (royklo) | HTML, CSV, DOCX, PDF | The prototype that defines the target for this milestone |

The `docs-feature` reference implementation in `/royklo/docs-feature/` is the most direct comparator: it is already scoped to the Inforcer API and represents the intended output quality bar. The analysis below is calibrated against it and the wider ecosystem.

---

## Table Stakes

Features users expect. Missing = product feels incomplete or untrustworthy.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| Per-policy setting name + value | Core documentation unit; every competing tool has it | Low | Raw API field names are unacceptable — must be friendly names |
| Friendly-name resolution for Settings Catalog | Intune settings use `settingDefinitionId` GUIDs internally; admins expect portal labels | Medium | IntuneSettingsCatalogViewer `settings.json` is the data source; must handle missing IDs gracefully (fall back to raw ID, no crash) |
| Product/category grouping | Policies span Intune, Entra, Defender, Exchange, Teams; ungrouped output is unusable at scale | Medium | Two-level hierarchy (Product → Category) maps to `PrimaryGroup`/`SecondaryGroup` from existing API data |
| Policy metadata (Basics section) | Name, description, platform, created/modified dates are the minimum context readers expect | Low | Already present in `Get-InforcerTenantPolicies` output |
| Assignments section per policy | "Who does this apply to?" is the first question during audits and troubleshooting | Low-Med | Inforcer API returns assignment data; groups need to be represented (IDs should resolve to names where possible) |
| Scope tags display | Required for MSP environments — tells reader which admin scope a policy belongs to | Low | Available in Inforcer tenant policies data |
| HTML output | Self-contained, shareable, no software install required for the reader | Medium | Must be a single file (self-contained CSS/JS); no CDN dependencies |
| Markdown output | Required for Git-centric workflows (IntuneCD pattern); also the most-requested format in the M365Documentation community | Low-Med | TOC generation essential; large Markdown files are a known pain point — collapsible structure matters |
| JSON output | Configuration backup use case; enables diff tooling (jq, git diff) | Low | Full-depth (depth 100 per module convention); structured, not just raw API passthrough |
| CSV output | Data analysis in Excel; requested by consultants for client deliverables | Low | Flattened rows with context columns (Product, Category, PolicyName, SettingName, Value) |
| Generation timestamp | Audit trail; "when was this snapshot taken?" | Trivial | In page title and footer |
| Tenant name in output | Multi-tenant MSP environment — must know which tenant the doc describes | Low | Resolved via `Get-InforcerTenant`; falls back to ID |
| Graceful handling of unknown setting IDs | Settings Catalog data evolves; the catalog will always have gaps | Low | Log warning, emit raw ID, do not error-halt |
| No external module dependencies for core formats | Module conventions require no new dependencies for HTML/MD/JSON/CSV | Low | Consistent with existing InforcerCommunity design constraint |

---

## Differentiators

Features that set this product apart from the existing tools. Not expected by default, but meaningfully valued.

| Feature | Value Proposition | Complexity | Notes |
|---------|------------------|------------|-------|
| Collapsible HTML with product tabs | Competing tools produce flat, large HTML/DOCX; tabbed + collapsible makes large tenants navigable | Medium | The `docs-feature` prototype already implements `<details>` + tab switching; this is the key UX differentiator vs M365Documentation and IntuneManagement |
| Dark/light mode toggle in HTML | Quality-of-life for screen readers and presentations; no competing tool has this | Low | CSS custom properties with `data-theme` attribute; trivial to implement once CSS is structured |
| "Configured" vs "not configured" distinction | Admins need to know which settings are actively set vs just enumerated; M365Documentation doesn't distinguish this | Low | `IsConfigured` flag on each row; grey-out not-configured rows |
| Per-policy setting count badge | At a glance: "42 settings, 38 configured" in the collapsed header | Trivial | Already in the prototype; zero extra data required |
| Graph API reference badge per category | Tells the reader exactly which Graph endpoint produced the data — useful for automation/scripting follow-up | Low | Static lookup table; already implemented in `docs-feature` |
| Category breadcrumb for Settings Catalog | "Windows > Security > BitLocker" instead of a UUID — navigability inside long policies | Low | Requires `categories.json` from IntuneSettingsCatalogViewer; already in prototype |
| Choice option resolution (friendly label + raw value) | Policy value shows "Require multifactor authentication" not `block_mfa_true_0`; no competing open-source tool does this consistently | Medium | Requires option matching within `settings.json`; already implemented in `docs-feature` |
| Tag filtering in HTML output | MSP admins use scope tags to partition tenants; filtering by tag in the rendered HTML reduces noise | Medium | Per-policy tag badges already in prototype; JS filter is the incremental add |
| Inforcer-native: no Graph auth setup required | Every other tool requires its own Azure app registration + delegated/application permissions; this uses the existing `Connect-Inforcer` session | N/A | Not a feature to build — it is the structural advantage. Emphasise in docs. |
| Multi-format in a single command invocation | `Export-InforcerDocumentation -Format Html,Csv,Markdown` — competing tools are single-format per run | Low | Already in `docs-feature` prototype design |

---

## Anti-Features

Features to explicitly NOT build.

| Anti-Feature | Why Avoid | What to Do Instead |
|--------------|-----------|-------------------|
| DOCX output in Phase 1 | Requires either PSWriteOffice (external dependency, breaks module conventions) or a custom Open XML generator (significant complexity, maintenance burden). The `docs-feature` prototype has a custom Open XML generator but it is fragile and requires a stripped-down DOCX without styles | Defer to a later milestone. HTML covers the "send to management" use case adequately; PDF via headless browser is a bridge. |
| PDF output in Phase 1 | Depends on Chrome/Edge being installed on the machine running the cmdlet — not reliable in CI or headless environments | Defer. Document as a user-performed step: "open the HTML in a browser and print to PDF." |
| Diff / tenant comparison | A distinct product feature. IntuneManagement does this; `compare_baselines.py` in the royklo root repo is already a separate track | Separate cmdlet/project; do not conflate with documentation generation |
| Scheduled / automated report push | Out of scope per PROJECT.md — users wrap the cmdlet in their own automation | Document the pattern; do not build scheduling infrastructure |
| Real-time settings catalog API calls | Latency, auth complexity, rate limiting; the bundled `settings.json` is updated regularly and covers all current policies | Use bundled or local-path settings.json only |
| Group name resolution via Graph API | Would require a second authentication context (Microsoft Graph) separate from the Inforcer API session. Adds significant auth complexity for marginal display benefit | Show group IDs with a note; or allow the user to pass a pre-built group map as a parameter (future option) |
| Interactive web UI / hosted report server | Out of scope for a PowerShell module; this is automation tooling, not a SaaS product | The self-contained HTML is the "portable viewer" |
| YAML output | IntuneCD does this; not part of the M365Documentation lineage and not requested by Inforcer-centric admins | JSON covers the structured-data backup use case |

---

## Feature Dependencies

```
Settings Catalog friendly names
  → requires: settings.json loaded at runtime
  → requires: categories.json for breadcrumbs (optional but recommended)
  → blocks: choice option resolution (needs option list from settings.json)

Product/category grouping
  → requires: Product + PrimaryGroup + SecondaryGroup fields from Inforcer API data
  → blocks: tabbed HTML, grouped Markdown TOC, per-product CSV files

HTML collapsible TOC
  → requires: product/category grouping
  → requires: per-policy metadata (Basics) to populate collapsed header

Per-policy assignments section
  → requires: assignments data from Get-InforcerTenantPolicies
  → optionally enhanced by: group-name resolution (deferred)

"Configured" distinction
  → requires: IsConfigured evaluation per row
  → enables: configured-only filter in HTML

Tag filtering in HTML
  → requires: scope tags in policy data
  → requires: tag badges already rendered in HTML
  → requires: JS filter logic (incremental add)

CSV output
  → requires: flat row structure (New-DocRow pattern)
  → must produce: one file per product tab (consistent with docs-feature prototype)

Markdown output
  → requires: product/category grouping
  → requires: collapsible anchor-based TOC (GitHub-Flavored Markdown compatible)

DOCX output (deferred)
  → requires: either PSWriteOffice OR custom Open XML generator
  → NOT a blocker for Phase 1
```

---

## MVP Recommendation

Prioritise for Phase 1 (the documentation milestone):

1. **Data pipeline**: `Get-InforcerBaseline` + `Get-InforcerTenant` + `Get-InforcerTenantPolicies` → flat documentation rows via Settings Catalog resolution
2. **HTML output**: self-contained, product tabs, collapsible categories/policies, dark/light mode, configured/not-configured distinction, scope tag badges
3. **Markdown output**: product-grouped, anchor TOC, settings tables per policy
4. **JSON output**: full-depth structured export
5. **CSV output**: flattened rows with Product/Category/PolicyName/SettingName/Value columns

Defer:
- **DOCX**: external dependency or significant fragile custom generator
- **PDF**: headless browser dependency unreliable in CI
- **Group name resolution**: requires second auth context (Microsoft Graph)
- **Tag filter JS in HTML**: add after core HTML is stable (low effort, low risk, Phase 2 candidate)

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Table stakes features | HIGH | Directly observed in M365Documentation, IntuneManagement, IntuneCD, and the docs-feature prototype |
| Differentiators | HIGH | Gaps in competing tools confirmed by reading their documentation and limitations sections |
| Anti-features (DOCX/PDF) | HIGH | Supported by IntuneDocumentation archived status citing PSWord fragility, Micke-K DOCX caveats, and Project.md explicit decision |
| MSP/consultant needs | MEDIUM | Inferred from community discussion and IntuneCD/stealthpuppy blog posts; no direct user interview data |
| Group name resolution complexity | HIGH | Microsoft Graph requires a separate auth context; confirmed by Conditional Access documentation requirements in competing tools |

---

## Sources

- [IntuneDocumentation GitHub (archived Feb 2025)](https://github.com/ThomasKur/IntuneDocumentation)
- [M365Documentation GitHub](https://github.com/ThomasKur/M365Documentation)
- [M365Documentation Markdown announcement - WPNinjas (Jul 2023)](https://www.wpninjas.ch/2023/07/unveiling-a-new-version-of-m365documentation-powershell-module-creating-markdown-documentation-with-ease/)
- [IntuneManagement GitHub (Micke-K)](https://github.com/Micke-K/IntuneManagement)
- [IntuneManagement Documentation.md](https://github.com/Micke-K/IntuneManagement/blob/master/Documentation.md)
- [IntuneCD GitHub (almenscorner)](https://github.com/almenscorner/IntuneCD)
- [Automate Intune As-Built Documentation - stealthpuppy](https://stealthpuppy.com/automate-intune-documentation-github/)
- [Best Intune Configuration Tools 2026 - AwesomeIntune](https://www.awesomeintune.com/best/configuration-tools)
- Internal: `/royklo/docs-feature/Document-InforcerTenant.ps1` (reference implementation)
- Internal: `/royklo/docs-feature/Document-InforcerTenant-Helpers.ps1` (settings resolution + product renderers)
- Internal: `/royklo/docs-feature/Document-InforcerTenant-Html.ps1` (HTML generation prototype)
- Internal: `InforcerCommunity/.planning/PROJECT.md` (project requirements and constraints)
