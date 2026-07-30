class PingTarget {
    $Target
    $PingTask
    $IPAddress
    
    PingTarget($target) {
        $this.Target = $target
        $this.PingTask = [net.networkinformation.ping]::new().SendPingAsync($this.Target, 800)
    }

    SendPing() {
        $this.PingTask = [net.networkinformation.ping]::new().SendPingAsync($this.Target, 800)
    }

    [PingResult] GetResult() {
        [Threading.Tasks.Task]::WaitAll($this.PingTask)
        $TargetIsIPAddress = try {
            [bool]([ipaddress]::Parse($this.Target).Address)
        }
        catch {
            $false
        }
        if ($TargetIsIPAddress) {
            return  [PingResult]::new($this.Target, $this.PingTask.result.Address.IPAddresstoString, $this.PingTask.result.Status)
        }
        else {
            return  [PingResult]::new($this.Target, $this.PingTask.result.Address.IPAddresstoString, $this.Target, $this.PingTask.result.Status)
        }
        
    }

    [PingResult] GetResultAsync() {
        $TargetIsIPAddress = try {
            [bool]([ipaddress]::Parse($this.Target).Address)
        }
        catch {
            $false
        }
        if ($TargetIsIPAddress) {
            return  [PingResult]::new($this.Target, $this.PingTask.result.Address.IPAddresstoString, $this.PingTask.result.Status)
        }
        else {
            return  [PingResult]::new($this.Target, $this.PingTask.result.Address.IPAddresstoString, $this.Target, $this.PingTask.result.Status)
        }
    }
}
function Start-SubnetScan {
    [cmdletbinding()]
    [OutputType([System.Collections.Generic.list[PingResult]])]
    param(
        $CIDR
    )
    $range = Get-IPV4Range -Range $CIDR
    $Tasks = [System.Collections.Generic.list[Object]]::new()
    foreach ($addr in $range) {
        $Tasks.Add([PingTarget]::new($addr))
    }
    [System.Threading.Tasks.Task]::WaitAll($Tasks.PingTask)
    $SuccessfullPings = ($Tasks.GetResultAsync() | where { $_.status -eq "Success" -and $_.IPAddress -in $range })
    Write-Verbose "Found $($SuccessfullPings.count) Devices"

    # Resolve the hostnames
    Write-Verbose "Attempting to resolve hostnames of $($SuccessfullPings.count) Devices"
    try {
        $SuccessfullPings.GetHostnameAsync()
        [System.Threading.Tasks.Task]::WaitAll($SuccessfullPings.DNSTask)
        
    }
    catch {
        $null
    }
    $SuccessfullPings.UpdateHostnameFromTask()
    return ($SuccessfullPings | Where-Object { $_ })
}


class PingResult {
    hidden $Target
    $IPAddress
    $HostName
    $Status
    hidden $DNSTask
    hidden $PingTask

    PingResult($Target, $IPAddress, $Status) {
        $this.Target = $target
        $this.IPAddress = $IPAddress
        $this.Status = $Status
    }

    PingResult($Target, $IPAddress, $Hostname, $Status) {
        $this.Target = $target
        $this.IPAddress = $IPAddress
        $This.Hostname = $Hostname
        $this.Status = $Status
    }

    CheckStatus() {
        $this.Status = [net.networkinformation.ping]::new().Send($this.Target, 1000).Status
    }

    CheckStatusAsync() {
        $this.PingTask = [net.networkinformation.ping]::new().SendPingAsync($this.Target, 1000)
    }

    GetHostName() {
        try {
            $this.DNSTask = [System.Net.DNS]::GetHostEntry($this.Target)
            $This.HostName = $This.DNSTask.HostName
        }
        catch {
            $This.HostName = $This.Target
        }

    }

    GetHostNameAsync() {
        try {
            $this.DNSTask = [System.Net.DNS]::GetHostEntryAsync($this.IPAddress)
        }
        catch {
            $This.HostName = $This.Target
        }

    }

    UpdateHostnameFromTask() {
        if ($This.DNSTask.result.HostName) {
            $This.HostName = $This.DNSTask.result.HostName
        }
        else {
            $this.Hostname = $this.IPAddress
        }
    }

    UpdateStatusFromTask() {
        $This.Status = $this.PingTask.Result.Status
    }
}

function Invoke-PingAsync {
    [cmdletbinding()]
    [OutputType([System.Collections.Generic.list[PingResult]])]
    param(
        $Range
    )
    
    $Tasks = [System.Collections.Generic.list[Object]]::new()
    foreach ($addr in $range) {
        $Tasks.Add([PingTarget]::new($addr))
    }
    [System.Threading.Tasks.Task]::WaitAll($Tasks.PingTask)
    $SuccessfullPings = ($Tasks.GetResultAsync() | where { $_.IPAddress -in $range })

    Write-Verbose "Found $($SuccessfullPings.count) Devices"

    # Resolve the hostnames
    Write-Verbose "Attempting to resolve hostnames of $($SuccessfullPings.count) Devices"
    try {
        $SuccessfullPings.GetHostnameAsync()
        [System.Threading.Tasks.Task]::WaitAll($SuccessfullPings.DNSTask)
        
    }
    catch {
        $null
    }
    $SuccessfullPings.UpdateHostnameFromTask()
    return ($SuccessfullPings )
}



function Invoke-FastPing {
    [cmdletbinding()]
    [OutputType([System.Collections.Generic.list[PingResult]])]
    param(
        $Range
    )
    $Tasks = [System.Collections.Generic.list[Object]]::new()
    foreach ($addr in $range) {
        $Tasks.Add([PingTarget]::new($addr))
    }
    [System.Threading.Tasks.Task]::WaitAll($Tasks.PingTask)
    $SuccessfullPings = ($Tasks.GetResultAsync() | where { $_.status -eq "Success" -and $_.IPAddress -in $range })
    Write-Verbose "Found $($SuccessfullPings.count) Devices"

    # Resolve the hostnames
    Write-Verbose "Attempting to resolve hostnames of $($SuccessfullPings.count) Devices"
    try {
        $SuccessfullPings.GetHostnameAsync()
        [System.Threading.Tasks.Task]::WaitAll($SuccessfullPings.DNSTask)
        
    }
    catch {
        $null
    }
    $SuccessfullPings.UpdateHostnameFromTask()
    return ($SuccessfullPings | Where-Object { $_ })
}

