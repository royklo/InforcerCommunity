function Get-InforcerReportTypeStaticKeys {
    <#
    .SYNOPSIS
        Returns the static fallback list of Reports API type keys used by argument completers
        before the live catalog cache ($script:InforcerReportTypeCache) is primed.
    .DESCRIPTION
        Argument completers on -ReportType / -Key prefer the live catalog when populated, but
        until the first /beta/reports/types call this static list is what shows up at TAB.
        Centralised here so Get-InforcerReportType and Invoke-InforcerReport stay in lockstep —
        empirically matched to the production catalog observed against api.inforcer.com.
    .OUTPUTS
        System.String[]
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseSingularNouns', '',
        Justification = 'Returns a collection of keys; plural noun is intentional.')]
    [CmdletBinding()]
    [OutputType([string[]])]
    param()

    ,$script:InforcerReportTypeStaticKeys
}

# Module-scoped canonical list — both completers read this directly so a single edit keeps
# Get-InforcerReportType and Invoke-InforcerReport completion identical.
$script:InforcerReportTypeStaticKeys = @(
    'ActiveUserCount'
    'ActiveUsers'
    'Assessment'
    'CopilotAdoption'
    'CredentialUserRegistrationDetails'
    'EncryptionDisabledDevices'
    'EncryptionEnabledDevices'
    'GetDetectedRisks'
    'GetDetectedServicePrincipalRisks'
    'GetOneDriveUsageAccountCounts'
    'GetOneDriveUsageStorage'
    'GetRiskyServicePrincipals'
    'GetRiskyUsers'
    'GetSharePointSiteUsageDetail'
    'GetSharePointSiteUsageStorage'
    'GetTenantMFAReport'
    'GlobalAdmins'
    'NonCompliantDevices'
    'SecureScores'
    'SecureScoresAverageComparativeScores'
    'SecureScoresControlScores'
    'ShadowAiDetection'
    'SubscribedSkus'
    'TenantAuditReport'
    'TenantMfaReport'
)
