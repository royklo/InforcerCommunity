@{
    RootModule        = 'InforcerCommunity.psm1'
    ModuleVersion     = '0.7.0'
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
        'Get-InforcerGroup'
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
            ReleaseNotes = 'v0.6.0: New cmdlet Get-InforcerSecureScore wraps GET /beta/tenants/{tenantId}/secureScores — current + 90-day daily score history, per-category scores, and actionable control profiles with remediation. Get-InforcerAuditEvent gains a -User parameter for server-side filtering and now exposes the raw event id as PascalCase Id. -EventType tab completion is now dynamic — reads $global:InforcerCachedEventTypes refreshed by Get-InforcerSupportedEventType, so new server-side event types show up automatically without a module release. Required API scope(s) documentation added to Get-Help output for 13 cmdlets that were missing it. Stale PolicyDiffFormatted mention removed from CMDLET-REFERENCE. See CHANGELOG.md for full details.'
            Tags         = @('Inforcer', 'API', 'Community')
        }
    }
}
