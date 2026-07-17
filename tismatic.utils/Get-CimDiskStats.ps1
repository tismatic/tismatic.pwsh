function Get-CimDiskStats {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string[]]$HostName,

        [Parameter()]
        [pscredential]$Credential,

        [Parameter()]
        [switch]$AsJob
    )

    foreach ($ComputerName in $HostName) {
        $Session = $null

        try {
            $SessionOption = New-CimSessionOption -Protocol Dcom

            $SessionParameters = @{
                ComputerName        = $ComputerName
                SessionOption       = $SessionOption
                OperationTimeoutSec = 1
                ErrorAction         = 'Stop'
            }

            if ($Credential) {
                $SessionParameters.Credential = $Credential
            }

            $Session = New-CimSession @SessionParameters

            Get-CimInstance `
                -ClassName Win32_LogicalDisk `
                -CimSession $Session `
                -Filter 'DriveType = 3' |
                ForEach-Object {
                    $UsedSpace = $_.Size - $_.FreeSpace

                    [pscustomobject]@{
                        TimeStamp          = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
                        HostName           = $ComputerName
                        DeviceID           = $_.DeviceID
                        VolumeName         = $_.VolumeName
                        Capacity           = Format-Size $_.Size
                        FreeSpace          = Format-Size $_.FreeSpace
                        UsedSpace          = $UsedSpace
                        UtilizationPercent = if ($_.Size -gt 0) {
                            [math]::Round(($UsedSpace / $_.Size) * 100, 2)
                        }
                        else {
                            0
                        }
                    }
                }
        }
        catch {
            Write-Error "Unable to retrieve disk statistics from '$ComputerName': $($_.Exception.Message)"
        }
        finally {
            if ($Session) {
                $Session.Dispose()
            }
        }
    }
}