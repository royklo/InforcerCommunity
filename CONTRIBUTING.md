# Contributing to the inforcer PowerShell Module

Thank you for your interest in contributing. This project is maintained by the community. Below is how to contribute via fork and pull request, how to report bugs, and what we expect from code changes.

## How to contribute (fork and pull request)

1. **Fork the repository**
  Click **Fork** on [the GitHub repo](https://github.com/royklo/InforcerCommunity).
2. **Clone your fork**
  ```powershell
   git clone https://github.com/YOUR_USERNAME/InforcerCommunity.git
   cd InforcerCommunity
  ```
3. **Create a branch** for your change
  ```powershell
   git checkout -b feature/your-feature-name
   # or: git checkout -b fix/bug-description
  ```
4. **Make your changes** in `module/` (see [Development setup](#development-setup) and [Code style](#code-style-and-consistency)).
5. **Run tests** (see [Testing](#testing)).
6. **Commit and push** to your fork
  ```powershell
   git add .
   git commit -m "Short description of your change"
   git push origin feature/your-feature-name
  ```
7. **Open a pull request**
  Go to the [original repository](https://github.com/royklo/InforcerCommunity) and open a **New pull request** from your branch. Fill in the PR template (summary of changes, related issue if any, checklist).

## Development setup

- **PowerShell 7.0+** is required.
- No build step: the module is a script module. After editing files under `module/`, re-import:
  ```powershell
  Import-Module ./module -Force
  ```
- Optional: run the full cmdlet verification script from repo root:
  ```powershell
  pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Test-AllCmdlets.ps1
  ```

## Code style and consistency

The module follows a **consistency contract** so all cmdlets behave predictably:

- **Parameter order:** Format → TenantId → Tag (if any) → OutputType for Get-* cmdlets that return API data.
- **-Format and -OutputType:** Present where applicable; do not remove them.
- **Property names:** Use the standard PascalCase aliases (Tenant, Baseline, Policy, AlignmentScore, AuditEvent) implemented in `module/Private/Add-InforcerPropertyAliases.ps1`.
- **JSON depth:** Always 100 for `-OutputType JsonObject`.

When you fix a bug or change behavior, describe what was done and how to test in your pull request.

## How to raise a bug

Use the **Bug report** issue template so we get the information we need:

1. Go to [New issue](https://github.com/royklo/InforcerCommunity/issues/new).
2. Choose **Bug report**.
3. Fill in:
  - **Description** — What went wrong?
  - **Steps to reproduce** — Exact commands or steps.
  - **Expected behavior** — What you expected.
  - **Actual behavior** — What happened instead.
  - **Environment** — PowerShell version, OS, module version (e.g. `Get-Module InforcerCommunity | Select-Object Version`).
  - **Additional context** — Logs, screenshots, or other details.

## How to request a feature

Use the **Feature request** template:

1. Go to [New issue](https://github.com/royklo/InforcerCommunity/issues/new).
2. Choose **Feature request**.
3. Describe the feature, the use case, and your proposed solution.

## Testing

From the repository root:

```powershell
Invoke-Pester ./Tests
```

- `Tests/Consistency.Tests.ps1` checks that exported functions and key parameters match the consistency contract.
- `Tests/V1.*.Tests.ps1` are mocked suites for the v1 (client credentials) API: transport, response mapping, and each cmdlet group. They need no network and no credentials.
- Optionally run `scripts/Test-AllCmdlets.ps1` to verify all cmdlets load and respond correctly when not connected.

### Testing both logins

The module supports two logins and a change is only done when it works with both:

- **Mocked (always):** every cmdlet change needs a beta (API key) test and a v1 (client credentials) test. Mock `Invoke-InforcerApiRequest` / the web layer; v1 fixtures use anonymised data (Contoso/Fabrikam, zero GUIDs) shaped like the v1 spec.
- **Live (maintainers):** needs **both** an API key and an API client (client ID and secret with the read permissions you test). Run the smoke script once per login (`Connect-Inforcer -ApiKey ...`, then `Connect-Inforcer -ClientId ... -ClientSecret ...`) and compare. Never commit keys, secrets, tokens, tenant names or tenant IDs, and use only production `*.inforcer.com` hosts in tracked files. The legacy API allows 400 calls per hour per key, so a full live run can exhaust it.

### Auth and endpoint rules

- **Auth headers are built only in `Get-InforcerAuthHeader`.** Never write `Inf-Api-Key` or `Authorization` anywhere else; it also renews v1 tokens.
- **Endpoints are version-neutral.** Callers pass `/tenants/{id}/policies`; the request helper adds `/beta` or `/v1` and applies the v1 renames (`roles` to `directoryRoles`, `auditEvents/eventTypes` to `auditEvents/types`, `customBaselineId` to `baselineId`). Do not hard-code `/beta/` or `/v1/` in cmdlets.
- **v1 responses are mapped to the module's property names** through `ConvertFrom-InforcerV1Response -ObjectType ...` (via the request helper's `-ObjectType`). Add a mapping there rather than special-casing a cmdlet.
- Paging goes through `Invoke-InforcerPagedRequest`; tenant lookups through `Get-InforcerTenantList` (cached per session).
- `-TenantId` parameters carry the aliases `ClientTenantId` and `MsTenantId`.
- Document every endpoint change in `docs/API-REFERENCE.md` with both the beta API-key scope and the v1 API client permission.



## Adding a new cmdlet

1. Implement in `module/Public/` following the consistency rules above, and add the function name to `FunctionsToExport` in `module/InforcerCommunity.psd1`.
2. Update `docs/CMDLET-REFERENCE.md` with synopsis, parameters, examples, example output, and the required beta scopes and v1 permissions, and `docs/API-REFERENCE.md` for new endpoints.
3. Run the consistency tests; update `Tests/Consistency.Tests.ps1` if the expected cmdlet or parameter list changes.

Thank you for contributing.