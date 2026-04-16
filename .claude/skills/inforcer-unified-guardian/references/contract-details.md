# Inforcer Unified Guardian — Contract Details

This file contains the detailed property tables and PowerShell patterns referenced by the main SKILL.md.

## Standard Property Names (PascalCase Aliases)

### Tenant
ClientTenantId, MsTenantId, TenantFriendlyName, TenantDnsName, SecureScore, IsBaseline, LastBackupTimestamp, RecentChanges; licenses (comma-separated string from API array); PolicyDiff when available. (PolicyDiffFormatted removed — recentChanges is an integer, not a structured object.)

### Baseline
BaselineId (id), BaselineName (name), BaselineClientTenantId, BaselineTenantFriendlyName, BaselineTenantDnsName, BaselineMsTenantId, AlignedThreshold, SemiAlignedThreshold; members array each get Tenant aliases.

### Policy
PolicyId (id), PolicyName (displayName/name), PolicyTypeId, FriendlyName, ReadOnly, Product, PrimaryGroup, SecondaryGroup, Platform, PolicyCategoryId, Tags (comma-separated string from policyTags array via EnrichPolicyObject), TagsArray (original array preserved), policyData (full nested object, shown as compact JSON in default view).

### AlignmentScore
TenantId, TenantFriendlyName, Score, BaselineGroupId, BaselineGroupName, LastComparisonDateTime.

### AlignmentDetail
Top-level: AlignmentScore, BaselineTenantId, SubjectTenantId, SubjectDataTimestamp, BaselineDataTimestamp, CompletedAt.
Metrics (nested object): TotalPolicies, MatchedPolicies, MatchedWithAcceptedDeviations, DeviatedPolicies, RecommendedPoliciesFromBaseline, CustomerOnlyPolicies.
Per-policy (matchedPolicies/deviatedUnaccepted arrays): PolicyName, Product, PrimaryGroup, SecondaryGroup, Platform, PolicyTypeId, InforcerPolicyTypeName, PolicyCategoryId, IsDeviation, IsMissingFromSubject, IsAdditionalInSubject, ReadOnly.

### AuditEvent
CorrelationId, ClientId, RelType, RelId, EventType, Message, Code, User, Timestamp; metadata kept on object (not removed — contains event-type-specific data). Flattened top-level properties added: ClientIpv4, ClientIpv6, UserName, UserDisplayName. nameLookup matching uses `user:username:*` / `user:displayName:*` patterns only (not broad regex). Format.ps1xml controls which fields show by default.

### UserSummary
13 aliases: Id, DisplayName, UserPrincipalName, UserType, JobTitle, Department, Groups, Roles, AssignedLicenses, IsGlobalAdmin, IsAccountEnabled, IsMfaRegistered, IsMfaCapable.

### User
All UserSummary aliases plus ~40 detail aliases (GivenName, Surname, Mail, AccountEnabled, OnPremises*, Manager, Groups, Devices, Roles, AppRoleAssignments, IsCloudOnly, IsHybrid, Risk*, etc.) — nested objects left as-is.

### GroupSummary
PascalCase aliases for list endpoint fields (Id, DisplayName, GroupType, MembershipType, etc.).

### Group
GroupSummary aliases plus detail fields (Members array, Description, etc.).

### Role
PascalCase aliases for directory role definition fields (Id, DisplayName, Description, IsBuiltIn, IsEnabled, IsPrivileged, etc.).

## Module Structure

