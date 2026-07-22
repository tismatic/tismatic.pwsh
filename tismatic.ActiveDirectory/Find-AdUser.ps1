function Find-ADuser {
    param(
        [Parameter(
            Mandatory,
            Position = 0,
            ValueFromRemainingArguments
        )]
        [string[]]$SearchString
    )
    $trusts = @((get-addomain).dnsroot) + @((Get-ADTrust -filter *).name)
    $Jobs = $trusts | Foreach-Object {
        Start-Threadjob -ScriptBlock {
            param(
                $SearchString,
                $Server
            )
            $PRogressPreference = 'SilentlyContinue'
            $Pattern = "*$($SearchString -join '*')*"
            $Filter = "DisplayName -like '$Pattern' -or UserPrincipalName -like '$SearchString*' -or SamAccountName -like '$SearchString*'"
            Get-ADUser -Filter $Filter -Server $Server -ErrorAction SilentlyContinue
    
        } -ArgumentList $SearchString, $_
    }
    $Results = $jobs | receive-job -Wait -AutoRemoveJob

    $Results
}