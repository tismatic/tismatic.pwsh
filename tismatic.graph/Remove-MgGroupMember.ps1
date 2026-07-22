function Remove-MgGroupMember {
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
                GroupId           = $GroupId
                Input             = $Identity
                UserPrincipalName = $null
                DisplayName       = $null
                UserObjectId      = $null
                Status            = 'Failed'
                Error             = $null
            }

            try {
                $User = Get-MgUser `
                    -UserId $Identity `
                    -Property Id, DisplayName, UserPrincipalName `
                    -ErrorAction Stop

                $Result.UserPrincipalName = $User.UserPrincipalName
                $Result.DisplayName       = $User.DisplayName
                $Result.UserObjectId      = $User.Id

                $Target = "$($User.UserPrincipalName) <- group $GroupId"

                if ($PSCmdlet.ShouldProcess($Target, 'Remove Entra group member')) {
                    Remove-MgGroupMemberByRef `
                        -GroupId $GroupId `
                        -DirectoryObjectId $User.Id `
                        -Confirm:$false `
                        -ErrorAction Stop

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
                $Message = $_.Exception.Message

                if ($Message -match 'not found|does not exist|Request_ResourceNotFound') {
                    $Result.Status = 'NotFound'
                    $Result.Error = $Message
                }
                else {
                    $Result.Error = $Message
                }
            }

            [pscustomobject]$Result
        }
    }
}
