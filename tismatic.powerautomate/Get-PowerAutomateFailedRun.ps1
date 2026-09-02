function Get-PowerAutomateFailedRun {
    [CmdletBinding()]
    param (
        [string]$EnvironmentName,
        [string]$FlowName,
        [string]$TenantId,

        [Parameter(Mandatory)]
        [datetime]$StartTime,

        [Parameter(Mandatory)]
        [datetime]$EndTime,

        [ValidateSet('All', 'OwnedByMe', 'Personal', 'SharedWithMe')]
        [string]$SharingStatus = 'All'
    )

    $ApiVersion = '2016-11-01'
    $ApiRoot = 'https://api.flow.microsoft.com/providers/Microsoft.ProcessSimple'

    $Auth = Get-PowerAutomateAuth -TenantId $TenantId

    function Get-AllResults {
        param (
            [Parameter(Mandatory)]
            [string]$Uri
        )

        $Results = [System.Collections.Generic.List[object]]::new()

        do {
            $Params = @{
                Method      = 'Get'
                Uri         = $Uri
                Headers     = $Auth.Headers
                ErrorAction = 'Stop'
            }

            $Response = Invoke-RestMethod @Params

            foreach ($Item in $Response.value) {
                $Results.Add($Item)
            }

            if ($Response.'@odata.nextLink') {
                $Uri = $Response.'@odata.nextLink'
            }
            elseif ($Response.nextLink) {
                $Uri = $Response.nextLink
            }
            else {
                $Uri = $null
            }
        }
        while ($Uri)

        $Results
    }

    function Select-ConsoleItem {
        param (
            [Parameter(Mandatory)]
            [object[]]$Items,

            [Parameter(Mandatory)]
            [string]$Prompt,

            [Parameter(Mandatory)]
            [scriptblock]$DisplayName
        )

        for ($i = 0; $i -lt $Items.Count; $i++) {
            $Name = & $DisplayName $Items[$i]
            Write-Host "[$($i + 1)] $Name"
        }

        do {
            $Selection = Read-Host $Prompt
            $Number = 0
            $Valid = [int]::TryParse($Selection, [ref]$Number)

            if ($Valid) {
                $Index = $Number - 1
                $Valid = $Index -ge 0 -and $Index -lt $Items.Count
            }

            if (-not $Valid) {
                Write-Warning 'Invalid selection.'
            }
        }
        until ($Valid)

        $Items[$Index]
    }

    if (-not $EnvironmentName) {
        Write-Host 'Retrieving Power Automate environments...'

        $Uri = "$ApiRoot/environments?api-version=$ApiVersion"
        $Environments = @(Get-AllResults -Uri $Uri)

        if (-not $Environments.Count) {
            throw 'No Power Automate environments were found.'
        }

        if ($Environments.Count -eq 1) {
            $Environment = $Environments[0]
        }
        else {
            $Environment = Select-ConsoleItem -Items $Environments -Prompt 'Select an environment' -DisplayName {
                param($Item)
                "$($Item.properties.displayName) [$($Item.name)]"
            }
        }

        $EnvironmentName = $Environment.name
    }

    if (-not $FlowName) {
        Write-Host "Retrieving flows from $EnvironmentName..."

        $BaseUri = "$ApiRoot/environments/$EnvironmentName/flows?api-version=$ApiVersion"

        switch ($SharingStatus) {
            'OwnedByMe' {
                $Flows = @(Get-AllResults -Uri $BaseUri)
            }

            'Personal' {
                $Uri = $BaseUri + '&$filter=search(''personal'')'
                $Flows = @(Get-AllResults -Uri $Uri)
            }

            'SharedWithMe' {
                $Uri = $BaseUri + '&$filter=search(''team'')'
                $Flows = @(Get-AllResults -Uri $Uri)
            }

            'All' {
                $PersonalUri = $BaseUri + '&$filter=search(''personal'')'
                $SharedUri = $BaseUri + '&$filter=search(''team'')'

                $PersonalFlows = @(Get-AllResults -Uri $PersonalUri)
                $SharedFlows = @(Get-AllResults -Uri $SharedUri)

                $Flows = @($PersonalFlows + $SharedFlows | Sort-Object id -Unique)
            }
        }

        $Flows = @($Flows | Sort-Object { $_.properties.displayName })

        if (-not $Flows.Count) {
            throw "No flows were found in environment $EnvironmentName."
        }

        if ($Flows.Count -eq 1) {
            $Flow = $Flows[0]
        }
        else {
            $Flow = Select-ConsoleItem -Items $Flows -Prompt 'Select a flow' -DisplayName {
                param($Item)

                $UserType = if ($Item.properties.userType) {
                    " - $($Item.properties.userType)"
                }
                else {
                    ''
                }

                "$($Item.properties.displayName)$UserType [$($Item.name)]"
            }
        }

        $FlowName = $Flow.name
    }

    $StartTimeUtc = $StartTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $EndTimeUtc = $EndTime.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

    $Filter = "status eq 'Failed' and startTime ge $StartTimeUtc and startTime lt $EndTimeUtc"
    $EncodedFilter = [uri]::EscapeDataString($Filter)

    $Uri = '{0}/environments/{1}/flows/{2}/runs?api-version={3}&$filter={4}' -f $ApiRoot, $EnvironmentName, $FlowName, $ApiVersion, $EncodedFilter

    Write-Host "Retrieving failed runs from $StartTimeUtc through $EndTimeUtc..."

    $FailedRuns = @(Get-AllResults -Uri $Uri)

    foreach ($Run in $FailedRuns) {
        $Run | Add-Member -NotePropertyName EnvironmentName -NotePropertyValue $EnvironmentName -Force
        $Run | Add-Member -NotePropertyName FlowName -NotePropertyValue $FlowName -Force
        $Run | Add-Member -NotePropertyName TenantId -NotePropertyValue $Auth.TenantId -Force
    }

    Write-Host "Found $($FailedRuns.Count) failed runs."

    $FailedRuns
}