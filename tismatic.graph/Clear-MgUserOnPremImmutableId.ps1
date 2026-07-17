function Clear-MgUserOnPremImmutableId {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$UserId
	)
		
	# Build the PATCH URI
	$uri = "https://graph.microsoft.com/v1.0/users/$UserId"
		
	# Body with a JSON null for onPremisesImmutableId
	$body = @{
		onPremisesImmutableId = $null
	} | ConvertTo-Json
		
	# Execute the PATCH
	Invoke-MgGraphRequest -Method PATCH -Uri $uri -Body $body
}