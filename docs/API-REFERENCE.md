# Inforcer API Reference

This document describes the Inforcer REST API endpoints, schemas, and response structures used by the InforcerCommunity PowerShell module.

> **Note**: This is a technical reference for the underlying API. For PowerShell cmdlet usage, see [CMDLET-REFERENCE.md](./CMDLET-REFERENCE.md).

---

## Table of Contents

- [Authentication](#authentication)
- [Endpoints](#endpoints)
  - [Baselines](#baselines)
  - [Alignment Scores](#alignment-scores)
  - [Tenants](#tenants)
  - [Tenant Policies](#tenant-policies)
  - [Audit Events](#audit-events)
  - [Users](#users)
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
- [Response Wrapper](#response-wrapper)
- [Error Responses](#error-responses)

---

## Authentication

All API requests require authentication via API key. Use `Connect-Inforcer` to establish a session before calling other cmdlets.

---

## Endpoints

### Baselines

#### GET /beta/baselines

Retrieves baseline groups and their members.

**Cmdlet**: `Get-InforcerBaseline`

| Parameter | Location | Required | Type | Description |
|-----------|----------|----------|------|-------------|
| baselineTenantId | query | No | integer | Filter baseline groups by baseline tenant ID. If not provided, all baseline groups are returned. |

**Response**: Array of [BaselineGroup](#baselinegroup)

---

### Alignment Scores

#### GET /beta/alignmentScores

Retrieves alignment scores for tenants.

**Cmdlet**: `Get-InforcerAlignmentScore`

**Response**: Array of [AlignmentScore](#alignmentscore)

---

### Tenants

#### GET /beta/tenants

Retrieves all tenants.

**Cmdlet**: `Get-InforcerTenant`

**Response**: Array of [Tenant](#tenant)

---

#### GET /beta/tenants/{tenantId}

Retrieves a specific tenant by ID.

**Cmdlet**: `Get-InforcerTenant -TenantId`

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

| Parameter | Location | Required | Type | Description |
|-----------|----------|----------|------|-------------|
| tenantId | path | Yes | integer | The unique identifier for the tenant. |

**Response**: Array of [Policy](#policy)

---

### Audit Events

#### GET /beta/auditEvents/eventTypes

Retrieves available event types for filtering audit events.

**Cmdlet**: Internal use (populates `-EventType` tab completion)

**Response**: Array of [EventType](#eventtype)

---

#### POST /beta/auditEvents/search

Searches the activity log with optional filters.

**Cmdlet**: `Get-InforcerAuditEvent`

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

| Parameter | In | Type | Required | Description |
|-----------|----|------|----------|-------------|
| `tenantId` | path | integer | Yes | Inforcer tenant ID. |
| `search` | query | string | No | Server-side search filter. |
| `continuationToken` | query | string | No | Token to continue a previous page. |

**Response**: Paginated array of [UserSummary](#usersummary) with `continuationToken` and `totalCount` at the response root level (siblings of `data`).

#### `GET /beta/tenants/{tenantId}/users/{userId}`

Returns full detail for a single user.

| Parameter | In | Type | Required | Description |
|-----------|----|------|----------|-------------|
| `tenantId` | path | integer | Yes | Inforcer tenant ID. |
| `userId` | path | string (GUID) | Yes | The user ID. |

**Response**: Single [User](#user) object.

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