```
module/
├── InforcerCommunity.psd1
├── InforcerCommunity.psm1
├── Private/
│   ├── # Core infrastructure
│   ├── Invoke-InforcerApiRequest.ps1         # REST client (Invoke-RestMethod, Depth 100)
│   ├── Test-InforcerSession.ps1              # Session guard
│   ├── Get-InforcerBaseUrl.ps1               # Region → base URL mapping
│   ├── ConvertFrom-InforcerSecureString.ps1  # BSTR SecureString → plaintext
│   ├── Filter-InforcerResponse.ps1           # OutputType routing (PSObject/JsonObject)
│   ├── ConvertTo-InforcerArray.ps1           # Array normalization helper
│   ├── # Resolution helpers
│   ├── Resolve-InforcerTenantId.ps1          # ID/GUID/name → numeric tenant ID
│   ├── Resolve-InforcerBaselineId.ps1        # Name/GUID → baseline GUID
│   ├── Resolve-InforcerAssignments.ps1       # Raw assignments → structured objects
│   ├── Resolve-InforcerSettingName.ps1       # settingDefinitionId → friendly name
│   ├── # Property / display helpers
│   ├── Add-InforcerPropertyAliases.ps1       # PascalCase aliases per ObjectType
│   ├── Get-InforcerPolicyDisplayInfo.ps1     # Category mapping (Intune + non-Intune)
│   ├── # Settings Catalog
│   ├── Get-InforcerSettingsCatalogPath.ps1   # 6-tier cache (download from GitHub)
│   ├── Import-InforcerSettingsCatalog.ps1    # Loads settings.json + categories.json
│   ├── # DocModel pipeline (Export + Compare)
│   ├── Get-InforcerDocData.ps1               # Stage 0: raw data collection
│   ├── ConvertTo-InforcerDocModel.ps1        # Stage 1: normalize → Products/Categories/Policies
│   ├── ConvertTo-InforcerSettingRows.ps1     # SC setting extraction (+ ConvertTo-FlatSettingRows)
│   ├── # Export renderers
│   ├── ConvertTo-InforcerHtml.ps1            # Tenant doc → HTML
│   ├── ConvertTo-InforcerMarkdown.ps1        # Tenant doc → Markdown
│   ├── Export-InforcerDocExcel.ps1           # Tenant doc → Excel (requires ImportExcel)
│   ├── # Comparison pipeline
│   ├── Get-InforcerComparisonData.ps1        # Stage 1: collect two DocModels via session swap
│   ├── Compare-InforcerDocModels.ps1         # Stage 2: diff two DocModels → ComparisonModel
│   ├── ConvertTo-InforcerComparisonHtml.ps1  # Stage 3: ComparisonModel → HTML report
│   ├── Format-InforcerAssignmentString.ps1   # DocModel assignments → display string
│   ├── Resolve-InforcerGroupId.ps1            # Group GUID/name → GUID resolution
│   ├── # Graph enrichment (optional, via -FetchGraphData)
│   ├── Connect-InforcerGraph.ps1             # Graph auth (session reuse, disconnect before tenant switch)
│   ├── Invoke-InforcerGraphRequest.ps1       # Graph API client (paged collection support)
│   └── Resolve-InforcerGraphEnrichment.ps1   # Batch Graph enrichment (groups, filters, scope tags, compliance rules)
├── Public/
│   ├── Connect-Inforcer.ps1                  # -PassThru for cross-session comparison
│   ├── Disconnect-Inforcer.ps1
│   ├── Test-InforcerConnection.ps1
│   ├── Get-InforcerTenant.ps1
│   ├── Get-InforcerBaseline.ps1
│   ├── Get-InforcerTenantPolicies.ps1
│   ├── Get-InforcerAlignmentDetails.ps1
│   ├── Get-InforcerAuditEvent.ps1
│   ├── Get-InforcerUser.ps1
│   ├── Get-InforcerGroup.ps1                   # List/ById with pagination, -Search, -Filter
│   ├── Get-InforcerRole.ps1                    # Directory role definitions
│   ├── Get-InforcerSupportedEventType.ps1
│   ├── Export-InforcerTenantDocumentation.ps1  # Utility: multi-format tenant docs
│   └── Compare-InforcerEnvironments.ps1        # Utility: cross-tenant comparison report
├── InforcerCommunity.Types.ps1xml
├── InforcerCommunity.Format.ps1xml
└── README.md
```

