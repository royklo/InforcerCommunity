function Test-InforcerInteractiveHost {
    <#
    .SYNOPSIS
        True when the caller is a human at a prompt, false on a CI runner or a non-interactive host.

    .DESCRIPTION
        Used as the computed default for -Show on the cmdlets that render HTML. A human who asked
        for a report by passing -OutputPath almost always wants to look at it, so opening it is a
        continuation of an explicit request rather than a surprise. A build agent never does, and
        on a headless box Start-Process either no-ops, errors, or blocks.

        Deliberately conservative: it answers "is this definitely NOT a build agent", not "is there
        definitely a browser". [Environment]::UserInteractive is true for most non-Windows pwsh
        sessions including scripted ones, so the CI variables carry most of the weight. Callers who
        need certainty either way pass -Show or -Show:$false explicitly, which always wins.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    # Set by GitHub Actions, GitLab CI, CircleCI, Travis, AppVeyor and most others; TF_BUILD is
    # Azure Pipelines, which does not set CI.
    foreach ($v in 'CI', 'TF_BUILD', 'GITHUB_ACTIONS', 'GITLAB_CI', 'JENKINS_URL', 'TEAMCITY_VERSION', 'BUILDKITE') {
        if (-not [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($v))) {
            Write-Verbose "Test-InforcerInteractiveHost: '$v' is set — treating as non-interactive."
            return $false
        }
    }

    return [Environment]::UserInteractive
}
