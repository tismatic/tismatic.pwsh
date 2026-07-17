function Get-StringSimilarity {
    <#
    .SYNOPSIS
        Returns similarity percent (0-100) between two strings using Levenshtein distance.
    .PARAMETER A
        First string.
    .PARAMETER B
        Second string.
    .PARAMETER IgnoreCase
        Compare case-insensitively.
    .PARAMETER Trim
        Trim inputs before comparing.
    .EXAMPLE
        Get-StringSimilarity -A "kitten" -B "sitting"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()][string]$A,
        [Parameter(Mandatory)][AllowNull()][string]$B,
        [switch]$IgnoreCase,
        [switch]$Trim
    )

    if ($null -eq $A) { $A = "" }
    if ($null -eq $B) { $B = "" }

    if ($Trim) {
        $A = $A.Trim()
        $B = $B.Trim()
    }
    if ($IgnoreCase) {
        $A = $A.ToLowerInvariant()
        $B = $B.ToLowerInvariant()
    }

    # Fast paths
    if ($A -eq $B) { return 100.0 }
    if ($A.Length -eq 0 -and $B.Length -eq 0) { return 100.0 }
    if ($A.Length -eq 0 -or $B.Length -eq 0) { return 0.0 }

    $lenA = $A.Length
    $lenB = $B.Length

    # Use two rows to reduce memory
    $prev = New-Object int[] ($lenB + 1)
    $curr = New-Object int[] ($lenB + 1)

    for ($j = 0; $j -le $lenB; $j++) { $prev[$j] = $j }

    for ($i = 1; $i -le $lenA; $i++) {
        $curr[0] = $i
        $charA = $A[$i - 1]

        for ($j = 1; $j -le $lenB; $j++) {
            $cost = if ($charA -eq $B[$j - 1]) { 0 } else { 1 }

            $del = $prev[$j] + 1
            $ins = $curr[$j - 1] + 1
            $sub = $prev[$j - 1] + $cost

            $curr[$j] = [Math]::Min($del, [Math]::Min($ins, $sub))
        }

        # swap rows
        $tmp = $prev
        $prev = $curr
        $curr = $tmp
    }

    $distance = $prev[$lenB]
    $maxLen = [Math]::Max($lenA, $lenB)

    # Similarity as (1 - normalized distance)
    $similarity = (1.0 - ($distance / [double]$maxLen)) * 100.0
    return [Math]::Round($similarity, 2)
}