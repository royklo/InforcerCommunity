# Domain Pitfalls

**Domain:** PowerShell M365 configuration documentation cmdlet (Export-InforcerDocumentation)
**Researched:** 2026-04-01
**Confidence:** HIGH — all findings verified against live code, actual data files, and measured benchmarks

---

## Critical Pitfalls

Mistakes that cause rewrites, corrupt output, or silently wrong data.

---

### Pitfall 1: String Concatenation for HTML Generation

**What goes wrong:** Using `$html += "<tr>..."` inside a loop over hundreds of policies and thousands of settings rows causes O(n²) memory allocation. PowerShell strings are immutable; every `+=` allocates a new string and copies the entire existing string.

**Why it happens:** It reads naturally and works fine at small scale. The break-even is invisible — output looks correct but generation time explodes.

**Consequences:** Verified benchmark: 10,000 row iterations took 386ms with `+=` vs 7ms with `StringBuilder` — a 55x difference. A real tenant with 194 policies and ~3,000+ settings rows will hit this. At 30,000+ rows (large enterprise tenant) it becomes minutes.

**Prevention:** Use `[System.Text.StringBuilder]` for all HTML assembly. Every append is `[void]$sb.Append(...)`. The reference implementation in `docs-feature/` already does this correctly — carry it forward.

**Detection:** If HTML generation takes more than a few seconds on a 200-policy tenant, string concat is the culprit. Profile with `Measure-Command`.

**Phase:** Core data pipeline / HTML renderer (Phase 1 or 2)

---

### Pitfall 2: Loading settings.json on Every Cmdlet Invocation

**What goes wrong:** If `Export-InforcerDocumentation` loads and parses settings.json at call time with no caching, every invocation pays a ~2-second cold-start cost (measured: 395ms `Get-Content`, 1,517ms `ConvertFrom-Json`, 22ms hashtable build = ~2 seconds for the 62.5MB file).

**Why it happens:** Simple implementation puts `Import-SettingsCatalog` inside the function body. Feels natural. Works correctly but is slow.

**Consequences:** Not just slow — it makes the experience feel broken. A user calling `Export-InforcerDocumentation` twice in a session waits 4 extra seconds for no reason.

**Prevention:** Cache the parsed catalog in a `$script:`-scoped hashtable inside the module. Load once on first use, reuse on subsequent calls. Expose a `-Force` or `-RefreshCatalog` switch if freshness matters.

**Detection:** Timing the cmdlet with `Measure-Command` across two sequential calls — second call should be materially faster if caching is working.

**Phase:** Settings Catalog resolution (Phase 2)

---

### Pitfall 3: Bundling settings.json Inside the Module

**What goes wrong:** Including settings.json in the published PowerShell module makes the module 62.5MB. PowerShell Gallery has a 400MB limit but practical install size expectations are in the 1-5MB range. `Install-Module` will work but is unexpectedly slow and bloats the user's module directory permanently.

**Why it happens:** Bundling feels like the safest path — no external dependency, always available. The file size is not immediately obvious.

**Consequences:** 62.5MB module. Slow installs. Poor user perception. The `categories.json` adds another 574KB. Together they dwarf the actual PowerShell code.

**Prevention:** Do NOT bundle. Instead: document that `-SettingsCatalogPath` requires a local path to the IntuneSettingsCatalogViewer `data/settings.json`. Accept a path parameter and default to auto-discovery of a sibling `IntuneSettingsCatalogViewer/data/settings.json` relative to the module. If not found, degrade gracefully to raw IDs with a visible warning.

**Detection:** Check module package size before publishing. If `.nupkg` > 5MB, investigate what is included.

**Phase:** Module integration / packaging (Phase 3)

---

### Pitfall 4: Missing `@odata.type` Handlers in settingInstance Resolution

