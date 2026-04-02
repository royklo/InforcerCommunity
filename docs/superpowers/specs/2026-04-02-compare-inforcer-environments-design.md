# Compare-InforcerEnvironments — Design Specification

## Summary

A new public cmdlet `Compare-InforcerEnvironments` for the InforcerCommunity module that compares the policy configuration of two M365 environments (tenant-to-tenant, baseline-to-tenant, baseline-to-baseline, or tenant-to-baseline) and produces a self-contained HTML report showing alignment, conflicts, and items requiring manual review.

**Core Value:** IT consultants performing onboarding or alignment projects can generate a complete comparison report in one command — seeing what matches, what conflicts, what's missing, and what needs manual inspection — without manually cross-referencing two tenant configurations.

## Constraints

- PowerShell 7.0+, no external module dependencies for core output (HTML)
- Must follow InforcerCommunity consistency contract (parameter order, property aliases, error handling)
- HTML output must be self-contained (embedded CSS, no CDN, no external files)
- Must match the visual style of `Export-InforcerTenantDocumentation` HTML output
- Settings Catalog resolution uses the same IntuneSettingsCatalogViewer dataset
- Must support cross-account comparison (two different Inforcer API keys)

## Parameters

```
Compare-InforcerEnvironments
    [-SourceTenantId] <object>          # Numeric ID, GUID, or friendly name
    [-DestinationTenantId] <object>     # Numeric ID, GUID, or friendly name
    [-SourceSession] <hashtable>        # Session object from Connect-Inforcer -PassThru
    [-DestinationSession] <hashtable>   # Session object from Connect-Inforcer -PassThru
    [-SourceBaselineId] <string>        # GUID or baseline name (use baseline policies as source)
    [-DestinationBaselineId] <string>   # GUID or baseline name (use baseline policies as destination)
    [-IncludingAssignments]             # Switch — fetch and display Graph assignment data (informational only, not scored)
    [-SettingsCatalogPath] <string>     # Path to settings.json (auto-discovers sibling repo if omitted)
    [-OutputPath] <string>              # Directory for HTML output file
```

**Parameter order note:** This cmdlet intentionally departs from the module's standard `Format → TenantId → Tag → OutputType` convention because it is a `Compare-` verb (not `Get-`/`Export-`) and requires source/destination pairs as its primary inputs. The standard parameters (`Format`, `OutputType`) are not present in v1 (HTML-only). If future formats are added, `-Format` should be inserted as the first parameter to align with convention.

### Parameter Sets

1. **TenantToTenant**: `-SourceTenantId` + `-DestinationTenantId` (same or different sessions)
2. **BaselineToTenant**: `-SourceBaselineId` + `-DestinationTenantId`
3. **TenantToBaseline**: `-SourceTenantId` + `-DestinationBaselineId`
4. **BaselineToBaseline**: `-SourceBaselineId` + `-DestinationBaselineId`

When `-SourceSession` or `-DestinationSession` is omitted, the cmdlet uses `$script:InforcerSession` (the current connection) for that side. This means same-account comparisons work without passing any session objects.

### Connect-Inforcer Change

Add a `-PassThru` switch to `Connect-Inforcer` that returns the session object in addition to storing it in `$script:InforcerSession`. This enables:

```powershell
$source = Connect-Inforcer -ApiKey $key1 -Region uk -PassThru
$dest   = Connect-Inforcer -ApiKey $key2 -Region eu -PassThru
Compare-InforcerEnvironments -SourceTenantId 'Contoso' -DestinationTenantId 'Fabrikam' `
    -SourceSession $source -DestinationSession $dest -OutputPath ./reports
```

## Architecture

Pipeline pattern matching `Export-InforcerTenantDocumentation`:

```
Compare-InforcerEnvironments (public)
    → Get-InforcerComparisonData (private)      — fetch policies from both environments
    → ConvertTo-InforcerComparisonModel (private) — build comparison model
    → ConvertTo-InforcerComparisonHtml (private)  — render HTML report
