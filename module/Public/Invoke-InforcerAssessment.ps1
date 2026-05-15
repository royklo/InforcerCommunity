<#
.SYNOPSIS
    Runs an assessment against one or more tenants via the Inforcer API.
.DESCRIPTION
    Triggers an assessment run and returns detailed results including per-check scores,
    passes, violations, warnings, and framework metadata.
    Supports single-tenant, multi-tenant (all tenants), and subset modes.
    Use -MultiTenant to run against all tenants, or pass multiple values to -TenantId.
    When -OutputPath is specified with multi-tenant, generates an HTML matrix report.
.PARAMETER TenantId
    Tenant(s) to run the assessment against. Accepts numeric ID, GUID, or friendly name.
    Pass multiple values for subset multi-tenant mode.
    Optional when -MultiTenant is used (defaults to all tenants).
.PARAMETER AssessmentId
    The assessment to run. Accepts an assessment ID string or a friendly assessment name.
.PARAMETER MultiTenant
    Switch. Runs the assessment against all tenants (or subset if -TenantId also specified).
    Requires -OutputPath with HTML extension for the matrix report.
.PARAMETER OutputPath
    Optional. File path to export results. Auto-detects format from file extension.
    Single tenant: HTML (.html) report or CSV (.csv).
    Multi-tenant: HTML (.html) matrix report or CSV (.csv) with tenant column.
    Returns System.IO.FileInfo when specified.
.PARAMETER OutputType
    PowerShellObject (default) or JsonObject. JSON uses Depth 100.
.EXAMPLE
    Invoke-InforcerAssessment -TenantId 144 -AssessmentId "Copilot Readiness"
    Runs the Copilot Readiness assessment against tenant 144.
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
    Invoke-InforcerAssessment -TenantId 144 -AssessmentId "Copilot Readiness" -OutputPath ./report.csv
    Exports assessment results to CSV.
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
    [Alias('ClientTenantId')]
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
$tenantData = @(Invoke-InforcerApiRequest -Endpoint '/beta/tenants' -Method GET -OutputType PowerShellObject)

