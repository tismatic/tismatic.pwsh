function Get-MgUserGroupReport {
    [CmdletBinding()]
    param (
        [Parameter(
            Mandatory,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [Alias('UserId', 'UPN')]
        [string[]]$UserPrincipalName,

        [switch]$Transitive
    )

    begin {
        $Properties = @(
            'id'
            'displayName'
            'mail'
            'groupTypes'
            'mailEnabled'
            'securityEnabled'
            'resourceProvisioningOptions'
            'membershipRule'
            'onPremisesSamAccountName'
            'onPremisesDomainName'
            'onPremisesSyncEnabled'
            'onPremisesSecurityIdentifier'
            'onPremisesLastSyncDateTime'
        )

        $Command = if ($Transitive) {
            'Get-MgUserTransitiveMemberOfAsGroup'
        }
        else {
            'Get-MgUserMemberOfAsGroup'
        }
    }

    process {
        foreach ($UPN in $UserPrincipalName) {
            try {
                $Groups = & $Command `
                    -UserId $UPN `
                    -Property $Properties `
                    -All `
                    -ErrorAction Stop
            }
            catch {
                Write-Error "Unable to retrieve group memberships for '$UPN': $($_.Exception.Message)"
                continue
            }

            foreach ($Group in $Groups) {
                $IsUnified = $Group.GroupTypes -contains 'Unified'
                $IsDynamic = $Group.GroupTypes -contains 'DynamicMembership'
                $IsTeam    = $Group.ResourceProvisioningOptions -contains 'Team'

                $Type = if ($IsUnified -and $IsTeam) {
                    'Microsoft Team'
                }
                elseif ($IsUnified) {
                    'Microsoft 365 Group'
                }
                elseif ($Group.MailEnabled -and $Group.SecurityEnabled) {
                    'Mail-Enabled Security Group'
                }
                elseif ($Group.SecurityEnabled) {
                    'Security Group'
                }
                elseif ($Group.MailEnabled) {
                    'Distribution Group'
                }
                else {
                    'Other Group'
                }

                [pscustomobject]@{
                    UserPrincipalName = $UPN
                    DisplayName       = $Group.DisplayName
                    GroupId           = $Group.Id
                    Mail              = $Group.Mail
                    GroupType         = $Type
                    IsDirect          = -not $Transitive
                    IsDynamicGroup    = $IsDynamic
                    MembershipRule    = $Group.MembershipRule
                    IsCloudOnly       = $Group.OnPremisesSyncEnabled -ne $true
                    OnPremSAM         = $Group.OnPremisesSamAccountName
                    OnPremDomain      = $Group.OnPremisesDomainName
                    OnPremSyncEnabled = $Group.OnPremisesSyncEnabled
                    OnPremSID         = $Group.OnPremisesSecurityIdentifier
                    OnPremLastSync    = $Group.OnPremisesLastSyncDateTime
                }
            }
        }
    }
}