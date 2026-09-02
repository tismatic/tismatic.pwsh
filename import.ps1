#gci -Recurse -File -Filter "*.ps1" -Exclude @("experemental_functions.ps1","thing.ps1","tmp.ps1") | % {. $($_.fullname)}


#try {add-mguserlicense -UserId foopa@apcisg.com -ProductName "Microsoft 365 E3" -ErrorAction Stop}catch{Write-logmsg $_ -LogLevel FAIL}