<#
.SYNOPSIS
Converts a date and time to Unix epoch time.

.DESCRIPTION
Converts a DateTimeOffset-compatible value to the number of seconds or
milliseconds elapsed since 1970-01-01T00:00:00Z.

.EXAMPLE
ConvertTo-EpochTime -DateTime '2026-07-17T14:00:00-04:00'

.EXAMPLE
Get-Date | ConvertTo-EpochTime -Milliseconds
#>
function ConvertTo-EpochTime {
    [CmdletBinding()]
    [OutputType([long])]
    param(
        [Parameter(
            Mandatory,
            Position = 0,
            ValueFromPipeline
        )]
        [datetimeoffset]$DateTime,

        [Parameter()]
        [switch]$Milliseconds
    )

    process {
        if ($Milliseconds) {
            $DateTime.ToUnixTimeMilliseconds()
        }
        else {
            $DateTime.ToUnixTimeSeconds()
        }
    }
}