function Get-IPV4Range {
    param(
        $Range
    )
    # Set up empty list to contain the calculated range
    $IPList = [System.Collections.Generic.list[object]]::new()

    # split out input to IP and CIDR and calculate the num,ber of addresses with the power of MATH
    $startIP, [int]$CIDR = $Range -split "/"
    $NumberOfAddresses = [Math]::Pow(2, (32 - $CIDR))

    # Get IP bytes, reverse it and convert bytes it to UInt32 for start and end addresses
    $StartIPBytes = ([ipaddress]$startIP).GetAddressBytes()
    [array]::Reverse($StartIPBytes)
    $StartIP = [BitConverter]::ToUInt32($StartIPBytes, 0)

    $EndIPBytes = [ipaddress]::Parse(($startIP) + ($NumberOfAddresses)).GetAddressBytes()
    [array]::Reverse($EndIPBytes)
    $EndIP = [BitConverter]::ToUInt32($EndIPBytes, 0)

    # Increase the start address int untill it equals the end INT parsing the IP to string and adding it to the list
    while ($startIP -lt $endIP) {
        $IPList.Add(([IPaddress]::Parse($startIP)).IPAddresstoString)
        $startIP++
    }
    return $IPlist
}


function Start-SubnetScan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$CIDR,

        [ValidateRange(1, 60000)]
        [int]$TimeoutMilliseconds = 800,

        [ValidateRange(1, 4096)]
        [int]$ThrottleLimit = 256,

        [switch]$ResolveHostName,

        [switch]$IncludeFailed
    )

    $range = @(
        Get-IPv4Range -Range $CIDR |
        ForEach-Object {
            [System.Net.IPAddress]$_
        }
    )

    if ($range.Count -eq 0) {
        return
    }

    $successfulCount = 0

    for (
        $batchStart = 0
        $batchStart -lt $range.Count
        $batchStart += $ThrottleLimit
    ) {
        $batchEnd = [Math]::Min(
            $batchStart + $ThrottleLimit - 1,
            $range.Count - 1
        )

        $batch = @($range[$batchStart..$batchEnd])

        # Start every ping in the batch before awaiting any results.
        $operations = @(
            foreach ($address in $batch) {
                $ping = [System.Net.NetworkInformation.Ping]::new()

                try {
                    [pscustomobject]@{
                        IPAddress  = $address
                        Client     = $ping
                        Task       = $ping.SendPingAsync(
                            $address,
                            $TimeoutMilliseconds
                        )
                        StartError = $null
                    }
                }
                catch {
                    $ping.Dispose()

                    [pscustomobject]@{
                        IPAddress  = $address
                        Client     = $null
                        Task       = $null
                        StartError = $_.Exception.Message
                    }
                }
            }
        )

        $batchResults = @(
            foreach ($operation in $operations) {
                if ($null -eq $operation.Task) {
                    [pscustomobject][ordered]@{
                        PSTypeName      = 'SubnetScan.Result'
                        IPAddress       = $operation.IPAddress.ToString()
                        HostName        = $null
                        Status          = 'Error'
                        RoundTripTimeMs = $null
                        Error           = $operation.StartError
                    }

                    continue
                }

                try {
                    $reply = $operation.Task.GetAwaiter().GetResult()

                    $succeeded = (
                        $reply.Status -eq
                        [System.Net.NetworkInformation.IPStatus]::Success
                    )

                    [pscustomobject][ordered]@{
                        PSTypeName      = 'SubnetScan.Result'
                        IPAddress       = $operation.IPAddress.ToString()
                        HostName        = $null
                        Status          = $reply.Status.ToString()
                        RoundTripTimeMs = if ($succeeded) {
                            $reply.RoundtripTime
                        }
                        else {
                            $null
                        }
                        Error           = $null
                    }
                }
                catch {
                    [pscustomobject][ordered]@{
                        PSTypeName      = 'SubnetScan.Result'
                        IPAddress       = $operation.IPAddress.ToString()
                        HostName        = $null
                        Status          = 'Error'
                        RoundTripTimeMs = $null
                        Error           = $_.Exception.Message
                    }
                }
                finally {
                    $operation.Client.Dispose()
                }
            }
        )

        $successfulResults = @(
            $batchResults |
            Where-Object Status -eq 'Success'
        )

        $successfulCount += $successfulResults.Count

        if ($ResolveHostName -and $successfulResults.Count -gt 0) {
            # Start all reverse lookups in this batch concurrently.
            $dnsOperations = @(
                foreach ($result in $successfulResults) {
                    [pscustomobject]@{
                        Result = $result
                        Task   = [System.Net.Dns]::GetHostEntryAsync(
                            [System.Net.IPAddress]$result.IPAddress
                        )
                    }
                }
            )

            foreach ($dnsOperation in $dnsOperations) {
                try {
                    $entry = $dnsOperation.Task.GetAwaiter().GetResult()
                    $dnsOperation.Result.HostName = $entry.HostName
                }
                catch {
                    # Missing reverse-DNS records are expected.
                    $dnsOperation.Result.HostName = $null
                }
            }
        }

        if ($IncludeFailed) {
            $batchResults
        }
        else {
            $successfulResults
        }
    }

    Write-Verbose "Found $successfulCount responsive addresses."
}

