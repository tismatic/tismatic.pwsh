function Get-MgLicenseBreakdownPerDomain {
	[CmdletBinding()]
	param (
		[Parameter(ValueFromPipeline)]
		[Alias('InputObject')]
		[object]$ReportData,
		[string[]]$Ignore = @()
	)
		
	begin {
		$allRows = @()
	}
		
	process {
		if ($null -eq $ReportData) {
			Write-Verbose "No input provided. Retrieving report data from Microsoft Graph..."
			try {
				$ReportData = Get-MgReport -Report "getOffice365ActiveUserDetail" -Period "D30"
			}
			catch {
				Write-Error "Failed to retrieve data from Get-MgReport: $_"
				return
			}
		}
			
		if ($ReportData -is [string] -and (Test-Path $ReportData)) {
			$allRows += Import-Csv -Path $ReportData
		}
		elseif ($ReportData -is [PSObject] -or $ReportData -is [System.Collections.IEnumerable]) {
			$allRows += $ReportData
		}
		else {
			Write-Warning "Unsupported input type or invalid path: $ReportData"
		}
	}
		
	end {
		$expanded = foreach ($row in $allRows) {
			$licenses = $row.'AssignedProducts' -split '\+'
			foreach ($license in $licenses) {
				$license = $license.Trim()
				if (-not [string]::IsNullOrWhiteSpace($license) -and $Ignore -notcontains $license) {
					[pscustomobject]@{
						EmailDomain     = ($row.'UserPrincipalName' -split '@')[-1]
						AssignedProduct = $license
					}
				}
			}
		}
			
		$grouped = $expanded | Group-Object EmailDomain, AssignedProduct | Sort-Object Name
			
		$grouped | ForEach-Object {
			[pscustomobject]@{
				EmailDomain     = $_.Group[0].EmailDomain
				AssignedProduct = $_.Group[0].AssignedProduct
				UserCount       = $_.Count
			}
		}
	}
}