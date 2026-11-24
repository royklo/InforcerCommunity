@{
    RootModule        = 'InforcerCommunity.psm1'
    ModuleVersion     = '1.1.0'
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
            ReleaseNotes = 'v1.1.0: Export-InforcerTenantDocumentation -Baseline takes several baselines and reads the tenant once (22 baselines: 34 min -> 48 s). Documents now show settings nested more than two levels deep, list items with their fields, Entra settings stored as a dotted @odata.type, and authentication strength combinations intact. See CHANGELOG.md.''s policies (same-named policies no longer leak in); a -Baseline that does not resolve or holds no policies is an error (BaselineFilterFailed) instead of exporting the whole tenant; name/value settings keep their values; -FetchGraphData reuses an app-only Graph session instead of opening a browser. See CHANGELOG.md.'
            Tags         = @('Inforcer', 'API', 'Community')
        }
    }
}
