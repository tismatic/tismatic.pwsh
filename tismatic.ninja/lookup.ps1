function Lookup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [string[]]$Search
    )

    begin {
        $Orgs = Get-NinjaOneOrganization |
        Group-Object -Property Id -AsHashTable
    }

    process {
        foreach ($String in $Search) {
            $SearchResult = Find-NinjaOneDevice `
                -SearchQuery $String `
                -Limit 1

            $FoundDevice = @($SearchResult.Devices)[0]

            if (-not $FoundDevice) {
                Write-Warning "No device found matching '$String'."
                continue
            }

            $Device = Get-NinjaOneDevice -DeviceId $FoundDevice.Id
            $DeviceOwner = ((Find-MgDevice ($Device.SystemName -replace "\..*")).OwnerDisplayName)
            if (!$DeviceOwner) {
                $DeviceOWner = @(Find-Mguser ($Device.lastLoggedInUser -replace "^.*\\" -replace "^.*\.") | where {$_.Mail})[0].DisplayName
            }

            $Properties = [ordered]@{
                Hostname         = $Device.SystemName
                DnsDomain        = $Device.DnsName -replace "$([regex]::Escape($Device.SystemName)).?"
                DeviceOwner      = $DeviceOWner
                IpAddress        = @($Device.IpAddresses)[0]
                PublicIp         = @($Device.PublicIp)[0]
                LastContact      = ($Device.lastContact | ConvertFrom-EpochTime)
                MacAddress       = @($Device.MacAddresses)[0]
                OS               = $Device.OS.Name
                Manufacturer     = $Device.System.Manufacturer
                ChassisType      = $Device.SystemLabels.chassisType
                RAM              = [math]::Round($Device.Memory.Capacity / 1GB, 2)
                Description      = $null
                Status           = $null
                Env              = $null
                BusinessUnit     = $Orgs[$Device.OrganizationId].Name
                VMHost           = (Get-NinjaOneDeviceCustomFields -deviceId $FoundDevice.Id).hypervHost
                Volumes          = ($Device.Volumes | sort-Object -Property name | select @{n = "volumeCapacity"; e = { "$($_.name)=$([math]::Round($_.capacity / 1GB, 2)) GB" } }).volumecapacity -join " - "
            }

            [pscustomobject]$Properties
        }
    }
}


