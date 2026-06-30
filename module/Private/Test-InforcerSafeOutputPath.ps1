function Test-InforcerSafeOutputPath {
    <#
    .SYNOPSIS
        Refuses output paths that point at known OS / system directories (Private helper).
    .DESCRIPTION
        Defense-in-depth against server-controlled filenames + user-supplied -OutputPath
        combining to write into protected locations. The Reports API's Content-Disposition
        filename is sanitized to a leaf name (no traversal), but if the user passes
        -OutputPath /etc and the server returns filename="passwd", we should refuse.

        Compares the canonical (resolved) path against a per-platform deny list. Returns
        $true when the path is safe; throws a terminating error when it isn't.

        Out of scope: this is not a full ACL check. We don't try to determine whether the
        user has write permission to the directory — only whether the directory is one we
        know the module should never write to.
    .PARAMETER Path
        Directory the user passed via -OutputPath. May not exist yet.
    .OUTPUTS
        System.Boolean — always $true on success; throws otherwise.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { return $true }

    # Resolve to canonical absolute path. GetFullPath handles `..` and symlinks-as-text but
    # does NOT follow filesystem symlinks; that's adequate for our deny check (caller can't
    # use `..` to escape the leaf restriction since the path goes through GetFullPath).
    $resolved = $null
    try {
        $resolved = [System.IO.Path]::GetFullPath($Path)
    } catch {
        # Malformed paths fall through — let downstream creation logic surface the error.
        return $true
    }
    if ([string]::IsNullOrWhiteSpace($resolved)) { return $true }

    $normalized = $resolved.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)

    # Platform-aware deny prefixes. On Windows we resolve %WINDIR% / %PROGRAMFILES% from env.
    $denyPrefixes = @()
    if ($IsWindows -or [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
        foreach ($envName in 'WINDIR','SystemRoot','PROGRAMFILES','PROGRAMFILES(X86)','PROGRAMDATA') {
            $v = [System.Environment]::GetEnvironmentVariable($envName)
            if ($v) { $denyPrefixes += $v.TrimEnd('\','/') }
        }
        # Plus the fixed roots.
        $denyPrefixes += @('C:\Windows','C:\Program Files','C:\Program Files (x86)','C:\ProgramData')
    } else {
        # macOS / Linux — block system directories. Don't block /tmp or /var/folders.
        $denyPrefixes += @('/etc','/usr','/bin','/sbin','/boot','/lib','/lib32','/lib64','/System','/Library/System')
    }

    foreach ($deny in $denyPrefixes) {
        if ([string]::IsNullOrWhiteSpace($deny)) { continue }
        $denyNorm = $deny.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
        # Case-insensitive on Windows, case-sensitive on Unix — match OS behavior.
        $cmp = if ($IsWindows -or [System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
            [System.StringComparison]::OrdinalIgnoreCase
        } else {
            [System.StringComparison]::Ordinal
        }
        if ($normalized.StartsWith($denyNorm, $cmp) -and
            ($normalized.Length -eq $denyNorm.Length -or
             $normalized[$denyNorm.Length] -eq [System.IO.Path]::DirectorySeparatorChar -or
             $normalized[$denyNorm.Length] -eq [System.IO.Path]::AltDirectorySeparatorChar)) {
            throw "Refusing to write under '$denyNorm' (system / OS directory). Choose a different -OutputPath."
        }
    }

    return $true
}
