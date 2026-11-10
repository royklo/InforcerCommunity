function ConvertTo-InforcerUserBody {
    <#
    .SYNOPSIS
        Builds the userProfile part of a create or update body from bound parameters (Private helper).
    .DESCRIPTION
        Only parameters the caller passed are included, so an update leaves every other field as it is
        (JSON Merge Patch). An empty string or an empty array becomes null, which clears the field.
        Parameter names map to the API names by lowercasing the first letter.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.IDictionary[string, object]]$BoundParameters
    )

    $fields = 'AccountEnabled', 'DisplayName', 'MailNickname', 'UserPrincipalName', 'GivenName', 'Surname',
        'JobTitle', 'Department', 'OfficeLocation', 'StreetAddress', 'City', 'State', 'PostalCode', 'Country',
        'MobilePhone', 'UsageLocation', 'PreferredLanguage', 'CompanyName', 'EmployeeId', 'EmployeeType',
        'Mail', 'BusinessPhones', 'OtherMails', 'ManagerId'

    $body = [ordered]@{}
    foreach ($name in $fields) {
        if (-not $BoundParameters.ContainsKey($name)) { continue }
        $value = $BoundParameters[$name]
        if ($value -is [array]) {
            $value = @($value | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            if ($value.Count -eq 0) { $value = $null }
        } elseif ($value -is [string] -and $value -eq '') {
            $value = $null
        }
        $body[$name.Substring(0, 1).ToLowerInvariant() + $name.Substring(1)] = $value
    }
    $body
}
