# inforcer API Reference

This document describes the inforcer REST API endpoints, schemas, and response structures used by the InforcerCommunity PowerShell module.

> **Note**: This is a technical reference for the underlying API. For PowerShell cmdlet usage, see [CMDLET-REFERENCE.md](./CMDLET-REFERENCE.md).

---

## Table of Contents

- [Authentication](#authentication)
  - [Redirects](#redirects)
  - [Session caches](#session-caches)
- [API Scopes](#api-scopes) (API key, beta)
- [API client permissions (v1)](#api-client-permissions-v1)
- [v1 API (client credentials)](#v1-api-client-credentials)
  - [Token](#token)
  - [Response envelope](#response-envelope)
  - [Errors](#errors)
  - [Pagination](#pagination)
  - [Rate limits](#rate-limits)
  - [failedPolicyTypes](#failedpolicytypes)
  - [v1 endpoints](#v1-endpoints)
  - [Managing users (v1 only)](#managing-users-v1-only)
  - [How v1 fields map to the module's names](#how-v1-fields-map-to-the-modules-names)
    - [Alignment details renames](#alignment-details-renames)
- [Beta endpoints](#beta-endpoints)
  - [Baselines](#baselines)
  - [Alignment Scores](#alignment-scores)
  - [Alignment Details](#alignment-details)
  - [Tenants](#tenants)
  - [Tenant Policies](#tenant-policies)
  - [Audit Events](#audit-events)
  - [Users](#users)
  - [Groups](#groups)
  - [Roles](#roles)
  - [Secure Scores](#secure-scores)
  - [Assessments](#assessments)
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
  - [CreatedUser](#createduser)
  - [UserUpdate](#userupdate)
  - [PasswordReset](#passwordreset)
  - [UserAuthenticationMethod](#userauthenticationmethod)
  - [TenantGroupSummary](#tenantgroupsummary)
  - [TenantGroup](#tenantgroup)
  - [TenantRole](#tenantrole)
  - [TenantSecureScoreDetails](#tenantsecurescoredetails)
  - [TenantSecureScoreHistoryPoint](#tenantsecurescorehistorypoint)
  - [TenantSecureScoreControlProfile](#tenantsecurescorecontrolprofile)
  - [Assessment](#assessment)
  - [AssessmentCheck](#assessmentcheck)
  - [ReportType](#reporttype)
  - [ReportRun](#reportrun)
  - [ReportOutput](#reportoutput)
- [Microsoft Graph](#microsoft-graph) (optional, `-FetchGraphData`)
- [Response Wrapper](#response-wrapper-beta)
- [Error Responses](#error-responses-beta)

---

## Authentication

The module supports two logins; the API version follows from the login. Use `Connect-Inforcer` to establish a session before calling other cmdlets.

| | Client credentials (recommended) | API key (legacy) |
|---|---|---|
| Cmdlet | `Connect-Inforcer -ClientId <id> -ClientSecret <secret> [-Region] [-BaseUrl]` | `Connect-Inforcer -ApiKey <key> [-Region] [-BaseUrl]` |
| API | v1, `https://api-{region}.inforcer.com/v1` | beta, `https://api-{region}.inforcer.com/api/beta` |
| Credential | OAuth 2.0 client credentials: `POST https://api-{region}.inforcer.com/oauth/token` returns a 60-minute token, renewed automatically | API key |
| Header | `Authorization: Bearer <token>` | `Inf-Api-Key: <key>` |
| Not interchangeable | a token does not work on beta | a key does not work on v1 |

`Get-InforcerAuthHeader` is the only place the module builds either header. Secrets and tokens are held as SecureString and never written to output. The legacy API is due to be retired by inforcer (no date announced) and `Connect-Inforcer -ApiKey` warns about it. Regions: `anz`, `eu`, `uk`, `us`.

Permissions differ per login: key scopes for the API key ([API Scopes](#api-scopes)), API client permissions for client credentials ([API client permissions (v1)](#api-client-permissions-v1)).

### Redirects

Requests that carry the API key, the access token or the client secret never follow a redirect, on both logins: API calls, the token request, report-run polling, report downloads, assessment runs, the `Connect-Inforcer` key probe and the `-AssessmentId` tab completer of `Invoke-InforcerReport`. A `3xx` answer fails with a message that names the target, for example: "The API answered with a redirect (HTTP 302) to '…'. The module does not follow redirects, so credentials are never sent to another address. Check -BaseUrl or -Region." The best-effort report-catalog prime in `Connect-Inforcer` skips a redirect silently (verbose message only).

### Session caches

Cached per session and cleared by `Connect-Inforcer` and `Disconnect-Inforcer`:

| Cache | Filled by | Notes |
|-------|-----------|-------|
| Tenant list (`GET /tenants`) | `Get-InforcerTenantList` | Used to resolve tenant names (and GUIDs on beta). Plain `Get-InforcerTenant` always fetches the list fresh; `Get-InforcerTenant -TenantId` on beta reads the list again once per call. |
| Baseline list (`GET /baselines`) | `Get-InforcerBaselineList` | Used to resolve baseline names. `Get-InforcerBaseline` and `Get-InforcerAlignmentDetails` fetch fresh once per call and refresh the cache. |
| Report types (`GET /reports/types`) | `Connect-Inforcer` (best effort), `Get-InforcerReportType` | `Get-InforcerReportType -Force` refetches. |

---

## API Scopes

> Applies to API-key logins (beta API). For API clients see [API client permissions (v1)](#api-client-permissions-v1).

inforcer API keys are issued with one or more scopes. Each cmdlet and endpoint below lists its required scope(s). Request the narrowest scope that satisfies your use case; `Tenants.Read` is a broad scope that covers most tenant-related reads.

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

> **Note on `Audit.Read`**: The scope mapping provided by the inforcer API team lists `Audit.Read → /beta/assessments`, but `/beta/assessments` is already covered by `Assessments.Read`, and the module's audit cmdlets call `/beta/auditEvents/search` and `/beta/auditEvents/eventTypes`. This table assumes `Audit.Read` applies to the `/beta/auditEvents/*` routes. **This needs confirmation with the inforcer API team.**

### Cmdlet → Endpoints → Required Scopes

Built mechanically by tracing each public cmdlet through the module (including the `Resolve-InforcerTenantId` helper that hits `GET /beta/tenants` whenever `-TenantId` is passed as a GUID or tenant name). The minimum-scope column is the **narrowest** union; `Tenants.Read` alone is always sufficient for every route it covers, so you can collapse the narrow scopes into `Tenants.Read` if you prefer broader access.

| Cmdlet | Endpoints called | Minimum scopes |
|--------|------------------|----------------|
| `Connect-Inforcer` | `GET /beta/baselines` probe (a denied scope still connects, with a warning) and a best-effort `GET /beta/reports/types` to prime the report catalog | None |
| `Disconnect-Inforcer` | — | None |
| `Test-InforcerConnection` | `GET /beta/baselines` | `Baselines.Read` (or `Tenants.Read`); without it the test returns `False` |
| `Get-InforcerTenant` | `GET /beta/tenants` (fetched once per call, also for piped tenants) | `Tenants.Read` |
| `Get-InforcerBaseline` | `GET /beta/baselines` + `GET /beta/tenants` *(GUID/name lookup)* | `Baselines.Read` + `Tenants.Read`† |
| `Get-InforcerTenantPolicies` | `GET /beta/tenants/{tenantId}/policies` + `GET /beta/tenants` *(GUID/name lookup)* | `tenants.policies.Read` + `Tenants.Read`† |
| `Get-InforcerAlignmentDetails` | `GET /beta/baselines`, `GET /beta/alignmentScores`, `GET /beta/tenants`, `GET /beta/tenants/{tenantId}/alignmentDetails` | `Baselines.Read` + `AlignmentScores.Read` + `Tenants.Read` + `tenants.policies.Read` |
| `Get-InforcerAuditEvent` | `POST /beta/auditEvents/search` (one search; without `-EventType` no event-type filter is sent) | `Audit.Read` *(unmapped — see note above)* |
| `Get-InforcerSupportedEventType` | `GET /beta/auditEvents/eventTypes` | `Audit.Read` *(unmapped — see note above)* |
| `Get-InforcerUser` | `GET /beta/tenants/{tenantId}/users[/...] ` + `GET /beta/tenants` *(GUID/name lookup)*; `-IncludeAuthenticationMethods` has no beta equivalent (needs an API client) | `Tenants.Users.Read` + `Tenants.Read`† |
| `New-InforcerUser` | none: the beta API cannot create users (the cmdlet needs an API client) | not available with an API key |
| `Set-InforcerUser` | none: the beta API cannot update users, reset passwords or revoke sessions (the cmdlet needs an API client) | not available with an API key |
| `Get-InforcerGroup` | `GET /beta/tenants/{tenantId}/groups[/...] ` + `GET /beta/tenants` *(GUID/name lookup)* | `Tenants.Groups.Read` + `Tenants.Read`† |
| `Get-InforcerRole` | `GET /beta/tenants/{tenantId}/roles` + `GET /beta/tenants` *(GUID/name lookup)* | `Tenants.Roles.Read` + `Tenants.Read`† |
| `Get-InforcerSecureScore` | `GET /beta/tenants/{tenantId}/secureScores` + `GET /beta/tenants` *(GUID/name lookup)* | `Tenants.SecureScores.Read` + `Tenants.Read`† |
| `Get-InforcerAssessment` | `GET /beta/assessments` | `Assessments.Read` |
| `Invoke-InforcerAssessment` | `GET /beta/tenants`, `GET /beta/assessments`, `POST /beta/tenants/{tenantId}/assessments/{assessmentId}/runs` | `Tenants.Read` + `Assessments.Read` + `Assessments.Run` |
| `Export-InforcerTenantDocumentation` | `GET /beta/tenants`, `GET /beta/baselines`, `GET /beta/tenants/{tenantId}/policies`; with `-Baseline` also `GET /beta/tenants/{tenantId}/alignmentDetails` | `Tenants.Read` + `Baselines.Read` + `tenants.policies.Read` |
| `Compare-InforcerEnvironments` | `GET /beta/tenants`, `GET /beta/baselines`, `GET /beta/tenants/{tenantId}/policies` *(per side, both sides fetched at the same time)*; with `-SourceBaselineId`/`-DestinationBaselineId` also `GET /beta/tenants/{tenantId}/alignmentDetails` | `Tenants.Read` + `Baselines.Read` + `tenants.policies.Read` |
| `Get-InforcerReportType` | `GET /beta/reports/types` | `Reports.Read` |
| `Invoke-InforcerReport` | `POST /beta/reports/runs`, `GET /beta/reports/runs/{runId}/outputs`, `GET /beta/reports/runs/{runId}/outputs/{outputId}` + `GET /beta/tenants` *(GUID/name lookup)* | `Reports.Read` + `Reports.Run` + `Tenants.Read`† |
| `Get-InforcerReportRun` | `GET /beta/reports/runs`, `GET /beta/reports/runs/{runId}/outputs` *(with `-Wait` or `-IncludeOutputs`)* | `Reports.Read` |
| `Save-InforcerReportOutput` | `GET /beta/reports/runs/{runId}/outputs/{outputId}` | `Reports.Read` |

> The probes in `Connect-Inforcer` never fail the login on a denied scope; only a redirect (see [Redirects](#redirects)) or an invalid key does.
>
> † `Tenants.Read` is only consumed for the tenant-list lookup that `Resolve-InforcerTenantId` performs when `-TenantId` is a GUID or tenant name. If callers always pass a numeric Client Tenant ID, the `Tenants.Read` portion can be omitted.

---

## API client permissions (v1)

An API client (client credentials, v1 API) carries **permissions** instead of key scopes. They are granted per client in the inforcer portal (**Configure > REST API**, Permissions tab) and are resolved server side: the access token carries no scope or permission claims, so a client cannot read its own permissions. A client can also be restricted to specific tenants (Filters tab); a tenant outside the filter answers `404`.

The permission names below are the ones the portal shows (feature and grant). **The per-endpoint mapping is unconfirmed.** It is inferred from the permission names: the test client held all of these permissions at once, so no endpoint was checked against a single permission. Treat every row as *(unconfirmed)* until inforcer publishes the mapping, and grant the neighbouring permission if a call answers `403`.

### Permission → Routes

| Area / feature | Grant | v1 routes | Status |
|----------------|-------|-----------|--------|
| Tenants / Tenants | Read: View | `/v1/tenants`, `/v1/tenants/{msTenantId}` | unconfirmed |
| Tenants / Policies | Read: View | `/v1/tenants/{msTenantId}/policies` | unconfirmed |
| Tenants / User & Group Management | Read: View | `/v1/tenants/{msTenantId}/users`, `/v1/tenants/{msTenantId}/users/{userId}`, `/v1/tenants/{msTenantId}/users/{userId}/authenticationMethods`, `/v1/tenants/{msTenantId}/groups`, `/v1/tenants/{msTenantId}/groups/{groupId}`, `/v1/tenants/{msTenantId}/groups/{groupId}/members` | unconfirmed |
| Tenants / User & Group Management | Write (grant name unconfirmed) | `POST /v1/tenants/{msTenantId}/users`, `PATCH /v1/tenants/{msTenantId}/users/{userId}`, `POST /v1/tenants/{msTenantId}/users/{userId}/password`, `POST /v1/tenants/{msTenantId}/users/{userId}/revokeSessions`, `DELETE /v1/tenants/{msTenantId}/users/{userId}/authenticationMethods/{methodId}` | unconfirmed (which write grant) |
| Tenants / Entra Dashboard | Read: View | `/v1/tenants/{msTenantId}/secureScores`, `/v1/tenants/{msTenantId}/directoryRoles` | unconfirmed |
| Align / Baselines | Read: View | `/v1/baselines` | unconfirmed |
| Align / Align | Read: View | `/v1/alignmentScores`, `/v1/tenants/{msTenantId}/alignmentDetails` | unconfirmed |
| Assess / Tenant Assessment | Write: Run | `/v1/assessments`, `/v1/tenants/{msTenantId}/assessments/{assessmentId}/runs` | unconfirmed (whether listing needs the run grant) |
| Assess / Reports | Write: All (3 grants) | `/v1/reports/types`, `/v1/reports/runs`, `/v1/reports/runs/{reportRunId}/outputs`, `/v1/reports/runs/{reportRunId}/outputs/{outputId}` | unconfirmed (which of the 3 grants gates which route) |
| Configure / Activity | Read | `/v1/auditEvents/types`, `/v1/auditEvents/search` | unconfirmed |
| Copilot Manager / Copilot Manager | Write: Manage | none in the current spec; the module does not use it | n/a |
| TDR / Threats | Read: View | none in the current spec; the module does not use it | n/a |

### Cmdlet → Endpoints → Required permissions (v1)

`msTenantId` is the Microsoft tenant ID. A GUID passed to `-TenantId` is used as is; only a tenant **name** costs a `GET /v1/tenants` lookup (cached per session), so **Tenants** is needed for names (marked †).

| Cmdlet | Endpoints called (v1) | Permissions |
|--------|-----------------------|-------------|
| `Connect-Inforcer` | `POST /oauth/token` (no permission needed; any valid client connects) and a best-effort `GET /v1/reports/types` to prime the report catalog | None |
| `Disconnect-Inforcer` | none | None |
| `Test-InforcerConnection` | `GET /v1/baselines` | Baselines; without it the test returns `False` |
| `Get-InforcerTenant` | `GET /v1/tenants`. `-TenantId <GUID>` makes only `GET /v1/tenants/{msTenantId}`; a name adds the cached list | Tenants |
| `Get-InforcerBaseline` | `GET /v1/baselines` (+ `GET /v1/tenants` for a tenant name) | Baselines, Tenants† |
| `Get-InforcerTenantPolicies` | `GET /v1/tenants/{msTenantId}/policies` | Policies, Tenants† |
| `Get-InforcerAlignmentDetails` | `GET /v1/baselines`, `GET /v1/alignmentScores`, `GET /v1/tenants`, `GET /v1/tenants/{msTenantId}/alignmentDetails` | Baselines + Align + Tenants |
| `Get-InforcerAuditEvent` | `POST /v1/auditEvents/search` | Activity |
| `Get-InforcerSupportedEventType` | `GET /v1/auditEvents/types` | Activity |
| `Get-InforcerUser` | `GET /v1/tenants/{msTenantId}/users[/{userId}]`, `.../users/{userId}/authenticationMethods` (with `-IncludeAuthenticationMethods`) | User & Group Management, Tenants† |
| `New-InforcerUser` | `POST /v1/tenants/{msTenantId}/users` | User & Group Management (write), Tenants† |
| `Set-InforcerUser` | `PATCH /v1/tenants/{msTenantId}/users/{userId}`, `POST .../users/{userId}/password` (with `-Password`), `DELETE .../users/{userId}/authenticationMethods/{methodId}` (with `-RemoveAuthenticationMethod`), `POST .../users/{userId}/revokeSessions` (with `-RevokeSessions`) | User & Group Management (write), Tenants† |
| `Get-InforcerGroup` | `GET /v1/tenants/{msTenantId}/groups[/{groupId}]`, `.../groups/{groupId}/members` (with `-Group`) | User & Group Management, Tenants† |
| `Get-InforcerRole` | `GET /v1/tenants/{msTenantId}/directoryRoles` | Entra Dashboard, Tenants† |
| `Get-InforcerSecureScore` | `GET /v1/tenants/{msTenantId}/secureScores` | Entra Dashboard, Tenants† |
| `Get-InforcerAssessment` | `GET /v1/assessments` | Tenant Assessment |
| `Invoke-InforcerAssessment` | `GET /v1/tenants`, `GET /v1/assessments`, `POST /v1/tenants/{msTenantId}/assessments/{assessmentId}/runs` | Tenants + Tenant Assessment |
| `Export-InforcerTenantDocumentation` | `GET /v1/tenants/{msTenantId}` (+ `GET /v1/tenants` for a tenant name), `GET /v1/baselines`, `GET /v1/tenants/{msTenantId}/policies` (+ `alignmentDetails` with `-Baseline`) | Tenants + Baselines + Policies (+ Align) |
| `Compare-InforcerEnvironments` | same as Export, per side; both sides are fetched at the same time | Tenants + Baselines + Policies (+ Align) |
| `Get-InforcerReportType` | `GET /v1/reports/types` | Reports |
| `Invoke-InforcerReport` | `POST /v1/reports/runs`, `GET /v1/reports/runs/{reportRunId}/outputs[/{outputId}]`, `GET /v1/tenants`† | Reports, Tenants† |
| `Get-InforcerReportRun` | `GET /v1/reports/runs`, `GET /v1/reports/runs/{reportRunId}/outputs` | Reports |
| `Save-InforcerReportOutput` | `GET /v1/reports/runs/{reportRunId}/outputs/{outputId}` | Reports |

All rows are *(unconfirmed)* per the note above. For the legacy key scopes of the same cmdlets see [Cmdlet → Endpoints → Required Scopes](#cmdlet--endpoints--required-scopes) (API key).

---

## v1 API (client credentials)

The v1 API is inforcer's current public API (`inforcer | Public API`, OpenAPI 1.0.0). The module chooses it when you log in with `Connect-Inforcer -ClientId ... -ClientSecret ...` and maps every v1 response to the property names the beta API used (see `module/Private/ConvertFrom-InforcerV1Response.ps1`), so cmdlet output stays the same across both logins. The spec is public at `https://api-{region}.inforcer.com/v1/openapi.json`; a copy is tracked in [`openapi-snapshot-v1.json`](./openapi-snapshot-v1.json) and refreshed by the Powershell-Module-Automation workflows.

### Differences at a glance

| | v1 | beta (legacy) |
|---|----|---------------|
| Auth | `Authorization: Bearer <token>` | `Inf-Api-Key: <key>` |
| Base | `https://api-{region}.inforcer.com/v1` | `https://api-{region}.inforcer.com/api/beta` |
| Tenant identifier | `msTenantId` (Microsoft tenant GUID) | `clientTenantId` (inforcer numeric ID) |
| Success body | one named collection (`{ "tenants": [ ... ] }`); single objects bare | `{ "data": ..., "success": true }` |
| Error body | `application/problem+json` | `{ "success": false, "message", "errors" }` |
| Rate limit | 400 calls/minute per partner, `429` + `Retry-After` | 400 calls/hour per API key |
| Permissions | API client permissions + tenant filters | key scopes |
| Status | current | due to be retired (no date); bug fixes only |

### Token

```
POST https://api-{region}.inforcer.com/oauth/token
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials&client_id=<client id>&client_secret=<client secret>
```

Response: `{ "access_token": "...", "token_type": "Bearer", "expires_in": 3600 }`. The token lasts 60 minutes, has no refresh token and is bound to the region (`aud`). The module requests a new token when less than five minutes remain, and once after a `401`. The OpenAPI document needs no token.

### Response envelope

Every v1 response is an object holding **one named collection** and sometimes metadata: `tenants`, `policies`, `users`, `groups`, `members`, `roles`, `baselines`, `alignmentScores`, `assessments`, `reportRuns`, `outputs`, `reportTypes`, `auditEvents`, `eventTypes`. There is no `data` or `status` wrapper. Metadata keys the module knows: `continuationToken`, `userCount`, `groupCount`, `memberCount`, `failedPolicyTypes`. Single-object endpoints (tenant, user, group, secure scores, alignment details, assessment run) return the object itself. The module unwraps the collection, so cmdlets return the items directly.

`-OutputType JsonObject` shape:

- **v1:** a list result is always a JSON array, also with one item (including `Get-InforcerTenant`, `Get-InforcerRole` and the alignment table).
- **API key (beta):** a list of exactly one item can come back as a bare JSON object (for example `Get-InforcerTenant`, `Get-InforcerBaseline`, `Get-InforcerRole`, `Get-InforcerUser`, `Get-InforcerGroup`, `Get-InforcerAuditEvent` and the alignment table), as in 0.8.0.
- **Piped tenants** (`Get-InforcerTenant | Get-InforcerTenantPolicies -OutputType JsonObject`): one JSON array for the whole call, each item carrying `TenantId`, on both logins.
- Single-object results (`Get-InforcerSecureScore`, `Get-InforcerUser -UserId`, `Get-InforcerGroup -Group`) are one JSON object.

> The spec marks many fields *Required* that the documentation calls nullable (and a few are typed `unknown`: `alignedBaselineMsTenantId`, `baselineTenant`, an output's `msTenantId`). Do not read Required as non-null.

### Errors

Errors are `application/problem+json`: `type`, `title`, `status`, `detail`, `instance`; `400` adds `errors{}` with field messages.

| Status | Meaning | Module behaviour |
|--------|---------|------------------|
| 400 | Invalid request (`errors{}` lists the fields) | Error with title, detail and field messages |
| 401 | Token missing or expired | Token renewed once, request retried |
| 403 | Missing permission or tenant | Error showing the API's title and detail |
| 404 | Does not exist **or** outside the client's tenant filter | Error showing the API's title and detail (e.g. `Tenant not found`) |
| 409 | Conflict | Error with the API's detail |
| 429 | Rate limit | Waits for `Retry-After` (seconds or HTTP date, capped at 300 s), up to 3 retries. v1 only: with an API key (beta) the first `429` fails the call, as in 0.8.0. Report-file downloads are not retried on `429`. |
| 500 / 502 | Server error (assessment runs can return both) | Error with the API's detail |

API calls use ErrorId `ApiRequestFailed_<status>` on both APIs; report-file downloads use `DownloadFailed_<status>`.

### Pagination

Lists that page return `continuationToken`; pass it back until it is empty. Page sizes: users 200, groups 20, group members 100. `GET` endpoints take `continuationToken` in the query (users, groups, members); `POST /v1/auditEvents/search` takes it in the JSON body together with `pageSize`. `search` filters users and groups by text. `userCount`, `groupCount` and `memberCount` (nullable) give totals. The module follows tokens in `Invoke-InforcerPagedRequest` for both APIs and stops on an empty or repeated token.

### Rate limits

v1: **400 calls per minute per partner**, shared by every client of the partner. Beta: **400 calls per hour per API key**. A throttled v1 call answers `429` with `Retry-After`; the module waits (at most 300 s) and retries up to three times, also for assessment runs. Report-file downloads are not retried on `429`. An API-key (beta) call is not retried: it fails on the first `429`, as in 0.8.0. Anything that fans out per tenant (Export, Compare, piped tenants) costs one call per tenant.

### `failedPolicyTypes`

`GET /v1/tenants/{msTenantId}/policies` returns `{ "policies": [ ... ], "failedPolicyTypes": { ... } }`. A non-empty `failedPolicyTypes` means the result is partial (policy types that could not be read, with a reason); `Get-InforcerTenantPolicies` writes a warning for it.

The v1 result holds the same policies as beta, Intune and Defender settings-catalog (`policyTypeId` 10) included (inforcer fixed the earlier gap on 2026-11-05, ENG-6967). A type inforcer could not read is listed in `failedPolicyTypes` with its reason, for example `"Cloud PC User Settings": "Insufficient permissions in the tenant"` (also when the tenant has no Windows 365 licence); beta leaves such types out without saying so. Also on v1: policy `id` is the Microsoft policy ID (beta: the inforcer ID), so the module keys on `policyData.id` where it can, and `GET /v1/baselines` `items` are policy categories (beta: item references).

### v1 endpoints

Every path in the v1 spec, its beta equivalent and the module cmdlet. The module writes version-neutral endpoints (`/tenants/{id}/policies`); `Get-InforcerBaseUrl` adds `/beta` or `/v1` and applies the renames `roles` → `directoryRoles`, `auditEvents/eventTypes` → `auditEvents/types` and query `customBaselineId` → `baselineId`.

| v1 path | Method | Beta equivalent | Cmdlet |
|---------|--------|-----------------|--------|
| `/v1/tenants` | GET | `/beta/tenants` | `Get-InforcerTenant` |
| `/v1/tenants/{msTenantId}` | GET | `/beta/tenants/{tenantId}` | `Get-InforcerTenant -TenantId` (the sanctioned use of this endpoint); also reached through it by Export and Compare |
| `/v1/tenants/{msTenantId}/policies` | GET | `/beta/tenants/{tenantId}/policies` | `Get-InforcerTenantPolicies`, Export, Compare |
| `/v1/tenants/{msTenantId}/alignmentDetails` | GET (`baselineId` required) | `/beta/tenants/{tenantId}/alignmentDetails` (`customBaselineId`) | `Get-InforcerAlignmentDetails`; Export/Compare baseline scoping |
| `/v1/tenants/{msTenantId}/secureScores` | GET | `/beta/tenants/{tenantId}/secureScores` | `Get-InforcerSecureScore` |
| `/v1/tenants/{msTenantId}/users` | GET (`search`, `continuationToken`) | `/beta/tenants/{tenantId}/users` | `Get-InforcerUser` |
| `/v1/tenants/{msTenantId}/users` | POST (201 `{ id }`) | none (v1 only) | `New-InforcerUser` |
| `/v1/tenants/{msTenantId}/users/{userId}` | GET | `/beta/tenants/{tenantId}/users/{userId}` | `Get-InforcerUser -UserId` |
| `/v1/tenants/{msTenantId}/users/{userId}` | PATCH (JSON Merge Patch, 204) | none (v1 only) | `Set-InforcerUser` |
| `/v1/tenants/{msTenantId}/users/{userId}/authenticationMethods` | GET | none (v1 only) | `Get-InforcerUser -UserId -IncludeAuthenticationMethods` |
| `/v1/tenants/{msTenantId}/users/{userId}/authenticationMethods/{methodId}` | DELETE (204) | none (v1 only) | `Set-InforcerUser -RemoveAuthenticationMethod` |
| `/v1/tenants/{msTenantId}/users/{userId}/password` | POST (204) | none (v1 only) | `Set-InforcerUser -Password` |
| `/v1/tenants/{msTenantId}/users/{userId}/revokeSessions` | POST (204) | none (v1 only) | `Set-InforcerUser -RevokeSessions` |
| `/v1/tenants/{msTenantId}/groups` | GET (`search`, `continuationToken`) | `/beta/tenants/{tenantId}/groups` | `Get-InforcerGroup` |
| `/v1/tenants/{msTenantId}/groups/{groupId}` | GET | `/beta/tenants/{tenantId}/groups/{groupId}` | `Get-InforcerGroup -Group` |
| `/v1/tenants/{msTenantId}/groups/{groupId}/members` | GET (`continuationToken`) | none (v1 only) | `Get-InforcerGroup -Group` (attached as members) |
| `/v1/tenants/{msTenantId}/directoryRoles` | GET | `/beta/tenants/{tenantId}/roles` | `Get-InforcerRole` |
| `/v1/tenants/{msTenantId}/assessments/{assessmentId}/runs` | POST (synchronous) | `/beta/tenants/{tenantId}/assessments/{assessmentId}/runs` | `Invoke-InforcerAssessment` |
| `/v1/baselines` | GET (`baselineMsTenantId`) | `/beta/baselines` (`baselineTenantId`) | `Get-InforcerBaseline` |
| `/v1/alignmentScores` | GET | `/beta/alignmentScores` | `Get-InforcerAlignmentDetails` (table) |
| `/v1/assessments` | GET | `/beta/assessments` | `Get-InforcerAssessment` |
| `/v1/reports/runs` | GET, POST (202 `reportRunId`) | `/beta/reports/runs` | `Get-InforcerReportRun`, `Invoke-InforcerReport` |
| `/v1/reports/runs/{reportRunId}/outputs` | GET | `/beta/reports/runs/{reportRunId}/outputs` | `Get-InforcerReportRun`, `Invoke-InforcerReport` |
| `/v1/reports/runs/{reportRunId}/outputs/{outputId}` | GET (raw json/csv/html/pdf) | `/beta/reports/runs/{reportRunId}/outputs/{outputId}` | `Save-InforcerReportOutput`, `Invoke-InforcerReport` |
| `/v1/reports/types` | GET | `/beta/reports/types` | `Get-InforcerReportType` |
| `/v1/auditEvents/types` | GET (`{ "eventTypes": [ { "name" } ] }`) | `/beta/auditEvents/eventTypes` | `Get-InforcerSupportedEventType` |
| `/v1/auditEvents/search` | POST (`user`, `eventTypes`, `dateFrom`, `dateTo` in whole seconds, `pageSize`, `continuationToken`) | `/beta/auditEvents/search` | `Get-InforcerAuditEvent` |

That is 25 paths and 28 operations (`/v1/reports/runs` has GET and POST, `/v1/tenants/{msTenantId}/users` GET and POST, `/v1/tenants/{msTenantId}/users/{userId}` GET and PATCH). Path parameters are `msTenantId` (Microsoft tenant GUID), `userId` (Entra object ID), `methodId` (an authentication method's `id`; not always a GUID), `groupId`, `assessmentId`, `reportRunId` and `outputId`. Report runs are triggered with `{ "reports": [ { "type", "outputFormat", "collate", "parameters" } ], "msTenantIds": [ ... ] }` (beta: `tenants.includeTenants` with numeric IDs).

### Managing users (v1 only)

The beta API has no equivalent, so `New-InforcerUser`, `Set-InforcerUser` and `Get-InforcerUser -IncludeAuthenticationMethods` need an API client; an API-key login stops with `RequiresApiClient`.

#### `POST /v1/tenants/{msTenantId}/users`

Creates a Microsoft Entra user in the tenant.

**Required API scope(s)**: not available with an API key (beta).
**Required API client permission(s)**: User & Group Management (write) *(unconfirmed)*

Body: the [UserUpdate](#userupdate) profile fields, of which `accountEnabled`, `displayName`, `mailNickname` and `userPrincipalName` are required, plus `passwordProfile` `{ password, forceChangePasswordNextSignIn }` (both required; the password must meet the tenant's password policy).

**Response**: `201` with [CreatedUser](#createduser) and a `Location` header. Errors: `400` (invalid field, with `errors{}`), `404` (tenant), `409` (for example the user principal name is taken).

#### `PATCH /v1/tenants/{msTenantId}/users/{userId}`

Updates a user's profile, manager and whether they can sign in. JSON Merge Patch (RFC 7396): a property left out is kept, `null` clears it.

**Required API scope(s)**: not available with an API key (beta).
**Required API client permission(s)**: User & Group Management (write) *(unconfirmed)*

Body: [UserUpdate](#userupdate), at least one property. Sent as `application/json` (the API also takes `application/merge-patch+json`).

**Response**: `204` without a body; a `GET` (by id or in the list) can show the old values for up to about five minutes; the two are cached separately. When the manager could not be changed but the other changes were saved, the API answers `502` with problem+json and `results[]`: one `{ step, status, title?, statusCode? }` per step (`profile`, `manager`). The module adds them to the error text as `Steps: profile: succeeded; manager: failed (reason)`.

#### `POST /v1/tenants/{msTenantId}/users/{userId}/password`

Sets a new password for the user, and can require them to change it when they next sign in. inforcer does not store or log the password.

**Required API scope(s)**: not available with an API key (beta).
**Required API client permission(s)**: User & Group Management (write) *(unconfirmed)*

Body: [PasswordReset](#passwordreset), both fields required.

**Response**: `204` without a body. Errors: `400` (missing field, or the password does not meet the tenant's password policy, in `errors.password`), `404` (tenant or user).

#### `POST /v1/tenants/{msTenantId}/users/{userId}/revokeSessions`

Signs the user out of every session by revoking their refresh tokens and session cookies. Access tokens already issued stay valid until they expire, typically within 90 minutes. No body.

**Required API scope(s)**: not available with an API key (beta).
**Required API client permission(s)**: User & Group Management (write) *(unconfirmed)*

**Response**: `204` without a body. Errors: `404` (tenant or user, `User not found`).

`Set-InforcerUser` runs the steps of one call in this order: `PATCH` (when a profile field is passed), password, delete authentication methods (one call per id), revoke sessions. When a step fails the later ones are skipped, and the error (`UserUpdatePartlyApplied`) names the steps already done and the steps not done.

#### `GET /v1/tenants/{msTenantId}/users/{userId}/authenticationMethods`

Lists the sign-in methods the user has registered, such as their password, phones, Microsoft Authenticator and passkeys. Secrets such as passwords and Temporary Access Pass codes are never returned.

**Required API scope(s)**: not available with an API key (beta).
**Required API client permission(s)**: User & Group Management *(unconfirmed)*

**Response**: `200` with `{ "authenticationMethods": [ ... ] }`, all methods in one response in no fixed order (see [UserAuthenticationMethod](#userauthenticationmethod)). `Get-InforcerUser -UserId -IncludeAuthenticationMethods` adds the array to the user as `authenticationMethods`. Like the other `GET` calls, the answer can be up to about five minutes old.

#### `DELETE /v1/tenants/{msTenantId}/users/{userId}/authenticationMethods/{methodId}`

Deletes one of the user's sign-in methods, such as a phone, Microsoft Authenticator or a passkey, so it can no longer be used to sign in. `methodId` is the method's `id` from the list above; usually a GUID, but not for every type (a passkey's id is not).

**Required API scope(s)**: not available with an API key (beta).
**Required API client permission(s)**: User & Group Management (write) *(unconfirmed)*

**Response**: `204` without a body. Errors: `400` when the method is not `deletable` (reason in `errors.methodId`) or Microsoft Entra refuses it, for example the default method while another phone remains (reason in `detail`); `404` (tenant, user or method). Microsoft Entra's reads lag its changes, so the list can still show a deleted method for a short time. `Set-InforcerUser -RemoveAuthenticationMethod` sends one call per id.

### How v1 fields map to the module's names

| Object | v1 field → module property | No v1 equivalent / v1 only |
|--------|----------------------------|----------------------------|
| Tenant | `name` → `tenantFriendlyName`, `dnsName` → `tenantDnsName`; alignment summary `lastAlignmentTimestamp` → `lastAlignmentDateTime` | no `clientTenantId`; `authenticationMode` is v1 only and only on the single-tenant record (`-TenantId`) |
| Policy | `policyTypeName` → `inforcerPolicyTypeName` | `id` is the Microsoft policy ID; no `policyCategoryId` |
| Baseline | `baselineTenant{}` flattened to `baselineMsTenantId`, `baselineTenantFriendlyName`, `baselineTenantDnsName`; members `name`/`dnsName` → `tenantFriendlyName`/`tenantDnsName`; items `product`, `primaryGroup`, `secondaryGroup` → `policyCategory*` | no `baselineClientTenantId`; `description`, `isSharedCopy`, member `lastAlignmentScore` are v1 only |
| Alignment score | `tenantName` → `tenantFriendlyName`, `alignedBaselineId` → `baselineGroupId`, `alignedBaselineName` → `baselineGroupName`, `alignmentScore` → `score`, `lastAlignmentTimestamp` → `lastComparisonDateTime` | `msTenantId` replaces the numeric `tenantId` |
| Alignment details | buckets `matched`, `matchedWithAcceptedDeviations`, `deviated`, `missingFromTenant`, `additionalInTenant` → `matchedPolicies`, `matchedWithAcceptedDeviations`, `deviatedUnaccepted`, `missingFromSubjectUnaccepted`, `additionalInSubjectUnaccepted`; `tenantDataTimestamp` → `subjectDataTimestamp`; per-policy `displayName` → `policyName`, `tenantPolicies` → `matchingSubjectPolicies`; more renames in [Alignment details renames](#alignment-details-renames) | compared policies are richer (diffs, similar policies) |
| User | list `groupCount`/`roleCount` → `groups`/`roles` | list has counts, not arrays |
| Group, role, secure score, assessment, report type, audit event type | unchanged | audit events lack `clientId` and `message`; v1 lists the event types a partner can use (191 on 2026-11-05); beta's list is older (147) and also holds internal types and types still in development |
| Assessment run | `assessmentId` → `assessment` | |
| Report run / output | `reportRunId` → `runId`; output `msTenantId` → `tenantId` (`null` = collated) | |

#### Alignment details renames

Inside a v1 `alignmentDetails` response the module also renames these fields (`ConvertFrom-InforcerV1Response`):

| Where | v1 field → module property |
|-------|----------------------------|
| `metrics` | `matched` → `matchedPolicies`, `deviated` → `deviatedPolicies`, `missingFromTenant` → `recommendedPoliciesFromBaseline`, `additionalInTenant` → `customerOnlyPolicies` |
| Compared policy | `displayName` → `policyName`, `policyTypeName` → `inforcerPolicyTypeName`, `tags` → `policyTags`, `tenantPolicies` → `matchingSubjectPolicies`, `variables` → `matchingVariables` |
| Matching tenant policy (`matchingSubjectPolicies[]`) | `tags` → `policyTags` |
| Variable (`matchingVariables[]`) | `name` → `variableName`, `tenantValue` → `subjectValue` |
| Diff (`policyDataDiff`, `policyAssignmentsDiff`) | `tenantValue` → `subjectValue` |
| Accepted deviation | `acceptedTimestamp` → `acceptedDateTime`, `reason` → `acceptedReason` |
| Similar policy | `name` → `policyName`, `categoryName` → `policyCategoryName` |

---

## Beta endpoints

> Endpoints below are the legacy beta API (API-key login). The same cmdlets call the v1 equivalents listed in [v1 endpoints](#v1-endpoints) on a client-credentials login.

### Baselines

#### GET /beta/baselines

Retrieves baseline groups and their members.

**Cmdlet**: `Get-InforcerBaseline`

**Required API scope(s)**: `Baselines.Read` (or `Tenants.Read`)

| Parameter | Location | Required | Type | Description |
|-----------|----------|----------|------|-------------|
| baselineTenantId | query | No | integer | Filter baseline groups by baseline tenant ID. If not provided, all baseline groups are returned. |

**Response**: Array of [BaselineGroup](#baselinegroup)

---

### Alignment Scores

#### GET /beta/alignmentScores

Retrieves alignment scores for tenants.

**Cmdlet**: `Get-InforcerAlignmentDetails`

**Required API scope(s)**: `AlignmentScores.Read` (or `Tenants.Read`)

**Response**: Array of [AlignmentScore](#alignmentscore)

---

### Alignment Details

#### GET /beta/tenants/{tenantId}/alignmentDetails

Compares one tenant against one baseline and returns the per-policy result.

**Cmdlet**: `Get-InforcerAlignmentDetails -BaselineId`; also `Export-InforcerTenantDocumentation -Baseline` and `Compare-InforcerEnvironments -SourceBaselineId`/`-DestinationBaselineId` (to list the baseline's policies)

**Required API scope(s)**: `tenants.policies.Read`

| Parameter | Location | Required | Type | Description |
|-----------|----------|----------|------|-------------|
| tenantId | path | Yes | integer | Client Tenant ID of the subject tenant. |
| customBaselineId | query | Yes | string (guid) | The baseline to compare against (v1: `baselineId`). |

**Response**: `{ data: { metrics, completedAt, alignment } }`. `alignment` holds the arrays `matchedPolicies`, `matchedWithAcceptedDeviations`, `deviatedUnaccepted`, `missingFromSubjectUnaccepted` and `additionalInSubjectUnaccepted`. v1 uses other names, mapped by the module (see [Alignment details renames](#alignment-details-renames)).

---

### Tenants

#### GET /beta/tenants

Retrieves all tenants.

**Cmdlet**: `Get-InforcerTenant`

**Required API scope(s)**: `Tenants.Read`

**Response**: Array of [Tenant](#tenant)

---

#### GET /beta/tenants/{tenantId}

Retrieves a specific tenant by ID.

**Cmdlet**: `Get-InforcerTenant -TenantId`

**Required API scope(s)**: `Tenants.Read`

| Parameter | Location | Required | Type | Description |
|-----------|----------|----------|------|-------------|
| tenantId | path | Yes | integer | The unique identifier for the tenant (Client Tenant ID). |

**Response**: [Tenant](#tenant)

> **Implementation Note**: On beta the module uses `GET /beta/tenants` with client-side filtering for consistency and deduplication. On v1 the list holds the same fields; `-TenantId` calls `GET /v1/tenants/{msTenantId}`, which adds `authenticationMode`.

---

### Tenant Policies

#### GET /beta/tenants/{tenantId}/policies

Retrieves policies for a specific tenant.

**Cmdlet**: `Get-InforcerTenantPolicies`

**Required API scope(s)**: `tenants.policies.Read`

| Parameter | Location | Required | Type | Description |
|-----------|----------|----------|------|-------------|
| tenantId | path | Yes | integer | The unique identifier for the tenant. |

**Response**: Array of [Policy](#policy)

---

### Audit Events

#### GET /beta/auditEvents/eventTypes

Retrieves available event types for filtering audit events.

**Cmdlet**: `Get-InforcerSupportedEventType` (also feeds `-EventType` tab completion of `Get-InforcerAuditEvent`)

**Required API scope(s)**: `Audit.Read` *(needs confirmation — see [API Scopes](#api-scopes))*

**Response**: Array of [EventType](#eventtype)

---

#### POST /beta/auditEvents/search

Searches the activity log with optional filters.

**Cmdlet**: `Get-InforcerAuditEvent`

**Required API scope(s)**: `Audit.Read` *(needs confirmation — see [API Scopes](#api-scopes))*

**Request Body**:

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| eventTypes | string[] | No | Event types to filter by (e.g., `authentication`, `failedAuthentication`). |
| dateFrom | string (date-time) | No | Start of date/time range (inclusive). ISO 8601 format. |
| dateTo | string (date-time) | No | End of date/time range (inclusive). ISO 8601 format. |
| pageSize | integer | No | Number of results per page. Default: 100. |
| continuationToken | string | No | Token for pagination (returned in previous response). |
| user | string | No | Filter by user (UPN). Sent for `Get-InforcerAuditEvent -User`. |

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

`Get-InforcerAuditEvent` sends one search per call. Without `-EventType` it omits `eventTypes` and the API searches every type; events come back in the API's order.

---

### Users

#### `GET /beta/tenants/{tenantId}/users`

Returns a paginated list of user summaries for a tenant.

**Required API scope(s)**: `Tenants.Users.Read` (or `Tenants.Read`)

| Parameter | In | Type | Required | Description |
|-----------|----|------|----------|-------------|
| `tenantId` | path | integer | Yes | inforcer tenant ID. |
| `search` | query | string | No | Server-side search filter. |
| `continuationToken` | query | string | No | Token to continue a previous page. |

**Response**: Paginated array of [UserSummary](#usersummary) with `continuationToken` and `totalCount` at the response root level (siblings of `data`).

#### `GET /beta/tenants/{tenantId}/users/{userId}`

Returns full detail for a single user.

**Required API scope(s)**: `Tenants.Users.Read` (or `Tenants.Read`)

| Parameter | In | Type | Required | Description |
|-----------|----|------|----------|-------------|
| `tenantId` | path | integer | Yes | inforcer tenant ID. |
| `userId` | path | string (GUID) | Yes | The user ID. |

**Response**: Single [User](#user) object.

### Groups

#### `GET /beta/tenants/{tenantId}/groups`

Returns a paginated list of Entra ID group summaries for a tenant.

**Required API scope(s)**: `Tenants.Groups.Read` (or `Tenants.Read`)

| Parameter | In | Type | Required | Description |
|-----------|----|------|----------|-------------|
| `tenantId` | path | integer | Yes | inforcer tenant ID. |
| `search` | query | string | No | Server-side search filter. |
| `continuationToken` | query | string | No | Token to continue a previous page. |

**Response**: Paginated array of [TenantGroupSummary](#tenantgroupsummary) with `continuationToken` and `totalCount` at the response root level (siblings of `data`).

#### `GET /beta/tenants/{tenantId}/groups/{groupId}`

Returns full detail for a single group including members.

**Required API scope(s)**: `Tenants.Groups.Read` (or `Tenants.Read`)

| Parameter | In | Type | Required | Description |
|-----------|----|------|----------|-------------|
| `tenantId` | path | integer | Yes | inforcer tenant ID. |
| `groupId` | path | string (GUID) | Yes | The group ID. |

**Response**: Single [TenantGroup](#tenantgroup) object.

### Roles

#### `GET /beta/tenants/{tenantId}/roles`

Returns the list of Entra ID directory role definitions for a tenant.

**Required API scope(s)**: `Tenants.Roles.Read` (or `Tenants.Read`)

| Parameter | In | Type | Required | Description |
|-----------|----|------|----------|-------------|
| `tenantId` | path | integer | Yes | inforcer tenant ID. |

**Response**: Array of [TenantRole](#tenantrole) objects.

### Secure Scores

#### `GET /beta/tenants/{tenantId}/secureScores`

Returns the current and historic Microsoft Secure Score for a tenant. Includes up to 90 days of daily score history, per-category scores, and actionable control profiles.

**Required API scope(s)**: `Tenants.SecureScores.Read` (or `Tenants.Read`)

| Parameter | In | Type | Required | Description |
|-----------|----|------|----------|-------------|
| `tenantId` | path | integer | Yes | inforcer tenant ID. |

**Response**: A single [TenantSecureScoreDetails](#tenantsecurescoredetails) object.

### Assessments

#### `GET /beta/assessments`

Lists the assessments that can be run (CIS, Essential Eight, custom, ...).

**Cmdlet**: `Get-InforcerAssessment`; `Invoke-InforcerAssessment` uses it to resolve an assessment name

**Required API scope(s)**: `Assessments.Read`

**Response**: Array of [Assessment](#assessment) objects.

#### `POST /beta/tenants/{tenantId}/assessments/{assessmentId}/runs`

Runs an assessment against one tenant and returns the results in the same response (no polling).

**Cmdlet**: `Invoke-InforcerAssessment`

**Required API scope(s)**: `Assessments.Run`

| Parameter | In | Type | Required | Description |
|-----------|----|------|----------|-------------|
| `tenantId` | path | integer | Yes | Client Tenant ID. |
| `assessmentId` | path | string | Yes | Assessment ID from `GET /beta/assessments` (an alphanumeric string, not a GUID). |

**Response**: `{ data: { assessment, name, results: [AssessmentCheck, ...] } }`. v1 (`POST /v1/tenants/{msTenantId}/assessments/{assessmentId}/runs`) answers `{ assessmentId, name, summary, results }`; `summary` is `{ total, assessed, passed, failed, notRun, score }`, where `score` is passed checks as a percentage of assessed checks, rounded down (`null` when nothing was assessed). `Invoke-InforcerAssessment` shows that score; beta has no summary, so the module computes `Pass ÷ (Pass + Fail)`. Runs can answer `500` or `502`. The module runs the request in a background runspace; on v1 it renews the token once after a `401` and honours `Retry-After` on a `429` (up to 3 times), and on both logins it refuses a redirect (see [Redirects](#redirects)).

### Reports

Beta endpoints for triggering and retrieving asynchronous report runs.

#### `GET /beta/reports/types`

Returns the catalog of available report types. Each entry advertises the report's key, supported output formats, whether it can be collated across tenants, accepted parameters, and tags.

**Required API scope(s)**: `Reports.Read`

**Cmdlet**: `Get-InforcerReportType`

**Response**: Array of [ReportType](#reporttype) objects (under `data`).

#### `POST /beta/reports/runs`

Queues one run, which can batch several report types and tenants, and returns its `runId`. With `collate: true` on a `collatable: true` type the run produces a single cross-tenant output instead of one output per tenant.

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

**Response**: `{ data: { runId } }` (v1: `{ reportRunId }`, HTTP 202).

> **Known server-side bug**: Duplicate `(type, outputFormat)` entries currently render all duplicates in the last-listed format. The module deduplicates client-side before POST.

#### `GET /beta/reports/runs`

Lists report runs across all tenants the caller has visibility into. Server-side cap: `maxItems: 500`, last 7 days. Query parameters (`?status=`, `?since=`, `?limit=`, ...) are currently ignored — filter client-side.

**Required API scope(s)**: `Reports.Read`

**Cmdlet**: `Get-InforcerReportRun`

> **Propagation lag**: a newly-queued run does not appear in this list for ~4 minutes. For freshly-queued runs, poll `GET /beta/reports/runs/{runId}/outputs` directly (404 until terminal, 200 once complete).

**Response**: `{ data: { runs: [ReportRun, ...] } }`.

#### `GET /beta/reports/runs/{runId}/outputs`

Returns the list of outputs for a single terminal run. Used as the polling probe for run completion (bypasses the list-endpoint propagation lag).

**Required API scope(s)**: `Reports.Read`

**Cmdlet**: `Test-InforcerReportRunTerminal` *(private helper, used by `Invoke-InforcerReport` (default; not with `-NoWait`), `Get-InforcerReportRun -Wait`, and `Get-InforcerReportRun -IncludeOutputs`)*

| Parameter | In | Type | Required | Description |
|-----------|----|------|----------|-------------|
| `runId` | path | string (GUID) | Yes | The run identifier returned by `POST /reports/runs`. |

**Responses:**

| Code | Body | Meaning |
|------|------|---------|
| 200 | `{ data: { outputs: [ReportOutput, ...] } }` | Run is in a terminal state (`completed` or `completedWithErrors`) and outputs are available. |
| 200 | `{ data: { outputs: [] } }` | Run is visible to the API key, but **no outputs are within the key's tenant scope.** Collated outputs (covering multiple tenants) are only returned when the key covers every tenant the run targeted. |
| 404 | — | **Deliberately indistinguishable across four cases**: (1) run does not exist, (2) run belongs to a different client, (3) run is not in a terminal state (still `running`, or `failed`), (4) output ID does not belong to this run. Designed this way to avoid leaking run existence across clients. |

> **Polling implication**: `Invoke-InforcerReport` (default; not with `-NoWait`) and `Get-InforcerReportRun -Wait` cannot distinguish a still-running run from a `failed` run — both 404 indefinitely. The cmdlet times out cleanly after `-TimeoutSeconds`. To detect `failed` status, query `GET /beta/reports/runs` (subject to the 4-minute lag).

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

**How the module saves the file** (`Save-InforcerReportOutput`, and the save step of `Invoke-InforcerReport`):

- The `Content-Disposition` name is reduced to a safe file name (no folders, no unsafe characters); a name that starts with a dot gets a leading `_` (`.csv` → `_.csv`).
- An existing file is never overwritten: a taken name is saved as `name (1).ext`, `name (2).ext`, and so on.
- `Save-InforcerReportOutput -FileName` writes your name directly; the server's name is not used.
- On Windows the file is marked as downloaded from the internet, so Office opens it in Protected View.
- A `401` on v1 renews the token once; a `429` is not retried. Errors use ErrorId `DownloadFailed_<status>`. A redirect is refused (see [Redirects](#redirects)).

---

## Schemas

The schemas below are the beta shapes, which are also the property names the module outputs. On a client-credentials login v1 responses are mapped to these names ([mapping table](#how-v1-fields-map-to-the-modules-names)); properties without a v1 source are absent and v1-only properties are added. The raw v1 schemas are in [`openapi-snapshot-v1.json`](./openapi-snapshot-v1.json).

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

Represents a tenant in the inforcer system.

| Property | Type | Description |
|----------|------|-------------|
| clientTenantId | integer | Unique identifier for the tenant in inforcer. |
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

> **Policy type name**: v1 sends `policyTypeName` (mapped to `inforcerPolicyTypeName`); the beta list currently sends no type name. `Export-InforcerTenantDocumentation` then fills its "Profile type" column from `policyTypeId`, using names the inforcer API returned for that id; ids without a known name stay blank. Since 2026-11-05 v1 `/policies` and `alignmentDetails` use the same name per id; `alignmentDetails` keeps the older label in `policyTypeFriendlyName`.

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

### CreatedUser

Returned by `POST /v1/tenants/{msTenantId}/users`. `New-InforcerUser` adds `TenantId`, `displayName` and `userPrincipalName` (from the request) so the result can be piped to `Set-InforcerUser`.

| Property | Type | Description |
|----------|------|-------------|
| id | string (uuid) | The new user's Microsoft Entra object id. |

### UserUpdate

The profile fields of `PATCH /v1/tenants/{msTenantId}/users/{userId}` (and of the create body). All optional and nullable unless noted; `null` clears a field. `displayName`, `mailNickname`, `userPrincipalName`, `mail` and `accountEnabled` cannot be cleared. Unknown properties are rejected.

| Property | Type | Limits / notes |
|----------|------|----------------|
| accountEnabled | boolean | `false` blocks sign-in; existing sessions last until their tokens expire. |
| displayName | string | 1-256 characters. |
| mailNickname | string | 1-64 characters. The mail alias. |
| userPrincipalName | string | The sign-in name. |
| givenName, surname | string | 1-64 characters. |
| jobTitle | string | 1-128 characters. |
| department | string | 1-64 characters. |
| officeLocation, city, state, country | string | 1-128 characters. |
| streetAddress | string | 1-1024 characters. |
| postalCode | string | 1-40 characters. |
| mobilePhone, preferredLanguage, companyName, employeeType | string | 1-64 characters. |
| usageLocation | string | Two letters (ISO 3166), such as `GB`. |
| employeeId | string | 1-16 characters. |
| mail | string (email) | |
| businessPhones | string[] | At most one number. |
| otherMails | string[] (email) | |
| managerId | string (uuid) | The manager's object id; `null` removes the manager. |

### PasswordReset

The body of `POST /v1/tenants/{msTenantId}/users/{userId}/password`.

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| password | string | Yes | The new password; it must meet the tenant's password policy. A blank password is a `400`. |
| forceChangePasswordNextSignIn | boolean | Yes | Whether the user must change the password when they next sign in. `Set-InforcerUser` sends `true` unless you pass `-ForceChangePasswordNextSignIn $false`. |

### UserAuthenticationMethod

One element of `authenticationMethods` from `GET /v1/tenants/{msTenantId}/users/{userId}/authenticationMethods`. Every property is always present; the ones that do not apply to the type are `null`.

| Property | Type | Description |
|----------|------|-------------|
| id | string | The method's Microsoft Entra id. Usually a uuid, but not for every type (a passkey's id is not). The password and each phone type have the same id for every user. |
| type | string | `password`, `phone`, `email`, `microsoftAuthenticator`, `passkey`, `windowsHelloForBusiness`, `platformCredential`, `temporaryAccessPass`, `softwareOath`, `hardwareOath`, `qrCodePin`, `externalAuthentication` or `other`. More values may be added; treat an unknown value as `other`. |
| displayName | string \| null | The device or key name, for Microsoft Authenticator, passkeys, Windows Hello for Business, platform credentials and hardware OATH tokens. |
| createdDateTime | string (date-time) \| null | When the method was registered; for `password`, when it was last set. |
| deletable | boolean | Whether inforcer can delete the method. `false` for `password`, `externalAuthentication` and `other`. |
| phoneNumber | string \| null | For a `phone` method. |
| phoneType | string \| null | `mobile`, `alternateMobile` or `office`, for a `phone` method. |
| emailAddress | string \| null | For an `email` method. |

### TenantGroupSummary

Summary of an Entra ID group (returned from list endpoint).

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| id | string (GUID) | Yes | The group ID. |
| displayName | string | Yes | Display name of the group. |
| description | string | No | Description of the group. |
| mail | string | No | Email address of the group. |
| visibility | string | No | Visibility (e.g. Public, Private). |
| membershipRule | string | No | Dynamic membership rule; `null` for assigned groups. Filled on the list since inforcer fixed it (2026-11; verified live 2026-11-03: every `DynamicMembership` group carried its rule). |
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
| onPremisesSyncEnabled | boolean | No | Whether synced from on-premises AD. Three states: `true` = synced, `false` = was synced but no longer, `null` = never synced (cloud-only). Not returned by the list endpoint at all. |
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

### TenantSecureScoreDetails

Top-level response object for `GET /beta/tenants/{tenantId}/secureScores`.

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| currentScore | number | Yes | Current Microsoft Secure Score. |
| currentScorePercentage | number | No | Current score as a percentage of `maxScore`. |
| maxScore | number | Yes | Maximum possible Secure Score. |
| licensedUserCount | integer | No | Number of licensed users. |
| enabledServices | array\<string\> | No | Services enabled for this tenant (e.g. `AzureAD`, `Exchange`). |
| scores | array\<[TenantSecureScoreHistoryPoint](#tenantsecurescorehistorypoint)\> | No | Up to 90 days of daily score history. |
| controlProfiles | array\<[TenantSecureScoreControlProfile](#tenantsecurescorecontrolprofile)\> | No | Actionable control profiles with remediation guidance. |
| controlCategoryScores | array\<object\> | No | Per-category scores and history (e.g. Identity, Data, Device). |

**PSTypeName:** `InforcerCommunity.SecureScore`

### TenantSecureScoreHistoryPoint

Single daily score entry in the `scores` array of `TenantSecureScoreDetails`.

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| createdDateTime | string (datetime) | Yes | Date the score was recorded (UTC). |
| currentScore | number | Yes | Score at this date. |
| currentScorePercentage | number | No | Score expressed as a percentage. |
| maxScore | number | Yes | Maximum possible score at this date. |

### TenantSecureScoreControlProfile

Actionable control profile in the `controlProfiles` array of `TenantSecureScoreDetails`.

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| id | string | Yes | Control profile identifier. |
| title | string | Yes | Human-readable title. |
| controlCategory | string | No | Category (e.g. Identity, Data). |
| service | string | No | Associated service (e.g. Azure AD, Exchange). |
| currentScore | number | No | Current score for this control. |
| currentScorePercentage | number | No | Current score as a percentage. |
| maxScore | number | No | Maximum score for this control. |
| maxScorePercentage | number | No | Maximum score as a percentage. |
| scoreDifference | number | No | Gap between current and max score (higher = larger remediation opportunity). |
| scoreDifferencePercentage | number | No | Score difference as a percentage. |
| remediation | string | No | Recommended remediation steps (HTML). |
| remediationImpact | string | No | Impact description of the remediation. |
| actionUrl | string | No | URL to take the recommended action. |

**PSTypeName:** `InforcerCommunity.SecureScoreControlProfile`. Each item in `.ControlProfiles` on a `TenantSecureScoreDetails` gets this PSTypeName inserted so the default `Format-List` view renders `Title`, `ControlCategory`, `Service`, current/max score with potential gain, `RemediationImpact`, `ActionUrl`, `Id` — the full HTML `remediation` string stays accessible via `.remediation`.

### Assessment

An assessment from `GET /beta/assessments`.

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| id | string | Yes | Assessment ID (alphanumeric, not a GUID). |
| name | string | Yes | Display name. |
| description | string | No | Description. |
| assessmentType | string | No | Type, e.g. `platform`, `custom`, `community`. |
| tags | string[] | No | Tags. |
| lastUpdated | string (date-time) | No | Last update. |
| created | string (date-time) | No | Creation time. |

**PSTypeName:** `InforcerCommunity.Assessment`

### AssessmentCheck

One item of `results` in an assessment run.

| Property | Type | Description |
|----------|------|-------------|
| id, key, name | string | Check identity and name. |
| category, subCategory | string | Grouping. |
| description, rationale, remediation, impact | string | Explanation and fix. |
| importance | string | Importance level. |
| findings | object | `{ compliant, status, message, scores: [{ objectId, objectName, score, passes[], violations[], warnings[] }] }`. `status` is `pass`, `fail`, `insufficientPermissions` or `error` (may be absent); `compliant` is `false` for unassessed checks too. |
| frameworks, tags, version, created, lastUpdated | various | Metadata. |

The module adds `Status` (`Pass`, `Fail`, `InsufficientPermissions`, `Error`), `ObjectsEvaluated`, `FindingsMessage` and `Scores`, and, for several tenants, `TenantName` and `TenantId`. **PSTypeName:** `InforcerCommunity.AssessmentCheck`

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

## Microsoft Graph

Optional. With `-FetchGraphData`, `Export-InforcerTenantDocumentation` and `Compare-InforcerEnvironments` (and `Connect-Inforcer -FetchGraphData`, which signs in up front) call Microsoft Graph directly to turn IDs into names. This is not the inforcer API: it uses an interactive delegated sign-in (Microsoft.Graph.Authentication module, not installed automatically) for the tenant being documented, and an existing Graph session is reused only when its tenant and scopes match.

Delegated scopes requested, all read-only:

| Scope | Used for | Graph calls |
|-------|----------|-------------|
| `Directory.Read.All` | Group, user and other object names in assignments and Conditional Access; directory role names (built-in and custom); Conditional Access application names | `POST /v1.0/directoryObjects/getByIds` (up to 1000 IDs per request); `GET /v1.0/roleManagement/directory/roleDefinitions`; `GET /v1.0/servicePrincipals?$filter=appId in (...)` (15 app IDs per request; a built-in name map is used only for IDs Graph does not return) |
| `Policy.Read.All` | Named location names in Conditional Access | `GET /v1.0/identity/conditionalAccess/namedLocations` |
| `DeviceManagementConfiguration.Read.All` | Assignment filter and scope tag names; custom compliance rules (Compare only) | `GET /beta/deviceManagement/assignmentFilters`, `GET /beta/deviceManagement/roleScopeTags`, `GET /beta/deviceManagement/deviceCompliancePolicies('{id}')` |

Conditional Access lookups (roles, named locations, applications) run for Export; compliance rules are fetched only by Compare.

Behaviour:

- `429`, `5xx` and network failures are retried (up to 3 attempts). `401` and `403` are not retried: a warning names the scope the call most likely lacks, and those names stay as raw IDs.
- Lists follow `@odata.nextLink` up to 10,000 items; a warning says when more were available.
- The name maps are built per tenant and per call, so one tenant's names never appear in another tenant's document.

---

## Response Wrapper (beta)

All beta API responses are wrapped in a standard envelope:

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

## Error Responses (beta)

v1 errors are `application/problem+json`, see [Errors](#errors).

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
