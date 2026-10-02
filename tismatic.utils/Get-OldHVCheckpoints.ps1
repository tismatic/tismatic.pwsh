function Get-OldHVCheckpoints {
    <#
    .SYNOPSIS
    Checks Hyper-V checkpoints by creation age using Hyper-V cmdlets.

    .DESCRIPTION
    Uses Get-VM and Get-VMSnapshot to find checkpoints older than a configured
    age threshold.

    Returns a structured result indicating whether stale checkpoints were found.
    Operational failures are returned as PowerShell errors and do not terminate
    the active PowerShell session.

    Supports remote execution via PowerShell remoting with -ComputerName and an
    optional -Credential. The Hyper-V checks are performed on the target host.

    .PARAMETER ThresholdHours
    Age threshold in hours. Any checkpoint with CreationTime older than this
    value is considered stale. Default is 24.

    .PARAMETER MaxReportItems
    Maximum number of stale checkpoints included in the Checkpoints property.
    Default is 25.

    .PARAMETER ComputerName
    Optional target computer. Defaults to the local computer.

    .PARAMETER Credential
    Optional credential for remote execution. Only used when ComputerName
    targets a remote computer.

    .EXAMPLE
    Get-OldHVCheckpoints

    Checks the local Hyper-V host using the default 24-hour threshold.

    .EXAMPLE
    Get-OldHVCheckpoints -ThresholdHours 36 -MaxReportItems 50

    Checks locally using a 36-hour threshold.

    .EXAMPLE
    Get-OldHVCheckpoints -ComputerName HV01

    Checks HV01 remotely using the current credentials.

    .EXAMPLE
    $cred = Get-Credential
    Get-OldHVCheckpoints -ComputerName HV01 -Credential $cred

    Checks HV01 remotely using alternate credentials.
    #>

    [CmdletBinding()]
    param(
        [ValidateRange(1, 2147483647)]
        [int]$ThresholdHours = 24,

        [ValidateRange(1, 2147483647)]
        [int]$MaxReportItems = 25,

        [string]$ComputerName = $env:COMPUTERNAME,

        [System.Management.Automation.PSCredential]$Credential
    )

    $checkpointCheck = {
        param(
            [int]$ThresholdHours,
            [int]$MaxReportItems
        )

        $ErrorActionPreference = 'Stop'
        $target = $env:COMPUTERNAME

        $hasHyperV = $false

        if (Get-Command Get-WindowsFeature -ErrorAction SilentlyContinue) {
            $feature = Get-WindowsFeature -Name Hyper-V -ErrorAction SilentlyContinue
            $hasHyperV = $feature -and $feature.InstallState -eq 'Installed'
        }
        elseif (Get-Command Get-WindowsOptionalFeature -ErrorAction SilentlyContinue) {
            $feature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -ErrorAction SilentlyContinue
            $hasHyperV = $feature -and $feature.State -eq 'Enabled'
        }

        if (-not $hasHyperV) {
            throw "Hyper-V role/feature is not installed on target '$target'."
        }

        if (-not (Get-Module -ListAvailable -Name Hyper-V)) {
            throw "Hyper-V PowerShell module is not available on target '$target'."
        }

        Import-Module Hyper-V -ErrorAction Stop

        $now = Get-Date
        $cutoff = $now.AddHours(-$ThresholdHours)

        $vms = @(Get-VM -ErrorAction Stop)

        $snapshots = @(
            foreach ($vm in $vms) {
                Get-VMSnapshot -VM $vm -ErrorAction Stop
            }
        )

        $oldSnapshots = @(
            $snapshots |
                Where-Object CreationTime -LT $cutoff |
                Sort-Object CreationTime
        )

        $checkpointDetails = @(
            $oldSnapshots |
                Select-Object -First $MaxReportItems |
                ForEach-Object {
                    [pscustomobject]@{
                        VMName       = $_.VMName
                        SnapshotName = $_.Name
                        SnapshotType = $_.SnapshotType
                        CreationTime = $_.CreationTime
                        AgeHours     = [math]::Round(
                            (New-TimeSpan -Start $_.CreationTime -End $now).TotalHours,
                            2
                        )
                    }
                }
        )

        $status = if ($oldSnapshots.Count -gt 0) {
            'Alert'
        }
        else {
            'OK'
        }

        [pscustomobject]@{
            ComputerName      = $target
            Status            = $status
            ThresholdHours    = $ThresholdHours
            SnapshotCount     = $snapshots.Count
            OldSnapshotCount  = $oldSnapshots.Count
            ReportedCount     = $checkpointDetails.Count
            UnreportedCount   = [math]::Max(0, $oldSnapshots.Count - $checkpointDetails.Count)
            Checkpoints       = $checkpointDetails
        }
    }

    $localNames = @(
        '.'
        'localhost'
        $env:COMPUTERNAME
    ) | Where-Object { $_ }

    $isLocalTarget = $ComputerName -in $localNames

    if ($isLocalTarget) {
        if ($PSBoundParameters.ContainsKey('Credential')) {
            Write-Error "-Credential is only supported when -ComputerName targets a remote host."
            return
        }

        try {
            return & $checkpointCheck -ThresholdHours $ThresholdHours -MaxReportItems $MaxReportItems
        }
        catch {
            Write-Error "Checkpoint check failed for target '$ComputerName': $($_.Exception.Message)"
            return
        }
    }

    $invokeParams = @{
        ComputerName = $ComputerName
        ScriptBlock  = $checkpointCheck
        ArgumentList = @($ThresholdHours, $MaxReportItems)
        ErrorAction  = 'Stop'
    }

    if ($PSBoundParameters.ContainsKey('Credential')) {
        $invokeParams.Credential = $Credential
    }

    try {
        return Invoke-Command @invokeParams
    }
    catch {
        Write-Error "Remote checkpoint check failed for target '$ComputerName': $($_.Exception.Message)"
    }
}