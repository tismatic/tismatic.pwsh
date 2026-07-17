# Retrieves a passphrase using the EFF large wordlist and diceware method.
function New-DicePassphrase {
    param (
        [int]$WordCount = 3,
        [string]$Separator = "-",
        [switch]$AsSecureString
    )
    $WordListPath = "$($Env:LOCALAPPDATA)\eff_large_wordlist.txt"
    if (!(Test-Path $WordListPath)) {
        Invoke-RestMethod 'https://www.eff.org/files/2016/07/18/eff_large_wordlist.txt' -OutFile $WordListPath
    }
    $WordList = Get-Content $WordListPath -Raw
    $words = 1 .. $WordCount | ForEach-Object {
        $Dice = ( -join (1 .. 5 | ForEach-Object {
                    Get-SecureRandom -Maximum 6 -Minimum 1
                })).Tostring()
        $StringLower = (((($Wordlist -split "`n") | Where-Object {
                        $_ -match $Dice
                    }) -replace "\d").trim())
        $StringUpper = $StringLower.Substring(0, 1).ToUpper() + $StringLower.Substring(1)
        $StringUpper
    }
    $RandomWord = ($words | Get-SecureRandom)
    $ModWord = $RandomWord -replace "$", (Get-SecureRandom -Maximum 9 -Minimum 1)
    $Words = $words -replace $RandomWord, $ModWord

    if (!$AsSecureString) {
        return $words -join $Separator
    }
    else {
        return (($words -join $Separator) | ConvertTo-SecureString -AsPlainText -Force)
    }
}