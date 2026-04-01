# Phase 1: Data Pipeline and Normalization - Research

**Researched:** 2026-04-01
**Domain:** PowerShell data collection, Settings Catalog resolution, and DocModel normalization for InforcerCommunity module
**Confidence:** HIGH — all findings verified against live sample data (1.4 MB, 194 real policies), settings.json (17,785 entries), and existing module source

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** Bundle a copy of settings.json inside the module's `data/` folder. This ships with the module — no external dependency.
- **D-02:** Future milestone: automate nightly refresh from IntuneSettingsCatalogViewer repo so the bundled copy stays current. Not in scope for v1.
- **D-03:** Cache loaded settings.json in `$script:InforcerSettingsCatalog` (same pattern as `$script:InforcerSession`). Load once per session, not per invocation.
- **D-04:** API already provides `product`, `primaryGroup`, and `secondaryGroup` fields on every policy. No mapping table needed — use these directly for the 3-level hierarchy.
- **D-05:** Products observed in real data: Entra, Intune, Defender, Exchange, SharePoint, Teams, M365 Admin Center, Purview. Group by `product` → `primaryGroup` as two-level TOC.
- **D-06:** At least 4 distinct policyData shapes exist based on policyTypeId (Settings Catalog type 10, Conditional Access type 1, Compliance type 3, Entra/SharePoint types 12/14, Exchange mail flow type 25, and others).
- **D-07:** Normalization layer must handle each shape and flatten to consistent Name/Value pair model. For Settings Catalog, resolve via settings.json. For all others, use property name as setting name.
- **D-08:** Data collection script already created at `scripts/Collect-InforcerData.ps1`. Captures `tenants.json`, `baselines.json`, `tenant-policies.json` to `scripts/sample-data/`.
- **D-09:** Sample data collected from tenant 142 ("inforcer Blueprint Library") — 194 policies across 8 products.
- **D-10:** DocModel shape is a nested tree: `$DocModel.Products["Entra"].Categories["Conditional Access / Policies"]` = array of policy objects, each with Basics, Settings, Assignments.
- **D-11:** Category key is `"primaryGroup / secondaryGroup"` (combined). When secondaryGroup equals primaryGroup or is "All", use just primaryGroup.
- **D-12:** Each setting row has: `Name` (friendly), `Value` (friendly), `Indent` (0 for top-level, 1 for child), `IsConfigured` (whether explicitly set vs default).
- **D-13:** displayName fallback chain: `displayName → friendlyName → name → policyData.name → policyData.displayName → "Policy {id}"`. Real data shows many `null` displayName values but `friendlyName` is usually populated.
- **D-14:** Platform field is `null` for ~96% of policies. Show as empty, don't fabricate.
- **D-15:** Tags array may be empty or null. Normalize to empty string when missing.

### Claude's Discretion

- Internal data structures and helper function signatures
- Performance optimization strategies for settings.json parsing
- Error handling granularity within the normalization pipeline

### Deferred Ideas (OUT OF SCOPE)

- Nightly automation to refresh settings.json from IntuneSettingsCatalogViewer repo
- Category breadcrumbs using categories.json from IntuneSettingsCatalogViewer
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DATA-01 | Cmdlet collects tenant info via Get-InforcerTenant -OutputType JsonObject | Existing cmdlet confirmed; returns depth-100 JSON string |
| DATA-02 | Cmdlet collects baseline data via Get-InforcerBaseline -OutputType JsonObject | Existing cmdlet confirmed; same pattern |
| DATA-03 | Cmdlet collects all policies via Get-InforcerTenantPolicies -OutputType JsonObject | Existing cmdlet confirmed; 194 policies in sample |
| DATA-04 | Data collection script provided for development/testing | scripts/Collect-InforcerData.ps1 already exists; fully functional |
| SCAT-01 | Settings Catalog settingDefinitionIDs resolved to friendly display names using settings.json | settings.json confirmed at sibling path; 17,785 entries; `id` and `displayName` fields present |
| SCAT-02 | Choice option values resolved to friendly labels | settings.json `options` array contains `itemId` → `displayName` mapping |
| SCAT-03 | Settings hierarchy preserved (parent/child via indentation) | `choiceSettingValue.children[]` and `groupSettingCollectionValue[].children[]` confirmed in real data |
| SCAT-04 | Unknown settingDefinitionIDs fall back to raw ID with warning, no error-halt | Standard pattern; implemented via `Write-Warning` + raw ID passthrough |
| SCAT-05 | settings.json loaded once and cached in $script: scope | $script:InforcerSettingsCatalog pattern follows $script:InforcerSession; load time ~2s makes this mandatory |
| SCAT-06 | All 5 settingInstance @odata.type variants handled | 4 confirmed in real data: Choice(678), SimpleCollection(38), Simple(22), GroupSettingCollection(7); ChoiceCollection not in sample but required per spec |
| NORM-01 | Policies grouped by M365 product area using API product/category fields | All 194 policies have product + primaryGroup confirmed; 31 unique policy type IDs observed |
| NORM-02 | Two-level hierarchy: Product → Category → Policies | D-11 defines category key formation; [ordered]@{} required to preserve deterministic ordering |
| NORM-03 | Per-policy data normalized into sections: Basics, Settings, Assignments | DocModel shape defined in D-10; verified against reference output format |
| NORM-04 | Basics section: Name, Description, Profile type, Platform, Created/Modified dates, Scope tags | Fields confirmed in sample data; platform is null 96% of time (D-14) |
| NORM-05 | Null/missing displayName handled via fallback chain | 123/194 policies have null name, 50 have null displayName, 50 have null friendlyName — fallback chain is critical |
| NORM-06 | $DocModel is format-agnostic — renderers receive only the model, no API calls | Architecture enforces this at design level; ConvertTo-InforcerDocModel returns pure data |
</phase_requirements>