**What goes wrong:** The Intune Settings Catalog uses five distinct `@odata.type` shapes for `settingInstance`: `ChoiceSettingInstance`, `SimpleSettingInstance`, `ChoiceSettingCollectionInstance`, `SimpleSettingCollectionInstance`, and `GroupSettingCollectionInstance`. A switch-based resolver that only handles some of them emits `(Unknown type: ...)` rows silently — output looks complete but settings are missing or garbled.

**Why it happens:** `ChoiceSettingInstance` is by far the most common (678 of 745 instances in measured test data, 91%). The others look rare. Developers test happy-path only. The `GroupSettingCollectionInstance` type requires recursive traversal of `groupSettingCollectionValue[].children` — it's easy to miss.

**Consequences:** Silent data loss. The documentation appears complete. Users trust it. Security settings from group collection policies (common in Defender and certain Endpoint Security templates) are omitted entirely.

**Prevention:** Handle all five types explicitly. Add a `default` case that emits the raw `settingDefinitionId` + raw value rather than `(Unknown type)`. Write a unit test that feeds each type into the resolver and asserts a non-empty result. The type distribution from real data:
- `ChoiceSettingInstance`: 678 (91%)
- `SimpleSettingCollectionInstance`: 38 (5%)
- `SimpleSettingInstance`: 22 (3%)
- `GroupSettingCollectionInstance`: 7 (1%)

**Detection:** After processing a real tenant, grep output for `(Unknown type:`. Any match = missing handler.

**Phase:** Settings Catalog resolution (Phase 2)

---

### Pitfall 5: Unhandled Null `displayName` — Policy Name Resolution Fallback

**What goes wrong:** In the real test dataset (194 policies), many Intune policies have `displayName = null` at the API response level. The policy name is stored in the `name` field instead. If the cmdlet reads only `displayName`, these policies appear with a blank or `null` name in the report, and they group incorrectly.

**Why it happens:** The API schema snapshot shows `"name": "null"` (literally) and `"displayName": "string"` for the policies endpoint — suggesting displayName should always be populated. In practice it is not. The reference implementation already handles this (`PolicyName = $p.displayName; if (-not $PolicyName) { $PolicyName = $p.name }`) but the pattern must be carried into the module cmdlet.

**Consequences:** Policies with null displayName appear as unnamed or empty sections. In a large tenant this could be 20-40% of Intune policies.

**Prevention:** Implement a fallback chain: `displayName → name → friendlyName → "Policy $id"`. This is already established in the existing `EnrichPolicyObject` function in `Get-InforcerTenantPolicies.ps1` via `Add-InforcerPropertyAliases`. When using `-OutputType PowerShellObject`, `PolicyName` is already resolved. When processing raw `policyData`, apply the same fallback explicitly.

**Detection:** In test output, search for policies rendered with empty names or literal `null`.

**Phase:** Data collection / normalization (Phase 1)

---

### Pitfall 6: HTML Special Characters in Policy Names and Setting Values

**What goes wrong:** Policy names and setting values frequently contain characters that are meaningful in HTML: `&` (in "Allow & Block"), `<` and `>` (in filter rules like `device.operatingSystem -eq "Windows"`), and `"` (in JSON-like values). Embedding them raw into HTML breaks the DOM or creates XSS vectors.

**Why it happens:** String interpolation into HTML feels natural and works for simple ASCII values. The problematic characters appear in real CA policy filter rules and Conditional Access conditions.

**Consequences:** Broken HTML rendering. Truncated table cells. In a self-contained file sent to stakeholders, injected script tags (though the file is local, not served — still a bad practice).

**Prevention:** Encode every user-derived value before inserting into HTML using `[System.Web.HttpUtility]::HtmlEncode($value)`. `Add-Type -AssemblyName System.Web` is required first — this call is fast and safe to do once at module load. Alternatively, `[System.Security.SecurityElement]::Escape()` works without the assembly load but does not encode `"` to `&quot;`.

**Detection:** Test with a CA policy that has a device filter rule containing `<`, `>`, or `&`. Inspect the HTML source for raw characters.

