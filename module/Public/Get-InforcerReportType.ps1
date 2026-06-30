<#
.SYNOPSIS
    Lists available report types from the Inforcer Reports API.

    Required API scope(s): Reports.Read
.DESCRIPTION
    Retrieves the catalog of report types from GET /beta/reports/types. Each catalog entry
    describes a report's key, supported output formats, collatability, accepted parameters,
    and tags. The catalog is cached in the module-scoped variable so subsequent calls
    (and tab-completion lookups) are instant; pass -Force to refetch from the API.

    Output is shaped for cmdlet consumption: PascalCase property aliases are added and
    the InforcerCommunity.ReportType PSTypeName is inserted to drive default formatting.
.PARAMETER Key
    Filter to a single report type by key (case-insensitive). Aliases: -Name, -ReportType.
.PARAMETER Tag
    Filter to types containing the specified tag (case-insensitive).
.PARAMETER OutputFormat
    Filter to types that support the specified output format (e.g. csv, json, pdf, html).
.PARAMETER Force
    Bypass the in-memory cache and refetch the catalog from the API.
.PARAMETER Format
    Raw (default). Reserved for future shape changes.
.PARAMETER OutputType
    PowerShellObject (default) or JsonObject. JSON uses Depth 100.
.EXAMPLE
    Get-InforcerReportType
    Lists every available report type.
.EXAMPLE
    Get-InforcerReportType -Key CopilotAdoption
    Returns the single CopilotAdoption catalog entry.
.EXAMPLE
    Get-InforcerReportType -OutputFormat pdf
    Lists every type that supports PDF output.
.EXAMPLE
    Get-InforcerReportType -Tag security
    Lists every type tagged with 'security'.
.EXAMPLE
    Get-InforcerReportType -Tag security | Invoke-InforcerReport -OutputFormat csv -TenantId 482
    Discovers every security-tagged report type and pipes each into Invoke-InforcerReport.
    Works because Get-InforcerReportType emits a 'Key' alias which binds to
    Invoke-InforcerReport's -ReportType (ValueFromPipelineByPropertyName).
.OUTPUTS
    PSObject or String
.LINK
    https://github.com/royklo/InforcerCommunity/blob/main/docs/CMDLET-REFERENCE.md#get-inforcerreporttype
.LINK
    Connect-Inforcer
.LINK
    Invoke-InforcerReport
