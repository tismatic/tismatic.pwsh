function Get-MUCatalogDownloadLink {
    param(
        [Parameter(ValueFromPipeline)]
        $UpdateID = ""
    )
    process {
        $body = @{
            Size      = 0
            Languages = "en-US"
            uidInfo   = $UpdateID
            updateID  = $UpdateID
        } | ConvertTo-Json -Compress

        $EncodedBody = @{ updateIDs = "[$body]" }
        $WebRequestResponse = Invoke-RestMethod -Method POST "https://www.catalog.update.microsoft.com/DownloadDialog.aspx" -Body $EncodedBody 
        
        [regex]::Matches($WebRequestResponse, "http.*com/[^']+")[0].value 
    }
}