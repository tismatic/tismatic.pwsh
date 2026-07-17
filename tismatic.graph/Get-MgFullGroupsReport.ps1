function Get-MgFullGroupsReport {
	[CmdletBinding()]
	param (
		[string]$Path,
		[switch]$PassThru
	)
	# Grab groups with the props we'll use
	$groups = Get-MgGroup -All -Property `
		"id,displayName,mail,mailNickname,groupTypes,securityEnabled,mailEnabled,proxyAddresses,visibility,createdDateTime,renewedDateTime,onPremisesSyncEnabled,resourceProvisioningOptions,membershipRule,membershipRuleProcessingState,isAssignableToRole"
		
	$report = foreach ($g in $groups) {
		# Safely read provisioning options (Teams flag)
		$provisioning = @()
		if ($g.PSObject.Properties.Match('ResourceProvisioningOptions').Count -gt 0 -and $g.ResourceProvisioningOptions) {
			$provisioning = $g.ResourceProvisioningOptions
		}
		elseif ($g.AdditionalProperties -and $g.AdditionalProperties.ContainsKey('resourceProvisioningOptions')) {
			$provisioning = $g.AdditionalProperties['resourceProvisioningOptions']
		}
			
		$isUnified = $g.GroupTypes -contains 'Unified'
		$isDynamic = -not [string]::IsNullOrEmpty($g.MembershipRule) -and $g.MembershipRuleProcessingState -eq 'On'
		$hasTeam = $provisioning -contains 'Team'
			
		$GroupType = if ($isUnified) {
			if ($hasTeam) {
				'Team (Microsoft 365 Group)'
			}
			else {
				'Microsoft 365 Group'
			}
		}
		elseif ($g.MailEnabled -and $g.SecurityEnabled) {
			'Mail-enabled Security Group'
		}
		elseif ($g.SecurityEnabled) {
			if ($isDynamic) {
				'Dynamic Security Group'
			}
			else {
				'Security Group'
			}
		}
		elseif ($g.MailEnabled) {
			'Distribution Group'
		}
		else {
			'Security Group (no mail)'
		}
			
		$MembershipType = if ($isDynamic) {
			'Dynamic'
		}
		else {
			'Assigned'
		}
		$SyncType = if ($g.PSObject.Properties.Match('OnPremisesSyncEnabled').Count -gt 0 -and $g.OnPremisesSyncEnabled) {
			'Synced'
		}
		else {
			'Cloud-only'
		}
			
		# Primary SMTP (uppercase SMTP: entry)
		$PrimarySmtp = $null
		if ($g.ProxyAddresses) {
			$PrimarySmtp = ($g.ProxyAddresses | Where-Object {
					$_ -like 'SMTP:*'
				} | Select-Object -First 1) -replace '^SMTP:'
		}
			
		[pscustomobject]@{
			Id                 = $g.Id
			GroupType          = $GroupType
			MembershipType     = $MembershipType
			SyncType           = $SyncType
			DisplayName        = $g.DisplayName
			Mail               = $g.Mail
			PrimarySmtpAddress = $PrimarySmtp
			ProxyAddresses     = ($g.ProxyAddresses -join ',')
			MailNickname       = $g.MailNickname
			Visibility         = $g.Visibility
			SecurityEnabled    = $g.SecurityEnabled
			MailEnabled        = $g.MailEnabled
			IsAssignableToRole = $g.IsAssignableToRole
			CreatedDateTime    = $g.CreatedDateTime
			RenewedDateTime    = $g.RenewedDateTime
		}
	}
		
	$sorted = $report | Sort-Object GroupType, DisplayName
	if ($Path) {
		$sorted | Export-Csv $Path -NoTypeInformation -Encoding UTF8
	}
		
	if ($PassThru -or -not $Path) {
		$sorted
	}
}