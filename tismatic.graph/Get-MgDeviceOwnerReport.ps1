function Get-MgDeviceOwnerReport {
    $Result = get-mgdevice -all -ExpandProperty registeredOwners
    foreach ($Device in $Result) {
        if ($Device -and $device.OperatingSystem -eq 'Windows') {
            try {
                $OS = "$($device.OperatingSystem) $(([version]$device.OperatingSystemVersion).Build -ge 22000 ? '11' : '10')"
            }
            catch {
                $OS = "$($device.OperatingSystem) $($device.OperatingSystemVersion)"
            }
            [pscustomobject]@{
                Id                            = $device.Id
                Displayname                   = $device.DisplayName
                OS                            = $OS
                OwnerDisplayName              = @($device.RegisteredOwners.AdditionalProperties.displayName) -join ","
                OwnerUserPrincipalName        = @($device.RegisteredOwners.AdditionalProperties.userPrincipalName) -join ","
                OwnerEmailAddress             = @($device.RegisteredOwners.AdditionalProperties.mail) -join ","
                OwnerMobilePhone              = @($device.RegisteredOwners.AdditionalProperties.mobilePhone) -join ","
                OwnerADAccountName            = @($device.RegisteredOwners.AdditionalProperties.onPremisesSamAccountName) -join ","
                OwnerAdDomain                 = @($device.RegisteredOwners.AdditionalProperties.onPremisesDomainName) -join ","
                ApproximateLastSignInDateTime = $device.ApproximateLastSignInDateTime
                TrustType                     = $device.TrustType
            }
        }
    }
}