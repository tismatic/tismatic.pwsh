function Get-MgOnPremObject {
	param (
		[Parameter(ValueFromPipeline)]
		$MGObject,
		[string[]]$Properties = "Name",
		[switch]$All
	)
	process {
		foreach ($Account in $MGObject) {
			if ($Account.onPremisesSamAccountName) {
				switch ($Account.Gettype().name) {
					"MicrosoftGraphgroup" {
						Get-ADGroup $Account.onPremisesSamAccountName -Server $Account.OnPremisesDomainName -Properties $Properties
					}
					"MicrosoftGraphUser" {
						Get-ADuser $Account.onPremisesSamAccountName -Server $Account.onPremisesDomainName -Properties $Properties
					}
						
					default {
						Get-ADObject -Filter "samaccountname -eq '$($Account.onPremisesSamAccountName)'" -Server $Account.onPremisesDomainName -Properties $Properties
					}
				}
			}
			else {
				if ($All) {
					$MGObject | Resolve-ADIdentity
				}
				else {
					$MGObject | Resolve-ADIdentity | Where-Object {($_.distinguishedname | Get-DomainFromDN ) -match $MGObject.userprincipalname}
				}
			}
		}
	}
}