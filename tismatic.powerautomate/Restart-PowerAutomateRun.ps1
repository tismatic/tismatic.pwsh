function Restart-PowerAutomateRun {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [object[]]$Run,

        [string]$EnvironmentName,
        [string]$FlowName,
        [string]$TenantId,

        [string]$RecoveryName,

        [string]$RecoveryRoot = (Join-Path $PWD 'PowerAutomateRecovery'),

        [ValidateRange(0, 60000)]
        [int]$DelayMilliseconds = 1000,

        [ValidateRange(1, 20)]
        [int]$MaxRetries = 5,

        [ValidateRange(0, 1000000)]
        [int]$MaxRuns = 0,

        [switch]$RetryUncertain,

        [switch]$Force
    )

    $ApiVersion = '2016-11-01'
    $ApiRoot = 'https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple'

    if (-not $EnvironmentName) {
        $Values = @($Run.EnvironmentName | Where-Object { $_ } | Sort-Object -Unique)

        if ($Values.Count -ne 1) {
            throw 'Unable to determine a single EnvironmentName from the supplied runs.'
        }

        $EnvironmentName = $Values[0]
    }

    if (-not $FlowName) {
        $Values = @($Run.FlowName | Where-Object { $_ } | Sort-Object -Unique)

        if ($Values.Count -ne 1) {
            throw 'Unable to determine a single FlowName from the supplied runs.'
        }

        $FlowName = $Values[0]
    }

    if (-not $TenantId) {
        $Values = @($Run.TenantId | Where-Object { $_ } | Sort-Object -Unique)

        if ($Values.Count -eq 1) {
            $TenantId = $Values[0]
        }
    }

    if (-not $RecoveryName) {
        $RecoveryName = "PowerAutomateRecovery-$FlowName"
    }

    $RecoveryPath = Join-Path $RecoveryRoot $RecoveryName
    $ManifestPath = Join-Path $RecoveryPath 'manifest.csv'
    $JournalPath = Join-Path $RecoveryPath 'journal.csv'
    $LogFilePath = Join-Path $RecoveryPath 'recovery.log'

    New-Item -ItemType Directory -Path $RecoveryPath -Force | Out-Null

    function Write-RecoveryLog {
        param (
            [Parameter(Mandatory)]
            [string]$Message,

            [ValidateSet('FAIL', 'INFO', 'WARN')]
            [string]$Level = 'INFO'
        )

        if (Get-Command Write-LogMsg -ErrorAction SilentlyContinue) {
            $Message | Write-LogMsg -LogLevel $Level -LogFilePath $LogFilePath | Write-Host
        }
        else {
            $Timestamp = Get-Date -Format '[ yyyy-MM-dd HH:mm:ss.fff ]'
            $Line = "$Timestamp [ $Level ] $Message"

            Add-Content -LiteralPath $LogFilePath -Value $Line -Encoding utf8
            Write-Host $Line
        }
    }

    function Add-RecoveryJournal {
        param (
            [string]$RunId,
            [string]$OriginalStartTime,
            [string]$State,
            [int]$Attempt = 0,
            [int]$HttpStatus = 0,
            [string]$Message
        )

        $Record = [pscustomobject]@{
            TimestampUtc      = (Get-Date).ToUniversalTime().ToString('o')
            RunId             = $RunId
            OriginalStartTime = $OriginalStartTime
            State             = $State
            Attempt           = $Attempt
            HttpStatus        = if ($HttpStatus) { $HttpStatus } else { $null }
            Message           = $Message
        }

        $Record | Export-Csv -LiteralPath $JournalPath -Append -NoTypeInformation
    }

    function Get-HttpStatusCode {
        param (
            $ErrorRecord
        )

        try {
            [int]$ErrorRecord.Exception.Response.StatusCode
        }
        catch {
            $null
        }
    }

    $Manifest = @(
        $Run | ForEach-Object {
            [pscustomobject]@{
                RunId             = $_.name
                OriginalStartTime = $_.properties.startTime
                OriginalStatus    = $_.properties.status
            }
        } | Sort-Object RunId -Unique
    )

    if (-not $Manifest.Count) {
        throw 'No runs were supplied.'
    }

    if (Test-Path $ManifestPath) {
        $ExistingManifest = @(Import-Csv -LiteralPath $ManifestPath)

        $Difference = Compare-Object ($ExistingManifest.RunId | Sort-Object) ($Manifest.RunId | Sort-Object)

        if ($Difference) {
            throw "The supplied runs do not match the existing recovery manifest at '$ManifestPath'."
        }

        $Manifest = $ExistingManifest

        Write-RecoveryLog "Existing manifest found containing $($Manifest.Count) runs. Resuming recovery."
    }
    else {
        $Manifest | Export-Csv -LiteralPath $ManifestPath -NoTypeInformation
        Write-RecoveryLog "Created recovery manifest containing $($Manifest.Count) runs."
    }

    $LatestState = @{}

    if (Test-Path $JournalPath) {
        foreach ($Entry in Import-Csv -LiteralPath $JournalPath) {
            $LatestState[$Entry.RunId] = $Entry
        }
    }

    $AlreadySubmitted = @(
        $Manifest | Where-Object {
            $LatestState.ContainsKey($_.RunId) -and $LatestState[$_.RunId].State -eq 'Submitted'
        }
    ).Count

    $Uncertain = @(
        $Manifest | Where-Object {
            $LatestState.ContainsKey($_.RunId) -and $LatestState[$_.RunId].State -in @('Submitting', 'Uncertain')
        }
    ).Count

    Write-RecoveryLog "Recovery state: Total=$($Manifest.Count), Submitted=$AlreadySubmitted, Uncertain=$Uncertain"

    if (-not $Force) {
        $Remaining = $Manifest.Count - $AlreadySubmitted
        $Answer = Read-Host "Resubmit up to $Remaining remaining runs? [y/N]"

        if ($Answer -notin @('y', 'yes')) {
            Write-RecoveryLog 'Recovery canceled by operator.' 'WARN'
            return
        }
    }

    $Auth = Get-PowerAutomateAuth -TenantId $TenantId

    $TriggerUri = "$ApiRoot/environments/$EnvironmentName/flows/$FlowName/triggers?api-version=$ApiVersion"

    $TriggerParams = @{
        Method      = 'Get'
        Uri         = $TriggerUri
        Headers     = $Auth.Headers
        ErrorAction = 'Stop'
    }

    $TriggerResponse = Invoke-RestMethod @TriggerParams
    $Triggers = @($TriggerResponse.value)

    if ($Triggers.Count -ne 1) {
        throw "Expected one flow trigger but received $($Triggers.Count)."
    }

    $TriggerName = $Triggers[0].name

    Write-RecoveryLog "Using trigger '$TriggerName'."

    $Processed = 0

    foreach ($Item in $Manifest) {
        $RunId = $Item.RunId

        if ($LatestState.ContainsKey($RunId)) {
            $PreviousState = $LatestState[$RunId].State

            if ($PreviousState -eq 'Submitted') {
                continue
            }

            if ($PreviousState -in @('Submitting', 'Uncertain') -and -not $RetryUncertain) {
                Write-RecoveryLog "Skipping uncertain run $RunId to prevent possible duplicate processing." 'WARN'
                continue
            }
        }

        if ($MaxRuns -gt 0 -and $Processed -ge $MaxRuns) {
            Write-RecoveryLog "MaxRuns limit of $MaxRuns reached."
            break
        }

        $Processed++

        if ($Auth.ExpiresOn -lt [datetimeoffset]::UtcNow.AddMinutes(5)) {
            Write-RecoveryLog 'Power Automate access token is nearing expiration. Refreshing.'
            $Auth = Get-PowerAutomateAuth -TenantId $TenantId
        }

        $Percent = [math]::Round(($Processed / $Manifest.Count) * 100, 1)

        Write-Progress -Activity 'Resubmitting Power Automate runs' -Status "$Processed / $($Manifest.Count)" -PercentComplete $Percent

        $ResubmitUri = "$ApiRoot/environments/$EnvironmentName/flows/$FlowName/triggers/$TriggerName/histories/$RunId/resubmit?api-version=$ApiVersion"

        $TerminalState = $null

        for ($Attempt = 1; $Attempt -le $MaxRetries; $Attempt++) {
            Add-RecoveryJournal -RunId $RunId -OriginalStartTime $Item.OriginalStartTime -State 'Submitting' -Attempt $Attempt

            Write-RecoveryLog "Resubmitting $RunId. Attempt $Attempt."

            try {
                $Params = @{
                    Method      = 'Post'
                    Uri         = $ResubmitUri
                    Headers     = $Auth.Headers
                    ErrorAction = 'Stop'
                }

                $Response = Invoke-WebRequest @Params
                $StatusCode = [int]$Response.StatusCode

                Add-RecoveryJournal -RunId $RunId -OriginalStartTime $Item.OriginalStartTime -State 'Submitted' -Attempt $Attempt -HttpStatus $StatusCode -Message 'Resubmit request accepted by Power Automate.'

                $LatestState[$RunId] = [pscustomobject]@{
                    State = 'Submitted'
                }

                Write-RecoveryLog "Submitted $RunId successfully. HTTP $StatusCode."

                $TerminalState = 'Submitted'
                break
            }
            catch {
                $StatusCode = Get-HttpStatusCode -ErrorRecord $_

                if ($StatusCode -eq 401) {
                    Write-RecoveryLog "HTTP 401 for $RunId. Refreshing token." 'WARN'

                    Add-RecoveryJournal -RunId $RunId -OriginalStartTime $Item.OriginalStartTime -State 'Retrying' -Attempt $Attempt -HttpStatus $StatusCode -Message 'Refreshing access token.'

                    $Auth = Get-PowerAutomateAuth -TenantId $TenantId
                    continue
                }

                if ($StatusCode -in @(408, 429, 500, 502, 503, 504)) {
                    $Delay = [math]::Min(60, [math]::Pow(2, $Attempt))

                    Write-RecoveryLog "HTTP $StatusCode for $RunId. Waiting $Delay seconds before retry." 'WARN'

                    Add-RecoveryJournal -RunId $RunId -OriginalStartTime $Item.OriginalStartTime -State 'Retrying' -Attempt $Attempt -HttpStatus $StatusCode -Message "Retrying after $Delay seconds."

                    Start-Sleep -Seconds $Delay
                    continue
                }

                if ($StatusCode) {
                    Add-RecoveryJournal -RunId $RunId -OriginalStartTime $Item.OriginalStartTime -State 'Failed' -Attempt $Attempt -HttpStatus $StatusCode -Message $_.Exception.Message

                    $LatestState[$RunId] = [pscustomobject]@{
                        State = 'Failed'
                    }

                    Write-RecoveryLog "Failed to submit $RunId. HTTP $StatusCode. $($_.Exception.Message)" 'FAIL'

                    $TerminalState = 'Failed'
                    break
                }

                Add-RecoveryJournal -RunId $RunId -OriginalStartTime $Item.OriginalStartTime -State 'Uncertain' -Attempt $Attempt -Message $_.Exception.Message

                $LatestState[$RunId] = [pscustomobject]@{
                    State = 'Uncertain'
                }

                Write-RecoveryLog "Submission state for $RunId is uncertain. It will not be automatically retried." 'WARN'

                $TerminalState = 'Uncertain'
                break
            }
        }

        if (-not $TerminalState) {
            Add-RecoveryJournal -RunId $RunId -OriginalStartTime $Item.OriginalStartTime -State 'Failed' -Attempt $MaxRetries -Message 'Maximum retry count reached.'

            $LatestState[$RunId] = [pscustomobject]@{
                State = 'Failed'
            }

            Write-RecoveryLog "Maximum retry count reached for $RunId." 'FAIL'
        }

        if ($TerminalState -eq 'Submitted' -and $DelayMilliseconds -gt 0) {
            Start-Sleep -Milliseconds $DelayMilliseconds
        }
    }

    Write-Progress -Activity 'Resubmitting Power Automate runs' -Completed

    $FinalState = @{}

    if (Test-Path $JournalPath) {
        foreach ($Entry in Import-Csv -LiteralPath $JournalPath) {
            $FinalState[$Entry.RunId] = $Entry
        }
    }

    $Submitted = 0
    $Failed = 0
    $Uncertain = 0
    $Pending = 0

    foreach ($Item in $Manifest) {
        if (-not $FinalState.ContainsKey($Item.RunId)) {
            $Pending++
            continue
        }

        switch ($FinalState[$Item.RunId].State) {
            'Submitted' { $Submitted++ }
            'Failed' { $Failed++ }
            { $_ -in @('Submitting', 'Uncertain') } { $Uncertain++ }
            default { $Pending++ }
        }
    }

    Write-RecoveryLog "Recovery pass complete. Submitted=$Submitted Failed=$Failed Uncertain=$Uncertain Pending=$Pending"

    [pscustomobject]@{
        RecoveryName = $RecoveryName
        Total        = $Manifest.Count
        Submitted    = $Submitted
        Failed       = $Failed
        Uncertain    = $Uncertain
        Pending      = $Pending
        Manifest     = $ManifestPath
        Journal      = $JournalPath
        Log          = $LogFilePath
    }
}