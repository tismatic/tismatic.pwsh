# .SYNOPSIS
# Gets a list of files shared with the current user from other users' OneDrives.

function Get-MgFilesSharedWithMe {
    [CmdletBinding()]
    param(
        # Optional: filter to a specific user's OneDrive shares (UPN/email)
        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias("UserPrincipalName")]
        [string]$SharedByUpn,

        # Optional: filename filter (PowerShell -like), e.g. "*DNS*" or "*.xlsx"
        [Parameter()]
        [string]$NameLike,

        # Search page size
        [Parameter()]
        [ValidateRange(1, 500)]
        [int]$PageSize = 200,

        # Pull all pages (up to MaxPages)
        [Parameter()]
        [switch]$All,

        # Safety cap when -All is used
        [Parameter()]
        [ValidateRange(1, 200)]
        [int]$MaxPages = 20,

        # If not already connected, connect with these scopes
        [Parameter()]
        [string[]]$Scopes = @("Files.Read.All", "Sites.Read.All")
    )

    if (-not (Get-MgContext)) {
        Connect-MgGraph -Scopes $Scopes | Out-Null
    }

    # Get your OneDrive webUrl so we can exclude your own "personal/<you>/" path
    $meDrive = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/me/drive?`$select=webUrl"
    $myDriveUrl = $meDrive.webUrl

    $uriHost = ([Uri]$myDriveUrl).Host
    $personalBase = "https://$uriHost/personal/"

    # If filtering by sharer, convert UPN/email to the SPO personal token
    # amalinowsky@apcisg.com -> amalinowsky_apcisg_com
    $sharedByToken = $null
    if ($SharedByUpn) {
        $sharedByToken = ($SharedByUpn -replace '[@\.]', '_')
    }

    $out = New-Object System.Collections.Generic.List[object]

    $pagesToFetch = if ($All) { $MaxPages } else { 1 }

    for ($page = 0; $page -lt $pagesToFetch; $page++) {
        $from = $page * $PageSize

        # KQL: look in all personal OneDrives, exclude your own personal drive path
        $kql = "path:`"$personalBase`" AND -path:`"$myDriveUrl`""

        $body = @{
            requests = @(
                @{
                    entityTypes = @("driveItem")
                    query       = @{ queryString = $kql }
                    from        = $from
                    size        = $PageSize
                    fields      = @("id", "name", "webUrl", "parentReference")
                }
            )
        } | ConvertTo-Json -Depth 10

        # Microsoft Search API query endpoint
        $resp = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/search/query" -Body $body

        $hits = @($resp.value[0].hitsContainers[0].hits)
        if (-not $hits -or $hits.Count -eq 0) { break }

        foreach ($h in $hits) {
            $r = $h.resource
            if (-not $r) { continue }

            # Optional: filter to a specific sharer's OneDrive path
            if ($sharedByToken) {
                if ($r.webUrl -notmatch "/personal/$([Regex]::Escape($sharedByToken))/" ) { continue }
            }

            # Optional: -like filter on the name
            if ($NameLike) {
                if ($r.name -notlike $NameLike) { continue }
            }

            $out.Add([pscustomobject]@{
                    Name   = $r.name
                    WebUrl = $r.webUrl
                })
        }

        # Stop early if we got less than a full page (no more results)
        if ($hits.Count -lt $PageSize) { break }
    }

    $out | Sort-Object Name, WebUrl -Unique
}