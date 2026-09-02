function Get-DomainFromDN {
    param (
        [Parameter(Mandatory,ValueFromPipeline)]
        [string]$DistinguishedName
    )

    ([regex]::Matches($DistinguishedName, '(?:^|,)DC=([^,]+)') |
    ForEach-Object { $_.Groups[1].Value }) -join '.'
}