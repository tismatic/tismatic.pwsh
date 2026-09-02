function New-AmazonConnectApp {
    <#>
    This script creates a new SAML application for Amazon Connect in Microsoft Entra ID (Azure AD) and assigns it to a security-enabled group.
    It also saves the application's signing certificate and federation metadata XML to the specified output path.

    .EXAMPLE
    New-AmazonConnectApp.ps1 -Company "MyCompany" -Environment "Production" -InstanceId "123456789012" -IamAccountNumber "123456789012"
<#>

    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Company,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Environment,

        [Parameter(Mandatory)]
        [guid]$InstanceId,

        [Parameter(Mandatory)]
        [ValidatePattern('^\d{12}$')]
        [string]$IamAccountNumber,

        [ValidateNotNullOrEmpty()]
        [string]$OutPath = (Get-Location).Path
    )

    # Connect-MgGraph must include Application.ReadWrite.All,
    # Policy.ReadWrite.ApplicationConfiguration, Group.ReadWrite.All, and
    # AppRoleAssignment.ReadWrite.All for this complete example.
    . (Join-Path $PSScriptRoot 'NewSamlApp.ps1')

    # Define the display names for the application and group
    $displayName = "Amazon Connect - $Company - $Environment"
    $groupDisplayName = "[App] $displayName"
    $escapedGroupDisplayName = $groupDisplayName.Replace("'", "''")
    $existingGroup = @(
        Get-MgGroup -Filter "displayName eq '$escapedGroupDisplayName'" -Property Id, DisplayName, MailNickname, SecurityEnabled -ErrorAction Stop
    )

    # Validate that the existing group is suitable for assignment
    if ($existingGroup.Count -gt 1) {
        throw "More than one group is named '$groupDisplayName'. Refusing to select one automatically."
    }

    if ($existingGroup.Count -eq 1 -and -not $existingGroup[0].SecurityEnabled) {
        throw "Existing group '$groupDisplayName' is not security enabled and cannot be reused for application assignment."
    }

    if (-not $PSCmdlet.ShouldProcess($displayName, 'Ensure the Amazon Connect SAML application, group, and assignment exist')) {
        return
    }

    # Create the SAML application with the specified parameters
    $template = [ordered]@{
        DisplayName               = $displayName
        IdentifierUri             = @(
            "https://signin.aws.amazon.com/saml-$Company-$Environment"
        )
        ReplyUrl                  = @(
            'https://signin.aws.amazon.com/saml'
        )
        RelayState                = "https://us-east-1.console.aws.amazon.com/connect/federate/$($InstanceId)?destination=%2Fconnect%2Fhome"

        ValueClaims               = @(
            @{
                Name      = 'Role'
                Namespace = 'https://aws.amazon.com/SAML/Attributes'
                Value     = "arn:aws:iam::${IamAccountNumber}:role/Spectrum-${Company}-Connect-${Environment}-SAML,arn:aws:iam::${IamAccountNumber}:saml-provider/Spectrum-Entra-${Company}-${Environment}"
            }
        )
        SamlClaims                = @(
            @{
                Name            = 'RoleSessionName'
                Namespace       = 'https://aws.amazon.com/SAML/Attributes'
                SourceAttribute = 'user.userprincipalname'
            }
        )
        CreateSigningCertificate  = $true
        SetCertificateAsPreferred = $true
        RequireAssignment         = $true
    }

    $newApp = New-MgSamlApp @template -Confirm:$false
    if (-not $newApp) {
        return
    }

    <#
    Assigning the new application to a group is required for users to be able to sign in.
    If the group does not exist, it will be created.
    If the group already exists, it will be reused.
    If the group exists but is not security enabled, an error will be thrown.
#> 
    try {
        $group = if ($existingGroup.Count -eq 1) {
            $existingGroup[0]
        }
        else {
            $null
        }
        $reusedGroup = $null -ne $group

        $assignment = if ($group) {
            @(
                Get-MgServicePrincipalAppRoleAssignedTo -ServicePrincipalId $newApp.ServicePrincipalId -All -ErrorAction Stop | Where-Object { $_.PrincipalId -eq $group.Id }
            )[0]
        }
        $reusedAssignment = $null -ne $assignment

        if (-not $assignment) {
            $appRoles = @($newApp.ServicePrincipal.AppRoles)
            if ($appRoles.Count -eq 0) {
                $appRoleId = [guid]::Empty
            }
            else {
                $assignableRoles = @(
                    $appRoles | Where-Object {
                        $_.IsEnabled -and $_.AllowedMemberTypes -contains 'User'
                    }
                )
                if ($assignableRoles.Count -eq 0) {
                    throw 'The enterprise application declares app roles, but none are enabled for user or group assignment.'
                }
                $appRoleId = $assignableRoles[0].Id
            }

            if (-not $group) {
                $GroupSplat = @{
                    DisplayName     = $groupDisplayName
                    MailEnabled     = $false
                    SecurityEnabled = $true
                    MailNickname    = "AmazonConnect-$Company-$Environment"
                }
                $group = New-MgGroup @GroupSplat -ErrorAction Stop
            }

            $AssignmentSplat = @{
                GroupId     = $group.Id
                PrincipalId = $group.Id
                ResourceId  = $newApp.ServicePrincipalId
                AppRoleId   = $appRoleId
            }
            $assignment = New-MgGroupAppRoleAssignment @AssignmentSplat -ErrorAction Stop
        }

        $certificateFile = Save-MgAppCertificate -Certificate $newApp.Certificate -DisplayName $newApp.DisplayName -OutPath $OutPath
        $metadataFile = Save-MgAppFederationXml -AppId $newApp.AppId -DisplayName $newApp.DisplayName -OutPath $OutPath
        $archiveFile = Compress-MgAppArtifact -DisplayName $newApp.DisplayName -CertificateFile $certificateFile -MetadataFile $metadataFile -OutPath $OutPath

        [pscustomobject]@{
            Application       = $newApp
            Group             = $group
            Assignment        = $assignment
            CertificateFile   = $certificateFile
            MetadataFile      = $metadataFile
            ArchiveFile       = $archiveFile
            ReusedApplication = $newApp.ReusedExisting
            ReusedGroup       = $reusedGroup
            ReusedAssignment  = $reusedAssignment
        }
    }
    catch {
        $message = "Amazon Connect post-configuration failed. The application '$($newApp.DisplayName)' with app ID '$($newApp.AppId)' was not deleted. $($_.Exception.Message)"
        throw [System.InvalidOperationException]::new($message, $_.Exception)
    }
}