# .SYNOPSIS
# Imports a Liquid template and prompts for any variables that are not provided in the $Parameters hash table.  Returns the rendered template as a string.
function Import-LiquidTemplate {
    param(
        $Path,
        $Parameters
    )
    $Content = (get-content $Path -raw)
    
    if (!$Parameters) {
        $Parameters = @{}
        $ast = convertTo-LiquidAst -Template $Content
        $Variables = (($ast.nodes | Where-Object { $_.type -eq "Output" }).Expression -replace "\|.*").Trim() | select -Unique
        $Variables | % {
            if ($_ -match "pass|secret") {
                $UserInput = (Read-Host $_ -AsSecureString)
                if ($UserInput) {
                    $Parameters[$_] = $UserInput
                }
            }
            else {
                $UserInput = (Read-Host $_)
                if ($UserInput) {
                    $Parameters[$_] = $UserInput
                }
            }
        }
    }

    Invoke-LiquidTemplate -Template $Content -Context $Parameters

}