function Get-MgLicenseSummary {
	<#
	.SYNOPSIS
	  Summarize Microsoft 365/Entra license inventory with friendly names.
	
	.DESCRIPTION
	  Combines the Microsoft licensing catalog CSV with Get-MgSubscribedSku
	  to return a per-SKU breakdown of Available, Used, and Total licenses.
	  Uses a cached CSV (per session) for fast lookups; force refresh with -RefreshCatalog.
	
	.PARAMETER Exclude
	  One or more strings/regex patterns to exclude (matched against
	  Product_Display_Name, String_Id, or GUID). Defaults to common "noise" SKUs.
	
	.PARAMETER Search
	  Optional regex to include ONLY rows that match Product_Display_Name, String_Id, or GUID.
	
	.PARAMETER RefreshCatalog
	  Force re-download of the Microsoft licensing CSV.
	
	.EXAMPLE
	  Get-MgLicenseSummary
	
	.EXAMPLE
	  Get-MgLicenseSummary -Search 'E3|E5'
	
	.EXAMPLE
	  Get-MgLicenseSummary -Exclude 'POWER_BI_STANDARD','FLOW_FREE'
	
	#>
	[CmdletBinding()]
	param (
		[string[]]$Exclude = @(
			'FLOW_FREE',
			'TEAMS_EXPLORATORY',
			'WINDOWS_STORE',
			'MICROSOFT_BUSINESS_CENTER',
			'POWER_BI_STANDARD',
			'VIRTUAL_AGENT_BASE'
		),
		[string]$Search,
		[switch]$RefreshCatalog
	)
		
	begin {
		# --- Load/CACHE the Microsoft licensing catalog CSV once per session ---
		if ($RefreshCatalog -or -not $script:MSPlanCatalog) {
			$csvUri = "https://download.microsoft.com/download/e/3/e/e3e9faf2-f28b-490a-9ada-c6089a1fc5b0/Product%20names%20and%20service%20plan%20identifiers%20for%20licensing.csv"
			try {
				$script:MSPlanCatalog = (Invoke-RestMethod -Uri $csvUri) | ConvertFrom-Csv
			}
			catch {
				throw "Failed to download/parse licensing catalog CSV from Microsoft. $_"
			}
				
			# Build fast lookup maps
			$script:MSPlanByGuid = $script:MSPlanCatalog | Group-Object -Property GUID -AsHashTable
			$script:MSPlanByStringId = $script:MSPlanCatalog | Group-Object -Property String_Id -AsHashTable
			$script:MSPlanByName = $script:MSPlanCatalog | Group-Object -Property Product_Display_Name -AsHashTable
		}
			
		# Pull SKUs from tenant
		try {
			$skus = Get-MgSubscribedSku
		}
		catch {
			throw "Get-MgSubscribedSku failed. Ensure you're connected and have permissions. $_"
		}
			
		# Normalize Exclude list to empty array if $null
		if (-not $Exclude) {
			$Exclude = @()
		}
	}
		
	process {
		$Report = foreach ($sku in $skus) {
			# Basic numbers
			$enabled = [int]$sku.prepaidUnits.enabled
			$warning = [int]$sku.prepaidUnits.warning
			$suspended = [int]$sku.prepaidUnits.suspended
			$total = $enabled + $warning
			$used = [int]$sku.consumedUnits
			$available = $total - $used
				
			# Lookup friendly metadata from the catalog
			$guid = ([string]$sku.SkuId).ToUpper()
			$stringId = if ($sku.SkuPartNumber) {
				[string]$sku.SkuPartNumber
			}
			else {
				$null
			}
				
			# Prefer GUID; fall back to String_Id; then fall back to raw skuPartNumber
			$record = $null
			if ($script:MSPlanByGuid.ContainsKey($guid)) {
				$record = $script:MSPlanByGuid[$guid] | Select-Object -First 1
			}
			elseif ($stringId -and $script:MSPlanByStringId.ContainsKey($stringId)) {
				$record = $script:MSPlanByStringId[$stringId] | Select-Object -First 1
			}
				
			$name = if ($record) {
				$record.Product_Display_Name
			}
			elseif ($stringId) {
				$stringId
			}
			else {
				$guid
			}
				
			# Filtering - Exclude (supports regex or exact matches)
			$excludeHit = $false
			foreach ($pattern in $Exclude) {
				if ($name -match $pattern -or $stringId -match $pattern) {
					$excludeHit = $true
					break
				}
			}
			if ($excludeHit) {
				continue
			}
				
			# Filtering - Search (includes only matches)
			if ($Search) {
				if (($name -notlike "*$Search*") -and ($stringId -notlike "*$Search*")) {
					continue
				}
			}
				
			# Output row
			[pscustomobject]@{
				Product_Display_Name = $name
				String_Id            = ${record}?.String_Id ?? $stringId
				Available            = $available
				Used                 = $used
				Total                = $total
				GUID                 = $record.guid
			}
		}
			
		$Report | Sort-Object Product_Display_Name
	}
}