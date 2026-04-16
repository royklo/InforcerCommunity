---
name: inforcer-changelog-release
description: >
  Writes changelogs and release notes for the InforcerCommunity PowerShell module. Use when
  preparing a release, bumping the version, writing CHANGELOG.md entries, drafting GitHub release
  notes, or reviewing what changed since the last tag. Triggers on "changelog", "release notes",
  "version bump", "prepare release", "what changed", or "draft release".
---

# Inforcer Changelog & Release Notes

> **Authority:** This skill handles versioning, changelogs, and release notes.
> It runs independently of the code-change chain (guardian → perf → docs).
> Use it **after** all code changes are done and tested.

## Triggers

Activate when the user mentions or the task involves:
- "Changelog", "update changelog", "add changelog entry"
- "Release notes", "draft release", "GitHub release"
- "Version bump", "prepare release", "cut a release"
- "What changed since last release"
- "Semantic version", "semver"

## Conventions

### Semantic Versioning

Follow [SemVer](https://semver.org/) based on conventional commit types:

| Change type | Version bump | Commit prefix examples |
|-------------|-------------|----------------------|
| Breaking change | **MAJOR** | `feat!:`, `refactor!:`, any with `BREAKING CHANGE:` in body |
| New feature / capability | **MINOR** | `feat:` |
| Bug fix, performance, patch | **PATCH** | `fix:`, `perf:`, `refactor:` (non-breaking) |
| Docs, tests, chore only | **No bump** (or PATCH if releasing) | `docs:`, `test:`, `chore:`, `ci:` |

### Conventional Commits

The automation pipeline (`Powershell-Module-Automation`) generates release notes from git history.
Commit messages **must** use these prefixes for the pipeline to categorize them:

| Prefix | CHANGELOG section | When to use |
|--------|------------------|-------------|
| `feat:` | Features | New cmdlet, parameter, output property, capability |
| `fix:` | Bug Fixes | Broken behavior, incorrect output, crash |
| `perf:` | Performance | Optimization without behavior change |
| `refactor:` | Refactoring | Code restructure without behavior change |
| `docs:` | Documentation | README, CONTRIBUTING, CMDLET-REFERENCE, help text |
| `test:` | Tests | New or updated Pester tests |
| `chore:` | Chores | CI, build, tooling, dependencies |
| `style:` | (omitted or Chores) | Formatting, whitespace |

### CHANGELOG.md Format

```markdown
## [X.Y.Z] - YYYY-MM-DD

### Features
- Description of new feature.

### Bug Fixes
- Description of fix.

### Performance
- Description of optimization.

### Refactoring
- Description of restructure.

### Documentation
- Description of docs change.

### Tests
- Description of test change.
```

**Rules:**
- Newest version at the top, below the header.
- Date in ISO 8601 (`YYYY-MM-DD`).
- Each bullet starts with a verb (Added, Fixed, Improved, Removed, Updated).
- Reference cmdlet names when relevant: `Get-InforcerAlignmentDetails`.
- Group related changes into a single bullet when they share context.
- Keep bullets concise (one line, max two) — details belong in commit messages.
- Empty sections are omitted (don't include `### Bug Fixes` if there are none).

## Workflow

### 1. Gather changes

Read the git log since the last tag/version:
```bash
git log $(git describe --tags --abbrev=0 2>/dev/null || echo "HEAD~50")..HEAD --oneline
```

If no tags exist, compare against the version in `CHANGELOG.md` and use recent history.

Also check:
- `FINDINGS.md` — for fixes and improvements done in this cycle
- `Tests/Consistency.Tests.ps1` — for new test count vs previous

### 2. Determine version bump

**CRITICAL: Always check the version on `main` branch first** — feature branches may have premature bumps:
```bash
git show main:module/InforcerCommunity.psd1 | grep ModuleVersion
```
The version on `main` is the **source of truth**. Bump from that, not from the current branch's psd1.

Based on the changes gathered:
- Any `feat!:` or `BREAKING CHANGE` → MAJOR
- Any `feat:` → MINOR
- Only `fix:`, `perf:`, `refactor:`, `docs:`, `test:` → PATCH
- When in doubt, ask the user

### 3. Write CHANGELOG.md entry

Insert the new version block at the top (below the header). Follow the format above.
Group bullets by section. Omit empty sections.

### 4. Update module version

Update `ModuleVersion` in `module/InforcerCommunity.psd1` to match.

### 5. Draft GitHub release notes (when asked)

Format for GitHub Releases (pasted into `gh release create` or PR description):

```markdown
## What's New

Brief 1-2 sentence summary of the release theme.

### Features
- ...

### Bug Fixes
- ...

### Performance
- ...

### Other Changes
- ...

**Full Changelog**: https://github.com/royklo/InforcerCommunity/compare/v{previous}...v{new}
```

The GitHub release notes are more conversational than CHANGELOG.md — explain *why* changes
matter, not just *what* changed. Highlight the most impactful changes first.

### 6. Commit message for the release

```
chore: release v{X.Y.Z}
```

This commit should only contain `CHANGELOG.md` and `InforcerCommunity.psd1` changes.

## Key Files

| File | Purpose |
|------|---------|
| `CHANGELOG.md` | Human-readable changelog (this skill writes it) |
| `module/InforcerCommunity.psd1` | `ModuleVersion` field — must match release |
| `.claude/FINDINGS.md` | Source of truth for what was fixed/improved |
| `Tests/Consistency.Tests.ps1` | Test count for release notes |

## Anti-Patterns

- Don't include internal refactors that don't affect users unless they're significant.
- Don't list every file changed — summarize by impact.
- Don't duplicate the git log — synthesize and group.
- Don't bump MAJOR for non-breaking changes just because there are many of them.
- Don't forget to update `ModuleVersion` in the `.psd1` — the pipeline reads it.
