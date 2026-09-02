function Get-PowerAutomateAuth {
    [CmdletBinding()]
    param (
        [string]$TenantId
    )

    if (-not $TenantId) {
        $Context = Get-AzContext

        if (-not $Context) {
            throw 'No Az PowerShell context exists. Run Connect-AzAccount first.'
        }

        $TenantId = $Context.Tenant.Id
    }

    $TokenParams = @{
        ResourceUrl = 'https://service.flow.microsoft.com/'
        TenantId    = $TenantId
        ErrorAction = 'Stop'
    }

    $TokenResult = Get-AzAccessToken @TokenParams

    $AccessToken = [System.Net.NetworkCredential]::new('', $TokenResult.Token).Password

    [pscustomobject]@{
        Headers = @{
            Authorization = "Bearer $AccessToken"
            Accept        = 'application/json'
        }
        ExpiresOn = $TokenResult.ExpiresOn
        TenantId  = $TenantId
    }
}