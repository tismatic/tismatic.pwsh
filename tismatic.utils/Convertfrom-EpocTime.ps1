<#
.SYNOPSIS
Converts Unix epoch time to local time.

.DESCRIPTION
Converts a Unix timestamp expressed in seconds or milliseconds into a
DateTime value in the computer's local time zone.

.EXAMPLE
ConvertFrom-EpochTime -EpochTime 1784311200

.EXAMPLE
1784311200000 | ConvertFrom-EpochTime -Milliseconds
#>
function ConvertFrom-EpochTime {
    [CmdletBinding()]
    [OutputType([datetime])]
    param (
        [Parameter(
            Mandatory,
            ValueFromPipeline,
            Position = 0
        )]
        [long]$EpochTime,

        [Parameter()]
        [switch]$Milliseconds
    )

    process {
        try {
            $DateTimeOffset = if ($Milliseconds) {
                [datetimeoffset]::FromUnixTimeMilliseconds($EpochTime)
            }
            else {
                [datetimeoffset]::FromUnixTimeSeconds($EpochTime)
            }

            $DateTimeOffset.LocalDateTime
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}