function Get-MgReport {
	param (
		[ValidateSet(
			"getOffice365ActiveUserDetail",
			"getMailboxUsageDetail",
			"getMailboxUsageStorage",
			"getOneDriveUsageAccountDetail",
			"getSharePointSiteUsageDetail",
			"getEmailActivityUserDetail",
			"getEmailAppUsageUserDetail",
			"getTeamsUserActivityUserDetail",
			"getSkypeForBusinessActivityUserDetail",
			"getYammerActivityUserDetail"
		)]
		[string]$Report,
		[ValidateSet("D7", "D30", "D90", "D180")]
		$Period = "D30",
		$UserID,
		$OutCSVPath
	)
	$CSVData = (Invoke-MgRequest -Method GET -Uri "https://graph.microsoft.com/beta/reports/$Report(period='$Period')?`$format=application/json")
		
	if ($OutCSVPath) {
		$CSVData | Export-CSV -Path "$(Join-Path (resolve-path $OutCSVPath) -ChildPath $Report).csv"
	}
	elseif ($UserID) {
		return ($CSVData -match $UserID)
	}
	else {
		return $CSVData
	}
}