- `InforcerCommunity.psm1` dot-sources Private then Public.
- Manifest `FunctionsToExport` lists all 14 exported functions.
- Every Public function has comment-based help.
- `Invoke-InforcerApiRequest` uses `Invoke-RestMethod` (not `Invoke-WebRequest`) and `ConvertTo-Json -Depth 100`. Supports `-PreserveStructure` (unwraps .data but keeps inner structure) and `-PreserveFullResponse` (returns raw parsed response, no unwrapping — use when pagination metadata is at response root level alongside .data). Validates response type: string/non-PSObject triggers NonJsonResponse error.
- `Filter-InforcerResponse` must use `ConvertTo-Json -Depth 100`.
- `Resolve-InforcerTenantId` accepts numeric ID, GUID, or tenant name (case-insensitive match on tenantFriendlyName/tenantDnsName). Callers with pre-fetched tenant data should pass `-TenantData` to avoid duplicate API calls.
- `scripts/Test-ApiSchemaChanges.ps1` — API schema drift detection (not part of module, lives in repo root `scripts/`).
- `docs/api-schema-snapshot.json` — machine-generated schema baseline (never hand-edit; regenerate with `Test-ApiSchemaChanges.ps1 -Update`).

## DocModel Pipeline (Export + Compare)

Both `Export-InforcerTenantDocumentation` and `Compare-InforcerEnvironments` share a common data pipeline:

```
Get-InforcerDocData → ConvertTo-InforcerDocModel → [renderer]
```

**DocModel structure:** `Products (ordered) → Categories (ordered) → Policies (list)`, each policy with `Basics`, `Settings`, `Assignments`, `PolicyTypeId`.

**Settings** come from `ConvertTo-InforcerSettingRows` (SC, policyTypeId 10) or `ConvertTo-FlatSettingRows` (non-SC). Each row: `Name`, `Value`, `Indent`, `IsConfigured`, `DefinitionId`.

**ConvertTo-FlatSettingRows** applies `ConvertTo-FriendlySettingName` to convert camelCase property names to Title Case (e.g., `allowBluetooth` → `Allow Bluetooth`). It also decodes base64-encoded script/rules content (detectionScriptContent, remediationScriptContent, scriptContent, rulesContent) and prefixes with `__SCRIPT_CODE__` marker for renderers to detect.

**-ComparisonMode** on `ConvertTo-InforcerDocModel` filters to Intune-relevant products (`intune`, `windows`, `macos`, `ios`, `android`, `defender`) and excludes exchange categories. Also resolves GUIDs in CA policy settings using a unified `$resolveGuid` helper across GroupNameMap, RoleNameMap, LocationNameMap, AppNameMap.

**Compare pipeline:** `Get-InforcerComparisonData` calls `Get-InforcerDocData` twice with session swapping, enriches via `$enrichComplianceData` helper (shared for src/dst), then `Compare-InforcerDocModels` diffs the two DocModels. Disambiguation uses `categories.json` CategoryName (e.g., "Trusted Sites Zone > setting name") with defId parsing fallback for firewall profiles.

**HTML renderers** detect `__SCRIPT_CODE__` prefix and render collapsible code blocks with syntax highlighting (PowerShell blue, Bash red, JSON indigo). Both Export and Compare renderers include a GitHub issues link in the footer.

**CRITICAL rules:**
- Never re-implement setting extraction — reuse `ConvertTo-InforcerSettingRows` / `ConvertTo-FlatSettingRows`.
- Never build custom comparison logic — reuse `Compare-InforcerDocModels`.
- Never duplicate src/dst logic — use shared scriptblocks with a `$Label` parameter.
- `Import-InforcerSettingsCatalog` loads both `settings.json` AND `categories.json` for disambiguation.
- The API returns the Defender product as `"Defender"` (not `"Microsoft Defender for Endpoint"`).

## Graph API Enrichment Endpoints

When `-FetchGraphData` is specified, the module supplements Inforcer API data with Microsoft Graph calls. Required scopes: `Directory.Read.All`, `DeviceManagementConfiguration.Read.All`.

