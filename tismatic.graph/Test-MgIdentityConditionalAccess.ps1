function Test-MgIdentityConditionalAccess {
	[CmdletBinding()]
	param (
		[Parameter(Mandatory)]
		[string]$UserId,
		# Accepts GUID or UPN
		[string[]]$IncludeApplications,
		# Override app set (≈ All cloud apps)
		[switch]$AppliedOnly # Only return policies that would apply
	)
		
	begin {
		if (-not (Get-Command Invoke-MgGraphRequest -ErrorAction SilentlyContinue)) {
			throw "Invoke-MgGraphRequest not found. Install/Import Microsoft.Graph."
		}
			
		$needScopes = @('Policy.Read.ConditionalAccess', 'Policy.Read.All') # CA What-If + per-user MFA reqs
		$ctx = Get-MgContext -ErrorAction SilentlyContinue
		$haveScopes = @()
		if ($ctx -and $ctx.Scopes) {
			$haveScopes = @($ctx.Scopes)
		}
		if ($needScopes | Where-Object {
				$haveScopes -notcontains $_
			}) {
			Connect-MgGraph -Scopes $needScopes | Out-Null
		}
			
		if (-not $IncludeApplications) {
			# Default set ≈ "All cloud apps"
			$IncludeApplications = @(
				'00000003-0000-0000-c000-000000000000', # Microsoft Graph
				'00000003-0000-0ff1-ce00-000000000000', # SharePoint / OneDrive
				'00000002-0000-0ff1-ce00-000000000000', # Exchange Online
				'1fec8e78-bce4-4aaf-ab1b-5451cc387264', # Microsoft Teams
				'797f4846-ba00-4fd7-ba43-dac1f8f63013' # Azure Resource Manager
			)
		}
			
		function Resolve-UserId {
			param ([string]$InputObject)
			try {
				[void][guid]$InputObject
				return $InputObject # already a GUID
			}
			catch {
				$u = Invoke-MgGraphRequest -Method GET -Uri ("https://graph.microsoft.com/v1.0/users/{0}?`$select=id,userPrincipalName" -f [uri]::EscapeDataString($InputObject))
				if (-not $u.id) {
					throw "User '$InputObject' not found."
				}
				return $u.id
			}
		}
	}
		
	process {
		$resolvedId = Resolve-UserId -InputObject $UserId
			
		# ----- Conditional Access What-If (v1.0) -----
		$evaluateBody = @{
			signInIdentity      = @{
				'@odata.type' = '#microsoft.graph.userSignIn'; userId = $resolvedId
			}
			signInContext       = @{
				'@odata.type' = '#microsoft.graph.applicationContext'; includeApplications = @($IncludeApplications)
			}
			signInConditions    = @{
			} # users-only; keeps it simple unless you need more conditions
			appliedPoliciesOnly = [bool]$AppliedOnly
		}
		$evalJson = $evaluateBody | ConvertTo-Json -Depth 10
		$evalResp = Invoke-MgGraphRequest -Method POST -Uri 'https://graph.microsoft.com/v1.0/identity/conditionalAccess/evaluate' -Body $evalJson -ContentType 'application/json'
		$items = if ($evalResp.value) {
			$evalResp.value
		}
		else {
			@($evalResp)
		}
			
		$applied, $notApplied = @(), @()
		foreach ($p in $items) {
			$grant = $p.grantControls
			$hasMfa = $false
			if ($null -ne $grant) {
				if ($grant.builtInControls -and ($grant.builtInControls -contains 'mfa')) {
					$hasMfa = $true
				}
				if ($grant.authenticationStrength) {
					$hasMfa = $true
				}
			}
			if ($p.policyApplies -eq $true) {
				$applied += [PSCustomObject]@{
					DisplayName   = $p.displayName
					Id            = $p.id
					State         = $p.state
					MFA           = $(if ($hasMfa) {
							'Yes'
						}
						else {
							'No'
						})
					GrantControls = @($grant.builtInControls) -join ',' + $(if ($grant.authenticationStrength) {
							',authStrength'
						}
						else {
							''
						})
				}
			}
			else {
				$notApplied += [PSCustomObject]@{
					DisplayName = $p.displayName
					Id          = $p.id
					State       = $p.state
					Reasons     = @($p.analysisReasons) -join ', '
				}
			}
		}
		$mfaByCa = [bool]($applied | Where-Object {
				$_.MFA -eq 'Yes'
			})
			
		# ----- Per-user MFA (beta) -----
		$req = Invoke-MgGraphRequest -Method GET -Uri ("https://graph.microsoft.com/beta/users/{0}/authentication/requirements" -f $resolvedId)
		$perUserMfaState = $req.perUserMfaState # disabled | enabled | enforced
		$perUserMfaEnabled = $false
		if ($perUserMfaState -in @('enabled', 'enforced')) {
			$perUserMfaEnabled = $true
		}
		if ($mfaByCa) {
			$MFAEnforcedFrom = "Conditional Access"
		}
		if ($perUserMfaEnabled) {
			$MFAEnforcedFrom = "Per-user MFA"
		}
		if ($perUserMfaEnabled -and $mfaByCa) {
			$MFAEnforcedFrom = "Conditional Access + Per-user MFA"
		}
		# ----- Combined verdict -----
		[PSCustomObject]@{
			UserInput              = $UserId
			UserObjectId           = $resolvedId
			AppsTested             = $IncludeApplications
			PerUserMfaState        = $perUserMfaState
			MfaRequiredByAnyPolicy = $mfaByCa
			MfaEnforced            = ($mfaByCa -or $perUserMfaEnabled) # your requested logic
			MFAEnforcedFrom        = $MFAEnforcedFrom
			AppliedPolicies        = $applied | Sort-Object DisplayName
			NotAppliedPolicies     = $notApplied | Sort-Object DisplayName
		}
	}
}