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


<# old function
function Add-MgUserLicense {
	param (
		$UserId,
		$ProductName
	)
		
	$Product = Get-MgLicenseSummary -Exclude $null -Search $ProductName
	$User = Get-MgUser -UserId $UserId
	if (!$User) {
		throw "$userid was not found."
	}
	if ($Product) {
		if ($product.Available -gt 0) {
			Set-MgUserLicense -UserId $UserId -AddLicenses @{
				skuid = $Product.guid
			} -RemoveLicenses @()
		}
		else {
			throw "Not enough licenses available for $ProductName"
		}
	}
	else {
		Write-Warning "Could not find a product for $ProductName"
	}
}
	#>