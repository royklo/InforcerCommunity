# Reports API — Feedback & Questions

From two empirical-probing sessions against `api-uk.inforcer.com` (UK region, beta endpoints) on 2026-06-25 and 2026-06-26. All findings reproduced at least twice unless noted. Test scope: API key with `Reports.Read` + `Reports.Trigger` scopes, targeting tenants `14436` and `18159`.

---

## 🐛 Bugs (reproducible)

### 1. Duplicate report+format renders in the last-listed format only

When the same `type` appears twice in `POST /reports/runs` with different `outputFormat` values, **both items render in the format of the last occurrence** — and you get two byte-identical files.

**Request:**
```json
{
  "reports": [
    { "type": "TenantAuditReport", "outputFormat": "html" },
    { "type": "TenantAuditReport", "outputFormat": "pdf"  }
  ],
  "tenants": { "includeTenants": [14436] }
}
```

**Expected:** 1× html + 1× pdf
**Actual:** 2× pdf, identical 285,757 bytes
RunIds for reference: `321687c7-0d2f-471d-93db-64625459d0ea`, `09d9822b-89b8-4c30-8680-d5f82f0f3088`. Reversing the order produces 2× html instead (`435189db-c0e8-4fcb-9c76-5ad7db4415b9`).

**Suggested fix:** either honour each item's `outputFormat`, or reject duplicate `(type, outputFormat)` combos at queue time.

### 2. Exact-duplicate report entries produce duplicate outputs

Posting two identical `{ "type": "ActiveUserCount", "outputFormat": "csv" }` entries produces 2 identical CSV outputs in the run (60 bytes each, same content). RunId `d3ca706e-7e77-45d3-9629-f084465f9f2a`. Probably the same root cause as #1.

**Suggested fix:** dedupe at queue time, or document that duplicates are intentional.

---

## ⚠️ Design inconsistencies worth tightening

### 3. `GET /reports/runs` propagation lag (~4 minutes)

A freshly queued run is reachable via `GET /runs/{id}/outputs` within seconds, but doesn't appear in `GET /runs` until ~4 minutes later. Measured: `094a49ed-b9b8-492b-870f-0f76fd3b2954` — outputs terminal at T+6s, list-visible at T+231s.

Combined with the lack of `GET /runs/{id}` (see Q4), this makes the list endpoint unsuitable for polling.

### 4. Three different error response shapes

| Source | Shape |
|--------|-------|
| App-layer validation/auth | `{ data, errorCode, success, message, errors[] }` |
| APIM routing (404 on unsupported method/path) | `{ statusCode, message }` |
| Missing/wrong `Content-Type` (415) | RFC 9110 ProblemDetails: `{ type, title, status, traceId }` |

Clients have to parse three shapes to know what went wrong. Suggest standardising on the `{ success, message, errors }` envelope everywhere.

### 5. Malformed GUID in URL → 401 `auth_failure`

`GET /reports/runs/not-a-guid/outputs` returns `401` with message `"User is not authenticated"` — instead of `400 Bad Request` or `404 Not Found`. Looks like an APIM routing artifact (the URL fails to match the route, falls through to the auth layer). Misleading for clients.

### 6. Unknown `parameters` keys silently accepted

`POST` with `parameters: { "bogus": "x" }` on a type that requires no parameters succeeds (202). The unknown key is ignored. Compare: out-of-range *values* for known keys are rejected at queue time. This is inconsistent — typos in parameter keys go unnoticed.

### 7. Inconsistent "no data" handling

Some report types produce a 4-byte BOM-only CSV (`EF BB BF 0A`, no header row) when there's no data. Others omit the output entirely from the run.

Same payload, observed split:
- `GetDetectedRisks` → 4-byte BOM CSV for both tenants
- `GetRiskyUsers` (csv) → 4-byte BOM for tenant 18159, **completely omitted** for tenant 14436

RunId: `36b65783-94e6-4f46-988e-6986647b7230`. Hard for callers to distinguish "report ran with empty result" from "report didn't run for this tenant."

### 8. `GET /reports/runs` query parameters silently ignored

