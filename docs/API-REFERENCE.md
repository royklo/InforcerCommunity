# Inforcer API Reference

This document describes the Inforcer REST API endpoints, schemas, and response structures used by the InforcerCommunity PowerShell module.

> **Note**: This is a technical reference for the underlying API. For PowerShell cmdlet usage, see [CMDLET-REFERENCE.md](./CMDLET-REFERENCE.md).

---

## Table of Contents

- [Authentication](#authentication)
- [API Scopes](#api-scopes)
- [Endpoints](#endpoints)
  - [Baselines](#baselines)
  - [Alignment Scores](#alignment-scores)
  - [Tenants](#tenants)
  - [Tenant Policies](#tenant-policies)
  - [Audit Events](#audit-events)
  - [Users](#users)
  - [Groups](#groups)
  - [Roles](#roles)
  - [Reports](#reports)
- [Schemas](#schemas)
  - [BaselineGroup](#baselinegroup)
  - [BaselineMember](#baselinemember)
  - [IncludedBaselineItem](#includedbaselineitem)
  - [AlignmentScore](#alignmentscore)
  - [Tenant](#tenant)
  - [TenantTag](#tenanttag)
  - [AlignmentSummary](#alignmentsummary)
  - [TenantLicense](#tenantlicense)
  - [Policy](#policy)
  - [PolicyTag](#policytag)
  - [EventType](#eventtype)
  - [AuditEvent](#auditevent)
  - [UserSummary](#usersummary)
  - [User](#user)
  - [UserLicense](#userlicense)
  - [TenantGroupSummary](#tenantgroupsummary)
  - [TenantGroup](#tenantgroup)
  - [TenantRole](#tenantrole)
  - [ReportType](#reporttype)
  - [ReportRun](#reportrun)
  - [ReportOutput](#reportoutput)
- [Response Wrapper](#response-wrapper)
- [Error Responses](#error-responses)

---

## Authentication

All API requests require authentication via API key. Use `Connect-Inforcer` to establish a session before calling other cmdlets.

---

## API Scopes

Inforcer API keys are issued with one or more scopes. Each cmdlet and endpoint below lists its required scope(s). Request the narrowest scope that satisfies your use case; `Tenants.Read` is a broad scope that covers most tenant-related reads.

### Scope → Routes

| Scope | Routes |
|-------|--------|
| `Baselines.Read` | `/beta/baselines` |
| `Tenants.Read` | `/beta/baselines`, `/beta/alignmentScores`, `/beta/tenants`, `/beta/tenants/{tenantId}`, `/beta/tenants/{tenantId}/groups`, `/beta/tenants/{tenantId}/groups/{groupId}`, `/beta/tenants/{tenantId}/roles`, `/beta/tenants/{tenantId}/secureScores`, `/beta/tenants/{tenantId}/users`, `/beta/tenants/{tenantId}/users/{userId}` |
| `AlignmentScores.Read` | `/beta/alignmentScores` |
| `tenants.policies.Read` | `/beta/tenants/{tenantId}/policies`, `/beta/tenants/{tenantId}/alignmentDetails` |
| `Assessments.Read` | `/beta/assessments` |
| `Assessments.Run` | `/beta/tenants/{tenantId}/assessments/{assessmentId}/runs` |
| `Audit.Read` | `/beta/auditEvents/search`, `/beta/auditEvents/eventTypes` *(needs confirmation — see note below)* |
| `Tenants.Groups.Read` | `/beta/tenants/{tenantId}/groups`, `/beta/tenants/{tenantId}/groups/{groupId}` |
| `Tenants.Roles.Read` | `/beta/tenants/{tenantId}/roles` |
| `Tenants.SecureScores.Read` | `/beta/tenants/{tenantId}/secureScores` |
| `Tenants.Users.Read` | `/beta/tenants/{tenantId}/users`, `/beta/tenants/{tenantId}/users/{userId}` |
| `Reports.Read` | `/beta/reports/types`, `/beta/reports/runs`, `/beta/reports/runs/{runId}/outputs`, `/beta/reports/runs/{runId}/outputs/{outputId}` |
| `Reports.Run` | `/beta/reports/runs` *(POST only)* |

> **Note on `Audit.Read`**: The scope mapping provided by the Inforcer API team lists `Audit.Read → /beta/assessments`, but `/beta/assessments` is already covered by `Assessments.Read`, and the module's audit cmdlets call `/beta/auditEvents/search` and `/beta/auditEvents/eventTypes`. This table assumes `Audit.Read` applies to the `/beta/auditEvents/*` routes. **This needs confirmation with the Inforcer API team.**

### Cmdlet → Endpoints → Required Scopes

Built mechanically by tracing each public cmdlet through the module (including the `Resolve-InforcerTenantId` helper that hits `GET /beta/tenants` whenever `-TenantId` is passed as a GUID or tenant name). The minimum-scope column is the **narrowest** union; `Tenants.Read` alone is always sufficient for every route it covers, so you can collapse the narrow scopes into `Tenants.Read` if you prefer broader access.

| Cmdlet | Endpoints called | Minimum scopes |
|--------|------------------|----------------|
| `Connect-Inforcer` | — (session validation only) | None |
| `Disconnect-Inforcer` | — | None |
| `Test-InforcerConnection` | — | None |
| `Get-InforcerTenant` | `GET /beta/tenants` | `Tenants.Read` |
| `Get-InforcerBaseline` | `GET /beta/baselines` | `Baselines.Read` |
| `Get-InforcerTenantPolicies` | `GET /beta/tenants/{tenantId}/policies` + `GET /beta/tenants` *(GUID/name lookup)* | `tenants.policies.Read` + `Tenants.Read`† |
| `Get-InforcerAlignmentDetails` | `GET /beta/baselines`, `GET /beta/alignmentScores`, `GET /beta/tenants`, `GET /beta/tenants/{tenantId}/alignmentDetails` | `Baselines.Read` + `AlignmentScores.Read` + `Tenants.Read` + `tenants.policies.Read` |
| `Get-InforcerAuditEvent` | `POST /beta/auditEvents/search` | `Audit.Read` *(unmapped — see note above)* |
| `Get-InforcerSupportedEventType` | `GET /beta/auditEvents/eventTypes` | `Audit.Read` *(unmapped — see note above)* |
| `Get-InforcerUser` | `GET /beta/tenants/{tenantId}/users[/...] ` + `GET /beta/tenants` *(GUID/name lookup)* | `Tenants.Users.Read` + `Tenants.Read`† |
| `Get-InforcerGroup` | `GET /beta/tenants/{tenantId}/groups[/...] ` + `GET /beta/tenants` *(GUID/name lookup)* | `Tenants.Groups.Read` + `Tenants.Read`† |
| `Get-InforcerRole` | `GET /beta/tenants/{tenantId}/roles` + `GET /beta/tenants` *(GUID/name lookup)* | `Tenants.Roles.Read` + `Tenants.Read`† |
| `Get-InforcerAssessment` | `GET /beta/assessments` | `Assessments.Read` |
| `Invoke-InforcerAssessment` | `GET /beta/tenants`, `GET /beta/assessments`, `POST /beta/tenants/{tenantId}/assessments/{assessmentId}/runs` | `Tenants.Read` + `Assessments.Read` + `Assessments.Run` |
| `Export-InforcerTenantDocumentation` | `GET /beta/tenants`, `GET /beta/baselines`, `GET /beta/tenants/{tenantId}/policies` | `Tenants.Read` + `Baselines.Read` + `tenants.policies.Read` |
| `Compare-InforcerEnvironments` | `GET /beta/tenants`, `GET /beta/baselines`, `GET /beta/tenants/{tenantId}/policies` *(per side)* | `Tenants.Read` + `Baselines.Read` + `tenants.policies.Read` |
| `Get-InforcerReportType` | `GET /beta/reports/types` | `Reports.Read` |
| `Invoke-InforcerReport` | `POST /beta/reports/runs`, `GET /beta/reports/runs/{runId}/outputs`, `GET /beta/reports/runs/{runId}/outputs/{outputId}` + `GET /beta/tenants` *(GUID/name lookup)* | `Reports.Read` + `Reports.Run` + `Tenants.Read`† |
| `Get-InforcerReportRun` | `GET /beta/reports/runs`, `GET /beta/reports/runs/{runId}/outputs` *(with `-Wait` or `-IncludeOutputs`)* | `Reports.Read` |
| `Save-InforcerReportOutput` | `GET /beta/reports/runs/{runId}/outputs/{outputId}` | `Reports.Read` |

> † `Tenants.Read` is only consumed for the tenant-list lookup that `Resolve-InforcerTenantId` performs when `-TenantId` is a GUID or tenant name. If callers always pass a numeric Client Tenant ID, the `Tenants.Read` portion can be omitted.

---

## Endpoints

### Baselines

#### GET /beta/baselines

Retrieves baseline groups and their members.

**Cmdlet**: `Get-InforcerBaseline`

**Required scope**: `Baselines.Read` (or `Tenants.Read`)

| Parameter | Location | Required | Type | Description |
|-----------|----------|----------|------|-------------|
| baselineTenantId | query | No | integer | Filter baseline groups by baseline tenant ID. If not provided, all baseline groups are returned. |

**Response**: Array of [BaselineGroup](#baselinegroup)

---

### Alignment Scores

#### GET /beta/alignmentScores

Retrieves alignment scores for tenants.

**Cmdlet**: `Get-InforcerAlignmentDetails`

**Required scope**: `AlignmentScores.Read` (or `Tenants.Read`)

**Response**: Array of [AlignmentScore](#alignmentscore)

---

### Tenants

#### GET /beta/tenants

Retrieves all tenants.

**Cmdlet**: `Get-InforcerTenant`

**Required scope**: `Tenants.Read`

**Response**: Array of [Tenant](#tenant)

---

#### GET /beta/tenants/{tenantId}

Retrieves a specific tenant by ID.

**Cmdlet**: `Get-InforcerTenant -TenantId`

**Required scope**: `Tenants.Read`

| Parameter | Location | Required | Type | Description |
|-----------|----------|----------|------|-------------|
| tenantId | path | Yes | integer | The unique identifier for the tenant (Client Tenant ID). |

**Response**: [Tenant](#tenant)

> **Implementation Note**: The PowerShell module uses `GET /beta/tenants` with client-side filtering for consistency and deduplication.

---

### Tenant Policies

#### GET /beta/tenants/{tenantId}/policies

Retrieves policies for a specific tenant.

**Cmdlet**: `Get-InforcerTenantPolicies`

**Required scope**: `tenants.policies.Read`

| Parameter | Location | Required | Type | Description |
|-----------|----------|----------|------|-------------|
| tenantId | path | Yes | integer | The unique identifier for the tenant. |

**Response**: Array of [Policy](#policy)

---

### Audit Events

#### GET /beta/auditEvents/eventTypes

Retrieves available event types for filtering audit events.

**Cmdlet**: Internal use (populates `-EventType` tab completion)

**Required scope**: `Audit.Read` *(needs confirmation — see [API Scopes](#api-scopes))*

**Response**: Array of [EventType](#eventtype)

---

#### POST /beta/auditEvents/search

Searches the activity log with optional filters.

**Cmdlet**: `Get-InforcerAuditEvent`

**Required scope**: `Audit.Read` *(needs confirmation — see [API Scopes](#api-scopes))*

**Request Body**:

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| eventTypes | string[] | No | Event types to filter by (e.g., `authentication`, `failedAuthentication`). |
| dateFrom | string (date-time) | No | Start of date/time range (inclusive). ISO 8601 format. |
| dateTo | string (date-time) | No | End of date/time range (inclusive). ISO 8601 format. |
| pageSize | integer | No | Number of results per page. Default: 100. |
| continuationToken | string | No | Token for pagination (returned in previous response). |

**Example Request**:

```json
{
  "eventTypes": ["authentication", "failedAuthentication"],
  "dateFrom": "2026-02-01T00:00:00Z",
  "dateTo": "2026-02-26T23:59:59Z",
  "pageSize": 50
}
```

**Response**: Paginated array of [AuditEvent](#auditevent) with `continuationToken`

---

### Users

#### `GET /beta/tenants/{tenantId}/users`

Returns a paginated list of user summaries for a tenant.

**Required scope**: `Tenants.Users.Read` (or `Tenants.Read`)

| Parameter | In | Type | Required | Description |
|-----------|----|------|----------|-------------|
| `tenantId` | path | integer | Yes | Inforcer tenant ID. |
| `search` | query | string | No | Server-side search filter. |
| `continuationToken` | query | string | No | Token to continue a previous page. |

**Response**: Paginated array of [UserSummary](#usersummary) with `continuationToken` and `totalCount` at the response root level (siblings of `data`).

#### `GET /beta/tenants/{tenantId}/users/{userId}`

Returns full detail for a single user.

**Required scope**: `Tenants.Users.Read` (or `Tenants.Read`)

| Parameter | In | Type | Required | Description |
|-----------|----|------|----------|-------------|
| `tenantId` | path | integer | Yes | Inforcer tenant ID. |
| `userId` | path | string (GUID) | Yes | The user ID. |

**Response**: Single [User](#user) object.

### Groups

#### `GET /beta/tenants/{tenantId}/groups`

Returns a paginated list of Entra ID group summaries for a tenant.

**Required scope**: `Tenants.Groups.Read` (or `Tenants.Read`)

| Parameter | In | Type | Required | Description |
|-----------|----|------|----------|-------------|
| `tenantId` | path | integer | Yes | Inforcer tenant ID. |
| `search` | query | string | No | Server-side search filter. |
| `continuationToken` | query | string | No | Token to continue a previous page. |

**Response**: Paginated array of [TenantGroupSummary](#tenantgroupsummary) with `continuationToken` and `totalCount` at the response root level (siblings of `data`).

#### `GET /beta/tenants/{tenantId}/groups/{groupId}`

Returns full detail for a single group including members.

**Required scope**: `Tenants.Groups.Read` (or `Tenants.Read`)

| Parameter | In | Type | Required | Description |
|-----------|----|------|----------|-------------|
| `tenantId` | path | integer | Yes | Inforcer tenant ID. |
| `groupId` | path | string (GUID) | Yes | The group ID. |

**Response**: Single [TenantGroup](#tenantgroup) object.

### Roles

#### `GET /beta/tenants/{tenantId}/roles`

Returns the list of Entra ID directory role definitions for a tenant.

**Required scope**: `Tenants.Roles.Read` (or `Tenants.Read`)

| Parameter | In | Type | Required | Description |
|-----------|----|------|----------|-------------|
| `tenantId` | path | integer | Yes | Inforcer tenant ID. |

**Response**: Array of [TenantRole](#tenantrole) objects.

### Reports

Beta endpoints for triggering and retrieving asynchronous report runs.

#### `GET /beta/reports/types`

Returns the catalog of available report types. Each entry advertises the report's key, supported output formats, whether it can be collated across tenants, accepted parameters, and tags.

**Required API scope(s)**: `Reports.Read`

**Cmdlet**: `Get-InforcerReportType`

**Response**: Array of [ReportType](#reporttype) objects (under `data`).

#### `POST /beta/reports/runs`

Queues one or more report runs against a set of target tenants. Returns one run record per (report × tenant) combination unless `collate: true` is set on a `collatable: true` type, in which case a single cross-tenant output is produced.

**Required API scope(s)**: `Reports.Run`

**Cmdlet**: `Invoke-InforcerReport`

**Request body**:

```json
{
  "reports": [
    {
      "type": "ActiveUserCount",
      "outputFormat": "csv",
      "collate": false,
      "parameters": { "report-period": "30" }
    }
  ],
  "tenants": { "includeTenants": [482, 483] }
}
```

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `reports[].type` | string | Yes | Report type key from `GET /reports/types`. Case-insensitive. |
| `reports[].outputFormat` | string | Yes | One of the `outputFormats` advertised by the type. Case-insensitive. |
| `reports[].collate` | boolean | No | When `true` on a `collatable: true` type, produces a single cross-tenant output. |
| `reports[].parameters` | object | No | Type-specific parameters (string-keyed, string-valued). Unknown keys are silently accepted today; the module rejects them client-side. |
| `tenants.includeTenants` | int[] | Yes | Numeric Client Tenant IDs. Duplicates are deduped by the server. |

**Response**: Array of [ReportRun](#reportrun) objects (one per created run).

> **Known server-side bug**: Duplicate `(type, outputFormat)` entries currently render all duplicates in the last-listed format. The module deduplicates client-side before POST.

#### `GET /beta/reports/runs`

Lists report runs across all tenants the caller has visibility into. Server-side cap: `maxItems: 500`, last 7 days. Query parameters (`?status=`, `?since=`, `?limit=`, ...) are currently ignored — filter client-side.

**Required API scope(s)**: `Reports.Read`

**Cmdlet**: `Get-InforcerReportRun`

> **Propagation lag**: a newly-queued run does not appear in this list for ~4 minutes. For freshly-queued runs, poll `GET /beta/reports/runs/{runId}/outputs` directly (404 until terminal, 200 once complete).

**Response**: Array of [ReportRun](#reportrun) objects (under `data`).

#### `GET /beta/reports/runs/{runId}/outputs`

Returns the list of outputs for a single terminal run. Used as the polling probe for run completion (bypasses the list-endpoint propagation lag).

**Required API scope(s)**: `Reports.Read`

**Cmdlet**: `Test-InforcerReportRunTerminal` *(private helper, used by `Invoke-InforcerReport -Wait`, `Get-InforcerReportRun -Wait`, and `Get-InforcerReportRun -IncludeOutputs`)*

| Parameter | In | Type | Required | Description |
|-----------|----|------|----------|-------------|
| `runId` | path | string (GUID) | Yes | The run identifier returned by `POST /reports/runs`. |

**Responses:**

| Code | Body | Meaning |
|------|------|---------|
| 200 | `{ data: [ReportOutput, ...] }` | Run is in a terminal state (`completed` or `completedWithErrors`) and outputs are available. |
| 200 | `{ data: [] }` | Run is visible to the API key, but **no outputs are within the key's tenant scope.** Collated outputs (covering multiple tenants) are only returned when the key covers every tenant the run targeted. |
| 404 | — | **Deliberately indistinguishable across four cases**: (1) run does not exist, (2) run belongs to a different client, (3) run is not in a terminal state (still `running`, or `failed`), (4) output ID does not belong to this run. Designed this way to avoid leaking run existence across clients. |

> **Polling implication**: `Invoke-InforcerReport -Wait` and `Get-InforcerReportRun -Wait` cannot distinguish a still-running run from a `failed` run — both 404 indefinitely. The cmdlet times out cleanly after `-TimeoutSeconds`. To detect `failed` status, query `GET /beta/reports/runs` (subject to the 4-minute lag).

#### `GET /beta/reports/runs/{runId}/outputs/{outputId}`

Downloads the raw bytes of a single output. Returns proper MIME type and a `Content-Disposition: attachment; filename=...; filename*=UTF-8''...` header. No `Range` / `ETag` support — every fetch is a full GET.

**Required API scope(s)**: `Reports.Read`

**Cmdlet**: `Save-InforcerReportOutput`

| Parameter | In | Type | Required | Description |
|-----------|----|------|----------|-------------|
| `runId` | path | string (GUID) | Yes | Run identifier. |
| `outputId` | path | string | Yes | Output identifier from the outputs list. |

**404 is deliberately indistinguishable** across: run doesn't exist, run belongs to a different client, run isn't in a terminal state, output ID doesn't belong to the run, or the output's tenant is outside the key's tenant scope. Designed to avoid leaking run/output existence.

**Response**: Raw bytes (CSV, JSON, HTML, PDF, etc. depending on `outputFormat`).

---

## Schemas

### BaselineGroup

Represents a baseline configuration group used for alignment scoring.

| Property | Type | Description |
|----------|------|-------------|
| id | string (guid) | Unique identifier for the baseline group. |
| name | string | Name of the baseline group. |
| baselineClientTenantId | integer | Unique identifier for the baseline tenant (owner). |
| baselineTenantFriendlyName | string | Display name of the baseline tenant. |
| baselineTenantDnsName | string | DNS name of the baseline tenant (e.g., `contoso.onmicrosoft.com`). |
| baselineMsTenantId | string (guid) | Microsoft tenant ID (Azure AD tenant ID) for the baseline tenant. |
| alignedThreshold | number | Score threshold for "aligned" status (e.g., 80 = 80% aligned). |
| semiAlignedThreshold | number | Score threshold for "semi-aligned" status (e.g., 60 = 60% aligned). |
| members | [BaselineMember](#baselinemember)[] | Tenants that are members of this baseline group. |
| mode | string | Baseline mode: `include` or `exclude`. |
| autoAddNewPolicies | boolean | Whether new policies are automatically added to the baseline. |
| isComplete | boolean | Whether this is a full baseline (`true`) or partial baseline (`false`). |
| isShared | boolean | Whether this baseline is shared with other organizations. |
| items | [IncludedBaselineItem](#includedbaselineitem)[] | Policy items explicitly configured for this baseline. `null` when using automatic inclusion rules. |

---

### BaselineMember

Represents a tenant that is a member of a baseline group.

| Property | Type | Description |
|----------|------|-------------|
| clientTenantId | integer | Unique identifier for the tenant. |
| tenantFriendlyName | string | Display name of the tenant. |
| tenantDnsName | string | DNS name of the tenant. |
| msTenantId | string (guid) | Microsoft tenant ID for the tenant. |

---

### IncludedBaselineItem

Represents an item explicitly included in a custom baseline. Can reference a specific policy, nested baseline, or category-based item.

| Property | Type | Description |
|----------|------|-------------|
| policySnapshotId | string (guid) | Policy snapshot ID included in the baseline. |
| childCustomBaselineId | string (guid) | Child baseline ID if this is a nested baseline item. |
| policyCategoryProduct | string | Product category (e.g., `Intune`, `Entra`, `Defender`) for category-based items. |
| policyCategoryPrimaryGroup | string | Primary group category (e.g., `Settings`, `Exchange`, `Windows`). Requires `policyCategoryProduct`. |
| policyCategorySecondaryGroup | string | Secondary group category (e.g., `Custom Indicators`, `Sensitivity Labels`, `Compliance Policies`). Requires `policyCategoryProduct` and `policyCategoryPrimaryGroup`. |
| alignAssignments | boolean | Whether policy assignments for this item should be aligned. |

---

### AlignmentScore

Represents the alignment score for a tenant against a baseline.

| Property | Type | Description |
|----------|------|-------------|
| tenantId | integer | Unique identifier for the tenant. |
| tenantFriendlyName | string | Display name of the tenant. |
| score | number | Alignment score (0-100). |
| baselineGroupId | string (guid) | ID of the baseline being compared against. |
| baselineGroupName | string | Name of the baseline being compared against. |
| lastComparisonDateTime | string (date-time) | Timestamp of the last alignment comparison. |

---

### Tenant

Represents a tenant in the Inforcer system.

| Property | Type | Description |
|----------|------|-------------|
| clientTenantId | integer | Unique identifier for the tenant in Inforcer. |
| tenantFriendlyName | string | Display name of the tenant. |
| tenantDnsName | string | DNS name of the tenant (e.g., `contoso.onmicrosoft.com`). |
| msTenantId | string (guid) | Microsoft tenant ID (Azure AD tenant ID). |
| secureScore | number | Microsoft Secure Score for the tenant. |
| isBaseline | boolean | Whether this tenant is configured as a baseline tenant. |
| lastBackupTimestamp | string (date-time) | Timestamp of the last policy backup. |
| recentChanges | integer | Number of recent policy changes detected. |
| policyDiff | string | Text report of added, removed, and changed policies. |
| tags | [TenantTag](#tenanttag)[] | Tags associated with the tenant. |
| alignmentSummaries | [AlignmentSummary](#alignmentsummary)[] | Alignment summaries for the tenant. |
| licenses | [TenantLicense](#tenantlicense)[] | Licenses associated with the tenant. |

---

### TenantTag

Represents a tag associated with a tenant.

| Property | Type | Description |
|----------|------|-------------|
| id | string (guid) | Unique identifier for the tag. |
| name | string | Name of the tag. |
| description | string | Description of the tag. |

---

### AlignmentSummary

Summary of alignment status for a tenant against a baseline.

| Property | Type | Description |
|----------|------|-------------|
| alignedBaselineTenantId | integer | ID of the baseline tenant. |
| alignedBaselineId | string (guid) | ID of the aligned baseline. |
| alignedBaselineName | string | Name of the aligned baseline. |
| alignmentScore | number | Current alignment score (0-100). |
| alignedThreshold | number | Threshold for "aligned" status. |
| semiAlignedThreshold | number | Threshold for "semi-aligned" status. |
| lastAlignmentDateTime | string (date-time) | Timestamp of the last alignment calculation. |

---

### TenantLicense

Represents a license associated with a tenant.

| Property | Type | Description |
|----------|------|-------------|
| sku | string | SKU identifier of the license (e.g., `PREMIUM`, `INTUNE`). |

---

### Policy

Represents a policy associated with a tenant.

| Property | Type | Description |
|----------|------|-------------|
| id | string | Unique identifier for the policy. |
| policyTypeId | integer | Numeric ID of the policy type. |
| name | string | Internal name of the policy. |
| displayName | string | Display name of the policy. |
| friendlyName | string | User-friendly name of the policy. |
| description | string | Description of the policy. |
| readOnly | boolean | Whether the policy is read-only (cannot be modified). |
| product | string | Product category (e.g., `Microsoft 365`, `Intune`, `Entra`). |
| primaryGroup | string | Primary grouping for categorization. |
| secondaryGroup | string | Secondary grouping for categorization. |
| platform | string | Platform the policy applies to (e.g., `Azure AD`, `Exchange`, `Windows`). |
| policyCategoryId | integer | ID of the policy category. |
| tags | [PolicyTag](#policytag)[] | Tags associated with the policy. |
| policyData | object | Full policy configuration data (structure varies by policy type). |

> **Note**: The PowerShell module normalizes policy names to `PolicyName` for consistency across different policy types.

---

### PolicyTag

Represents a tag associated with a policy.

| Property | Type | Description |
|----------|------|-------------|
| id | string (guid) | Unique identifier for the tag. |
| name | string | Name of the tag. |
| description | string | Description of the tag. |

---

### EventType

Represents a type of audit event.

| Property | Type | Description |
|----------|------|-------------|
| name | string | Name of the event type (e.g., `authentication`, `failedAuthentication`, `policyChange`). |

---

### AuditEvent

Represents an entry in the activity log.

| Property | Type | Description |
|----------|------|-------------|
| id | string (guid) | Unique identifier for the event. |
| correlationId | string (guid) | Correlation ID for grouping related events. |
| clientId | integer | Client ID associated with the event. |
| relType | string | Related entity type (e.g., `tenant`, `policy`). |
| relId | string | Related entity ID. |
| eventType | string | Type of event (see [EventType](#eventtype)). |
| message | string | Human-readable event message. |
| code | string | Event code for programmatic handling. |
| user | string | User who triggered the event. |
| timestamp | string (date-time) | When the event occurred. |
| metadata | object | Additional event-specific data (flattened to top-level properties in PowerShell output). |

**Flattened metadata properties** (when present):

| Property | Type | Description |
|----------|------|-------------|
| ClientIpv4 | string | Client IPv4 address. |
| ClientIpv6 | string | Client IPv6 address. |
| UserName | string | Username associated with the event. |
| UserDisplayName | string | Display name of the user. |

---

### UserSummary

Returned by the list/search users endpoint. Contains key user properties and counts.

| Property | Type | Description |
|----------|------|-------------|
| id | string (GUID) | The user ID. |
| displayName | string | Display name. |
| userPrincipalName | string | User principal name (UPN). |
| userType | string | User type (e.g. Member, Guest). |
| jobTitle | string | Job title. |
| department | string | Department. |
| groups | integer | Number of groups the user is a member of. |
| roles | integer | Number of roles assigned. |
| assignedLicenses | array\<[UserLicense](#userlicense)\> | Assigned licenses. |
| isGlobalAdmin | boolean | Whether the user is a global administrator. |
| isAccountEnabled | boolean | Whether the account is enabled. |
| isMfaRegistered | boolean | Whether the user is registered for MFA. |
| isMfaCapable | boolean | Whether the user is capable of MFA. |

**PascalCase aliases**: Id, DisplayName, UserPrincipalName, UserType, JobTitle, Department, Groups, Roles, AssignedLicenses, IsGlobalAdmin, IsAccountEnabled, IsMfaRegistered, IsMfaCapable

---

### User

Returned by the get-user-by-ID endpoint. Includes all UserSummary fields plus detailed profile, on-premises, group/role/device memberships, risk, and license information.

| Property | Type | Description |
|----------|------|-------------|
| id | string (GUID) | The user ID. |
| displayName | string | Display name. |
| givenName | string | First name. |
| surname | string | Last name. |
| userPrincipalName | string | UPN. |
| userType | string | User type. |
| jobTitle | string | Job title. |
| department | string | Department. |
| mail | string | Email address. |
| mobilePhone | string | Mobile phone number. |
| businessPhones | array\<string\> | Business phone numbers. |
| officeLocation | string | Office location. |
| streetAddress | string | Street address. |
| city | string | City. |
| state | string | State/province. |
| postalCode | string | Postal code. |
| country | string | Country. |
| preferredLanguage | string | Preferred language. |
| accountEnabled | boolean | Whether the account is enabled. |
| usageLocation | string | Usage location (ISO country code). |
| createdDateTime | datetime | Account creation time. |
| lastPasswordChangeDateTime | datetime | Last password change. |
| lastSignInDateTime | datetime | Last sign-in time. |
| companyName | string | Company name. |
| employeeId | string | Employee ID. |
| employeeType | string | Employee type. |
| employeeHireDate | datetime | Hire date. |
| mailNickname | string | Mail alias. |
| onPremisesSyncEnabled | boolean | Whether synced from on-premises AD. |
| manager | object | Manager reference (`{ id: GUID }`). |
| groups | array\<object\> | Group memberships (id, displayName, description, groupTypes). |
| roles | array\<object\> | Directory role assignments (id, displayName, roleTemplateId). |
| devices | array\<object\> | Registered devices (id, displayName, OS, compliance, etc.). |
| appRoleAssignments | array\<object\> | App role assignments. |
| assignedLicenses | array\<[UserLicense](#userlicense)\> | Assigned licenses. |
| isGlobalAdmin | boolean | Whether global administrator. |
| isCloudOnly | boolean | Cloud-only account. |
| isHybrid | boolean | Hybrid (synced) account. |
| isMfaRegistered | boolean | MFA registered. |
| isMfaCapable | boolean | MFA capable. |
| isAllDevicesCompliant | boolean | All devices compliant. |
| riskState | string | Identity risk state. |
| riskDetail | string | Risk detail. |
| riskLevel | string | Risk level. |

**PascalCase aliases**: All properties above are aliased to PascalCase. Nested objects (groups, roles, devices, appRoleAssignments, manager) are left as-is.

---

### UserLicense

License assignment on a user, used in both UserSummary and User schemas.

| Property | Type | Description |
|----------|------|-------------|
| sku | string | SKU part number (e.g. `SPB`, `EXCHANGESTANDARD`). |
| skuId | string (GUID) | SKU unique identifier. |
| name | string | Display-friendly SKU name (may be null). |
| capabilityStatus | string | Capability status (e.g. Enabled). |
| isExpired | boolean | Whether the license is expired. |
| isCancelled | boolean | Whether the license is cancelled. |
| state | string | License assignment state. |

### TenantGroupSummary

Summary of an Entra ID group (returned from list endpoint).

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| id | string (GUID) | Yes | The group ID. |
| displayName | string | Yes | Display name of the group. |
| description | string | No | Description of the group. |
| mail | string | No | Email address of the group. |
| visibility | string | No | Visibility (e.g. Public, Private). |
| groupTypes | array\<string\> | Yes | Types of the group (e.g. Unified, DynamicMembership). |

**PSTypeName:** `InforcerCommunity.GroupSummary`

### TenantGroup

Full detail of an Entra ID group (returned from by-ID endpoint).

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| id | string (GUID) | Yes | The group ID. |
| displayName | string | Yes | Display name of the group. |
| description | string | No | Description of the group. |
| mail | string | No | Email address of the group. |
| mailNickname | string | No | Mail alias of the group. |
| visibility | string | No | Visibility (e.g. Public, Private). |
| membershipRule | string | No | Dynamic membership rule (null for static groups). |
| groupTypes | array\<string\> | Yes | Types of the group. |
| createdDateTime | string (datetime) | No | When the group was created. |
| mailEnabled | boolean | No | Whether mail is enabled. |
| onPremisesSyncEnabled | boolean | No | Whether synced from on-premises AD. |
| members | array\<object\> | No | Group members (id, displayName, type). |

**PSTypeName:** `InforcerCommunity.Group`

### TenantRole

An Entra ID directory role definition.

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| id | string (GUID) | Yes | The unique identifier of the role definition. |
| templateId | string (GUID) | No | The unique identifier of the role definition template. |
| displayName | string | Yes | Display name of the role definition. |
| description | string | Yes | Description of the role definition. |
| isBuiltIn | boolean | No | Whether the role is built-in. |
| isEnabled | boolean | No | Whether the role is enabled. |
| isPrivileged | boolean | No | Whether the role is privileged. |

**PSTypeName:** `InforcerCommunity.Role`

### ReportType

A catalog entry from `GET /beta/reports/types`. Field names verified against `api-uk.inforcer.com`.

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| key | string | Yes | Stable identifier (e.g. `ActiveUserCount`, `CopilotAdoption`). Case-insensitive in requests. |
| name | string | No | Display name. |
| description | string | No | One-line description of what the report contains. |
| collatable | boolean | No | Whether the type can produce a single cross-tenant output when `collate: true` is passed. |
| supportedOutputFormats | string[] | No | Output formats accepted for this type at `POST /reports/runs`. Observed values: `csv`, `json`, `pdf`, `html`. |
| tags | string[] | No | Categorization tags (e.g. `Identity`, `Adoption`, `Security`). |
| requiredParameters | array\<object\> | No | Per-type parameters (e.g. `report-period`, `assessment-id`). Empty array `[]` for types that take no parameters. Each entry typically exposes `key`, `name`, `type`, and value/range constraints. |

**PSTypeName:** `InforcerCommunity.ReportType`. The module also exposes `OutputFormats` and `Parameters` as PascalCase back-compat aliases over `supportedOutputFormats` / `requiredParameters`.

### ReportRun

A run record from `GET /beta/reports/runs` (list) or `POST /beta/reports/runs` (create). **One run batches the full reports[] array submitted in the POST**, so the run carries plural `reportTypes` and `outputFormats` arrays — not singular fields. Field names verified against `api-uk.inforcer.com`.

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| runId | string (GUID) | Yes | Unique run identifier. **POST response shape is `{ data: { runId: "<guid>" } }` — only the runId is returned at create time.** |
| status | string | Yes | One of `running`, `completed`, `completedWithErrors`, `failed`. |
| reportTypes | string[] | No | The report type keys batched into this run (case may differ from catalog — e.g. `activeusercount` instead of `ActiveUserCount`). |
| outputFormats | string[] | No | The output formats requested across the run's reports. |
| triggeredByType | string | No | `user` or `scheduled`. |
| triggeredBy | string | No | Identity that triggered the run. |
| createdAt | string (ISO 8601) | No | When the run was created. |
| startedAt | string (ISO 8601) | No | When processing began (typically the same instant as `createdAt`). |
| completedAt | string (ISO 8601) | No | When the run reached a terminal status. |
| outputCount | int | No | Number of outputs produced (0 is valid — e.g. no Copilot data, or no tenant-visible outputs). |
| outputs | array\<[ReportOutput](#reportoutput)\> | No | Embedded when `-IncludeOutputs` / `-Wait` is used; absent from the raw list endpoint. |

**PSTypeName:** `InforcerCommunity.ReportRun`. `Id` is exposed as a PascalCase alias over `runId` for `-Id`-style pipeline binding.

### ReportOutput

An output record from `GET /beta/reports/runs/{runId}/outputs`. The actual bytes are fetched via the per-output download endpoint (see `Save-InforcerReportOutput`). Field names verified against `api-uk.inforcer.com`.

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| id | string (GUID) | Yes | Output identifier (unique within the run). Aliased as `OutputId`. |
| reportType | string | Yes | Report type key for this output (e.g. `ActiveUserCount`). |
| tenantId | int | Yes | Numeric Client Tenant ID. Absent on collated cross-tenant outputs. |
| format | string | Yes | Output format (`csv`, `json`, `pdf`, `html`). Aliased as `OutputFormat`. |
| sizeBytes | int | Yes | Size in bytes. Aliased as `FileSize`. |

**Server does not return**: a `fileName`, `contentType`, or `createdAt` on the output record — the filename and MIME type come from the download endpoint's `Content-Disposition` and `Content-Type` headers respectively.

**Module-attached property**: `RunId` is attached client-side when needed for pipeline binding to `Save-InforcerReportOutput`.

**PSTypeName:** `InforcerCommunity.ReportOutput`

> **Empty-result caveat**: Some report types produce a 4-byte UTF-8 BOM CSV (`EF BB BF 0A`) when there's no data, while others omit the output entirely. The cmdlet does not try to disambiguate "report ran with empty result" from "report didn't run for this tenant"; callers should inspect `fileSize` and/or content.

---

## Response Wrapper

All API responses are wrapped in a standard envelope:

```json
{
  "success": true,
  "message": "optional message",
  "errors": [],
  "data": [ ... ]
}
```

| Property | Type | Description |
|----------|------|-------------|
| success | boolean | Whether the request succeeded. |
| message | string | Optional message about the response. |
| errors | string[] | Array of error messages (empty on success). |
| data | any | The response payload (array or object depending on endpoint). |

The PowerShell module automatically unwraps the `data` property, so cmdlets return the payload directly.

---

## Error Responses

### 401 Unauthorized

```json
{
  "success": false,
  "message": "Your credentials are invalid or you are not logged in",
  "errors": ["Please verify your credentials"]
}
```

**PowerShell**: Returns error "Your credentials are invalid. Please verify your API key."

---

### 403 Forbidden

```json
{
  "success": false,
  "message": "Client tenant verification failed",
  "errors": ["You do not have access to this resource"]
}
```

**PowerShell**: Returns error "You don't have permission to access this tenant or resource."

---

### 404 Not Found

```json
{
  "success": false,
  "message": "The resource 'derp' could not be found",
  "errors": ["Could not find the resource"]
}
```

**PowerShell**: Returns error "Tenant or resource not found."

---

### 500 Internal Server Error

```json
{
  "success": false,
  "message": "Something went wrong",
  "errors": ["Internal server error"]
}
```

**PowerShell**: Returns error with the API-provided message.

---

## See also

- **[CMDLET-REFERENCE.md](./CMDLET-REFERENCE.md)** — PowerShell cmdlet usage and examples.
- **[README.md](../README.md)** — Installation and quick start.
- **[CONTRIBUTING.md](../CONTRIBUTING.md)** — How to contribute.
