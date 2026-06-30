function Get-InforcerHeaderValue {
    <#
    .SYNOPSIS
        Case-insensitive lookup of a single response header value (Private helper).
    .DESCRIPTION
        Header collection shapes vary across PowerShell hosts:
          * Invoke-RestMethod -ResponseHeadersVariable returns IDictionary<string,string[]>
          * Exception.Response.Headers / Invoke-WebRequest.Headers may be HttpResponseHeaders,
            WebHeaderCollection, or a plain hashtable

        Returns the first matching value as a string, or $null when absent.
    .PARAMETER Headers
        The header collection object. Accepts any of the shapes above. $null returns $null.
    .PARAMETER Name
        The header name (case-insensitive).
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory = $false, Position = 0)]
        $Headers,

        [Parameter(Mandatory = $true, Position = 1)]
        [string]$Name
    )

    if ($null -eq $Headers) { return $null }

    if ($Headers -is [System.Net.Http.Headers.HttpResponseHeaders] -or `
        $Headers -is [System.Net.Http.Headers.HttpHeaders]) {
        $values = $null
        if ($Headers.TryGetValues($Name, [ref]$values)) {
            return (($values | Select-Object -First 1) -as [string])
        }
        return $null
    }

    if ($Headers -is [System.Net.WebHeaderCollection]) {
        $value = $Headers[$Name]
        if ($value) { return ($value -as [string]) }
        return $null
    }

    if ($Headers -is [System.Collections.IDictionary]) {
        foreach ($key in $Headers.Keys) {
            if (($key -as [string]) -ieq $Name) {
                $value = $Headers[$key]
                if ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) {
                    return (($value | Select-Object -First 1) -as [string])
                }
                return ($value -as [string])
            }
        }
        return $null
    }

    if ($Headers.PSObject.Properties[$Name]) {
        $value = $Headers.PSObject.Properties[$Name].Value
        if ($value -is [System.Collections.IEnumerable] -and $value -isnot [string]) {
            return (($value | Select-Object -First 1) -as [string])
        }
        return ($value -as [string])
    }

    return $null
}
