# .SYNOPSIS
# Updates the owner of a device in Azure AD using Microsoft Graph API.
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