function ConvertTo-HumanDuration {
    [CmdletBinding(DefaultParameterSetName = 'Timespan')]
    param(
        # Pass a [TimeSpan] directly
        [Parameter(Mandatory, ParameterSetName = 'Timespan', ValueFromPipeline)]
        [TimeSpan]$TimeSpan,

        # Or pass two dates (or a date and "now") and it will compute the difference
        [Parameter(Mandatory, ParameterSetName = 'Dates')]
        [datetime]$From,

        [Parameter(ParameterSetName = 'Dates')]
        [datetime]$To = (Get-Date),

        # How many units to include in the output (e.g., "1 hour, 30 mins" => 2)
        [ValidateRange(1, 5)]
        [int]$MaxParts = 2,

        # Rounding behavior for the last part in the output
        [ValidateSet('Floor', 'Round', 'Ceiling')]
        [string]$Rounding = 'Floor',

        # When the duration is 0, return this string
        [string]$ZeroText = '0 seconds',

        # If using Dates: show "in ..." for future and "... ago" for past
        [switch]$IncludeDirection
    )

    begin {
        function Get-UnitLabel([string]$Unit, [long]$Value) {
            if ($Value -eq 1) { return $Unit }
            switch ($Unit) {
                'day' { 'days' }
                'hour' { 'hours' }
                'minute' { 'mins' }
                'second' { 'secs' }
                default { "${Unit}s" }
            }
        }

        function Apply-Rounding([double]$Value, [string]$Mode) {
            switch ($Mode) {
                'Floor' { [math]::Floor($Value) }
                'Ceiling' { [math]::Ceiling($Value) }
                'Round' { [math]::Round($Value) }
            }
        }
    }

    process {
        $directionPrefix = $null
        $directionSuffix = $null

        if ($PSCmdlet.ParameterSetName -eq 'Dates') {
            $delta = $To - $From
            if ($IncludeDirection) {
                if ($delta.Ticks -lt 0) {
                    $delta = $delta.Negate()
                    $directionPrefix = 'in '
                }
                else {
                    $directionSuffix = ' ago'
                }
            }
            else {
                if ($delta.Ticks -lt 0) { $delta = $delta.Negate() }
            }
            $TimeSpan = $delta
        }

        if ($TimeSpan.Ticks -lt 0) { $TimeSpan = $TimeSpan.Negate() }

        if ($TimeSpan.Ticks -eq 0) {
            return ($directionPrefix + $ZeroText + $directionSuffix)
        }

        # Work in whole seconds to keep formatting stable
        $totalSeconds = [math]::Floor($TimeSpan.TotalSeconds)

        $units = @(
            @{ Name = 'day'; Seconds = 86400L }
            @{ Name = 'hour'; Seconds = 3600L }
            @{ Name = 'minute'; Seconds = 60L }
            @{ Name = 'second'; Seconds = 1L }
        )

        $parts = New-Object System.Collections.Generic.List[string]
        $remaining = [double]$totalSeconds

        # Build all but the last part using floor
        for ($i = 0; $i -lt $units.Count -and $parts.Count -lt ($MaxParts - 1); $i++) {
            $u = $units[$i]
            $count = [long]([math]::Floor($remaining / $u.Seconds))
            if ($count -gt 0) {
                $parts.Add(("{0} {1}" -f $count, (Get-UnitLabel $u.Name $count)))
                $remaining -= ($count * $u.Seconds)
            }
        }

        # Last part: choose the best unit for what's left (or next smaller unit) and apply rounding mode
        if ($parts.Count -lt $MaxParts) {
            # Pick the largest unit that fits, otherwise seconds
            $lastUnit = $units | Where-Object { $remaining -ge $_.Seconds } | Select-Object -First 1
            if (-not $lastUnit) { $lastUnit = $units[-1] }

            $raw = $remaining / $lastUnit.Seconds
            $lastCount = [long](Apply-Rounding $raw $Rounding)

            # If rounding produced 0, drop to the next smaller unit if possible
            if ($lastCount -le 0 -and $lastUnit.Seconds -gt 1) {
                $idx = [array]::IndexOf($units, $lastUnit)
                $lastUnit = $units[[math]::Min($idx + 1, $units.Count - 1)]
                $raw = $remaining / $lastUnit.Seconds
                $lastCount = [long](Apply-Rounding $raw $Rounding)
            }

            if ($lastCount -gt 0) {
                $parts.Add(("{0} {1}" -f $lastCount, (Get-UnitLabel $lastUnit.Name $lastCount)))
            }
        }

        if ($parts.Count -eq 0) {
            $out = $ZeroText
        }
        else {
            $out = ($parts -join ', ')
        }

        return ($directionPrefix + $out + $directionSuffix)
    }
}