function Invoke-NmapHostDiscovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CIDR,

        [string]$InterfaceAlias,

        [ValidateRange(1, 3600)]
        [int]$TimeoutSeconds = 300
    )

    $nmap = Get-Command nmap `
        -CommandType Application `
        -ErrorAction Stop |
    Select-Object -First 1

    $arguments = [System.Collections.Generic.List[string]]::new()

    foreach ($argument in @('-sn', '-oX', '-')) {
        $arguments.Add($argument)
    }

    if ($InterfaceAlias) {
        $arguments.Add('-e')
        $arguments.Add($InterfaceAlias)
    }

    $arguments.Add($CIDR)

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $nmap.Source
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true

    foreach ($argument in $arguments) {
        [void]$startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo

    try {
        if (-not $process.Start()) {
            throw 'Unable to start Nmap.'
        }

        $standardOutputTask = $process.StandardOutput.ReadToEndAsync()
        $standardErrorTask = $process.StandardError.ReadToEndAsync()

        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $process.Kill($true)
            throw "Nmap exceeded the timeout of $TimeoutSeconds seconds."
        }

        $standardOutput = $standardOutputTask.GetAwaiter().GetResult()
        $standardError = $standardErrorTask.GetAwaiter().GetResult()

        if ($process.ExitCode -ne 0) {
            throw "Nmap exited with code $($process.ExitCode): $standardError"
        }
    }
    finally {
        $process.Dispose()
    }

    try {
        [xml]$document = $standardOutput
    }
    catch {
        throw "Nmap returned invalid XML: $($_.Exception.Message)"
    }

    foreach ($hostRecord in @($document.nmaprun.host)) {
        if ([string]$hostRecord.status.state -ne 'up') {
            continue
        }

        $addresses = @($hostRecord.address)

        $ipNode = $addresses |
        Where-Object addrtype -eq 'ipv4' |
        Select-Object -First 1

        if (-not $ipNode) {
            continue
        }

        $macNode = $addresses |
        Where-Object addrtype -eq 'mac' |
        Select-Object -First 1

        $hostNameNode = @($hostRecord.hostnames.hostname) |
        Where-Object name |
        Select-Object -First 1

        [pscustomobject][ordered]@{
            PSTypeName      = 'SubnetScan.Result'
            IPAddress       = [string]$ipNode.addr
            HostName        = [string]$hostNameNode.name
            MacAddress      = [string]$macNode.addr
            Manufacturer    = [string]$macNode.vendor
            Status          = 'Success'
            StatusReason    = [string]$hostRecord.status.reason
            RoundTripTimeMs = $null
            DiscoveryMethod = 'Nmap'
            LastSeen        = [datetime]::Now
        }
    }
}


function Get-MicrosoftOfficeProduct {
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        $SearchString
    )

    begin {
        if (-not $Global:MSProductNamesCSV) {
            $CSVUri = "https://download.microsoft.com/download/e/3/e/e3e9faf2-f28b-490a-9ada-c6089a1fc5b0/Product%20names%20and%20service%20plan%20identifiers%20for%20licensing.csv"
            $Global:MSProductNamesCSV = (Invoke-RestMethod -Uri $CSVUri | ConvertFrom-Csv | select Product_Display_Name, String_Id, GUID -Unique)
        }
    }
		
    process {
        #$Global:MSProductNamesCSV | Where-Object { $_.Product_Display_Name -eq $SearchString -or $_.String_Id -eq $SearchString } | Select-Object -first 1
        $Global:MSProductNamesCSV | where {$_.Product_Display_Name -match $SearchString -or $_.String_Id -match $SearchString}
    }
}

function Invoke-Async {
    [CmdletBinding()]
    [OutputType(
        [object],
        [System.Management.Automation.Job]
    )]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory, Position = 1)]
        [Alias('Tasks')]
        [ValidateNotNullOrEmpty()]
        [scriptblock[]]$Task,

        # None = return immediately
        # Any  = return the first result and cancel the remaining tasks
        # All  = wait for every task
        [ValidateSet('None', 'Any', 'All')]
        [string]$Await = 'All',

        [Parameter()]
        [ValidateRange(1, 1024)]
        [int]$ThrottleLimit,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$TimeoutSeconds,

        # Runs once in every thread before its task.
        # Useful for Import-Module, function definitions, etc.
        [Parameter()]
        [scriptblock]$InitializationScript,

        # Return Job objects instead of receiving their output.
        [Parameter()]
        [switch]$PassThruJob,

        # Keep jobs and their buffered output after completion.
        [Parameter()]
        [switch]$KeepJob
    )

    if (-not (Get-Command Start-ThreadJob -ErrorAction Ignore)) {
        Import-Module ThreadJob -ErrorAction Stop
    }

    $terminalStates = @(
        'Completed'
        'Failed'
        'Stopped'
        'Suspended'
        'Disconnected'
    )

    $batchId = [guid]::NewGuid().
    ToString('N').
    Substring(0, 8)

    $jobs = @()

    try {
        for ($index = 0; $index -lt $Task.Count; $index++) {
            $startParameters = @{
                Name        = '{0}-{1:D2}-{2}' -f @(
                    $Name
                    $index + 1
                    $batchId
                )
                ScriptBlock = $Task[$index]
            }

            if ($PSBoundParameters.ContainsKey('ThrottleLimit')) {
                $startParameters.ThrottleLimit = $ThrottleLimit
            }

            if ($InitializationScript) {
                $startParameters.InitializationScript =
                $InitializationScript
            }

            $job = Start-ThreadJob @startParameters

            $job | Add-Member -NotePropertyName AsyncBatchId `
                -NotePropertyValue $batchId

            $job | Add-Member -NotePropertyName AsyncIndex `
                -NotePropertyValue $index

            $job | Add-Member -NotePropertyName AsyncSelected `
                -NotePropertyValue $false

            $jobs += $job
        }
    }
    catch {
        # Do not leave partially created batches running.
        $activeJobs = @(
            $jobs | Where-Object State -NotIn $terminalStates
        )

        if ($activeJobs) {
            $activeJobs | Stop-Job -ErrorAction SilentlyContinue
            $null = $activeJobs |
            Wait-Job -ErrorAction SilentlyContinue
        }

        $jobs | Remove-Job -ErrorAction SilentlyContinue
        throw
    }

    # This is the genuinely asynchronous mode.
    if ($Await -eq 'None') {
        return $jobs
    }

    $waitParameters = @{
        Job = $jobs
    }

    if ($Await -eq 'Any') {
        $waitParameters.Any = $true
    }

    if ($PSBoundParameters.ContainsKey('TimeoutSeconds')) {
        $waitParameters.Timeout = $TimeoutSeconds
    }

    $null = Wait-Job @waitParameters

    $finishedJobs = @(
        $jobs | Where-Object State -In $terminalStates
    )

    $awaitSatisfied = if ($Await -eq 'All') {
        $finishedJobs.Count -eq $jobs.Count
    }
    else {
        $finishedJobs.Count -gt 0
    }

    if (-not $awaitSatisfied) {
        # Structured-concurrency behavior: do not leave timed-out
        # work running invisibly.
        $activeJobs = @(
            $jobs | Where-Object State -NotIn $terminalStates
        )

        if ($activeJobs) {
            $activeJobs | Stop-Job -ErrorAction SilentlyContinue
            $null = $activeJobs |
            Wait-Job -ErrorAction SilentlyContinue
        }

        if (-not ($KeepJob -or $PassThruJob)) {
            $jobs | Remove-Job -ErrorAction SilentlyContinue
        }

        throw [System.TimeoutException]::new(
            "Async batch '$Name' did not satisfy Await '$Await' " +
            "within $TimeoutSeconds seconds."
        )
    }

    if ($Await -eq 'Any') {
        # Select the task that reached a terminal state first.
        $selectedJobs = @(
            $finishedJobs |
            Sort-Object -Property @(
                @{ Expression = { $_.PSEndTime } }
                @{ Expression = { $_.AsyncIndex } }
            ) |
            Select-Object -First 1
        )

        # Treat Await Any like Promise.race: cancel the losers.
        $remainingJobs = @(
            $jobs | Where-Object {
                $_.InstanceId -ne $selectedJobs[0].InstanceId -and
                $_.State -notin $terminalStates
            }
        )

        if ($remainingJobs) {
            $remainingJobs | Stop-Job -ErrorAction SilentlyContinue
            $null = $remainingJobs |
            Wait-Job -ErrorAction SilentlyContinue
        }
    }
    else {
        $selectedJobs = $jobs
    }

    $selectedIds = @($selectedJobs.InstanceId)

    foreach ($job in $jobs) {
        $job.AsyncSelected = $job.InstanceId -in $selectedIds
    }

    # Returning a job that was immediately removed would be misleading.
    if ($PassThruJob) {
        return (
            $jobs |
            Sort-Object AsyncIndex
        )
    }

    try {
        # Receive in declaration order, rather than random completion order.
        foreach ($job in $selectedJobs | Sort-Object AsyncIndex) {
            Receive-Job `
                -Job $job `
                -Keep:$KeepJob `
                -ErrorAction $ErrorActionPreference
        }
    }
    finally {
        if (-not $KeepJob) {
            $jobs | Remove-Job -ErrorAction SilentlyContinue
        }
    }
}

