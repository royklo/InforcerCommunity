function ConvertFrom-InforcerBase64Text {
    <#
    .SYNOPSIS
        Decodes a base64 string, returning it only when the result is real text.
    .DESCRIPTION
        Intune base64-encodes both text (scriptContent, rulesContent, the macOS/iOS
        .mobileconfig payload plist) and binary (hashedScriptContent digests, signed
        profiles) — so the property name alone is not a safe test. This decodes and
        verifies the bytes were text, returning $null otherwise so callers keep the
        base64 as-is rather than rendering mojibake.
    .PARAMETER Value
        The candidate base64 string.
    .OUTPUTS
        [string] The decoded text, or $null when the input isn't base64-encoded text.
    .EXAMPLE
        ConvertFrom-InforcerBase64Text -Value $policy.payload
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()]
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Length -le 20 -or $Value -match '\s') { return $null }

    try { $bytes = [System.Convert]::FromBase64String($Value) } catch { return $null }
    if ($bytes.Length -eq 0) { return $null }

    # Strict decode: invalid UTF-8 throws instead of silently yielding U+FFFD.
    try { $text = [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes) } catch { return $null }

    $text = $text.TrimStart([char]0xFEFF)
    if ($text -match '[\x00-\x08\x0B\x0C\x0E-\x1F]') { return $null }

    $text
}
