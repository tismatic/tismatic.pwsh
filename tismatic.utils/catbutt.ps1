function Show-MessageBox {
    param (
        [string]$Message,
        [string]$Title = 'Message',
        [System.Windows.Forms.MessageBoxButtons]$Buttons = [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information,
        [Scriptblock]$Scriptblock
    )
    [void][System.Windows.Forms.Application]::EnableVisualStyles()
    $Result = [System.Windows.Forms.MessageBox]::Show($Message, $Title, $Buttons, $Icon)
    if ($Result -eq 'OK' -and $Scriptblock) {
        $Scriptblock.Invoke()
    }
}
Add-Type -AssemblyName System.Windows.Forms
$message = @"
⠀⢀⣤⠶⠒⠲⢦⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⢰⡏⣡⠞⠛⠳⣦⠙⣇⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
⢸⣀⡏⠀⠀⠀⠸⡇⢷⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀  ⢀⣠⡄⠀⠀⠀⠀⠀
⠈⠉⠁⠀⠀⠀⠀⢷⡘⢷⣄⣤⣤⠤⢤⣤⣄⡀⠀⠀⢀⡶⠛⠹⡇⣀⣤⣤⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⣻⢶⣶⣶⡶⠀⠀⠀⠈⠙⠳⣴⣟⠁⠀⠀⢿⣿⣤⡏⠀⠀
⠀⠀⠀⠀⠀⠀⢠⡾⠃⠀⣤⣤⣄⠀⠀⠀⠀⠀⠀⠈⢻⣧⣀⣀⠀⠈⢻⣅⠀⠀
⠀⠀⠀⠀⠀⢠⡟⠀⠀⠀⢿💥⣿⠀⠀⠀⠀⠀⠀⠀⠀⢻⣿⠟⣀⣀⣤⣿⡆⠀
⠀⠀⠀⠀⠀⣼⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠉⢀⠛⠿⠋⢹⡇⠀
⠀⠀⠀⠀⠀⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣤⡄⠀⠀⣿⡆⣀⣤⣿⣷⠆
⠀⠀⠀⠀⠀⣿⠀⠀⠀⠀⠀⠀⠀⠀⠀⡀⠀⠀⠀⣿⡇⢀⣤⡟⠋⠉⠀⠀⠉⠀
⠀⠀⠀⠀⠀⢹⡀⠰⣶⣤⣀⣀⣀⣀⣸⣿⠀⠀⢠⣿⣡⣾⣿⠃⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠘⣧⠀⠈⣧⠀⠉⠉⠉⢹⡇⠀⢠⡿⠛⣟⢡⡏⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠘⢷⡀⢹⡄⠀⠀⢀⡿⠀⢠⡟⠁⠀⢻⣌⣿⠀⠀⠀⠀⠀⠀⠀
⠀⠀⠀⠀⠀⠀⠀⠀⠙⠛⠁⠀⠀⠈⠓⠚⠋⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀
"@
#Show-MessageBox -Icon None -Message $Message -Buttons ok -Title 'CattButt.exe'