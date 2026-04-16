---
name: inforcer-docs-maintenance
description: >
  MANDATORY when updating repository documentation for the Inforcer PowerShell module. Use when
  updating README, CONTRIBUTING, CMDLET-REFERENCE.md, badges, version references, or example
  output in docs. Also triggers after any cmdlet or parameter change that needs docs updates.
---

# Inforcer Documentation Maintenance

> **Authority:** This skill handles all documentation changes for InforcerCommunity.
> For code changes that also affect docs, this skill runs **last** in the chain:
> 1. inforcer-unified-guardian (consistency) → 2. inforcer-performance-maintenance (perf) → 3. **this skill** (docs)
>
> For docs-only changes (no code), this skill runs alone.

## Triggers

Activate when the user mentions or the task involves:
- "Update README", "update docs", "documentation"
- "Cmdlet reference", "CMDLET-REFERENCE.md"
- "CONTRIBUTING.md", "contribution workflow"
- "Badge", "version badge"
- "Example output in docs"
- Any cmdlet/parameter change that needs docs updated

## Rules

1. **Every new cmdlet or parameter change** must be reflected in `docs/CMDLET-REFERENCE.md`: synopsis, parameter table, at least one example, and example output (fake but realistic).
2. **Fake responses** must match the **actual output shape**: same property names (PascalCase aliases), same structure, same types as the real cmdlet. Do not invent properties the cmdlet does not output.
3. **Links** use real URLs: `https://github.com/royklo/InforcerCommunity` and `https://www.powershellgallery.com/packages/InforcerCommunity`. Keep consistent.
4. **Badges and version**: Keep in sync with `module/InforcerCommunity.psd1` ModuleVersion.
5. **CONTRIBUTING** must reference issue templates (Bug report, Feature request) and PR template.
6. **Every `-OutputType JsonObject` must have an example** in both the cmdlet help (.ps1) and CMDLET-REFERENCE.md.
7. **All doc files must stay in sync.** When adding a cmdlet, update ALL of: CMDLET-REFERENCE.md, API-REFERENCE.md (endpoints + schemas + TOC), README.md (cmdlet table), CHANGELOG.md ([Unreleased] section), api-schema-snapshot.json (new endpoint schemas). Missing any one creates drift.
8. **API-REFERENCE.md TOC must include new sections.** Both the endpoint section and the schema section need TOC entries when new endpoints/schemas are added.
9. **FINDINGS.md must be updated** when fixing audit findings — change status from `(Pending)` to a description of what was done.

## Workflow

1. Implement the change in `module/Public/*.ps1` (and Private if needed).
2. Update comment-based help in the script (synopsis, description, parameters, examples — including `-OutputType JsonObject` example).
3. Update ALL doc files (checklist below).
4. If the change fixes a bug or adds a finding, update FINDINGS.md (see inforcer-unified-guardian skill).

### New Cmdlet Checklist

When adding a new cmdlet, update ALL of these files:

- [ ] `module/Public/[Cmdlet].ps1` — comment-based help with synopsis, description, all parameters, examples (including `-OutputType JsonObject`), outputs, links
- [ ] `module/InforcerCommunity.psd1` — add to `FunctionsToExport`
- [ ] `module/InforcerCommunity.Format.ps1xml` — add ListControl view for each new PSTypeName
- [ ] `module/Private/Add-InforcerPropertyAliases.ps1` — add ObjectType cases and update ValidateSet
- [ ] `docs/CMDLET-REFERENCE.md` — synopsis, parameter table, examples, example output
- [ ] `docs/API-REFERENCE.md` — endpoint section + schema section + both TOC entries
- [ ] `docs/api-schema-snapshot.json` — add endpoint schema
- [ ] `README.md` — add to cmdlet table
- [ ] `CHANGELOG.md` — add to `[Unreleased]` section
- [ ] `Tests/Consistency.Tests.ps1` — update expectedCount, expectedNames, expectedParameters, add no-silent-failure test, parameter binding tests, property alias tests
- [ ] `.claude/skills/inforcer-unified-guardian/SKILL.md` — update cmdlet list, API shapes, PSTypeNames table
- [ ] `.claude/skills/inforcer-unified-guardian/references/contract-details.md` — update module structure, property aliases, Graph endpoints if changed

## Example Output Style (CMDLET-REFERENCE.md)

- Use **realistic but fictional data** (fake tenant names, IDs, dates).
- Prefer **property list** format (all cmdlets default to ListControl). Example output should match the Format.ps1xml ListControl view — show only the properties defined in the view, not all raw API properties. Mention `| Select-Object *` for full access.
- For JSON output, describe the shape or show a short sample; no full JSON blobs.

## Key Files

| Document | Path | Purpose |
|----------|------|---------|
| Main README | `README.md` | Overview, install, quick start, cmdlet table, badges |
| Contributing | `CONTRIBUTING.md` | Fork-and-PR workflow, code style, testing |
| Cmdlet reference | `docs/CMDLET-REFERENCE.md` | Per-cmdlet synopsis, parameters, examples, fake output |
| Module README | `module/README.md` | How to load and use the script module |
