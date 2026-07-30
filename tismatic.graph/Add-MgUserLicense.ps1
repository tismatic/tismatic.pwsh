function Add-MgUserLicense {
	[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
	param (
		[Parameter(
			Mandatory,
			ValueFromPipeline,
			ValueFromPipelineByPropertyName,
			Position = 0
		)]
		[Alias('Id', 'UserPrincipalName', 'UPN')]
		[string[]]$UserId,

		[Parameter(Mandatory, Position = 1)]
		[ArgumentCompleter({
				param(
					$CommandName,
					$ParameterName,
					$WordToComplete,
					$CommandAst,
					$FakeBoundParameters
				)

				try {
					$cache = Get-Variable -Name MgLicenseProductCompletionCache -Scope Script -ValueOnly -ErrorAction SilentlyContinue

					if (-not $cache -or $cache.ExpiresAt -lt [datetime]::UtcNow) {
						$cache = [pscustomobject]@{
							ExpiresAt = [datetime]::UtcNow.AddMinutes(5)
							Products  = @(
								Get-MgLicenseSummary -Exclude $null -ErrorAction Stop
							)
						}

						Set-Variable -Name MgLicenseProductCompletionCache -Scope Script -Value $cache
					}

					$trimCharacters = [char[]](39, 34)
					$searchText = $WordToComplete.Trim($trimCharacters)

					$cache.Products |
					Where-Object {
						$displayName = [string]$_.Product_Display_Name
						$stringId = [string]$_.String_Id

						$displayName.StartsWith(
							$searchText,
							[System.StringComparison]::OrdinalIgnoreCase
						) -or
						$stringId.StartsWith(
							$searchText,
							[System.StringComparison]::OrdinalIgnoreCase
						)
					} |
					Sort-Object Product_Display_Name, String_Id |
					ForEach-Object {
						$completionValue = if ($_.Product_Display_Name) {
							[string]$_.Product_Display_Name
						}
						elseif ($_.String_Id) {
							[string]$_.String_Id
						}
						else {
							[string]$_.GUID
						}

						$completionText = "'$($completionValue.Replace("'", "''"))'"

						$listItemText = if ($_.Available -gt 0) {
							"$completionValue [$($_.Available) available]"
						}
						else {
							"$completionValue [None available]"
						}

						$toolTipLines = @(
							$completionValue
							"SKU: $($_.String_Id)"
							"Available: $($_.Available)"
							"Used: $($_.Used)"
							"Total: $($_.Total)"
							"SKU ID: $($_.GUID)"
						)

						[System.Management.Automation.CompletionResult]::new(
							$completionText,
							$listItemText,
							[System.Management.Automation.CompletionResultType]::ParameterValue,
							($toolTipLines -join [Environment]::NewLine)
						)
					}
				}
				catch {
					return
				}
			})]
		[string]$ProductName
	)

	begin {
		$Products = @(
			Get-MgLicenseSummary -Exclude $null -Search $ProductName
		)

		# Prefer an exact friendly-name, SKU-name, or GUID match over partial matches.
		$ExactProducts = @(
			$Products |
			Where-Object {
				$_.Product_Display_Name -eq $ProductName -or
				$_.String_Id -eq $ProductName -or
				[string]$_.GUID -eq $ProductName
			}
		)

		if ($ExactProducts.Count -gt 0) {
			$Products = $ExactProducts
		}

		if ($Products.Count -eq 0) {
			throw "Could not find a license product matching '$ProductName'."
		}

		if ($Products.Count -gt 1) {
			$ProductMatches = $Products |
			ForEach-Object {
				if ($_.Product_Display_Name) {
					"$($_.Product_Display_Name) [$($_.String_Id)]"
				}
				elseif ($_.String_Id) {
					$_.String_Id
				}
				else {
					$_.GUID
				}
			}

			throw "Multiple license products matched '$ProductName': $($ProductMatches -join ', ')"
		}

		$Product = $Products[0]

		try {
			$SkuId = [guid]$Product.GUID
		}
		catch {
			throw "The matched product does not contain a valid GUID: '$($Product.GUID)'."
		}

		$ResolvedProductName = if ($Product.Product_Display_Name) {
			$Product.Product_Display_Name
		}
		elseif ($Product.String_Id) {
			$Product.String_Id
		}
		else {
			$ProductName
		}

		$RemainingAvailable = [int]$Product.Available
	}

	process {
		foreach ($CurrentUserId in $UserId) {
			$userProperties = @(
				'Id'
				'DisplayName'
				'UserPrincipalName'
				'LicenseAssignmentStates'
			)

			$userParameters = @{
				UserId      = $CurrentUserId
				Property    = $userProperties
				ErrorAction = 'Stop'
			}

			try {
				$User = Get-MgUser @userParameters
			}
			catch {
				Write-Error "Unable to find user '$CurrentUserId': $($_.Exception.Message)"
				continue
			}

			$ExistingAssignments = @(
				$User.LicenseAssignmentStates |
				Where-Object {
					[string]$_.SkuId -eq [string]$SkuId
				}
			)

			if ($ExistingAssignments.Count -gt 0) {
				$DirectAssignment = @(
					$ExistingAssignments |
					Where-Object { -not $_.AssignedByGroup }
				)

				$GroupAssignments = @(
					$ExistingAssignments |
					Where-Object { $_.AssignedByGroup }
				)

				$AssignmentType = if (
					$DirectAssignment.Count -gt 0 -and
					$GroupAssignments.Count -gt 0
				) {
					'Direct and Group'
				}
				elseif ($DirectAssignment.Count -gt 0) {
					'Direct'
				}
				else {
					'Group'
				}

				[pscustomobject]@{
					PSTypeName        = 'MgUserLicenseResult'
					Action            = 'Add'
					Status            = 'AlreadyAssigned'
					UserPrincipalName = $User.UserPrincipalName
					DisplayName       = $User.DisplayName
					ProductName       = $ResolvedProductName
					SkuId             = $SkuId
					AssignmentType    = $AssignmentType
					Message           = "'$ResolvedProductName' is already assigned to $($User.UserPrincipalName)."
				}

				continue
			}

			if ($RemainingAvailable -le 0) {
				Write-Error "No licenses are available for '$ResolvedProductName'."
				continue
			}

			$Target = "$($User.UserPrincipalName) [$($User.Id)]"

			if (
				-not $PSCmdlet.ShouldProcess(
					$Target,
					"Assign license '$ResolvedProductName'"
				)
			) {
				continue
			}

			$addLicenses = @(
				@{
					SkuId = $SkuId
				}
			)

			$licenseParameters = @{
				UserId         = $User.Id
				AddLicenses    = $addLicenses
				RemoveLicenses = @()
				ErrorAction    = 'Stop'
			}

			try {
				$null = Set-MgUserLicense @licenseParameters
				$RemainingAvailable--

				[pscustomobject]@{
					PSTypeName        = 'MgUserLicenseResult'
					Action            = 'Add'
					Status            = 'Succeeded'
					UserPrincipalName = $User.UserPrincipalName
					DisplayName       = $User.DisplayName
					ProductName       = $ResolvedProductName
					SkuId             = $SkuId
					AssignmentType    = 'Direct'
					Message           = "Successfully assigned '$ResolvedProductName' to $($User.UserPrincipalName)."
				}
			}
			catch {
				Write-Error "Failed to assign '$ResolvedProductName' to $($User.UserPrincipalName): $($_.Exception.Message)"
			}
		}
	}
}


<# Old Function
 
function Add-MgUserLicense {
	[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
	param (
		[Parameter(
			Mandatory,
			ValueFromPipeline,
			ValueFromPipelineByPropertyName,
			Position = 0
		)]
		[Alias('Id', 'UserPrincipalName', 'UPN')]
		[string[]]$UserId,

		[Parameter(Mandatory, Position = 1)]
		[string]$ProductName
	)

	begin {
		$Products = @(
			Get-MgLicenseSummary -Exclude $null -Search $ProductName
		)

		if ($Products.Count -eq 0) {
			throw "Could not find a license product matching '$ProductName'."
		}

		if ($Products.Count -gt 1) {
			$ProductMatches = $Products |
			ForEach-Object {
				if ($_.ProductName) {
					$_.ProductName
				}
				elseif ($_.SkuPartNumber) {
					$_.SkuPartNumber
				}
				else {
					$_.Guid
				}
			}

			throw "Multiple license products matched '$ProductName': $($ProductMatches -join ', ')"
		}

		$Product = $Products[0]

		try {
			$SkuId = [guid]$Product.Guid
		}
		catch {
			throw "The matched product does not contain a valid Guid: '$($Product.Guid)'."
		}

		$ResolvedProductName = if ($Product.ProductName) {
			$Product.ProductName
		}
		elseif ($Product.SkuPartNumber) {
			$Product.SkuPartNumber
		}
		elseif ($Product.DisplayName) {
			$Product.DisplayName
		}
		else {
			$ProductName
		}

		$RemainingAvailable = [int]$Product.Available
	}

	process {
		foreach ($CurrentUserId in $UserId) {
			try {
				$User = Get-MgUser `
					-UserId $CurrentUserId `
					-Property Id, DisplayName, UserPrincipalName, LicenseAssignmentStates `
					-ErrorAction Stop
			}
			catch {
				Write-Error "Unable to find user '$CurrentUserId': $($_.Exception.Message)"
				continue
			}

			$ExistingAssignments = @(
				$User.LicenseAssignmentStates |
				Where-Object {
					[string]$_.SkuId -eq [string]$SkuId
				}
			)

			if ($ExistingAssignments.Count -gt 0) {
				$DirectAssignment = @(
					$ExistingAssignments |
					Where-Object { -not $_.AssignedByGroup }
				)

				$GroupAssignments = @(
					$ExistingAssignments |
					Where-Object { $_.AssignedByGroup }
				)

				$AssignmentType = if (
					$DirectAssignment.Count -gt 0 -and
					$GroupAssignments.Count -gt 0
				) {
					'Direct and Group'
				}
				elseif ($DirectAssignment.Count -gt 0) {
					'Direct'
				}
				else {
					'Group'
				}

				[pscustomobject]@{
					PSTypeName        = 'MgUserLicenseResult'
					Action            = 'Add'
					Status            = 'AlreadyAssigned'
					UserPrincipalName = $User.UserPrincipalName
					DisplayName       = $User.DisplayName
					ProductName       = $ResolvedProductName
					SkuId             = $SkuId
					AssignmentType    = $AssignmentType
					Message           = "'$ResolvedProductName' is already assigned to $($User.UserPrincipalName)."
				}

				continue
			}

			if ($RemainingAvailable -le 0) {
				Write-Error "No licenses are available for '$ResolvedProductName'."
				continue
			}

			$Target = "$($User.UserPrincipalName) [$($User.Id)]"

			if (
				-not $PSCmdlet.ShouldProcess(
					$Target,
					"Assign license '$ResolvedProductName'"
				)
			) {
				continue
			}

			try {
				$null = Set-MgUserLicense `
					-UserId $User.Id `
					-AddLicenses @(
					@{
						SkuId = $SkuId
					}
				) `
					-RemoveLicenses @() `
					-ErrorAction Stop

				$RemainingAvailable--

				[pscustomobject]@{
					PSTypeName        = 'MgUserLicenseResult'
					Action            = 'Add'
					Status            = 'Succeeded'
					UserPrincipalName = $User.UserPrincipalName
					DisplayName       = $User.DisplayName
					ProductName       = $ResolvedProductName
					SkuId             = $SkuId
					AssignmentType    = 'Direct'
					Message           = "Successfully assigned '$ResolvedProductName' to $($User.UserPrincipalName)."
				}
			}
			catch {
				Write-Error "Failed to assign '$ResolvedProductName' to $($User.UserPrincipalName): $($_.Exception.Message)"
			}
		}
	}
}
#>
