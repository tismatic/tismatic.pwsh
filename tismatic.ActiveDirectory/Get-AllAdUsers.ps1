function Get-AllAdusers {
    $trusts = @((get-addomain).dnsroot) + @((Get-ADTrust -filter *).name)
    $Jobs = $trusts | Foreach-Object {
        Start-Threadjob -ScriptBlock {
            param(
                $Server
            )
            $PRogressPreference = 'SilentlyContinue'
            Get-ADUser -Filter {Enabled -eq $true} -server $Server | Where-Object { $_.adminCount -ne 1 }
    
        } -ArgumentList $_
    }
    $Jobs | receive-job -Wait -AutoRemoveJob
}