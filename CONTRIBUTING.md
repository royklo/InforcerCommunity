# Contributing to the Inforcer PowerShell Module

Thank you for your interest in contributing. This project is maintained by the community. Below is how to contribute via fork and pull request, how to report bugs, and what we expect from code changes.

## How to contribute (fork and pull request)

1. **Fork the repository**  
   Click **Fork** on [the GitHub repo](<!-- REPLACE: GITHUB_URL -->).

2. **Clone your fork**
   ```powershell
   git clone https://github.com/YOUR_USERNAME/Inforcer-Powershell-Module.git
   cd Inforcer-Powershell-Module
   ```

3. **Create a branch** for your change
   ```powershell
   git checkout -b feature/your-feature-name
   # or: git checkout -b fix/bug-description
   ```

4. **Make your changes** in `Powershell/` (see [Development setup](#development-setup) and [Code style](#code-style)).

5. **Run tests** (see [Testing](#testing)).

6. **Commit and push** to your fork
   ```powershell
   git add .
   git commit -m "Short description of your change"
   git push origin feature/your-feature-name
   ```

7. **Open a pull request**  
   Go to the [original repository](<!-- REPLACE: GITHUB_URL -->) and open a **New pull request** from your branch. Fill in the PR template (summary of changes, related issue if any, checklist).

## Development setup

- **PowerShell 7.0+** is required.
- No build step: the module is a script module. After editing files under `Powershell/`, re-import:
  ```powershell
  Import-Module ./Powershell -Force
  ```
- Optional: run the full cmdlet verification script from repo root:
  ```powershell
  pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/Test-AllCmdlets.ps1
  ```

## Code style and consistency

The module follows a **consistency contract** so all cmdlets behave predictably:

- **Parameter order:** Format → TenantId → Tag (if any) → OutputType for Get-* cmdlets that return API data.
- **-Format and -OutputType:** Present where applicable; do not remove them.
- **Property names:** Use the standard PascalCase aliases (Tenant, Baseline, Policy, AlignmentScore, AuditEvent) implemented in `Powershell/Private/Add-InforcerPropertyAliases.ps1`.
- **JSON depth:** Always 100 for `-OutputType JsonObject`.

The full contract and checklist are in `.cursor/agents/inforcer-unified-guardian.md` and summarized in `.cursor/skills/inforcer-unified-guardian/SKILL.md`. When you fix a bug or change behavior, update **FINDINGS.md** with what was done and how to test.

## How to raise a bug

Use the **Bug report** issue template so we get the information we need:

1. Go to [New issue](<!-- REPLACE: GITHUB_URL -->/issues/new).
2. Choose **Bug report**.
3. Fill in:
   - **Description** — What went wrong?
   - **Steps to reproduce** — Exact commands or steps.
   - **Expected behavior** — What you expected.
   - **Actual behavior** — What happened instead.
   - **Environment** — PowerShell version, OS, module version (e.g. `Get-Module Inforcer | Select-Object Version`).
   - **Additional context** — Logs, screenshots, or other details.

## How to request a feature

Use the **Feature request** template:

1. Go to [New issue](<!-- REPLACE: GITHUB_URL -->/issues/new).
2. Choose **Feature request**.
3. Describe the feature, the use case, and your proposed solution.

## Testing

From the repository root:

```powershell
Invoke-Pester ./Powershell/Tests/Consistency.Tests.ps1
```

This checks that exported functions and key parameters match the consistency contract. Optionally run `scripts/Test-AllCmdlets.ps1` to verify all cmdlets load and respond correctly when not connected.

## Pull request expectations

- **CI must pass** (the GitHub Action runs the consistency tests).
- **Tests pass locally** — run the Pester tests before pushing.
- **Comment-based help** — Keep `.SYNOPSIS`, `.DESCRIPTION`, parameters, and examples complete for any cmdlet you change.
- **Consistency contract** — Follow parameter order and property names; reference the guardian docs if you change parameters or output shape.
- **FINDINGS.md** — If your change fixes a bug or adds a finding, add or update the row with "What was done" and "How to test".

Avoid breaking changes to Public cmdlets or output properties without prior discussion in an issue.

## Adding a new cmdlet

1. Update the consistency contract in `.cursor/agents/inforcer-unified-guardian.md` (cmdlet list, parameters, and property names if you introduce a new object type).
2. Implement in `Powershell/Public/` and add the function name to `FunctionsToExport` in `Powershell/Inforcer.psd1`.
3. Update `docs/CMDLET-REFERENCE.md` with synopsis, parameters, examples, and example output.
4. Run the consistency checklist and tests; update `Powershell/Tests/Consistency.Tests.ps1` if the expected cmdlet/parameter list changes.

Thank you for contributing.
