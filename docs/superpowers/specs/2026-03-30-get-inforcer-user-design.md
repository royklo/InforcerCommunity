# Design: Get-InforcerUser

## Summary

Add a `Get-InforcerUser` cmdlet that merges two new Inforcer API beta endpoints into a single PowerShell cmdlet:

- `GET /beta/tenants/{tenantId}/users` — list/search users (returns `UserSummary`)
- `GET /beta/tenants/{tenantId}/users/{userId}` — get user detail (returns full `User`)

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Merge into one cmdlet | Yes | Matches existing module pattern (Get-InforcerTenant) |
| Detail endpoint when UserId provided | Yes | Detail endpoint returns significantly richer data (groups, roles, devices, risk, on-prem) |
| Server-side Search parameter | Yes | API supports it natively, minimal cost to expose |
| Auto-pagination | Yes | Matches Get-InforcerAuditEvent precedent, PowerShell-idiomatic |
| Separate PSTypeNames | UserSummary + User | Enables different Format.ps1xml views per shape |
| Property aliases | Top-level only | Nested objects (groups, roles, devices) are already well-structured |
| Approach | ParameterSets | Prevents invalid combinations at binding level |

## Cmdlet Signature

```powershell
Get-InforcerUser
    [-Format <String>]           # ValidateSet: 'Raw'. Default: 'Raw'
    -TenantId <Object>           # Required. ValueFromPipeline, ValueFromPipelineByPropertyName. Resolved via Resolve-InforcerTenantId
    [-Search <String>]           # List ParameterSet only. Server-side filter passed as ?search=
    [-MaxResults <Int32>]        # List ParameterSet only. Caps auto-pagination
    [-UserId <String>]           # ById ParameterSet only. Mandatory. User GUID
    [-OutputType <String>]       # ValidateSet: 'PowerShellObject','JsonObject'. Default: 'PowerShellObject'
```

### Parameter Sets

- **List** (default): Format, TenantId, Search, MaxResults, OutputType
- **ById**: Format, TenantId, UserId, OutputType

### Parameter Order (contract)

Format → TenantId → Search → MaxResults → UserId → OutputType

## API Calls

### List Parameter Set

```
GET /beta/tenants/{tenantId}/users
GET /beta/tenants/{tenantId}/users?search={search}
GET /beta/tenants/{tenantId}/users?continuationToken={token}
GET /beta/tenants/{tenantId}/users?search={search}&continuationToken={token}
```

- Auto-paginate: loop passing `continuationToken` as query parameter until null or MaxResults reached
- Use `[System.Collections.ArrayList]` with `[void].Add()` for accumulation
- Call `Invoke-InforcerApiRequest` with `-PreserveStructure` to access `continuationToken` and `data` separately

### ById Parameter Set

```
GET /beta/tenants/{tenantId}/users/{userId}
```

- Single call, no pagination
- Standard response unwrapping (`.data`)

## Output Types

| Shape | PSTypeName | Source | When |
|-------|-----------|--------|------|
| Summary | `InforcerCommunity.UserSummary` | List endpoint | No UserId provided |
| Detail | `InforcerCommunity.User` | Detail endpoint | UserId provided |

## Property Aliases

### UserSummary (list endpoint)

| Alias (PascalCase) | Source (camelCase) |
|--------------------|--------------------|
| Id | id |
| DisplayName | displayName |
| UserPrincipalName | userPrincipalName |
| UserType | userType |
| JobTitle | jobTitle |
| Department | department |
| Groups | groups |
| Roles | roles |
| AssignedLicenses | assignedLicenses |
| IsGlobalAdmin | isGlobalAdmin |
| IsAccountEnabled | isAccountEnabled |
| IsMfaRegistered | isMfaRegistered |
| IsMfaCapable | isMfaCapable |

### User (detail endpoint)

All UserSummary aliases plus:

