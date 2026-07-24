# Retrieves BitLocker recovery keys for a specified computer from Active Directory.
function Get-ADComputerBitLocker {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$ComputerName,

        [Parameter()]
        [System.Management.Automation.PSCredential]$Credential
    )

    process {
        $adParams = @{}

        if ($Credential) {
            $adParams.Credential = $Credential
        }

        $computer = Get-ADComputer -Identity $ComputerName -Properties DistinguishedName @adParams -ErrorAction Stop

        Get-ADObject `
            -SearchBase $computer.DistinguishedName `
            -LDAPFilter '(objectClass=msFVE-RecoveryInformation)' `
            -Properties 'msFVE-RecoveryPassword', 'whenCreated' `
            @adParams |
        Sort-Object whenCreated -Descending |
        Select-Object -First 1 `
            @{Name = 'ComputerName'; Expression = { $ComputerName }},
            @{Name = 'Created'; Expression = { $_.whenCreated }},
            @{Name = 'RecoveryPassword'; Expression = { $_.'msFVE-RecoveryPassword' }}
    }
}


<#
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
#>
