function Add-MgUserLicense {
	param (
		$UserId,
		$ProductName
	)
		
	$Product = Get-MgLicenseSummary -Exclude $null -Search $ProductName
	$User = Get-MgUser -UserId $UserId
	if (!$User) {
		throw "$userid was not found."
	}
	if ($Product) {
		if ($product.Available -gt 0) {
			Set-MgUserLicense -UserId $UserId -AddLicenses @{
				skuid = $Product.guid
			} -RemoveLicenses @()
		}
		else {
			throw "Not enough licenses available for $ProductName"
		}
	}
	else {
		Write-Warning "Could not find a product for $ProductName"
	}
}