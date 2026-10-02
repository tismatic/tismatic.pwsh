Import-Module Pode
Import-Module .\tismatic.pwsh.psm1
function Get-NinjaAuthCode {
    param(
        $ClientID,
        $ClientSecret
    )
    $URI = 'https://app.ninjarmm.com/ws/oauth/token'

    $Headers = @{
        'Content-Type' = 'application/x-www-form-urlencoded'
    }
        
    $Body = "grant_type=client_credentials&client_id=$($ClientID)&client_secret=$($ClientSecret)&scope=monitoring"
    
    $Response = Invoke-RestMethod -Uri $URI -Method Post -Headers $Headers -Body $Body
    
    $AccessToken = $Response.'access_token'
    
    $PostAuthHeaders = @{
        Accept        = "application/json"
        Authorization = "Bearer $AccessToken"
    }

    return $PostAuthHeaders
}
function refreshauth {
    return (Get-NinjaAuthCode -ClientID 't2z60ko0dEZXrzv45IfbhdkOUts' -ClientSecret '5cQKjbWl8CIzlkRFAb8ucOTXnLOkY2fn-s7LenCsWA0ECD6446kf0A')
}
function New-HTMLTable {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [PSObject[]]$Content
    )

    begin {
        $output = @()
        $output += '<table class="table">'
        $output += "<thead><tr>"

        # Extracting property names for table headers
        $propertyNames = $Content[0].PSObject.Properties | Select-Object -ExpandProperty Name
        foreach ($propertyName in $propertyNames) {
            $output += "<th>$propertyName</th>"
        }

        $output += "</tr></thead>"
        $output += "<tbody>"
    }

    process {
        foreach ($item in $Content) {
            $output += "<tr>"
            foreach ($propertyName in $propertyNames) {
                $value = $item.$propertyName
                $output += "<td>$value</td>"
            }
            $output += "</tr>"
        }
    }

    end {
        $output += "</tbody>"
        $output += "</table>"

        # Outputting the HTML
        $output -join "`n"
    }
}
Start-PodeServer {
    New-PodeLoggingMethod -Terminal | Enable-PodeErrorLogging
    Add-PodeEndpoint -Address * -Port 7001 -Protocol Http

    Set-PodeViewEngine -Type Pode

    Add-PodeRoute -Method Get -Path '/roomalert' -ScriptBlock {
    
        $Data = Get-RoomAlertTemps -IPAddress $($Webevent.Query.ip)

        Write-PodeJsonResponse $Data
    }
    Add-PodeRoute -Method Get -Path '/ad/users' -ScriptBlock {
        function Get-AllDomainTrustNames {
            return ( -split (Get-addomain).dnsroot + (get-adtrust -Filter *).name)
        }
        $user = Get-AllDomainTrustNames | % { Get-ADuser -filter "SamAccountName -eq '$($Webevent.Query.username)'" -Server $_ | select Name, UserprincipalName, Enabled, Samaccountname }

        Write-PodeJsonResponse $user -Depth 10
    }
    Add-PodeRoute -Method Get -Path '/ad/users/locked' -ScriptBlock {
        function Get-AllDomainTrustNames {
            return ( -split (Get-addomain).dnsroot + (get-adtrust -Filter *).name)
        }
        $user = Get-AllDomainTrustNames | % { Search-ADAccount -LockedOut -Server $_ | select Name, UserprincipalName, Enabled, Samaccountname }

        Write-PodeJsonResponse $user -Depth 10
    }
    Add-PodeRoute -Method Get -Path '/ninja/serverstatus' -Scriptblock {
        $auth = refreshauth
        $all = (Invoke-RestMethod -uri "https://app.ninjarmm.com/v2/devices?df=class=WINDOWS_SERVER" -Headers $Auth) 
        $Offline = $all | where { $_.offline -and !$_.maintenance }
        $Online = $all | where { !$_.maintenance -and !$_.offline }
        $Maintenance = $all | where { $_.maintenance }
        $data = @{
            Online          = $Online.count
            Offline         = $Offline.count
            Maintenance     = $Maintenance.count
            OfflineList     = $Offline.systemName
            MaintenanceList = $Maintenance.SystemName
            OnlineList      = $Online.SystemName
        }

        Write-PodeJsonResponse -Value $data
    }
    Add-PodeRoute -Method Get -Path '/ninja/alerts' -Scriptblock {
        $auth = refreshauth
        
        $Request = Invoke-RestMethod -uri "https://app.ninjarmm.com/v2/alerts?expand=device" -Headers $Auth

        $data = foreach ($result in $Request) {
            @{
                SystemName   = $result.device.systemname
                AlertMessage = $result.message
                AlertSource  = $result.sourceType
            }
        }

        Write-PodeJsonResponse -Value $data
    }
    Add-PodeRoute -Method Get -Path 'ninja/diskreport' -ScriptBlock {
        $auth = refreshauth
        $AllServers = Invoke-RestMethod -uri "https://app.ninjarmm.com/v2/devices?df=class=WINDOWS_SERVER&pageSize=999" -Headers $auth
        $result = (Invoke-RestMethod -Method Get -Uri 'https://app.ninjarmm.com/v2/queries/volumes?include=device&pageSize=9999' -Headers $auth).results

        $report = foreach ($volume in $result) {
            if ($allservers | where { $volume.deviceId -eq $_.Id }) {
                [pscustomobject]@{
                    SystemName         = ($allservers | where { $volume.deviceId -eq $_.Id }).SystemName
                    SystemDeviceID     = $volume.deviceId
                    Name               = $volume.name
                    Label              = $volume.label
                    UtilizationPercent = [int]$(Get-DiskUtilization -capacity $Volume.capacity -freeSpace $Volume.freeSpace)
                }
            }
        }
        if ($Webevent.Query.threshold) {
            $threshold = [int]($Webevent.Query.threshold)
        }
        else {
            $threshold = 0
        }
        
        Write-PodeJsonResponse ($report | where { $_.UtilizationPercent -gt $threshold })
    }
}

