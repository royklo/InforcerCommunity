@{
    RootModule        = 'InforcerCommunity.psm1'
    ModuleVersion     = '1.2.0'
    GUID              = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author            = 'Roy Klooster'
    Description       = 'Community PowerShell module for the Inforcer API. Created by Roy Klooster. Not owned or officially maintained by Inforcer.'
    PowerShellVersion = '7.0'
    ScriptsToProcess  = @()
    TypesToProcess    = @('InforcerCommunity.Types.ps1xml')
    FormatsToProcess  = @('InforcerCommunity.Format.ps1xml')
    FunctionsToExport = @(
        'Connect-Inforcer'
        'Disconnect-Inforcer'
        'Test-InforcerConnection'
        'Get-InforcerTenant'
        'Get-InforcerBaseline'
        'Get-InforcerTenantPolicies'
        'Get-InforcerAlignmentDetails'
        'Get-InforcerAuditEvent'
        'Get-InforcerSupportedEventType'
        'Get-InforcerUser'
        'New-InforcerUser'
        'Set-InforcerUser'
        'Get-InforcerGroup'
        'Set-InforcerGroup'
        'Get-InforcerThreat'
        'Get-InforcerThreatIndicator'
        'Get-InforcerRole'
        'Get-InforcerSecureScore'
        'Export-InforcerTenantDocumentation'
        'Compare-InforcerEnvironments'
        'Get-InforcerAssessment'
        'Invoke-InforcerAssessment'
        'Get-InforcerReportType'
        'Invoke-InforcerReport'
        'Get-InforcerReportRun'
        'Save-InforcerReportOutput'
    )
    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            ProjectUri   = 'https://github.com/royklo/InforcerCommunity'
            LicenseUri   = 'https://github.com/royklo/InforcerCommunity/blob/main/LICENSE'
            ReleaseNotes = 'v1.2.0: manage users, groups and mailboxes with New-InforcerUser, Set-InforcerUser and Set-InforcerGroup; read sign-in methods, mailboxes and message traces with Get-InforcerUser, licences with Get-InforcerTenant -IncludeSubscriptions, and threats with Get-InforcerThreat and Get-InforcerThreatIndicator (API client only). See CHANGELOG.md.'
            Tags         = @('Inforcer', 'API', 'Community')
        }
    }
}