**Phase:** HTML renderer (Phase 2)

---

### Pitfall 7: UTF-8 BOM in Generated Output Files

**What goes wrong:** `[System.IO.File]::WriteAllText(path, content)` with the default `Encoding.UTF8` writes a UTF-8 BOM (bytes EF BB BF). Some downstream tools (browsers opening local files, diff tools, certain CI artifact processors) handle BOMs poorly. DOCX XML files with BOMs are rejected by Word's Open XML parser outright.

**Why it happens:** .NET's `System.Text.Encoding.UTF8` is BOM-producing by default. Developers assume UTF-8 means "standard UTF-8."

**Consequences:** Broken DOCX files (Word cannot open them). HTML files with a visible `ï»¿` at the start in some editors. Markdown files that fail linting in CI.

**Prevention:**
- For HTML/Markdown: use `Out-File -Encoding utf8` (PS 7 `utf8` is BOM-free) or `[System.Text.UTF8Encoding]::new($false)` with `WriteAllText`.
- For DOCX XML: verify BOM removal. The reference implementation already includes a BOM-stripping loop after writing XML files — preserve this.

**Detection:** Check first 3 bytes of generated files: `[System.IO.File]::ReadAllBytes($path)[0..2]` should not be `0xEF, 0xBB, 0xBF`.

**Phase:** Output file writing (Phase 2-3)

---

## Moderate Pitfalls

---

### Pitfall 8: Markdown Table Breakage from Pipe Characters and Newlines in Values

**What goes wrong:** Markdown tables use `|` as column delimiters. If a setting value contains `|` (common in filter rules: `"Include | Exclude: All platforms"`), the table column count becomes wrong and the table renders incorrectly in all Markdown viewers. Newlines in values (multi-line JSON-like values from `Format-SettingValue`) break the table row entirely.

**Why it happens:** Developers test with simple scalar values. Complex CA conditions and group membership values contain pipe characters. `Format-SettingValue` can emit `ConvertTo-Json -Compress` output which contains `[` and `{` but not pipes — but group conditions joined with ` | ` separators do.

**Consequences:** Entire Markdown output is malformed. GitHub rendering, VS Code preview, and any Markdown-to-PDF pipeline shows a broken table.

**Prevention:** Before inserting any value into a Markdown table cell, apply: `$value -replace '\|', '\|' -replace "`r`n|`n", ' '`. This is safe for all Markdown renderers.

**Detection:** Render the Markdown output in a viewer with a CA policy that has device filters or location conditions.

**Phase:** Markdown renderer (Phase 2)

---

### Pitfall 9: `ConvertTo-Json` Default Depth Silently Truncates Nested Objects

**What goes wrong:** `ConvertTo-Json` defaults to `-Depth 2`. Deeply nested policyData (Settings Catalog policies have `settings[].settingInstance.choiceSettingValue.children[].settingInstance`) truncates at depth 2, replacing inner objects with `"System.Collections.Hashtable"` or `"System.Management.Automation.PSCustomObject"`. The warning is printed but not a terminating error.

**Why it happens:** The default is well-known but easy to forget. The warning prints to the console but is easy to miss in automated pipelines.

**Consequences:** JSON output format produces silently truncated data. Users relying on `Export-InforcerDocumentation -OutputType JSON` for downstream processing get corrupt data.

**Prevention:** Always pass `-Depth 100` (the established convention for this module). Add a Pester test that round-trips a deeply nested policy through the JSON output format and asserts no `System.Collections` strings appear.

**Detection:** Grep JSON output for `"System.Collections"` or `"System.Management.Automation"`.

**Phase:** JSON output format (Phase 2)

---

### Pitfall 10: `RedirectSettingDefinition` Entries in Settings Catalog