$Results = Invoke-SpectreCommandWithStatus -Title "Resolving Entra device owners" -ScriptBlock {

    Write-SpectreHost "Collecting Sales, NVPS, and Customer Service users..."

    $salesOU = "OU=SalesUsers,OU=Sales,OU=APCHQ,DC=apc,DC=local"
    $nvpsOU = "OU=NVPSUsers,OU=NVPS,OU=APCHQ,DC=apc,DC=local"
    $customerserviceusersOU = "OU=CustomerServiceUsers,OU=CustomerService,OU=APCHQ,DC=apc,DC=local"

    $sales = Get-MgUser -Filter "endswith(onPremisesDistinguishedName,'$salesOU') and accountEnabled eq true" -ConsistencyLevel eventual -All
    $nvps = Get-MgUser -Filter "endswith(onPremisesDistinguishedName,'$nvpsOU') and accountEnabled eq true" -ConsistencyLevel eventual -All
    $customerserviceusers = Get-MgUser -Filter "endswith(onPremisesDistinguishedName,'$customerserviceusersOU') and accountEnabled eq true" -ConsistencyLevel eventual -All

    $Users = @($sales) + @($nvps) + @($customerserviceusers)

    Write-SpectreHost "Found $($Users.Count) users."
    Write-SpectreHost "Building user lookup table..."

    $UserIds = [System.Collections.Generic.HashSet[string]]::new([string[]]$Users.Id)

    $UsersById = @{}

    foreach ($User in $Users) {
        $UsersById[$User.Id] = $User
    }

    Write-SpectreHost "Collecting Entra devices..."

    $Uri = 'https://graph.microsoft.com/v1.0/devices?$select=id,deviceId,displayName,operatingSystem,trustType&$expand=registeredOwners($select=id)&$top=999'

    $Devices = do {
        $Response = Invoke-MgGraphRequest -Method GET -Uri $Uri

        $Response.value

        $Uri = $Response.'@odata.nextLink'
    } while ($Uri)

    Write-SpectreHost "Found $($Devices.Count) Entra devices."
    Write-SpectreHost "Resolving device owners..."

    foreach ($Device in $Devices) {

        foreach ($Owner in @($Device.registeredOwners)) {

            $OwnerId = [string]$Owner.id

            if (-not $UserIds.Contains($OwnerId)) {
                continue
            }

            $User = $UsersById[$OwnerId]

            [pscustomobject]@{
                UserDisplayName   = $User.DisplayName
                UserPrincipalName = $User.UserPrincipalName
                DeviceDisplayName = $Device.displayName
                DeviceId          = $Device.deviceId
                OperatingSystem   = $Device.operatingSystem
                TrustType         = $Device.trustType
                Relationship      = 'Owner'
            }
        }
    }
}

