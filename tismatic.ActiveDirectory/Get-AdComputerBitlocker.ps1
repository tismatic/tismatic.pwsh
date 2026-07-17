# Retrieves BitLocker recovery keys for a specified computer from Active Directory.
function Get-ADComputerBitLocker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ComputerName,
        $Credential
    )

    try {
        $Computer = Get-ADComputer -Identity $ComputerName -Properties DistinguishedName
    }
    catch {
        Write-Warning "Computer '$ComputerName' not found in Active Directory."
        return
    }

    $RecoveryObjects = Get-ADObject -Filter 'objectClass -eq "msFVE-RecoveryInformation"' `
        -SearchBase $Computer.DistinguishedName `
        -Properties 'msFVE-RecoveryPassword', 'msFVE-RecoveryGuid', 'whenCreated'

    if (-not $RecoveryObjects) {
        Write-Output "No BitLocker recovery keys found for '$ComputerName'."
        return
    }

    $RecoveryObjects | Select-Object `
    @{Name = 'ComputerName'; Expression = { $ComputerName } },
    @{Name = 'RecoveryKeyID'; Expression = { [guid]$_.'msFVE-RecoveryGuid' } },
    @{Name = 'RecoveryPassword'; Expression = { $_.'msFVE-RecoveryPassword' } },
    @{Name = 'Created'; Expression = { Get-date $_.whenCreated -format "MM/dd/yyy" } } | Sort-Object -Property Created -Descending 

} 