function Set-PrimarySMTPAddress {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias('samaccountname', 'OnPremisesSamAccountName')]
        [object]$Identity,

        [Parameter(Mandatory)]
        [string]$NewPrimarySMTPAddress,

        [Parameter(Mandatory, ValueFromPipeline)]
        [Alias('OnPremisesDomainName')]
        [string]$Server,

        [pscredential]$Credential
    )

    begin {
        $commonParams = @{}
        if ($Server) { $commonParams.Server = $Server }
        if ($Credential) { $commonParams.Credential = $Credential }
    }

    process {
        # Normalize identity into an ADUser with ProxyAddresses loaded
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

        $newPrimary = $NewPrimarySMTPAddress.Trim()

        # Build a case-insensitive set to dedupe, preserving order as best we can
        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        $result = New-Object System.Collections.Generic.List[string]

        foreach ($p in ($adUser.ProxyAddresses | ForEach-Object { $_.ToString() })) {
            # demote any current primary SMTP
            $normalized = $p -creplace '^SMTP:', 'smtp:'

            if ($seen.Add($normalized)) {
                $null = $result.Add($normalized)
            }
        }

        # Remove any existing entries for the new address (smtp/SMTP) then add as primary
        $smtpValue = "smtp:${newPrimary}"
        $SMTPValue = "SMTP:${newPrimary}"

        for ($i = $result.Count - 1; $i -ge 0; $i--) {
            if ($result[$i].Equals($smtpValue, [System.StringComparison]::OrdinalIgnoreCase) -or
                $result[$i].Equals($SMTPValue, [System.StringComparison]::OrdinalIgnoreCase)) {
                $result.RemoveAt($i)
            }
        }

        # Insert primary SMTP at the front (common convention); you can append if you prefer
        $result.Insert(0, $SMTPValue)

        if ($PSCmdlet.ShouldProcess($adUser.SamAccountName, "Set primary SMTP to ${newPrimary}")) {
            Set-ADUser -Identity $adUser -Replace @{ ProxyAddresses = $result.ToArray() } @commonParams
        }

        [pscustomobject]@{
            SamAccountName        = $adUser.SamAccountName
            DistinguishedName     = $adUser.DistinguishedName
            NewPrimarySMTPAddress = $newPrimary
            ProxyAddresses        = $result
        }
    }
}