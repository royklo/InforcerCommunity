# Compare-InforcerEnvironments — Deferred Scope

These features were designed and initially implemented but deferred to focus v1 exclusively on Intune Settings Catalog comparison.

## Deferred: Non-Intune Policy Comparison (Strategy B)

Policy-level comparison using match key `PolicyTypeId + Product + PrimaryGroup + PolicyName` (case-insensitive) for non-Settings-Catalog policies (Entra ID Conditional Access, Exchange Online, SharePoint, etc.).

**How it worked:**
- Build dictionary of source/destination policies keyed by match key
- Compare policyData JSON for equivalence
- Matched (identical JSON), Conflicting (different JSON), SourceOnly, DestOnly

**Why deferred:** The real value of this cmdlet is setting-level comparison for Intune Settings Catalog, which the existing alignment API cannot do. Non-Intune policy comparison can be added later using the same pipeline architecture.

## Deferred: Manual Review Tab

A separate tab for policies that can't be auto-compared — specifically Administrative Templates (flat JSON) in areas where the other environment uses Settings Catalog policies.

**How it worked:**
- Detect unmatched non-SC policies in product/category areas that also have SC policies
- List each policy individually with Environment, PolicyName, PolicyType, Reason columns
- No assumptions about which source/destination policies relate to each other

**Why deferred:** Depends on non-Intune comparison being active. Will be re-added when Strategy B returns.

## Deferred: Non-HTML Output Formats

Markdown, JSON, CSV renderers following the same pattern as Export-InforcerTenantDocumentation.

## Re-implementation Notes

The original code for Strategy B and Manual Review was in `ConvertTo-InforcerComparisonModel.ps1`. The git history on `feature/compare-environments` (commit `e9de4ba`) contains the full implementation with 25 unit tests. The HTML renderer (commit `2aa76bf`) also had the Manual Review tab rendering logic.