Connect-NInjaOne -ClientId $env:NINJA_API_CLIENTID -ClientSecret $env:NINJA_API_CLIENTSECRET -instance us -useClientAuth -writeToSecretVault
$allninjadevices = Get-NinjaOneDevice
$ninjadevicetable = $allninjadevices | Group-Object -Property systemName -AsHashTable
$FinalResult = $results | % { $ninjadevicetable.$($_.DeviceDisplayName) }


function Resolve-NinjaDeviceFromUser {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, ValueFromPipeline)]
        [string]$UserPrincipalName
    )

    process {
        (Get-MgUserOwnedDeviceAsDevice -UserId $UserPrincipalName -Property DisplayName).DisplayName | ForEach-Object {
            $DeviceName = $_
            $NinjaDevice = (Find-NinjaOneDevice -Limit 1 -SearchQuery $DeviceName).devices

            if ($NinjaDevice.systemName -eq $DeviceName) {
                $NinjaDevice
            }
        }
    }
}


$Tags = Get-NinjaOneTags
$Tag = $Tags.tags | Where-Object Name -eq 'Amazon Connect Client'

$TagUpdate = @{
    assetIds       = @($FinalResult.id)
    tagIdsToAdd    = @($Tag.Id)
    tagIdsToRemove = @()
}

Set-NinjaOneTagBatch -AssetType  -TagUpdate $TagUpdate



function Export-EntraNinjaDeviceMap {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$Path
    )

    $UserProperties = @(
        'Id'
        'DisplayName'
        'UserPrincipalName'
        'OnPremisesDistinguishedName'
        'OnPremisesDomainName'
    )

    $DeviceProperties = @(
        'Id'
        'DeviceId'
        'DisplayName'
        'OperatingSystem'
        'TrustType'
    )

    Write-Host "Collecting Entra users..."
    $EntraUsers = Get-MgUser -All -Property $UserProperties

    Write-Host "Collecting Entra devices and registered owners..."
    $EntraDevices = Get-MgDevice -All -Property $DeviceProperties -ExpandProperty RegisteredOwners

    Write-Host "Collecting Ninja devices..."
    $NinjaDevices = Get-NinjaOneDevice -detailed

    Write-Host "Building lookup tables..."

    $UsersById = @{}

    foreach ($User in $EntraUsers) {
        $UsersById[$User.Id] = $User
    }

    $NinjaDevicesByName = @{}

    foreach ($NinjaDevice in $NinjaDevices) {
        if ($NinjaDevice.systemName) {
            $NinjaDevicesByName[$NinjaDevice.systemName] = $NinjaDevice
        }
    }

    Write-Host "Resolving device ownership and Ninja mappings..."

    $Results = foreach ($Device in $EntraDevices) {

        $OwnerId = @($Device.RegisteredOwners).Id | Select-Object -First 1

        $Owner = if ($OwnerId) {
            $UsersById[[string]$OwnerId]
        }
        else {
            $null
        }

        $NinjaDevice = $NinjaDevicesByName[$Device.DisplayName]

        $OnPremisesOU = if ($Owner.OnPremisesDistinguishedName) {
            (($Owner.OnPremisesDistinguishedName -split ',') | Where-Object { $_ -like 'OU=*' }) -join ','
        }
        else {
            $null
        }

        [pscustomobject]@{
            DeviceDisplayName = $Device.DisplayName
            EntraObjectId     = $Device.Id
            EntraDeviceId     = $Device.DeviceId
            OperatingSystem   = $Device.OperatingSystem
            TrustType         = $Device.TrustType

            NinjaId           = if ($NinjaDevice) { $NinjaDevice.ID } else { $null }
            NinjaSystemName   = if ($NinjaDevice) { $NinjaDevice.systemName } else { $null }
            LastLoggedInUser  = if ($NinjaDevice) { $NinjaDevice.lastLoggedInUser } else { $null }
            NinjaMatched      = [bool]$NinjaDevice

            OwnerDisplayName  = if ($Owner) { $Owner.DisplayName } else { $null }
            OwnerUPN          = if ($Owner) { $Owner.UserPrincipalName } else { $null }

            OnPremisesOU      = $OnPremisesOU
            OnPremisesDomain  = if ($Owner) { $Owner.OnPremisesDomainName } else { $null }
        }
    }

    $Results = $Results | Sort-Object DeviceDisplayName

    $Results | Export-Csv -Path $Path -NoTypeInformation -Encoding utf8

    $Results
}

