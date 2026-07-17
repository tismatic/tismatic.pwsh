function Get-MicrosoftOfficeProduct {
	[CmdletBinding(DefaultParameterSetName = 'Search')]
	param (
		[string[]]$SkuPartNumber,
		[Parameter(ValueFromPipeline)]
		[string[]]$SkuId
	)
		
	begin {
		if (-not $Global:MSProductNamesCSV) {
			$CSVUri = "https://download.microsoft.com/download/e/3/e/e3e9faf2-f28b-490a-9ada-c6089a1fc5b0/Product%20names%20and%20service%20plan%20identifiers%20for%20licensing.csv"
			$Global:MSProductNamesCSV = Invoke-RestMethod -Uri $CSVUri | ConvertFrom-Csv
		}
	}
		
	process {
		$results = @()
			
		if ($SkuPartNumber) {
			$hashTable = $Global:MSProductNamesCSV | Group-Object -Property String_Id -AsHashTable
			foreach ($sku in $SkuPartNumber) {
				$result = $hashTable.$sku
				$result = ($result.count -gt 1 ? $result[0] : $result)
				if ($result) {
					$results += $result
				}
			}
		}
		elseif ($SkuId) {
			$hashTable = $Global:MSProductNamesCSV | Group-Object -Property GUID -AsHashTable
			foreach ($id in $SkuId) {
				$result = $hashTable.$id
				$result = ($result.count -gt 1 ? $result[0] : $result)
				if ($result) {
					$results += $result
				}
			}
		}
		else {
			$Global:MSProductNamesCSV
		}
		foreach ($item in $results) {
			[pscustomobject]@{
				SkuName       = $item.Product_Display_Name
				SkuPartNumber = $item.String_Id
				SkuId         = $item.GUID
			}
		}
	}
}