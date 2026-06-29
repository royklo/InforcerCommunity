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

    # 1. Ensure catalog is available. Cache lives for 15 minutes — long-running sessions
    # auto-refresh so newly-shipped report types don't require disconnect/reconnect.
    $catalogFetchError = $null
    $cacheTtlMinutes = 15
    $cacheIsStale = $false
    if ($script:InforcerReportTypeCache -and $script:InforcerReportTypeCacheStamp) {
        $age = (Get-Date) - $script:InforcerReportTypeCacheStamp
        if ($age.TotalMinutes -gt $cacheTtlMinutes) {
            Write-Verbose ("Reports catalog cache is {0:N1} minutes old (TTL {1}m) — refreshing." -f $age.TotalMinutes, $cacheTtlMinutes)
            $cacheIsStale = $true
        }
    }
    if ($Force -or $null -eq $script:InforcerReportTypeCache -or $cacheIsStale) {
        try {
            $catalog = Invoke-InforcerApiRequest -Endpoint '/beta/reports/types' -Method GET -ErrorAction Stop
        } catch {
            $catalog = $null
            # Defensive re-scrub: even though Invoke-InforcerApiRequest already redacts API
            # keys, surfacing $_.Exception.Message in our own Write-Warning is safer with one
            # more pass through Protect-InforcerApiKeyInText.
            $rawMsg = $_.Exception.Message
            $catalogFetchError = if ($script:InforcerSession -and $script:InforcerSession.ApiKey) {
                $maskedKey = ConvertFrom-InforcerSecureString -SecureString $script:InforcerSession.ApiKey
                Protect-InforcerApiKeyInText -Text $rawMsg -ApiKey $maskedKey
            } else { $rawMsg }
        }
        if ($catalog) {
            $script:InforcerReportTypeCache = @($catalog)
            $script:InforcerReportTypeCacheStamp = Get-Date
        }
    }
    $catalog = $script:InforcerReportTypeCache

    # If catalog fetch failed (vs. genuinely-empty endpoint), surface a single warning so
    # callers know their input wasn't validated client-side. Without this, a transient
    # network failure / rate limit / scope issue would let bogus -ReportType / -OutputFormat
    # / unknown -Parameter keys pass through to the API as confusing 400s.
    if ($null -eq $catalog -and $null -ne $catalogFetchError) {
        Write-Warning ("Report types catalog could not be fetched ({0}). Client-side validation of -ReportType / -OutputFormat / -Parameter is disabled for this call; errors will surface from the server." -f $catalogFetchError)
    }

    # 2. Look up the type entry (or proceed without when catalog isn't available)
    $typeEntry = $null
    if ($catalog) {
        $typeEntry = $catalog | Where-Object {
            $keyProp = $_.PSObject.Properties['key']
            $keyProp -and (($keyProp.Value -as [string]) -ieq $ReportType)
        } | Select-Object -First 1

        if (-not $typeEntry -and -not $Force) {
            # Cache may be stale (Inforcer ships new report types regularly). Refetch once before
            # surfacing "Unknown report type" — auto-recovery beats forcing the user to disconnect.
            Write-Verbose "Type '$ReportType' not found in cached catalog; refetching once before failing."
            try {
                $refreshed = Invoke-InforcerApiRequest -Endpoint '/beta/reports/types' -Method GET -ErrorAction Stop
            } catch {
                $refreshed = $null
            }
            if ($refreshed) {
                $script:InforcerReportTypeCache = @($refreshed)
                $catalog = $script:InforcerReportTypeCache
                $typeEntry = $catalog | Where-Object {
                    $keyProp = $_.PSObject.Properties['key']
                    $keyProp -and (($keyProp.Value -as [string]) -ieq $ReportType)
                } | Select-Object -First 1
            }
        }

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

    # 6. Build the final flattened parameters bag (string values only — matches API contract).
    # Reject non-scalar values up-front — passing an array or hashtable would otherwise get
    # silently coerced via `-as [string]` ("System.Object[]" or "1 2 3"), producing a request
    # the server can't act on without any clear error.
    $finalParams = @{}
    if ($Parameter) {
        foreach ($k in $Parameter.Keys) {
            $v = $Parameter[$k]
            # Scriptblocks would silently stringify to "{...}" via `-as [string]` — reject explicitly
            # so the user finds out their callable wasn't sent as a value.
            if ($v -is [scriptblock]) {
                throw "Parameter '$k' is a [scriptblock]; the API only accepts scalar string-coercible values. Did you mean to invoke the scriptblock first?"
            }
            # Arrays / lists / dictionaries silently flatten to "1 2 3" or "System.Object[]".
            # Exclude [string] (IEnumerable<char>) and [DateTime] (PowerShell decorates date types
            # with PSCustomObject markers in some hosts — keep them scalar).
            if ($null -ne $v -and $v -isnot [string] -and $v -isnot [datetime] -and $v -is [System.Collections.IEnumerable]) {
                throw "Parameter '$k' must be a scalar value; arrays and collections are not supported by the API. Got: $($v.GetType().FullName)."
            }
            # Use the literal PSCustomObject type — `-is [PSCustomObject]` is too broad in PS7 and
            # incorrectly matches scalars like [DateTime].
            if ($v -is [hashtable] -or $v -is [System.Management.Automation.PSCustomObject]) {
                throw "Parameter '$k' must be a scalar value; got nested object of type $($v.GetType().FullName)."
            }
            $finalParams[($k -as [string])] = ($v -as [string])
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
