function Get-MicrosoftOfficeProduct {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        $SearchString
    )

    begin {
        if (-not $Global:MSProductNamesCSV) {
            $CSVUri = "https://download.microsoft.com/download/e/3/e/e3e9faf2-f28b-490a-9ada-c6089a1fc5b0/Product%20names%20and%20service%20plan%20identifiers%20for%20licensing.csv"
            $Global:MSProductNamesCSV = (Invoke-RestMethod -Uri $CSVUri | ConvertFrom-Csv | select Product_Display_Name, String_Id, GUID -Unique)
        }
    }
		
    process {
        #$Global:MSProductNamesCSV | Where-Object { $_.Product_Display_Name -eq $SearchString -or $_.String_Id -eq $SearchString } | Select-Object -first 1
        $Global:MSProductNamesCSV | where {$_.Product_Display_Name -match $SearchString -or $_.String_Id -match $SearchString}
    }
}