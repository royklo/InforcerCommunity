# Cmdlet Reference

This document describes each cmdlet with parameters, usage examples, and **example output**.

> **Tip**: For detailed property definitions and API schemas, see the [API Reference](./API-REFERENCE.md).

> **Note**: Default output shows key properties. Use `| Select-Object *` to see all properties including raw API fields.

---

## Connect-Inforcer

Establishes a secure connection to the Inforcer REST API. The API key is stored as a SecureString. A minimal API call validates the key before returning; on failure (e.g. wrong key or endpoint), the connection is not established.

| Parameter | Type | Mandatory | Description |
|-----------|------|-----------|--------------|
| **ApiKey** | Object | Yes | API key (string or SecureString). Alias: `Key`. |
| **Region** | String | No | `uk`, `eu`, `us`, `anz`. Default: `uk`. Ignored when `-BaseUrl` is set. |
| **BaseUrl** | String | No | Custom base URL. When set, `-Region` is ignored. |

### Example

```powershell
Connect-Inforcer -ApiKey "your-api-key" -Region uk
```

### Example output

```
Status      : Connected
Region      : uk
BaseUrl     : https://api-uk.inforcer.com/api
ConnectedAt : 05-Mar-2025 14:30:00
```

---

## Disconnect-Inforcer

Disconnects from the Inforcer API and clears the session from memory.

No parameters.

### Example

```powershell
Disconnect-Inforcer
```

### Example output

When a session was active:

```
Disconnected from Inforcer API.
```

When no session was active:

```
No active session to disconnect.
```

---

## Test-InforcerConnection

Tests the current API connection by sending a request to the API. Requires an active session (run `Connect-Inforcer` first).

No parameters.

### Example

```powershell
Connect-Inforcer -ApiKey $env:INFORCER_API_KEY -Region uk
Test-InforcerConnection
```

### Example output

Success (written to host):

```
Connection successful. API is reachable.
```

When not connected, an error is written (e.g. "Not connected. To connect, run: Connect-Inforcer ...").

---

## Get-InforcerTenant

Retrieves tenant information. Optionally filter by `-TenantId` (numeric ID, Microsoft Tenant ID GUID, or tenant name). Licenses are shown as a comma-separated string; PolicyDiff and PolicyDiffFormatted show policy change info when the API provides it.