---

## Summary

Phase 1 builds a four-component pipeline: data collection, settings catalog loading, name resolution, and DocModel normalization. All components have clear predecessors in the existing module: the session caching pattern (`$script:InforcerSession`), the enrichment helper (`EnrichPolicyObject`), and the -OutputType JsonObject pipeline are already established and proven. The `scripts/Collect-InforcerData.ps1` data collection script is already implemented and working.

The most complex component is the Settings Catalog resolver (`Resolve-InforcerSettingName`). Real data confirms 4 active settingInstance types in the 50 Settings Catalog policies (type 10): ChoiceSettingInstance (678 occurrences, 91%), SimpleSettingCollectionInstance (38), SimpleSettingInstance (22), GroupSettingCollectionInstance (7). GroupSettingCollectionInstance requires recursive traversal and nesting can reach 3+ levels deep in real data. ChoiceSettingInstance also has `children[]` arrays that must be traversed recursively to capture dependent sub-settings.

The normalization layer must handle 31+ distinct policy type IDs, but only type 10 uses settings.json lookup. All other types use flat key-value property enumeration from policyData. The D-07 strategy (property name as setting name for non-catalog types) is confirmed correct by examining types 1, 3, 12, 14, 25, and 70 in the sample data.

**Primary recommendation:** Build in dependency order: Import-InforcerSettingsCatalog → Resolve-InforcerSettingName → Get-InforcerDocData → ConvertTo-InforcerDocModel. Each component is independently testable with the existing sample data files before the next is written.

---

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| PowerShell 7.0+ | 7.0+ | Runtime | Module requirement; `ConvertFrom-Json -Depth 100` available in 7.x |
| Pester | 5.x (installed) | Unit/consistency testing | Already used in Tests/Consistency.Tests.ps1 |
| System.Text.StringBuilder | .NET (built-in) | String assembly | Eliminates O(n²) string concat; established in performance skill |
| System.Collections.Generic.List[object] | .NET (built-in) | Array building in loops | No += on arrays; established in performance skill |
| System.Collections.Specialized.OrderedDictionary / [ordered]@{} | .NET (built-in) | Product/category grouping | Deterministic key ordering; prevents non-deterministic doc output |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| ConvertFrom-Json | PS built-in | Deserialize API JSON strings | Always with -Depth 100; never without |
| ConvertTo-Json | PS built-in | Serialize DocModel | Always with -Depth 100; JSON output format |
| Write-Warning | PS built-in | Unknown settingDefinitionID fallback | Non-terminating warning on catalog miss |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| [ordered]@{} for grouping | Regular @{} | Regular hashtable has non-deterministic key order — produces different TOC ordering on each run; breaks diffs |
| $script: scope for settings catalog | Caller-supplied parameter per call | Passing catalog around adds complexity; session scope is the established module pattern |
| Bundle settings.json in module/data/ | Reference sibling path only | Bundling adds ~5 MB to module; user decision D-01 locks this to bundle |

**Installation:** No additional packages required. This phase uses built-in PowerShell and .NET types only.

**Version verification:** PowerShell 7.0+ confirmed as module minimum. `ConvertFrom-Json -Depth` parameter verified available in PS 7.x.

---

## Architecture Patterns

### Recommended Project Structure

