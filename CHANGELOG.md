# Changelog

All notable changes to this project will be documented in this file.

The format follows [Conventional Commits](https://www.conventionalcommits.org/) and this project adheres to [Semantic Versioning](https://semver.org/). Release notes for each version are also generated from git history by the automation pipeline using the same conventional types (feat, fix, docs, refactor, test, etc.).

## [0.0.3] - 2026-03-06

### Features

- PowerShell Gallery–ready metadata.
- README Quick start: example for showing policy changes per tenant.


### Documentation

- README, CONTRIBUTING, and LICENSE wording aligned; CONTRIBUTING.

### Refactoring

- Clearer error messages when API returns forbidden or no data; safer examples in docs.

### Tests

- Help coverage check (Synopsis and Example per cmdlet); parameter binding tests.

## [0.0.2] - 2026-03-06

### Improvements

- Various documentation updates, and test improvements.
- Consistency and no-silent-failure behaviour for all Get-* cmdlets.
- Clearer API error handling and alignment score filtering.

## [0.0.1] - 2026-03-05

### Features

- Initial release of the InforcerCommunity PowerShell module.
- Cmdlets: Connect-Inforcer, Disconnect-Inforcer, Test-InforcerConnection, Get-InforcerTenant, Get-InforcerBaseline, Get-InforcerTenantPolicies, Get-InforcerAlignmentScore, Get-InforcerAuditEvent.
- Tab completion for audit event types (-EventType on Get-InforcerAuditEvent).
- Region support (uk, eu, us, anz) and custom BaseUrl.
- Output types: PowerShellObject and JsonObject (depth 100).

