function Add-ProxyAddress {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$Identity,

        [Parameter(Mandatory)]
        [string]$ProxyAddress,

        [switch]$IsPrimary,

        [string]$Server,

        [pscredential]$Credential
    )

    begin {
        if (-not $Server) { $Server = (Get-ADDomain).DNSRoot }

        $commonParams = @{ Server = $Server }
        if ($Credential) { $commonParams.Credential = $Credential }
    }

    process {
        $adUser =
        if ($Identity -is [Microsoft.ActiveDirectory.Management.ADUser]) {
            if (-not $Identity.ProxyAddresses) {
                Get-ADUser -Identity $Identity.DistinguishedName -Properties ProxyAddresses @commonParams
            }
            else {
                $Identity
            }
        }
        else {
            Get-ADUser -Identity $Identity -Properties ProxyAddresses @commonParams
        }

        if (-not $adUser) {
            Write-Error "User '${Identity}' not found."
            return
        }

        $addr = $ProxyAddress.Trim()
        $smtpValue = "smtp:${addr}"

        # Add only if not already present (case-insensitive)
        $current = @($adUser.ProxyAddresses | ForEach-Object { $_.ToString() })
        $exists = $current | Where-Object { $_.Equals($smtpValue, [System.StringComparison]::OrdinalIgnoreCase) -or
            $_.Equals(("SMTP:${addr}"), [System.StringComparison]::OrdinalIgnoreCase) }

        if (-not $exists) {
            if ($PSCmdlet.ShouldProcess($adUser.SamAccountName, "Add proxy address ${smtpValue}")) {
                Set-ADUser -Identity $adUser -Add @{ ProxyAddresses = $smtpValue } @commonParams
            }
        }

        if ($IsPrimary) {
            Set-PrimarySMTPAddress -Identity $adUser -NewPrimarySMTPAddress $addr -Server $Server -Credential $Credential
        }
        else {
            $adUser  # return user object for pipeline chaining if desired
        }
    }
}