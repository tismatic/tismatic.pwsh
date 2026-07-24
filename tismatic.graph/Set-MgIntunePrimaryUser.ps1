function Set-MgIntunePrimaryUser {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(
            Mandatory,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [Alias('ComputerName', 'DisplayName')]
        [ValidateNotNullOrEmpty()]
        [string[]]$DeviceName,

        [Parameter(Mandatory)]
        [Alias('UserPrincipalName')]
        [ValidateNotNullOrEmpty()]
        [string]$UserId
    )

    begin {
        try {
            $user = Get-MgUser `
                -UserId $UserId `
                -Property Id, DisplayName, UserPrincipalName `
                -ErrorAction Stop
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }

    process {
        foreach ($name in $DeviceName) {
            try {
                $escapedName = $name.Replace("'", "''")
                $encodedFilter = [uri]::EscapeDataString(
                    "deviceName eq '$escapedName'"
                )

                $uri = @(
                    'https://graph.microsoft.com/v1.0'
                    '/deviceManagement/managedDevices'
                    "?`$filter=$encodedFilter"
                    '&$select=id,deviceName,azureADDeviceId,userId,userPrincipalName'
                ) -join ''

                $response = Invoke-MgGraphRequest `
                    -Method GET `
                    -Uri $uri `
                    -OutputType PSObject `
                    -ErrorAction Stop

                $managedDevices = @($response.value)

                if ($managedDevices.Count -eq 0) {
                    throw "No Intune managed device was found with the name '$name'."
                }

                if ($managedDevices.Count -gt 1) {
                    throw "Multiple Intune managed devices were found with the name '$name'."
                }

                $managedDevice = $managedDevices[0]

                $currentUserResponse = Invoke-MgGraphRequest `
                    -Method GET `
                    -Uri (
                        'https://graph.microsoft.com/v1.0/' +
                        "deviceManagement/managedDevices/$($managedDevice.id)/users" +
                        '?$select=id,displayName,userPrincipalName'
                    ) `
                    -OutputType PSObject `
                    -ErrorAction Stop

                $currentUsers = @($currentUserResponse.value)
                $currentPrimaryUser = $currentUsers | Select-Object -First 1

                if ($user.Id -in @($currentUsers.id)) {
                    [pscustomobject]@{
                        DeviceName                  = $managedDevice.deviceName
                        ManagedDeviceId              = $managedDevice.id
                        EntraDeviceId                = $managedDevice.azureADDeviceId
                        PreviousPrimaryUser          = $currentPrimaryUser.userPrincipalName
                        PrimaryUser                  = $user.UserPrincipalName
                        Changed                      = $false
                        Status                       = 'Already assigned'
                    }

                    continue
                }

                if ($PSCmdlet.ShouldProcess(
                    "$($managedDevice.deviceName) [$($managedDevice.id)]",
                    "Set Intune primary user to '$($user.UserPrincipalName)'"
                )) {
                    $body = @{
                        '@odata.id' = (
                            'https://graph.microsoft.com/v1.0/' +
                            "users/$($user.Id)"
                        )
                    } | ConvertTo-Json

                    Invoke-MgGraphRequest `
                        -Method POST `
                        -Uri (
                            'https://graph.microsoft.com/v1.0/' +
                            "deviceManagement/managedDevices/$($managedDevice.id)/users/`$ref"
                        ) `
                        -Body $body `
                        -ContentType 'application/json' `
                        -ErrorAction Stop |
                        Out-Null

                    [pscustomobject]@{
                        DeviceName                  = $managedDevice.deviceName
                        ManagedDeviceId              = $managedDevice.id
                        EntraDeviceId                = $managedDevice.azureADDeviceId
                        PreviousPrimaryUser          = $currentPrimaryUser.userPrincipalName
                        PrimaryUser                  = $user.UserPrincipalName
                        Changed                      = $true
                        Status                       = 'Primary user updated'
                    }
                }
            }
            catch {
                $PSCmdlet.WriteError($_)
            }
        }
    }
}