Set-Alias -Name async -Value Invoke-Async

function jimmy {
    param(
        $msg
    )
    $body = @{
        messages    = @(
            @{
                role    = 'user'
                content = $msg
            }
        )
        chatOptions = @{
            selectedModel = 'llama3.1-8B'
            systemPrompt  = ''
            topK          = 8
        }
        attachment  = $null
    } | ConvertTo-Json -Depth 10
    $r = irm -Method POST -uri 'https://chatjimmy.ai/api/chat' -Body $body
    
    ($r -replace "<|stats|>.*<|/stats|>|\|").trim() | glow
}


#############################

function Remove-ADUserAllGroups {
    <#
    .SYNOPSIS
        Removes an Active Directory user from all directly assigned groups.

    .DESCRIPTION
        Accepts ADUser objects from the pipeline and removes each user from
        every group listed in the user's MemberOf attribute.

        The user's primary group, normally Domain Users, is not included in
        MemberOf and therefore is not removed.

        OutLogPath can be either:
        - A directory, in which case a timestamped log file is created.
        - A complete file path, in which case that file is used.

    .EXAMPLE
        Get-ADUser jsmith |
            Remove-ADUserAllGroups

    .EXAMPLE
        Get-ADUser -Filter "Department -eq 'Former Employees'" |
            Remove-ADUserAllGroups -Server DC01 -Credential $Credential

    .EXAMPLE
        Get-ADUser jsmith |
            Remove-ADUserAllGroups -OutLogPath C:\Logs -WhatIf

    .EXAMPLE
        Get-ADUser jsmith |
            Remove-ADUserAllGroups -OutLogPath C:\Logs\GroupRemoval.log
    #>

    [CmdletBinding(
        SupportsShouldProcess,
        ConfirmImpact = 'Medium'
    )]
    param (
        [Parameter(
            Mandatory,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            Position = 0
        )]
        [Alias(
            'Identity',
            'DistinguishedName',
            'SamAccountName',
            'UserPrincipalName'
        )]
        [object[]]$User,

        [string]$Server,

        [PSCredential]$Credential,

        [ValidateNotNullOrEmpty()]
        [string]$OutLogPath = (Get-Location).Path
    )

    begin {
        if (-not (Get-Command Write-LogMsg -ErrorAction SilentlyContinue)) {
            throw 'Write-LogMsg was not found in the current session.'
        }

        if (-not (Get-Command Get-ADUser -ErrorAction SilentlyContinue)) {
            throw 'The ActiveDirectory module is required.'
        }

        # Resolve relative paths against the current PowerShell location.
        $ExpandedLogPath = [Environment]::ExpandEnvironmentVariables(
            $OutLogPath
        )

        if (-not [System.IO.Path]::IsPathRooted($ExpandedLogPath)) {
            $ExpandedLogPath = Join-Path (
                Get-Location
            ).Path $ExpandedLogPath
        }

        $ExpandedLogPath = [System.IO.Path]::GetFullPath(
            $ExpandedLogPath
        )

        # An existing directory or a path without an extension is treated
        # as a directory. Otherwise, it is treated as a complete file path.
        $IsDirectory = if (
            Test-Path -LiteralPath $ExpandedLogPath -PathType Container
        ) {
            $true
        }
        elseif (
            Test-Path -LiteralPath $ExpandedLogPath -PathType Leaf
        ) {
            $false
        }
        else {
            [string]::IsNullOrWhiteSpace(
                [System.IO.Path]::GetExtension($ExpandedLogPath)
            )
        }

        if ($IsDirectory) {
            $LogDirectory = $ExpandedLogPath

            $LogFilePath = Join-Path $LogDirectory (
                'Remove-ADUserAllGroups_{0}.log' -f (
                    Get-Date -Format 'yyyyMMdd_HHmmss'
                )
            )
        }
        else {
            $LogFilePath = $ExpandedLogPath
            $LogDirectory = Split-Path -Path $LogFilePath -Parent
        }

        try {
            if (-not (Test-Path -LiteralPath $LogDirectory)) {
                $null = New-Item -Path $LogDirectory `
                    -ItemType Directory `
                    -Force `
                    -ErrorAction Stop
            }
        }
        catch {
            throw "Unable to create log directory '$LogDirectory': $($_.Exception.Message)"
        }

        $ConnectionParameters = @{}

        if ($PSBoundParameters.ContainsKey('Server')) {
            $ConnectionParameters.Server = $Server
        }

        if ($PSBoundParameters.ContainsKey('Credential')) {
            $ConnectionParameters.Credential = $Credential
        }

        $UsersProcessed = 0
        $GroupsRemoved  = 0
        $GroupsFailed   = 0
        $GroupsSkipped  = 0

        "Starting AD group removal. Log file: $LogFilePath" |
            Write-LogMsg -LogFilePath $LogFilePath
    }

    process {
        foreach ($InputUser in $User) {
            $UsersProcessed++

            # Determine the best identity value from the supplied object.
            if ($InputUser -is [string]) {
                $UserIdentity = $InputUser
            }
            elseif (
                $InputUser.PSObject.Properties['DistinguishedName'] -and
                $InputUser.DistinguishedName
            ) {
                $UserIdentity = $InputUser.DistinguishedName
            }
            elseif (
                $InputUser.PSObject.Properties['ObjectGUID'] -and
                $InputUser.ObjectGUID
            ) {
                $UserIdentity = $InputUser.ObjectGUID
            }
            elseif (
                $InputUser.PSObject.Properties['SamAccountName'] -and
                $InputUser.SamAccountName
            ) {
                $UserIdentity = $InputUser.SamAccountName
            }
            elseif (
                $InputUser.PSObject.Properties['UserPrincipalName'] -and
                $InputUser.UserPrincipalName
            ) {
                $UserIdentity = $InputUser.UserPrincipalName
            }
            else {
                $UserIdentity = [string]$InputUser
            }

            try {
                $ADUser = Get-ADUser `
                    -Identity $UserIdentity `
                    -Properties MemberOf, UserPrincipalName `
                    @ConnectionParameters `
                    -ErrorAction Stop
            }
            catch {
                "Unable to retrieve AD user '$UserIdentity': $($_.Exception.Message)" |
                    Write-LogMsg `
                        -LogLevel FAIL `
                        -LogFilePath $LogFilePath

                continue
            }

            $UserDisplayName = if ($ADUser.UserPrincipalName) {
                $ADUser.UserPrincipalName
            }
            elseif ($ADUser.SamAccountName) {
                $ADUser.SamAccountName
            }
            else {
                $ADUser.DistinguishedName
            }

            $GroupMemberships = @($ADUser.MemberOf)

            if ($GroupMemberships.Count -eq 0) {
                "'$UserDisplayName' has no direct group memberships to remove." |
                    Write-LogMsg `
                        -LogLevel INFO `
                        -LogFilePath $LogFilePath

                continue
            }

            "Found $($GroupMemberships.Count) direct group membership(s) for '$UserDisplayName'." |
                Write-LogMsg `
                    -LogLevel INFO `
                    -LogFilePath $LogFilePath

            foreach ($GroupDistinguishedName in $GroupMemberships) {
                $GroupName = $GroupDistinguishedName

                try {
                    $Group = Get-ADGroup `
                        -Identity $GroupDistinguishedName `
                        @ConnectionParameters `
                        -ErrorAction Stop

                    $GroupName = $Group.Name
                }
                catch {
                    "Could not resolve group '$GroupDistinguishedName' to a friendly name. The distinguished name will be used." |
                        Write-LogMsg `
                            -LogLevel WARN `
                            -LogFilePath $LogFilePath
                }

                $ShouldRemove = $PSCmdlet.ShouldProcess(
                    "$UserDisplayName -> $GroupName",
                    'Remove AD group membership'
                )

                if (-not $ShouldRemove) {
                    $GroupsSkipped++

                    $SkipMessage = if ($WhatIfPreference) {
                        "Would remove '$UserDisplayName' from '$GroupName'."
                    }
                    else {
                        "Removal of '$UserDisplayName' from '$GroupName' was not confirmed."
                    }

                    $SkipMessage |
                        Write-LogMsg `
                            -LogLevel INFO `
                            -LogFilePath $LogFilePath

                    continue
                }

                try {
                    Remove-ADGroupMember `
                        -Identity $GroupDistinguishedName `
                        -Members $ADUser.DistinguishedName `
                        @ConnectionParameters `
                        -Confirm:$false `
                        -ErrorAction Stop

                    $GroupsRemoved++

                    "Removed '$UserDisplayName' from '$GroupName'." |
                        Write-LogMsg `
                            -LogLevel INFO `
                            -LogFilePath $LogFilePath
                }
                catch {
                    $GroupsFailed++

                    "Failed to remove '$UserDisplayName' from '$GroupName': $($_.Exception.Message)" |
                        Write-LogMsg `
                            -LogLevel FAIL `
                            -LogFilePath $LogFilePath
                }
            }
        }
    }

    end {
        @"
Completed AD group removal.
Users processed: $UsersProcessed
Groups removed:  $GroupsRemoved
Groups failed:   $GroupsFailed
Groups skipped:  $GroupsSkipped
Log file:        $LogFilePath
"@ | Write-LogMsg `
            -LogLevel INFO `
            -LogFilePath $LogFilePath
    }
}

function Set-ADUserOffboardDisplayName {
    <#
    .SYNOPSIS
        Prepends "[Legacy]" to an Active Directory user's display name.

    .DESCRIPTION
        Accepts ADUser objects or user identities and changes the DisplayName
        attribute from:

            Noah Peltier

        To:

            [Legacy] Noah Peltier

        Users whose display name already begins with "[Legacy]" are skipped.

    .EXAMPLE
        Get-ADUser npeltier |
            Set-ADUserOffboardDisplayName

    .EXAMPLE
        Get-ADUser npeltier |
            Set-ADUserOffboardDisplayName `
                -Server DC01.apc.local `
                -Credential $Credential `
                -OutLogPath C:\Logs

    .EXAMPLE
        Get-ADUser -Filter "Enabled -eq '$false'" |
            Set-ADUserOffboardDisplayName -WhatIf
    #>

    [CmdletBinding(
        SupportsShouldProcess,
        ConfirmImpact = 'Medium'
    )]
    param (
        [Parameter(
            Mandatory,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName,
            Position = 0
        )]
        [Alias(
            'Identity',
            'DistinguishedName',
            'SamAccountName',
            'UserPrincipalName'
        )]
        [object[]]$User,

        [string]$Server,

        [PSCredential]$Credential,

        [ValidateNotNullOrEmpty()]
        [string]$OutLogPath = (Get-Location).Path
    )

    begin {
        if (-not (Get-Command Write-LogMsg -ErrorAction SilentlyContinue)) {
            throw 'Write-LogMsg was not found in the current session.'
        }

        if (-not (Get-Command Get-ADUser -ErrorAction SilentlyContinue)) {
            throw 'The ActiveDirectory module is required.'
        }

        $ExpandedLogPath = [Environment]::ExpandEnvironmentVariables(
            $OutLogPath
        )

        if (-not [System.IO.Path]::IsPathRooted($ExpandedLogPath)) {
            $ExpandedLogPath = Join-Path `
                -Path (Get-Location).Path `
                -ChildPath $ExpandedLogPath
        }

        $ExpandedLogPath = [System.IO.Path]::GetFullPath(
            $ExpandedLogPath
        )

        $IsDirectory = if (
            Test-Path -LiteralPath $ExpandedLogPath -PathType Container
        ) {
            $true
        }
        elseif (
            Test-Path -LiteralPath $ExpandedLogPath -PathType Leaf
        ) {
            $false
        }
        else {
            [string]::IsNullOrWhiteSpace(
                [System.IO.Path]::GetExtension($ExpandedLogPath)
            )
        }

        if ($IsDirectory) {
            $LogDirectory = $ExpandedLogPath

            $LogFilePath = Join-Path `
                -Path $LogDirectory `
                -ChildPath (
                    'Set-ADUserOffboardDisplayName_{0}.log' -f
                    (Get-Date -Format 'yyyyMMdd_HHmmss')
                )
        }
        else {
            $LogFilePath = $ExpandedLogPath
            $LogDirectory = Split-Path -Path $LogFilePath -Parent
        }

        try {
            if (-not (Test-Path -LiteralPath $LogDirectory)) {
                $null = New-Item `
                    -Path $LogDirectory `
                    -ItemType Directory `
                    -Force `
                    -ErrorAction Stop
            }
        }
        catch {
            throw "Unable to create log directory '$LogDirectory': $($_.Exception.Message)"
        }

        $ConnectionParameters = @{}

        if ($PSBoundParameters.ContainsKey('Server')) {
            $ConnectionParameters.Server = $Server
        }

        if ($PSBoundParameters.ContainsKey('Credential')) {
            $ConnectionParameters.Credential = $Credential
        }

        $UsersProcessed = 0
        $UsersUpdated   = 0
        $UsersSkipped   = 0
        $UsersFailed    = 0

        "Starting offboard display-name updates. Log file: $LogFilePath" |
            Write-LogMsg -LogFilePath $LogFilePath
    }

    process {
        foreach ($InputUser in $User) {
            $UsersProcessed++

            if ($InputUser -is [string]) {
                $UserIdentity = $InputUser
            }
            elseif (
                $InputUser.PSObject.Properties['DistinguishedName'] -and
                $InputUser.DistinguishedName
            ) {
                $UserIdentity = $InputUser.DistinguishedName
            }
            elseif (
                $InputUser.PSObject.Properties['ObjectGUID'] -and
                $InputUser.ObjectGUID
            ) {
                $UserIdentity = $InputUser.ObjectGUID
            }
            elseif (
                $InputUser.PSObject.Properties['SamAccountName'] -and
                $InputUser.SamAccountName
            ) {
                $UserIdentity = $InputUser.SamAccountName
            }
            elseif (
                $InputUser.PSObject.Properties['UserPrincipalName'] -and
                $InputUser.UserPrincipalName
            ) {
                $UserIdentity = $InputUser.UserPrincipalName
            }
            else {
                $UserIdentity = [string]$InputUser
            }

            try {
                $ADUser = Get-ADUser `
                    -Identity $UserIdentity `
                    -Properties DisplayName, UserPrincipalName `
                    @ConnectionParameters `
                    -ErrorAction Stop
            }
            catch {
                $UsersFailed++

                "Unable to retrieve AD user '$UserIdentity': $($_.Exception.Message)" |
                    Write-LogMsg `
                        -LogLevel FAIL `
                        -LogFilePath $LogFilePath

                continue
            }

            $UserDescription = if ($ADUser.UserPrincipalName) {
                $ADUser.UserPrincipalName
            }
            else {
                $ADUser.SamAccountName
            }

            if ([string]::IsNullOrWhiteSpace($ADUser.DisplayName)) {
                $UsersFailed++

                "User '$UserDescription' does not have a display name." |
                    Write-LogMsg `
                        -LogLevel FAIL `
                        -LogFilePath $LogFilePath

                continue
            }

            if ($ADUser.DisplayName -match '^\[Legacy\](?:\s|$)') {
                $UsersSkipped++

                "Skipped '$UserDescription' because its display name is already '$($ADUser.DisplayName)'." |
                    Write-LogMsg `
                        -LogLevel INFO `
                        -LogFilePath $LogFilePath

                continue
            }

            $OldDisplayName = $ADUser.DisplayName
            $NewDisplayName = "[Legacy] $OldDisplayName"

            $ShouldUpdate = $PSCmdlet.ShouldProcess(
                $UserDescription,
                "Change display name from '$OldDisplayName' to '$NewDisplayName'"
            )

            if (-not $ShouldUpdate) {
                $UsersSkipped++

                $Message = if ($WhatIfPreference) {
                    "Would change '$UserDescription' from '$OldDisplayName' to '$NewDisplayName'."
                }
                else {
                    "Display-name change for '$UserDescription' was not confirmed."
                }

                $Message |
                    Write-LogMsg `
                        -LogLevel INFO `
                        -LogFilePath $LogFilePath

                continue
            }

            try {
                Set-ADUser `
                    -Identity $ADUser.DistinguishedName `
                    -DisplayName $NewDisplayName `
                    @ConnectionParameters `
                    -ErrorAction Stop

                $UsersUpdated++

                "Changed '$UserDescription' display name from '$OldDisplayName' to '$NewDisplayName'." |
                    Write-LogMsg `
                        -LogLevel INFO `
                        -LogFilePath $LogFilePath
            }
            catch {
                $UsersFailed++

                "Failed to update '$UserDescription': $($_.Exception.Message)" |
                    Write-LogMsg `
                        -LogLevel FAIL `
                        -LogFilePath $LogFilePath
            }
        }
    }

    end {
        @"
Completed offboard display-name updates.
Users processed: $UsersProcessed
Users updated:   $UsersUpdated
Users skipped:   $UsersSkipped
Users failed:    $UsersFailed
Log file:        $LogFilePath
"@ |
            Write-LogMsg `
                -LogLevel INFO `
                -LogFilePath $LogFilePath
    }
}


function Invoke-Termination {
    [CmdletBinding(
        SupportsShouldProcess,
        ConfirmImpact = 'High'
    )]
    param(
        [Parameter(
            Mandatory,
            Position = 0,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [Alias(
            'SamAccountName',
            'UserPrincipalName',
            'DistinguishedName'
        )]
        [object]$Identity,

        [Parameter()]
        [Alias('TargetPath')]
        [ValidateNotNullOrEmpty()]
        [string]$MoveToOu,

        [Parameter()]
        [switch]$RemoveFromAllGroups,

        [Parameter()]
        [switch]$ClearManagerField,

        [Parameter()]
        [switch]$SetExchangeOnlineCloudManaged,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$Server,

        [Parameter()]
        [System.Management.Automation.PSCredential]$Credential
    )

    process {
        $adConnectionParameters = @{
            ErrorAction = 'Stop'
        }

        if ($PSBoundParameters.ContainsKey('Server')) {
            $adConnectionParameters.Server = $Server
        }

        if (
            $PSBoundParameters.ContainsKey('Credential') -and
            $null -ne $Credential
        ) {
            $adConnectionParameters.Credential = $Credential
        }

        try {
            $user = Get-ADUser `
                -Identity $Identity `
                -Properties @(
                    'DisplayName'
                    'DistinguishedName'
                    'Enabled'
                    'Mail'
                    'Manager'
                    'ObjectGUID'
                    'SamAccountName'
                    'UserPrincipalName'
                ) `
                @adConnectionParameters
        }
        catch {
            Write-LogMsg `
                -LogLevel FAIL `
                -InputObject "Unable to resolve AD user '$Identity'. $($_.Exception.Message)"

            return
        }

        $userLabel = if ($user.UserPrincipalName) {
            "$($user.DisplayName) <$($user.UserPrincipalName)>"
        }
        else {
            "$($user.DisplayName) <$($user.SamAccountName)>"
        }

        $completedActions = [System.Collections.Generic.List[string]]::new()
        $failedActions = [System.Collections.Generic.List[string]]::new()
        $skippedActions = [System.Collections.Generic.List[string]]::new()

        Write-LogMsg `
            -LogLevel INFO `
            -InputObject "Beginning termination processing for $userLabel."

        # Use ObjectGUID so that moving or renaming the user does not invalidate
        # the identity used by later AD commands.
        $adIdentityParameters = @{
            Identity    = $user.ObjectGUID
            ErrorAction = 'Stop'
        }

        if ($PSBoundParameters.ContainsKey('Server')) {
            $adIdentityParameters.Server = $Server
        }

        if (
            $PSBoundParameters.ContainsKey('Credential') -and
            $null -ne $Credential
        ) {
            $adIdentityParameters.Credential = $Credential
        }

        #region Disable account

        if (-not $user.Enabled) {
            [void]$skippedActions.Add('Disable AD account')

            Write-LogMsg `
                -LogLevel INFO `
                -InputObject "The AD account for $userLabel is already disabled."
        }
        elseif ($PSCmdlet.ShouldProcess($userLabel, 'Disable AD account')) {
            try {
                Disable-ADAccount @adIdentityParameters

                [void]$completedActions.Add('Disable AD account')

                Write-LogMsg `
                    -LogLevel INFO `
                    -InputObject "Disabled the AD account for $userLabel."
            }
            catch {
                [void]$failedActions.Add('Disable AD account')

                Write-LogMsg `
                    -LogLevel FAIL `
                    -InputObject "Failed to disable the AD account for $userLabel. $($_.Exception.Message)"
            }
        }
        else {
            [void]$skippedActions.Add('Disable AD account')
        }

        #endregion

        #region Prefix display name

        $currentDisplayName = if ($user.DisplayName) {
            $user.DisplayName.Trim()
        }
        else {
            $user.Name.Trim()
        }

        if ($currentDisplayName -match '^\[Legacy\](?:\s|$)') {
            [void]$skippedActions.Add('Set legacy display name')

            Write-LogMsg `
                -LogLevel INFO `
                -InputObject "The display name for $userLabel already begins with '[Legacy]'."
        }
        else {
            $legacyDisplayName = "[Legacy] $currentDisplayName"

            if (
                $PSCmdlet.ShouldProcess(
                    $userLabel,
                    "Set display name to '$legacyDisplayName'"
                )
            ) {
                try {
                    Set-ADUser `
                        @adIdentityParameters `
                        -DisplayName $legacyDisplayName

                    [void]$completedActions.Add('Set legacy display name')

                    Write-LogMsg `
                        -LogLevel INFO `
                        -InputObject "Changed the display name for $userLabel to '$legacyDisplayName'."

                    $user.DisplayName = $legacyDisplayName
                }
                catch {
                    [void]$failedActions.Add('Set legacy display name')

                    Write-LogMsg `
                        -LogLevel FAIL `
                        -InputObject "Failed to change the display name for $userLabel. $($_.Exception.Message)"
                }
            }
            else {
                [void]$skippedActions.Add('Set legacy display name')
            }
        }

        #endregion

        #region Clear manager

        if ($ClearManagerField) {
            if (-not $user.Manager) {
                [void]$skippedActions.Add('Clear manager')

                Write-LogMsg `
                    -LogLevel INFO `
                    -InputObject "The manager field for $userLabel is already empty."
            }
            elseif ($PSCmdlet.ShouldProcess($userLabel, 'Clear manager field')) {
                try {
                    Set-ADUser `
                        @adIdentityParameters `
                        -Clear 'manager'

                    [void]$completedActions.Add('Clear manager')

                    Write-LogMsg `
                        -LogLevel INFO `
                        -InputObject "Cleared the manager field for $userLabel."
                }
                catch {
                    [void]$failedActions.Add('Clear manager')

                    Write-LogMsg `
                        -LogLevel FAIL `
                        -InputObject "Failed to clear the manager field for $userLabel. $($_.Exception.Message)"
                }
            }
            else {
                [void]$skippedActions.Add('Clear manager')
            }
        }

        #endregion

        #region Remove group memberships

        if ($RemoveFromAllGroups) {
            if (
                $PSCmdlet.ShouldProcess(
                    $userLabel,
                    'Remove all removable AD group memberships'
                )
            ) {
                try {
                    $removeGroupParameters = @{}

                    if ($PSBoundParameters.ContainsKey('Server')) {
                        $removeGroupParameters.Server = $Server
                    }

                    if (
                        $PSBoundParameters.ContainsKey('Credential') -and
                        $null -ne $Credential
                    ) {
                        $removeGroupParameters.Credential = $Credential
                    }

                    # Remove-AdUserAllGroups is expected to log each individual
                    # group removal through Write-LogMsg.
                    & {
                        $ErrorActionPreference = 'Stop'
                        $user | Remove-AdUserAllGroups @removeGroupParameters
                    }

                    [void]$completedActions.Add('Remove AD groups')

                    Write-LogMsg `
                        -LogLevel INFO `
                        -InputObject "Finished removing AD group memberships for $userLabel."
                }
                catch {
                    [void]$failedActions.Add('Remove AD groups')

                    Write-LogMsg `
                        -LogLevel FAIL `
                        -InputObject "Failed while removing AD group memberships for $userLabel. $($_.Exception.Message)"
                }
            }
            else {
                [void]$skippedActions.Add('Remove AD groups')
            }
        }

        #endregion

        #region Exchange attribute source of authority

        if ($SetExchangeOnlineCloudManaged) {
            $exchangeIdentity = if ($user.UserPrincipalName) {
                $user.UserPrincipalName
            }
            elseif ($user.Mail) {
                $user.Mail
            }
            else {
                $user.SamAccountName
            }

            if (
                $PSCmdlet.ShouldProcess(
                    $exchangeIdentity,
                    'Set Exchange attributes as cloud managed'
                )
            ) {
                try {
                    Set-Mailbox `
                        -Identity $exchangeIdentity `
                        -IsExchangeCloudManaged $true `
                        -ErrorAction Stop

                    [void]$completedActions.Add(
                        'Set Exchange Online cloud managed'
                    )

                    Write-LogMsg `
                        -LogLevel INFO `
                        -InputObject "Set Exchange attributes as cloud managed for $exchangeIdentity."
                }
                catch {
                    [void]$failedActions.Add(
                        'Set Exchange Online cloud managed'
                    )

                    Write-LogMsg `
                        -LogLevel FAIL `
                        -InputObject "Failed to set Exchange attributes as cloud managed for $exchangeIdentity. $($_.Exception.Message)"
                }
            }
            else {
                [void]$skippedActions.Add(
                    'Set Exchange Online cloud managed'
                )
            }
        }

        #endregion

        #region Move user

        # Move last because it changes the distinguished name.
        if ($MoveToOu) {
            if (
                $PSCmdlet.ShouldProcess(
                    $userLabel,
                    "Move AD object to '$MoveToOu'"
                )
            ) {
                try {
                    Move-ADObject `
                        @adIdentityParameters `
                        -TargetPath $MoveToOu

                    [void]$completedActions.Add('Move AD object')

                    Write-LogMsg `
                        -LogLevel INFO `
                        -InputObject "Moved $userLabel to '$MoveToOu'."
                }
                catch {
                    [void]$failedActions.Add('Move AD object')

                    Write-LogMsg `
                        -LogLevel FAIL `
                        -InputObject "Failed to move $userLabel to '$MoveToOu'. $($_.Exception.Message)"
                }
            }
            else {
                [void]$skippedActions.Add('Move AD object')
            }
        }

        #endregion

        if ($failedActions.Count -gt 0) {
            Write-LogMsg `
                -LogLevel WARN `
                -InputObject (
                    "Termination processing for $userLabel completed with " +
                    "$($failedActions.Count) failed action(s): " +
                    "$($failedActions -join ', ')."
                )
        }
        else {
            Write-LogMsg `
                -LogLevel INFO `
                -InputObject "Termination processing completed successfully for $userLabel."
        }

        [pscustomobject]@{
            PSTypeName       = 'APC.TerminationResult'
            SamAccountName   = $user.SamAccountName
            UserPrincipalName = $user.UserPrincipalName
            DisplayName      = $user.DisplayName
            Successful       = $failedActions.Count -eq 0
            CompletedActions = $completedActions.ToArray()
            FailedActions    = $failedActions.ToArray()
            SkippedActions   = $skippedActions.ToArray()
        }
    }
}

