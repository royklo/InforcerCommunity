---
name: inforcer-docs-maintenance
description: How to maintain repository documentation for the Inforcer PowerShell module. Use when updating README, CONTRIBUTING, cmdlet reference, or any root-level docs.
---

# Inforcer Documentation Maintenance

Use this skill when adding or changing **repository documentation**: README, CONTRIBUTING, cmdlet reference, or other markdown that explains how the module works or how to contribute.

## When to use

- Adding or changing a Public cmdlet or its parameters (update CMDLET-REFERENCE.md)
- Changing installation or quick-start steps (update README)
- Changing contribution workflow, issue templates, or PR process (update CONTRIBUTING)
- Adding or removing badges, links, or version references (update README and any doc that references them)
- Keeping fake/example output in docs in sync with actual cmdlet output

## Key files

| Document | Path | Purpose |
|----------|------|---------|
| Main README | `README.md` (repo root) | Project overview, install, quick start, cmdlet table, badges, links |
| Contributing | `CONTRIBUTING.md` (repo root) | Fork-and-PR workflow, how to raise bugs/features, code style, testing |
| Cmdlet reference | `docs/CMDLET-REFERENCE.md` | Per-cmdlet synopsis, parameters, examples, and **fake response output** |
| Module README | `module/README.md` | How to load and use the script module (optional; can point to root README) |

## Rules

1. **Every new cmdlet or parameter change** must be reflected in `docs/CMDLET-REFERENCE.md`: add or update the section with synopsis, parameter table, at least one example, and example output (fake but realistic).
2. **Fake responses** must match the **actual output shape**: same property names (PascalCase aliases: ClientTenantId, TenantFriendlyName, etc.), same structure (single object vs array), and same types (string, int, datetime) as the real cmdlet. Do not invent properties the cmdlet does not output.
3. **Links**: The repo uses real URLs pointing to `https://github.com/royklo/Inforcer-Powershell-Module` and `https://www.powershellgallery.com/packages/Inforcer`. Keep links consistent when editing docs.
4. **Badges and version**: If README or other docs show module version or "latest" links, keep them in sync with `module/Inforcer.psd1` ModuleVersion when you bump a release.
5. **CONTRIBUTING** must reference the issue templates (Bug report, Feature request) and the PR template so contributors know where to open issues and what to fill in.

## Workflow when changing a cmdlet

1. Implement the change in `module/Public/*.ps1` (and Private if needed).
2. Update comment-based help in the script (synopsis, description, parameters, examples).
3. Update `docs/CMDLET-REFERENCE.md`: same synopsis/parameters/examples and example output that matches the new behavior.
4. If the change fixes a bug or adds a finding, update FINDINGS.md (see inforcer-unified-guardian skill).

## Example output style (CMDLET-REFERENCE.md)

- Use **realistic but fictional data** (fake tenant names, IDs, dates).
- Prefer **property list or table** format so readers see property names and types.
- For JSON output (e.g. `-OutputType JsonObject`), describe the shape or show a short sample; you do not need to paste a full JSON blob if it is long.

## Related

- **Consistency contract and cmdlet behavior:** [.cursor/skills/inforcer-unified-guardian/SKILL.md](../inforcer-unified-guardian/SKILL.md)
- **Findings and how to test:** [FINDINGS.md](../../FINDINGS.md)
