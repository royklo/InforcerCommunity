<#
.SYNOPSIS
    Runs an assessment against a tenant via the Inforcer API.
.DESCRIPTION
    Triggers an assessment run for a specific tenant and returns detailed results including
    per-check scores, passes, violations, warnings, and framework metadata.
    -AssessmentId accepts an assessment ID string or a friendly name (e.g. "Copilot Readiness").
.PARAMETER TenantId
    The tenant to run the assessment against. Accepts numeric ID, GUID, or tenant name.
.PARAMETER AssessmentId
    The assessment to run. Accepts an assessment ID string or a friendly assessment name.
.PARAMETER OutputType
    PowerShellObject (default) or JsonObject. JSON uses Depth 100.
.EXAMPLE
    Invoke-InforcerAssessment -TenantId 144 -AssessmentId "Copilot Readiness"
    Runs the Copilot Readiness assessment against tenant 144.
.EXAMPLE
    Invoke-InforcerAssessment -TenantId "Contoso" -AssessmentId "l1f8wd29pl44pp1j66r9"
    Runs the assessment by ID against the Contoso tenant.
.EXAMPLE
    Invoke-InforcerAssessment -TenantId 144 -AssessmentId "CIS Microsoft 365 Foundations Benchmark v6.0.0 (L1)" -OutputType JsonObject
    Returns the assessment results as a JSON string.
.OUTPUTS
    PSObject or String
.LINK
    https://github.com/royklo/InforcerCommunity/blob/main/docs/CMDLET-REFERENCE.md#invoke-inforcerassessment
.LINK
    Connect-Inforcer
.LINK
    Get-InforcerAssessment
