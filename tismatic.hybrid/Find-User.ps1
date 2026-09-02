function Find-User {
    param(
        $SearchString
    )
    $results = @()

    $results += Find-ADuser $SearchString
    $results += Find-MGUser $SearchString

    $results
}
function Get-UserTypeName { param( [Parameter(ValueFromPipeline)] $UserObject ) $UserObject.Gettype().Name } function Invoke-BlockUserSignin { param( [Parameter(ValueFromPipeline)] $UserObject ) $result = switch ($UserObject | Get-UserTypeName) { "MicrosoftGraphUser" { Update-Mguser $UserObject.id -AccountEnabled:$false } "ADUser" { $UserObject | Disable-ADAccount } default { write-error "Unknown user type" } } $result }
function Get-MyUpn {
    (get-mgcontext).Account
}

function Block-UserSignin {
    param(
        [Parameter(ValueFromPipeline)]
        $UserObject
    )
    $result = switch ($UserObject.OnPremisesSyncEnabled) {
        $true {
            try {
                Update-Mguser -UserId $UserObject.id -AccountEnabled:$false
                Write-LogMsg -Message "$(Get-MyUpn) disabled account for $($UserObject.Userprincipalname)"
            }
            catch {
                Write-LogMsg -Message "Action started by $(Get-MyUpn) failed: $_" -LogLevel FAIL
            }
        }
        $false {
            try {
                Disable-ADAccount -Identity $UserObject.OnPremisesSamAccountName -Server $UserObject.OnPremisesDomainName
                Write-LogMsg -Message "$(Get-MyUpn) disabled account for $($UserObject.Userprincipalname)"
            }
            catch {
                Write-LogMsg -Message "Action started by $(Get-MyUpn) failed: $_" -LogLevel FAIL
            }
            
        }
        
        default { write-error "Unknown user type" }
    }

    $result
}

function Reset-UserPassword {
    param(
        [Parameter(ValueFromPipeline)]
        $UserObject
    )
    $result = switch ($UserObject | Get-UserTypeName) {
        "MicrosoftGraphUser" { "We would do cloud action" }
        "ADUser" { "We would do an on prem action" }
        default { write-error "Unknown user type" }
    }

    $result
}