```
module/
├── Public/
│   └── (no new public cmdlets in Phase 1)
├── Private/
│   ├── Get-InforcerDocData.ps1          # Stage 1: data collection
│   ├── Import-InforcerSettingsCatalog.ps1  # Stage 2a: catalog load + cache
│   ├── Resolve-InforcerSettingName.ps1  # Stage 2b: per-setting ID resolution
│   └── ConvertTo-InforcerDocModel.ps1   # Stage 2c: normalization → $DocModel
└── data/
    └── settings.json                    # Bundled copy (62.5 MB from sibling repo)
scripts/
└── sample-data/                         # Already populated with 194-policy fixture
    ├── tenants.json
    ├── baselines.json
    └── tenant-policies.json
```

### Pattern 1: Session-Scoped Catalog Cache

**What:** Load settings.json once per session, cache in `$script:InforcerSettingsCatalog`. Subsequent calls skip loading.

**When to use:** Always — 62.5 MB file with ~2 second parse time makes per-call loading unacceptable.

**Example:**
```powershell
# In Import-InforcerSettingsCatalog.ps1
function Import-InforcerSettingsCatalog {
    param([string]$Path)
    # Guard: already loaded
    if ($null -ne $script:InforcerSettingsCatalog) { return }

    $raw = Get-Content -Path $Path -Raw -Encoding UTF8
    $entries = $raw | ConvertFrom-Json -Depth 100

    $catalog = [ordered]@{}
    foreach ($entry in $entries) {
        $id = $entry.id
        if ([string]::IsNullOrEmpty($id)) { continue }
        $options = [ordered]@{}
        foreach ($opt in @($entry.options)) {
            if ($opt -and $opt.itemId) { $options[$opt.itemId] = $opt.displayName }
        }
        $catalog[$id] = @{
            DisplayName = $entry.displayName
            Description = $entry.description
            Options     = $options
            OdataType   = $entry.'@odata.type'
        }
    }
    $script:InforcerSettingsCatalog = $catalog
}
```

### Pattern 2: Non-Throwing Resolver with Fallback

**What:** `Resolve-InforcerSettingName` never throws on a miss; returns raw ID as name.

**When to use:** Every settingDefinitionId lookup from Settings Catalog policies.

**Example:**
```powershell
function Resolve-InforcerSettingName {
    param(
        [string]$SettingDefinitionId,
        [string]$ChoiceValue  # optional; the raw itemId to resolve to label
    )
    $result = @{ DisplayName = $SettingDefinitionId; Description = ''; ValueLabel = ''; IsRedirect = $false }
    if ([string]::IsNullOrEmpty($SettingDefinitionId)) { return $result }
    if ($null -eq $script:InforcerSettingsCatalog) { return $result }

    $entry = $script:InforcerSettingsCatalog[$SettingDefinitionId]
    if ($null -eq $entry) {
        Write-Warning "Settings Catalog: unknown settingDefinitionId '$SettingDefinitionId'"
        return $result
    }

    $result.DisplayName = if ($entry.DisplayName) { $entry.DisplayName } else { $SettingDefinitionId }
    $result.Description = $entry.Description
    $result.IsRedirect  = $entry.OdataType -like '*Redirect*'

    if (-not [string]::IsNullOrEmpty($ChoiceValue)) {
        $label = $entry.Options[$ChoiceValue]
        $result.ValueLabel = if ($label) { $label } else { $ChoiceValue }
    }
    return $result
}
```

### Pattern 3: Recursive settingInstance Traversal

**What:** Settings Catalog policies have a tree of settingInstances, including nested children. The traversal must be recursive and handle all 5 odata.type variants.

**When to use:** Any type-10 (Settings Catalog) policy policyData processing.

**Key insight from real data:** `choiceSettingValue.children[]` contains nested instances (Depth=1). `groupSettingCollectionValue[].children[]` also contains nested instances, and can nest 3+ levels deep (GroupSettingCollection can contain another GroupSettingCollection).

