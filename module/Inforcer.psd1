@{
    RootModule        = 'Inforcer.psm1'
    ModuleVersion     = '0.0.2'
    GUID              = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author            = 'Roy Klooster'
    Description       = 'Community PowerShell module for the Inforcer API. Created by Roy Klooster.'
    PowerShellVersion = '7.0'
    ScriptsToProcess  = @()
    TypesToProcess    = @('Inforcer.Types.ps1xml')
    FormatsToProcess  = @('Inforcer.Format.ps1xml')
    FunctionsToExport = @(
        'Connect-Inforcer'
        'Disconnect-Inforcer'
        'Test-InforcerConnection'
        'Get-InforcerTenant'
        'Get-InforcerBaseline'
        'Get-InforcerTenantPolicies'
        'Get-InforcerAlignmentScore'
        'Get-InforcerAuditEvent'
    )
    CmdletsToExport   = @()
    VariablesToExport  = @()
    AliasesToExport   = @()
    PrivateData       = @{
        PSData = @{
            ProjectUri = 'https://github.com/royklo/Inforcer-Powershell-Module'
        }
    }
}
