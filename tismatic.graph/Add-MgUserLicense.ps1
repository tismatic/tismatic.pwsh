function Remove-MgUserLicense {
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
            $Matches = $Products |
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

            throw "Multiple license products matched '$ProductName': $($Matches -join ', ')"
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

            $Assignments = @(
                $User.LicenseAssignmentStates |
                    Where-Object {
                        [string]$_.SkuId -eq [string]$SkuId
                    }
            )

            if ($Assignments.Count -eq 0) {
                [pscustomobject]@{
                    PSTypeName        = 'MgUserLicenseResult'
                    Action            = 'Remove'
                    Status            = 'NotAssigned'
                    UserPrincipalName = $User.UserPrincipalName
                    DisplayName       = $User.DisplayName
                    ProductName       = $ResolvedProductName
                    SkuId             = $SkuId
                    AssignmentType    = $null
                    Message           = "'$ResolvedProductName' is not assigned to $($User.UserPrincipalName)."
                }

                continue
            }

            $DirectAssignments = @(
                $Assignments |
                    Where-Object { -not $_.AssignedByGroup }
            )

            $GroupAssignments = @(
                $Assignments |
                    Where-Object { $_.AssignedByGroup }
            )

            $GroupIds = @(
                $GroupAssignments.AssignedByGroup |
                    Where-Object { $_ } |
                    Sort-Object -Unique
            )

            if ($DirectAssignments.Count -eq 0) {
                [pscustomobject]@{
                    PSTypeName        = 'MgUserLicenseResult'
                    Action            = 'Remove'
                    Status            = 'InheritedFromGroup'
                    UserPrincipalName = $User.UserPrincipalName
                    DisplayName       = $User.DisplayName
                    ProductName       = $ResolvedProductName
                    SkuId             = $SkuId
                    AssignmentType    = 'Group'
                    AssignedByGroup   = $GroupIds
                    Message           = "'$ResolvedProductName' is inherited from a group and cannot be removed directly from the user."
                }

                continue
            }

            $Target = "$($User.UserPrincipalName) [$($User.Id)]"

            if (
                -not $PSCmdlet.ShouldProcess(
                    $Target,
                    "Remove license '$ResolvedProductName'"
                )
            ) {
                continue
            }

            try {
                $null = Set-MgUserLicense `
                    -UserId $User.Id `
                    -AddLicenses @() `
                    -RemoveLicenses @($SkuId) `
                    -ErrorAction Stop

                $RemainsAssignedByGroup = $GroupAssignments.Count -gt 0

                $Message = if ($RemainsAssignedByGroup) {
                    "Successfully removed the direct '$ResolvedProductName' assignment from $($User.UserPrincipalName). The license remains inherited from a group."
                }
                else {
                    "Successfully removed '$ResolvedProductName' from $($User.UserPrincipalName)."
                }

                [pscustomobject]@{
                    PSTypeName            = 'MgUserLicenseResult'
                    Action                = 'Remove'
                    Status                = 'Succeeded'
                    UserPrincipalName     = $User.UserPrincipalName
                    DisplayName           = $User.DisplayName
                    ProductName           = $ResolvedProductName
                    SkuId                 = $SkuId
                    AssignmentType        = 'Direct'
                    RemainsAssignedByGroup = $RemainsAssignedByGroup
                    AssignedByGroup       = $GroupIds
                    Message               = $Message
                }
            }
            catch {
                Write-Error "Failed to remove '$ResolvedProductName' from $($User.UserPrincipalName): $($_.Exception.Message)"
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