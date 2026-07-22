function Find-MgUser {
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
        $Properties = 'Id,AccountEnabled,AgeGroup,OfficeLocation,AssignedLicenses,AssignedPlans,City,CompanyName,ConsentProvidedForMinor,Country,CreationType,Department,DisplayName,GivenName,OnPremisesImmutableId,JobTitle,LegalAgeGroupClassification,Mail,MailNickName,MobilePhone,OnPremisesSecurityIdentifier,OtherMails,PasswordPolicies,PasswordProfile,PostalCode,PreferredLanguage,ProvisionedPlans,OnPremisesProvisioningErrors,ProxyAddresses,RefreshTokensValidFromDateTime,ShowInAddressList,State,StreetAddress,Surname,BusinessPhones,UsageLocation,UserPrincipalName,ExternalUserState,ExternalUserStateChangeDateTime,UserType,OnPremisesLastSyncDateTime,ImAddresses,SecurityIdentifier,OnPremisesUserPrincipalName,ServiceProvisioningErrors,IsResourceAccount,OnPremisesExtensionAttributes,DeletedDateTime,OnPremisesSyncEnabled,EmployeeType,EmployeeHireDate,CreatedDateTime,EmployeeOrgData,preferredDataLocation,Identities,onPremisesSamAccountName,EmployeeId,EmployeeLeaveDateTime,AuthorizationInfo,FaxNumber,OnPremisesDistinguishedName,OnPremisesDomainName,IsLicenseReconciliationNeeded,signInSessionsValidFromDateTime,registeredDevices'
    }

    process {
        $SearchText = ($SearchString -join ' ').Trim()

        $Search = '"displayName:{0}" OR "userPrincipalName:{0}" OR "mail:{0}"' -f $SearchText

        Write-Verbose "Graph search: $Search"

        $User = Get-MgUser -Search $Search -ConsistencyLevel eventual -CountVariable ResultCount -All -Property $Properties

        if ($User) {
            $User
        }
        else {
            Write-Warning "No user found matching '$SearchText'."
        }
    }
    
}