| Alias (PascalCase) | Source (camelCase) |
|--------------------|--------------------|
| GivenName | givenName |
| Surname | surname |
| Mail | mail |
| MobilePhone | mobilePhone |
| BusinessPhones | businessPhones |
| OfficeLocation | officeLocation |
| StreetAddress | streetAddress |
| City | city |
| State | state |
| PostalCode | postalCode |
| Country | country |
| PreferredLanguage | preferredLanguage |
| AccountEnabled | accountEnabled |
| UsageLocation | usageLocation |
| CreatedDateTime | createdDateTime |
| LastPasswordChangeDateTime | lastPasswordChangeDateTime |
| LastSignInDateTime | lastSignInDateTime |
| CompanyName | companyName |
| EmployeeId | employeeId |
| EmployeeType | employeeType |
| EmployeeHireDate | employeeHireDate |
| MailNickname | mailNickname |
| PreferredDataLocation | preferredDataLocation |
| OnPremisesSyncEnabled | onPremisesSyncEnabled |
| OtherMails | otherMails |
| ProxyAddresses | proxyAddresses |
| CreationType | creationType |
| PasswordPolicies | passwordPolicies |
| SignInSessionsValidFromDateTime | signInSessionsValidFromDateTime |
| ImAddresses | imAddresses |
| LegalAgeGroupClassification | legalAgeGroupClassification |
| OnPremisesLastSyncDateTime | onPremisesLastSyncDateTime |
| OnPremisesDistinguishedName | onPremisesDistinguishedName |
| OnPremisesDomainName | onPremisesDomainName |
| OnPremisesImmutableId | onPremisesImmutableId |
| OnPremisesSecurityIdentifier | onPremisesSecurityIdentifier |
| OnPremisesSamAccountName | onPremisesSamAccountName |
| OnPremisesUserPrincipalName | onPremisesUserPrincipalName |
| Manager | manager |
| Devices | devices |
| Roles | roles |
| AppRoleAssignments | appRoleAssignments |
| IsCloudOnly | isCloudOnly |
| IsHybrid | isHybrid |
| IsAllDevicesCompliant | isAllDevicesCompliant |
| RiskState | riskState |
| RiskDetail | riskDetail |
| RiskLevel | riskLevel |

Nested objects (groups, roles, devices, assignedLicenses, appRoleAssignments, manager) are left as-is — no flattening or transformation.

## Format.ps1xml Views

### InforcerCommunity.UserSummary — ListControl

Properties displayed: DisplayName, UserPrincipalName, UserType, Department, IsAccountEnabled, IsGlobalAdmin, IsMfaRegistered

### InforcerCommunity.User — ListControl

Properties displayed: DisplayName, UserPrincipalName, UserType, Department, Mail, AccountEnabled, IsGlobalAdmin, IsCloudOnly, IsMfaRegistered, RiskLevel

Note: ListControl per module convention (no TableControl).

## Error Handling

- `Test-InforcerSession` at top — `Write-Error` + `return` if not connected (non-terminating)
- API errors surfaced via existing `Invoke-InforcerApiRequest` error handling
- 404 on ById: non-terminating error ("User '{userId}' not found in tenant '{tenantId}'")

## Usage Examples

```powershell
# List all users for a tenant
Get-InforcerUser -TenantId 139

# List users with search filter
Get-InforcerUser -TenantId 139 -Search "Adele"

# List users, cap at 50 results
Get-InforcerUser -TenantId 139 -MaxResults 50

# Get full detail for a specific user
Get-InforcerUser -TenantId 139 -UserId "8e61ce11-a45b-42a6-8ca4-1d881781566d"

# Pipeline from Get-InforcerTenant
Get-InforcerTenant -TenantId 139 | Get-InforcerUser

# Get specific user as JSON
Get-InforcerUser -TenantId 139 -UserId "8e61ce11-a45b-42a6-8ca4-1d881781566d" -OutputType JsonObject
```

## Files Touched

| File | Change |
|------|--------|
| `module/Public/Get-InforcerUser.ps1` | New cmdlet |
| `module/Private/Add-InforcerPropertyAliases.ps1` | Add `User` and `UserSummary` object types |
| `module/InforcerCommunity.psd1` | Add `Get-InforcerUser` to FunctionsToExport |
| `module/InforcerCommunity.Format.ps1xml` | ListControl views for both types |
| `Tests/Consistency.Tests.ps1` | Add Get-InforcerUser to test coverage |

## Consistency Contract Compliance

- Parameter order: Format → TenantId → ... → OutputType
- JSON Depth 100 in all ConvertTo-Json calls
- PascalCase aliases via Add-InforcerPropertyAliases (no property removal/renaming)
- PSTypeName set on all output objects
- FunctionsToExport updated in psd1
- Comment-based help with Synopsis and Examples
- Session-based auth with Test-InforcerSession check
- Non-terminating errors for auth/API, terminating for input validation
- ArrayList with [void].Add() for pagination accumulation
