# Connects to Graph and Exchange Online using the current user context. If the user is not already connected, it will prompt for authentication.
function Connect-365Admin {
    [CmdletBinding()]
    param()

    Write-Host 'Connecting to Graph and Exchange...'

    $mgContext = Get-MgContext -ErrorAction SilentlyContinue
    if (-not $mgContext) {
        Connect-MgGraph -NoWelcome
        $mgContext = Get-MgContext
    }

    $exoConnected = $false
    if (Get-Command Get-ConnectionInformation -ErrorAction SilentlyContinue) {
        $exoConnected = [bool](Get-ConnectionInformation -ErrorAction SilentlyContinue)
    }

    if (-not $exoConnected) {
        Import-Module ExchangeOnlineManagement -ErrorAction Stop
        $params = @{
            UserPrincipalName = $mgContext.Account
            ShowBanner        = $false
            DisableWAM        = $true
        }
        Connect-ExchangeOnline @params
    }
}