#>
function Get-InforcerReportType {
[CmdletBinding()]
[OutputType([PSObject], [string])]
param(
    [Parameter(Mandatory = $false, Position = 0)]
    [Alias('Name', 'ReportType')]
    [ArgumentCompleter({
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        # ArgumentCompleter scriptblocks run in the *caller's* session state, NOT the module's,
        # so $script:InforcerReportTypeCache / $script:InforcerReportTypeStaticKeys are invisible
        # from here. Bounce through the module's session via Get-Module so $script:* resolves.
        # The static-fallback list and live cache both live in Private/Get-InforcerReportTypeStaticKeys.ps1.
        $module = Get-Module InforcerCommunity
        $candidates = if ($module) {
            & $module {
                if ($script:InforcerReportTypeCache) {
                    $tmp = [System.Collections.Generic.List[string]]::new()
                    foreach ($e in $script:InforcerReportTypeCache) {
                        if ($e -isnot [PSObject]) { continue }
                        $keyProp = $e.PSObject.Properties['key']
                        if (-not $keyProp) { continue }
                        $v = $keyProp.Value -as [string]
                        if ($v) { [void]$tmp.Add($v) }
                    }
                    # If cache existed but yielded zero keys (malformed entries / unexpected shape),
                    # fall back to the static list rather than letting PS use filesystem completion.
                    if ($tmp.Count -eq 0) { ,$script:InforcerReportTypeStaticKeys } else { ,$tmp.ToArray() }
                } else {
                    ,$script:InforcerReportTypeStaticKeys
                }
            }
        } else { @() }
        $matched = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($c in $candidates) { if ($c -like "$wordToComplete*") { [void]$matched.Add($c) } }
        foreach ($c in $matched) {
            [System.Management.Automation.CompletionResult]::new($c, $c, 'ParameterValue', $c)
        }
    })]
    [string]$Key,

    [Parameter(Mandatory = $false)]
    [ArgumentCompleter({
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        # ArgumentCompleter scriptblocks run in the caller's session state, so $script:*
        # variables defined in the module are invisible from here — bounce through the module
        # to read the live tag set from the cached catalog.
        $known = @('Adoption','Identity','Productivity','Security')
        $module = Get-Module InforcerCommunity
        $candidates = if ($module) {
            & $module {
                if ($script:InforcerReportTypeCache) {
                    $tmp = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                    foreach ($e in $script:InforcerReportTypeCache) {
                        $tagsProp = $e.PSObject.Properties['tags']
                        if ($tagsProp) {
                            foreach ($t in @($tagsProp.Value)) {
                                $tStr = $t -as [string]
                                if ($tStr) { [void]$tmp.Add($tStr) }
                            }
                        }
                    }
                    ,$tmp.ToArray()
                } else {
                    ,@()
                }
            }
        } else { @() }
        if (-not $candidates -or @($candidates).Count -eq 0) { $candidates = $known }
        foreach ($c in $candidates) {
            if ($c -like "$wordToComplete*") {
                [System.Management.Automation.CompletionResult]::new($c, $c, 'ParameterValue', $c)
            }
        }
    })]
    [string]$Tag,

    [Parameter(Mandatory = $false)]
    [ArgumentCompleter({
        param($commandName, $parameterName, $wordToComplete, $commandAst, $fakeBoundParameters)
        $formats = @('csv','json','html','pdf','xlsx')
        foreach ($f in $formats) {
            if ($f -like "$wordToComplete*") {
                [System.Management.Automation.CompletionResult]::new($f, $f, 'ParameterValue', $f)
            }
        }
    })]
    [string]$OutputFormat,

    [Parameter(Mandatory = $false)]
    [switch]$Force,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Raw')]
    [string]$Format = 'Raw',

    [Parameter(Mandatory = $false)]
    [ValidateSet('PowerShellObject', 'JsonObject')]
    [string]$OutputType = 'PowerShellObject'
)

if (-not (Test-InforcerSession)) {
    Write-Error -Message 'Not connected yet. Please run Connect-Inforcer first.' `
        -ErrorId 'NotConnected' -Category ConnectionError
    return
}

# Fetch (or use cache) — JsonObject path always refetches so the response shape isn't
# distorted by PSObject mutations applied during alias-adding.
if ($OutputType -eq 'JsonObject' -or $Force -or $null -eq $script:InforcerReportTypeCache) {
    Write-Verbose 'Retrieving report types catalog...'
    $response = Invoke-InforcerApiRequest -Endpoint '/beta/reports/types' -Method GET -OutputType $OutputType
    if ($null -eq $response) { return }

    if ($OutputType -eq 'JsonObject') {
        # Caller asked for raw JSON — no filtering / aliasing supported in this mode.
        return $response
    }

    $script:InforcerReportTypeCache = @($response)
    $script:InforcerReportTypeCacheStamp = Get-Date
}

$catalog = @($script:InforcerReportTypeCache)

# Filtering — single pass over the cache applying all 3 predicates short-circuit.
$applyKey    = $PSBoundParameters.ContainsKey('Key')          -and -not [string]::IsNullOrWhiteSpace($Key)
$applyTag    = $PSBoundParameters.ContainsKey('Tag')          -and -not [string]::IsNullOrWhiteSpace($Tag)
$applyFormat = $PSBoundParameters.ContainsKey('OutputFormat') -and -not [string]::IsNullOrWhiteSpace($OutputFormat)
if ($applyKey -or $applyTag -or $applyFormat) {
    $filtered = [System.Collections.Generic.List[object]]::new()
    :outer foreach ($entry in $catalog) {
        if ($applyKey) {
            $keyProp = $entry.PSObject.Properties['key']
            if (-not $keyProp -or (($keyProp.Value -as [string]) -ine $Key)) { continue outer }
        }
        if ($applyTag) {
            $tagsProp = $entry.PSObject.Properties['tags']
            $hit = $false
            if ($tagsProp) {
                # Handle both shapes the API may return: an array of tag strings, OR a single
                # comma-separated string (live observed). Split on commas defensively when we
                # see a string, trim whitespace, and match case-insensitively against each entry.
                foreach ($raw in @($tagsProp.Value)) {
                    $rawStr = $raw -as [string]
                    if (-not $rawStr) { continue }
                    foreach ($part in ($rawStr -split ',')) {
                        if ($part.Trim() -ieq $Tag) { $hit = $true; break }
                    }
                    if ($hit) { break }
                }
            }
            if (-not $hit) { continue outer }
        }
        if ($applyFormat) {
            $formats = $null
            foreach ($candidate in 'supportedOutputFormats','outputFormats','supportedFormats','formats') {
                if ($entry.PSObject.Properties[$candidate]) {
                    $formats = $entry.PSObject.Properties[$candidate].Value
                    break
                }
            }
            $hit = $false
            if ($formats) {
                foreach ($f in @($formats)) {
                    if (($f -as [string]) -ieq $OutputFormat) { $hit = $true; break }
                }
            }
            if (-not $hit) { continue outer }
        }
        [void]$filtered.Add($entry)
    }
    $catalog = $filtered.ToArray()
}

# Apply aliases + PSTypeName for clean default display.
foreach ($item in $catalog) {
    if ($item -is [PSObject]) {
        $null = Add-InforcerPropertyAliases -InputObject $item -ObjectType ReportType
        if ($item.PSObject.TypeNames[0] -ne 'InforcerCommunity.ReportType') {
            $item.PSObject.TypeNames.Insert(0, 'InforcerCommunity.ReportType')
        }
    }
}

$catalog
}
