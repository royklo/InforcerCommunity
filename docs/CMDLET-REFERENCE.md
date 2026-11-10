# Cmdlet Reference

This document describes each cmdlet with parameters, usage examples, and **example output**.

> **Tip**: For detailed property definitions and API schemas, see the [API Reference](./API-REFERENCE.md).

> **Logins**: every cmdlet works with both logins, except `New-InforcerUser` and `Set-InforcerUser`, which need an API client because the beta API cannot create or change users. An API client (`Connect-Inforcer -ClientId -ClientSecret`) uses the v1 API; an API key (`-ApiKey`) uses the legacy beta API. Each cmdlet lists the beta API-key scopes and the v1 API client permissions it needs. The v1 permission mapping is unconfirmed (see [API client permissions](./API-REFERENCE.md#api-client-permissions-v1)). Tenant IDs: Microsoft tenant ID (GUID) or name on both logins; the numeric Client Tenant ID only with an API key. `-TenantId` has the aliases `ClientTenantId` and `MsTenantId`.

> **Note**: Default output shows key properties. Use `| Select-Object *` to see all properties including raw API fields.

---

## Personal data

User details (`Get-InforcerUser -UserId`), audit events, report outputs and the files written by `Export-InforcerTenantDocumentation`, `Compare-InforcerEnvironments`, `Invoke-InforcerAssessment`, `Invoke-InforcerReport` and `Save-InforcerReportOutput` can contain personal data (names, UPNs, email addresses, IP addresses, sign-in details). The module caches no user or audit data and writes files only where you ask (`-OutputPath`, or the current directory for `Invoke-InforcerReport` and `Save-InforcerReportOutput`). Handle exported files as personal data.

---

## Connect-Inforcer

Establishes a secure connection to the inforcer REST API. There are two parameter sets, and the API version follows from the one you use:

- **ClientCredentials** (`-ClientId`, `-ClientSecret`) uses the current **v1** API. The connection is validated by requesting an OAuth access token; a successful token request is enough (no permission is probed, so any valid client connects). The token lasts 60 minutes and is renewed automatically.
- **ApiKey** (`-ApiKey`) uses the **legacy beta** API. A minimal API call validates the key before returning; on failure (wrong key or endpoint, expired or revoked key) the connection is not established. A key that is valid but lacks the scope for the probe endpoint still connects, with a warning that the key's scopes are unverified. Because inforcer says the legacy API is due to be retired (no date announced), every API-key login prints a warning that advises switching to client credentials.

Secrets and tokens are stored as SecureString only; `-PassThru` never exposes them in plain text. Requests that carry the key, secret or token never follow a redirect: when the API answers with a redirect (HTTP 3xx), the connection fails with `ConnectionValidationFailed` and a message naming the target, so credentials are never sent to another address.

> **Known limit:** after a failed request, `$Error` and your own `-ErrorVariable` still hold PowerShell's transport error record. The module strips the auth header from it, but it keeps the request URL (host, path, tenant id), so review `Format-List * -Force` dumps before sharing them.

**Endpoints called**: API key: `GET /beta/baselines` (validation probe; a key without that scope still connects, with a warning) and a best-effort `GET /beta/reports/types` (primes the report catalog, never fails the login). Client credentials: `POST /oauth/token` and the same best-effort `GET /v1/reports/types`.
**Required API scope(s)**: None (a key that lacks the probe's scope still connects; a client-credentials login only needs a valid client)

| Parameter | Type | Mandatory | Description |
|-----------|------|-----------|--------------|
| **ApiKey** | Object | Yes (ApiKey set) | API key (string or SecureString), legacy beta API. Alias: `Key`. |
| **ClientId** | String | Yes (ClientCredentials set) | Client ID of an inforcer API client (create it under Configure > REST API in the portal). |
| **ClientSecret** | Object | Yes (ClientCredentials set) | Client secret (string or SecureString). |
| **Region** | String | No | `uk`, `eu`, `us`, `anz`. Default: `uk`. Ignored when `-BaseUrl` is set. |
| **BaseUrl** | String | No | Custom API host, with or without `/api`. Must use `https`; an `http` URL is rejected. When set, `-Region` is ignored. |
| **FetchGraphData** | Switch | No | Also sign in to Microsoft Graph interactively, requesting the read scopes `Directory.Read.All`, `Policy.Read.All` and `DeviceManagementConfiguration.Read.All` (see [Graph enrichment](#graph-integration--fetchgraphdata)). `Export-InforcerTenantDocumentation` and `Compare-InforcerEnvironments -FetchGraphData` reuse that session when it is for the same tenant. Requires the `Microsoft.Graph.Authentication` module, which is not installed automatically: when it is missing, a warning says how to install it and Graph is skipped. |
| **PassThru** | Switch | No | Returns only an independent copy of the session hashtable (no status object, so `$src = Connect-Inforcer ... -PassThru` holds a session usable with `-SourceSession`; earlier versions also returned the status object, which broke that example). Use to capture sessions for cross-account comparison with `Compare-InforcerEnvironments` (sessions of different login types can be mixed). A captured session stays usable after `Disconnect-Inforcer`, which clears only the module's session; remove it when done (`Remove-Variable src`). |

### Examples

```powershell
# Client credentials (v1, recommended)
$secret = Read-Host -AsSecureString -Prompt 'Client secret'
Connect-Inforcer -ClientId '<client-id>' -ClientSecret $secret -Region uk

# Legacy API key (beta) - prints the legacy-API warning
Connect-Inforcer -ApiKey "your-api-key" -Region uk

# Capture sessions for cross-account comparison
$src = Connect-Inforcer -ClientId $id1 -ClientSecret $secret1 -Region uk -PassThru
$dst = Connect-Inforcer -ApiKey $key2 -Region eu -PassThru
Compare-InforcerEnvironments -SourceTenantId 'Contoso' -DestinationTenantId 'Fabrikam' -SourceSession $src -DestinationSession $dst
Remove-Variable src, dst   # captured sessions outlive Disconnect-Inforcer
```

### Example output

```
Status      : Connected
Region      : uk
BaseUrl     : https://api-uk.inforcer.com
ConnectedAt : 05-Mar-2025 14:30:00
```

With an API key `BaseUrl` ends in `/api` (`https://api-uk.inforcer.com/api`) and the following warning is written first:

```
WARNING: You connected with an API key, which uses inforcer's legacy beta API. API keys are due to be retired. Switch to an API client: create one in the inforcer portal (Configure > REST API), then run Connect-Inforcer -ClientId <client id> -ClientSecret <client secret> -Region uk. With an API client, pass the Microsoft tenant ID (GUID) or tenant name instead of the numeric tenant id.
```

---

## Disconnect-Inforcer

Disconnects from the inforcer API and clears the module's session from memory. Sessions captured with `Connect-Inforcer -PassThru` are separate copies and stay usable after Disconnect; remove them when done (`Remove-Variable src, dst`).

**Required API scope(s)**: None (session management only; a client-credentials login only needs a valid client)

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

Tests the current API connection by sending a request to the API, and returns `$true` or `$false` so the result can be used as a condition. Requires an active session (run `Connect-Inforcer` first).

Failures — including "no session" — are reported as **warnings**, not errors, so the cmdlet keeps answering the question instead of throwing in scripts that run under `$ErrorActionPreference = 'Stop'`.

**Endpoints called (beta)**: `GET /beta/baselines`
**Required API scope(s) (API key, beta)**: `Baselines.Read` (or `Tenants.Read`)
**Endpoints on v1**: `GET /v1/baselines`
**Required API client permission(s) (v1)**: Baselines *(unconfirmed, see [API client permissions](./API-REFERENCE.md#api-client-permissions-v1))*

A key or API client without that permission makes the test return `False` with a warning, even though the session itself works.

No parameters.

### Example

```powershell
Connect-Inforcer -ClientId $env:INFORCER_CLIENT_ID -ClientSecret (ConvertTo-SecureString $env:INFORCER_CLIENT_SECRET -AsPlainText -Force) -Region uk
Test-InforcerConnection
```

```powershell
# Reconnect only when the current session is dead
if (-not (Test-InforcerConnection)) { Connect-Inforcer -ClientId $id -ClientSecret $secret -Region uk }
```

### Example output

Returns `True`; the following is written to the host:

```
SUCCESS! Connection is working.
```

With no active session it returns `False` and writes a warning:

```
WARNING: Not connected. To connect, run: Connect-Inforcer -ClientId <ClientId> -ClientSecret <ClientSecret> -Region <uk|eu|us|anz>
```

---

## Get-InforcerTenant

Retrieves tenant information. Optionally filter by `-TenantId` (Microsoft Tenant ID GUID or tenant name; the numeric Client Tenant ID only with an API key). Licenses are shown as a comma-separated string; `PolicyDiff` shows policy change info when the API provides it.

- **Both logins:** the list holds every field (licenses, `SecureScore`, `IsBaseline`, tags, alignment summaries, `LastBackupTimestamp`).
- **Client-credentials login (v1):** `ClientTenantId` does not exist. `-TenantId` loads the tenant's own record, which adds `AuthenticationMode`; `-TenantId <GUID>` makes only that one call, a name is first looked up in the tenant list.
- **`-TenantId` always returns the current record:** with an API key the tenant list is fetched once per call (piped tenants share that fetch); with client credentials the tenant is fetched by id.
- **JSON:** with client credentials `-OutputType JsonObject` is always a JSON array, also for one tenant. With an API key a single tenant is a bare JSON object, as in 0.8.0.

**Endpoints called (beta)**: `GET /beta/tenants`
**Required API scope(s) (API key, beta)**: `Tenants.Read`
**Endpoints on v1**: `GET /v1/tenants`; `-TenantId <GUID>` calls only `GET /v1/tenants/{msTenantId}` (a name also reads the tenant list)
**Required API client permission(s) (v1)**: Tenants *(unconfirmed, see [API client permissions](./API-REFERENCE.md#api-client-permissions-v1))*

**Output schema**: [Tenant](./API-REFERENCE.md#tenant) — includes `licenses`, `PolicyDiff`

| Parameter | Type | Mandatory | Description |
|-----------|------|-----------|--------------|
| **Format** | String | No | `Raw` (default). |
| **TenantId** | Object | No | Filter to this tenant: Microsoft tenant ID (GUID), tenant name or DNS name; numeric Client Tenant ID with an API key only. Aliases: `ClientTenantId`, `MsTenantId`. |
| **OutputType** | String | No | `PowerShellObject` (default) or `JsonObject`. JSON uses Depth 100. |

### Examples

```powershell
Get-InforcerTenant
Get-InforcerTenant | Where-Object IsBaseline
Get-InforcerTenant -TenantId 'Contoso'
Get-InforcerTenant -TenantId 102            # API key only (numeric Client Tenant ID)
Get-InforcerTenant -OutputType JsonObject
```

### Example output — list of tenants (API key; client credentials has no ClientTenantId)

```
ClientTenantId      : 101
MsTenantId          : 00000000-0000-0000-0000-000000000001
TenantFriendlyName  : Contoso Ltd
TenantDnsName       : contoso.onmicrosoft.com
licenses            : PREMIUM, INTUNE
SecureScore         : 85
IsBaseline          : True
LastBackupTimestamp : 2025-03-01T10:00:00Z

ClientTenantId      : 102
MsTenantId          : 00000000-0000-0000-0000-000000000002
TenantFriendlyName  : Fabrikam Inc
TenantDnsName       : fabrikam.onmicrosoft.com
licenses            : PREMIUM
SecureScore         : 72
IsBaseline          : False
LastBackupTimestamp : 2025-03-01T09:00:00Z
```

The default view shows 8 key properties. Use `| Select-Object *` to see all properties including `alignmentSummaries`, `policyDiff`, `tags`, and `recentChanges`.

### Example output — single tenant with -TenantId

Same shape as one of the objects above (one tenant). With client credentials it has no `ClientTenantId` and adds `AuthenticationMode`.

---

## Get-InforcerBaseline

Retrieves baseline groups and their members. Optionally filter by `-TenantId` (owner or member).

**Pipeline:** piped tenants (for example `Get-InforcerTenant | Get-InforcerBaseline`) are handled one by one; each result gets a `TenantId` property naming its tenant, and `-OutputType JsonObject` returns one JSON array for all of them. Calls without pipeline input are unchanged. Baselines are read once per call; a baseline shared by several piped tenants is returned once per tenant, and an identical (tenant, baseline) pair never repeats.

**Endpoints called (beta)**: `GET /beta/baselines` — plus `GET /beta/tenants` when `-TenantId` is a GUID or name (resolution).
**Required API scope(s) (API key, beta)**: `Baselines.Read` + `Tenants.Read`†
**Endpoints on v1**: `GET /v1/baselines` (+ `GET /v1/tenants` for a tenant name)
**Required API client permission(s) (v1)**: Baselines + Tenants (only for a tenant name) *(unconfirmed, see [API client permissions](./API-REFERENCE.md#api-client-permissions-v1))*

**Output schema**: [BaselineGroup](./API-REFERENCE.md#baselinegroup) — includes `members`, `items`, alignment thresholds

| Parameter | Type | Mandatory | Description |
|-----------|------|-----------|--------------|
| **Format** | String | No | `Raw` (default). |
| **TenantId** | Object | No | Filter baselines where this tenant is owner or member (Microsoft tenant ID (GUID) or tenant name; numeric Client Tenant ID with an API key only). Aliases: `ClientTenantId`, `MsTenantId`. |
| **OutputType** | String | No | `PowerShellObject` (default) or `JsonObject`. |

### Example

```powershell
Get-InforcerBaseline
Get-InforcerBaseline -TenantId 'Contoso'
Get-InforcerBaseline -OutputType JsonObject
```

> † `Tenants.Read` is only needed when `-TenantId` is a GUID or tenant name. A numeric `-TenantId` (API key) or no `-TenantId` needs no tenant lookup.

### Example output

```
BaselineName         : Production baseline
BaselineId           : bg-001
Owner                : Contoso Ltd
OwnerTenantId        : 101
Members              : Fabrikam (102), Tailspin (103)
AlignedThreshold     : 80
SemiAlignedThreshold : 60
Mode                 : Standard
```

Use `| Select-Object *` to see all properties including `autoAddNewPolicies`, `isComplete`, `isShared`, and `items`.

---

## Get-InforcerTenantPolicies

Retrieves policies for a specified tenant. TenantId accepts a Microsoft Tenant ID (GUID) or tenant name (also a numeric Client Tenant ID with an API key). With client credentials, policy types inforcer could not read are named in one warning.

**Pipeline:** piped tenants (for example `Get-InforcerTenant | Get-InforcerTenantPolicies`) are handled one by one; each result gets a `TenantId` property naming its tenant, and `-OutputType JsonObject` returns one JSON array for all of them. Calls without pipeline input are unchanged.

> **v1:** the cmdlet writes a warning when the response lists `failedPolicyTypes` (a partial result: the types inforcer could not read, with the reason). Beta leaves such types out without a warning. Policy `Id` is the Microsoft policy ID on v1 and the inforcer ID on beta.

**Endpoints called (beta)**: `GET /beta/tenants/{tenantId}/policies` — plus `GET /beta/tenants` when `-TenantId` is a GUID or name (used by `Resolve-InforcerTenantId` to look up the numeric `clientTenantId`).
**Required API scope(s) (API key, beta)**: `tenants.policies.Read` + `Tenants.Read` *(the `Tenants.Read` part can be skipped if `-TenantId` is always passed as a numeric Client Tenant ID — no lookup needed)*
**Endpoints on v1**: `GET /v1/tenants/{msTenantId}/policies` (a GUID needs no lookup; a tenant name also calls `GET /v1/tenants`)
**Required API client permission(s) (v1)**: Policies + Tenants (only when `-TenantId` is a tenant name) *(unconfirmed, see [API client permissions](./API-REFERENCE.md#api-client-permissions-v1))*

**Output schema**: [Policy](./API-REFERENCE.md#policy) — includes `product`, `platform`, `policyData`, `tags`

| Parameter | Type | Mandatory | Description |
|-----------|------|-----------|--------------|
| **Format** | String | No | `Raw` (default). |
| **TenantId** | Object | Yes | Tenant to get policies for (Microsoft tenant ID (GUID) or tenant name; numeric Client Tenant ID with an API key only). Aliases: `ClientTenantId`, `MsTenantId`. |
| **OutputType** | String | No | `PowerShellObject` (default) or `JsonObject`. JSON uses Depth 100. |

### Example

```powershell
Get-InforcerTenantPolicies -TenantId 'Contoso'
Get-InforcerTenantPolicies -TenantId 101            # API key only (numeric Client Tenant ID)
Get-InforcerTenantPolicies -TenantId "00000000-0000-0000-0000-000000000003" -OutputType JsonObject
```

### Example output

```
PolicyName     : Require MFA for admins
Product        : Entra
PrimaryGroup   : Conditional Access
SecondaryGroup : Policies
Platform       : All
ReadOnly       : False
Tags           : IAM - Core, Tier 1
PolicyData     : {"displayName":"Require MFA for admins","state":"enabled",...}

PolicyName     : Block legacy auth
Product        : Entra
PrimaryGroup   : Conditional Access
SecondaryGroup : Policies
Platform       : All
ReadOnly       : False
Tags           :
PolicyData     : {"displayName":"Block legacy auth","state":"enabled",...}
```

The default view shows 8 key properties (`PolicyData` as compact JSON). Use `| Select-Object *` to see all properties including the policy `id`, the full `policyData` and raw API fields.

---

## Get-InforcerAlignmentDetails

Retrieves alignment scores or detailed alignment data. **Format Table** (default): one row per alignment with columns below. **Format Raw**: raw API response. Optional `-TenantId` and `-Tag` filter the table. With `-BaselineId`, retrieves detailed per-policy alignment data. When `-BaselineId` is used without `-TenantId`, the first member tenant is queried (baseline policies are identical across all members).

**Pipeline:** piped tenants are collected and the scores, tenant list and baselines are read once per call, so rows never repeat; with `-BaselineId` each distinct tenant gets one detail call. Each result gets a `TenantId` property naming its tenant, and `-OutputType JsonObject` returns one JSON array. With client credentials the table's JSON is always an array, also for one row (with an API key one row is a bare object, as in 0.8.0).

**Endpoints called (beta)**: `GET /beta/baselines`, `GET /beta/alignmentScores`, `GET /beta/tenants`, `GET /beta/tenants/{tenantId}/alignmentDetails`
**Required API scope(s) (API key, beta)**: `Baselines.Read` + `AlignmentScores.Read` + `Tenants.Read` + `tenants.policies.Read`
**Endpoints on v1**: `GET /v1/baselines`, `GET /v1/alignmentScores`, `GET /v1/tenants`, `GET /v1/tenants/{msTenantId}/alignmentDetails`
**Required API client permission(s) (v1)**: Baselines + Align + Tenants *(unconfirmed, see [API client permissions](./API-REFERENCE.md#api-client-permissions-v1))*

**Output schema**: [AlignmentScore](./API-REFERENCE.md#alignmentscore) — includes `score`, `baselineGroupId`, `lastComparisonDateTime`

| Parameter | Type | Mandatory | Description |
|-----------|------|-----------|--------------|
| **Format** | String | No | `Table` (default) or `Raw`. |
| **TenantId** | Object | No | Filter to this tenant (Microsoft tenant ID (GUID) or tenant name; numeric Client Tenant ID with an API key only). Aliases: `ClientTenantId`, `MsTenantId`. When used with `-BaselineId`, queries that specific tenant. |
| **BaselineId** | String | No | Baseline GUID or friendly name. When used alone (without `-TenantId`), queries the first member tenant (baseline policies are identical across members). |
| **Tag** | String | No | When Format is Table (without `-BaselineId`), filter to tenants with tag containing this value (case-insensitive). No match returns no rows and a warning. |
| **OutputType** | String | No | `PowerShellObject` (default) or `JsonObject`. JSON uses Depth 100. |

### Examples

```powershell
Get-InforcerAlignmentDetails
Get-InforcerAlignmentDetails -Format Raw -OutputType JsonObject
Get-InforcerAlignmentDetails -TenantId 'Contoso' -Tag Production
Get-InforcerAlignmentDetails -BaselineId "Provision M365"
Get-InforcerAlignmentDetails -TenantId 'Contoso' -BaselineId "Provision M365"
Get-InforcerAlignmentDetails -TenantId 'Contoso' -BaselineId "00000000-0000-0000-0000-000000000004" -Format Raw
```

### Example output — Format Table (summary)

```
Tenant                 : Contoso
TenantId               : 101
AlignmentScore         : 100
BaselineName           : Inforcer Blueprint Baseline - Tier 0 - Initiate
LastComparisonDateTime : 2026-03-26T22:03:07Z

Tenant                 : Fabrikam Inc
TenantId               : 102
AlignmentScore         : 98.9
BaselineName           : Inforcer Blueprint Baseline - Tier 1 - Foundations
LastComparisonDateTime : 2026-03-26T21:58:41Z
```

`TenantId` is the numeric Client Tenant ID with an API key and the Microsoft tenant ID (GUID) with client credentials. Pipe to `Format-Table` for a table.

### Example output — Format Table with -TenantId and -BaselineId (detail)

A metrics summary is written to the host, not the pipeline:

```
  Tenant: Contoso (101)
  Alignment Score: 100 | Total: 27 | Aligned: 27 | Accepted Deviation: 0 | Unaccepted Deviation: 0 | Recommended: 0 | Customer Only: 0
  Completed: 2026-03-26T22:03:07Z
```

The pipeline returns one object per policy (so `| Select-Object -First 1` is a policy row; use `-Format Raw` to get the metrics as an object):

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

Retrieves audit events from the inforcer API. Supports optional `-EventType`, `-DateFrom`, `-DateTo`, `-User`, `-PageSize`, and `-MaxResults`.

> **v1:** events have no `ClientId` or `Message`. v1 lists only the event types a partner can see, including the API client events (`apiClientCreate`, `apiClientTokenReject`, ...); beta also lists internal types and types still in development.

> **Personal data:** events carry user names, UPNs and IP addresses. See [Personal data](#personal-data).

Without `-EventType` one search covers every event type (both logins), and events come back in the API's order; `-MaxResults` returns the first events of that order. All `-EventType` values go in one search.

**Endpoints called (beta)**: `POST /beta/auditEvents/search` (paged)
**Required API scope(s) (API key, beta)**: `Audit.Read` *(not in the API team's published scope→route mapping — the route `/beta/auditEvents/search` is unmapped; `Audit.Read` is the assumed scope based on naming. Confirm with inforcer API team.)*
**Endpoints on v1**: `POST /v1/auditEvents/search` (paged)
**Required API client permission(s) (v1)**: Activity *(unconfirmed, see [API client permissions](./API-REFERENCE.md#api-client-permissions-v1))*

**Output schema**: [AuditEvent](./API-REFERENCE.md#auditevent) — includes `eventType`, `timestamp`, flattened metadata fields

| Parameter | Type | Mandatory | Description |
|-----------|------|-----------|-------------|
| **Id** | String | No | Retrieve a specific audit event by its event ID (GUID). Searches all event types and filters client-side. |
| **CorrelationId** | String | No | Retrieve all audit events sharing this correlation ID. Searches all event types and filters client-side. |
| **EventType** | String[] | No | Event types to include. Tab completion with supported event types. Omit for all types. |
| **DateFrom** | DateTime | No | Start of date/time range (inclusive). |
| **DateTo** | DateTime | No | End of date/time range (inclusive). |
| **User** | String | No | Filter events server-side by this user (matches the `user` field in the API request body). |
| **PageSize** | Int | No | Page size per API request. Default: 100. |
| **MaxResults** | Int | No | Max events to return. 0 = no limit. Default: 0. |
| **Format** | String | No | `Raw` (default). |
| **OutputType** | String | No | `PowerShellObject` (default) or `JsonObject`. JSON uses Depth 100. |

### Examples

```powershell
Get-InforcerAuditEvent
Get-InforcerAuditEvent -DateFrom (Get-Date).AddDays(-7) -DateTo (Get-Date)
Get-InforcerAuditEvent -EventType authentication,failedAuthentication -DateFrom $from -DateTo $to
Get-InforcerAuditEvent -User admin@contoso.com -DateFrom (Get-Date).AddDays(-30)
Get-InforcerAuditEvent -OutputType JsonObject
```

### Example output

```
Id              : 00000000-0000-0000-0000-000000000010
EventType       : authentication
Code            : USER_SIGNIN_SUCCESS
User            : admin@contoso.com
Timestamp       : 2025-03-05T14:25:00Z
Message         : User signed in successfully
ClientIpv4      : 192.168.1.1
UserName        : admin@contoso.com
UserDisplayName : Admin User

Id              : 00000000-0000-0000-0000-000000000011
EventType       : failedAuthentication
Code            : USER_SIGNIN_FAILED
User            : unknown
Timestamp       : 2025-03-05T14:20:00Z
Message         : Invalid credentials
ClientIpv4      :
UserName        :
UserDisplayName :
```

The default view shows 9 key properties. Use `| Select-Object *` to see all properties including `correlationId`, `clientId`, `relType`, `relId`, and `ClientIpv6`.

---

## Get-InforcerUser

Retrieves users from an inforcer tenant. Without `-UserId`, returns a paginated list of user summaries with optional search filtering. With `-UserId`, returns the full user detail including groups, roles, devices, and risk information.

> **Personal data:** `-UserId` returns a full personal record. See [Personal data](#personal-data).

> **v1:** the list view returns `Groups` and `Roles` as counts (`groupCount`/`roleCount` mapped to those names), not arrays; `-UserId` returns the full record.

**Pipeline:** piped tenants (for example `Get-InforcerTenant | Get-InforcerUser`) are handled one by one; each result gets a `TenantId` property naming its tenant, and `-OutputType JsonObject` returns one JSON array for all of them. Calls without pipeline input are unchanged.

**Endpoints called (beta)**: `GET /beta/tenants/{tenantId}/users` (list) or `GET /beta/tenants/{tenantId}/users/{userId}` (detail) — plus `GET /beta/tenants` when `-TenantId` is a GUID or name (resolution).
**Required API scope(s) (API key, beta)**: `Tenants.Users.Read` + `Tenants.Read` *(the `Tenants.Read` part can be skipped if `-TenantId` is always passed as a numeric Client Tenant ID — no lookup needed)*
**Endpoints on v1**: `GET /v1/tenants/{msTenantId}/users[/{userId}]`
**Required API client permission(s) (v1)**: User & Group Management + Tenants (only for a tenant name) *(unconfirmed, see [API client permissions](./API-REFERENCE.md#api-client-permissions-v1))*

**Output schemas**: [UserSummary](./API-REFERENCE.md#usersummary) (list) | [User](./API-REFERENCE.md#user) (detail)

| Parameter | Type | Mandatory | ParameterSet | Description |
|-----------|------|-----------|--------------|-------------|
| **Format** | String | No | Both | `Raw` (default). |
| **TenantId** | Object | Yes | Both | Microsoft tenant ID (GUID) or tenant name; numeric Client Tenant ID with an API key only. Aliases: `ClientTenantId`, `MsTenantId`. Supports pipeline input. |
| **Search** | String | No | List | Server-side search filter for the user list. |
| **MaxResults** | Int | No | List | Max users to return. 0 = no limit. Default: 0. |
| **UserId** | String | Yes | ById | The user ID (GUID) to retrieve full details for. |
| **OutputType** | String | No | Both | `PowerShellObject` (default) or `JsonObject`. JSON uses Depth 100. |

### Examples

```powershell
Get-InforcerUser -TenantId 'Contoso'
Get-InforcerUser -TenantId 'Contoso' -Search "Adele"
Get-InforcerUser -TenantId 'Contoso' -MaxResults 50
Get-InforcerUser -TenantId 'Contoso' -UserId "00000000-0000-0000-0000-000000000005"
Get-InforcerTenant -TenantId 'Contoso' | Get-InforcerUser
Get-InforcerUser -TenantId 'Contoso' -OutputType JsonObject
```

### Example output — List (UserSummary)

```
DisplayName      : Jane Doe
UserPrincipalName : jane.doe@contoso.onmicrosoft.com
UserType         : Member
Department       : Retail
AssignedLicenses : {@{sku=SPB; name=Microsoft 365 Business Premium; ...}}
IsGlobalAdmin    : False
IsMfaCapable     : False
```

### Example output — Detail (User)

```
DisplayName      : Jane Doe
UserPrincipalName : jane.doe@contoso.onmicrosoft.com
UserType         : Member
Department       : Retail
Mail             : jane.doe@contoso.onmicrosoft.com
AccountEnabled   : True
IsGlobalAdmin    : False
IsCloudOnly      : True
IsMfaRegistered  : False
RiskLevel        :
```

---

## New-InforcerUser

Creates a Microsoft Entra user in a tenant. Needs a login with an API client (`Connect-Inforcer -ClientId -ClientSecret`); with an API key it stops with the error `RequiresApiClient`, because the beta API cannot create users.

The user can sign in by default and must change the password at the first sign-in. `-MailNickname` defaults to the part of `-UserPrincipalName` before the `@`. The password must meet the tenant's password policy; it is sent only in the request body and never written to verbose output. A new user can take a few seconds to show in `Get-InforcerUser`. Supports `-WhatIf` and `-Confirm`.

**Endpoints called (beta)**: none (not available on the beta API).
**Required API scope(s) (API key, beta)**: not available with an API key.
**Endpoints on v1**: `POST /v1/tenants/{msTenantId}/users` (+ `GET /v1/tenants` for a tenant name)
**Required API client permission(s) (v1)**: User & Group Management (write) + Tenants (only for a tenant name) *(unconfirmed, see [API client permissions](./API-REFERENCE.md#api-client-permissions-v1))*

**Output schema**: [CreatedUser](./API-REFERENCE.md#createduser), with `TenantId`, `displayName` and `userPrincipalName` added.

| Parameter | Type | Mandatory | Description |
|-----------|------|-----------|-------------|
| **TenantId** | Object | Yes | Microsoft tenant ID (GUID) or tenant name. Aliases: `ClientTenantId`, `MsTenantId`. Supports pipeline input by property name. |
| **DisplayName** | String | Yes | The name shown for the user. |
| **UserPrincipalName** | String | Yes | The sign-in name, such as `jo.bloggs@contoso.com`. The domain must be verified in the tenant. |
| **Password** | SecureString | Yes | The initial password. |
| **MailNickname** | String | No | The mail alias. Default: the part of `-UserPrincipalName` before the `@`. |
| **ForceChangePasswordNextSignIn** | Bool | No | Whether the user must change the password at the first sign-in. Default: `$true`. |
| **AccountEnabled** | Bool | No | Whether the user can sign in. Default: `$true`. |
| **GivenName**, **Surname**, **JobTitle**, **Department**, **OfficeLocation**, **StreetAddress**, **City**, **State**, **PostalCode**, **Country**, **MobilePhone**, **PreferredLanguage**, **CompanyName**, **EmployeeId**, **EmployeeType**, **Mail** | String | No | Profile fields, sent as given. |
| **UsageLocation** | String | No | Two-letter country code (ISO 3166) where the user's licences are used, such as `GB`. Needed before licences can be assigned. |
| **BusinessPhones** | String[] | No | Business phone number. Microsoft Entra allows one. |
| **OtherMails** | String[] | No | Other email addresses. |
| **ManagerId** | String | No | The Microsoft Entra object id of the user's manager. |
| **OutputType** | String | No | `PowerShellObject` (default) or `JsonObject`. JSON uses Depth 100; piped tenants return one array. |

### Examples

```powershell
$password = Read-Host -AsSecureString -Prompt 'Initial password'
New-InforcerUser -TenantId 'Contoso' -DisplayName 'Jo Bloggs' -UserPrincipalName 'jo.bloggs@contoso.com' -Password $password
New-InforcerUser -TenantId 'Contoso' -DisplayName 'Jo Bloggs' -UserPrincipalName 'jo.bloggs@contoso.com' -Password $password -GivenName 'Jo' -Surname 'Bloggs' -Department 'Sales' -UsageLocation 'GB' -AccountEnabled $false
New-InforcerUser -TenantId 'Contoso' -DisplayName 'Jo Bloggs' -UserPrincipalName 'jo.bloggs@contoso.com' -Password $password -WhatIf
New-InforcerUser -TenantId 'Contoso' -DisplayName 'Jo Bloggs' -UserPrincipalName 'jo.bloggs@contoso.com' -Password $password -OutputType JsonObject
```

### Example output

```
DisplayName       : Jo Bloggs
UserPrincipalName : jo.bloggs@contoso.com
Id                : 00000000-0000-0000-0000-000000000005
TenantId          : 00000000-0000-0000-0000-000000000001
```

---

## Set-InforcerUser

Updates a Microsoft Entra user's profile, manager or whether they can sign in. Needs a login with an API client (`Connect-Inforcer -ClientId -ClientSecret`); with an API key it stops with the error `RequiresApiClient`, because the beta API cannot change users.

Only the parameters you pass are changed; every other field stays as it is. Pass an empty string (`''`) or `$null` to clear a field, such as `-JobTitle ''`, or `-ManagerId ''` to remove the manager. `DisplayName`, `MailNickname`, `UserPrincipalName` and `Mail` cannot be cleared. `-AccountEnabled $false` blocks sign-in, but existing sessions last until their tokens expire. A change can take a few seconds to show in `Get-InforcerUser`. Returns nothing. Supports `-WhatIf` and `-Confirm`.

When the manager could not be changed but the other changes were saved (HTTP 502), the error lists each step and whether it was applied, for example `Steps: profile: succeeded; manager: failed (Manager not found)`.

**Pipeline:** users from `Get-InforcerUser` or `New-InforcerUser` can be piped in; `-UserId` binds from their `id` and `-TenantId` from their `TenantId` when they have one.

**Endpoints called (beta)**: none (not available on the beta API).
**Required API scope(s) (API key, beta)**: not available with an API key.
**Endpoints on v1**: `PATCH /v1/tenants/{msTenantId}/users/{userId}` (+ `GET /v1/tenants` for a tenant name)
**Required API client permission(s) (v1)**: User & Group Management (write) + Tenants (only for a tenant name) *(unconfirmed, see [API client permissions](./API-REFERENCE.md#api-client-permissions-v1))*

**Request schema**: [UserUpdate](./API-REFERENCE.md#userupdate)

| Parameter | Type | Mandatory | Description |
|-----------|------|-----------|-------------|
| **TenantId** | Object | Yes | Microsoft tenant ID (GUID) or tenant name. Aliases: `ClientTenantId`, `MsTenantId`. Supports pipeline input by property name. |
| **UserId** | String | Yes | The user's Microsoft Entra object id. Alias: `Id`. Supports pipeline input by property name. |
| **AccountEnabled** | Bool | No | Whether the user can sign in. |
| **DisplayName**, **MailNickname**, **UserPrincipalName**, **Mail** | String | No | Cannot be cleared; an empty value is refused. |
| **GivenName**, **Surname**, **JobTitle**, **Department**, **OfficeLocation**, **StreetAddress**, **City**, **State**, **PostalCode**, **Country**, **MobilePhone**, **UsageLocation**, **PreferredLanguage**, **CompanyName**, **EmployeeId**, **EmployeeType** | String | No | Profile fields; `''` clears the field. |
| **BusinessPhones**, **OtherMails** | String[] | No | Replace the whole list; `@()` clears it. |
| **ManagerId** | String | No | The manager's Microsoft Entra object id; `''` removes the manager. |

At least one field must be passed; otherwise the cmdlet stops with `NoChangeSpecified` without a request.

### Examples

```powershell
Set-InforcerUser -TenantId 'Contoso' -UserId '00000000-0000-0000-0000-000000000005' -Department 'Sales' -JobTitle 'Account Manager'
Set-InforcerUser -TenantId 'Contoso' -UserId '00000000-0000-0000-0000-000000000005' -AccountEnabled $false
Get-InforcerUser -TenantId 'Contoso' -Search 'Adele' | Set-InforcerUser -TenantId 'Contoso' -ManagerId ''
Set-InforcerUser -TenantId 'Contoso' -UserId '00000000-0000-0000-0000-000000000005' -UsageLocation 'GB' -WhatIf
```

### Example output

None. With `-WhatIf`:

```
What if: Performing the operation "Update usageLocation" on target "user 00000000-0000-0000-0000-000000000005 in tenant 00000000-0000-0000-0000-000000000001".
```

---

## Get-InforcerGroup

Retrieves Entra ID groups from an inforcer tenant. When called without `-Group`, returns all groups (GroupSummary objects) with optional search filtering and auto-pagination. When called with `-Group`, resolves the group by GUID or display name and returns the full group detail (Group object) including members (on v1 the members come from a separate paged call, so a very large group takes one call per page of members).

**Pipeline:** piped tenants (for example `Get-InforcerTenant | Get-InforcerGroup`) are handled one by one; each result gets a `TenantId` property naming its tenant, and `-OutputType JsonObject` returns one JSON array for all of them. Calls without pipeline input are unchanged.

**Endpoints called (beta)**: `GET /beta/tenants/{tenantId}/groups` (list) or `GET /beta/tenants/{tenantId}/groups/{groupId}` (detail) — plus `GET /beta/tenants` when `-TenantId` is a GUID or name (resolution).
**Required API scope(s) (API key, beta)**: `Tenants.Groups.Read` + `Tenants.Read` *(the `Tenants.Read` part can be skipped if `-TenantId` is always passed as a numeric Client Tenant ID — no lookup needed)*
**Endpoints on v1**: `GET /v1/tenants/{msTenantId}/groups[/{groupId}]`, `.../groups/{groupId}/members` (with `-Group`)
**Required API client permission(s) (v1)**: User & Group Management + Tenants (only for a tenant name) *(unconfirmed, see [API client permissions](./API-REFERENCE.md#api-client-permissions-v1))*

| Parameter | Type | Mandatory | Description |
|-----------|------|-----------|--------------|
| **TenantId** | Object | Yes | Tenant (Microsoft tenant ID (GUID) or tenant name; numeric Client Tenant ID with an API key only). Aliases: `ClientTenantId`, `MsTenantId`. |
| **Group** | String | Yes* | Group GUID or display name for full detail. Alias: `GroupId`. Resolves name automatically via search. |
| **Search** | String | No | Server-side search filter (List parameter set only). |
| **Filter** | String | No | Client-side wildcard filter applied after retrieving groups. Supports `*` wildcards (e.g., `SG - Entra*`). Requires fetching all groups before filtering (List parameter set only). |
| **MaxResults** | Int | No | Maximum groups to return. `0` = no limit (List parameter set only). |
| **OutputType** | String | No | `PowerShellObject` (default) or `JsonObject`. |

### Examples

```powershell
# List all groups in a tenant
Get-InforcerGroup -TenantId 'Contoso'

# Search for groups
Get-InforcerGroup -TenantId 'Contoso' -Search "Finance"

# Get full detail by display name (resolves automatically)
Get-InforcerGroup -TenantId 'Contoso' -Group "Tailspin Toys"

# Get full detail by GUID
Get-InforcerGroup -TenantId 'Contoso' -Group "00000000-0000-0000-0000-000000000006"

# Pipeline from Get-InforcerTenant
Get-InforcerTenant -TenantId 'Contoso' | Get-InforcerGroup

# JSON output
Get-InforcerGroup -TenantId 'Contoso' -OutputType JsonObject
```

### Example output (List)

```
DisplayName : All Company
Id          : 00000000-0000-0000-0000-000000000006
Description : This is the default group for everyone in the network
Mail        : allcompany@contoso.onmicrosoft.com
Visibility  : Public
GroupTypes  : Unified
```

> **`MembershipRule` is filled on the list.** Since inforcer fixed this (2026-11, verified live 2026-11-03),
> the list returns the rule for every `DynamicMembership` group on both APIs, and the list view shows it.

### Example output (ById)

```
DisplayName           : SG - Contoso - All Internal Users
Id                    : 00000000-0000-0000-0000-000000000007
Description           : This group contains all users in the organization.
Mail                  :
Visibility            :
GroupTypes            : DynamicMembership
MembershipRule        : (user.userType -eq "Member")
MailEnabled           : False
CreatedDateTime       : 2026-02-18T21:22:23+00:00
OnPremisesSyncEnabled : False (cloud-only)
Members               : (none)
```

`MembershipRule` appears only when the group has one — static groups render exactly as before, with no
blank row.

`OnPremisesSyncEnabled` is always shown, and distinguishes the API's three states rather than printing
a bare `True`/blank:

| API value | Rendered | Meaning |
|-----------|----------|---------|
| `true` | `True` | Synced from on-premises AD |
| `null` | `False (cloud-only)` | Never synced — created in the cloud |
| `false` | `False (no longer syncing)` | Was synced from on-premises AD, no longer is |

Both properties are on the object in raw API form (`membershipRule`, `onPremisesSyncEnabled`) and are
unaffected by the display formatting — `-OutputType JsonObject` and `Select-Object` see the raw values.

---

## Get-InforcerRole

Retrieves Entra ID directory role definitions from an inforcer tenant. Returns role definitions including display name, description, and whether the role is built-in, enabled, or privileged.

**Pipeline:** piped tenants (for example `Get-InforcerTenant | Get-InforcerRole`) are handled one by one; each result gets a `TenantId` property naming its tenant, and `-OutputType JsonObject` returns one JSON array for all of them. Calls without pipeline input are unchanged. With client credentials `-OutputType JsonObject` is always a JSON array (`[]` for no roles); with an API key one role is a bare JSON object, as in 0.8.0.

**Endpoints called (beta)**: `GET /beta/tenants/{tenantId}/roles` — plus `GET /beta/tenants` when `-TenantId` is a GUID or name (resolution).
**Required API scope(s) (API key, beta)**: `Tenants.Roles.Read` + `Tenants.Read` *(the `Tenants.Read` part can be skipped if `-TenantId` is always passed as a numeric Client Tenant ID — no lookup needed)*
**Endpoints on v1**: `GET /v1/tenants/{msTenantId}/directoryRoles`
**Required API client permission(s) (v1)**: Entra Dashboard + Tenants (only for a tenant name) *(unconfirmed, see [API client permissions](./API-REFERENCE.md#api-client-permissions-v1))*

| Parameter | Type | Mandatory | Description |
|-----------|------|-----------|--------------|
| **TenantId** | Object | Yes | Tenant (Microsoft tenant ID (GUID) or tenant name; numeric Client Tenant ID with an API key only). Aliases: `ClientTenantId`, `MsTenantId`. |
| **OutputType** | String | No | `PowerShellObject` (default) or `JsonObject`. |

### Examples

```powershell
# List all roles in a tenant
Get-InforcerRole -TenantId 'Contoso'

# Filter to privileged roles only
Get-InforcerRole -TenantId 'Contoso' | Where-Object IsPrivileged -eq $true

# Pipeline from Get-InforcerTenant
Get-InforcerTenant -TenantId 'Contoso' | Get-InforcerRole

# JSON output
Get-InforcerRole -TenantId 'Contoso' -OutputType JsonObject
```

### Example output

```
DisplayName  : Global Administrator
Id           : 00000000-0000-0000-0000-000000000008
Description  : Can manage all aspects of Microsoft Entra ID and Microsoft services that use Microsoft Entra identities.
IsBuiltIn    : True
IsEnabled    : True
IsPrivileged : True
```

---

## Get-InforcerSecureScore

Retrieves the current and historic Microsoft Secure Score for a tenant, including up to 90 days of daily score history, per-category breakdown, and actionable control profiles with remediation guidance.

**Pipeline:** piped tenants (for example `Get-InforcerTenant | Get-InforcerSecureScore`) are handled one by one; each result gets a `TenantId` property naming its tenant, and `-OutputType JsonObject` returns one JSON array for all of them. Calls without pipeline input are unchanged. Without pipeline input `-OutputType JsonObject` is one JSON object.

**Endpoints called (beta)**: `GET /beta/tenants/{tenantId}/secureScores` — plus `GET /beta/tenants` when `-TenantId` is a GUID or name (resolution).
**Required API scope(s) (API key, beta)**: `Tenants.SecureScores.Read` + `Tenants.Read` *(the `Tenants.Read` part can be skipped if `-TenantId` is always passed as a numeric Client Tenant ID — no lookup needed)*
**Endpoints on v1**: `GET /v1/tenants/{msTenantId}/secureScores`
**Required API client permission(s) (v1)**: Entra Dashboard + Tenants (only for a tenant name) *(unconfirmed, see [API client permissions](./API-REFERENCE.md#api-client-permissions-v1))*

**Output schema**: [TenantSecureScore](./API-REFERENCE.md#tenantsecurescoredetails) — includes `Scores` (90-day history), `ControlProfiles` (actionable recommendations), and `ControlCategoryScores`.

| Parameter | Type | Mandatory | Description |
|-----------|------|-----------|--------------|
| **TenantId** | Object | Yes | Tenant (Microsoft tenant ID (GUID) or tenant name; numeric Client Tenant ID with an API key only). Aliases: `ClientTenantId`, `MsTenantId`. |
| **OutputType** | String | No | `PowerShellObject` (default) or `JsonObject`. |

### Examples

```powershell
# Summary view for one tenant
$s = Get-InforcerSecureScore -TenantId 'Contoso'
$s

# Full recommendation list, biggest wins first
$s.ControlProfiles | Sort-Object ScoreDifference -Descending

# Top 10 quick wins as a compact table
$s.ControlProfiles | Sort-Object ScoreDifference -Descending | Select-Object -First 10 |
    Format-Table Title, ControlCategory, Service, ScoreDifference -AutoSize

# One specific recommendation with full detail (including HTML remediation)
$s.ControlProfiles | Where-Object Id -eq 'AdminMFAV2' | Select-Object *

# Unfinished work grouped by category with total potential gain
$s.ControlProfiles | Where-Object ScoreDifference -gt 0 |
    Group-Object ControlCategory |
    Select-Object Name, Count, @{n='TotalGain';e={($_.Group | Measure-Object ScoreDifference -Sum).Sum}}

# Score trend for the last 30 days
$s.Scores | Select-Object -First 30 CreatedDateTime, CurrentScore, CurrentScorePercentage

# Category history — Identity's daily scores
($s.ControlCategoryScores | Where-Object ControlCategory -eq 'Identity').HistoricScores |
    Format-Table CreatedDateTime, CurrentScore, MaxScore, CurrentScorePercentage -AutoSize

# Export the recommendations to CSV for a ticket
$s.ControlProfiles | Sort-Object ScoreDifference -Descending |
    Select-Object Title, ControlCategory, Service, CurrentScore, MaxScore, ScoreDifference, ActionUrl |
    Export-Csv ./secure-score-actions.csv -NoTypeInformation

# Open the fix page for the top recommendation
Start-Process ($s.ControlProfiles | Sort-Object ScoreDifference -Descending | Select-Object -First 1).ActionUrl

# Pipeline from Get-InforcerTenant
Get-InforcerTenant -TenantId 'Contoso' | Get-InforcerSecureScore

# JSON output
Get-InforcerSecureScore -TenantId 'Contoso' -OutputType JsonObject
```

### Example output (default list view)

```
CurrentScore           : 1002.88
MaxScore               : 1267
CurrentScorePercentage : 79.15
LicensedUserCount      : 0
EnabledServices        : HasAADP1, HasCASD, HasMDOP1, HasDLP, HasAIPP1, HasMDB, HasSPOP1
ScoreHistory           : 90 day(s), 2026-04-09 → 2026-07-07 (latest 1002.88 / 1267)
ControlCategoryScores  : Identity: 49.13/71, Apps: 177/198, Data: 7/9, Device: 769.75/989
ControlProfilesCount   : 64
TopRecommendations     : +10 Ensure multifactor authentication is enabled for all users in administrative roles
                         +8.75 Fix Microsoft Defender for Endpoint sensor data collection in macOS
                         +8.75 Fix Microsoft Defender for Endpoint impaired communications in macOS
Hint                   : Use $obj.ControlProfiles | Sort-Object ScoreDifference -Descending for the full list. .Scores / .ControlCategoryScores[0].HistoricScores for the history.
```

Each nested item in `.ControlProfiles` carries the PSTypeName `InforcerCommunity.SecureScoreControlProfile` and renders as a compact list (`Title`, `ControlCategory`, `Service`, current/max score with potential gain, `RemediationImpact`, `ActionUrl`, `Id`) — the full HTML `remediation` string is still on the object as `.remediation` when needed.

Use `| Select-Object *` to see all properties on any level.

---

## Export-InforcerTenantDocumentation

Generates comprehensive, human-readable documentation of an entire M365 tenant's configuration as managed through the inforcer API. Collects the tenant, its baselines and its policies, resolves Intune Settings Catalog settingDefinitionIDs to friendly names, and outputs in multiple formats.

The "Profile type" column comes from the policy's type name. The legacy API no longer sends that name, so with an API key the module fills it from the policy type id; a type id it does not know stays blank. Entra, SharePoint and Microsoft 365 settings policies show the name inforcer gives them.

Piped tenants are documented one by one, each with its own Graph data (no names carry over between tenants or calls). Pass a directory as `-OutputPath` when piping several tenants: a file path works for one tenant only, and a second piped tenant stops with an `OutputPathIsFileForSeveralTenants` error before anything is fetched for it.

> **Personal data:** written documents can contain names and UPNs (for example assignment and group details). See [Personal data](#personal-data).

**Endpoints called (beta)**: `GET /beta/tenants`, `GET /beta/baselines`, `GET /beta/tenants/{tenantId}/policies`; with `-Baseline` also `GET /beta/tenants/{tenantId}/alignmentDetails`.
**Required API scope(s) (API key, beta)**: `Tenants.Read` + `Baselines.Read` + `tenants.policies.Read`
**Endpoints on v1**: `GET /v1/tenants`, `GET /v1/tenants/{msTenantId}`, `GET /v1/baselines`, `GET /v1/tenants/{msTenantId}/policies`; with `-Baseline` also `GET /v1/tenants/{msTenantId}/alignmentDetails`
**Required API client permission(s) (v1)**: Tenants + Baselines + Policies (+ Align) *(unconfirmed, see [API client permissions](./API-REFERENCE.md#api-client-permissions-v1))*

The HTML output features a modern admin dashboard design with a collapsible sidebar navigation, search, tag filtering, dark/light mode toggle, and hide-empty-fields toggle. All output is self-contained (no external dependencies or CDN links).

| Parameter | Type | Mandatory | Description |
|-----------|------|-----------|--------------|
| **Format** | String | No | Output format: `Html` (default), `Markdown`, `Excel`. Excel creates an .xlsx workbook with one sheet per product (requires `ImportExcel` module). |
| **TenantId** | Object | Yes | Tenant to document (Microsoft tenant ID (GUID) or tenant name; numeric Client Tenant ID with an API key only). Aliases: `ClientTenantId`, `MsTenantId`. |
| **OutputPath** | String | No | Directory to write the output files to (auto-named `{TenantName}-Documentation.{ext}`). With a single `-Format` and a path that has a file extension, it is the output file itself; that works for one tenant only (see above). **No default** — omit it and no files are written; the DocModel is returned instead. |
| **Show** | Switch | No | Open the generated HTML in the default browser, each file once per call (also when tenants are piped). Requires `-OutputPath` and `-Format Html`. **Defaults to on interactively, off in CI** (`CI`, `TF_BUILD`, `GITHUB_ACTIONS`, `GITLAB_CI`, `JENKINS_URL`, `TEAMCITY_VERSION`, `BUILDKITE`). `-Show` forces it, `-Show:$false` suppresses it; an explicit value always wins. |
| **SettingsCatalogPath** | String | No | Path to a local `settings.json` for Intune Settings Catalog name resolution. When omitted, the latest data is downloaded from the [IntuneSettingsCatalogData](https://github.com/royklo/IntuneSettingsCatalogData) GitHub release and cached at `~/.inforcercommunity/data/settings.json` (~65 MB). The cache is used as is for 24 hours; after that the module checks the release and downloads only when a newer catalog exists. A download replaces the cache only when it is a valid catalog of at most 512 MB. Offline, the cached copy is used, or raw setting IDs when there is none. |
| **FetchGraphData** | Switch | No | Signs in to Microsoft Graph interactively for the exported tenant (or reuses an existing Graph session for that tenant that already has the scopes), then resolves IDs to names: assignment groups and filters, scope tags, and the groups, directory roles, named locations and applications in Conditional Access policies. Requests `Directory.Read.All`, `Policy.Read.All` and `DeviceManagementConfiguration.Read.All`. Requires the `Microsoft.Graph.Authentication` module; without it, or when sign-in fails, raw IDs are kept with a warning. See [Graph integration](#graph-integration--fetchgraphdata). |
| **Baseline** | String | No | Filter to policies belonging to a specific baseline (name or ID). |
| **Tag** | String | No | Filter to policies with a specific inforcer tag (case-insensitive). |

### Examples

```powershell
# Return the DocModel only (no file written)
Export-InforcerTenantDocumentation -Format Html -TenantId 'Contoso'

# Write HTML documentation to ./docs
Export-InforcerTenantDocumentation -Format Html -TenantId 'Contoso' -OutputPath ./docs

# Several tenants: pass a directory, one file per tenant
Get-InforcerTenant | Export-InforcerTenantDocumentation -Format Html -OutputPath ./docs -Show:$false

# Generate Markdown with baseline filter
Export-InforcerTenantDocumentation -Format Markdown -TenantId 'Contoso' -Baseline "Production"

# Generate Excel workbook with one sheet per product
Export-InforcerTenantDocumentation -Format Excel -TenantId 'Contoso'

# Full HTML with Graph data resolution (group names, filter names, scope tags)
Connect-Inforcer -ApiKey $key -Region uk -FetchGraphData
Export-InforcerTenantDocumentation -Format Html -TenantId 'Contoso' -FetchGraphData

# Filter by tag
Export-InforcerTenantDocumentation -Format Html -TenantId 'Contoso' -Tag "Tier 1"
```

### Output

With `-OutputPath`: returns `FileInfo` objects for the exported file(s). Without it: no files are written and the DocModel (hashtable) is returned instead, so the tenant configuration can be read without producing artefacts. HTML output opens in the default browser automatically in an interactive session, and not on a CI runner — see `-Show`.

- **Excel:** values that start with `=` are written as text with a leading apostrophe (`'=…`), so a value from a tenant never runs as a formula, and web addresses are not turned into links.
- **Markdown:** `&`, `<` and `>` in table cells, the tenant name and policy headings are written as `&amp;`, `&lt;` and `&gt;`; they look the same once rendered.
- **HTML:** names with quotes or markup show as plain text (search highlight and filters included).

### HTML features

- Modern glassmorphism sidebar with collapsible Product > Category > Policy hierarchy
- Tag filter pills for AND/OR filtering by inforcer tags
- Real-time search bar with text highlighting
- Dark/Light mode toggle (persisted via localStorage)
- Hide empty fields toggle (on by default, scoped to Basics/Settings sections only)
- Show metadata toggle for @odata properties
- Back-to-top floating button
- Notch-style status bar showing tenant/baseline name and policy count
- Collapsible long values with Expand/Collapse button
- Collapsible code blocks for detection/remediation scripts (PowerShell/Bash syntax highlighting), compliance rules JSON (JSON syntax highlighting), and macOS/iOS `.mobileconfig` payloads (decoded from base64 to the plist XML, with XML syntax highlighting)
- Binary base64 fields are left as base64 rather than decoded into unreadable text — `hashedScriptContent` is a digest, not a script
- Code blocks keep their original indentation and scroll horizontally; lines are never re-wrapped or broken mid-identifier
- Friendly setting names — camelCase property names converted to Title Case (e.g., `allowBluetooth` → "Allow Bluetooth")
- Categories sorted alphabetically, grouped by platform
- Policy tags shown inline as blue-bordered badges
- "None" displayed for policies without assignments

### Graph integration (`-FetchGraphData`)

When `-FetchGraphData` is specified, the cmdlet signs in to Graph for the exported tenant (or reuses a Graph session for that tenant that already has the three scopes) and builds its name maps fresh for every tenant:

| Graph call | Resolves | Delegated scope |
|------------|----------|-----------------|
| `POST /v1.0/directoryObjects/getByIds` (up to 1000 IDs per request) | Groups and users in assignments and Conditional Access | `Directory.Read.All` |
| `GET /v1.0/roleManagement/directory/roleDefinitions` | Directory roles in Conditional Access, built-in and custom | `Directory.Read.All` |
| `GET /v1.0/servicePrincipals?$filter=appId in (…)` (15 IDs per request) | Applications in Conditional Access; a built-in name list is used only for apps the tenant does not return | `Directory.Read.All` |
| `GET /v1.0/identity/conditionalAccess/namedLocations` | Named locations in Conditional Access | `Policy.Read.All` |
| `GET /beta/deviceManagement/assignmentFilters` | Assignment filters | `DeviceManagementConfiguration.Read.All` |
| `GET /beta/deviceManagement/roleScopeTags` | Scope tags | `DeviceManagementConfiguration.Read.All` |

- The Graph tenant is validated against the inforcer tenant's `msTenantId`.
- Throttling (`429`), server errors (`5xx`) and network failures are retried. A refused call (`401`/`403`) is not retried: a warning names the likely missing scope and those names stay as raw IDs.
- A list stops at 10,000 items, with a warning when that cuts it short.

### Value enrichment

Applied automatically (no `-FetchGraphData` required):
- Conditional Access camelCase property names are mapped to friendly labels (e.g., `includeGroups` → "Include Groups")
- Authentication combination values are mapped to readable names (e.g., `windowsHelloForBusiness` → "Windows Hello for Business")
- ISO 8601 durations are converted to friendly text (e.g., `PT0S` → "0 (immediate)", `P30D` → "30 days")
- Settings Catalog is only loaded when Intune/Defender policies (policyTypeId 10) are present

---

## Compare-InforcerEnvironments

Compares the Intune policy configuration of two tenants and generates an interactive HTML report. Supports baseline-scoped comparison via `-SourceBaselineId` / `-DestinationBaselineId` to compare only policies belonging to a specific baseline. Uses the shared DocModel pipeline to normalize both environments, then diffs settings at the `settingDefinitionId` level. The report includes tabs for Comparison, Manual Review, Duplicates, and Deprecated settings.

Source and destination are collected at the same time (the destination in a background runspace), so a comparison takes about as long as its slower side; the destination's warnings appear after the source's progress lines.

The two sides may use different logins: pass `-SourceSession` from an API-key `Connect-Inforcer -PassThru` and `-DestinationSession` from a client-credentials one (or the reverse). Such a comparison pairs policies by `Basics.Id`, which is the inforcer ID on beta and the Microsoft policy ID on v1, so across logins the ids never match and policies are paired by their settings instead.

**Endpoints called (beta)**: `GET /beta/tenants`, `GET /beta/baselines`, `GET /beta/tenants/{tenantId}/policies` per side; with a baseline also `GET /beta/tenants/{tenantId}/alignmentDetails`.
**Required API scope(s) (API key, beta)**: `Tenants.Read` + `Baselines.Read` + `tenants.policies.Read`
**Endpoints on v1**: `GET /v1/tenants`, `GET /v1/tenants/{msTenantId}`, `GET /v1/baselines`, `GET /v1/tenants/{msTenantId}/policies` per side; with a baseline also `GET /v1/tenants/{msTenantId}/alignmentDetails`
**Required API client permission(s) (v1)**: Tenants + Baselines + Policies (+ Align) *(unconfirmed, see [API client permissions](./API-REFERENCE.md#api-client-permissions-v1))*

| Parameter | Type | Mandatory | Description |
|-----------|------|-----------|--------------|
| **SourceTenantId** | Object | No | Source tenant (Microsoft tenant ID (GUID) or tenant name; numeric Client Tenant ID with an API key only). Can be omitted when `-SourceBaselineId` is specified — the baseline owner tenant is auto-resolved. |
| **DestinationTenantId** | Object | No | Destination tenant (Microsoft tenant ID (GUID) or tenant name; numeric Client Tenant ID with an API key only). Can be omitted when `-DestinationBaselineId` is specified — the baseline owner tenant is auto-resolved. |
| **SourceSession** | Hashtable | No | Session from `Connect-Inforcer -PassThru`. Defaults to current session. |
| **DestinationSession** | Hashtable | No | Session from `Connect-Inforcer -PassThru`. Defaults to current session. |
| **SourceBaselineId** | String | No | Baseline GUID or friendly name for the source tenant. Scopes comparison to only policies in this baseline. The destination is scoped to the same baseline unless `-DestinationBaselineId` is given; if the destination is not a member, it is compared in full, with a warning. |
| **DestinationBaselineId** | String | No | Baseline GUID or friendly name for the destination tenant. Scopes comparison to only policies in this baseline. Defaults to `-SourceBaselineId`. |
| **IncludingAssignments** | Switch | No | Include assignment data in the report (informational only, does not affect score). |
| **FetchGraphData** | Switch | No | Sign in to Microsoft Graph for each tenant to resolve group names, assignment filters, scope tags and compliance rules. Requests `Directory.Read.All`, `Policy.Read.All` and `DeviceManagementConfiguration.Read.All`; a call Graph refuses leaves those names as raw IDs, with a warning. |
| **ExcludeOS** | String[] | No | OS/platform or product names to exclude. Case-insensitive contains matching, applied to both the product name (`Entra`, `Intune`, `Defender`, `Exchange`, `SharePoint`) and the category key, which is where the OS actually lives (`Windows`, `macOS`, `iOS/iPadOS`, `Android`). Examples: `'macOS'`, `'iOS'`, `'Android'`, `'Windows'`. |
| **PolicyNameFilter** | String | No | Only include policies whose name contains this string (case-insensitive). |
| **SettingsCatalogPath** | String | No | Path to a local `settings.json` for Intune Settings Catalog name resolution. When omitted, the latest data is downloaded from the [IntuneSettingsCatalogData](https://github.com/royklo/IntuneSettingsCatalogData) GitHub release and cached at `~/.inforcercommunity/data/settings.json` (~65 MB). The cache is used as is for 24 hours; after that the module checks the release and downloads only when a newer catalog exists. A download replaces the cache only when it is a valid catalog of at most 512 MB. Offline, the cached copy is used, or raw setting IDs when there is none. |
| **OutputPath** | String | No | Directory for the HTML report. **No default** — omit it and no file is written; the comparison model is returned instead. |
| **Show** | Switch | No | Open the generated HTML in the default browser. Requires `-OutputPath`. **Defaults to on interactively, off in CI** (`CI`, `TF_BUILD`, `GITHUB_ACTIONS`, `GITLAB_CI`, `JENKINS_URL`, `TEAMCITY_VERSION`, `BUILDKITE`). `-Show` forces it, `-Show:$false` suppresses it; an explicit value always wins. |

### Examples

```powershell
# Basic comparison (same inforcer account)
Compare-InforcerEnvironments -SourceTenantId 'Contoso' -DestinationTenantId 'Fabrikam'

# Cross-account comparison with Graph enrichment
$src = Connect-Inforcer -ApiKey $key1 -Region uk -PassThru
$dst = Connect-Inforcer -ApiKey $key2 -Region eu -PassThru
Compare-InforcerEnvironments -SourceTenantId 'Contoso' -DestinationTenantId 'Fabrikam' `
    -SourceSession $src -DestinationSession $dst -FetchGraphData

# Exclude macOS and filter by policy name
Compare-InforcerEnvironments -SourceTenantId 'Contoso' -DestinationTenantId 'Fabrikam' `
    -ExcludeOS 'macOS' -PolicyNameFilter 'Defender'

# Compare a baseline on both tenants (the destination is scoped to the same baseline)
Compare-InforcerEnvironments -SourceTenantId 'Contoso' -SourceBaselineId 'Tier 1 Foundations' `
    -DestinationTenantId 'Fabrikam'

# Compare a baseline without specifying the owner tenant (auto-resolved)
Compare-InforcerEnvironments -SourceBaselineId 'Inforcer Blueprint Baseline - Tier 1 - Foundations' `
    -DestinationTenantId 'Fabrikam'

# Compare two baselines from different tenants
Compare-InforcerEnvironments -SourceTenantId 'Contoso' -SourceBaselineId 'Tier 1' `
    -DestinationTenantId 'Fabrikam' -DestinationBaselineId 'Tier 2'
```

### Output

With `-OutputPath`: returns a `FileInfo` object for the exported HTML report. Without it: no file is written and the comparison model (hashtable) is returned instead, so alignment scores can be read without producing artefacts. The report opens in the default browser automatically in an interactive session, and not on a CI runner — see `-Show`.

### HTML report features

- **Comparison tab**: Flat table with all Settings Catalog settings, sortable columns, status filter pills (Matched/Conflicting/Source Only/Dest Only), category dropdown, advanced column filters with AND/OR logic, search
- **Manual Review tab**: Non-Settings-Catalog policies (compliance, enrollment, scripts) in a 50/50 source/destination layout grouped by platform. Matching policy names aligned side-by-side. Independent column layout — expanding a policy on one side does not affect the other. Collapsible code blocks with syntax highlighting for scripts (PowerShell/Bash), compliance rules (JSON), and macOS/iOS `.mobileconfig` payloads (decoded plist XML). Code blocks keep their indentation and scroll horizontally rather than re-wrapping
- **Duplicates tab**: Settings configured in 2+ policies with different values, with automated analysis
- **Deprecated tab**: Settings flagged as deprecated by Microsoft, grouped by source/destination
- **Configuration Match score**: Animated percentage with color gradient, confetti at 100%
- Dark/light mode toggle, responsive layout, column resize handles

### Graph enrichment (`-FetchGraphData`)

When specified, connects to Microsoft Graph for each tenant (same scopes and retry rules as [Export](#graph-integration--fetchgraphdata)):
- Group/user ObjectIDs resolved to display names (`POST /v1.0/directoryObjects/getByIds`)
- Assignment filter and scope tag IDs resolved to names
- Compliance policy detection rules (`rulesContent`) fetched per policy (`GET /beta/deviceManagement/deviceCompliancePolicies('{id}')`, `DeviceManagementConfiguration.Read.All`)
- Discovery scripts linked to parent compliance policies

---

## Get-InforcerSupportedEventType

Returns the list of supported audit event type names from the inforcer API (the live list; without a session, or when the call fails, the last list it got is returned, which is a built-in list of 80 until the first successful call). It also refreshes the `-EventType` tab completion of `Get-InforcerAuditEvent`. `Get-InforcerAuditEvent` itself no longer calls it.

**Endpoints called (beta)**: `GET /beta/auditEvents/eventTypes`
**Required API scope(s) (API key, beta)**: `Audit.Read` *(not in the API team's published scope→route mapping — the route `/beta/auditEvents/eventTypes` is unmapped; `Audit.Read` is the assumed scope based on naming. Confirm with inforcer API team.)*
**Endpoints on v1**: `GET /v1/auditEvents/types`
**Required API client permission(s) (v1)**: Activity *(unconfirmed, see [API client permissions](./API-REFERENCE.md#api-client-permissions-v1))*

No parameters.

### Example

```powershell
Get-InforcerSupportedEventType
```

### Example output

```
authentication
failedAuthentication
policyChange
userCreated
```

---

## Get-InforcerAssessment

Retrieves available assessments from the inforcer API. Returns a list of assessments that can be run against tenants via `Invoke-InforcerAssessment`.

**Endpoints called (beta)**: `GET /beta/assessments`
**Required API scope(s) (API key, beta)**: `Assessments.Read`
**Endpoints on v1**: `GET /v1/assessments`
**Required API client permission(s) (v1)**: Tenant Assessment *(unconfirmed, see [API client permissions](./API-REFERENCE.md#api-client-permissions-v1))*

**Output schema**: [Assessment](./API-REFERENCE.md#assessment)

| Parameter | Type | Mandatory | Description |
|-----------|------|-----------|-------------|
| **Format** | String | No | `Raw` (default). |
| **OutputType** | String | No | `PowerShellObject` (default) or `JsonObject`. JSON uses Depth 100. |

### Examples

```powershell
Get-InforcerAssessment
Get-InforcerAssessment -OutputType JsonObject
```

### Example output

```
Name           : CIS Microsoft 365 Foundations Benchmark
Id             : assess-001
Description    : Checks M365 configuration against CIS benchmark controls.
AssessmentType : Compliance
Tags           : {CIS, M365}
LastUpdated    : 2025-01-15T00:00:00Z
Created        : 2024-06-01T00:00:00Z
```

---

## Invoke-InforcerAssessment

Runs an assessment against one or more inforcer tenants and outputs per-check results to the pipeline. Supports friendly assessment name resolution, multi-tenant execution, and optional HTML/CSV export.

Piped tenants are collected into one multi-tenant run, the same as passing them to `-TenantId`; a single piped tenant also adds `TenantId` to each check. With client credentials a throttled run (`429`) is retried after `Retry-After` and a `401` renews the token once; with an API key neither is retried. A run that answers with a redirect fails with a clear message.

**Endpoints called (beta)**: `GET /beta/tenants`, `GET /beta/assessments`, `POST /beta/tenants/{tenantId}/assessments/{assessmentId}/runs`
**Required API scope(s) (API key, beta)**: `Tenants.Read` + `Assessments.Read` + `Assessments.Run`
**Endpoints on v1**: `GET /v1/tenants`, `GET /v1/assessments`, `POST /v1/tenants/{msTenantId}/assessments/{assessmentId}/runs`
**Required API client permission(s) (v1)**: Tenants + Tenant Assessment *(unconfirmed, see [API client permissions](./API-REFERENCE.md#api-client-permissions-v1))*

| Parameter | Type | Mandatory | Description |
|-----------|------|-----------|-------------|
| **TenantId** | Object[] | No | One or more tenants (Microsoft tenant ID (GUID) or tenant name; numeric Client Tenant ID with an API key only). Accepts arrays, friendly names and pipeline input: piped tenants are collected into one multi-tenant run. Required unless `-MultiTenant` is specified. Aliases: `ClientTenantId`, `MsTenantId`. |
| **AssessmentId** | String | Yes | Assessment ID or friendly name to run. |
| **MultiTenant** | Switch | No | Run the assessment against all tenants in the account. |
| **OutputPath** | String | No | File path for an export; the extension picks the format: `.html`/`.htm` (report, or a matrix report for several tenants) or `.csv` (with a tenant column for several tenants). Any other extension, or a directory, fails with `UnsupportedFormat`. Returns a `FileInfo`. CSV values that start with `=`, `+`, `-`, `@`, a tab or a carriage return get a leading `'`, so Excel shows them as text instead of running them as formulas. When omitted, results stream to the pipeline only. |
| **OutputType** | String | No | `PowerShellObject` (default) or `JsonObject`. JSON uses Depth 100. |

### Examples

```powershell
# Run against a single tenant
Invoke-InforcerAssessment -TenantId 'Contoso' -AssessmentId "CIS Microsoft 365 Foundations Benchmark"

# Run against all tenants
Invoke-InforcerAssessment -AssessmentId "assess-001" -MultiTenant

# Export results to HTML
Invoke-InforcerAssessment -TenantId 'Contoso' -AssessmentId "assess-001" -OutputPath C:\Reports\assessment.html

# Several tenants, CSV with a tenant column
Invoke-InforcerAssessment -TenantId 'Contoso', 'Fabrikam' -AssessmentId "assess-001" -OutputPath ./assessment.csv

# JSON output
Invoke-InforcerAssessment -TenantId 'Contoso' -AssessmentId "assess-001" -OutputType JsonObject
```

### Example output

```
Status           : Pass
name             : Ensure MFA is enabled for all users
category         : Identity
subCategory      : Authentication
importance       : High
ObjectsEvaluated : 42
FindingsMessage  : All users have MFA enabled.
Scores           : {@{objectId=00000000-0000-0000-0000-000000000001; score=100; objectName=Contoso; ...}}
```

### Status values

`Status` is `Pass`, `Fail`, `InsufficientPermissions` or `Error`. The last two mean the API could not assess the check (missing permissions, or data that could not be read from the tenant). They are not counted as failures, and the HTML reports show them as **Not Assessed**. The compliance score is inforcer's own score with client credentials (the run's `summary.score`, the number the portal shows, rounded down to a whole percentage); with an API key, which has no score, it is `Pass ÷ (Pass + Fail)` to one decimal. Multi-tenant `-OutputType JsonObject` reports them per tenant as `NotAssessed`, next to `Passed` and `Failed`.

---

## Get-InforcerReportType

Lists available report types from the inforcer Reports API. The catalog is cached in the module session; pass `-Force` to refetch.

**Endpoints called (beta)**: `GET /beta/reports/types`
**Required API scope(s) (API key, beta)**: `Reports.Read`
**Endpoints on v1**: `GET /v1/reports/types`
**Required API client permission(s) (v1)**: Reports *(unconfirmed, see [API client permissions](./API-REFERENCE.md#api-client-permissions-v1))*

**Output schema**: [ReportType](./API-REFERENCE.md#reporttype)

| Parameter | Type | Mandatory | Description |
|-----------|------|-----------|-------------|
| **Key** | String | No | Filter to a single report type by key (case-insensitive). Aliases: `-Name`, `-ReportType`. |
| **Tag** | String | No | Filter to types containing the specified tag. |
| **OutputFormat** | String | No | Filter to types that support the specified output format. |
| **Force** | Switch | No | Bypass the in-memory cache and refetch the catalog. |
| **Format** | String | No | `Raw` (default). |
| **OutputType** | String | No | `PowerShellObject` (default) or `JsonObject`. JSON uses Depth 100. |

### Examples

```powershell
Get-InforcerReportType
Get-InforcerReportType -Key CopilotAdoption
Get-InforcerReportType -OutputFormat pdf
Get-InforcerReportType -Tag security
Get-InforcerReportType -OutputType JsonObject
```

### Example output

```
Key            : CopilotAdoption
Name           : Copilot Adoption
Description    : Usage trends and adoption rates for Microsoft 365 Copilot.
Collatable     : True
OutputFormats  : csv, json
Tags           : Copilot, Productivity
Parameters     : report-period
```

---

## Invoke-InforcerReport

Queues one or more inforcer reports, polls the outputs endpoint until each run is terminal, and saves the outputs to disk. Use `-NoWait` to return immediately, or `-NoSave` to poll without downloading.

Saving follows the [download rules](#download-rules) of `Save-InforcerReportOutput`: existing files are never overwritten. With client credentials a numeric `-TenantId` fails with an error that says to pass the Microsoft tenant ID (GUID) or tenant name (ErrorId `TenantResolutionFailed` here; the other cmdlets use `InvalidTenantId`).

**Endpoints called (beta)**: `POST /beta/reports/runs`, `GET /beta/reports/runs/{runId}/outputs`, `GET /beta/reports/runs/{runId}/outputs/{outputId}`, `GET /beta/tenants` *(GUID/name lookup)*
**Required API scope(s) (API key, beta)**: `Reports.Read` + `Reports.Run` + `Tenants.Read`†
**Endpoints on v1**: `POST /v1/reports/runs`, `GET /v1/reports/runs/{reportRunId}/outputs[/{outputId}]`, `GET /v1/tenants` (tenant name)
**Required API client permission(s) (v1)**: Reports + Tenants (only for a tenant name) *(unconfirmed, see [API client permissions](./API-REFERENCE.md#api-client-permissions-v1))*

| Parameter | Type | Mandatory | Description |
|-----------|------|-----------|-------------|
| **ReportType** | String[] | Yes | One or more report type keys. Aliases: `-Key`. |
| **OutputFormat** | String[] | Yes | One or more output formats. Zip rules: 1 format broadcasts to all reports; N formats pair by index; any other count errors. |
| **TenantId** | Object[] | Yes | One or more tenants (Microsoft tenant ID (GUID) or tenant name; numeric Client Tenant ID with an API key only). Aliases: `ClientTenantId`, `MsTenantId`. |
| **ReportPeriod** | Int | No | Days for the `report-period` parameter. CopilotAdoption / ShadowAiDetection auto-default to 30. |
| **AssessmentId** | String | No | Required when `-ReportType Assessment`. The assessment identifier (alphanumeric string, not a GUID — inforcer assessment IDs look like `l1f8wd29pl44pp1j66r9`). Tab-completes against `Get-InforcerAssessment`. |
| **Parameter** | Hashtable | No | Escape hatch for future API parameters. Keys validated against the type's catalog entry. |
| **Collate** | Switch | No | Request a single cross-tenant output. Rejected when the type's catalog says `collatable: false`. |
| **NoWait** | Switch | No | Return immediately after `POST` with run identifiers. Skip polling and download. |
| **NoSave** | Switch | No | Poll until terminal but do not write files. Returns outputs metadata. |
| **Open** | Switch | No | After each output is saved, launch it with the OS default handler (`Invoke-Item`). Only `.csv`, `.json`, `.html`, `.htm`, `.pdf`, `.xlsx`, `.xml`, `.txt`, `.zip`, `.md` and `.tsv` files are launched; for any other extension (`.xls` included) the output folder is opened instead, with a warning. Ignored when `-NoWait` or `-NoSave` is also set (emits a warning). Aliases: `-Show`, `-ShowResult`. |
| **OutputPath** | String | No | Directory for downloaded outputs. Default: current working directory. Existing files are never overwritten (see [download rules](#download-rules)). |
| **TimeoutSeconds** | Int | No | Maximum wait per run when polling. Default: 600. |
| **PollIntervalSeconds** | Int | No | Initial poll interval (doubles up to 15s cap). Default: 2. |
| **Format** | String | No | `Raw` (default). |
| **OutputType** | String | No | `PowerShellObject` (default) or `JsonObject`. |

> † `Tenants.Read` is only consumed when `-TenantId` is a GUID or tenant name (which triggers `Resolve-InforcerTenantId`). Numeric `-TenantId` calls skip the tenant-list lookup.

### Examples

```powershell
# Single report, single tenant — saves ActiveUserCount-<id>.csv to the current directory
Invoke-InforcerReport -ReportType ActiveUserCount -OutputFormat csv -TenantId 'Contoso'

# Two reports, paired formats — TenantAuditReport→pdf, ActiveUserCount→csv
Invoke-InforcerReport -ReportType TenantAuditReport, ActiveUserCount -OutputFormat pdf, csv -TenantId 'Contoso'

# Cross-tenant, broadcast format — same csv format for both
Invoke-InforcerReport -ReportType CopilotAdoption -OutputFormat csv -TenantId 'Contoso', 'Fabrikam'

# Async — return RunIds immediately
Invoke-InforcerReport -ReportType ActiveUserCount -OutputFormat csv -TenantId 'Contoso' -NoWait

# Assessment report
Invoke-InforcerReport -ReportType Assessment -AssessmentId l1f8wd29pl44pp1j66r9 -OutputFormat pdf -TenantId 'Contoso'

# Save and immediately open the file with the OS default handler
Invoke-InforcerReport -ReportType TenantAuditReport -OutputFormat html -TenantId 'Contoso' -Open

# Discover-then-run pipeline — every Security-tagged type queued in one batch (Key alias on
# Get-InforcerReportType binds to -ReportType via ValueFromPipelineByPropertyName).
Get-InforcerReportType -Tag Security | Invoke-InforcerReport -OutputFormat csv -TenantId 'Contoso'

# JSON output
Invoke-InforcerReport -ReportType ActiveUserCount -OutputFormat csv -TenantId 'Contoso' -OutputType JsonObject
```

### Example output (default sync + save)

```
RunId         : 00000000-0000-0000-0000-000000000009
ReportType    : ActiveUserCount
OutputFormat  : csv
TenantId      : 00000000-0000-0000-0000-000000000001
FilePath      : /path/to/output/ActiveUserCount_2026-06-26.csv
FileName      : ActiveUserCount_2026-06-26.csv
FileSize      : 12480
ContentType   : text/csv
```

### Example output (-NoWait)

The POST response is intentionally minimal — `RunId` is the only property the API returns. Poll status with `Get-InforcerReportRun -RunId <id>` or `Get-InforcerReportRun -RunId <id> -Wait -IncludeOutputs`.

```
RunId : 00000000-0000-0000-0000-000000000009
```

---

## Get-InforcerReportRun

Lists report runs from the inforcer Reports API. The list endpoint has a ~4-minute propagation lag for fresh runs and a server-side 500-item / 7-day cap; use `-Wait` with `-RunId` to bypass the lag by polling the outputs endpoint directly.

**Endpoints called (beta)**: `GET /beta/reports/runs`, `GET /beta/reports/runs/{runId}/outputs` *(with `-Wait` or `-IncludeOutputs`)*
**Required API scope(s) (API key, beta)**: `Reports.Read`
**Endpoints on v1**: `GET /v1/reports/runs`, `GET /v1/reports/runs/{reportRunId}/outputs`
**Required API client permission(s) (v1)**: Reports *(unconfirmed, see [API client permissions](./API-REFERENCE.md#api-client-permissions-v1))*

**Output schema**: [ReportRun](./API-REFERENCE.md#reportrun)

| Parameter | Type | Mandatory | Description |
|-----------|------|-----------|-------------|
| **RunId** | Guid | No | Filter to a single run. Required with `-Wait`. |
| **Wait** | Switch | No | Poll the outputs endpoint until the run is terminal (or `-TimeoutSeconds` elapses). |
| **IncludeOutputs** | Switch | No | Fetch outputs for every returned run. Adds one API call per run. |
| **TimeoutSeconds** | Int | No | Maximum wait when polling. Default: 600. |
| **PollIntervalSeconds** | Int | No | Initial poll interval. Default: 2. |
| **Format** | String | No | `Raw` (default). |
| **OutputType** | String | No | `PowerShellObject` (default) or `JsonObject`. |

### Examples

```powershell
Get-InforcerReportRun
Get-InforcerReportRun -RunId 00000000-0000-0000-0000-000000000009
Get-InforcerReportRun -RunId 00000000-0000-0000-0000-000000000009 -Wait
Get-InforcerReportRun -IncludeOutputs
Get-InforcerReportRun -OutputType JsonObject
```

### Example output

A run can batch multiple report types and output formats under a single `RunId`, so `ReportTypes` and `OutputFormats` are plural arrays.

```
RunId           : 00000000-0000-0000-0000-000000000009
Status          : completed
ReportTypes     : {activeusercount, globaladmins}
OutputFormats   : {csv}
TriggeredByType : user
CreatedAt       : 2026-06-26T14:01:23Z
CompletedAt    : 2026-06-26T14:01:29Z
OutputCount     : 2
```

---

## Save-InforcerReportOutput

Downloads a report output to disk. Pipeline-friendly: pipe output records from `Invoke-InforcerReport -NoSave` or `Get-InforcerReportRun -IncludeOutputs` to download every output in bulk.

### Download rules

These apply here and to the save step of `Invoke-InforcerReport`:

- **File name:** the server's `Content-Disposition` name (including the RFC 5987 form), reduced to a safe file name with no folder part. A name that starts with a dot gets a leading underscore (`.csv` becomes `_.csv`). `-FileName` replaces it; the server's name is then not used at all.
- **No overwrite:** an existing file is never replaced. When the name is taken, the output is saved as `name (1).ext`, `name (2).ext`, and so on.
- **Redirects:** the download carries your credential, so a redirect (HTTP 3xx) is not followed; it fails with `DownloadFailed_<status>` and a message naming the target.
- **Retries:** with client credentials a `401` renews the token and retries once. A `429` is not retried for downloads.
- **Windows:** saved files are marked as downloaded from the internet (`Zone.Identifier`), so Office opens them in Protected View.

> **Personal data:** saved outputs can contain names and UPNs. See [Personal data](#personal-data).

**Endpoints called (beta)**: `GET /beta/reports/runs/{runId}/outputs/{outputId}`
**Required API scope(s) (API key, beta)**: `Reports.Read`
**Endpoints on v1**: `GET /v1/reports/runs/{reportRunId}/outputs/{outputId}`
**Required API client permission(s) (v1)**: Reports *(unconfirmed, see [API client permissions](./API-REFERENCE.md#api-client-permissions-v1))*

| Parameter | Type | Mandatory | Description |
|-----------|------|-----------|-------------|
| **RunId** | Guid | Yes | The run identifier. Pipeline-bindable. |
| **OutputId** | String | Yes | The output identifier. Pipeline-bindable. Alias: `-Id`. |
| **ReportType** | String | No | Pipeline-bindable pass-through. Auto-populated when piped from `Invoke-InforcerReport -NoSave` or `Get-InforcerReportRun -IncludeOutputs`. Surfaced on the result object for parity with `Invoke-InforcerReport`. `$null` when called standalone. |
| **OutputFormat** | String | No | Pipeline-bindable pass-through. Same behavior as `-ReportType`. |
| **TenantId** | Object | No | Pipeline-bindable pass-through. Aliases: `ClientTenantId`, `MsTenantId`. Same behavior as `-ReportType`. |
| **OutputPath** | String | No | Target directory. Default: current working directory. Created if missing. Existing files are never overwritten. |
| **FileName** | String | No | Save under this name instead of the server's (made safe for the file system). The server's name is not written at all. |
| **OutputType** | String | No | `PowerShellObject` (default) or `JsonObject`. |

### Examples

```powershell
# Single download
Save-InforcerReportOutput -RunId 00000000-0000-0000-0000-000000000009 -OutputId out-1

# Bulk download via pipeline
Invoke-InforcerReport -ReportType ActiveUserCount -OutputFormat csv -TenantId 'Contoso' -NoSave |
    Save-InforcerReportOutput -OutputPath ./reports

# Bulk download from every visible run
Get-InforcerReportRun -IncludeOutputs |
    ForEach-Object { $_.outputs } |
    Save-InforcerReportOutput -OutputPath ./bulk

# Own file name; result as JSON
Save-InforcerReportOutput -RunId 00000000-0000-0000-0000-000000000009 -OutputId out-1 -FileName users.csv -OutputType JsonObject
```

### Example output

```
RunId         : 00000000-0000-0000-0000-000000000009
ReportType    : ActiveUserCount
OutputFormat  : csv
TenantId      : 00000000-0000-0000-0000-000000000001
FilePath      : /path/to/output/ActiveUserCount_2026-06-26.csv
FileName      : ActiveUserCount_2026-06-26.csv
FileSize      : 12480
ContentType   : text/csv
```

`OutputId` and `CorrelationId` are on the object too (`Select-Object *`). `TenantId`, `ReportType`, and `OutputFormat` are populated automatically when piped from `Invoke-InforcerReport -NoSave` or `Get-InforcerReportRun -IncludeOutputs`; they are `$null` when the cmdlet is called standalone with bare `-RunId` / `-OutputId`.

---

## See also

- **[API-REFERENCE.md](./API-REFERENCE.md)** — Detailed API schemas and response structures.
- **[README.md](../README.md)** — Installation and quick start.
- **[CONTRIBUTING.md](../CONTRIBUTING.md)** — How to contribute and report bugs.
- **Get-Help \<CmdletName\> -Full** — Full comment-based help in the module.
