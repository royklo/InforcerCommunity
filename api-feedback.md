# Inforcer API Feedback

Findings from building the InforcerCommunity PowerShell module against the Inforcer REST API.
Report to API team for consideration in future releases.

Each item describes what the API currently does, what it should do instead, and how our PowerShell module works around it today.

---

## Tenants

### `GET /beta/tenants/{id}` — Returns the full tenant list instead of a single tenant

**Severity:** High
**The problem:** Calling `GET /beta/tenants/{id}` with a specific tenant ID returns all tenants (with duplicates), not just the requested one. A single-resource endpoint should return one resource.
**What should change:** `GET /beta/tenants/{id}` should return only the tenant matching that ID, or 404 if not found. This is standard REST behavior.
**How our module handles it:** We never call the single-tenant endpoint. Instead we always fetch the full list via `GET /beta/tenants`, deduplicate by `clientTenantId`, and filter client-side with `Where-Object`. This works but wastes bandwidth — every tenant lookup downloads the entire list.

### `GET /beta/tenants` — Sometimes returns a single object instead of an array

**Severity:** Low
**The problem:** When there is only one tenant, the API returns a plain JSON object instead of a one-element array. This forces every consumer to handle both shapes.
**What should change:** List endpoints should always return an array, even when there is only one result. `[]` for zero, `[{...}]` for one, `[{...},{...}]` for many.
**How our module handles it:** We wrap every list response in `@()` to force it into an array regardless of what the API returns.

---

## Groups

### `GET /beta/tenants/{tenantId}/groups?search=` — Search only matches prefix, not contains

**Severity:** High
**The problem:** The `?search=` parameter only matches groups whose `displayName` starts with the search term. Searching for `comp` returns nothing even though "All Company" exists. Searching for `empl` returns nothing even though "All Employees" exists. Only `all` works because those groups start with "All".
**What should change:** Search should do substring/contains matching on `displayName`. When someone searches for "comp", they expect to find "All Company". This is standard behavior in Microsoft Graph and most search APIs.
**How our module handles it:** We added a separate `-Filter` parameter that fetches all groups from the API, then applies local PowerShell wildcard matching (e.g. `*comp*`). This gives users contains-matching but is slower than server-side filtering because it downloads everything first.

### `GET /beta/tenants/{tenantId}/groups/{groupId}` — Members lack userPrincipalName

**Severity:** High
**The problem:** The `members` array in the group detail response returns only `id`, `displayName`, and `type` per member. There is no `userPrincipalName`.
**What should change:** Include `userPrincipalName` for each member. `displayName` is not unique — two users can have the same name. UPN is the reliable identifier that IT admins use everywhere.
**How our module handles it:** We show `displayName` in the default view and expose the full member data via `Select-Object -ExpandProperty Members`. Users who need UPN must cross-reference with `Get-InforcerUser` per member, which requires N extra API calls per group.

```json
// Current response
"members": [
  { "id": "...", "displayName": "Alex Wilber", "type": "#microsoft.graph.user" }
]

// Requested response
"members": [
  { "id": "...", "displayName": "Alex Wilber", "userPrincipalName": "AlexW@contoso.com", "type": "#microsoft.graph.user" }
]
```

### `GET /beta/tenants/{tenantId}/groups/{groupId}` — Returns 404 for security groups

**Severity:** Medium
**The problem:** Some security groups that appear in the list endpoint (`GET /groups`) return 404 when queried by ID via the detail endpoint (`GET /groups/{groupId}`). If a group is in the list, it should be retrievable by ID.
**What should change:** The detail endpoint should return any group that exists in the list endpoint. If certain group types are not supported for detail retrieval, the list endpoint should indicate this (e.g. a `detailAvailable` flag) so consumers don't make a failing call.
**How our module handles it:** We catch the 404 and return a friendly error message: "Group not found in tenant." Users see the group in the list but can't get its detail — which is confusing.

### `GET /beta/tenants/{tenantId}/groups` — `visibility` is often `null` instead of an explicit value

**Severity:** Medium
**The problem:** Many groups return `visibility: null` in the list response, including mail-enabled and Entra-named groups where the same tenant shows `Private` or `Public` for other rows. The field is inconsistent — some items return concrete values, others return `null` for what appear to be comparable group types.
**What should change:** Always return an explicit value for `visibility`. Use `"Public"`, `"Private"`, or a documented sentinel like `"NotApplicable"` for group types where M365 visibility doesn't apply. Never return `null` when the underlying directory object has a known visibility.
**Why it matters:** `null` reads as "unknown" or "missing data." Reporting and automation (filtering "all private groups," compliance views, etc.) need a stable value per row without special-casing `null`.
**How our module handles it:** We display the value as-is. Empty/null shows as blank in the output. Users have no way to distinguish "truly private" from "visibility not returned by API."

