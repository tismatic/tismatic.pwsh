function Remove-ProxyAddress {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias('SamAccountName', 'OnPremisesSamAccountName')]
        [object]$Identity,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ProxyAddress,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$NewPrimarySMTPAddress,

        [string]$Server,

        [pscredential]$Credential
    )

    begin {
        if (-not $Server) {
            $Server = (Get-ADDomain -ErrorAction Stop).DNSRoot
        }

        $CommonParams = @{
            Server      = $Server
            ErrorAction = 'Stop'
        }

        if ($Credential) {
            $CommonParams.Credential = $Credential
        }
    }

    process {
        $Result = [ordered]@{
            SamAccountName        = $null
            DistinguishedName     = $null
            RemovedProxyAddress   = $null
            NewPrimarySMTPAddress = $null
            Status                = 'Failed'
            Error                 = $null
        }

        try {
            $AdUser = if (
                $Identity.PSObject.Properties['DistinguishedName'] -and
                $Identity.DistinguishedName
            ) {
                Get-ADUser `
                    -Identity $Identity.DistinguishedName `
                    -Properties ProxyAddresses `
                    @CommonParams
            }
            else {
                Get-ADUser `
                    -Identity $Identity `
                    -Properties ProxyAddresses `
                    @CommonParams
            }

            $Result.SamAccountName    = $AdUser.SamAccountName
            $Result.DistinguishedName = $AdUser.DistinguishedName

            $Address = $ProxyAddress.Trim() -replace '^(?i)smtp:', ''
            if (-not $Address) {
                throw 'ProxyAddress must contain an SMTP address.'
            }

            $Current = @($AdUser.ProxyAddresses | ForEach-Object { $_.ToString() })
            $AddressMatches = @(
                $Current | Where-Object {
                    ($_ -replace '^(?i)smtp:', '').Equals(
                        $Address,
                        [System.StringComparison]::OrdinalIgnoreCase
                    ) -and $_ -match '^(?i)smtp:'
                }
            )

            if ($AddressMatches.Count -eq 0) {
                $Result.Status = 'NotPresent'
                [pscustomobject]$Result
                continue
            }

            $PrimaryMatch = $AddressMatches | Where-Object { $_ -cmatch '^SMTP:' } | Select-Object -First 1

            if ($PrimaryMatch -and -not $NewPrimarySMTPAddress) {
                throw "'$Address' is the primary SMTP address. Supply -NewPrimarySMTPAddress before removing it."
            }

            if (-not $PrimaryMatch -and $NewPrimarySMTPAddress) {
                throw '-NewPrimarySMTPAddress can only be used when removing the current primary SMTP address.'
            }

            $UpdatedAddresses = @(
                $Current | Where-Object {
                    $CurrentValue = $_
                    -not ($AddressMatches | Where-Object {
                        $_.Equals($CurrentValue, [System.StringComparison]::OrdinalIgnoreCase)
                    })
                }
            )

            if ($PrimaryMatch) {
                $NewPrimary = $NewPrimarySMTPAddress.Trim() -replace '^(?i)smtp:', ''

                if (-not $NewPrimary) {
                    throw 'NewPrimarySMTPAddress must contain an SMTP address.'
                }

                if ($NewPrimary.Equals($Address, [System.StringComparison]::OrdinalIgnoreCase)) {
                    throw 'The replacement primary SMTP address must differ from the address being removed.'
                }

                $UpdatedAddresses = @(
                    $UpdatedAddresses | ForEach-Object {
                        if ($_ -cmatch '^SMTP:') {
                            $_ -creplace '^SMTP:', 'smtp:'
                        }
                        else {
                            $_
                        }
                    } | Where-Object {
                        -not (($_ -replace '^(?i)smtp:', '').Equals(
                            $NewPrimary,
                            [System.StringComparison]::OrdinalIgnoreCase
                        ) -and $_ -match '^(?i)smtp:')
                    }
                )

                $UpdatedAddresses = @("SMTP:$NewPrimary") + $UpdatedAddresses
                $Result.NewPrimarySMTPAddress = $NewPrimary
            }

            $Action = if ($PrimaryMatch) {
                "Remove '$Address' and set primary SMTP to '$NewPrimary'"
            }
            else {
                "Remove proxy address '$Address'"
            }

            if ($PSCmdlet.ShouldProcess($AdUser.SamAccountName, $Action)) {
                if ($UpdatedAddresses.Count -eq 0) {
                    Set-ADUser -Identity $AdUser -Clear ProxyAddresses @CommonParams
                }
                else {
                    Set-ADUser `
                        -Identity $AdUser `
                        -Replace @{ ProxyAddresses = $UpdatedAddresses } `
                        @CommonParams
                }

                $Result.RemovedProxyAddress = $Address
                $Result.Status = 'Removed'
            }
            else {
                $Result.Status = if ($WhatIfPreference) {
                    'WhatIf'
                }
                else {
                    'Skipped'
                }
            }
        }
        catch {
            $Result.Error = $_.Exception.Message
        }

        [pscustomobject]$Result
    }
}