**What goes wrong:** The settings catalog contains 30 entries with `@odata.type = "#microsoft.graph.deviceManagementConfigurationRedirectSettingDefinition"`. These are not real configurable settings — they are UI redirect pointers. If a policy's `settingDefinitionId` resolves to one of these, displaying it as a setting produces confusing output: no value, no description, just a redirect label.

**Why it happens:** The catalog lookup treats all 17,785 entries equally. Redirect entries have valid `id` fields that can match `settingDefinitionId` in policy data.

**Consequences:** A small number of settings rows in the output show a redirect type instead of a real setting name. Low frequency (30 of 17,785 = 0.17%) but looks like a bug to users.

**Prevention:** When resolving a `settingDefinitionId`, check the resolved definition's `@odata.type`. If it contains `Redirect`, either skip the row or mark it clearly as `(See portal for this setting)`.

**Detection:** Check test output for rows where SettingName contains "redirect" (case insensitive) or where the resolved `@odata.type` includes `Redirect`.

**Phase:** Settings Catalog resolution (Phase 2)

---

### Pitfall 11: Settings Catalog Data Freshness — New Microsoft Policies Won't Resolve

**What goes wrong:** The `IntuneSettingsCatalogViewer/data/settings.json` is a snapshot. Microsoft continuously adds new settings to the Intune Settings Catalog. A tenant using newly-added settings will have `settingDefinitionIds` that are not in the snapshot, causing those settings to display with their raw ID (e.g., `device_vendor_msft_policy_config_...`) instead of a friendly name.

**Why it happens:** Offline catalog resolution requires a static file. Any static file is immediately stale.

**Consequences:** New tenant policies partially resolve — some settings show friendly names, others show raw IDs. The output is technically correct but looks inconsistent and confusing.

**Prevention:** The graceful fallback (use the raw ID if not found in catalog) must be implemented and visually distinct — mark unresolved IDs with a `[ID]` prefix or different styling. Do not treat missing-from-catalog as an error. Document that users should keep IntuneSettingsCatalogViewer up to date.

**Detection:** After generating output for any tenant, check for SettingName values that look like `settingDefinitionId` patterns (`vendor_msft_`, `~policy~`, etc.).

**Phase:** Settings Catalog resolution (Phase 2)

---

### Pitfall 12: CSV Output Breaking on Complex Nested Values

**What goes wrong:** `Export-Csv` serializes PSCustomObject properties to string. If a `Value` property contains newlines (from `ConvertTo-Json -Compress` on arrays, or `Format-SettingValue` on nested objects), CSV cells break across rows and Excel/Google Sheets misinterpret the file.

**Why it happens:** `Export-Csv` wraps values with embedded commas in double quotes but does not handle newlines inside quoted fields consistently across all parsers.

**Prevention:** Before passing rows to `Export-Csv`, normalize the `Value` field: replace all newlines with a space or ` | `. The `Format-SettingValue` function should produce flat single-line output for all input types.

**Detection:** Open the CSV in Excel after generation. If row count in Excel differs from policy count times setting count, embedded newlines are present.

**Phase:** CSV output format (Phase 2)

---

## Minor Pitfalls

---

### Pitfall 13: Platform Field Is Null for Most Policies

**What goes wrong:** The API schema shows `"platform": "null"` for the policies endpoint. In measured real data, 187 of 194 policies (96%) have a null `platform` field. Code that branches on platform for display (e.g., "Windows only" badges) will fail to populate for almost all policies.

**Prevention:** Treat `platform` as optional display information only. Where the platform is non-null, display it. Where it is null, omit the badge rather than showing "(null)" or "unknown".

**Phase:** Policy normalization (Phase 1)

---

### Pitfall 14: Ordered Dictionary vs Hashtable for Product/Group Grouping

**What goes wrong:** Using a regular `@{}` hashtable for product-tab grouping produces non-deterministic ordering. The HTML output changes the product tab order on every run, which is confusing for users comparing runs and breaks diffs.

**Prevention:** Use `[ordered]@{}` (or `[System.Collections.Specialized.OrderedDictionary]`) at every grouping level: Product → PrimaryGroup → PolicyName. The reference implementation does this correctly — preserve it.

