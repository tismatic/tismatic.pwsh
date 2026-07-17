function Get-DomainFromDN {
    param (
        [Parameter(Mandatory)]
        [string]$DistinguishedName
    )

    ([regex]::Matches($DistinguishedName, '(?:^|,)DC=([^,]+)') |
    ForEach-Object { $_.Groups[1].Value }) -join '.'
}