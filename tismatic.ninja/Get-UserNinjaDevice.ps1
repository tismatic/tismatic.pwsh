function Get-UserNinjaDevice {
    param(
        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias("OnPremisesSamAccountName")]
        $UserId
    )
    Connect-SahNinja
    $results = (Find-NinjaOneDevice -searchQuery $UserId).devices | where { $_.score -ge 95 -and $_.nodeClass -eq "WINDOWS_WORKSTATION" -and $_.matchAttr -eq "lastLoggedOnUser" }
    foreach ($result in $results) {
        $result | Add-member -MemberType NoteProperty -Name URL -Value ("https://app.ninjarmm.com/#/deviceDashboard/$($result.Id)/overview")
    }

    $results
}