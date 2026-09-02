function Get-MgSubscriptionReport {
    param(
        [guid]$TenantId,

        [string]$OutputPath = (Join-Path $PWD 'M365-Subscription-Report')
    )

    $ErrorActionPreference = 'Stop'

    if (-not (Test-Path $OutputPath)) {
        New-Item -Path $OutputPath -ItemType Directory | Out-Null
    }

    $scopes = @(
        'Organization.Read.All'
    )

    if ($TentantId) {
        Connect-MgGraph -TenantId $TenantId -Scopes $scopes -NoWelcome -ContextScope Process 
    }
    

    $context = Get-MgContext
    $subscriptions = Get-MgDirectorySubscription -All
    $skus = Get-MgSubscribedSku -All

    $report = foreach ($subscription in $subscriptions) {

        $sku = $skus | Where-Object { $_.SkuId -eq $subscription.SkuId } | Select-Object -First 1

        $purchased = if ($null -ne $sku) {
            [int]$sku.PrepaidUnits.Enabled
        }
        else {
            [int]$subscription.TotalLicenses
        }

        $assigned = if ($null -ne $sku) {
            [int]$sku.ConsumedUnits
        }
        else {
            $null
        }

        $available = if ($null -ne $assigned) {
            $purchased - $assigned
        }
        else {
            $null
        }

        $nextLifecycle = if ($subscription.NextLifecycleDateTime) {
            [datetime]$subscription.NextLifecycleDateTime
        }
        else {
            $null
        }

        $daysRemaining = if ($nextLifecycle) {
            [math]::Floor(($nextLifecycle.ToLocalTime() - (Get-Date)).TotalDays)
        }
        else {
            $null
        }

        [pscustomobject]@{
            SkuPartNumber          = $subscription.SkuPartNumber
            SkuId                  = $subscription.SkuId
            CommerceSubscriptionId = $subscription.CommerceSubscriptionId
            Status                 = $subscription.Status
            IsTrial                = $subscription.IsTrial
            PurchasedLicenses      = $purchased
            AssignedLicenses       = $assigned
            AvailableLicenses      = $available
            NextLifecycleDate      = if ($nextLifecycle) { $nextLifecycle.ToLocalTime() } else { $null }
            DaysUntilLifecycle     = $daysRemaining
            OwnerType              = $subscription.OwnerType
            OwnerId                = $subscription.OwnerId
            OwnerTenantId          = $subscription.OwnerTenantId
            CreatedDate            = $subscription.CreatedDateTime
        }
    }

    $properties = @(
        'SkuPartNumber'
        'Status'
        'IsTrial'
        'PurchasedLicenses'
        'AssignedLicenses'
        'AvailableLicenses'
        'NextLifecycleDate'
        'DaysUntilLifecycle'
        'CommerceSubscriptionId'
        'OwnerType'
    )

    $report = $report | Sort-Object NextLifecycleDate, SkuPartNumber

    $report | Select-Object -Property $properties | Format-Table -AutoSize

    $csvPath = Join-Path $OutputPath 'M365-Subscriptions.csv'
    $report | Export-Csv -Path $csvPath -NoTypeInformation -Encoding utf8

    $style = @'
<style>
body {
    font-family: "Segoe UI", Arial, sans-serif;
    margin: 30px;
    font-size: 14px;
}
h1 {
    margin-bottom: 5px;
}
.summary {
    margin-bottom: 25px;
}
table {
    border-collapse: collapse;
    width: 100%;
}
th {
    background-color: #f2f2f2;
    font-weight: 600;
}
th, td {
    border: 1px solid #d0d0d0;
    padding: 7px;
    text-align: left;
}
</style>
'@

    $htmlProperties = @(
        'SkuPartNumber'
        'Status'
        'PurchasedLicenses'
        'AssignedLicenses'
        'AvailableLicenses'
        'NextLifecycleDate'
        'DaysUntilLifecycle'
        'CommerceSubscriptionId'
    )

    $table = $report | Select-Object -Property $htmlProperties | ConvertTo-Html -Fragment

    $generated = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

    $body = @"
<h1>Microsoft 365 Subscription Report</h1>
<div class="summary">
Tenant: $($context.TenantId)<br>
Generated: $generated<br>
Subscriptions: $($report.Count)
</div>
$table
"@

    $htmlPath = Join-Path $OutputPath 'M365-Subscriptions.html'
    ConvertTo-Html -Title 'Microsoft 365 Subscription Report' -Head $style -Body $body | Set-Content -Path $htmlPath -Encoding utf8

    Write-Host ''
    Write-Host "CSV:  $csvPath"
    Write-Host "HTML: $htmlPath"

    Disconnect-MgGraph | Out-Null
}