**Traversal outline:**
```powershell
function ConvertTo-InforcerSettingRows {
    param($SettingInstance, [int]$Depth = 0)

    $rows = [System.Collections.Generic.List[object]]::new()
    $odataType = $SettingInstance.'@odata.type'
    $defId = $SettingInstance.settingDefinitionId
    $resolved = Resolve-InforcerSettingName -SettingDefinitionId $defId

    switch -Wildcard ($odataType) {
        '*ChoiceSettingInstance' {
            $csv = $SettingInstance.choiceSettingValue
            $choiceLabel = if ($csv) { (Resolve-InforcerSettingName -SettingDefinitionId $defId -ChoiceValue $csv.value).ValueLabel } else { '' }
            [void]$rows.Add([PSCustomObject]@{ Name = $resolved.DisplayName; Value = $choiceLabel; Indent = $Depth; IsConfigured = $true })
            # Recurse into children
            foreach ($child in @($csv.children)) {
                if ($child) { foreach ($r in (ConvertTo-InforcerSettingRows $child ($Depth + 1))) { [void]$rows.Add($r) } }
            }
        }
        '*SimpleSettingInstance' {
            $value = $SettingInstance.simpleSettingValue.value
            [void]$rows.Add([PSCustomObject]@{ Name = $resolved.DisplayName; Value = $value; Indent = $Depth; IsConfigured = $true })
        }
        '*SimpleSettingCollectionInstance' {
            $values = ($SettingInstance.simpleSettingCollectionValue | ForEach-Object { $_.value }) -join ', '
            [void]$rows.Add([PSCustomObject]@{ Name = $resolved.DisplayName; Value = $values; Indent = $Depth; IsConfigured = $true })
        }
        '*GroupSettingCollectionInstance' {
            [void]$rows.Add([PSCustomObject]@{ Name = $resolved.DisplayName; Value = ''; Indent = $Depth; IsConfigured = $false })
            foreach ($group in @($SettingInstance.groupSettingCollectionValue)) {
                foreach ($child in @($group.children)) {
                    if ($child) { foreach ($r in (ConvertTo-InforcerSettingRows $child ($Depth + 1))) { [void]$rows.Add($r) } }
                }
            }
        }
        '*ChoiceSettingCollectionInstance' {
            # Less common; each element in choiceSettingCollectionValue is a choice
            foreach ($item in @($SettingInstance.choiceSettingCollectionValue)) {
                $label = (Resolve-InforcerSettingName -SettingDefinitionId $defId -ChoiceValue $item.value).ValueLabel
                [void]$rows.Add([PSCustomObject]@{ Name = $resolved.DisplayName; Value = $label; Indent = $Depth; IsConfigured = $true })
            }
        }
        default {
            Write-Warning "Unhandled settingInstance type: $odataType for '$defId'"
            [void]$rows.Add([PSCustomObject]@{ Name = $defId; Value = "(unhandled type: $odataType)"; Indent = $Depth; IsConfigured = $false })
        }
    }
    $rows
}
```

### Pattern 4: Ordered Grouping for Deterministic Output

**What:** Use `[ordered]@{}` at every grouping level to prevent non-deterministic key ordering.

**When to use:** Products hashtable, Categories hashtable within each product.

```powershell
$products = [ordered]@{}
foreach ($policy in $allPolicies) {
    $prod = $policy.product
    if (-not $products.Contains($prod)) { $products[$prod] = [ordered]@{} }
    $catKey = Get-CategoryKey -PrimaryGroup $policy.primaryGroup -SecondaryGroup $policy.secondaryGroup
    if (-not $products[$prod].Contains($catKey)) { $products[$prod][$catKey] = [System.Collections.Generic.List[object]]::new() }
    [void]$products[$prod][$catKey].Add($normalizedPolicy)
}
```

### Pattern 5: Non-Catalog Policy Flat Enumeration

**What:** For all policyTypeId values other than 10, enumerate policyData properties directly as Name/Value pairs.

**When to use:** Types 1 (CA), 3 (Compliance), 12 (Entra Settings), 14 (SharePoint), 25 (Exchange), 70 (M365 Admin Center self-service), and all other types.

**Key insight from real data:** Type 12 policyData has a nested `data` object containing named sub-policies (e.g., `AdminAppConsent`). Type 70 (M365 Admin Center) has flat key-value pairs. Type 3 (Compliance) is flat with boolean/string/int property values.

```powershell
function ConvertTo-FlatSettingRows {
    param($PolicyData, [int]$Depth = 0)
    $rows = [System.Collections.Generic.List[object]]::new()
    if ($null -eq $PolicyData) { return $rows }

    $skip = @('@odata.type','id','createdDateTime','lastModifiedDateTime','roleScopeTagIds','version','templateId','displayName','description','assignments','settings')
    foreach ($prop in $PolicyData.PSObject.Properties) {
        if ($prop.Name -in $skip) { continue }
        $val = $prop.Value
        # Recurse into nested objects (e.g. type 12 'data' object)
        if ($val -is [PSObject] -and $val.PSObject.Properties.Count -gt 0 -and $Depth -lt 2) {
            [void]$rows.Add([PSCustomObject]@{ Name = $prop.Name; Value = ''; Indent = $Depth; IsConfigured = $false })
            foreach ($r in (ConvertTo-FlatSettingRows $val ($Depth + 1))) { [void]$rows.Add($r) }
        } else {
            $strVal = if ($null -eq $val) { '' } elseif ($val -is [array]) { $val -join ', ' } else { $val.ToString() }
            [void]$rows.Add([PSCustomObject]@{ Name = $prop.Name; Value = $strVal; Indent = $Depth; IsConfigured = $true })
        }
    }
    $rows
}
```

