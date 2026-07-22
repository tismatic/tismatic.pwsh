function Disconnect-365Admin {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
    param(
        [Parameter()]
        [ValidateSet('All', 'Graph', 'Exchange')]
        [string]$Service = 'All'
    )

    $Services = if ($Service -eq 'All') {
        'Graph', 'Exchange'
    }
    else {
        $Service
    }

    foreach ($CurrentService in $Services) {
        $Result = [ordered]@{
            Service = $CurrentService
            Account = $null
            Status  = 'Failed'
            Error   = $null
        }

        try {
            switch ($CurrentService) {
                'Graph' {
                    if (
                        -not (Get-Command Get-MgContext -ErrorAction Ignore) -or
                        -not (Get-Command Disconnect-MgGraph -ErrorAction Ignore)
                    ) {
                        $Result.Status = 'CommandUnavailable'
                        break
                    }

                    $Context = Get-MgContext -ErrorAction Stop

                    if (-not $Context) {
                        $Result.Status = 'NotConnected'
                        break
                    }

                    $Result.Account = $Context.Account

                    if ($PSCmdlet.ShouldProcess(
                        "Microsoft Graph session for $($Context.Account)",
                        'Disconnect'
                    )) {
                        Disconnect-MgGraph -ErrorAction Stop | Out-Null
                        $Result.Status = 'Disconnected'
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

                'Exchange' {
                    if (
                        -not (Get-Command Get-ConnectionInformation -ErrorAction Ignore) -or
                        -not (Get-Command Disconnect-ExchangeOnline -ErrorAction Ignore)
                    ) {
                        $Result.Status = 'CommandUnavailable'
                        break
                    }

                    $Connections = @(Get-ConnectionInformation -ErrorAction Stop)

                    if ($Connections.Count -eq 0) {
                        $Result.Status = 'NotConnected'
                        break
                    }

                    $Result.Account = @($Connections.UserPrincipalName | Select-Object -Unique) -join ', '

                    if ($PSCmdlet.ShouldProcess(
                        "Exchange Online session for $($Result.Account)",
                        'Disconnect'
                    )) {
                        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction Stop |
                            Out-Null
                        $Result.Status = 'Disconnected'
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
            }
        }
        catch {
            $Result.Error = $_.Exception.Message
        }

        [pscustomobject]$Result
    }
}
