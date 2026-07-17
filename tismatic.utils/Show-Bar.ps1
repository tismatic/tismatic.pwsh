# Retrieves a progress bar for console output.
function Show-Bar {
    param(
        $transferred,
        $Total = 100,
        $Caption
    )
    $barmax = 40
    $percentComplete = [math]::Round(($transferred / $Total) * 100)
    $barLength = [math]::Round(($percentComplete / 100) * $barmax)

    $doneChar = '━'
    $remainingChar = '━'
    $e = [char]0x1b
    # ANSI Colors (foreground)
    $colorDone = "$e[1;34m"        # Green
    $colorRemaining = "$e[38;5;240m"  # Dark gray
    $reset = "$e[0m"

    $done = $colorDone + ($doneChar * $barLength)
    $remaining = $colorRemaining + ($remainingChar * ($barmax - $barLength))

    if ($Caption) {
        $bar = "$Caption`n$done$remaining$reset"
    }
    else {
        $bar = "$done$remaining$reset"
    }

    return $bar
}