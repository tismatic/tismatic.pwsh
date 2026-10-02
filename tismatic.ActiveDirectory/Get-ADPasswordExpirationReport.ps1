function Get-ADPasswordExpirationReport {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory = $true)]
		[int]$Days,
		[Parameter(Mandatory = $false)]
		[string]$Server
	)
		
	$today = Get-Date
	$expireCutoff = $today.AddDays($Days)
		
	$params = @{
		Filter     = "*"
		Properties = "msDS-UserPasswordExpiryTimeComputed", "PasswordNeverExpires", "Enabled", "UserPrincipalName"
	}
		
	if ($PSBoundParameters.ContainsKey('Server')) {
		$params['Server'] = $Server
	}
		
	Get-ADUser @params |
	Where-Object {
		$_.Enabled -eq $true -and
		$_.PasswordNeverExpires -eq $false -and
		$null -ne $_."msDS-UserPasswordExpiryTimeComputed"
	} |
	Select-Object Name, SamAccountName, UserPrincipalName,
	@{
		Name = "PasswordExpiryDate"; Expression = {
			[datetime]::FromFileTime($_."msDS-UserPasswordExpiryTimeComputed")
		}
	} |
	Where-Object {
		$_.PasswordExpiryDate -le $expireCutoff -and $_.PasswordExpiryDate -ge $today
	}
}