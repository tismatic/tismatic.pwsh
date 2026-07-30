function Remove-MgUserDirectoryRole {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory)]
        [Alias('UserPrincipalName')]
        [string]$UserId,

        [Parameter(Mandatory)]
        [ArgumentCompleter({
            param(
                $CommandName,
                $ParameterName,
                $WordToComplete,
                $CommandAst,
                $FakeBoundParameters
            )

            $boundUserId = [string]$FakeBoundParameters['UserId']

            if ([string]::IsNullOrWhiteSpace($boundUserId)) {
                return
            }

            $scopeId = if ($FakeBoundParameters.ContainsKey('DirectoryScopeId')) {
                [string]$FakeBoundParameters['DirectoryScopeId']
            }
            else {
                '/'
            }

            try {
                $user = Get-MgUser -UserId $boundUserId -ErrorAction Stop
                $cacheKey = "$($user.Id)|$scopeId"

                if (-not $script:MgAssignedRoleCompletionCache) {
                    $script:MgAssignedRoleCompletionCache = @{}
                }

                $cachedResult = $script:MgAssignedRoleCompletionCache[$cacheKey]

                if (-not $cachedResult -or $cachedResult.ExpiresAt -lt [datetime]::UtcNow) {
                    $assignments = @(
                        Get-MgRoleManagementDirectoryRoleAssignment -Filter "principalId eq '$($user.Id)'" -All -ErrorAction Stop |
                            Where-Object DirectoryScopeId -EQ $scopeId
                    )

                    $roleDefinitionIds = @(
                        $assignments.RoleDefinitionId |
                            Sort-Object -Unique
                    )

                    $roleDefinitions = if ($roleDefinitionIds.Count -gt 0) {
                        @(
                            Get-MgRoleManagementDirectoryRoleDefinition -All -ErrorAction Stop |
                                Where-Object Id -In $roleDefinitionIds |
                                Sort-Object DisplayName
                        )
                    }
                    else {
                        @()
                    }

                    $cachedResult = [pscustomobject]@{
                        ExpiresAt = [datetime]::UtcNow.AddMinutes(2)
                        Roles     = $roleDefinitions
                    }

                    $script:MgAssignedRoleCompletionCache[$cacheKey] = $cachedResult
                }

                $cachedResult.Roles |
                    Where-Object DisplayName -Like "$WordToComplete*" |
                    Sort-Object DisplayName -Unique |
                    ForEach-Object {
                        $completionText = "'$($_.DisplayName.Replace("'", "''"))'"
                        $toolTip = @(
                            $_.DisplayName
                            "Scope: $scopeId"
                            $_.Description
                        ) -join [Environment]::NewLine

                        [System.Management.Automation.CompletionResult]::new(
                            $completionText,
                            $_.DisplayName,
                            [System.Management.Automation.CompletionResultType]::ParameterValue,
                            $toolTip
                        )
                    }
            }
            catch {
                return
            }
        })]
        [string[]]$RoleName,

        [string]$DirectoryScopeId = '/'
    )

    $user = Get-MgUser -UserId $UserId -ErrorAction Stop

    $assignments = @(
        Get-MgRoleManagementDirectoryRoleAssignment -Filter "principalId eq '$($user.Id)'" -All -ErrorAction Stop |
            Where-Object DirectoryScopeId -EQ $DirectoryScopeId
    )

    if ($assignments.Count -eq 0) {
        Write-Warning "$($user.UserPrincipalName) has no direct role assignments at scope '$DirectoryScopeId'."
        return
    }

    $assignedRoleDefinitionIds = @(
        $assignments.RoleDefinitionId |
            Sort-Object -Unique
    )

    $roleDefinitions = @(
        Get-MgRoleManagementDirectoryRoleDefinition -All -ErrorAction Stop |
            Where-Object Id -In $assignedRoleDefinitionIds
    )

    foreach ($requestedRoleName in $RoleName) {
        $matchingRoleDefinitions = @(
            $roleDefinitions |
                Where-Object DisplayName -EQ $requestedRoleName
        )

        if ($matchingRoleDefinitions.Count -eq 0) {
            Write-Warning "$($user.UserPrincipalName) does not have a direct '$requestedRoleName' assignment at scope '$DirectoryScopeId'."
            continue
        }

        if ($matchingRoleDefinitions.Count -gt 1) {
            Write-Error "More than one role definition matched '$requestedRoleName'."
            continue
        }

        $roleDefinition = $matchingRoleDefinitions[0]

        $matchingAssignments = @(
            $assignments |
                Where-Object RoleDefinitionId -EQ $roleDefinition.Id
        )

        foreach ($assignment in $matchingAssignments) {
            $target = "$($user.UserPrincipalName) at scope '$DirectoryScopeId'"
            $action = "Remove directory role '$($roleDefinition.DisplayName)'"

            if (-not $PSCmdlet.ShouldProcess($target, $action)) {
                continue
            }

            try {
                $removed = Remove-MgRoleManagementDirectoryRoleAssignment -UnifiedRoleAssignmentId $assignment.Id -PassThru -Confirm:$false -ErrorAction Stop

                if (-not $removed) {
                    throw "Microsoft Graph did not confirm removal of assignment '$($assignment.Id)'."
                }

                [pscustomobject]@{
                    UserPrincipalName = $user.UserPrincipalName
                    RoleName         = $roleDefinition.DisplayName
                    DirectoryScopeId = $DirectoryScopeId
                    AssignmentId     = $assignment.Id
                    Removed          = $true
                }
            }
            catch {
                Write-Error "Failed to remove '$($roleDefinition.DisplayName)' from '$($user.UserPrincipalName)': $($_.Exception.Message)"
            }
        }
    }

    if ($script:MgAssignedRoleCompletionCache) {
        $cacheKey = "$($user.Id)|$DirectoryScopeId"
        [void]$script:MgAssignedRoleCompletionCache.Remove($cacheKey)
    }
}