**Output schema**: [Tenant](./API-REFERENCE.md#tenant) — includes `licenses`, `PolicyDiff`

| Parameter | Type | Mandatory | Description |
|-----------|------|-----------|--------------|
| **Format** | String | No | `Raw` (default). |
| **TenantId** | Object | No | Filter to this tenant (numeric ID, GUID, or tenant name). |
| **OutputType** | String | No | `PowerShellObject` (default) or `JsonObject`. JSON uses Depth 100. |

### Examples

```powershell
Get-InforcerTenant
Get-InforcerTenant -TenantId 482
Get-InforcerTenant -OutputType JsonObject
```

### Example output — list of tenants

```
ClientTenantId      : 103
MsTenantId          : a1b2c3d4-e5f6-7890-abcd-ef1111111111
TenantFriendlyName  : Contoso Ltd
TenantDnsName       : contoso.onmicrosoft.com
licenses            : PREMIUM, INTUNE
SecureScore         : 85
IsBaseline          : True
LastBackupTimestamp : 2025-03-01T10:00:00Z

ClientTenantId      : 482
MsTenantId          : b2c3d4e5-f6a7-8901-bcde-f22222222222
TenantFriendlyName  : Fabrikam Inc
TenantDnsName       : fabrikam.onmicrosoft.com
licenses            : PREMIUM
SecureScore         : 72
IsBaseline          : False
LastBackupTimestamp : 2025-03-01T09:00:00Z
```

The default view shows 8 key properties. Use `| Select-Object *` to see all properties including `alignmentSummaries`, `policyDiff`, `tags`, and `recentChanges`.

### Example output — single tenant with -TenantId 482

Same shape as one of the objects above (one tenant).

---

## Get-InforcerBaseline

Retrieves baseline groups and their members. Optionally filter by `-TenantId` (owner or member).

**Output schema**: [BaselineGroup](./API-REFERENCE.md#baselinegroup) — includes `members`, `items`, alignment thresholds

| Parameter | Type | Mandatory | Description |
|-----------|------|-----------|--------------|
| **Format** | String | No | `Raw` (default). |
| **TenantId** | Object | No | Filter baselines where this tenant is owner or member. |
| **OutputType** | String | No | `PowerShellObject` (default) or `JsonObject`. |

### Example

```powershell
Get-InforcerBaseline
Get-InforcerBaseline -TenantId 482
```

### Example output

```
BaselineName         : Production baseline
BaselineId           : bg-001
Owner                : Contoso Ltd
OwnerTenantId        : 103
Members              : Fabrikam (142), Tailspin (201)
AlignedThreshold     : 80
SemiAlignedThreshold : 60
Mode                 : Standard
```

Use `| Select-Object *` to see all properties including `autoAddNewPolicies`, `isComplete`, `isShared`, and `items`.

---

## Get-InforcerTenantPolicies

Retrieves policies for a specified tenant. TenantId accepts a numeric ID, Microsoft Tenant ID (GUID), or tenant name.

**Output schema**: [Policy](./API-REFERENCE.md#policy) — includes `product`, `platform`, `policyData`, `tags`

| Parameter | Type | Mandatory | Description |
|-----------|------|-----------|--------------|
| **Format** | String | No | `Raw` (default). |
| **TenantId** | Object | Yes | Tenant to get policies for (numeric ID, GUID, or tenant name). |
| **OutputType** | String | No | `PowerShellObject` (default) or `JsonObject`. JSON uses Depth 100. |

### Example

```powershell
Get-InforcerTenantPolicies -TenantId 482
Get-InforcerTenantPolicies -TenantId "a1b2c3d4-e5f6-7890-abcd-ef1234567890" -OutputType JsonObject
```

### Example output

```
PolicyId       : pol-101
PolicyName     : Require MFA for admins
Product        : Microsoft 365
PrimaryGroup   : Conditional Access
SecondaryGroup : Policies
Platform       : Azure AD
ReadOnly       : False

PolicyId       : pol-102
PolicyName     : Block legacy auth
Product        : Microsoft 365
PrimaryGroup   : Conditional Access
SecondaryGroup : Policies
Platform       : Exchange
ReadOnly       : False
```

The default view shows 7 key properties. Use `| Select-Object *` to see all properties including `policyData`, `TagsArray`, and raw API fields.

---

## Get-InforcerAlignmentDetails

Retrieves alignment scores or detailed alignment data. **Format Table** (default): one row per alignment with columns below. **Format Raw**: raw API response. Optional `-TenantId` and `-Tag` filter the table. With `-BaselineId`, retrieves detailed per-policy alignment data. When `-BaselineId` is used without `-TenantId`, the first member tenant is queried (baseline policies are identical across all members).

**Output schema**: [AlignmentScore](./API-REFERENCE.md#alignmentscore) — includes `score`, `baselineGroupId`, `lastComparisonDateTime`

| Parameter | Type | Mandatory | Description |
|-----------|------|-----------|--------------|
| **Format** | String | No | `Table` (default) or `Raw`. |
| **TenantId** | Object | No | Filter to this tenant (numeric ID, GUID, or tenant name). When used with `-BaselineId`, queries that specific tenant. |
| **BaselineId** | String | No | Baseline GUID or friendly name. When used alone (without `-TenantId`), queries the first member tenant (baseline policies are identical across members). |
| **Tag** | String | No | When Format is Table (without `-BaselineId`), filter to tenants with tag containing this value (case-insensitive). |
| **OutputType** | String | No | `PowerShellObject` (default) or `JsonObject`. JSON uses Depth 100. |

### Examples

```powershell
Get-InforcerAlignmentDetails
Get-InforcerAlignmentDetails -Format Raw -OutputType JsonObject
Get-InforcerAlignmentDetails -TenantId 482 -Tag Production
Get-InforcerAlignmentDetails -BaselineId "Provision M365"
Get-InforcerAlignmentDetails -TenantId 139 -BaselineId "Provision M365"
Get-InforcerAlignmentDetails -TenantId 139 -BaselineId "91e0b0f7-69f1-453f-8d73-5a6f726b5b21" -Format Raw
```

### Example output — Format Table (summary)

```
Tenant                   TenantId Score BaselineName                                       LastComparison
------                   -------- ----- ------------                                       --------------
Contoso                  646      100   Inforcer Blueprint Baseline - Tier 0 - Initiate    2026-03-26...
Inforced by Roy          647      98,9  Inforcer Blueprint Baseline - Tier 1 - Foundations  2026-03-26...
```

### Example output — Format Table with -TenantId and -BaselineId (detail)

First object is the metrics summary:

```
TenantName               : Contoso
TenantId                 : 646
AlignmentScore           : 100
TotalPolicies            : 27
Aligned                  : 27
AcceptedDeviation        : 0
UnacceptedDeviation      : 0
RecommendedFromBaseline  : 0
ExistingCustomerPolicies : 0
CompletedAt              : 2026-03-26T22:03:07Z
```

Followed by per-policy rows (no repeated metrics):

```
PolicyName             : Power BI Pro
AlignmentStatus        : Aligned
Product                : M365 Admin Center
PrimaryGroup           : Self-Service Trials and Purchases
SecondaryGroup         : Products
InforcerPolicyTypeName : Self Service
Tags                   : Provision M365, Tier 1

PolicyName             : Enable guest self-service sign up via user flows
AlignmentStatus        : Unaccepted Deviation
Product                : Entra
PrimaryGroup           : Settings
SecondaryGroup         : All
InforcerPolicyTypeName : Entra
Tags                   : IAM - Core, Secure Collaboration, Provision M365, Tier 1
```

Possible `AlignmentStatus` values: `Aligned`, `Unaccepted Deviation`, `Accepted Deviation`, `Recommended From Baseline`, `Existing Customer Policy`.

### Example output — Format Raw with -OutputType JsonObject

A JSON string (array of objects) with properties such as `tenantId`, `tenantFriendlyName`, `score`, `baselineGroupId`, `baselineGroupName`, `lastComparisonDateTime`. Depth 100. When using `-BaselineId`, the JSON contains the full alignment detail including `metrics`, `alignment`, and `completedAt`.

---

## Get-InforcerAuditEvent

Retrieves audit events from the Inforcer API. Supports optional `-EventType`, `-DateFrom`, `-DateTo`, `-PageSize`, and `-MaxResults`.

**Output schema**: [AuditEvent](./API-REFERENCE.md#auditevent) — includes `eventType`, `timestamp`, flattened metadata fields

| Parameter | Type | Mandatory | Description |
|-----------|------|-----------|-------------|
| **EventType** | String[] | No | Event types to include. Tab completion with supported event types. Omit for all types. |
| **DateFrom** | DateTime | No | Start of date/time range (inclusive). |
| **DateTo** | DateTime | No | End of date/time range (inclusive). |
| **PageSize** | Int | No | Page size per API request. Default: 100. |
| **MaxResults** | Int | No | Max events to return. 0 = no limit. Default: 0. |
| **Format** | String | No | `Raw` (default). |
| **OutputType** | String | No | `PowerShellObject` (default) or `JsonObject`. JSON uses Depth 100. |

### Examples

```powershell
Get-InforcerAuditEvent
Get-InforcerAuditEvent -DateFrom (Get-Date).AddDays(-7) -DateTo (Get-Date)
Get-InforcerAuditEvent -EventType authentication,failedAuthentication -DateFrom $from -DateTo $to
Get-InforcerAuditEvent -OutputType JsonObject
```

### Example output

```
EventType       : authentication
Code            : USER_SIGNIN_SUCCESS
User            : admin@contoso.com
Timestamp       : 2025-03-05T14:25:00Z
Message         : User signed in successfully
ClientIpv4      : 192.168.1.1
UserName        : admin@contoso.com
UserDisplayName : Admin User

EventType       : failedAuthentication
Code            : USER_SIGNIN_FAILED
User            : unknown
Timestamp       : 2025-03-05T14:20:00Z
Message         : Invalid credentials
ClientIpv4      :
UserName        :
UserDisplayName :
```

The default view shows 8 key properties. Use `| Select-Object *` to see all properties including `id`, `correlationId`, `clientId`, `relType`, `relId`, and `ClientIpv6`.

---

## Get-InforcerUser

Retrieves users from an Inforcer tenant. Without `-UserId`, returns a paginated list of user summaries with optional search filtering. With `-UserId`, returns the full user detail including groups, roles, devices, and risk information.

**Output schemas**: [UserSummary](./API-REFERENCE.md#usersummary) (list) | [User](./API-REFERENCE.md#user) (detail)

| Parameter | Type | Mandatory | ParameterSet | Description |
|-----------|------|-----------|--------------|-------------|
| **Format** | String | No | Both | `Raw` (default). |
| **TenantId** | Object | Yes | Both | Numeric ID, Microsoft Tenant ID (GUID), or tenant name. Supports pipeline input. |
| **Search** | String | No | List | Server-side search filter for the user list. |
| **MaxResults** | Int | No | List | Max users to return. 0 = no limit. Default: 0. |
| **UserId** | String | Yes | ById | The user ID (GUID) to retrieve full details for. |
| **OutputType** | String | No | Both | `PowerShellObject` (default) or `JsonObject`. JSON uses Depth 100. |

### Examples

```powershell
Get-InforcerUser -TenantId 139
Get-InforcerUser -TenantId 139 -Search "Adele"
Get-InforcerUser -TenantId 139 -MaxResults 50
Get-InforcerUser -TenantId 139 -UserId "8e61ce11-a45b-42a6-8ca4-1d881781566d"
Get-InforcerTenant -TenantId 139 | Get-InforcerUser
Get-InforcerUser -TenantId 139 -OutputType JsonObject
```

### Example output — List (UserSummary)

```
DisplayName      : Adele Vance
UserPrincipalName : AdeleV@contoso.OnMicrosoft.com
UserType         : Member
Department       : Retail
AssignedLicenses : {@{sku=SPB; name=Microsoft 365 Business Premium; ...}}
IsGlobalAdmin    : False
IsMfaCapable     : False
```

### Example output — Detail (User)

```
DisplayName      : Adele Vance
UserPrincipalName : AdeleV@contoso.OnMicrosoft.com
UserType         : Member
Department       : Retail
Mail             : AdeleV@contoso.OnMicrosoft.com
AccountEnabled   : True
IsGlobalAdmin    : False
IsCloudOnly      : True
IsMfaRegistered  : False
RiskLevel        :
```

---

## Export-InforcerTenantDocumentation

Generates comprehensive, human-readable documentation of an entire M365 tenant's configuration as managed through the Inforcer API. Pulls data from existing cmdlets (`Get-InforcerBaseline`, `Get-InforcerTenant`, `Get-InforcerTenantPolicies`), resolves Intune Settings Catalog settingDefinitionIDs to friendly names, and outputs in multiple formats.

The HTML output features a modern admin dashboard design with a collapsible sidebar navigation, search, tag filtering, dark/light mode toggle, and hide-empty-fields toggle. All output is self-contained (no external dependencies or CDN links).

| Parameter | Type | Mandatory | Description |
|-----------|------|-----------|--------------|
| **Format** | String | No | Output format: `Html` (default), `Markdown`, `Json`, `Csv`. |
| **TenantId** | Object | Yes | Tenant to document (numeric ID, GUID, or tenant name). |
| **OutputPath** | String | No | Directory to write the output file. Defaults to current directory. |
| **SettingsCatalogPath** | String | No | Path to a local `settings.json` file for Intune Settings Catalog name resolution. When omitted, automatically downloads and caches the latest data from the [IntuneSettingsCatalogData](https://github.com/royklo/IntuneSettingsCatalogData) GitHub repository (~65 MB, cached at `~/.inforcercommunity/data/settings.json` with a 24-hour TTL). |
| **FetchGraphData** | Switch | No | When set, resolves group ObjectIDs to display names, assignment filter IDs to names, and scope tag IDs to names via Microsoft Graph. Requires a Graph connection (use `Connect-Inforcer -FetchGraphData` or `Connect-InforcerGraph`). |
| **Baseline** | String | No | Filter to policies belonging to a specific baseline (name or ID). |
| **Tag** | String | No | Filter to policies with a specific Inforcer tag (case-insensitive). |

### Examples

```powershell
# Generate HTML documentation for a tenant
Export-InforcerTenantDocumentation -Format Html -TenantId 482

# Generate Markdown with baseline filter
Export-InforcerTenantDocumentation -Format Markdown -TenantId 482 -Baseline "Production"

# Generate JSON export to a specific directory
Export-InforcerTenantDocumentation -Format Json -TenantId 482 -OutputPath ./reports

# Generate CSV for spreadsheet analysis
Export-InforcerTenantDocumentation -Format Csv -TenantId 482

# Full HTML with Graph data resolution (group names, filter names, scope tags)
Connect-Inforcer -ApiKey $key -Region uk -FetchGraphData
Export-InforcerTenantDocumentation -Format Html -TenantId 482 -FetchGraphData

# Filter by tag
Export-InforcerTenantDocumentation -Format Html -TenantId 482 -Tag "Tier 1"
```

### Output

Returns `FileInfo` objects for the exported file(s). HTML output auto-opens in the default browser.

### HTML features

- Modern glassmorphism sidebar with collapsible Product > Category > Policy hierarchy
- Tag filter pills for AND/OR filtering by Inforcer tags
- Real-time search bar with text highlighting
- Dark/Light mode toggle (persisted via localStorage)
- Hide empty fields toggle (scoped to Basics/Settings sections only)
- Show metadata toggle for @odata properties
- Back-to-top floating button
- Notch-style status bar showing tenant/baseline name and policy count
- Collapsible long values with Expand/Collapse button
- Categories sorted alphabetically, grouped by platform
- Policy tags shown inline as blue-bordered badges
- "None" displayed for policies without assignments

### Graph integration (`-FetchGraphData`)

When `-FetchGraphData` is specified and a Graph connection is available:
- Group ObjectIDs in assignments are resolved to display names via `/directoryObjects`
- Assignment filter IDs are resolved to names via `/beta/deviceManagement/assignmentFilters`
- Scope tag IDs are resolved to names via `/beta/deviceManagement/roleScopeTags`
- The Graph tenant is validated against the Inforcer tenant's `msTenantId`

---

## See also

- **[API-REFERENCE.md](./API-REFERENCE.md)** — Detailed API schemas and response structures.
- **[README.md](../README.md)** — Installation and quick start.
- **[CONTRIBUTING.md](../CONTRIBUTING.md)** — How to contribute and report bugs.
- **Get-Help \<CmdletName\> -Full** — Full comment-based help in the module.
