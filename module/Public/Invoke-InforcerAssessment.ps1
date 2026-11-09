<#
.SYNOPSIS
    Runs an assessment against one or more tenants via the Inforcer API.

    Required API scope(s): Tenants.Read + Assessments.Read + Assessments.Run (API key);
    Tenants (read) + Tenant Assessment (run) permissions (API client, unconfirmed).
.DESCRIPTION
    Triggers an assessment run and returns detailed results including per-check scores,
    passes, violations, warnings, and framework metadata.
    Each check's Status is Pass, Fail, InsufficientPermissions or Error. The last two mean the
    API could not assess the check; they are reported but left out of the compliance score.
    Supports single-tenant, multi-tenant (all tenants), and subset modes.
    Use -MultiTenant to run against all tenants, or pass multiple values to -TenantId.
    Works with both login types. With an API key (legacy API) tenants are identified by numeric
    Client Tenant ID, GUID or name; with a client ID and secret (v1 API) by Microsoft tenant ID
    (GUID) or name, and the TenantId on the output is the Microsoft tenant ID. v1 runs return
    when the assessment completes, exactly like the legacy runs.
    When -OutputPath is specified with multi-tenant, generates an HTML matrix report.
    With client credentials a throttled run (429) is retried after Retry-After and a 401 renews the
    token once; with an API key neither is retried. A run that answers with a redirect fails.
.PARAMETER TenantId
    Tenant(s) to run the assessment against. Accepts numeric Client Tenant ID (API key only),
    Microsoft tenant GUID, or friendly name. Aliases: -ClientTenantId, -MsTenantId.
    Pass multiple values for subset multi-tenant mode.
    Optional when -MultiTenant is used (defaults to all tenants).
    Piped tenants are collected into one run; every check then carries TenantId.
.PARAMETER AssessmentId
    The assessment to run. Accepts an assessment ID string or a friendly assessment name.
.PARAMETER MultiTenant
    Switch. Runs the assessment against all tenants (or subset if -TenantId also specified).
    Requires -OutputPath with HTML extension for the matrix report.
.PARAMETER OutputPath
    Optional. File path (not a directory) to export results; the extension picks the format, and
    any other extension fails with UnsupportedFormat.
    Single tenant: HTML (.html or .htm) report or CSV (.csv).
    Multi-tenant: HTML (.html) matrix report or CSV (.csv) with tenant column.
    CSV values that start with =, +, -, @, a tab or a carriage return get a leading ' so Excel
    shows them as text instead of running them as formulas.
    Returns System.IO.FileInfo when specified.
.PARAMETER OutputType
    PowerShellObject (default) or JsonObject. JSON uses Depth 100.
.EXAMPLE
    Invoke-InforcerAssessment -TenantId 'Contoso' -AssessmentId "Copilot Readiness"
    Runs the Copilot Readiness assessment against the tenant Contoso.
.EXAMPLE
    Invoke-InforcerAssessment -TenantId "Contoso" -AssessmentId "Copilot Readiness" -OutputPath ./report.html
    Generates an interactive HTML assessment report.
.EXAMPLE
    Invoke-InforcerAssessment -AssessmentId "Copilot Readiness" -MultiTenant -OutputPath ./matrix.html
    Runs the assessment against all tenants and generates a matrix comparison report.
.EXAMPLE
    Invoke-InforcerAssessment -TenantId "Contoso","Fabrikam","Woodgrove" -AssessmentId "Copilot Readiness" -OutputPath ./matrix.html
    Runs the assessment against specific tenants and generates a matrix report.
.EXAMPLE
    Invoke-InforcerAssessment -TenantId 'Contoso' -AssessmentId "Copilot Readiness" -OutputPath ./report.csv
    Exports assessment results to CSV.
.EXAMPLE
    Invoke-InforcerAssessment -TenantId 'Contoso' -AssessmentId "Copilot Readiness" -OutputType JsonObject
    Returns the assessment results as a JSON string (depth 100) instead of objects.

.OUTPUTS
    PSObject, String, or System.IO.FileInfo
.LINK
    https://github.com/royklo/InforcerCommunity/blob/main/docs/CMDLET-REFERENCE.md#invoke-inforcerassessment
.LINK
    Connect-Inforcer
.LINK
    Get-InforcerAssessment
