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
    [string]$Key,

    [Parameter(Mandatory = $false)]
    [string]$Tag,

    [Parameter(Mandatory = $false)]
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
                foreach ($t in @($tagsProp.Value)) {
                    if (($t -as [string]) -ieq $Tag) { $hit = $true; break }
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
