function Write-LogMsg {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [Alias('Message')]
        [AllowNull()]
        [object]$InputObject,
        [ValidateSet('FAIL', 'INFO', 'WARN')]
        [string]$LogLevel,
        [string]$LogFilePath,
        [object]$TextBox
    )
    process {
        if ($env:LogFilePath) { $LogFilePath = $env:LogFilePath }
        $autoLevel = 'INFO'
        $message = ''
        switch ($InputObject) {
            { $_ -is [System.Management.Automation.ErrorRecord] } {
                $autoLevel = 'FAIL'
                $message = if ($_.Exception?.Message) { $_.Exception.Message } else { $_.ToString() }
                break
            }
            { $_ -is [System.Management.Automation.WarningRecord] } {
                $autoLevel = 'WARN'
                $message = $_.Message
                break
            }
            { $_ -is [System.Management.Automation.InformationRecord] } {
                $autoLevel = 'INFO'
                $md = $_.MessageData
                $message = if ($md -is [string]) { $md } elseif ($null -ne $md) { ($md | Out-String).Trim() } else { $_.ToString() }
                break
            }
            { $_ -is [System.Management.Automation.VerboseRecord] } {
                $autoLevel = 'INFO'
                $message = "[VERBOSE] $($_.Message)"
                break
            }
            { $_ -is [System.Management.Automation.DebugRecord] } {
                $autoLevel = 'INFO'
                $message = "[DEBUG] $($_.Message)"
                break
            }
            default {
                $message = if ($null -eq $InputObject) { '' }
                elseif ($InputObject.PSObject.Properties['Message']) { [string]$InputObject.Message }
                else { ($InputObject | Out-String).TrimEnd() }
            }
        }
        $effectiveLevel = if ($PSBoundParameters.ContainsKey('LogLevel')) { $LogLevel } else { $autoLevel }
        $prefix = switch ($effectiveLevel) {
            'FAIL' { '[ FAIL ]' }
            'WARN' { '[ WARN ]' }
            default { '[ INFO ]' }
        }
        $timestamp = Get-Date -Format '[ yyyy-MM-dd HH:mm:ss.fff ]'
        $logMsg = "$timestamp $prefix $message"
        if ($LogFilePath) {
            try { Add-Content -LiteralPath $LogFilePath -Value $logMsg -Encoding utf8 -ErrorAction Stop }
            catch { Write-Warning "Failed to write to log file '$LogFilePath': $($_.Exception.Message)" }
        }
        $targetTextBox = if ($TextBox) { $TextBox } elseif ($Global:LogTextBox) { $Global:LogTextBox } else { $null }
        if ($targetTextBox) {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
            $append = { param($tb, $text) $tb.AppendText("$text`r`n") }
            if ($targetTextBox.InvokeRequired) { [void]$targetTextBox.BeginInvoke($append, @($targetTextBox, $logMsg)) }
            else { & $append $targetTextBox $logMsg }
        }
        $logMsg
    }
}