#>
function Invoke-InforcerAssessment {
[CmdletBinding()]
[OutputType([PSObject], [string], [System.IO.FileInfo])]
param(
    [Parameter(Mandatory = $false, ValueFromPipelineByPropertyName = $true)]
    [Alias('ClientTenantId', 'MsTenantId')]
    [object[]]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$AssessmentId,

    [Parameter(Mandatory = $false)]
    [switch]$MultiTenant,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [ValidateSet('PowerShellObject', 'JsonObject')]
    [string]$OutputType = 'PowerShellObject'
)

begin { $pipedTenantIds = [System.Collections.Generic.List[object]]::new() }
process { if ($null -ne $TenantId) { foreach ($t in @($TenantId)) { $pipedTenantIds.Add($t) } } }
end {
# Piped input that held no tenant (an empty filter result) must not fall through to an all-tenant run.
if ($PSCmdlet.MyInvocation.ExpectingInput -and $pipedTenantIds.Count -eq 0) {
    Write-Verbose 'No tenants were piped in; nothing to assess.'
    return
}
if ($pipedTenantIds.Count -gt 0) { $TenantId = $pipedTenantIds.ToArray() }

if (-not (Test-InforcerSession)) {
    Write-Error -Message 'Not connected yet. Please run Connect-Inforcer first.' -ErrorId 'NotConnected' -Category ConnectionError
    return
}

# Validate: single-tenant requires -TenantId
$isMultiTenant = $MultiTenant.IsPresent -or ($null -ne $TenantId -and @($TenantId).Count -gt 1)
if (-not $isMultiTenant -and ($null -eq $TenantId -or @($TenantId).Count -eq 0)) {
    Write-Error -Message 'TenantId is required for single-tenant mode. Use -MultiTenant to run against all tenants.' -ErrorId 'MissingTenantId' -Category InvalidArgument
    return
}

# Fetch tenant list (needed for name resolution and multi-tenant)
$isV1 = $script:InforcerSession.ApiVersion -eq 'v1'
$tenantIdProperty = if ($isV1) { 'msTenantId' } else { 'clientTenantId' }
$tenantData = @(Get-InforcerTenantList -Refresh)

# Resolve assessment
$assessmentData = $null
try {
    $assessmentData = @(Invoke-InforcerApiRequest -Endpoint '/assessments' -Method GET -OutputType PowerShellObject -ObjectType Assessment)
    $resolvedAssessmentId = Resolve-InforcerAssessmentId -AssessmentId $AssessmentId -AssessmentData $assessmentData
} catch {
    Write-Error -Message $_.Exception.Message -ErrorId 'InvalidAssessmentId' -Category InvalidArgument
    return
}

# Resolve assessment friendly name
$assessmentDisplayName = $AssessmentId
foreach ($a in $assessmentData) {
    if ($a -is [PSObject]) {
        $idProp = $a.PSObject.Properties['id']
        if ($idProp -and $idProp.Value -eq $resolvedAssessmentId) {
            $np = $a.PSObject.Properties['name']
            if ($np -and -not [string]::IsNullOrWhiteSpace($np.Value)) { $assessmentDisplayName = $np.Value }
            break
        }
    }
}

# Helper: resolve tenant friendly name from tenant data (id -> name, first match wins)
$tenantNames = @{}
foreach ($t in $tenantData) {
    if ($t -isnot [PSObject]) { continue }
    $cidProp = $t.PSObject.Properties[$tenantIdProperty]
    if (-not $cidProp -or $null -eq $cidProp.Value -or $tenantNames.ContainsKey("$($cidProp.Value)")) { continue }
    $fn = $t.PSObject.Properties['tenantFriendlyName']
    $dn = $t.PSObject.Properties['tenantDnsName']
    $tenantNames["$($cidProp.Value)"] = if ($fn -and -not [string]::IsNullOrWhiteSpace($fn.Value) -and $fn.Value -ne 'Tenant') { $fn.Value }
        elseif ($dn -and -not [string]::IsNullOrWhiteSpace($dn.Value)) { $dn.Value }
        else { "$($cidProp.Value)" }
}
$resolveTenantName = {
    param($cid)
    if ($tenantNames.ContainsKey("$cid")) { return $tenantNames["$cid"] }
    return "$cid"
}

# CSV cells that start with = + - @ tab or CR are formulas in Excel: prefix them with a quote.
$csvSafe = {
    param($row)
    foreach ($prop in $row.PSObject.Properties) {
        $v = $prop.Value
        if ($v -is [string] -and $v.Length -gt 0 -and "=+-@`t`r".IndexOf($v[0]) -ge 0) { $prop.Value = "'" + $v }
    }
    $row
}

# Helper: process raw API results into enriched check objects
$placeholderNames = @('[Multiple Objects Evaluated]', '[unknown id]', '[unknown name]')
$processResults = {
    param([array]$results)
    $checks = [System.Collections.Generic.List[object]]::new()
    foreach ($r in $results) {
        if (-not ($r -is [PSObject])) { continue }
        $fp = $r.PSObject.Properties['findings']
        $isCompliant = $false; $findingsMessage = ''; $apiStatus = $null
        if ($fp -and $fp.Value -is [PSObject]) {
            $cp = $fp.Value.PSObject.Properties['compliant']
            if ($cp) { $isCompliant = $cp.Value -eq $true }
            $mp = $fp.Value.PSObject.Properties['message']
            if ($mp) { $findingsMessage = $mp.Value }
            $sp = $fp.Value.PSObject.Properties['status']
            if ($sp) { $apiStatus = $sp.Value }
        }
        # The API sends compliant=false for checks it could not assess; status tells them apart
        $statusText = switch ($apiStatus) {
            'pass' { 'Pass' }
            'fail' { 'Fail' }
            'insufficientPermissions' { 'InsufficientPermissions' }
            'error' { 'Error' }
            default { if ($isCompliant) { 'Pass' } else { 'Fail' } }
        }

        $allPasses = [System.Collections.Generic.List[string]]::new()
        $allViolations = [System.Collections.Generic.List[string]]::new()
        $allWarnings = [System.Collections.Generic.List[string]]::new()
        $objectsEvaluated = 0; $scoresArray = @()
        if ($fp -and $fp.Value -is [PSObject]) {
            $scoresProp = $fp.Value.PSObject.Properties['scores']
            if ($scoresProp -and $scoresProp.Value -is [array]) {
                $objectsEvaluated = $scoresProp.Value.Count
                $scoresArray = $scoresProp.Value
                foreach ($s in $scoresProp.Value) {
                    if (-not ($s -is [PSObject])) { continue }
                    $objName = ''
                    $onp = $s.PSObject.Properties['objectName']
                    if ($onp -and $onp.Value -and $onp.Value -notin $placeholderNames) { $objName = $onp.Value }
                    $prefix = if ($objName) { "$objName — " } else { '' }
                    $pp = $s.PSObject.Properties['passes']
                    if ($pp -and $pp.Value -is [array]) { foreach ($p in $pp.Value) { if ($p) { [void]$allPasses.Add("${prefix}$p") } } }
                    $vp = $s.PSObject.Properties['violations']
                    if ($vp -and $vp.Value -is [array]) { foreach ($v in $vp.Value) { if ($v) { [void]$allViolations.Add("${prefix}$v") } } }
                    $wp = $s.PSObject.Properties['warnings']
                    if ($wp -and $wp.Value -is [array]) { foreach ($w in $wp.Value) { if ($w) { [void]$allWarnings.Add("${prefix}$w") } } }
                }
            }
        }
        $r | Add-Member -NotePropertyName 'Status' -NotePropertyValue $statusText -Force
        $r | Add-Member -NotePropertyName 'ObjectsEvaluated' -NotePropertyValue $objectsEvaluated -Force
        $r | Add-Member -NotePropertyName 'FindingsMessage' -NotePropertyValue $findingsMessage -Force
        $r | Add-Member -NotePropertyName 'Scores' -NotePropertyValue $scoresArray -Force
        $r | Add-Member -NotePropertyName 'Violations' -NotePropertyValue @($allViolations) -Force
        $r | Add-Member -NotePropertyName 'Warnings' -NotePropertyValue @($allWarnings) -Force
        $r | Add-Member -NotePropertyName 'Passes' -NotePropertyValue @($allPasses) -Force
        $r.PSObject.TypeNames.Insert(0, 'InforcerCommunity.AssessmentCheck')
        [void]$checks.Add($r)
    }
    return ,$checks
}

# Helper: counts and score; checks that were not assessed stay out of the score.
# v1 sends inforcer's own score (summary.score, the portal's number); beta has none, so it is computed.
$summarize = {
    param($checks, $response)
    $passed = 0; $failed = 0
    foreach ($c in $checks) { if ($c.Status -eq 'Pass') { $passed++ } elseif ($c.Status -eq 'Fail') { $failed++ } }
    $apiSummary = if ($response -is [PSObject]) { $response.PSObject.Properties['summary'].Value }
    $apiScore = if ($apiSummary -is [PSObject]) { $apiSummary.PSObject.Properties['score'].Value }
    # Only a real 0-100 number is trusted; it lands in HTML reports. Anything else falls back to the computed score.
    $useApi = $apiScore -is [ValueType] -and $apiScore -isnot [bool] -and [double]$apiScore -ge 0 -and [double]$apiScore -le 100
    @{
        Score       = if ($useApi) { [double]$apiScore } elseif ($passed + $failed -gt 0) { [math]::Round(($passed / ($passed + $failed)) * 100, 1) } else { 0 }
        Passed      = $passed
        Failed      = $failed
        NotAssessed = $checks.Count - $passed - $failed
        TotalChecks = $checks.Count
    }
}

# ── MULTI-TENANT MODE ──
if ($isMultiTenant) {
    # Build list of tenants to run against
    $tenantsToRun = [System.Collections.Generic.List[object]]::new()

    if ($null -ne $TenantId -and @($TenantId).Count -gt 0) {
        # Resolve each specified tenant
        foreach ($tid in @($TenantId)) {
            try {
                $cid = Resolve-InforcerTenantId -TenantId $tid -TenantData $tenantData
                $tname = & $resolveTenantName $cid
                [void]$tenantsToRun.Add(@{ Id = $cid; Name = $tname })
            } catch {
                Write-Warning "Skipping tenant '$tid': $($_.Exception.Message)"
            }
        }
    } else {
        # All tenants
        foreach ($t in $tenantData) {
            if ($t -is [PSObject]) {
                $cidProp = $t.PSObject.Properties[$tenantIdProperty]
                if ($cidProp -and $null -ne $cidProp.Value) {
                    $cid = if ($isV1) { "$($cidProp.Value)" } else { [int]$cidProp.Value }
                    $tname = & $resolveTenantName $cid
                    [void]$tenantsToRun.Add(@{ Id = $cid; Name = $tname })
                }
            }
        }
    }

    if ($tenantsToRun.Count -eq 0) {
        Write-Error -Message 'No tenants found to run assessment against.' -ErrorId 'NoTenants' -Category ObjectNotFound
        return
    }

    # Format elapsed time as human-readable
    $fmtTime = {
        param([double]$totalSeconds)
        if ($totalSeconds -ge 60) {
            $mins = [math]::Floor($totalSeconds / 60)
            $secs = [math]::Round($totalSeconds % 60)
            return "${mins}m ${secs}s"
        }
        return "$([math]::Round($totalSeconds, 1))s"
    }

    Write-Host ""
    Write-Host "Multi-tenant assessment: '$assessmentDisplayName' across $($tenantsToRun.Count) tenant(s)" -ForegroundColor Cyan
    Write-Host ""

    # Run assessment for each tenant
    $totalStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $allTenantResults = [System.Collections.Generic.List[object]]::new()
    $tenantIndex = 0
    foreach ($tenant in $tenantsToRun) {
        $tenantIndex++
        Write-Host "[$tenantIndex/$($tenantsToRun.Count)] " -NoNewline
        $response = Invoke-InforcerAssessmentRun `
            -TenantId $tenant.Id `
            -ResolvedAssessmentId $resolvedAssessmentId `
            -TenantDisplayName $tenant.Name `
            -AssessmentDisplayName $assessmentDisplayName

        if ($null -eq $response) {
            Write-Warning "  No results for $($tenant.Name) — skipping."
            continue
        }

        $resultsProp = $response.PSObject.Properties['results']
        $results = if ($resultsProp -and $resultsProp.Value -is [array]) { $resultsProp.Value } else { @() }
        $checks = & $processResults $results
        [void]$allTenantResults.Add(@{ TenantId = $tenant.Id; TenantName = $tenant.Name; Checks = @($checks) } + (& $summarize $checks $response))
    }

    $totalStopwatch.Stop()
    $totalTimeStr = & $fmtTime $totalStopwatch.Elapsed.TotalSeconds

    Write-Host ""
    Write-Host "All assessments complete. $($allTenantResults.Count) tenant(s) processed in $totalTimeStr." -ForegroundColor Green

    # Every tenant failed. Bail before the summary and every export path: the HTML and CSV
    # renderers take a mandatory -TenantResults, so falling through binds an empty collection
    # and throws a parameter-binding error that says nothing about why the runs failed.
    # One guard here covers the Json, Html and Csv paths below.
    if ($allTenantResults.Count -eq 0) {
        Write-Error -Message 'No assessment results were returned for any tenant, so there is nothing to report. See the errors above for the per-tenant failures.' -ErrorId 'NoAssessmentResults' -Category InvalidResult
        return
    }

    # Summary per tenant
    foreach ($tr in $allTenantResults) {
        $color = if ($tr.Score -ge 90) { 'Green' } elseif ($tr.Score -ge 70) { 'Yellow' } else { 'Red' }
        Write-Host "  $($tr.TenantName) — $($tr.Score)% ($($tr.Passed)/$($tr.Passed + $tr.Failed)$(if ($tr.NotAssessed) { ", $($tr.NotAssessed) not assessed" }))" -ForegroundColor $color
    }
    Write-Host ""

    # JsonObject output for automation
    if ($OutputType -eq 'JsonObject') {
        $jsonOutput = [System.Collections.Generic.List[object]]::new()
        foreach ($tr in $allTenantResults) {
            [void]$jsonOutput.Add([PSCustomObject]@{
                TenantName      = $tr.TenantName
                TenantId        = $tr.TenantId
                ComplianceScore = $tr.Score
                TotalChecks     = $tr.TotalChecks
                Passed          = $tr.Passed
                Failed          = $tr.Failed
                NotAssessed     = $tr.NotAssessed
                Checks          = @($tr.Checks | ForEach-Object {
                    [PSCustomObject]@{
                        Name             = $_.name
                        Category         = $_.category
                        SubCategory      = $_.subCategory
                        Importance       = $_.importance
                        Status           = $_.Status
                        ObjectsEvaluated = $_.ObjectsEvaluated
                        FindingsMessage  = $_.FindingsMessage
                        Violations       = $_.Violations
                        Warnings         = $_.Warnings
                        Passes           = $_.Passes
                    }
                })
            })
        }
        ConvertTo-Json -InputObject @($jsonOutput) -Depth 100
        return
    }

    # Export
    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
        $resolvedPath = [System.IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath))
        $ext = [System.IO.Path]::GetExtension($resolvedPath).ToLower()

        if ($ext -eq '.html' -or $ext -eq '.htm') {
            $html = ConvertTo-InforcerAssessmentMatrixHtml `
                -AssessmentName $assessmentDisplayName `
                -TenantResults @($allTenantResults)
            $html | Set-Content -Path $resolvedPath -Encoding UTF8
            Write-Host "Matrix HTML report saved to: $resolvedPath"
        }
        elseif ($ext -eq '.csv') {
            $csvRows = [System.Collections.Generic.List[object]]::new()
            foreach ($tr in $allTenantResults) {
                foreach ($c in $tr.Checks) {
                    [void]$csvRows.Add((& $csvSafe ([PSCustomObject]@{
                        Tenant           = $tr.TenantName
                        TenantId         = $tr.TenantId
                        Status           = $c.Status
                        Name             = $c.name
                        Category         = $c.category
                        SubCategory      = $c.subCategory
                        Importance       = $c.importance
                        ObjectsEvaluated = $c.ObjectsEvaluated
                        FindingsMessage  = $c.FindingsMessage
                        Violations       = ($c.Violations -join '; ')
                        Warnings         = ($c.Warnings -join '; ')
                        Passes           = ($c.Passes -join '; ')
                    })))
                }
            }
            $csvRows | Export-Csv -Path $resolvedPath -NoTypeInformation -Encoding utf8NoBOM
            Write-Host "CSV report saved to: $resolvedPath"
        }
        else {
            Write-Error -Message "Unsupported file extension '$ext'. Use .html or .csv." -ErrorId 'UnsupportedFormat' -Category InvalidArgument
            return
        }
        [System.IO.FileInfo]::new($resolvedPath)
        return
    }

    # Pipeline output: emit checks with TenantName added
    foreach ($tr in $allTenantResults) {
        foreach ($c in $tr.Checks) {
            $c | Add-Member -NotePropertyName 'TenantName' -NotePropertyValue $tr.TenantName -Force
            $c | Add-Member -NotePropertyName 'TenantId' -NotePropertyValue $tr.TenantId -Force
            $c
        }
    }
    return
}

