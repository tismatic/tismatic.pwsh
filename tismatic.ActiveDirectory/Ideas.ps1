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

function Set-ADUserOffboardDisplayName {
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

        [string]$Server = (Get-ADdomain).dnsroot,

        [PSCredential]$Credential,

        [ValidateNotNullOrEmpty()]
        [string]$OutLogPath = (Get-Location).Path
    )

    if ($User.PSObject.Properties['UserPrincipalName']) {
        $UserIdentity = $InputUser.UserPrincipalName
    }
    elseif ($User -is [String]) {
        $UserIdentity = Get-ADUser 
    }
}