### Pattern 6: DocData Bundle from Existing Cmdlets

**What:** `Get-InforcerDocData` calls all three existing cmdlets and returns a raw data bundle hashtable. This is STAGE 1 of the pipeline.

**When to use:** Always as the first step of Export-InforcerDocumentation.

**Note:** `Get-InforcerTenant` requires no -TenantId for listing all tenants; the caller finds the target tenant after. `Get-InforcerTenantPolicies` requires -TenantId.

```powershell
function Get-InforcerDocData {
    param([object]$TenantId)
    # Resolve TenantId first
    $clientTenantId = Resolve-InforcerTenantId -TenantId $TenantId
    @{
        TenantJson   = Get-InforcerTenant -OutputType JsonObject
        BaselineJson = Get-InforcerBaseline -OutputType JsonObject
        PoliciesJson = Get-InforcerTenantPolicies -TenantId $clientTenantId -OutputType JsonObject
        CollectedAt  = [datetime]::UtcNow
    }
}
```

### Anti-Patterns to Avoid

- **Loading settings.json inside ConvertTo-InforcerDocModel:** Moves the 2-second load into the hot path. Load once in Import-InforcerSettingsCatalog; ConvertTo-InforcerDocModel reads from the in-memory hashtable only.
- **Regular @{} for product/category grouping:** Produces non-deterministic key order; different TOC ordering per run; breaks document diffs.
- **Using ConvertFrom-Json without -Depth 100:** Silently truncates Settings Catalog policyData at default depth 2. Always use -Depth 100.
- **String += in loops:** Never accumulate strings with += in any loop. The performance skill explicitly forbids this — use StringBuilder or List[string] with -join.
- **Array += in loops:** Never use @() += pattern. Use [System.Collections.Generic.List[object]]::new() with .Add().
- **Calling Get-* cmdlets in ConvertTo-InforcerDocModel:** No API calls in the normalization stage. All data must be in the DocData bundle from Stage 1.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Ordered key iteration | Custom sort logic on hashtables | `[ordered]@{}` / `[System.Collections.Specialized.OrderedDictionary]` | Native PowerShell ordered dict preserves insertion order; no sort code needed |
| JSON depth truncation prevention | Manual depth tracking | `ConvertFrom-Json -Depth 100` / `ConvertTo-Json -Depth 100` | Module convention; handles any nesting depth |
| String assembly | `$str +=` accumulation | `[System.Text.StringBuilder]` | O(1) vs O(n²); critical for HTML rendering in later phases; establish the pattern here |
| Array collection in loops | `@()` and `+=` | `[System.Collections.Generic.List[object]]::new()` | No repeated array allocation; module convention from performance skill |
| Session guard | Manual $script:InforcerSession check | `Test-InforcerSession` | Already implemented; consistent error message |
| TenantId resolution | Custom parsing of numeric/GUID/name | `Resolve-InforcerTenantId` | Already handles all 3 forms |
| PolicyName fallback | One-off null coalescing | Mirror the chain in `Add-InforcerPropertyAliases` (ObjectType Policy) | Established canonical resolution already tested |

**Key insight:** The module's private helper library already handles session, ID resolution, and property aliasing. Phase 1 private functions must call these helpers, not duplicate the logic.

---

## Runtime State Inventory

Phase 1 is a code addition — no rename, refactor, or migration. There is no stored data with old identifiers to update. This section is explicitly confirmed as not applicable.

| Category | Items Found | Action Required |
|----------|-------------|-----------------|
| Stored data | None — new code, no existing records | None |
| Live service config | None — new private helpers, not registered services | None |
| OS-registered state | None | None |
| Secrets/env vars | None — uses existing $script:InforcerSession | None |
| Build artifacts | None — adding new .ps1 files only | None |

---

## Common Pitfalls

### Pitfall 1: Missing ChoiceSettingInstance Children

**What goes wrong:** The resolver handles the top-level `choiceSettingValue.value` but ignores `choiceSettingValue.children[]`. In real data, many ChoiceSettingInstances have non-empty children arrays representing dependent sub-settings (e.g., enabling a feature exposes additional configuration options).

**Why it happens:** Happy-path testing only uses policies where the choice has no children. The 50 Settings Catalog policies in sample data contain many choices with children.

**How to avoid:** The recursive traversal (Pattern 3) must pass `children[]` back through the same traversal function at Depth+1.

**Warning signs:** Generated documentation is missing sub-settings for enabled features. Compare setting count in output vs `settingCount` field in policyData.

