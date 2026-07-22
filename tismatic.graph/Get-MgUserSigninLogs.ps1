function Get-MgUserSigninLogs {
    <#
    .SYNOPSIS
        Retrieves Microsoft Entra sign-in logs for one or more users.

    .DESCRIPTION
        Calls the Microsoft Graph beta auditLogs/signIns endpoint directly
        through Invoke-MgGraphRequest.

        UserId may be either:
          - A user principal name
          - An Entra user object ID

        Use either:
          -StartDate and -EndDate
        or:
          -Last '24 hours'

        A date-only EndDate is treated as the entire specified day.

    .EXAMPLE
        Get-MgUserSigninLogs `
            -UserId 'tismatic@contoso.com' `
            -Last '24 hours'

    .EXAMPLE
        Get-MgUserSigninLogs `
            -UserId 'tismatic@contoso.com' `
            -Last '7 days' `
            -SignInType NonInteractive

    .EXAMPLE
        Get-MgUserSigninLogs `
            -UserId 'tismatic@contoso.com' `
            -StartDate '2026-07-01' `
            -EndDate '2026-07-01'

    .EXAMPLE
        'user1@contoso.com', 'user2@contoso.com' |
            Get-MgUserSigninLogs -Last '1 month'
    #>

    [CmdletBinding(DefaultParameterSetName = 'Last')]
    param (
        [Parameter(
            Mandatory,
            Position = 0,
            ValueFromPipeline,
            ValueFromPipelineByPropertyName
        )]
        [Alias('Id', 'UPN', 'UserPrincipalName')]
        [ValidateNotNullOrEmpty()]
        [string[]]$UserId,

        [Parameter(
            Mandatory,
            ParameterSetName = 'Range'
        )]
        [Alias('Start')]
        [datetimeoffset]$StartDate,

        [Parameter(
            Mandatory,
            ParameterSetName = 'Range'
        )]
        [Alias('End')]
        [datetimeoffset]$EndDate,

        [Parameter(
            Mandatory,
            ParameterSetName = 'Last'
        )]
        [Alias('Since')]
        [ValidateNotNullOrEmpty()]
        [string]$Last,

        [ValidateSet(
            'All',
            'Interactive',
            'NonInteractive'
        )]
        [string]$SignInType = 'All',

        [ValidateRange(1, 1000)]
        [int]$PageSize = 1000
    )

    begin {
        if (-not (Get-Command Invoke-MgGraphRequest -ErrorAction Ignore)) {
            throw @'
Invoke-MgGraphRequest was not found. Install or import the
Microsoft.Graph.Authentication module first.
'@
        }

        if ($PSCmdlet.ParameterSetName -eq 'Last') {
            $RangeEnd = [datetimeoffset]::Now

            $Pattern = @'
^(?<Value>\d+(?:\.\d+)?)\s*(?<Unit>m(?:in(?:ute)?s?)?|h(?:r|our)?s?|d(?:ay)?s?|w(?:eek)?s?|mo(?:nth)?s?)$
'@.Trim()

            if ($Last.Trim() -notmatch $Pattern) {
                throw @"
Invalid value for -Last: '$Last'

Examples:
  -Last '30 minutes'
  -Last '24 hours'
  -Last '7 days'
  -Last '2 weeks'
  -Last '1 month'

Abbreviations such as 30min, 24h, 7d, 2w, and 1mo are also supported.
"@
            }

            $Quantity = [double]::Parse(
                $Matches['Value'],
                [cultureinfo]::InvariantCulture
            )

            if ($Quantity -le 0) {
                throw '-Last must specify a value greater than zero.'
            }

            $Unit = $Matches['Unit'].ToLowerInvariant()

            $RangeStart = switch -Regex ($Unit) {
                '^m(?!o)' {
                    $RangeEnd.AddMinutes(-$Quantity)
                    break
                }

                '^h' {
                    $RangeEnd.AddHours(-$Quantity)
                    break
                }

                '^d' {
                    $RangeEnd.AddDays(-$Quantity)
                    break
                }

                '^w' {
                    $RangeEnd.AddDays( - ($Quantity * 7))
                    break
                }

                '^mo' {
                    if ([math]::Truncate($Quantity) -ne $Quantity) {
                        throw 'Months must be specified as a whole number.'
                    }

                    $RangeEnd.AddMonths( - [int]$Quantity)
                    break
                }
            }
        }
        else {
            $RangeStart = $StartDate
            $RangeEnd = $EndDate

            # Treat a date-only EndDate as the entire calendar day.
            if ($RangeEnd.TimeOfDay -eq [timespan]::Zero) {
                $RangeEnd = $RangeEnd.AddDays(1).AddMilliseconds(-1)
            }
        }

        if ($RangeStart -gt $RangeEnd) {
            throw 'StartDate must be earlier than EndDate.'
        }

        $StartDateText = $RangeStart.UtcDateTime.ToString(
            "yyyy-MM-dd'T'HH:mm:ss.fff'Z'",
            [cultureinfo]::InvariantCulture
        )

        $EndDateText = $RangeEnd.UtcDateTime.ToString(
            "yyyy-MM-dd'T'HH:mm:ss.fff'Z'",
            [cultureinfo]::InvariantCulture
        )

        $EventTypeFilter = switch ($SignInType) {
            'Interactive' {
                "signInEventTypes/any(t:t eq 'interactiveUser')"
            }

            'NonInteractive' {
                "signInEventTypes/any(t:t eq 'nonInteractiveUser')"
            }

            'All' {
                "signInEventTypes/any(" +
                "t:t eq 'interactiveUser' or " +
                "t eq 'nonInteractiveUser')"
            }
        }
    }

    process {
        foreach ($CurrentUserId in $UserId) {
            $CurrentUserId = $CurrentUserId.Trim()

            if (-not $CurrentUserId) {
                continue
            }

            $EscapedUserId = $CurrentUserId.Replace("'", "''")
            $ParsedGuid = [guid]::Empty

            $UserFilter = if (
                [guid]::TryParse(
                    $CurrentUserId,
                    [ref]$ParsedGuid
                )
            ) {
                "userId eq '$ParsedGuid'"
            }
            else {
                $NormalizedUPN = $EscapedUserId.ToLowerInvariant()
                "userPrincipalName eq '$NormalizedUPN'"
            }

            $Filter = @(
                $UserFilter
                @"
(createdDateTime ge $StartDateText and createdDateTime le $EndDateText)
"@.Trim()
                $EventTypeFilter
            ) -join ' and '

            $EncodedFilter = [uri]::EscapeDataString($Filter)

            $Uri = @"
https://graph.microsoft.com/beta/auditLogs/signIns?`$filter=$EncodedFilter&`$top=$PageSize
"@.Trim()

            do {
                Write-Verbose "Requesting sign-ins for '$CurrentUserId'"

                try {
                    $Response = Invoke-MgGraphRequest `
                        -Method GET `
                        -Uri $Uri `
                        -ErrorAction Stop
                }
                catch {
                    $PSCmdlet.WriteError($_)
                    break
                }

                if ($Response -is [System.Collections.IDictionary]) {
                    $SignIns = $Response['value']
                    $Uri = $Response['@odata.nextLink']
                }
                else {
                    $SignIns = $Response.value
                    $Uri = $Response.'@odata.nextLink'
                }

                foreach ($SignIn in @($SignIns)) {
                    if ($null -eq $SignIn) {
                        continue
                    }

                    $OutputObject = [pscustomobject]$SignIn
                    $OutputObject.PSObject.TypeNames.Insert(
                        0,
                        'Microsoft.Graph.SignInLog'
                    )

                    $OutputObject
                }
            }
            while ($Uri)
        }
    }
}

<#
# Useful formatted view
Get-MgUserSigninLogs `
    -UserId 'npeltier@apcisg.com' `
    -Last '24 hours' |
    Select-Object `
        createdDateTime,
        userPrincipalName,
        signInEventTypes,
        appDisplayName,
        resourceDisplayName,
        ipAddress,
        clientAppUsed,
        isInteractive,
        conditionalAccessStatus,
        @{
            Name       = 'Result'
            Expression = {
                if ($_.status.errorCode -eq 0) {
                    'Success'
                }
                else {
                    'Failure'
                }
            }
        },
        @{
            Name       = 'ErrorCode'
            Expression = { $_.status.errorCode }
        },
        @{
            Name       = 'FailureReason'
            Expression = { $_.status.failureReason }
        }
#>