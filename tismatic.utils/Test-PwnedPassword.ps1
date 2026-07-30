function Test-PwnedPassword {
    [CmdletBinding()]
    param (
        [Parameter(Valuefrompipeline)]
        [string]$Password
    )
    $StringBytes = [system.text.encoding]::utf8.GetBytes("$Password")
    $SHA1CryptoProvider = [System.Security.Cryptography.SHA1CryptoServiceProvider]::new()
    $SHA1ComputedHash = $SHA1CryptoProvider.ComputeHash($StringBytes)
    $SHA1HashHexString = [BitConverter]::ToString($SHA1ComputedHash) -replace "-"
    $HashFirst5Chars = $SHA1HashHexString.Substring(0, 5)
    $Response = Invoke-RestMethod -URI "https://api.pwnedpasswords.com/range/$HashFirst5Chars"
		
    $HashSuffix = $SHA1HashHexString.Substring(5, 35) + ":"
    $FoundHashMatch = $Response.Split() -match $HashSuffix
    if ($FoundHashMatch) {
        $Count = (($FoundHashMatch.split(':'))[1]).trim()
        Write-host ("This password has been seen {0} times before in data breaches!" -f $Count) -ForegroundColor Red
        return $true
    }
    else {
        Write-host "This password wasn't found in any of the Pwned Passwords loaded into Have I Been Pwned" -ForegroundColor Green
        return $false
    }
		
}