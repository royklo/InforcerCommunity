function Resolve-InforcerReportOutputFileName {
    <#
    .SYNOPSIS
        Parses a Content-Disposition header to extract a safe output filename (Private helper).
    .DESCRIPTION
        Handles both filename= and the RFC 5987 filename*=charset'lang'percent-encoded form,
        preferring the latter when present (it can carry non-ASCII characters that filename=
        cannot). The returned name is sanitized: path components stripped, reserved characters
        removed, leading/trailing whitespace trimmed.

        When the header is absent, empty, or contains no usable filename, falls back to
        -DefaultName (or 'output' if also unset).
    .PARAMETER ContentDisposition
        The raw Content-Disposition header value. May be $null/empty.
    .PARAMETER DefaultName
        Fallback name when no usable filename can be parsed. Default: 'output'.
    .OUTPUTS
        String — a sanitized filename safe for cross-platform filesystem use.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        [string]$ContentDisposition,

        [Parameter(Mandatory = $false)]
        [string]$DefaultName = 'output'
    )

    $parsed = $null

    if (-not [string]::IsNullOrWhiteSpace($ContentDisposition)) {
        # RFC 5987 form takes precedence (supports non-ASCII).
        # Grammar:  filename*=<charset>'<lang>'<percent-encoded-value>
        # We accept any charset; default to UTF-8 when missing or unknown.
        $rfc5987 = [regex]::Match(
            $ContentDisposition,
            "filename\*\s*=\s*(?<charset>[^']*)'(?<lang>[^']*)'(?<value>[^;]+)",
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )
        if ($rfc5987.Success) {
            $charsetName = $rfc5987.Groups['charset'].Value
            $encodedValue = $rfc5987.Groups['value'].Value.Trim()
            $encoding = [System.Text.Encoding]::UTF8
            if (-not [string]::IsNullOrWhiteSpace($charsetName)) {
                try {
                    $encoding = [System.Text.Encoding]::GetEncoding($charsetName)
                } catch {
                    $encoding = [System.Text.Encoding]::UTF8
                }
            }
            try {
                $parsed = [System.Web.HttpUtility]::UrlDecode($encodedValue, $encoding)
            } catch {
                $parsed = [System.Uri]::UnescapeDataString($encodedValue)
            }
        }

        # Fallback to plain filename=
        if ([string]::IsNullOrWhiteSpace($parsed)) {
            $plain = [regex]::Match(
                $ContentDisposition,
                'filename\s*=\s*(?<quoted>"(?<q>[^"]*)"|(?<raw>[^;]+))',
                [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
            )
            if ($plain.Success) {
                $value = if ($plain.Groups['q'].Success) { $plain.Groups['q'].Value } else { $plain.Groups['raw'].Value }
                $parsed = $value.Trim()
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($parsed)) {
        $parsed = $DefaultName
    }

    # Strip any directory components — only keep the leaf name.
    $parsed = [System.IO.Path]::GetFileName($parsed)

    # Replace control + cross-platform-unsafe characters with underscore.
    # Reserved on Windows: < > : " | ? * \ /  plus 0x00-0x1F.
    $unsafe = '[<>:"|?*\\/\x00-\x1F]'
    $parsed = [regex]::Replace($parsed, $unsafe, '_')

    # Trim trailing dots and spaces (illegal on Windows).
    $parsed = $parsed.Trim().TrimEnd('.', ' ')

    if ([string]::IsNullOrWhiteSpace($parsed)) {
        $parsed = $DefaultName
    }

    return $parsed
}