$Path = '.\Mailboxes.xlsx'

$Mailboxes = Get-EXOMailbox -ResultSize Unlimited -PropertySets Minimum, Archive |
Select-Object DisplayName, PrimarySmtpAddress, ArchiveStatus, ArchiveName, AutoExpandingArchiveEnabled

$ArchivedMailboxes = @($Mailboxes | Where-Object ArchiveStatus -eq 'Active')

$TotalMailboxCount = $Mailboxes.Count
$ArchiveCount = $ArchivedMailboxes.Count
$NoArchiveCount = $TotalMailboxCount - $ArchiveCount
$AutoExpandingEnabledCount = @($ArchivedMailboxes | Where-Object AutoExpandingArchiveEnabled -eq $true).Count
$AutoExpandingDisabledCount = $ArchiveCount - $AutoExpandingEnabledCount

$Summary = @(
    [pscustomobject]@{
        Metric = 'Total Mailboxes'
        Count  = $TotalMailboxCount
    }
    [pscustomobject]@{
        Metric = 'Archive Enabled'
        Count  = $ArchiveCount
    }
    [pscustomobject]@{
        Metric = 'No Archive'
        Count  = $NoArchiveCount
    }
    [pscustomobject]@{
        Metric = 'Auto-Expanding Archive Enabled'
        Count  = $AutoExpandingEnabledCount
    }
    [pscustomobject]@{
        Metric = 'Archive Enabled, Auto-Expanding Disabled'
        Count  = $AutoExpandingDisabledCount
    }
)

$ArchiveChart = New-ExcelChartDefinition -ChartType Pie -Title 'Mailbox Archive Status' -XRange 'A2:A3' -YRange 'B2:B3' -ShowCategory -ShowPercent -Row 5 -Column 1 -Width 600 -Height 350

$AutoExpandingChart = New-ExcelChartDefinition -ChartType Pie -Title 'Auto-Expanding Archive Status' -XRange 'C2:C3' -YRange 'D2:D3' -ShowCategory -ShowPercent -Row 5 -Column 9 -Width 600 -Height 350

Remove-Item $Path -ErrorAction Ignore

$Mailboxes | Export-Excel -Path $Path -WorksheetName 'Mailboxes' -TableName 'Mailboxes' -TableStyle Medium2 -AutoSize -FreezeTopRow -AutoFilter -BoldTopRow

$ExportParams = @{
    Path                 = $Path
    WorksheetName        = 'Summary'
    TableName            = 'ArchiveSummary'
    TableStyle           = 'Medium2'
    AutoSize             = $true
    BoldTopRow           = $true
    MoveToStart          = $true
    ExcelChartDefinition = @($ArchiveChart, $AutoExpandingChart)
}

$Summary | Export-Excel @ExportParams


$orgs = Get-NinjaOneOrganizations | Group-Object -Property id -AsHashTable
$devices = Get-NinjaOneDevice -deviceFilter "class eq WINDOWS_SERVER" -detailed
$customFields = Get-NinjaOneCustomFields -deviceFilter "group 121" | Group-Object -Property deviceId -AsHashTable

$Servers = $devices | ForEach-Object {
    if ($customFields[$_.id].fields.availableWindowsUpdates.text -match 'Available updates:\s*(\d+)') {
        $count = [int]$Matches[1]
    }
    
    [pscustomobject]@{
        SystemName          = $_.systemName
        WindowsUpdateStatus = $customFields[$_.id].fields.windowsupdatestatus
        AvailableUpdates    = $count
        AssignedTechnician   = $customFields[$_.id].fields.assignedTechnitian
        OrgName             = $orgs[$_.organizationId].name
    }
}

$Servers | ft


$s = get-clipboard