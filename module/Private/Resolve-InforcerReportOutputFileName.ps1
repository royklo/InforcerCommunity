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

    # Guarantee we have *something* even if both ContentDisposition and DefaultName are unusable.
    if ([string]::IsNullOrWhiteSpace($parsed)) { $parsed = $DefaultName }
    if ([string]::IsNullOrWhiteSpace($parsed)) { $parsed = 'output' }

    # Strip any directory components — only keep the leaf name.
    $parsed = [System.IO.Path]::GetFileName($parsed)

    # Replace control + cross-platform-unsafe characters with underscore. Applied on every
    # platform (defense-in-depth so files written on macOS / Linux are safely copied to a
    # Windows host later). The set is the Windows-reserved character class plus 0x00-0x1F
    # control chars.
    $unsafe = '[<>:"|?*\\/\x00-\x1F]'
    $parsed = [regex]::Replace($parsed, $unsafe, '_')

    # Trim trailing dots and spaces (illegal on Windows). Avoid stripping the only dot
    # in the name — "report." (which would otherwise eat the extension separator) is
    # preserved when the name has actual non-dot content.
    $beforeTrim = $parsed
    $candidate = $parsed.Trim().TrimEnd('.', ' ')
    $beforeTrimStripped = $beforeTrim.Trim().Trim('.', ' ')
    if ($candidate.Length -eq 0) {
        # Path was entirely dots/spaces — fall through to default.
        $parsed = ''
    } elseif (-not $candidate.Contains('.') -and $beforeTrimStripped.Length -gt 0 -and $beforeTrim.Trim() -ne $candidate) {
        # Trim removed a meaningful trailing dot. Keep it.
        $parsed = $beforeTrim.Trim()
    } else {
        $parsed = $candidate
    }

    if ([string]::IsNullOrWhiteSpace($parsed)) { $parsed = 'output' }

    # Prefix Windows reserved device names (CON, PRN, AUX, NUL, COM1-9, LPT1-9 with or without
    # extension) to avoid OS-level redirection on Windows. Cross-platform safe; just a leading '_'.
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($parsed)
    $reserved = @('CON','PRN','AUX','NUL','COM1','COM2','COM3','COM4','COM5','COM6','COM7','COM8','COM9',
                  'LPT1','LPT2','LPT3','LPT4','LPT5','LPT6','LPT7','LPT8','LPT9')
    if ($reserved -contains $stem.ToUpperInvariant()) {
        $parsed = '_' + $parsed
    }

    # Cap leaf length at 200 chars (HFS+/APFS allows 255 bytes; multibyte names hit that fast).
    # Preserve the extension. Walk back from the cut point to a grapheme-cluster boundary so a
    # combining mark isn't orphaned from its base char.
    if ($parsed.Length -gt 200) {
        $ext = [System.IO.Path]::GetExtension($parsed)
        $base = [System.IO.Path]::GetFileNameWithoutExtension($parsed)
        $maxBase = 200 - $ext.Length
        if ($maxBase -lt 1) { $maxBase = 1 }
        $cut = [Math]::Min($base.Length, $maxBase)
        # Pull the cut back until it sits on a grapheme cluster boundary (handles combining marks).
        if ($cut -lt $base.Length) {
            $elements = [System.Globalization.StringInfo]::ParseCombiningCharacters($base)
            $safe = $cut
            foreach ($e in $elements) {
                if ($e -ge $cut) { break }
                $safe = $e
            }
            $cut = $safe
            if ($cut -lt 1) { $cut = 1 }
        }
        $parsed = $base.Substring(0, $cut) + $ext
    }

    return $parsed
}
