function New-PsCredential {
    param (
        [Parameter(Mandatory = $true)]
        [string]$UserName,
        [Parameter(Mandatory = $true)]
        [SecureString]$Password
    )

    return [PSCredential]::new($UserName, $Password)
}