**Note:** `groupTypes: []` alongside `visibility: null` is ambiguous for distinguishing security vs distribution vs M365 groups. An explicit `groupKind` field or documented mapping would help.

---

## Audit Events

### `POST /beta/auditEvents/search` — No server-side filtering by event ID or correlation ID

**Severity:** High
**The problem:** There is no endpoint to retrieve a single audit event by its ID, or to query events by correlation ID. The only way to find a specific event is to search all event types within a date range, download all results, and filter locally.
**What should change:** Add query parameters like `?id={guid}` or `?correlationId={guid}` to the search endpoint, or provide dedicated endpoints like `GET /beta/auditEvents/{id}`. This is basic CRUD — you should be able to retrieve a resource by its identifier without downloading everything.
**How our module handles it:** We have `-Id` and `-CorrelationId` parameters that perform a broad search across all event types and filter client-side with `Where-Object`. This is slow and wasteful — a tenant with thousands of events forces the module to paginate through all of them just to find one.

### Supported event types endpoint — Can fail without fallback

**Severity:** Low
**The problem:** The API that returns supported event types can fail, and there's no documented default list of event types to fall back on.
**What should change:** Document the standard event types so consumers can hardcode a fallback, or make the event types endpoint more reliable.
**How our module handles it:** When the event types API fails, we fall back to `authentication` and `failedAuthentication` as defaults and show a warning so the user knows they might not be seeing all event types.

---

## Alignment Scores

### `GET /beta/alignmentScores` — Inconsistent response format

**Severity:** Medium
**The problem:** The alignment scores endpoint can return two different response formats depending on (unknown) conditions: a flat array with `tenantId, score, baselineGroupName` properties, or a nested format with `clientTenantId` and `alignmentSummaries` array. Consumers have to detect which format was returned and handle both.
**What should change:** Pick one format and always return it. Ideally the flat format (simpler to consume). If the nested format is needed for backward compatibility, document both and add a version or format parameter so consumers can request the shape they want.
**How our module handles it:** We detect the response shape at runtime — if the first item has a `tenantId` property it's flat format, otherwise it's nested. Then we use separate code paths to normalize both into the same output. This works but doubles the code complexity for what should be a single endpoint.

---

## General — Pagination metadata placement

### `continuationToken` at response root instead of inside `data`

**Severity:** Low
**The problem:** The Users and Groups endpoints place `continuationToken` and `totalCount` as siblings of `.data` in the response root, while other endpoints wrap everything inside `.data`. This inconsistency forces consumers to handle two different pagination patterns.
**What should change:** Standardize pagination metadata placement. Either always inside `.data` (consistent with most endpoints) or always at the response root (consistent with Microsoft Graph). Pick one and document it.
**How our module handles it:** For paginated endpoints (Users, Groups), we use a special `-PreserveFullResponse` flag to get the raw response and manually extract `continuationToken` from the root. For non-paginated endpoints, the standard `.data` unwrapping works fine.

---

## Feature Request — Self-Discoverable API (OpenAPI / Swagger)

### The API should publish a machine-readable schema that clients can discover automatically

**Severity:** High
**The problem:** There is no OpenAPI/Swagger endpoint or published schema for the Inforcer API. When new endpoints go live, consumers have no way to discover them programmatically. We have to manually check the portal, wait for release notes, or stumble upon changes during development. This makes it impossible to:
- Automatically detect new endpoints or breaking changes
- Generate client code or type definitions
- Build automated API drift detection (we tried — see `scripts/Test-ApiSchemaChanges.ps1` — but it relies on a manually maintained snapshot)
- Know when a property was added, removed, or changed type

**What should change:** Publish an OpenAPI 3.x specification at a well-known endpoint (e.g. `GET /swagger/v1/swagger.json` or `GET /openapi.json`). This should:
1. **Always reflect the live API** — generated from the actual code, not manually written
2. **Include all endpoints** with parameters, request/response schemas, and error codes
3. **Be versioned** — so consumers can diff between versions and detect changes
4. **Be publicly accessible** — no authentication required to read the spec (the schema is not sensitive; the data is)

**Why it matters for the community:**
- Module authors like us can automatically detect when new endpoints ship and add cmdlets for them
- We can generate property type definitions instead of guessing from sample responses
- We can set up CI that alerts when the API schema changes (new fields, removed fields, type changes)
- We can validate our `api-schema-snapshot.json` against the live spec instead of maintaining it by hand
- Other tooling (Postman collections, TypeScript clients, Python SDKs) can be auto-generated

**How we handle it today:** We maintain a manual `docs/api-schema-snapshot.json` that we update by hand whenever we discover new endpoints. We have a drift detection script but it can only compare against our own snapshot — not the actual API contract. Every new endpoint is discovered by trial and error or by reading the portal.

---

*Last updated: 2026-04-11*