# ── SINGLE-TENANT MODE ──
$singleTenantId = @($TenantId)[0]
try {
    $clientTenantId = Resolve-InforcerTenantId -TenantId $singleTenantId -TenantData $tenantData
} catch {
    Write-Error -Message $_.Exception.Message -ErrorId 'InvalidTenantId' -Category InvalidArgument
    return
}
$tenantDisplayName = & $resolveTenantName $clientTenantId

$response = Invoke-InforcerAssessmentRun `
    -TenantId $clientTenantId `
    -ResolvedAssessmentId $resolvedAssessmentId `
    -TenantDisplayName $tenantDisplayName `
    -AssessmentDisplayName $assessmentDisplayName

if ($null -eq $response) { return }

# A piped tenant: results carry its id, as in multi-tenant mode.
$pipedTenantId = if ($PSCmdlet.MyInvocation.ExpectingInput) { $clientTenantId } else { $null }

if ($OutputType -eq 'JsonObject') {
    if ($null -ne $pipedTenantId -and $response -is [PSObject] -and -not $response.PSObject.Properties['TenantId']) {
        $response.PSObject.Properties.Add([System.Management.Automation.PSNoteProperty]::new('TenantId', $pipedTenantId))
    }
    $response | ConvertTo-Json -Depth 100
    return
}

