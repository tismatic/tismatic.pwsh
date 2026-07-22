function Find-MgDeviceByUser {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$UserStartsWith,

        [ValidateSet(
            'DisplayName',
            'UserPrincipalName',
            'Either'
        )]
        [string]$MatchOn = 'Either'
    )

    $escapedValue = $UserStartsWith.Replace("'", "''")

    $filter = switch ($MatchOn) {
        'DisplayName' {
            "startswith(displayName, '$escapedValue')"
        }

        'UserPrincipalName' {
            "startswith(userPrincipalName, '$escapedValue')"
        }

        'Either' {
            @(
                "startswith(displayName, '$escapedValue')"
                "startswith(userPrincipalName, '$escapedValue')"
            ) -join ' or '
        }
    }

    $users = @(
        Get-MgUser `
            -Filter $filter `
            -Property @(
                'Id'
                'DisplayName'
                'UserPrincipalName'
                'Mail'
                'MobilePhone'
                'OnPremisesSamAccountName'
                'OnPremisesDomainName'
            ) `
            -ConsistencyLevel eventual `
            -All
    )

    if (-not $users) {
        Write-Warning "No users were found matching '$UserStartsWith'."
        return
    }

    foreach ($user in $users) {
        try {
            $devices = @(
                Get-MgUserOwnedDeviceAsDevice -UserId $user.Id -Property @(
                        'Id'
                        'DisplayName'
                        'OperatingSystem'
                        'OperatingSystemVersion'
                        'ApproximateLastSignInDateTime'
                        'TrustType'
                    ) `
                    -All `
                    -ErrorAction Stop
            )
        }
        catch {
            Write-Error "Could not retrieve devices for $($user.UserPrincipalName): $_"
            continue
        }

        foreach ($device in $devices) {
            try {
                $OS = "$($device.OperatingSystem) $(([version]$device.OperatingSystemVersion).Build -ge 22000 ? '11' : '10')"
            }
            catch {
                $OS = "$($device.OperatingSystem) $($device.OperatingSystemVersion)"
            }

            [pscustomobject]@{
                Id                            = $device.Id
                DisplayName                   = $device.DisplayName
                OS                            = $OS
                OwnerDisplayName              = $user.DisplayName
                OwnerUserPrincipalName        = $user.UserPrincipalName
                OwnerEmailAddress             = $user.Mail
                OwnerMobilePhone              = $user.MobilePhone
                OwnerADAccountName            = $user.OnPremisesSamAccountName
                OwnerAdDomain                 = $user.OnPremisesDomainName
                ApproximateLastSignInDateTime = $device.ApproximateLastSignInDateTime
                TrustType                     = $device.TrustType
            }
        }
    }
}