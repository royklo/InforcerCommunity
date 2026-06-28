function Resolve-InforcerReportTypeSchema {
    <#
    .SYNOPSIS
        Validates a (ReportType, OutputFormat, parameters) tuple against the report types catalog
        and returns the normalized POST /reports/runs entry (Private helper).
    .DESCRIPTION
        Uses the module-scoped $script:InforcerReportTypeCache. If the cache is empty, lazy-fetches
        the catalog from GET /beta/reports/types via Invoke-InforcerApiRequest.

        Validates client-side (so the user gets a clear error before the API does):
          * ReportType is in the catalog (case-insensitive)
          * OutputFormat is in the type's supportedFormats (when discoverable)
          * Collate switch is rejected on types where the catalog reports collatable:false
          * AssessmentId is mandatory for the Assessment report type
          * Smart defaults applied: CopilotAdoption / ShadowAiDetection → report-period=30 when omitted

        On invalid input, throws a terminating error. The catalog response shape isn't fully
        contractual yet — the helper introspects common property name variants and degrades to
        "skip validation, defer to server" when the shape isn't recognized.
    .PARAMETER ReportType
        Single report type key (e.g. 'CopilotAdoption'). Case-insensitive.
    .PARAMETER OutputFormat
        Single output format (e.g. 'csv', 'pdf'). Case-insensitive.
    .PARAMETER Parameter
        Optional hashtable of additional parameters passed straight to the API.
    .PARAMETER ReportPeriod
        Optional integer days. When set, merged into parameters as 'report-period'=<value>.
    .PARAMETER AssessmentId
        Optional GUID. When set, merged into parameters as 'assessment-id'=<value>. Required
        for ReportType='Assessment'.
    .PARAMETER Collate
        Request a single cross-tenant output. Only valid on types with collatable:true.
    .PARAMETER Force
        Bypass the cache and refetch the catalog.
    .OUTPUTS
        PSCustomObject with members:
          Entry           — the [ordered]@{...} hashtable ready to drop into reports[] array
          TypeKey         — canonical type key
          OutputFormat    — canonical output format
          Collate         — boolean
          Parameters      — final flattened parameters hashtable
          CatalogEntry    — the matching catalog item (or $null when catalog unavailable)
          IsCollatable    — boolean / $null
          SupportedFormats — list of supported formats (or $null)
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ReportType,

        [Parameter(Mandatory = $true)]
        [string]$OutputFormat,

        [Parameter(Mandatory = $false)]
        [hashtable]$Parameter,

        [Parameter(Mandatory = $false)]
        [Nullable[int]]$ReportPeriod,

        [Parameter(Mandatory = $false)]
        [string]$AssessmentId,

        [Parameter(Mandatory = $false)]
        [switch]$Collate,

        [Parameter(Mandatory = $false)]
        [switch]$Force
    )

    # 1. Ensure catalog is available
    if ($Force -or $null -eq $script:InforcerReportTypeCache) {
        try {
            $catalog = Invoke-InforcerApiRequest -Endpoint '/beta/reports/types' -Method GET -ErrorAction Stop
        } catch {
            $catalog = $null
        }
        if ($catalog) {
            $script:InforcerReportTypeCache = @($catalog)
        }
    }
    $catalog = $script:InforcerReportTypeCache

    # 2. Look up the type entry (or proceed without when catalog isn't available)
    $typeEntry = $null
    if ($catalog) {
        $typeEntry = $catalog | Where-Object {
            $keyProp = $_.PSObject.Properties['key']
            $keyProp -and (($keyProp.Value -as [string]) -ieq $ReportType)
        } | Select-Object -First 1

        if (-not $typeEntry) {
            $availableKeys = @($catalog | ForEach-Object { $_.PSObject.Properties['key'].Value -as [string] } | Where-Object { $_ }) -join ', '
            throw "Unknown report type '$ReportType'. Available: $availableKeys"
        }
    } else {
        Write-Verbose "Report types catalog unavailable; skipping catalog validation for '$ReportType'."
    }

    # 3. Canonicalize ReportType / OutputFormat using catalog casing when present
    if ($typeEntry -and $typeEntry.PSObject.Properties['key']) {
        $ReportType = ($typeEntry.PSObject.Properties['key'].Value -as [string])
    }

    # 4. Validate OutputFormat against catalog (when discoverable)
    $supportedFormats = $null
    if ($typeEntry) {
        foreach ($candidate in 'supportedOutputFormats','outputFormats','supportedFormats','formats') {
            if ($typeEntry.PSObject.Properties[$candidate]) {
                $supportedFormats = $typeEntry.PSObject.Properties[$candidate].Value
                break
            }
        }
    }
    if ($supportedFormats) {
        $matchedFormat = $null
        foreach ($candidate in @($supportedFormats)) {
            if (($candidate -as [string]) -ieq $OutputFormat) { $matchedFormat = $candidate -as [string]; break }
        }
        if (-not $matchedFormat) {
            $list = ($supportedFormats -join ', ')
            throw "Report type '$ReportType' does not support output format '$OutputFormat'. Supported: $list"
        }
        $OutputFormat = $matchedFormat
    }

    # 5. Validate Collate against catalog
    $isCollatable = $null
    if ($typeEntry -and $typeEntry.PSObject.Properties['collatable']) {
        $isCollatable = [bool]$typeEntry.PSObject.Properties['collatable'].Value
    }
    if ($Collate.IsPresent -and $null -ne $isCollatable -and -not $isCollatable) {
        throw "Report type '$ReportType' does not support collation (collatable:false). Remove -Collate or choose a different type."
    }

    # 6. Build the final flattened parameters bag (string values only — matches API contract)
    $finalParams = @{}
    if ($Parameter) {
        foreach ($k in $Parameter.Keys) {
            $finalParams[($k -as [string])] = ($Parameter[$k] -as [string])
        }
    }
    if ($PSBoundParameters.ContainsKey('ReportPeriod')) {
        $finalParams['report-period'] = ($ReportPeriod -as [string])
    }
    if ($PSBoundParameters.ContainsKey('AssessmentId')) {
        $finalParams['assessment-id'] = $AssessmentId.ToString()
    }

    # 7. Validate parameter keys against catalog (defensive — bug #6: server silently ignores unknowns)
    if ($typeEntry -and $finalParams.Count -gt 0) {
        $catalogParams = $null
        foreach ($candidate in 'requiredParameters','parameters','params') {
            if ($typeEntry.PSObject.Properties[$candidate]) {
                $catalogParams = $typeEntry.PSObject.Properties[$candidate].Value
                break
            }
        }
        if ($catalogParams) {
            $allowedKeys = @(
                foreach ($p in @($catalogParams)) {
                    if ($p -is [string]) {
                        $p
                    } else {
                        foreach ($keyProp in 'key','name','id') {
                            if ($p.PSObject.Properties[$keyProp]) {
                                $p.PSObject.Properties[$keyProp].Value -as [string]
                                break
                            }
                        }
                    }
                }
            ) | Where-Object { $_ }

            if ($allowedKeys.Count -gt 0) {
                $allowedSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($a in $allowedKeys) { [void]$allowedSet.Add($a) }
                foreach ($k in @($finalParams.Keys)) {
                    if (-not $allowedSet.Contains($k)) {
                        $allowedList = ($allowedKeys -join ', ')
                        throw "Unknown parameter '$k' for report type '$ReportType'. Allowed: $allowedList"
                    }
                }
            }
        }
    }

    # 8. Apply smart auto-defaults for known types
    if (-not $finalParams.ContainsKey('report-period')) {
        if ($ReportType -ieq 'CopilotAdoption' -or $ReportType -ieq 'ShadowAiDetection') {
            $finalParams['report-period'] = '30'
        }
    }

    # 9. Assessment type requires assessment-id with no sensible default
    if ($ReportType -ieq 'Assessment' -and -not $finalParams.ContainsKey('assessment-id')) {
        throw "Report type 'Assessment' requires -AssessmentId. Run Get-InforcerAssessment to list available IDs."
    }

    # 10. Build the per-request entry shape that Invoke-InforcerReport will drop into reports[]
    $entry = [ordered]@{
        type         = $ReportType
        outputFormat = $OutputFormat
    }
    if ($Collate.IsPresent) {
        $entry['collate'] = $true
    }
    if ($finalParams.Count -gt 0) {
        $entry['parameters'] = $finalParams
    }

    [PSCustomObject]@{
        Entry            = $entry
        TypeKey          = $ReportType
        OutputFormat     = $OutputFormat
        Collate          = [bool]$Collate.IsPresent
        Parameters       = $finalParams
        CatalogEntry     = $typeEntry
        IsCollatable     = $isCollatable
        SupportedFormats = $supportedFormats
    }
}
