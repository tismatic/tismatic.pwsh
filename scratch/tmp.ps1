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
        $GroupsRemoved = 0
        $GroupsFailed = 0
        $GroupsSkipped = 0

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
function Write-LogMsg {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [Alias('Message')]
        [AllowNull()]
        [object]$InputObject,

        [ValidateSet('FAIL', 'INFO', 'WARN')]
        [string]$LogLevel,

        [string]$LogFilePath
    )

    process {
        if ($env:LogFilePath) {
            $LogFilePath = $env:LogFilePath
        }

        $autoLevel = 'INFO'
        $message = ''

        switch ($InputObject) {
            { $_ -is [System.Management.Automation.ErrorRecord] } {
                $autoLevel = 'FAIL'

                if ($null -ne $_.Exception -and -not [string]::IsNullOrEmpty($_.Exception.Message)) {
                    $message = $_.Exception.Message
                }
                else {
                    $message = $_.ToString()
                }

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

                if ($md -is [string]) {
                    $message = $md
                }
                elseif ($null -ne $md) {
                    $message = ($md | Out-String).Trim()
                }
                else {
                    $message = $_.ToString()
                }

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
                if ($null -eq $InputObject) {
                    $message = ''
                }
                elseif ($InputObject.PSObject.Properties['Message']) {
                    $message = [string]$InputObject.Message
                }
                else {
                    $message = ($InputObject | Out-String).TrimEnd()
                }
            }
        }

        if ($PSBoundParameters.ContainsKey('LogLevel')) {
            $effectiveLevel = $LogLevel
        }
        else {
            $effectiveLevel = $autoLevel
        }

        $prefix = switch ($effectiveLevel) {
            'FAIL' { '[ FAIL ]' }
            'WARN' { '[ WARN ]' }
            default { '[ INFO ]' }
        }

        $timestamp = Get-Date -Format '[ yyyy-MM-dd HH:mm:ss.fff ]'
        $logMsg = "$timestamp $prefix $message"

        if ($LogFilePath) {
            try {
                Add-Content -LiteralPath $LogFilePath -Value $logMsg -Encoding UTF8 -ErrorAction Stop
            }
            catch {
                Write-Warning "Failed to write to log file '$LogFilePath': $($_.Exception.Message)"
            }
        }

        $logMsg
    }
}
#$users = get-aduser -filter * -SearchBase "OU=Disabled Users,DC=vanguarddealerservices,DC=local" -Server vanguarddealerservices.local
#$users | Remove-ADUserAllGroups -server vanguarddealerservices.local -OutLogPath C:\Logs\VDS_Remove_Groups.log


$ConnectParams = @{
    AuthScope             = 'https://service.flow.microsoft.com/'
    SkipContextPopulation = $true
    Scope                 = 'Process'
}

Connect-AzAccount @ConnectParams

$Auth = Get-PowerAutomateAuth -TenantId $TenantId
$Auth | Select-Object TenantId, ExpiresOn

$fails = Get-PowerAutomateFailedRun -StartTime '2026-08-21T08:00:00Z' -EndTime '2026-08-24T17:00:00Z'
$params = @{
    Run               = $fails
    EnvironmentName   = 'Default-a924863a-a67c-44b5-b1af-9735ccf85acb'
    FlowName          = '2728e79d-802e-44a6-8c44-d6b63c16bcab'
    TenantId          = $TenantId
    RecoveryName      = 'MMSPrivacy-20260821-20260824'
    RecoveryRoot      = $PWD
    DelayMilliseconds = 2000
    MaxRetries        = 5
    MaxRuns           = 5
    Force             = $true
}

Restart-PowerAutomateRun @params
