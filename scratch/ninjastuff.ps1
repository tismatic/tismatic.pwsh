$orgs = Get-NinjaOneOrganizations | Group-Object -Property id -AsHashTable
$devices = Get-NinjaOneDevice -deviceFilter "group 121" -detailed
#Get-NinjaOneDevice -deviceFilter "class eq WINDOWS_SERVER" -detailed
$customFields = Get-NinjaOneCustomFields -deviceFilter "group 121" | Group-Object -Property deviceId -AsHashTable

$devices | ForEach-Object {
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

$csv = import-csv  "C:\Users\npeltier\Downloads\ServerUpdates(2026.Sep.csv"
$csv | % {
    $device = (Find-NinjaOneDevice -searchQuery $_.AssetName -limit 1).devices
    Set-NinjaOneDeviceCustomField -deviceId $device -deviceCustomFields @{"eligibleForQuarterlyUpdates" = $true}
}


######################

$progressPreference = 'SilentlyContinue'
$orgs = Get-NinjaOneOrganizations | Group-Object -Property id -AsHashTable

$properties = @(
    'SystemName'
    'WindowsUpdateStatus'
    'AvailableUpdates'
    'AssignedTechnician'
    'OrgName'
)

function Get-WindowsServerUpdateStatus {
    $devices = Get-NinjaOneDevice -deviceFilter "group 123" -detailed
    $customFields = Get-NinjaOneCustomFields -deviceFilter "group 123" | Group-Object -Property deviceId -AsHashTable

    $devices | ForEach-Object {
        $count = $null

        if ($customFields[$_.id].fields.availableWindowsUpdates.text -match 'Available updates:\s*(\d+)') {
            $count = [int]$Matches[1]
        }

        [pscustomobject]@{
            SystemName          = $_.systemName
            WindowsUpdateStatus = $customFields[$_.id].fields.windowsupdatestatus
            AvailableUpdates    = $count
            AssignedTechnician  = $customFields[$_.id].fields.assignedTechnitian
            OrgName             = $orgs[$_.organizationId].name
        }
    }
}

$table = Get-WindowsServerUpdateStatus |
    Format-SpectreTable -Property $properties -Title "Windows Server Update Status" -Expand

Invoke-SpectreLive -Data $table -ScriptBlock {
    param(
        [Spectre.Console.LiveDisplayContext]$Context
    )

    while ($true) {
        $data = Get-WindowsServerUpdateStatus

        $table = $data |
            Sort-Object AvailableUpdates -Descending |
            Format-SpectreTable -Property $properties -Title "Windows Server Update Status - $(Get-Date -Format 'HH:mm:ss')" -Expand

        $Context.UpdateTarget($table)
        $Context.Refresh()

        Start-Sleep -Seconds 3
    }
}

########### Sync CSV to Ninja
$CSV = IMport-CSV "C:\Users\npeltier\Downloads\ServerUpdates(2026.Sep.csv"
$Devices = $CSV | % {
    $device = (Find-NInjaOneDevice -searchQuery $_.AssetName -limit 1).devices
    [PSCustomObject]@{
        id = $device.id
        AssetName = $_.AssetName
        POC = $_.POC
        Responsibility = $_.Responsibility
        TimeOfDay = $_.TimeOfDay
    }  
}
$Devices | % {
    Set-NinjaOneDeviceCustomFields -deviceId $_.id -deviceCustomFields @{
        "assignedTechnician" = $_.Responsibility
        "pointOfContact" = $_.POC
        "maintenanceWindow" = $_.TimeOfDay
        "eligibleForQuarterlyUpdates" = $true
    } -erroraction silentlycontinue
}
############

Get-NinjaOneAutomationScripts | ogv

Invoke-NinjaOneDeviceScript -deviceId 1266 -scriptId 405 -type SCRIPT -runAs SYSTEM -show