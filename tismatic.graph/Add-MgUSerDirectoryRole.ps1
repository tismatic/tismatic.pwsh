function Add-MgUserDirectoryRole {
    [CmdletBinding(SupportsShouldProcess)]
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

            $cacheExpired = -not $script:MgDirectoryRoleCompletionCacheTime -or
                $script:MgDirectoryRoleCompletionCacheTime -lt (Get-Date).AddMinutes(-10)

            if (-not $script:MgDirectoryRoleCompletionCache -or $cacheExpired) {
                try {
                    $script:MgDirectoryRoleCompletionCache = @(
                        Get-MgRoleManagementDirectoryRoleDefinition -All -ErrorAction Stop |
                            Sort-Object DisplayName
                    )

                    $script:MgDirectoryRoleCompletionCacheTime = Get-Date
                }
                catch {
                    return
                }
            }

            $script:MgDirectoryRoleCompletionCache |
                Where-Object DisplayName -Like "$WordToComplete*" |
                ForEach-Object {
                    $completionText = "'$($_.DisplayName.Replace("'", "''"))'"

                    [System.Management.Automation.CompletionResult]::new(
                        $completionText,
                        $_.DisplayName,
                        [System.Management.Automation.CompletionResultType]::ParameterValue,
                        "$($_.DisplayName)`n$($_.Description)"
                    )
                }
        })]
        [string[]]$RoleName,

        [string]$DirectoryScopeId = '/'
    )

    $User = Get-MgUser -UserId $UserId -ErrorAction Stop

    $roleDefinitions = @(
        Get-MgRoleManagementDirectoryRoleDefinition -All -ErrorAction Stop
    )

    foreach ($requestedRoleName in $RoleName) {
        $Role = @(
            $roleDefinitions |
                Where-Object DisplayName -EQ $requestedRoleName
        )

        if ($Role.Count -eq 0) {
            Write-Error "Directory role '$requestedRoleName' was not found."
            continue
        }

        if ($Role.Count -gt 1) {
            Write-Error "More than one directory role matched '$requestedRoleName'."
            continue
        }

        $existingFilterParts = @(
            "principalId eq '$($User.Id)'"
            "roleDefinitionId eq '$($Role.Id)'"
            "directoryScopeId eq '$DirectoryScopeId'"
        )

        $existingFilter = $existingFilterParts -join ' and '

        $ExistingAssignment = Get-MgRoleManagementDirectoryRoleAssignment -Filter $existingFilter

        if ($ExistingAssignment) {
            Write-Warning "$($User.UserPrincipalName) already has the '$($Role.DisplayName)' role at scope '$DirectoryScopeId'."
            $ExistingAssignment
            continue
        }

        $assignmentParameters = @{
            PrincipalId      = $User.Id
            RoleDefinitionId = $Role.Id
            DirectoryScopeId = $DirectoryScopeId
        }

        if ($PSCmdlet.ShouldProcess(
            $User.UserPrincipalName,
            "Assign directory role '$($Role.DisplayName)'"
        )) {
            New-MgRoleManagementDirectoryRoleAssignment @assignmentParameters
        }
    }
}