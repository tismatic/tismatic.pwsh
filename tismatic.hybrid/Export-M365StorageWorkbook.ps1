function Export-M365StorageWorkbook {
    [CmdletBinding()]
    param (
        [Parameter()]
        [ValidateSet('D7', 'D30', 'D90', 'D180')]
        [string]$Period = 'D7',

        [Parameter()]
        [ValidateRange(1, 100)]
        [double]$AtRiskThreshold = 70,

        [Parameter()]
        [string]$Path = (
            Join-Path $PWD (
                'M365-Storage-Report_{0}.xlsx' -f (
                    Get-Date -Format 'yyyy-MM-dd_HHmm'
                )
            )
        ),

        [Parameter()]
        [switch]$Show
    )

    Import-Module ImportExcel -ErrorAction Stop

    if (-not (Get-Command Get-MgReport -ErrorAction SilentlyContinue)) {
        throw 'The Get-MgReport function is not available in the current session.'
    }

    #region Helper functions

    function Convert-BytesToGB {
        param (
            [AllowNull()]
            [object]$Bytes
        )

        if ($null -eq $Bytes -or [string]::IsNullOrWhiteSpace([string]$Bytes)) {
            return 0
        }

        [math]::Round(([double]$Bytes / 1GB), 2)
    }

    function Get-PercentFull {
        param (
            [AllowNull()]
            [object]$Used,

            [AllowNull()]
            [object]$Quota
        )

        $UsedValue  = [double]$Used
        $QuotaValue = [double]$Quota

        if ($QuotaValue -le 0) {
            return $null
        }

        [math]::Round(($UsedValue / $QuotaValue) * 100, 2)
    }

    function Get-CapacityStatus {
        param (
            [AllowNull()]
            [object]$Percent
        )

        if ($null -eq $Percent) {
            return 'Unknown'
        }

        switch ([double]$Percent) {
            { $_ -ge 95 } { return 'Critical' }
            { $_ -ge 90 } { return 'Very High' }
            { $_ -ge 80 } { return 'High' }
            { $_ -ge 70 } { return 'Elevated' }
            default       { return 'Normal' }
        }
    }

    function Convert-ToReportDate {
        param (
            [AllowNull()]
            [object]$Value
        )

        if ([string]::IsNullOrWhiteSpace([string]$Value)) {
            return $null
        }

        $ParsedDate = [datetime]::MinValue

        if (
            [datetime]::TryParse(
                [string]$Value,
                [ref]$ParsedDate
            )
        ) {
            return $ParsedDate
        }

        $Value
    }

    function New-SummaryRow {
        param (
            [Parameter(Mandatory)]
            [string]$Service,

            [Parameter()]
            [object[]]$Data,

            [Parameter(Mandatory)]
            [string]$UsedProperty,

            [Parameter(Mandatory)]
            [string]$QuotaProperty,

            [Parameter(Mandatory)]
            [string]$PercentProperty
        )

        $Items = @($Data)

        $TotalUsed = (
            $Items |
                Measure-Object -Property $UsedProperty -Sum
        ).Sum

        $TotalQuota = (
            $Items |
                Measure-Object -Property $QuotaProperty -Sum
        ).Sum

        if ($null -eq $TotalUsed) {
            $TotalUsed = 0
        }

        if ($null -eq $TotalQuota) {
            $TotalQuota = 0
        }

        [PSCustomObject][ordered]@{
            Service           = $Service
            Resources         = $Items.Count
            AtRiskThreshold   = $AtRiskThreshold
            AtRiskCount       = @(
                $Items |
                    Where-Object {
                        $null -ne $_.$PercentProperty -and
                        $_.$PercentProperty -ge $AtRiskThreshold
                    }
            ).Count
            Over70Percent     = @(
                $Items |
                    Where-Object { $_.$PercentProperty -ge 70 }
            ).Count
            Over80Percent     = @(
                $Items |
                    Where-Object { $_.$PercentProperty -ge 80 }
            ).Count
            Over90Percent     = @(
                $Items |
                    Where-Object { $_.$PercentProperty -ge 90 }
            ).Count
            Over95Percent     = @(
                $Items |
                    Where-Object { $_.$PercentProperty -ge 95 }
            ).Count
            TotalUsedGB       = [math]::Round($TotalUsed, 2)
            TotalQuotaGB      = [math]::Round($TotalQuota, 2)
            TotalRemainingGB  = [math]::Round(
                ($TotalQuota - $TotalUsed),
                2
            )
        }
    }

    function Export-ReportWorksheet {
        param (
            [Parameter()]
            [object[]]$Data,

            [Parameter(Mandatory)]
            [string]$WorksheetName,

            [Parameter(Mandatory)]
            [string]$TableName,

            [Parameter()]
            [switch]$Append
        )

        $ExportData = @($Data)

        if ($ExportData.Count -eq 0) {
            $ExportData = @(
                [PSCustomObject]@{
                    Message = "No data was returned for $WorksheetName."
                }
            )
        }

        $Parameters = @{
            Path            = $Path
            WorksheetName   = $WorksheetName
            TableName       = $TableName
            TableStyle      = 'Medium2'
            AutoSize        = $true
            MaxAutoSizeRows = 1000
            FreezeTopRow    = $true
            BoldTopRow      = $true
            ConditionalText = $CapacityFormatting
        }

        if ($Append) {
            $Parameters.Append = $true
        }

        $ExportData |
            Export-Excel @Parameters
    }

    #endregion Helper functions

    # Exact text matching prevents "High" from also matching "Very High".
    $CapacityFormatting = @(
        New-ConditionalText `
            -Text 'Critical' `
            -ConditionalType Equal `
            -ConditionalTextColor White `
            -BackgroundColor DarkRed

        New-ConditionalText `
            -Text 'Very High' `
            -ConditionalType Equal `
            -ConditionalTextColor White `
            -BackgroundColor Red

        New-ConditionalText `
            -Text 'High' `
            -ConditionalType Equal `
            -ConditionalTextColor Black `
            -BackgroundColor Orange

        New-ConditionalText `
            -Text 'Elevated' `
            -ConditionalType Equal `
            -ConditionalTextColor Black `
            -BackgroundColor Gold

        New-ConditionalText `
            -Text 'Normal' `
            -ConditionalType Equal `
            -ConditionalTextColor DarkGreen `
            -BackgroundColor LightGreen

        New-ConditionalText `
            -Text 'Unknown' `
            -ConditionalType Equal `
            -ConditionalTextColor Black `
            -BackgroundColor LightGray
    )

    $ParentDirectory = Split-Path -Path $Path -Parent

    if (
        $ParentDirectory -and
        -not (Test-Path -LiteralPath $ParentDirectory)
    ) {
        $null = New-Item `
            -Path $ParentDirectory `
            -ItemType Directory `
            -Force
    }

    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Force
    }

    #region Retrieve reports

    Write-Verbose 'Retrieving OneDrive usage report.'

    $OneDriveRaw = @(
        Get-MgReport `
            -Report getOneDriveUsageAccountDetail `
            -Period $Period
    )

    Write-Verbose 'Retrieving SharePoint usage report.'

    $SharePointRaw = @(
        Get-MgReport `
            -Report getSharePointSiteUsageDetail `
            -Period $Period
    )

    Write-Verbose 'Retrieving Exchange mailbox usage report.'

    $ExchangeRaw = @(
        Get-MgReport `
            -Report getMailboxUsageDetail `
            -Period $Period
    )

    #endregion Retrieve reports

    #region OneDrive

    $OneDrive = @(
        foreach ($Item in $OneDriveRaw) {
            $UsedBytes      = [double]$Item.storageUsedInBytes
            $AllocatedBytes = [double]$Item.storageAllocatedInBytes
            $PercentFull    = Get-PercentFull `
                -Used $UsedBytes `
                -Quota $AllocatedBytes

            [PSCustomObject][ordered]@{
                OwnerDisplayName  = $Item.ownerDisplayName
                OwnerPrincipalName = $Item.ownerPrincipalName
                SiteUrl           = $Item.siteUrl
                LastActivityDate  = Convert-ToReportDate $Item.lastActivityDate
                FileCount         = [long]$Item.fileCount
                ActiveFileCount   = [long]$Item.activeFileCount
                UsedGB            = Convert-BytesToGB $UsedBytes
                AllocatedGB       = Convert-BytesToGB $AllocatedBytes
                RemainingGB       = Convert-BytesToGB (
                    $AllocatedBytes - $UsedBytes
                )
                PercentFull       = $PercentFull
                CapacityStatus    = Get-CapacityStatus $PercentFull
                IsDeleted         = [bool]$Item.isDeleted
                ReportRefreshDate = Convert-ToReportDate $Item.reportRefreshDate
            }
        }
    ) | Sort-Object PercentFull -Descending

    #endregion OneDrive

    #region SharePoint

    $SharePoint = @(
        foreach ($Item in $SharePointRaw) {
            $UsedBytes      = [double]$Item.storageUsedInBytes
            $AllocatedBytes = [double]$Item.storageAllocatedInBytes
            $PercentFull    = Get-PercentFull `
                -Used $UsedBytes `
                -Quota $AllocatedBytes

            [PSCustomObject][ordered]@{
                OwnerDisplayName   = $Item.ownerDisplayName
                OwnerPrincipalName = $Item.ownerPrincipalName
                SiteUrl            = $Item.siteUrl
                RootWebTemplate    = $Item.rootWebTemplate
                LastActivityDate   = Convert-ToReportDate $Item.lastActivityDate
                FileCount          = [long]$Item.fileCount
                ActiveFileCount    = [long]$Item.activeFileCount
                PageViewCount      = [long]$Item.pageViewCount
                VisitedPageCount   = [long]$Item.visitedPageCount
                UsedGB             = Convert-BytesToGB $UsedBytes
                AllocatedGB        = Convert-BytesToGB $AllocatedBytes
                RemainingGB        = Convert-BytesToGB (
                    $AllocatedBytes - $UsedBytes
                )
                PercentFull        = $PercentFull
                CapacityStatus     = Get-CapacityStatus $PercentFull
                ExternalSharing    = $Item.externalSharing
                IsDeleted          = [bool]$Item.isDeleted
                ReportRefreshDate  = Convert-ToReportDate $Item.reportRefreshDate
            }
        }
    ) | Sort-Object PercentFull -Descending

    #endregion SharePoint

    #region Exchange

    $Exchange = @(
        foreach ($Item in $ExchangeRaw) {
            $UsedBytes        = [double]$Item.storageUsedInBytes
            $WarningBytes     = [double]$Item.issueWarningQuotaInBytes
            $SendQuotaBytes   = [double]$Item.prohibitSendQuotaInBytes
            $MailboxQuotaBytes = [double]$Item.prohibitSendReceiveQuotaInBytes

            $DeletedBytes      = [double]$Item.deletedItemSizeInBytes
            $DeletedQuotaBytes = [double]$Item.deletedItemQuota

            $MailboxPercent = Get-PercentFull `
                -Used $UsedBytes `
                -Quota $MailboxQuotaBytes

            $DeletedPercent = Get-PercentFull `
                -Used $DeletedBytes `
                -Quota $DeletedQuotaBytes

            [PSCustomObject][ordered]@{
                DisplayName              = $Item.displayName
                UserPrincipalName         = $Item.userPrincipalName
                RecipientType             = $Item.recipientType
                CreatedDate               = Convert-ToReportDate $Item.createdDate
                LastActivityDate          = Convert-ToReportDate $Item.lastActivityDate
                ItemCount                 = [long]$Item.itemCount

                UsedGB                    = Convert-BytesToGB $UsedBytes
                IssueWarningQuotaGB       = Convert-BytesToGB $WarningBytes
                ProhibitSendQuotaGB       = Convert-BytesToGB $SendQuotaBytes
                MailboxQuotaGB            = Convert-BytesToGB $MailboxQuotaBytes
                MailboxRemainingGB        = Convert-BytesToGB (
                    $MailboxQuotaBytes - $UsedBytes
                )
                MailboxPercentFull        = $MailboxPercent
                MailboxCapacityStatus     = Get-CapacityStatus $MailboxPercent

                DeletedItemCount          = [long]$Item.deletedItemCount
                DeletedItemSizeGB         = Convert-BytesToGB $DeletedBytes
                DeletedItemQuotaGB        = Convert-BytesToGB $DeletedQuotaBytes
                DeletedItemRemainingGB    = Convert-BytesToGB (
                    $DeletedQuotaBytes - $DeletedBytes
                )
                DeletedItemPercentFull    = $DeletedPercent
                DeletedItemCapacityStatus = Get-CapacityStatus $DeletedPercent

                HasArchive                = [bool]$Item.hasArchive
                IsDeleted                 = [bool]$Item.isDeleted
                DeletedDate               = Convert-ToReportDate $Item.deletedDate
                ReportRefreshDate         = Convert-ToReportDate $Item.reportRefreshDate
            }
        }
    ) | Sort-Object MailboxPercentFull -Descending

    #endregion Exchange

    #region Summary

    $Summary = @(
        New-SummaryRow `
            -Service 'OneDrive' `
            -Data $OneDrive `
            -UsedProperty UsedGB `
            -QuotaProperty AllocatedGB `
            -PercentProperty PercentFull

        New-SummaryRow `
            -Service 'SharePoint' `
            -Data $SharePoint `
            -UsedProperty UsedGB `
            -QuotaProperty AllocatedGB `
            -PercentProperty PercentFull

        New-SummaryRow `
            -Service 'Exchange Mailboxes' `
            -Data $Exchange `
            -UsedProperty UsedGB `
            -QuotaProperty MailboxQuotaGB `
            -PercentProperty MailboxPercentFull

        New-SummaryRow `
            -Service 'Exchange Deleted Items' `
            -Data $Exchange `
            -UsedProperty DeletedItemSizeGB `
            -QuotaProperty DeletedItemQuotaGB `
            -PercentProperty DeletedItemPercentFull
    )

    #endregion Summary

    #region At-risk combined report

    $AtRisk = @(
        foreach ($Item in $OneDrive) {
            if (
                $null -ne $Item.PercentFull -and
                $Item.PercentFull -ge $AtRiskThreshold
            ) {
                [PSCustomObject][ordered]@{
                    Service        = 'OneDrive'
                    Resource       = $Item.OwnerDisplayName
                    Identity       = $Item.OwnerPrincipalName
                    Url            = $Item.SiteUrl
                    UsedGB         = $Item.UsedGB
                    QuotaGB        = $Item.AllocatedGB
                    RemainingGB    = $Item.RemainingGB
                    PercentFull    = $Item.PercentFull
                    CapacityStatus = $Item.CapacityStatus
                }
            }
        }

        foreach ($Item in $SharePoint) {
            if (
                $null -ne $Item.PercentFull -and
                $Item.PercentFull -ge $AtRiskThreshold
            ) {
                [PSCustomObject][ordered]@{
                    Service        = 'SharePoint'
                    Resource       = $Item.OwnerDisplayName
                    Identity       = $Item.OwnerPrincipalName
                    Url            = $Item.SiteUrl
                    UsedGB         = $Item.UsedGB
                    QuotaGB        = $Item.AllocatedGB
                    RemainingGB    = $Item.RemainingGB
                    PercentFull    = $Item.PercentFull
                    CapacityStatus = $Item.CapacityStatus
                }
            }
        }

        foreach ($Item in $Exchange) {
            if (
                $null -ne $Item.MailboxPercentFull -and
                $Item.MailboxPercentFull -ge $AtRiskThreshold
            ) {
                [PSCustomObject][ordered]@{
                    Service        = 'Exchange Mailbox'
                    Resource       = $Item.DisplayName
                    Identity       = $Item.UserPrincipalName
                    Url            = $null
                    UsedGB         = $Item.UsedGB
                    QuotaGB        = $Item.MailboxQuotaGB
                    RemainingGB    = $Item.MailboxRemainingGB
                    PercentFull    = $Item.MailboxPercentFull
                    CapacityStatus = $Item.MailboxCapacityStatus
                }
            }

            if (
                $null -ne $Item.DeletedItemPercentFull -and
                $Item.DeletedItemPercentFull -ge $AtRiskThreshold
            ) {
                [PSCustomObject][ordered]@{
                    Service        = 'Exchange Deleted Items'
                    Resource       = $Item.DisplayName
                    Identity       = $Item.UserPrincipalName
                    Url            = $null
                    UsedGB         = $Item.DeletedItemSizeGB
                    QuotaGB        = $Item.DeletedItemQuotaGB
                    RemainingGB    = $Item.DeletedItemRemainingGB
                    PercentFull    = $Item.DeletedItemPercentFull
                    CapacityStatus = $Item.DeletedItemCapacityStatus
                }
            }
        }
    ) | Sort-Object PercentFull -Descending

    #endregion At-risk combined report

    #region Export workbook

    Export-ReportWorksheet `
        -Data $Summary `
        -WorksheetName 'Summary' `
        -TableName 'StorageSummary'

    Export-ReportWorksheet `
        -Data $AtRisk `
        -WorksheetName 'At Risk' `
        -TableName 'AtRiskResources' `
        -Append

    Export-ReportWorksheet `
        -Data $OneDrive `
        -WorksheetName 'OneDrive' `
        -TableName 'OneDriveUsage' `
        -Append

    Export-ReportWorksheet `
        -Data $SharePoint `
        -WorksheetName 'SharePoint' `
        -TableName 'SharePointUsage' `
        -Append

    Export-ReportWorksheet `
        -Data $Exchange `
        -WorksheetName 'Exchange' `
        -TableName 'ExchangeUsage' `
        -Append

    # Apply consistent Excel number formats and prevent huge URL columns.
    $ExcelPackage = Open-ExcelPackage -Path $Path

    try {
        foreach ($Worksheet in $ExcelPackage.Workbook.Worksheets) {
            if (-not $Worksheet.Dimension) {
                continue
            }

            $Worksheet.View.ShowGridLines = $false

            $HeaderColumns = @{}

            for (
                $Column = 1
                $Column -le $Worksheet.Dimension.End.Column
                $Column++
            ) {
                $Header = [string]$Worksheet.Cells[1, $Column].Value

                if ($Header) {
                    $HeaderColumns[$Header] = $Column
                }
            }

            foreach (
                $Header in @(
                    'UsedGB',
                    'AllocatedGB',
                    'RemainingGB',
                    'QuotaGB',
                    'TotalUsedGB',
                    'TotalQuotaGB',
                    'TotalRemainingGB',
                    'IssueWarningQuotaGB',
                    'ProhibitSendQuotaGB',
                    'MailboxQuotaGB',
                    'MailboxRemainingGB',
                    'DeletedItemSizeGB',
                    'DeletedItemQuotaGB',
                    'DeletedItemRemainingGB'
                )
            ) {
                if ($HeaderColumns.ContainsKey($Header)) {
                    $Worksheet.Column(
                        $HeaderColumns[$Header]
                    ).Style.Numberformat.Format = '#,##0.00'
                }
            }

            foreach (
                $Header in @(
                    'PercentFull',
                    'MailboxPercentFull',
                    'DeletedItemPercentFull',
                    'AtRiskThreshold'
                )
            ) {
                if ($HeaderColumns.ContainsKey($Header)) {
                    # Values are stored as 0-100, so the percent symbol is literal.
                    $Worksheet.Column(
                        $HeaderColumns[$Header]
                    ).Style.Numberformat.Format = '0.00"%"'
                }
            }

            foreach (
                $Header in @(
                    'CreatedDate',
                    'DeletedDate',
                    'LastActivityDate',
                    'ReportRefreshDate'
                )
            ) {
                if ($HeaderColumns.ContainsKey($Header)) {
                    $Worksheet.Column(
                        $HeaderColumns[$Header]
                    ).Style.Numberformat.Format = 'yyyy-mm-dd'
                }
            }

            foreach ($Header in @('SiteUrl', 'Url')) {
                if ($HeaderColumns.ContainsKey($Header)) {
                    $UrlColumn = $Worksheet.Column(
                        $HeaderColumns[$Header]
                    )

                    $UrlColumn.Width = 60
                    $UrlColumn.Style.WrapText = $true
                }
            }

            # Cap automatically sized columns so unusually long values
            # do not make the workbook difficult to navigate.
            for (
                $Column = 1
                $Column -le $Worksheet.Dimension.End.Column
                $Column++
            ) {
                if ($Worksheet.Column($Column).Width -gt 60) {
                    $Worksheet.Column($Column).Width = 60
                }
            }
        }
    }
    finally {
        Close-ExcelPackage $ExcelPackage
    }

    #endregion Export workbook

    $Result = Get-Item -LiteralPath $Path

    if ($Show) {
        Invoke-Item -LiteralPath $Result.FullName
    }

    $Result
}