### Pitfall 2: GroupSettingCollectionInstance Requires Multi-Level Recursion

**What goes wrong:** A `GroupSettingCollectionInstance` contains `groupSettingCollectionValue[]`, each element of which has a `children[]` array. Those children can themselves be `GroupSettingCollectionInstance` objects (confirmed in real data: LocalUsersAndGroups policy nests group within group).

**Why it happens:** The pattern looks like one level of indirection but is actually unbounded depth.

**How to avoid:** The traversal function (Pattern 3) must call itself recursively for any child regardless of its odata.type. The Depth parameter tracks indentation for the output rows.

**Warning signs:** Policies like LocalUsersAndGroups or LAPS BitLocker settings show only the group header row with no child settings.

### Pitfall 3: ConvertFrom-Json Without -Depth 100 Truncates policyData

**What goes wrong:** The default depth for `ConvertFrom-Json` in PS 7 is 1024 for the basic parser but truncation occurs at depth 2 for complex structures when using -Depth explicitly without 100. The established module convention is always -Depth 100. Forgetting it produces `System.Management.Automation.PSCustomObject` strings instead of nested objects.

**Why it happens:** The import of PoliciesJson string (which is already depth-100 serialized) must be deserialized with matching depth.

**How to avoid:** All `ConvertFrom-Json` calls use `-Depth 100`. All `ConvertTo-Json` calls use `-Depth 100`. This is the module convention — see unified-guardian skill.

**Warning signs:** Check DocModel.Products for any settings row where Value contains "System.Collections" or "PSCustomObject".

### Pitfall 4: Non-Deterministic Product/Category Ordering

**What goes wrong:** Using regular `@{}` for Products and Categories produces different key ordering between runs. Users notice the TOC changes order between documentation runs on the same tenant.

**Why it happens:** PowerShell hashtable key order is hash-bucket dependent, not insertion-order.

**How to avoid:** Use `[ordered]@{}` or `[System.Collections.Specialized.OrderedDictionary]` for all grouping hashtables. The ordering will then match the order policies are encountered in the API response.

**Warning signs:** Two documentation runs on identical input produce different product/category orderings.

### Pitfall 5: Null PolicyName in 63% of Policies

**What goes wrong:** In the sample data, 123 of 194 policies have `name = null`. 50 have `displayName = null` and 50 have `friendlyName = null`. The normalization layer must apply the fallback chain or many policies appear with empty/null names.

**Why it happens:** The Inforcer API returns `null` for `name` on most non-Intune policies. The `friendlyName` field is usually populated and is the most reliable fallback for the Inforcer policy name.

**How to avoid:** Apply the D-13 fallback chain: `displayName → friendlyName → name → policyData.name → policyData.displayName → "Policy {id}"`. This mirrors the existing `Add-InforcerPropertyAliases` logic for ObjectType Policy.

**Warning signs:** Policies appearing with name "Policy {guid}" in the output — usually means displayName and friendlyName were both null and only the ID fallback was reached.

### Pitfall 6: settings.json Load Creates Module/data Directory That Doesn't Exist Yet

**What goes wrong:** `Import-InforcerSettingsCatalog` points to `module/data/settings.json` but the `module/data/` directory does not exist yet in the repo. The copy of settings.json must be placed there as part of Phase 1.

**Why it happens:** The directory isn't created until someone creates a file in it.

**How to avoid:** Phase 1 must include a task to copy settings.json from the sibling IntuneSettingsCatalogViewer repo to `module/data/settings.json`. Verify the directory exists and the file is present before writing tests.

**Warning signs:** `Import-InforcerSettingsCatalog` fails with "Cannot find path" on first run.

### Pitfall 7: ChoiceSettingCollectionInstance Not in Sample Data

**What goes wrong:** SCAT-06 requires handling 5 types, but only 4 appear in the 194-policy sample dataset. `ChoiceSettingCollectionInstance` (0 occurrences in sample) still must be implemented per spec.

**Why it happens:** The sample tenant may not have policies using this type. It is used by Endpoint Security catalog policies (e.g., Windows Security Experience profiles).

**How to avoid:** Implement the handler following the `ChoiceSettingCollectionInstance` pattern: each element in `choiceSettingCollectionValue[]` has a `value` field that can be resolved via the catalog's options map. Write a unit test with a hand-crafted fixture object rather than live data.

**Warning signs:** If any live tenant produces `(unhandled type: *ChoiceSettingCollection*)` in the output.

---

## Code Examples

Verified patterns from existing module source:

### Existing Session Guard Pattern (from Get-InforcerTenantPolicies.ps1)

