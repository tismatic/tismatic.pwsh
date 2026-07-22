function Set-MgUserOnPremImmutableId {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(
            Mandatory,
            Position = 0,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [Alias('Id', 'UPN', 'UserPrincipalName')]
        [ValidateNotNullOrEmpty()]
        [string[]]$UserId,

        [Parameter(Mandatory, Position = 1)]
        [ValidateNotNullOrEmpty()]
        [string]$ImmutableId
    )

    process {
        foreach ($CurrentUserId in $UserId) {
            $Result = [ordered]@{
                UserPrincipalName   = $null
                UserObjectId        = $null
                PreviousImmutableId = $null
                ImmutableId         = $ImmutableId
                Status              = 'Failed'
                Error               = $null
            }

            try {
                $User = Get-MgUser `
                    -UserId $CurrentUserId `
                    -Property Id, DisplayName, UserPrincipalName, OnPremisesImmutableId `
                    -ErrorAction Stop

                $Result.UserPrincipalName   = $User.UserPrincipalName
                $Result.UserObjectId        = $User.Id
                $Result.PreviousImmutableId = $User.OnPremisesImmutableId

                if ($User.OnPremisesImmutableId -ceq $ImmutableId) {
                    $Result.Status = 'AlreadySet'
                    [pscustomobject]$Result
                    continue
                }

                if ($PSCmdlet.ShouldProcess(
                    "$($User.UserPrincipalName) [$($User.Id)]",
                    "Set on-premises immutable ID to '$ImmutableId'"
                )) {
                    $Body = @{
                        onPremisesImmutableId = $ImmutableId
                    } | ConvertTo-Json -Compress

                    Invoke-MgGraphRequest `
                        -Method PATCH `
                        -Uri "https://graph.microsoft.com/v1.0/users/$($User.Id)" `
                        -Body $Body `
                        -ContentType 'application/json' `
                        -ErrorAction Stop |
                        Out-Null

                    $Result.Status = 'Set'
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
}
