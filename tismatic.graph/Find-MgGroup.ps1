function Find-MgGroup {
    [CmdletBinding()]
    param(
        [Parameter(
            Mandatory,
            Position = 0,
            ValueFromRemainingArguments
        )]
        [string[]]$SearchString
    )
	$properties = 'Id,DisplayName,Description,GroupTypes,Mail,MailEnabled,MailNickname,SecurityEnabled,Visibility,ProxyAddresses,CreatedDateTime,RenewedDateTime,PreferredDataLocation,OnPremisesSyncEnabled,OnPremisesSamAccountName,OnPremisesSecurityIdentifier,OnPremisesDomainName,OnPremisesLastSyncDateTime,OnPremisesProvisioningErrors,ResourceBehaviorOptions,ResourceProvisioningOptions,MembershipRule,MembershipRuleProcessingState,AssignedLabels,SecurityIdentifier'
    $SearchText = ($SearchString -join ' ').Trim()

    $Search = '"displayName:{0}" OR "mailNickname:{0}" OR "mail:{0}"' -f $SearchText

    Write-Verbose "Graph search: $Search"

    $Group = Get-MgGroup -Search $Search -ConsistencyLevel eventual -CountVariable ResultCount -All -Property $properties

    if ($Group) {
        $Group
    }
    else {
        Write-Warning "No group found matching '$SearchText'."
    }
}