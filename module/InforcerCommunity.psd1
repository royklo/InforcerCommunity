@{
    RootModule        = 'InforcerCommunity.psm1'
    ModuleVersion     = '0.5.0'
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
            ReleaseNotes = 'v0.5.0: New Reports API cmdlets (Get-InforcerReportType, Invoke-InforcerReport, Get-InforcerReportRun, Save-InforcerReportOutput) wrapping /beta/reports/*. Sync+save default, -NoWait/-NoSave modes, -Open switch to launch saved files via OS default handler with extension allowlist, pipeline-bindable catalog objects, three-phase Write-Progress, and proper Content-Disposition parsing. Connect-Inforcer accepts any valid API key regardless of scope (envelope-shape detection) and best-effort primes the Reports catalog cache for instant TAB completion. Invoke-InforcerApiRequest now handles all three error envelope shapes (app-layer, APIM gateway, RFC 9110 ProblemDetails), captures x-correlation-id, and surfaces structured errors[] field details so validation failures tell you which field actually broke. Dynamic -AssessmentId completer with three-state UX (not connected / scope denied / connected) caching denial on 401 and 403. Breaking: Invoke-InforcerReport ConfirmImpact bumped from Low to Medium. See CHANGELOG.md for full details.'
            Tags         = @('Inforcer', 'API', 'Community')
        }
    }
}
