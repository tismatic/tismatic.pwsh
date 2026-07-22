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



function Find-MGDevice {
    [CmdletBinding()]
    param(
        [Parameter(
            Mandatory,
            Position = 0,
            ValueFromRemainingArguments,
            ValueFromPipeline
        )]
        [string[]]$SearchString
    )
    begin {
        $Properties = 'Id,AccountEnabled,ApproximateLastSignInDateTime,DeviceId,DeviceMetadata,DeviceOwnership,DeviceOSType,DeviceOSVersion,DisplayName,IsCompliant,IsManaged,Manufacturer,Model,OnPremisesLastSyncDateTime,OnPremisesSyncEnabled,OperatingSystem,PhysicalIds,ProfileType,RegisteredOwners,RegisteredUsers,SystemLabels,SystemTags,TrustType'
    }

    process {
        $SearchText = ($SearchString -join ' ').Trim()

        $Search = '"displayName:{0}" OR "deviceId:{0}" OR "operatingSystem:{0}"' -f $SearchText

        Write-Verbose "Graph search: $Search"

        #$Device = Get-MgDevice -Search $Search -ConsistencyLevel eventual -CountVariable ResultCount -All -Property $Properties
        $Device = get-mgdevice -filter "(displayname eq '$SearchString')" -ExpandProperty registeredOwners -ConsistencyLevel eventual

        if ($Device -and $device.OperatingSystem -eq 'Windows') {
            [pscustomobject]@{
                Id                            = $device.Id
                Displayname                   = $device.DisplayName
                OS                            = "$($device.OperatingSystem) $(([version]$device.OperatingSystemVersion).Build -ge 22000 ? '11' : '10')"
                OwnerDisplayName              = $device.RegisteredOwners.AdditionalProperties.displayName
                OwnerUserPrincipalName        = $device.RegisteredOwners.AdditionalProperties.userPrincipalName
                OwnerEmailAddress             = $device.RegisteredOwners.AdditionalProperties.mail
                OwnerMobilePhone              = $device.RegisteredOwners.AdditionalProperties.mobilePhone
                OwnerADAccountName            = $device.RegisteredOwners.AdditionalProperties.onPremisesSamAccountName
                OwnerAdDomain                 = $device.RegisteredOwners.AdditionalProperties.onPremisesDomainName
                ApproximateLastSignInDateTime = $device.ApproximateLastSignInDateTime
                TrustType                     = $device.TrustType
            }
        }
        else {
            Write-Warning "No device found matching '$SearchText'."
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
			$Global:MSProductNamesCSV = (Invoke-RestMethod -Uri $CSVUri | ConvertFrom-Csv | select Product_Display_Name,String_Id,GUID -Unique)
		}
	}
		
	process {
        $Global:MSProductNamesCSV | Where-Object {$_.Product_Display_Name -eq $SearchString -or $_.String_Id -eq $SearchString} | Select-Object -first 1
    }
}