# Resolve assessment
$assessmentData = $null
try {
    $assessmentData = @(Invoke-InforcerApiRequest -Endpoint '/beta/assessments' -Method GET -OutputType PowerShellObject)
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

# Helper: resolve tenant friendly name from tenant data
$resolveTenantName = {
    param([int]$cid, [array]$data)
    foreach ($t in $data) {
        if ($t -is [PSObject]) {
            $cidProp = $t.PSObject.Properties['clientTenantId']
            if ($cidProp -and [int]$cidProp.Value -eq $cid) {
                $fn = $t.PSObject.Properties['tenantFriendlyName']
                $dn = $t.PSObject.Properties['tenantDnsName']
                if ($fn -and -not [string]::IsNullOrWhiteSpace($fn.Value) -and $fn.Value -ne 'Tenant') { return $fn.Value }
                if ($dn -and -not [string]::IsNullOrWhiteSpace($dn.Value)) { return $dn.Value }
                return "$cid"
            }
        }
    }
    return "$cid"
}

# Helper: process raw API results into enriched check objects
$placeholderNames = @('[Multiple Objects Evaluated]', '[unknown id]', '[unknown name]')
$processResults = {
    param([array]$results)
    $checks = [System.Collections.Generic.List[object]]::new()
    foreach ($r in $results) {
        if (-not ($r -is [PSObject])) { continue }
        $fp = $r.PSObject.Properties['findings']
        $isCompliant = $false; $findingsMessage = ''
        if ($fp -and $fp.Value -is [PSObject]) {
            $cp = $fp.Value.PSObject.Properties['compliant']
            if ($cp) { $isCompliant = $cp.Value -eq $true }
            $mp = $fp.Value.PSObject.Properties['message']
            if ($mp) { $findingsMessage = $mp.Value }
        }
        $statusText = if ($isCompliant) { 'Pass' } else { 'Fail' }

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

# ── MULTI-TENANT MODE ──
if ($isMultiTenant) {
    # Build list of tenants to run against
    $tenantsToRun = [System.Collections.Generic.List[object]]::new()

    if ($null -ne $TenantId -and @($TenantId).Count -gt 0) {
        # Resolve each specified tenant
        foreach ($tid in @($TenantId)) {
            try {
                $cid = Resolve-InforcerTenantId -TenantId $tid -TenantData $tenantData
                $tname = & $resolveTenantName $cid $tenantData
                [void]$tenantsToRun.Add(@{ Id = $cid; Name = $tname })
            } catch {
                Write-Warning "Skipping tenant '$tid': $($_.Exception.Message)"
            }
        }
    } else {
        # All tenants
        foreach ($t in $tenantData) {
            if ($t -is [PSObject]) {
                $cidProp = $t.PSObject.Properties['clientTenantId']
                if ($cidProp) {
                    $cid = [int]$cidProp.Value
                    $tname = & $resolveTenantName $cid $tenantData
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
            -ClientTenantId $tenant.Id `
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

        # Compute score
        $passed = 0; foreach ($c in $checks) { if ($c.Status -eq 'Pass') { $passed++ } }
        $tScore = if ($checks.Count -gt 0) { [math]::Round(($passed / $checks.Count) * 100, 1) } else { 0 }

        [void]$allTenantResults.Add(@{
            TenantId    = $tenant.Id
            TenantName  = $tenant.Name
            Checks      = @($checks)
            Score       = $tScore
            Passed      = $passed
            Failed      = $checks.Count - $passed
            TotalChecks = $checks.Count
        })
    }

    $totalStopwatch.Stop()
    $totalTimeStr = & $fmtTime $totalStopwatch.Elapsed.TotalSeconds

    Write-Host ""
    Write-Host "All assessments complete. $($allTenantResults.Count) tenant(s) processed in $totalTimeStr." -ForegroundColor Green

    # Summary per tenant
    foreach ($tr in $allTenantResults) {
        $color = if ($tr.Score -ge 90) { 'Green' } elseif ($tr.Score -ge 70) { 'Yellow' } else { 'Red' }
        Write-Host "  $($tr.TenantName) — $($tr.Score)% ($($tr.Passed)/$($tr.TotalChecks))" -ForegroundColor $color
    }
    Write-Host ""

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
                    [void]$csvRows.Add([PSCustomObject]@{
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
                    })
                }
            }
            $csvRows | Export-Csv -Path $resolvedPath -NoTypeInformation -Encoding UTF8
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
$tenantDisplayName = & $resolveTenantName $clientTenantId $tenantData

$response = Invoke-InforcerAssessmentRun `
    -ClientTenantId $clientTenantId `
    -ResolvedAssessmentId $resolvedAssessmentId `
    -TenantDisplayName $tenantDisplayName `
    -AssessmentDisplayName $assessmentDisplayName

if ($null -eq $response) { return }

if ($OutputType -eq 'JsonObject') {
    $response | ConvertTo-Json -Depth 100
    return
}

# Compute summary
$resultsProp = $response.PSObject.Properties['results']
$results = if ($resultsProp -and $resultsProp.Value -is [array]) { $resultsProp.Value } else { @() }
$processedChecks = & $processResults $results
$totalChecks = $processedChecks.Count
$compliantCount = 0; foreach ($c in $processedChecks) { if ($c.Status -eq 'Pass') { $compliantCount++ } }
$nonCompliantCount = $totalChecks - $compliantCount
$score = if ($totalChecks -gt 0) { [math]::Round(($compliantCount / $totalChecks) * 100, 1) } else { 0 }

Write-Host ""
Write-Host "  $assessmentDisplayName — ${score}% compliant ($compliantCount/$totalChecks checks passed)" -ForegroundColor $(if ($score -eq 100) { 'Green' } elseif ($score -ge 75) { 'Yellow' } else { 'Red' })
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
            -TotalChecks $totalChecks `
            -Passed $compliantCount `
            -Failed $nonCompliantCount
        $html | Set-Content -Path $resolvedPath -Encoding UTF8
        Write-Host "HTML report saved to: $resolvedPath"
    }
    elseif ($ext -eq '.csv') {
        $csvRows = foreach ($c in $processedChecks) {
            [PSCustomObject]@{
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
            }
        }
        $csvRows | Export-Csv -Path $resolvedPath -NoTypeInformation -Encoding UTF8
        Write-Host "CSV report saved to: $resolvedPath"
    }
    else {
        Write-Error -Message "Unsupported file extension '$ext'. Use .html or .csv." -ErrorId 'UnsupportedFormat' -Category InvalidArgument
        return
    }
    [System.IO.FileInfo]::new($resolvedPath)
    return
}

foreach ($c in $processedChecks) { $c }
}