#>
function Invoke-InforcerAssessment {
[CmdletBinding()]
[OutputType([PSObject], [string])]
param(
    [Parameter(Mandatory = $true, ValueFromPipelineByPropertyName = $true)]
    [Alias('ClientTenantId')]
    [object]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$AssessmentId,

    [Parameter(Mandatory = $false)]
    [ValidateSet('PowerShellObject', 'JsonObject')]
    [string]$OutputType = 'PowerShellObject'
)

if (-not (Test-InforcerSession)) {
    Write-Error -Message 'Not connected yet. Please run Connect-Inforcer first.' -ErrorId 'NotConnected' -Category ConnectionError
    return
}

# Resolve tenant and get friendly name
$tenantData = $null
try {
    $tenantData = @(Invoke-InforcerApiRequest -Endpoint '/beta/tenants' -Method GET -OutputType PowerShellObject)
    $clientTenantId = Resolve-InforcerTenantId -TenantId $TenantId -TenantData $tenantData
} catch {
    Write-Error -Message $_.Exception.Message -ErrorId 'InvalidTenantId' -Category InvalidArgument
    return
}

# Resolve tenant friendly name for display
$tenantDisplayName = "$clientTenantId"
if ($tenantData) {
    foreach ($t in $tenantData) {
        if ($t -is [PSObject]) {
            $cidProp = $t.PSObject.Properties['clientTenantId']
            if ($cidProp -and [int]$cidProp.Value -eq $clientTenantId) {
                $fn = $t.PSObject.Properties['tenantFriendlyName']
                $dn = $t.PSObject.Properties['tenantDnsName']
                $tenantDisplayName = if ($fn -and -not [string]::IsNullOrWhiteSpace($fn.Value) -and $fn.Value -ne 'Tenant') {
                    $fn.Value
                } elseif ($dn -and -not [string]::IsNullOrWhiteSpace($dn.Value)) {
                    $dn.Value
                } else { "$clientTenantId" }
                break
            }
        }
    }
}

# Resolve assessment (fetch list once for name resolution + friendly name)
$assessmentData = $null
try {
    $assessmentData = @(Invoke-InforcerApiRequest -Endpoint '/beta/assessments' -Method GET -OutputType PowerShellObject)
    $resolvedAssessmentId = Resolve-InforcerAssessmentId -AssessmentId $AssessmentId -AssessmentData $assessmentData
} catch {
    Write-Error -Message $_.Exception.Message -ErrorId 'InvalidAssessmentId' -Category InvalidArgument
    return
}

# Resolve assessment friendly name for display
$assessmentDisplayName = $AssessmentId
if ($assessmentData) {
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
}

Write-Host "Running '$assessmentDisplayName' assessment against $tenantDisplayName..."

$endpoint = "/beta/tenants/$clientTenantId/assessments/$resolvedAssessmentId/runs"

# Build URI and headers for async HTTP call
$uri = $script:InforcerSession.BaseUrl + $endpoint
$apiKey = ConvertFrom-InforcerSecureString -SecureString $script:InforcerSession.ApiKey
$headers = @{ 'Inf-Api-Key' = $apiKey; 'Content-Type' = 'application/json' }

# Run async with PowerShell runspace so we can show progress
$ps = [PowerShell]::Create()
$null = $ps.AddScript('param($Uri, $Headers); Invoke-RestMethod -Uri $Uri -Method POST -Headers $Headers')
$null = $ps.AddParameter('Uri', $uri)
$null = $ps.AddParameter('Headers', $headers)
$asyncResult = $ps.BeginInvoke()

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$lastUpdate = 0
while (-not $asyncResult.IsCompleted) {
    Start-Sleep -Milliseconds 500
    $elapsed = [math]::Floor($stopwatch.Elapsed.TotalSeconds)
    if ($elapsed -gt 0 -and $elapsed % 10 -eq 0 -and $elapsed -ne $lastUpdate) {
        Write-Host "  Still running... ${elapsed}s elapsed"
        $lastUpdate = $elapsed
    }
}

$rawResponse = $null
$hasError = $false
try {
    $rawResponse = $ps.EndInvoke($asyncResult)
    if ($ps.Streams.Error.Count -gt 0) {
        $hasError = $true
        foreach ($e in $ps.Streams.Error) {
            # Extract clean message from HTTP errors (strip HTML)
            $errMsg = $e.ToString()
            if ($errMsg -match '<title>([^<]+)</title>') { $errMsg = "API error: $($Matches[1].Trim())" }
            elseif ($errMsg.Length -gt 500) { $errMsg = $errMsg.Substring(0, 200) + '...' }
            Write-Error -Message $errMsg -ErrorId 'AssessmentRunFailed' -Category InvalidResult
        }
    }
} catch {
    $hasError = $true
    $errMsg = $_.Exception.Message
    if ($errMsg -match '<title>([^<]+)</title>') { $errMsg = "API error: $($Matches[1].Trim())" }
    elseif ($errMsg.Length -gt 500) { $errMsg = $errMsg.Substring(0, 200) + '...' }
    Write-Error -Message "Assessment run failed: $errMsg" -ErrorId 'AssessmentRunFailed' -Category InvalidResult
} finally {
    $ps.Dispose()
}

$stopwatch.Stop()
$elapsed = [math]::Round($stopwatch.Elapsed.TotalSeconds, 1)
if ($hasError) {
    Write-Host "Assessment failed after ${elapsed}s."
    return
}
Write-Host "Assessment completed in ${elapsed}s."

# Unwrap: $rawResponse from EndInvoke is a PSDataCollection — extract first item
$responseObj = if ($rawResponse -and $rawResponse.Count -gt 0) { $rawResponse[0] } else { $null }
if ($null -eq $responseObj) { return }

# Unwrap .data from response (same pattern as Invoke-InforcerApiRequest)
$dataProp = $responseObj.PSObject.Properties['data']
$response = if ($dataProp) { $dataProp.Value } else { $responseObj }
if ($null -eq $response) { return }

if ($OutputType -eq 'JsonObject') {
    $response | ConvertTo-Json -Depth 100
    return
}

# Compute summary and display via Write-Host (not pipeline)
$resultsProp = $response.PSObject.Properties['results']
$results = if ($resultsProp -and $resultsProp.Value -is [array]) { $resultsProp.Value } else { @() }
$totalChecks = $results.Count
$compliantCount = 0
$nonCompliantCount = 0
foreach ($r in $results) {
    if ($r -is [PSObject]) {
        $fp = $r.PSObject.Properties['findings']
        if ($fp -and $fp.Value -is [PSObject]) {
            $cp = $fp.Value.PSObject.Properties['compliant']
            if ($cp -and $cp.Value -eq $true) { $compliantCount++ } else { $nonCompliantCount++ }
        }
    }
}
$score = if ($totalChecks -gt 0) { [math]::Round(($compliantCount / $totalChecks) * 100, 1) } else { 0 }

Write-Host ""
Write-Host "  $assessmentDisplayName — ${score}% compliant ($compliantCount/$totalChecks checks passed)" -ForegroundColor $(if ($score -eq 100) { 'Green' } elseif ($score -ge 75) { 'Yellow' } else { 'Red' })
Write-Host ""

# Emit each check as a pipeline object
foreach ($r in $results) {
    if (-not ($r -is [PSObject])) { continue }
    $fp = $r.PSObject.Properties['findings']
    $isCompliant = $false
    $findingsMessage = ''
    if ($fp -and $fp.Value -is [PSObject]) {
        $cp = $fp.Value.PSObject.Properties['compliant']
        if ($cp) { $isCompliant = $cp.Value -eq $true }
        $mp = $fp.Value.PSObject.Properties['message']
        if ($mp) { $findingsMessage = $mp.Value }
    }

    $statusText = if ($isCompliant) { 'Pass' } else { 'Fail' }

    # Flatten passes, violations, warnings from findings.scores
    # Strip placeholder objectNames — only prefix with real policy/object names
    $placeholderNames = @('[Multiple Objects Evaluated]', '[unknown id]', '[unknown name]')
    $allPasses = [System.Collections.Generic.List[string]]::new()
    $allViolations = [System.Collections.Generic.List[string]]::new()
    $allWarnings = [System.Collections.Generic.List[string]]::new()
    if ($fp -and $fp.Value -is [PSObject]) {
        $scoresProp = $fp.Value.PSObject.Properties['scores']
        if ($scoresProp -and $scoresProp.Value -is [array]) {
            foreach ($s in $scoresProp.Value) {
                if (-not ($s -is [PSObject])) { continue }
                $objName = ''
                $onp = $s.PSObject.Properties['objectName']
                if ($onp -and $onp.Value -and $onp.Value -notin $placeholderNames) {
                    $objName = $onp.Value
                }
                $prefix = if ($objName) { "$objName — " } else { '' }

                $pp = $s.PSObject.Properties['passes']
                if ($pp -and $pp.Value -is [array]) {
                    foreach ($p in $pp.Value) { if ($p) { [void]$allPasses.Add("${prefix}$p") } }
                }
                $vp = $s.PSObject.Properties['violations']
                if ($vp -and $vp.Value -is [array]) {
                    foreach ($v in $vp.Value) { if ($v) { [void]$allViolations.Add("${prefix}$v") } }
                }
                $wp = $s.PSObject.Properties['warnings']
                if ($wp -and $wp.Value -is [array]) {
                    foreach ($w in $wp.Value) { if ($w) { [void]$allWarnings.Add("${prefix}$w") } }
                }
            }
        }
    }

    # Build per-object findings summary and count objects evaluated
    $objectsEvaluated = 0
    $findingsSummary = [System.Collections.Generic.List[string]]::new()
    if ($fp -and $fp.Value -is [PSObject]) {
        $scoresProp2 = $fp.Value.PSObject.Properties['scores']
        if ($scoresProp2 -and $scoresProp2.Value -is [array]) {
            $objectsEvaluated = $scoresProp2.Value.Count
            foreach ($s in $scoresProp2.Value) {
                if (-not ($s -is [PSObject])) { continue }
                $onp = $s.PSObject.Properties['objectName']
                $oName = if ($onp -and $onp.Value -and $onp.Value -notin $placeholderNames) { $onp.Value } else { 'Tenant check' }
                $oScore = $s.PSObject.Properties['score']
                $scoreVal = if ($oScore) { "$($oScore.Value)%" } else { '?' }
                $vCount = 0; $wCount = 0
                $vArr = $s.PSObject.Properties['violations']
                if ($vArr -and $vArr.Value -is [array]) { $vCount = @($vArr.Value | Where-Object { $_ }).Count }
                $wArr = $s.PSObject.Properties['warnings']
                if ($wArr -and $wArr.Value -is [array]) { $wCount = @($wArr.Value | Where-Object { $_ }).Count }
                $issues = [System.Collections.Generic.List[string]]::new()
                if ($vCount -gt 0) { [void]$issues.Add("$vCount violation$(if ($vCount -ne 1) { 's' })") }
                if ($wCount -gt 0) { [void]$issues.Add("$wCount warning$(if ($wCount -ne 1) { 's' })") }
                $suffix = if ($issues.Count -gt 0) { " ($($issues -join ', '))" } else { '' }
                [void]$findingsSummary.Add("$oName — $scoreVal$suffix")
            }
        }
    }

    # Promote findings.scores to top-level Scores property for easy access
    $scoresArray = @()
    if ($fp -and $fp.Value -is [PSObject]) {
        $sp = $fp.Value.PSObject.Properties['scores']
        if ($sp -and $sp.Value -is [array]) { $scoresArray = $sp.Value }
    }

    $r | Add-Member -NotePropertyName 'Status' -NotePropertyValue $statusText -Force
    $r | Add-Member -NotePropertyName 'ObjectsEvaluated' -NotePropertyValue $objectsEvaluated -Force
    $r | Add-Member -NotePropertyName 'FindingsMessage' -NotePropertyValue $findingsMessage -Force
    $r | Add-Member -NotePropertyName 'Scores' -NotePropertyValue $scoresArray -Force
    $r | Add-Member -NotePropertyName 'Violations' -NotePropertyValue @($allViolations) -Force
    $r | Add-Member -NotePropertyName 'Warnings' -NotePropertyValue @($allWarnings) -Force
    $r | Add-Member -NotePropertyName 'Passes' -NotePropertyValue @($allPasses) -Force
    $r.PSObject.TypeNames.Insert(0, 'InforcerCommunity.AssessmentCheck')
    $r
}
}
