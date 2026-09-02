function Get-NewPassword {
    param (
        [switch]$AsPlainText
    )
    do {
        $pass = Read-Host -AsSecureString -Prompt "Enter Password" | Convertfrom-SecureString -AsPlainText
        $repeat = Read-Host -AsSecureString -Prompt "Repeat Password" | Convertfrom-SecureString -AsPlainText
        if (-not $pass.Equals($repeat)) {
            Write-Host "Passwords did not match. Please try again" -ForegroundColor DarkYellow
        }
    }
    while ((-not $pass.Equals($repeat)))

    if ($AsPlainText) {
        return $pass
    }
    else {
        return ($pass | ConvertTo-SecureString -AsPlainText -Force)
    }
}