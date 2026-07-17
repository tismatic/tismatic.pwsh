function Get-TenantIDfromUserID {
	param (
		$EmailOrDomain
	)
	$EmailDomain = $EmailOrDomain -replace ".*@"
	try {
		$openIdConfig = Invoke-RestMethod -UseBasicParsing "https://login.microsoftonline.com/$EmailDomain/.well-known/openid-configuration"
		$OpenIdConfig.authorization_endpoint.Split("/")[3]
	}
	catch {
		Write-error ($_.ErrorDetails.message | convertfrom-json).error_description
	}
}