**Detection:** Generate two identical tenant docs and diff the HTML. Non-deterministic tab order causes false diffs.

**Phase:** Grouping logic (Phase 1)

---

### Pitfall 15: HTML Anchor IDs Colliding Across Products

**What goes wrong:** When generating TOC anchor links for HTML (`<a href="#policy-name">`), policy names like "Baseline" or "Default" may appear in multiple product tabs. The second occurrence has a duplicate ID, which browsers resolve to the first match — TOC links navigate to the wrong section.

**Prevention:** Prefix anchor IDs with the product+group: `id="intune-configuration-policies-baseline"` rather than `id="baseline"`. Alternatively, use JavaScript-based tab switching that doesn't rely on anchor IDs.

**Detection:** Inspect generated HTML for duplicate `id=` attributes. Any id that appears twice is a collision.

**Phase:** HTML renderer / TOC (Phase 2)

---

## Phase-Specific Warnings

| Phase Topic | Likely Pitfall | Mitigation |
|-------------|----------------|------------|
| Data collection from existing cmdlets | Null `displayName` in Intune policies | Implement name fallback chain: `displayName → name → friendlyName → "Policy $id"` |
| Settings Catalog resolution | Missing `@odata.type` handlers for 4 non-Choice types | Cover all 5 settingInstance types; add recursive handler for GroupSettingCollectionInstance |
| Settings Catalog load | 2-second cold-start per invocation | Cache in `$script:`-scoped hashtable; load once per session |
| Settings Catalog bundling | 62.5MB file too large for module | Accept `-SettingsCatalogPath` parameter; auto-discover sibling path; never bundle |
| HTML rendering | String concat O(n²) | Use `StringBuilder` throughout; never `$html +=` in a loop |
| HTML rendering | HTML special characters breaking DOM | `[System.Web.HttpUtility]::HtmlEncode()` on every user-derived value |
| Markdown rendering | Pipe characters breaking tables | Escape `\|` and flatten newlines before inserting into table cells |
| JSON output | ConvertTo-Json depth 2 truncation | Always use `-Depth 100` (established module convention) |
| CSV output | Embedded newlines in value cells | Flatten all values to single-line strings before `Export-Csv` |
| File writing (all formats) | UTF-8 BOM from .NET default encoding | Use `Out-File -Encoding utf8` or `[System.Text.UTF8Encoding]::new($false)` |
| New Intune settings (catalog staleness) | Settings not in snapshot show raw IDs | Implement graceful fallback with visible `[ID]` marker; document update process |

---

## Sources

All findings are based on direct investigation of this codebase and data:

- `docs-feature/Document-InforcerTenant-Helpers.ps1` — Reference implementation; settingInstance resolver; GroupSettingCollectionInstance handling pattern
- `docs-feature/Document-InforcerTenant-Html.ps1` — Reference HTML renderer; StringBuilder usage; HtmlEncode usage
- `docs-feature/out/all-settings.json` — Real tenant data: 194 policies, null displayName distribution, settingDefinitionId coverage
- `docs-feature/out/TenantDoc_OfflineTest_*.html` — Generated output: 2.1MB, 29k lines for a 194-policy tenant
- `IntuneSettingsCatalogViewer/data/settings.json` — 62.5MB, 17,785 entries, type distribution measured
- `module/Public/Get-InforcerTenantPolicies.ps1` — Existing null-displayName handling via `Add-InforcerPropertyAliases`
- `docs/api-schema-snapshot.json` — API response shapes; `platform: null` for policies endpoint
- Measured benchmarks: `StringBuilder` vs `+=` (55x), `ConvertFrom-Json` load time (~1.5s), hashtable lookup (~0ms)
- PowerShell 7 encoding behavior: `Out-File -Encoding utf8` = no BOM; `[System.IO.File]::WriteAllText` default = BOM