```powershell
if (-not (Test-InforcerSession)) {
    Write-Error -Message 'Not connected yet. Please run Connect-Inforcer first.' -ErrorId 'NotConnected' -Category ConnectionError
    return
}
```

### Existing TenantId Resolution Pattern (from Get-InforcerTenantPolicies.ps1)

```powershell
try {
    $clientTenantId = Resolve-InforcerTenantId -TenantId $TenantId
} catch {
    Write-Error -Message $_.Exception.Message -ErrorId 'InvalidTenantId' -Category InvalidArgument
    return
}
```

### Existing Script-Scope Session Pattern (from Disconnect-Inforcer.ps1)

```powershell
# Clearing session on disconnect
$script:InforcerSession = $null
```

New code must add `$script:InforcerSettingsCatalog = $null` in the same block.

### Existing PolicyName Fallback (from Add-InforcerPropertyAliases.ps1, ObjectType Policy)

```powershell
$policyNameVal = $obj.PSObject.Properties['displayName'].Value -as [string]
if ([string]::IsNullOrWhiteSpace($policyNameVal)) { $policyNameVal = $obj.PSObject.Properties['name'].Value -as [string] }
if ([string]::IsNullOrWhiteSpace($policyNameVal)) { $policyNameVal = $obj.PSObject.Properties['friendlyName'].Value -as [string] }
if ([string]::IsNullOrWhiteSpace($policyNameVal)) {
    $idVal = $obj.PSObject.Properties['id'].Value
    $policyNameVal = "Policy $(if ($null -ne $idVal) { $idVal } else { 'Unknown' })"
}
```

### Category Key Formation (from D-11)

```powershell
function Get-InforcerCategoryKey {
    param([string]$PrimaryGroup, [string]$SecondaryGroup)
    if ([string]::IsNullOrWhiteSpace($SecondaryGroup) -or
        $SecondaryGroup -eq $PrimaryGroup -or
        $SecondaryGroup -eq 'All') {
        return $PrimaryGroup
    }
    return "$PrimaryGroup / $SecondaryGroup"
}
```

### settings.json Structure (verified from IntuneSettingsCatalogViewer/data/settings.json)

```json
{
  "@odata.type": "#microsoft.graph.deviceManagementConfigurationChoiceSettingDefinition",
  "id": "sirisettings_enabled",
  "displayName": "Enabled",
  "description": "...",
  "options": [
    { "itemId": "sirisettings_enabled_false", "displayName": "Disabled" },
    { "itemId": "sirisettings_enabled_true",  "displayName": "Enabled"  }
  ]
}
```

Catalog lookup key: `settings.json[entry.id]`. Option lookup: `entry.options[n].itemId` → `entry.options[n].displayName`.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| One-time string concat (`$html +=`) | `[System.Text.StringBuilder]` | Established in performance skill | 55x faster; required for HTML renderer phase |
| `@()` arrays with `+=` | `[System.Collections.Generic.List[object]]` | Established in performance skill | No GC pressure from repeated array allocation |
| Separate loops over same collection | Single-pass with conditional branching | Established in performance skill | Fewer iterations; matters with 745+ settings |
| `Where-Object` for hashtable lookups | Pre-built hashtable with direct indexing | Established in performance skill | O(1) vs O(n) for catalog lookup; critical for 17,785 entries |

---

## Open Questions

1. **settings.json bundling — module size impact**
   - What we know: settings.json is 62.5 MB. Module data/ directory does not yet exist. D-01 locks the decision to bundle.
   - What's unclear: The PITFALLS.md document (written before CONTEXT.md) recommends NOT bundling due to install size. CONTEXT.md D-01 explicitly locks "bundle a copy in module/data/". STATE.md also shows an initial decision to NOT bundle (reference sibling repo).
   - Recommendation: CONTEXT.md is the most recent binding document — honor D-01 and bundle. The planner should note this size tradeoff in the Phase 3 module integration plan where packaging decisions are made.

2. **5th settingInstance type (ChoiceSettingCollectionInstance) — no sample data**
   - What we know: 0 occurrences in the 194-policy sample. Required by SCAT-06.
   - What's unclear: Exact structure of `choiceSettingCollectionValue[]` elements.
   - Recommendation: Implement based on the MS Graph API spec pattern (array of choice values, each with a `value` field resolving to an itemId in the catalog options). Write a fixture-based unit test rather than relying on live data.

3. **Disconnect-Inforcer settings catalog cleanup scope**
   - What we know: `$script:InforcerSettingsCatalog = $null` must be added to Disconnect-Inforcer.
   - What's unclear: Whether it belongs in `module/Public/Disconnect-Inforcer.ps1` directly or in a new private helper that both session management and catalog management can call.
   - Recommendation: Add directly to Disconnect-Inforcer.ps1 as a one-liner, same pattern as `$script:InforcerSession = $null`. Keep it simple.