`?limit=`, `?status=`, `?since=`, `?from=`, `?createdAfter=`, `?$top=`, `?skip=`, `?page=`, `?runId=` — all silently ignored, always returns the full set. Either reject unknown params or implement filtering (see request #5 below).

### 9. .NET internals leak in JSON conversion errors

```
"The JSON value could not be converted to System.Int32. Path: $.tenants.includeTenants[0]..."
"The JSON value could not be converted to System.Collections.Generic.IReadOnlyDictionary`2[System.String,System.String]..."
```
Cosmetic but unprofessional — exposes server-side implementation. Suggest a domain-meaningful error like `"tenants.includeTenants[0] must be an integer"`.

### 10. Whitespace in `type` not normalised

`"type": "  ActiveUserCount  "` → 400 `"is not a known report type"`. Trimming before lookup would be a small UX win, but documented strictness is acceptable.

### 11. Field-naming inconsistency for output-format lists across Reports endpoints

`GET /reports/types` returns each catalog entry's accepted formats as **`supportedOutputFormats[]`**, but `GET /reports/runs` exposes the same conceptual data on each run record as **`outputFormats[]`**. Two field names for the same array on the same feature forces clients to maintain dual-key lookup helpers (e.g. `try $.supportedOutputFormats || $.outputFormats`). Pick one — preference would be `supportedOutputFormats` everywhere, or `outputFormats` everywhere.

### 12. Run identifier is `runId`, but every other entity returned by the Inforcer API uses `id`

`GET /tenants[/{id}]`, `GET /baselines`, `GET /assessments`, `POST /reports/runs/{id}/outputs` (the inner output records), `GET /tenants/{id}/users` — every other resource uses `id` at the top level of the record. Only run records use `runId`. Two consequences: (a) generic clients can no longer assume `record.id` is the primary key for any Inforcer resource; (b) shape-aware consumers like `Where-Object { $_.id -eq $needle }` silently miss runs. Standardise on `id` (preferred) or document `runId` as a deliberate exception.

### 13. Output records use `format` and `sizeBytes` — third name for the same fields across the same feature

`POST /reports/runs` accepts `outputFormat` (singular) on each requested report. `GET /reports/runs` then exposes `outputFormats[]` (plural) on the run record. `GET /reports/runs/{id}/outputs` returns `format` (no `output` prefix at all) on each individual output record. Likewise size — there's no `fileSize`, `size`, or `length` precedent elsewhere, but output records use `sizeBytes`. Three names for the same single concept (`outputFormat` / `outputFormats` / `format`) across one user flow is a documentation tax. Suggest aligning to `outputFormat` (request + response) and using `size` or `fileSize` to match common HTTP conventions.

### 14. `assessment-id` parameter is an alphanumeric string, not a GUID — document explicitly

The implementation-handoff brief (and intuitive client code that types AssessmentId as `[Guid]`) assumed assessment IDs are GUIDs (e.g. `9b7c…-…-…-…-…`). The real shape is opaque alphanumeric strings like `l1f8wd29pl44pp1j66r9`. This is unique among Inforcer resources — tenants are numeric, baselines/users/groups are GUIDs. Recommend either documenting `assessment-id` as `string (opaque, ≤32 chars)` in the OpenAPI schema, or migrating to a GUID-shaped identifier.

### 15. The ~4-minute list-propagation lag (already filed in §3) also blocks `-IncludeOutputs`-style discovery

Per §3 a freshly-queued run isn't visible in `GET /reports/runs` for ~4 minutes. We've now confirmed the same lag bites *any* enumeration flow — e.g. "for every recent run, fetch its outputs and download them" via `GET /runs` followed by `GET /runs/{id}/outputs` — not just polling. The PowerShell client works around this by probing `GET /runs/{id}/outputs` directly when an explicit RunId is supplied, but that's not viable for "show me everything from the last 30 minutes" use cases. Already covered by feature request #1 (`GET /runs/{id}`) + #3 (`?since=` filter); flagging the broader impact for prioritisation.

### 16. Collated outputs return `tenantId: 0` — collides with the integer tenant-ID space

When a request uses `collate: true` on a `collatable: true` type, the resulting output record returns `tenantId: 0` (verified live). Numeric `0` is indistinguishable at the schema level from a hypothetical Inforcer client tenant with ID 0, and clients can't distinguish "collated cross-tenant aggregate" from "single tenant with ID 0" without additional context. Suggest either emitting `tenantId: null` for collated outputs or — preferably — adding an explicit `scope: "collated" | "tenant"` discriminator so the response is self-describing.

---

## ❓ Questions for the API team

### Q1. Full enum of run `status` values
We've only ever observed `completed` across ~50 runs. Are there other states (`queued`, `running`, `failed`, `cancelled`, `partiallyFailed`)? If a run can fail asynchronously, what does its record look like? Most validation seems to happen synchronously at queue time — is async failure actually possible?

### Q2. How does `collatable` actually work?
For report types with `collatable: true`, does a multi-tenant run produce a single cross-tenant output, or one output per tenant? Our probes always produced one-per-tenant regardless of `collatable`. What does collation mean in practice?

### Q3. Retention policy
Outputs from yesterday are still byte-identically downloadable today (15h+). What's the documented retention window for:
- Run metadata in `GET /runs`?
- Output blobs in `GET /runs/{id}/outputs/{id}`?

### Q4. Direct run lookup
Is `GET /runs/{id}` planned? Currently we have to scan the list (with the 4-min lag and no filter support) to get a specific run's metadata.

### Q5. Concurrency / quota limits
We sent 10 parallel POSTs with no rate-limit headers and no throttling. What are the documented limits (concurrent runs, daily quota, requests/sec)? Should we be implementing client-side throttling?

### Q6. `triggeredByType` enum
We've only seen `user`. What other values exist (`system`, `scheduled`, `api`, `webhook`)?

### Q7. List endpoint cap
Is there a maximum number of runs returned by `GET /reports/runs`? We've seen the response grow from 14 to 20 as more runs accumulated; we never hit a ceiling.

### Q8. Case-insensitivity of `type` / `outputFormat`
Both `"activeusercount"` and `"ActiveUserCount"` were accepted. Same for `"CSV"` vs `"csv"`. Is case-insensitive matching a contract we can rely on, or a current implementation detail?

### Q9. `Content-Disposition` filename stability
The download endpoint returns useful filenames like `Assessment_NIS2HardeningPREVIEW.pdf`. Are these stable / safe for callers to depend on for saving files?

### Q10. `x-correlation-id` for support
Every response includes `x-correlation-id`. Is this the right identifier for us to include when filing support tickets?

---

## 💡 Feature requests (nice-to-have)

1. **`GET /reports/runs/{id}`** for direct run-record lookup (eliminates the list-endpoint lag problem entirely).
2. **Run cancellation** — `DELETE /runs/{id}` or similar — for long-running batches the caller no longer needs.
3. **Filter/paginate `GET /runs`** — `?status=`, `?since=`, `?limit=`, `?after=` (cursor). Today the endpoint always returns the full set, which won't scale.
4. **Webhook callback** on run completion — eliminate polling for high-volume integrations.
5. **Tenant selector siblings** — alongside `includeTenants`, support `excludeTenants`, `allTenants: true`, or `tags: [...]` to match the Inforcer tagging model.
6. **Server-side dedup** of `(type, outputFormat)` pairs in `POST /reports/runs` (would also resolve bug #1).
7. **Document the empty-result behavior** explicitly in the OpenAPI schema (4-byte BOM vs omitted output), or unify it.

---

## ✅ Things that work great (worth keeping)

For balance — these behaviors are reliable and we're building on them:

- `Inf-Api-Key` authentication is rock-solid; `WWW-Authenticate` header on 401 makes auth-failure debugging easy.
- `x-correlation-id` on every response — excellent.
- Validation errors at queue time are clear and actionable (parameters, formats, tenant scope).
- Output downloads include proper MIME types and meaningful `Content-Disposition` filenames.
- Server transparently dedupes duplicate tenant IDs in `includeTenants` — helpful.
- Burst of 10 parallel POSTs / 30 parallel GETs handled cleanly with no rate-limit errors.
- 13–15+ hour output retention confirmed; downloads are byte-identical on re-fetch (idempotent).
- The 404→200 transition on `GET /runs/{id}/outputs` is a clean, fast polling mechanism.
