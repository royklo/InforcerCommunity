# Repository check and GitHub setup checklist

**Date:** Generated for repos under `/Users/roy/github/royklo`  
**Repos:** `Inforcer-Powershell-Module`, `Powershell-Module-Automation`

---

## 1. Local check — what’s in place

### Inforcer-Powershell-Module

| Check | Status |
|-------|--------|
| **Location** | `/Users/roy/github/royklo/Inforcer-Powershell-Module` |
| **Git remote** | `git@github.com-personal:royklo/Inforcer-Powershell-Module.git` |
| **Branch** | `main` (tracks `origin/main`) |
| **Structure** | `module/` (Inforcer.psd1, .psm1, Public/, Private/, *.ps1xml), `Tests/`, `docs/`, `.github/workflows/` |
| **Workflows** | `build-and-test.yml` (Pester + PSScriptAnalyzer on push/PR), `trigger-publish.yml` (repository_dispatch on push to main) |
| **Manifest** | `module/Inforcer.psd1` — ModuleVersion 0.0.1, ProjectUri = `https://github.com/royklo/Inforcer-Powershell-Module` |
| **Trigger fallback** | `vars.AUTOMATION_REPO` defaults to `royklo/Powershell-Module-Automation` |
| **Local validation** | PSScriptAnalyzer: 0 errors; Pester: 11 tests passed |

### Powershell-Module-Automation

| Check | Status |
|-------|--------|
| **Location** | `/Users/roy/github/royklo/Powershell-Module-Automation` |
| **Git remote** | `git@github.com-personal:royklo/Powershell-Module-Automation.git` |
| **Branch** | `main` |
| **Structure** | `.github/workflows/publish-module.yml`, `scripts/` (Test-Module.ps1, Test-Version.ps1, Generate-Changelog.ps1, Publish-InfModule.ps1, Invoke-DynamicCommandValidation.ps1) |
| **Pipeline** | 14 steps including “Stage module for publish” (folder name = module name for Publish-Module) |

**Verdict:** Both repos are in the right place and configured correctly. Remaining work is in **GitHub** (secrets, variables, optional branch protection, first run).

---

## 2. What you need to do in GitHub

### A. Automation repo — `royklo/Powershell-Module-Automation`

1. **Open the repo:** https://github.com/royklo/Powershell-Module-Automation  
2. **Settings → Secrets and variables → Actions**  
3. **Add two repository secrets:**

   | Name | Value | Where to get it |
   |------|--------|------------------|
   | `PS_GALLERY_API_KEY` | Your PowerShell Gallery API key | powershellgallery.com → Profile → API Key (or Account → API Key) |
   | `MODULE_RELEASE_TOKEN` | A GitHub Personal Access Token (PAT) | GitHub → Profile → Settings → Developer settings → Personal access tokens. Create a token with **repo** scope (or fine‑grained with **Contents: Read and write** + **Metadata: Read** on `royklo/Inforcer-Powershell-Module`). This token is used to checkout the module repo and to create GitHub releases on it. |

4. **Workflow permissions (optional but recommended):**  
   **Settings → Actions → General** → under “Workflow permissions” choose **Read repository contents and packages**. The PAT above is used for writing to the module repo.

---

### B. Module repo — `royklo/Inforcer-Powershell-Module`

1. **Open the repo:** https://github.com/royklo/Inforcer-Powershell-Module  
2. **Settings → Secrets and variables → Actions**  
3. **Add one repository secret:**

   | Name | Value |
   |------|--------|
   | `AUTOMATION_TRIGGER_TOKEN` | A GitHub PAT that can trigger the automation repo. Easiest: use the **same** PAT as `MODULE_RELEASE_TOKEN` if it has **repo** scope and access to both repos. Otherwise create a new PAT with **repo** (or at least access to `royklo/Powershell-Module-Automation`). |

4. **Add one repository variable:**

   | Name | Value |
   |------|--------|
   | `AUTOMATION_REPO` | `royklo/Powershell-Module-Automation` |

   Path: **Settings → Secrets and variables → Actions** → **Variables** tab → New repository variable.

---

### C. Branch protection (optional but recommended)

On **Inforcer-Powershell-Module**:

1. **Settings → Branches → Add branch protection rule**  
2. **Branch name pattern:** `main`  
3. Enable:
   - **Require a pull request before merging**
   - **Require status checks to pass before merging** → add status checks: **Pester (script module)** and **PSScriptAnalyzer**  
   - **Do not allow bypassing the above settings** (if you want to enforce this even for admins)

This ensures only validated code can be merged and then published.

---

### D. First run — test the pipeline

1. **Push your local state** (if not already):
   ```bash
   cd /Users/roy/github/royklo/Inforcer-Powershell-Module
   git status
   git add -A && git commit -m "chore: sync local state"  # if there are changes
   git push origin main
   ```
2. **Module repo:** After push, open the **Actions** tab. You should see:
   - **Build and Test** run (Pester + PSScriptAnalyzer).
   - **Trigger Publish** run, which sends the dispatch to the automation repo.
3. **Automation repo:** Open **Actions** for `royklo/Powershell-Module-Automation`. You should see **Publish PowerShell Module** run (triggered by `repository_dispatch`).
4. **First time recommended:** Run the publish pipeline **manually** once to confirm everything works before relying on auto-trigger:
   - Automation repo → **Actions** → **Publish PowerShell Module** → **Run workflow**  
   - Set **repository** to `royklo/Inforcer-Powershell-Module` and **ref** to `main`, then run.  
   - Check that all 14 steps pass. If the module is not yet on PowerShell Gallery, the version check step will skip (first publish).  
   - **Note:** Steps 12–14 will actually publish to the gallery and create a GitHub release if you have real secrets configured. If you want to test without publishing, you’d need to temporarily comment out or skip those steps.

---

## 3. Quick reference

| Task | Where |
|------|--------|
| Add secrets | Repo **Settings** → **Secrets and variables** → **Actions** |
| Add variables | Repo **Settings** → **Variables** → **Actions** |
| Branch protection | Repo **Settings** → **Branches** → Add rule |
| Create PAT | GitHub profile → **Settings** → **Developer settings** → **Personal access tokens** |
| Run workflow manually | Repo **Actions** tab → select workflow → **Run workflow** |
| View run logs | **Actions** → click a run |

---

## 4. Troubleshooting

- **Trigger Publish fails with 404 or 401:**  
  Check that `AUTOMATION_TRIGGER_TOKEN` is a valid PAT with access to `royklo/Powershell-Module-Automation`, and that `AUTOMATION_REPO` is set to `royklo/Powershell-Module-Automation`.

- **Publish workflow can’t checkout module repo or create release:**  
  Check that `MODULE_RELEASE_TOKEN` has **repo** (or equivalent) and can access `royklo/Inforcer-Powershell-Module`.

- **Publish to PowerShell Gallery fails:**  
  Check `PS_GALLERY_API_KEY` and that the module version in `module/Inforcer.psd1` is greater than the version already on the gallery (if any).

- **Build and Test not running on push:**  
  Ensure the workflow files are on `main` and that GitHub Actions is enabled for the repo (**Settings** → **Actions** → **General**).

---

*After completing the steps above, both repositories are correctly placed and configured locally, and GitHub is set up for CI/CD and optional branch protection.*
