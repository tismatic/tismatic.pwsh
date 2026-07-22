function Add-MgGroupMember {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$GroupId,

        [Parameter(
            Mandatory,
            Position = 1,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [Alias('UserPrincipalName', 'UPN', 'Id')]
        [ValidateNotNull()]
        [object]$UserId
    )

    process {
        # Handles:
        # - One UPN
        # - An explicitly supplied array
        # - Individual pipeline strings
        # - Get-MgUser objects
        foreach ($InputUser in @($UserId)) {
            $Identity = if ($InputUser -is [string]) {
                $InputUser.Trim()
            }
            elseif (
                $InputUser.PSObject.Properties['UserPrincipalName'] -and
                $InputUser.UserPrincipalName
            ) {
                [string]$InputUser.UserPrincipalName
            }
            elseif (
                $InputUser.PSObject.Properties['Id'] -and
                $InputUser.Id
            ) {
                [string]$InputUser.Id
            }
            else {
                Write-Error "Unable to determine a UPN or object ID from input: $InputUser"
                continue
            }

            $Result = [ordered]@{
                GroupId          = $GroupId
                Input            = $Identity
                UserPrincipalName = $null
                DisplayName      = $null
                UserObjectId     = $null
                Status           = 'Failed'
                Error            = $null
            }

            try {
                # -UserId accepts either the user's object ID or UPN
                $User = Get-MgUser `
                    -UserId $Identity `
                    -Property Id, DisplayName, UserPrincipalName `
                    -ErrorAction Stop

                $Result.UserPrincipalName = $User.UserPrincipalName
                $Result.DisplayName       = $User.DisplayName
                $Result.UserObjectId      = $User.Id

                $Target = "$($User.UserPrincipalName) -> group $GroupId"

                if ($PSCmdlet.ShouldProcess($Target, 'Add Entra group member')) {
                    New-MgGroupMemberByRef `
                        -GroupId $GroupId `
                        -OdataId "https://graph.microsoft.com/v1.0/directoryObjects/$($User.Id)" `
                        -ErrorAction Stop

                    $Result.Status = 'Added'
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
                $Message = $_.Exception.Message

                if ($Message -match 'already exist|already a member') {
                    $Result.Status = 'AlreadyMember'
                }
                else {
                    $Result.Error = $Message
                }
            }

            [pscustomobject]$Result
        }
    }
}