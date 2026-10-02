function Search-MUCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Query,

        [int]$MaxAttempts = 20
    )

    $attempts = 0
    $results = $null
    $encodedQuery = [uri]::EscapeDataString($Query)

    do {
        try {
            $results = Invoke-WebRequest -Uri "https://www.catalog.update.microsoft.com/Search.aspx?q=$encodedQuery" -UserAgent Chrome -UseBasicParsing
        }
        catch {
            $attempts++

            if ($attempts -lt $MaxAttempts) {
                Write-Host "Request attempt to Microsoft Update Catalog failed. Attempt $attempts of $MaxAttempts." -ForegroundColor Yellow
            }
            else {
                Write-Host "Request attempt to Microsoft Update Catalog failed. Max attempts reached." -ForegroundColor Yellow
            }
        }
    }
    until ($results -or $attempts -ge $MaxAttempts)

    if (-not $results) {
        return
    }

    $pattern = '(?s)<a[^>]+id=["''](?<Id>[^"'']+)_link["''][^>]+class=["'']contentTextItemSpacerNoBreakLink["''][^>]*>(?<Text>.*?)</a>'

    foreach ($match in [regex]::Matches($results.Content, $pattern)) {
        $text = [System.Net.WebUtility]::HtmlDecode($match.Groups['Text'].Value)
        $text = ($text -replace '<[^>]+>', '' -replace '\s+', ' ').Trim()

        $kb = if ($text -match '\bKB\d+\b') {
            $Matches[0]
        }
        $DownloadURL = Get-CatalogDownloadlink -UpdateID $match.Groups['Id'].Value
        [pscustomobject]@{
            Id   = $match.Groups['Id'].Value
            Text = $text
            KB   = $kb
            DownloadURL = $DownloadURL
            FileSize   = Get-RemoteFileSize -URL $DownloadURL
        }
    }
}