# Compute summary
$resultsProp = $response.PSObject.Properties['results']
$results = if ($resultsProp -and $resultsProp.Value -is [array]) { $resultsProp.Value } else { @() }
$processedChecks = & $processResults $results
$summary = & $summarize $processedChecks $response
$score = $summary.Score

Write-Host ""
Write-Host "  $assessmentDisplayName — ${score}% compliant ($($summary.Passed)/$($summary.Passed + $summary.Failed) checks passed$(if ($summary.NotAssessed) { ", $($summary.NotAssessed) not assessed" }))" -ForegroundColor $(if ($score -eq 100) { 'Green' } elseif ($score -ge 75) { 'Yellow' } else { 'Red' })
Write-Host ""

# Export or emit
if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $resolvedPath = [System.IO.Path]::GetFullPath($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath))
    $ext = [System.IO.Path]::GetExtension($resolvedPath).ToLower()

    if ($ext -eq '.html' -or $ext -eq '.htm') {
        $html = ConvertTo-InforcerAssessmentHtml `
            -AssessmentName $assessmentDisplayName `
            -TenantName $tenantDisplayName `
            -Checks @($processedChecks) `
            -Score $score `
            -TotalChecks $summary.TotalChecks `
            -Passed $summary.Passed `
            -Failed $summary.Failed `
            -NotAssessed $summary.NotAssessed
        $html | Set-Content -Path $resolvedPath -Encoding UTF8
        Write-Host "HTML report saved to: $resolvedPath"
    }
    elseif ($ext -eq '.csv') {
        $csvRows = foreach ($c in $processedChecks) {
            & $csvSafe ([PSCustomObject]@{
                Status           = $c.Status
                Name             = $c.name
                Category         = $c.category
                SubCategory      = $c.subCategory
                Importance       = $c.importance
                ObjectsEvaluated = $c.ObjectsEvaluated
                FindingsMessage  = $c.FindingsMessage
                Violations       = ($c.Violations -join '; ')
                Warnings         = ($c.Warnings -join '; ')
                Passes           = ($c.Passes -join '; ')
            })
        }
        $csvRows | Export-Csv -Path $resolvedPath -NoTypeInformation -Encoding utf8NoBOM
        Write-Host "CSV report saved to: $resolvedPath"
    }
    else {
        Write-Error -Message "Unsupported file extension '$ext'. Use .html or .csv." -ErrorId 'UnsupportedFormat' -Category InvalidArgument
        return
    }
    [System.IO.FileInfo]::new($resolvedPath)
    return
}

foreach ($c in $processedChecks) {
    if ($null -ne $pipedTenantId -and -not $c.PSObject.Properties['TenantId']) { $c | Add-Member -NotePropertyName 'TenantId' -NotePropertyValue $pipedTenantId }
    $c
}
}
}
