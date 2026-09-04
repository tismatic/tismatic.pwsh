Write-host "You shouldn't see this"
$ADProperties = @(
    'DisplayName'
    'Mail'
    'ProxyAddresses'
    'EmployeeID'
)

$AllADUsers = Get-TrustedAdDomains | ForEach-Object {
    Start-ThreadJob -ScriptBlock {
        param($Server, $Properties)

        $ProgressPreference = 'SilentlyContinue'

        $Parameters = @{
            Filter      = '*'
            Properties  = $Properties
            Server      = $Server
            ErrorAction = 'SilentlyContinue'
        }

        Get-ADUser @Parameters
    } -ArgumentList $_, $ADProperties
} | Receive-Job -Wait -AutoRemoveJob

$Properties = 'Id,AccountEnabled,AgeGroup,OfficeLocation,AssignedLicenses,AssignedPlans,City,CompanyName,ConsentProvidedForMinor,Country,CreationType,Department,DisplayName,GivenName,OnPremisesImmutableId,JobTitle,LegalAgeGroupClassification,Mail,MailNickName,MobilePhone,OnPremisesSecurityIdentifier,OtherMails,PasswordPolicies,PasswordProfile,PostalCode,PreferredLanguage,ProvisionedPlans,OnPremisesProvisioningErrors,ProxyAddresses,RefreshTokensValidFromDateTime,ShowInAddressList,State,StreetAddress,Surname,BusinessPhones,UsageLocation,UserPrincipalName,ExternalUserState,ExternalUserStateChangeDateTime,UserType,OnPremisesLastSyncDateTime,ImAddresses,SecurityIdentifier,OnPremisesUserPrincipalName,ServiceProvisioningErrors,IsResourceAccount,OnPremisesExtensionAttributes,DeletedDateTime,OnPremisesSyncEnabled,EmployeeType,EmployeeHireDate,CreatedDateTime,EmployeeOrgData,preferredDataLocation,Identities,onPremisesSamAccountName,EmployeeId,EmployeeLeaveDateTime,AuthorizationInfo,FaxNumber,OnPremisesDistinguishedName,OnPremisesDomainName,IsLicenseReconciliationNeeded,signInSessionsValidFromDateTime,registeredDevices'
$AllMGUsers = Get-MgUser -All -Property $Properties

$MgByUpn = @{}
$MgByEmployeeId = @{}
$MgBySid = @{}
$MgByMail = @{}

foreach ($User in $AllMGUsers) {
    if ($User.UserPrincipalName) {
        $MgByUpn[$User.UserPrincipalName] = $User
    }

    if ($User.EmployeeId) {
        $MgByEmployeeId[$User.EmployeeId] = $User
    }

    if ($User.OnPremisesSecurityIdentifier) {
        $MgBySid[$User.OnPremisesSecurityIdentifier] = $User
    }

    if ($User.Mail) {
        $MgByMail[$User.Mail] = $User
    }
}


$tla = "SAH"

# Get unique company names
$companies = (get-clipboard)
#(get-mguser -all -Property companyname | select companyname -Unique).companyname
$errors = @()
$NewGroups = @()

# Create dynamic groups for each company
foreach ($tla in $companies) {
    if ($tla -and $tla -match '^[A-Z]{3}(\.[A-Z]{3})?$') {
        Write-host "Creating dynamic group for $tla"
        $params = @{
            # DSG stands for Dynamic Security Group in this case
            DisplayName                   = "[DSG] $tla Users"
            Description                   = "Dynamic security group for all users in the $tla company"
            GroupTypes                    = @('DynamicMembership')
            MailEnabled                   = $false
            MailNickname                  = "$tla.all.users"
            SecurityEnabled               = $true
            <# 
                Dynamic membership rule to include all users with the specified company name and exclude disabled accounts
                and accounts with display names starting with '[' to filter out shared mailboxes and other non users
            #>
            MembershipRule = $('(user.companyName -eq "{0}") -and (user.accountEnabled -eq true) -and (user.displayName -notStartsWith "[") -and (user.mail -ne null)' -f $tla)
            MembershipRuleProcessingState = 'On'
        }

        try {
            Write-LogMsg -Message "Creating dynamic group for $tla"
            $newGroups += (New-MgGroup @params)
        }
        catch {
            $errors += [pscustomobject]@{
                TLA = Write-LogMsg -Message "Failed creating group for $tla"
                Error = $_.Exception.Message
            }
        }
    }
}

$Group = New-MgGroup @params

"IDS - Kerry Osterhage" -match '^[A-Z]{3}(\.[A-Z]{3})?$'
