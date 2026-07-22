function Find-MGDevice {
    [CmdletBinding()]
    param(
        [Parameter(
            Mandatory,
            Position = 0,
            ValueFromRemainingArguments,
            ValueFromPipeline
        )]
        [string[]]$SearchString
    )

    process {
        $SearchText = ($SearchString -join ' ').Trim()

        Write-Verbose "Graph search: $Search"

        $Result = get-mgdevice -filter "(displayname eq '$SearchString')" -ExpandProperty registeredOwners -ConsistencyLevel eventual
        foreach ($Device in $Result) {
            try {
                $OS = "$($device.OperatingSystem) $(([version]$device.OperatingSystemVersion).Build -ge 22000 ? '11' : '10')"
            }
            catch {
                $OS = "$($device.OperatingSystem) $($device.OperatingSystemVersion)"
            }
            if ($Device) {

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
            else {
                Write-Warning "No device found matching '$SearchText'."
            }
        }
    }
}