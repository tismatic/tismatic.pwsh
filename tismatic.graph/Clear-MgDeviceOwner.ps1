function Clear-MgDeviceOwner {
    [CmdletBinding(
        SupportsShouldProcess,
        ConfirmImpact = 'High',
        DefaultParameterSetName = 'ByName'
    )]
    param(
        [Parameter(Mandatory, ParameterSetName = 'ByName')]
        [ValidateNotNullOrEmpty()]
        [string]$DeviceName,

        [Parameter(Mandatory, ParameterSetName = 'ById')]
        [ValidateNotNullOrEmpty()]
        [string]$DeviceId,

        [Parameter()]
        [Alias('UserPrincipalName', 'UPN')]
        [ValidateNotNullOrEmpty()]
        [string]$UserId,

        [Parameter()]
        [switch]$ClearRegisteredUsers
    )

    try {
        $Device = if ($PSCmdlet.ParameterSetName -eq 'ById') {
            Get-MgDevice `
                -DeviceId $DeviceId `
                -Property Id, DisplayName, OperatingSystem, ApproximateLastSignInDateTime `
                -ErrorAction Stop
        }
        else {
            $EscapedDeviceName = $DeviceName.Replace("'", "''")
            $Devices = @(
                Get-MgDevice `
                    -Filter "displayName eq '$EscapedDeviceName'" `
                    -Property Id, DisplayName, OperatingSystem, ApproximateLastSignInDateTime `
                    -Top 2 `
                    -ErrorAction Stop
            )

            if ($Devices.Count -eq 0) {
                throw "No device was found with the name '$DeviceName'."
            }

            if ($Devices.Count -gt 1) {
                throw "Multiple devices were found with the name '$DeviceName'. Use -DeviceId instead."
            }

            $Devices[0]
        }

        $ResolvedUser = if ($UserId) {
            Get-MgUser `
                -UserId $UserId `
                -Property Id, DisplayName, UserPrincipalName `
                -ErrorAction Stop
        }

        $CurrentOwners = @(
            Get-MgDeviceRegisteredOwner `
                -DeviceId $Device.Id `
                -All `
                -ErrorAction Stop
        )

        $TargetOwners = if ($ResolvedUser) {
            @($CurrentOwners | Where-Object Id -EQ $ResolvedUser.Id)
        }
        else {
            $CurrentOwners
        }

        $TargetRegisteredUsers = @()
        if ($ClearRegisteredUsers) {
            $CurrentRegisteredUsers = @(
                Get-MgDeviceRegisteredUser `
                    -DeviceId $Device.Id `
                    -All `
                    -ErrorAction Stop
            )

            $TargetRegisteredUsers = if ($ResolvedUser) {
                @($CurrentRegisteredUsers | Where-Object Id -EQ $ResolvedUser.Id)
            }
            else {
                $CurrentRegisteredUsers
            }
        }

        $Changes = [System.Collections.Generic.List[object]]::new()

        foreach ($Owner in $TargetOwners) {
            $Change = [ordered]@{
                Relationship      = 'RegisteredOwner'
                DirectoryObjectId = $Owner.Id
                Status            = 'Failed'
                Error             = $null
            }

            try {
                if ($PSCmdlet.ShouldProcess(
                    "$($Device.DisplayName) [$($Device.Id)]",
                    "Remove registered owner '$($Owner.Id)'"
                )) {
                    Remove-MgDeviceRegisteredOwnerByRef `
                        -DeviceId $Device.Id `
                        -DirectoryObjectId $Owner.Id `
                        -Confirm:$false `
                        -ErrorAction Stop

                    $Change.Status = 'Removed'
                }
                else {
                    $Change.Status = if ($WhatIfPreference) {
                        'WhatIf'
                    }
                    else {
                        'Skipped'
                    }
                }
            }
            catch {
                $Change.Error = $_.Exception.Message
            }

            $Changes.Add([pscustomobject]$Change)
        }

        foreach ($RegisteredUser in $TargetRegisteredUsers) {
            $Change = [ordered]@{
                Relationship      = 'RegisteredUser'
                DirectoryObjectId = $RegisteredUser.Id
                Status            = 'Failed'
                Error             = $null
            }

            try {
                if ($PSCmdlet.ShouldProcess(
                    "$($Device.DisplayName) [$($Device.Id)]",
                    "Remove registered user '$($RegisteredUser.Id)'"
                )) {
                    Remove-MgDeviceRegisteredUserByRef `
                        -DeviceId $Device.Id `
                        -DirectoryObjectId $RegisteredUser.Id `
                        -Confirm:$false `
                        -ErrorAction Stop

                    $Change.Status = 'Removed'
                }
                else {
                    $Change.Status = if ($WhatIfPreference) {
                        'WhatIf'
                    }
                    else {
                        'Skipped'
                    }
                }
            }
            catch {
                $Change.Error = $_.Exception.Message
            }

            $Changes.Add([pscustomobject]$Change)
        }

        $Status = if ($Changes.Count -eq 0) {
            'NoMatch'
        }
        elseif (@($Changes | Where-Object Status -NE 'Failed').Count -eq 0) {
            'Failed'
        }
        elseif ($Changes.Status -contains 'Failed') {
            'PartiallyFailed'
        }
        elseif ($Changes.Status -contains 'WhatIf') {
            'WhatIf'
        }
        elseif ($Changes.Status -contains 'Skipped') {
            'Skipped'
        }
        else {
            'Cleared'
        }

        [pscustomobject]@{
            DeviceName              = $Device.DisplayName
            DeviceId                = $Device.Id
            OperatingSystem         = $Device.OperatingSystem
            ApproximateLastSignIn   = $Device.ApproximateLastSignInDateTime
            TargetUserId            = $ResolvedUser.Id
            TargetUserPrincipalName = $ResolvedUser.UserPrincipalName
            Status                  = $Status
            Changes                 = @($Changes)
        }
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
