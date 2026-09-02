function Resolve-ADIdentity {
	[CmdletBinding()]
	param (
		[Parameter(ValueFromPipeline)]
		$Identity,
		[string[]]$Properties = "Name"
	)
	if ($identity -isnot [string]) {
		$identity = "$($Identity.givenName) $($Identity.surname)"
	}
		
	$SearchLocations = Get-TrustedAdDomains
	#-split ((Get-Addomain).Dnsroot) + ((Get-ADtrust -Filter *).name)
	$jobs = $SearchLocations | ForEach-Object {
		$isReachable = [bool]$(try {
				(New-Object System.Net.Networkinformation.Ping).Send($_, 200)
			}
			catch {
			})
		if ($isReachable) {
			Start-ThreadJob -ScriptBlock {
				param (
					$Identity,
					$Server,
					$Properties
				)
				$ProgressPreference = 'SilentlyContinue'
				$filter = "(&(objectCategory=user)(objectClass=user)(|(userPrincipalName=$Identity)(samAccountName=$Identity)(distinguishedName=$Identity)(name=$Identity)))"
				try {
					get-aduser -LDAPFilter $filter -Server $Server -ErrorAction Stop -Properties $Properties
					# -filter "anr -eq '$Identity'"
				}
				catch {
						
				}
					
			} -ArgumentList $identity, $_, $Properties
		}
		else {
			Write-Verbose "Skipping $($_): Host unreachable"
		}
	}
	$Result = $jobs | Receive-Job -Wait -AutoRemoveJob
	#$jobs | Wait-Job | Out-Null
	#$Result = $Jobs | Receive-Job
	#$jobs | Remove-Job
		
	return $Result
}