---

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| PowerShell 7.0+ | All new Private helpers | Yes (module requirement) | 7.x | None — module requires PS 7+ |
| IntuneSettingsCatalogViewer/data/settings.json | Import-InforcerSettingsCatalog (initial copy) | Yes | 17,785 entries | None — must bundle |
| scripts/sample-data/tenant-policies.json | Unit/integration testing | Yes (1.4 MB, 194 policies) | Current | None — already present |
| Pester 5.x | Tests/Consistency.Tests.ps1 | Yes (already in use) | 5.x | None needed |

**Missing dependencies with no fallback:** None. All required dependencies confirmed available.

---

## Project Constraints (from CLAUDE.md)

- **Skill chain:** Any code change triggers: inforcer-unified-guardian → inforcer-performance-maintenance → inforcer-docs-maintenance (in this order)
- **Parameter order:** Format → TenantId → Tag → OutputType — all new Public cmdlets must follow this
- **Property aliases:** PascalCase via `Add-InforcerPropertyAliases` — new object types need entries here
- **JSON depth:** Always 100 — every `ConvertTo-Json` and `ConvertFrom-Json` uses -Depth 100
- **Auth pattern:** Session-based (`$script:InforcerSession`) — all data cmdlets call `Test-InforcerSession` first
- **Private helpers:** Go in `module/Private/`; dot-sourced by InforcerCommunity.psm1
- **Error handling:** Session/auth → non-terminating (Write-Error + return); invalid input → terminating; API failures → non-terminating
- **No += on arrays in loops** — use `[System.Collections.Generic.List[object]]`
- **No DEV/UAT/staging URLs or API keys** in committed files
- **PSTypeName required** on all output objects with Format.ps1xml view
- **Suppress function output:** Always use `$null = Add-InforcerPropertyAliases ...`
- **Consistency tests** must be updated for any new exported cmdlet

**Note for Phase 1:** Phase 1 creates only Private helpers — no new Public cmdlets. The unified-guardian consistency contract checklist applies to Private helpers only for parameter naming conventions. No FunctionsToExport or Format.ps1xml update is needed in Phase 1. Those are Phase 3 concerns.

---

## Sources

### Primary (HIGH confidence)

- Inspected directly: `scripts/sample-data/tenant-policies.json` — 194 real policies, measured odata.type distribution, confirmed policyData shapes for types 1, 3, 10, 12, 14, 70
- Inspected directly: `../IntuneSettingsCatalogViewer/data/settings.json` — 17,785 entries, confirmed `id`/`displayName`/`options[]`/`@odata.type` structure
- Inspected directly: `module/Private/Add-InforcerPropertyAliases.ps1` — canonical PolicyName fallback chain
- Inspected directly: `module/Public/Get-InforcerTenantPolicies.ps1` — session guard, TenantId resolution, EnrichPolicyObject pattern
- Inspected directly: `module/Public/Disconnect-Inforcer.ps1` — $script:InforcerSession = $null pattern
- Inspected directly: `.claude/skills/inforcer-unified-guardian/SKILL.md` — consistency contract, parameter rules, error handling conventions
- Inspected directly: `.claude/skills/inforcer-performance-maintenance/SKILL.md` — List[object], no +=, hashtable lookups, StringBuilder
- Inspected directly: `.planning/research/ARCHITECTURE.md` — component boundaries, file locations, build order, anti-patterns
- Inspected directly: `.planning/research/PITFALLS.md` — measured benchmarks (StringBuilder 55x, ConvertFrom-Json ~2s), type distribution, null displayName stats

### Secondary (MEDIUM confidence)

- `.planning/phases/01-data-pipeline-and-normalization/01-CONTEXT.md` — all D-01 through D-15 decisions; current research confirms decisions are valid against live sample data

### Tertiary (LOW confidence)

- None — all claims verified against source code or live data files

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all libraries are built-in PowerShell/.NET; no external packages to evaluate
- Architecture: HIGH — verified against ARCHITECTURE.md (which was itself derived from direct code inspection) and confirmed against real data shapes
- Pitfalls: HIGH — all verified against live 194-policy sample data or measured benchmarks from PITFALLS.md
- settingInstance traversal: HIGH for 4 confirmed types; MEDIUM for ChoiceSettingCollectionInstance (no sample data, implementation based on type pattern)

**Research date:** 2026-04-01
**Valid until:** 2026-05-01 (settings.json entries grow as Microsoft adds new Intune settings; code patterns are stable)