### Shared (via Resolve-InforcerGraphEnrichment)
| Endpoint | Version | Purpose |
|----------|---------|---------|
| `POST /v1.0/directoryObjects/getByIds` | v1.0 | Batch resolve group/user ObjectIDs → display names |
| `GET /v1.0/directoryObjects/{oid}` | v1.0 | Fallback individual lookup when batch fails |
| `GET /beta/deviceManagement/assignmentFilters` | beta | Fetch Intune assignment filters (ID → name/rule) |
| `GET /beta/deviceManagement/roleScopeTags` | beta | Fetch scope tags (ID → display name) |
| `GET /beta/deviceManagement/deviceCompliancePolicies('{id}')` | beta | Fetch compliance rules (rulesContent) + script link |

### Export-only (in Export-InforcerTenantDocumentation)
| Endpoint | Version | Purpose |
|----------|---------|---------|
| `GET /v1.0/directoryRoleTemplates` | v1.0 | Resolve CA role GUIDs → role names |
| `GET /v1.0/identity/conditionalAccess/namedLocations` | v1.0 | Resolve CA location GUIDs → location names |
| `GET /v1.0/servicePrincipals(appId='{id}')` | v1.0 | Resolve CA application IDs → app names |

## Pipeline Binding Pattern

For `-TenantId`, use `ValueFromPipelineByPropertyName` (not `ValueFromPipeline`) with `[Alias('ClientTenantId')]` to bind the property by name from piped objects. Using `ValueFromPipeline` on `[object]` would bind the whole object, causing `.ToString()` to fail in `Resolve-InforcerTenantId`.

```powershell
[Parameter(Mandatory, ValueFromPipelineByPropertyName)]
[Alias('ClientTenantId')]
[object]$TenantId
```

## JsonObject Output Pattern

When `-OutputType JsonObject`, skip `Add-InforcerPropertyAliases` and PSTypeName insertion. Aliases add PascalCase duplicates that `ConvertTo-Json` would serialize alongside camelCase originals. Buffer raw API items and convert at the end. For PowerShellObject, add aliases and stream to pipeline immediately.

## Streaming Output Pattern

For paginated List endpoints, stream items to the pipeline as each page arrives (don't buffer into ArrayList). Only buffer when `-OutputType JsonObject` requires building a single JSON string. This reduces memory and shows results immediately.

## Advanced PowerShell Patterns

### Pipeline Support
```powershell
[CmdletBinding()]
param(
    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [object]$TenantId
)
process {
    # Process each piped TenantId
}
```

### Parameter Validation
```powershell
[ValidateNotNullOrEmpty()]
[string]$Name

[ValidateSet('PowerShellObject', 'JsonObject')]
[string]$OutputType = 'PowerShellObject'

[ValidateRange(1, [int]::MaxValue)]
[int]$Count
```

### Comment-Based Help Template
```powershell
<#
.SYNOPSIS
    Gets Inforcer tenants.
.DESCRIPTION
    Retrieves tenant information from the Inforcer API.
.PARAMETER TenantId
    The tenant identifier: numeric Client Tenant ID, Microsoft Tenant ID (GUID), or tenant name. Optional.
.PARAMETER Format
    Output format. 'Raw' returns API response. Default: Raw.
.PARAMETER OutputType
    Output object type. Default: PowerShellObject.
.EXAMPLE
    Get-InforcerTenant
    Gets all tenants as PowerShell objects.
.OUTPUTS
    PSObject or String (when -OutputType JsonObject)
.LINK
    Connect-Inforcer
#>
```

## Baseline Owner Behavior (AlignmentScore)

When -TenantId is a baseline owner (not scored itself), also include tenants aligned TO that baseline (via `alignmentSummaries.alignedBaselineTenantId` from /beta/tenants). This is handled by the `Add-ChildTenantIdsFromAlignments` helper.

## Version and Manifest

- **ModuleVersion** in `module/InforcerCommunity.psd1`
- **FunctionsToExport:** Every Public cmdlet including Get-InforcerSupportedEventType

## Testing

- Pester tests: basic call, expected properties, -OutputType JsonObject, session-not-connected
- Cross-platform: verify on Windows and macOS when possible