```

### Stage 1: Get-InforcerComparisonData

**Input:** Source/destination identifiers + session objects

**Cross-session mechanism:** All existing cmdlets (`Get-InforcerTenantPolicies`, `Resolve-InforcerTenantId`, etc.) read from `$script:InforcerSession` directly. To support cross-account comparison without modifying every existing cmdlet, `Get-InforcerComparisonData` temporarily swaps `$script:InforcerSession` before each call and restores it afterward:

```powershell
# Save current session
$originalSession = $script:InforcerSession
try {
    # Fetch source data
    $script:InforcerSession = $SourceSession
    $sourcePolicies = Get-InforcerTenantPolicies -TenantId $SourceTenantId -OutputType PowerShellObject

    # Fetch destination data
    $script:InforcerSession = $DestinationSession
    $destPolicies = Get-InforcerTenantPolicies -TenantId $DestinationTenantId -OutputType PowerShellObject
} finally {
    # Always restore
    $script:InforcerSession = $originalSession
}
```

This is a low-risk approach: no changes to existing cmdlets, the swap is scoped within a `try/finally`, and the original session is always restored. The trade-off is that it is not thread-safe, but PowerShell module-scoped variables are inherently single-threaded per runspace.

**Process:**
1. Resolve tenant IDs and/or baseline IDs using existing helpers (`Resolve-InforcerTenantId`, `Resolve-InforcerBaselineId`) — with session swapped to the appropriate side
2. Fetch policies for source environment:
   - If baseline: call `Get-InforcerBaseline` to get the baseline's `baselineTenantId`, then call `Get-InforcerTenantPolicies` with that tenant ID to get the baseline's policies
   - If tenant: call `Get-InforcerTenantPolicies` directly with the tenant ID
3. Fetch policies for destination environment (same logic, swapped to destination session)
4. Load Settings Catalog lookup table via `Import-InforcerSettingsCatalog` (once, shared — does not depend on session)

**Output:** Hashtable with `SourcePolicies`, `DestinationPolicies`, `SourceName`, `DestinationName`, `SourceType` (Baseline/Tenant), `DestinationType`, `SettingsCatalog`, `CollectedAt`

### Stage 2: ConvertTo-InforcerComparisonModel

**Input:** Output from Stage 1

**Process — two comparison strategies:**

#### Strategy A: Intune Settings Catalog Policies (have settingDefinitionIDs)

Compare at the **individual setting level**, not the policy level:

1. From source policies, extract all settings as `{ settingDefinitionId, value, policyName }` tuples
2. From destination policies, extract the same
3. Build a lookup keyed by `settingDefinitionId`
4. For each unique settingDefinitionId across both environments:
   - **Matched**: same settingDefinitionId exists in both, values are equal → record source policy name, dest policy name
   - **Conflicting**: same settingDefinitionId exists in both, values differ → record both values and both policy names
   - **Source Only**: settingDefinitionId exists only in source
   - **Destination Only**: settingDefinitionId exists only in destination
5. Resolve settingDefinitionIds to friendly names via the Settings Catalog lookup

This correctly handles the case where Setting A is in Policy 1 in tenant A and Policy 5 in tenant B — it's still aligned because the setting-level match is what matters.

#### Strategy B: Non-Settings-Catalog Policies (including Administrative Templates)

Compare at the **policy level** using the match key: `PolicyTypeId + Product + PrimaryGroup + PolicyName` (case-insensitive):

1. Build a dictionary of source policies keyed by match key
2. Build a dictionary of destination policies keyed by match key
3. For each unique match key:
   - **Matched**: exists in both, policy data is equivalent
   - **Conflicting**: exists in both, policy data differs (surface the differing properties)
   - **Source Only**: exists only in source
   - **Destination Only**: exists only in destination

This applies to **all** non-Settings-Catalog policies, including Intune Administrative Templates. If both the source and destination have an Admin Template with the same match key, they can be compared at the policy level — the flat JSON properties can be diffed directly. Admin Templates are only a problem when you try to compare them against Settings Catalog policies, not against each other.

#### Manual Review Classification

A policy is classified as **manual review** only when automated comparison is not possible:

1. **Cross-structure mismatch**: An Intune policy area where one side uses Settings Catalog and the other uses Administrative Templates. The JSON structures are entirely different and have no comparable properties.
2. **Unmatched Admin Templates**: An Administrative Template that has no match-key counterpart in the other environment AND exists in a product area where the other side has Settings Catalog policies. The consultant needs to determine whether the Settings Catalog policies on the other side cover the same functionality.
3. **Unmatched with ambiguity**: Any unmatched policy where the comparison engine cannot confidently classify it as simply "source only" or "destination only" because of structural differences in the same area.

Policies that are clearly source-only or destination-only (no structural ambiguity) remain in the Comparison tab, not in Manual Review.

**Output — ComparisonModel:**
```
@{
    SourceName       = 'Contoso Production'
    DestinationName  = 'Fabrikam Ltd'
    SourceType       = 'Baseline'   # or 'Tenant'
    DestinationType  = 'Tenant'     # or 'Baseline'
    GeneratedAt      = [datetime]
    AlignmentScore   = 78.2         # (matched / total unique items) × 100
    TotalItems       = 527
    Counters         = @{ Matched = 412; Conflicting = 38; SourceOnly = 52; DestOnly = 25; Manual = 14 }
    Products         = [OrderedDictionary] @{
        'Intune' = @{
            Counters   = @{ Matched = 298; Conflicting = 24; SourceOnly = 31; DestOnly = 12 }
            Categories = [OrderedDictionary] @{
                'Device Configuration / Security' = @{
                    ComparisonRows = @(
                        @{
                            Status           = 'Matched'  # Matched|Conflicting|SourceOnly|DestOnly
                            ItemType         = 'Setting'  # Setting (Intune SC) or Policy (non-SC)
                            Name             = 'Require BitLocker encryption'
                            SourcePolicy     = 'Security Baseline v3'
                            SourceValue      = 'Enabled'
                            DestPolicy       = 'Endpoint Protection Policy'
                            DestValue        = 'Enabled'
                            SourceAssignment = 'All Users'      # Only populated when -IncludingAssignments
                            DestAssignment   = 'All Devices'    # Only populated when -IncludingAssignments
                        }
                        # ...more rows
                    )
                }
            }
        }
    }
    ManualReview     = [OrderedDictionary] @{
        'Intune' = @{
            Count      = 11
            Categories = [OrderedDictionary] @{
                'Endpoint Security / Firewall' = @(
                    @{
                        Environment = 'Source'   # Source or Destination
                        PolicyName  = 'Firewall Configuration v2'
                        PolicyType  = 'Administrative Template'
                        Reason      = 'Administrative Template — flat JSON structure, cannot auto-compare with Settings Catalog'
                    }
                    @{
                        Environment = 'Destination'
                        PolicyName  = 'Firewall Configuration'
                        PolicyType  = 'Administrative Template'
                        Reason      = 'Administrative Template — flat JSON structure, cannot auto-compare with Settings Catalog'
                    }
                )
            }
        }
    }
}
```

### Stage 3: ConvertTo-InforcerComparisonHtml

**Input:** ComparisonModel from Stage 2

**Process:**
- StringBuilder assembly (no string concatenation in loops)
- Reuse CSS custom properties from `ConvertTo-InforcerHtml` (same color tokens, radius, shadows, typography)
- Embedded CSS + minimal JS in `<style>` and `<script>` blocks (self-contained)

**HTML Structure:**
1. **Notch bar** — fixed at top, shows item count and manual review count
2. **Header** — centered: title, source → destination with type labels, generated timestamp
3. **Alignment score card** — large percentage with animated loading bar (JS counter + bar sync'd)
4. **Summary tiles** — 5-column grid: Matched (green), Conflicting (red), Source Only (yellow), Destination Only (blue), Manual Review (purple)
5. **Search bar** — full-width between counters and tabs, filters product sections
6. **Tabs** — "Comparison" and "Manual Review" (with badge count)
7. **Comparison tab** — `<details>` per product with status badge counts in summary, `<h3>` per category, comparison tables per category
8. **Manual Review tab** — same product/category structure, table per category with columns: Environment, Policy Name, Policy Type, Reason — each policy is its own row, no assumptions about relationships
9. **Floating buttons** — back-to-top (appears on scroll), dark/light mode toggle
10. **Footer** — cmdlet name + module version

**Comparison table columns (Intune Settings Catalog):**
| Status | Setting | Source Policy | Source Value | Dest Policy | Dest Value |

With `-IncludingAssignments`:
| Status | Setting | Source Policy | Source Value | Source Assignment | Dest Policy | Dest Value | Dest Assignment |

**Comparison table columns (non-Settings-Catalog):**
| Status | Policy | Source | Destination |

With `-IncludingAssignments`:
| Status | Policy | Source | Source Assignment | Destination | Dest Assignment |

**Manual review table columns:**
| Environment | Policy Name | Policy Type | Reason |

**Visual status indicators:**
- Matched: green checkmark badge
- Conflicting: red cross badge (destination value highlighted in red)
- Source Only: yellow "Source Only" badge, destination columns show "Not configured" in muted italic
- Destination Only: blue "Dest Only" badge, source columns show "Not configured" in muted italic

**Dark/light mode:** Same approach as doc export — CSS custom properties with `prefers-color-scheme` media query + manual toggle via `classList.add('dark'/'light')` with `localStorage` persistence.

## Alignment Score Calculation

```
alignment_percentage = (total_matched / total_unique_items) × 100
```

Where `total_unique_items` = matched + conflicting + source_only + destination_only (manual review items are excluded from the score since they can't be assessed).

For Intune Settings Catalog, each unique `settingDefinitionId` counts as one item. For non-Settings-Catalog policies, each unique policy (by match key) counts as one item.

## File Layout

```
module/
├── Public/
│   └── Compare-InforcerEnvironments.ps1    # Public cmdlet
├── Private/
│   ├── Get-InforcerComparisonData.ps1      # Stage 1: data collection
│   ├── ConvertTo-InforcerComparisonModel.ps1  # Stage 2: comparison engine
│   └── ConvertTo-InforcerComparisonHtml.ps1   # Stage 3: HTML renderer
```

## Changes to Existing Files

1. **`Connect-Inforcer.ps1`** — Add `-PassThru` [switch] parameter. When set, output the session hashtable to the pipeline in addition to storing it in `$script:InforcerSession`.
2. **`InforcerCommunity.psd1`** — Add `Compare-InforcerEnvironments` to `FunctionsToExport`.
3. **`Tests/Consistency.Tests.ps1`** — Add test coverage for the new cmdlet (parameter order, property aliases, etc.).

## Settings Catalog Detection Logic

To determine if an Intune policy is a Settings Catalog policy (and therefore auto-comparable at the setting level):

1. Check if `policyData` contains properties with keys matching settingDefinitionId patterns (typically contain `_` separators and long dotted paths like `device_vendor_msft_...`)
2. Cross-reference against the loaded settings.json lookup — if any property key resolves to an entry in the catalog, it's a Settings Catalog policy
3. If no properties match the catalog: classify as non-Settings-Catalog (Administrative Template / flat JSON) → manual review

## Edge Cases

- **Missing Settings Catalog file**: Degrade gracefully — compare Intune policies at the policy level (like non-SC) instead of setting level. Warn the user that setting-level comparison is unavailable.
- **Empty environment**: If one side has zero policies, all items from the other side are classified as source-only or destination-only.
- **Identical environments**: 100% alignment score, all items matched, no conflicts.
- **No `-SourceSession`/`-DestinationSession`**: Both sides use `$script:InforcerSession`. Works for comparing two tenants under the same API key.
- **Same tenant compared to itself**: Valid use case (sanity check). Should show 100% alignment.
- **`-IncludingAssignments` without Graph connection**: Write-Warning and continue without assignment columns — don't fail the comparison.

## Assignment Display (`-IncludingAssignments`)

When `-IncludingAssignments` is specified:

1. **Data collection**: Stage 1 fetches assignment data from the Graph API for each policy (requires `Connect-Inforcer -FetchGraphData` on the relevant sessions)
2. **Model**: Each `ComparisonRow` gains `SourceAssignment` and `DestAssignment` string properties (comma-separated group/user targets)
3. **HTML rendering**: The comparison tables gain two additional columns: "Source Assignment" and "Dest Assignment"
4. **NOT scored**: Assignments are purely informational — they do not affect the alignment score, do not contribute to matched/conflicting/source-only/dest-only counts, and are never flagged as conflicts. The purpose is to give consultants a heads-up about the impact scope of each policy.
5. **Error handling**: If `-IncludingAssignments` is used but the session was not connected with `-FetchGraphData`, Write-Warning and continue without assignment data (don't fail the whole comparison).

Without `-IncludingAssignments`, the assignment columns are omitted entirely from the HTML output.

## Out of Scope (v1)

- Non-HTML output formats (Markdown, JSON, CSV) — can be added later following the same renderer pattern
- Interactive policy deployment/remediation from the report
- Sidebar navigation (keep the simpler tab-based layout for v1)
