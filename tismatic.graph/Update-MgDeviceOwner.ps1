# .SYNOPSIS
# Updates the owner of a device in Azure AD using Microsoft Graph API.

function Update-MgDeviceOwner {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DeviceName,

        [Parameter(Mandatory)]
        [Alias('UserPrincipalName')]
        [ValidateNotNullOrEmpty()]
        [string]$UserId,

        [Parameter()]
        [switch]$ReplaceCurrentOwner,

        [Parameter()]
        [switch]$ReplaceRegisteredUsers
    )

    try {
        # Escape apostrophes for the OData filter.
        $escapedDeviceName = $DeviceName.Replace("'", "''")

        $devices = @(
            Get-MgDevice `
                -Filter "displayName eq '$escapedDeviceName'" `
                -Property Id, DisplayName, OperatingSystem, ApproximateLastSignInDateTime `
                -Top 2 `
                -ErrorAction Stop
        )

        if ($devices.Count -eq 0) {
            throw "No device was found with the name '$DeviceName'."
        }

        if ($devices.Count -gt 1) {
            throw "Multiple devices were found with the name '$DeviceName'. Use the device ID instead or ensure the name is unique."
        }

        $device = $devices[0]

        $user = Get-MgUser `
            -UserId $UserId `
            -Property Id, DisplayName, UserPrincipalName `
            -ErrorAction Stop

        $currentOwners = @(
            Get-MgDeviceRegisteredOwner `
                -DeviceId $device.Id `
                -All `
                -ErrorAction Stop
        )

        $currentRegisteredUsers = @(
            Get-MgDeviceRegisteredUser `
                -DeviceId $device.Id `
                -All `
                -ErrorAction Stop
        )

        $isCurrentOwner = $user.Id -in @($currentOwners.Id)
        $isRegisteredUser = $user.Id -in @($currentRegisteredUsers.Id)

        if (
            -not $isCurrentOwner -and
            $currentOwners.Count -gt 0 -and
            -not $ReplaceCurrentOwner
        ) {
            throw @"
Device '$($device.DisplayName)' already has a registered owner.

Use -ReplaceCurrentOwner to remove the existing owner and assign '$($user.UserPrincipalName)'.
"@
        }

        $removedOwnerIds = [System.Collections.Generic.List[string]]::new()
        $removedRegisteredUserIds = [System.Collections.Generic.List[string]]::new()
        $ownerAdded = $false
        $registeredUserAdded = $false

        if ($ReplaceCurrentOwner) {
            foreach ($owner in $currentOwners) {
                if ($owner.Id -eq $user.Id) {
                    continue
                }

                if ($PSCmdlet.ShouldProcess(
                    "$($device.DisplayName) [$($device.Id)]",
                    "Remove registered owner '$($owner.Id)'"
                )) {
                    Remove-MgDeviceRegisteredOwnerByRef `
                        -DeviceId $device.Id `
                        -DirectoryObjectId $owner.Id `
                        -Confirm:$false `
                        -ErrorAction Stop

                    $removedOwnerIds.Add($owner.Id)
                }
            }
        }

        if (-not $isCurrentOwner) {
            if ($PSCmdlet.ShouldProcess(
                "$($device.DisplayName) [$($device.Id)]",
                "Assign '$($user.UserPrincipalName)' as registered owner"
            )) {
                New-MgDeviceRegisteredOwnerByRef `
                    -DeviceId $device.Id `
                    -OdataId "https://graph.microsoft.com/v1.0/directoryObjects/$($user.Id)" `
                    -ErrorAction Stop |
                    Out-Null

                $ownerAdded = $true
            }
        }

        if ($ReplaceRegisteredUsers) {
            foreach ($registeredUser in $currentRegisteredUsers) {
                if ($registeredUser.Id -eq $user.Id) {
                    continue
                }

                if ($PSCmdlet.ShouldProcess(
                    "$($device.DisplayName) [$($device.Id)]",
                    "Remove registered user '$($registeredUser.Id)'"
                )) {
                    Remove-MgDeviceRegisteredUserByRef `
                        -DeviceId $device.Id `
                        -DirectoryObjectId $registeredUser.Id `
                        -Confirm:$false `
                        -ErrorAction Stop

                    $removedRegisteredUserIds.Add($registeredUser.Id)
                }
            }
        }

        if (-not $isRegisteredUser) {
            if ($PSCmdlet.ShouldProcess(
                "$($device.DisplayName) [$($device.Id)]",
                "Add '$($user.UserPrincipalName)' as registered user"
            )) {
                New-MgDeviceRegisteredUserByRef `
                    -DeviceId $device.Id `
                    -OdataId "https://graph.microsoft.com/v1.0/directoryObjects/$($user.Id)" `
                    -ErrorAction Stop |
                    Out-Null

                $registeredUserAdded = $true
            }
        }

        [pscustomobject]@{
            DeviceName               = $device.DisplayName
            DeviceId                 = $device.Id
            OperatingSystem          = $device.OperatingSystem
            ApproximateLastSignIn    = $device.ApproximateLastSignInDateTime
            OwnerDisplayName         = $user.DisplayName
            OwnerUserPrincipalName   = $user.UserPrincipalName
            OwnerId                  = $user.Id
            OwnerAdded               = $ownerAdded
            RemovedOwnerIds          = @($removedOwnerIds)
            RegisteredUserAdded      = $registeredUserAdded
            RemovedRegisteredUserIds = @($removedRegisteredUserIds)
        }
    }
    catch {
        $PSCmdlet.ThrowTerminatingError($_)
    }
}
<# OLD function 
function Update-MgDeviceOwner {
    param(
        $DeviceName,
        $UserId
    )
    $device = get-mgdevice -Filter "displayName eq '$DeviceName'" -ConsistencyLevel eventual | Select-Object Id, DisplayName, OperatingSystem, ApproximateLastSignInDateTime
    $user = Get-Mguser -userid $UserId

    if ($device -and $user) {
        try {
            New-MgDeviceRegisteredOwnerByRef -DeviceId $device.Id -OdataId "https://graph.microsoft.com/v1.0/directoryObjects/$($user.Id)"
        }
        catch {
            $_.Exception.Message
        }
        try {
            New-MgDeviceRegisteredUserByRef -DeviceId $device.Id -OdataId "https://graph.microsoft.com/v1.0/directoryObjects/$($user.Id)"
        }
        catch {
            $_.Exception.Message
        }
    }
    else {
        "Didn't set anything"
    }
}
#>
