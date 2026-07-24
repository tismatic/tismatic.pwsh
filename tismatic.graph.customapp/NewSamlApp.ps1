<#
Requires a Microsoft Graph connection with Application.ReadWrite.All and
Policy.ReadWrite.ApplicationConfiguration. Custom claims use the beta
customClaimsPolicy endpoint so that they remain manageable in the Entra portal.
#>

function ConvertTo-MgSamlSourcedClaim {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [ValidateNotNullOrEmpty()]
        [string]$Namespace = 'http://schemas.xmlsoap.org/ws/2005/05/identity/claims',

        [Parameter(Mandatory)]
        [ValidatePattern('^[^.]+\.[^.]+$')]
        [string]$SourceAttribute,

        [switch]$IsExtensionAttribute
    )

    $source, $id = $SourceAttribute -split '\.', 2

    [ordered]@{
        '@odata.type' = '#microsoft.graph.customClaim'
        configurations = @(
            [ordered]@{
                attribute = [ordered]@{
                    source = $source
                    id = $id
                    isExtensionAttribute = [bool]$IsExtensionAttribute
                    '@odata.type' = '#microsoft.graph.sourcedAttribute'
                }
                transformations = @()
                condition = $null
            }
        )
        namespace = $Namespace
        name = $Name
        tokenFormat = @('saml')
        samlAttributeNameFormat = $null
    }
}

function ConvertTo-MgSamlValueClaim {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$Namespace,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value
    )

    [ordered]@{
        '@odata.type' = '#microsoft.graph.customClaim'
        configurations = @(
            [ordered]@{
                attribute = [ordered]@{
                    value = $Value
                    '@odata.type' = '#microsoft.graph.valueBasedAttribute'
                }
                transformations = @()
                condition = $null
            }
        )
        namespace = $Namespace
        name = $Name
        tokenFormat = @('saml')
        samlAttributeNameFormat = $null
    }
}

function ConvertTo-MgSamlNameIdClaim {
    [CmdletBinding()]
    param (
        [ValidatePattern('^[^.]+\.[^.]+$')]
        [string]$SourceAttribute = 'user.mail',

        [ValidateSet('emailAddress', 'persistent', 'transient', 'unspecified', 'default', 'windowsDomainQualifiedName')]
        [string]$NameIdFormat = 'emailAddress'
    )

    $source, $id = $SourceAttribute -split '\.', 2

    [ordered]@{
        '@odata.type' = '#microsoft.graph.samlNameIdClaim'
        configurations = @(
            [ordered]@{
                attribute = [ordered]@{
                    source = $source
                    id = $id
                    isExtensionAttribute = $false
                    '@odata.type' = '#microsoft.graph.sourcedAttribute'
                }
                transformations = @()
                condition = $null
            }
        )
        serviceProviderNameQualifier = $null
        nameIdFormat = $NameIdFormat
    }
}

function Set-MgSamlClaimsPolicy {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [Alias('ObjectId', 'SpId')]
        [ValidateNotNullOrEmpty()]
        [string]$ServicePrincipalId,

        [bool]$IncludeStandardClaims = $true,

        [ValidatePattern('^[^.]+\.[^.]+$')]
        [string]$NameIdSourceAttribute = 'user.mail',

        [ValidateSet('emailAddress', 'persistent', 'transient', 'unspecified', 'default', 'windowsDomainQualifiedName')]
        [string]$NameIdFormat = 'emailAddress',

        [object[]]$AdditionalClaims = @()
    )

    $claims = @()

    if ($IncludeStandardClaims) {
        $claims += @(
            ConvertTo-MgSamlSourcedClaim -Name 'givenname'    -SourceAttribute 'user.givenname'
            ConvertTo-MgSamlSourcedClaim -Name 'surname'      -SourceAttribute 'user.surname'
            ConvertTo-MgSamlSourcedClaim -Name 'emailaddress' -SourceAttribute 'user.mail'
            ConvertTo-MgSamlSourcedClaim -Name 'name'         -SourceAttribute 'user.userprincipalname'
        )
    }

    $claims += ConvertTo-MgSamlNameIdClaim -SourceAttribute $NameIdSourceAttribute -NameIdFormat $NameIdFormat
    $claims += @($AdditionalClaims | Where-Object { $null -ne $_ })

    $body = [ordered]@{
        '@odata.type' = '#microsoft.graph.customClaimsPolicy'
        groupFilter = $null
        includeApplicationIdInIssuer = $false
        includeBasicClaimSet = $true
        audienceOverride = $null
        claims = $claims
    }

    $uri = "https://graph.microsoft.com/beta/servicePrincipals/$ServicePrincipalId/claimsPolicy"

    if (-not $PSCmdlet.ShouldProcess($ServicePrincipalId, 'Replace the SAML custom claims policy')) {
        return
    }

    Invoke-MgGraphRequest `
        -Method PUT `
        -Uri $uri `
        -ContentType 'application/json' `
        -Body ($body | ConvertTo-Json -Depth 100) `
        -ErrorAction Stop | Out-Null

    Invoke-MgGraphRequest -Method GET -Uri $uri -ErrorAction Stop
}

function Get-MgSamlExistingApp {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$DisplayName,

        [Parameter(Mandatory)]
        [string[]]$IdentifierUri,

        [Parameter(Mandatory)]
        [string[]]$ReplyUrl
    )

    $escapedDisplayName = $DisplayName.Replace("'", "''")
    $namedApplications = @(
        Get-MgApplication `
            -Filter "displayName eq '$escapedDisplayName'" `
            -Property Id,AppId,DisplayName,IdentifierUris,Web `
            -ErrorAction Stop
    )
    $namedServicePrincipals = @(
        Get-MgServicePrincipal `
            -Filter "displayName eq '$escapedDisplayName'" `
            -Property Id,AppId,DisplayName,PreferredSingleSignOnMode,AppRoleAssignmentRequired,LoginUrl,LogoutUrl,SamlSingleSignOnSettings,KeyCredentials,PreferredTokenSigningKeyThumbprint,AppRoles `
            -ErrorAction Stop
    )

    $identifierMatches = @{}

    foreach ($identifier in $IdentifierUri) {
        $escapedIdentifier = $identifier.Replace("'", "''")
        $identifierApplications = @(
            Get-MgApplication `
                -Filter "identifierUris/any(uri:uri eq '$escapedIdentifier')" `
                -Property Id,AppId,DisplayName,IdentifierUris,Web `
                -ErrorAction Stop
        )

        foreach ($match in $identifierApplications) {
            $identifierMatches[$match.Id] = $match
        }
    }

    if ($identifierMatches.Count -eq 0) {
        if ($namedApplications.Count -gt 0 -or $namedServicePrincipals.Count -gt 0) {
            throw "An application or service principal named '$DisplayName' exists but does not use the requested identifier URI."
        }

        return
    }

    if ($identifierMatches.Count -ne 1) {
        throw "The requested identifier URIs matched $($identifierMatches.Count) applications. Refusing to select one automatically."
    }

    $app = @($identifierMatches.Values)[0]
    if ($app.DisplayName -ne $DisplayName) {
        throw "Identifier URI belongs to '$($app.DisplayName)', not '$DisplayName'."
    }

    $conflictingApplications = @($namedApplications | Where-Object { $_.Id -ne $app.Id })
    if ($conflictingApplications.Count -gt 0) {
        throw "More than one application is named '$DisplayName'. Refusing to select one automatically."
    }

    $expectedIdentifiers = @($IdentifierUri | Sort-Object -Unique)
    $actualIdentifiers = @($app.IdentifierUris | Sort-Object -Unique)
    if (@(Compare-Object -ReferenceObject $expectedIdentifiers -DifferenceObject $actualIdentifiers).Count -gt 0) {
        throw "Existing application '$DisplayName' does not have the same identifier URI configuration."
    }

    $expectedReplyUrls = @($ReplyUrl | Sort-Object -Unique)
    $actualReplyUrls = @($app.Web.RedirectUris | Sort-Object -Unique)
    if (@(Compare-Object -ReferenceObject $expectedReplyUrls -DifferenceObject $actualReplyUrls).Count -gt 0) {
        throw "Existing application '$DisplayName' does not have the same reply URL configuration."
    }

    $escapedAppId = $app.AppId.Replace("'", "''")
    $servicePrincipals = @(
        Get-MgServicePrincipal `
            -Filter "appId eq '$escapedAppId'" `
            -Property Id,AppId,DisplayName,PreferredSingleSignOnMode,AppRoleAssignmentRequired,LoginUrl,LogoutUrl,SamlSingleSignOnSettings,KeyCredentials,PreferredTokenSigningKeyThumbprint,AppRoles `
            -ErrorAction Stop
    )

    if ($servicePrincipals.Count -ne 1) {
        throw "Expected one service principal for app ID '$($app.AppId)', but found $($servicePrincipals.Count)."
    }

    $sp = $servicePrincipals[0]
    if ($sp.DisplayName -ne $DisplayName) {
        throw "The service principal for '$DisplayName' is named '$($sp.DisplayName)' and cannot be reused as an exact match."
    }

    $conflictingServicePrincipals = @($namedServicePrincipals | Where-Object { $_.Id -ne $sp.Id })
    if ($conflictingServicePrincipals.Count -gt 0) {
        throw "More than one service principal is named '$DisplayName'. Refusing to select one automatically."
    }

    if ($sp.PreferredSingleSignOnMode -ne 'saml') {
        throw "Existing application '$DisplayName' is not configured for SAML single sign-on."
    }

    [pscustomobject]@{
        Application = $app
        ServicePrincipal = $sp
    }
}

function Get-MgSamlSigningCertificate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]$ServicePrincipalId
    )

    $keyData = Invoke-MgGraphRequest `
        -Method GET `
        -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$ServicePrincipalId`?`$select=keyCredentials,preferredTokenSigningKeyThumbprint" `
        -ErrorAction Stop
    $candidates = @(
        $keyData.keyCredentials |
            Where-Object { $_.usage -eq 'Verify' -and $null -ne $_.key }
    )

    if ($candidates.Count -eq 0) {
        return
    }

    $preferredThumbprint = $keyData.preferredTokenSigningKeyThumbprint
    $selected = $null

    foreach ($candidate in $candidates) {
        $customIdentifier = $candidate.customKeyIdentifier
        $identifierBytes = if ($customIdentifier -is [byte[]]) {
            $customIdentifier
        }
        elseif ($customIdentifier) {
            [Convert]::FromBase64String([string]$customIdentifier)
        }
        else {
            $null
        }
        $hexThumbprint = if ($identifierBytes) {
            [BitConverter]::ToString($identifierBytes).Replace('-', '')
        }

        if ($preferredThumbprint -and $hexThumbprint -eq $preferredThumbprint) {
            $selected = [pscustomobject]@{
                Key = $candidate.key
                KeyId = $candidate.keyId
                Thumbprint = $hexThumbprint
                EndDateTime = $candidate.endDateTime
            }
            break
        }
    }

    if (-not $selected -and $candidates.Count -eq 1) {
        $candidate = $candidates[0]
        $customIdentifier = $candidate.customKeyIdentifier
        $identifierBytes = if ($customIdentifier -is [byte[]]) {
            $customIdentifier
        }
        elseif ($customIdentifier) {
            [Convert]::FromBase64String([string]$customIdentifier)
        }
        $selected = [pscustomobject]@{
            Key = $candidate.key
            KeyId = $candidate.keyId
            Thumbprint = if ($identifierBytes) { [BitConverter]::ToString($identifierBytes).Replace('-', '') }
            EndDateTime = $candidate.endDateTime
        }
    }

    if (-not $selected) {
        throw "Multiple public signing certificates exist on service principal '$ServicePrincipalId', but none matches its preferred thumbprint."
    }

    $selected
}

function New-MgSamlApp {
    [CmdletBinding(SupportsShouldProcess)]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DisplayName,

        [Parameter(
            Mandatory,
            HelpMessage = 'The SAML Entity ID / Identifier that uniquely identifies the application.'
        )]
        [Alias('IdentifierID', 'IdentifierUris', 'IdentifierEntityId', 'EntityId', 'Audience')]
        [ValidateScript({ $_.Count -gt 0 -and @($_ | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -eq 0 })]
        [string[]]$IdentifierUri,

        [Parameter(
            Mandatory,
            HelpMessage = 'The Assertion Consumer Service URLs where the application receives SAML responses.'
        )]
        [Alias('ReplyURLs', 'RedirectUris', 'AcsUrl', 'AssertionConsumerServiceUrl')]
        [ValidateScript({ $_.Count -gt 0 -and @($_ | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -eq 0 })]
        [string[]]$ReplyUrl,

        [Alias('LoginUrl')]
        [string]$SignOnUrl,

        [string]$RelayState,

        [string]$LogoutUrl,

        [hashtable[]]$SamlClaims = @(),

        [hashtable[]]$ValueClaims = @(),

        # Complete customClaimsPolicy claim objects can be supplied for conditions or transformations.
        [object[]]$CustomClaims = @(),

        [bool]$IncludeStandardClaims = $true,

        [ValidatePattern('^[^.]+\.[^.]+$')]
        [string]$NameIdSourceAttribute = 'user.mail',

        [ValidateSet('emailAddress', 'persistent', 'transient', 'unspecified', 'default', 'windowsDomainQualifiedName')]
        [string]$NameIdFormat = 'emailAddress',

        [switch]$RequireAssignment,

        [switch]$CreateSigningCertificate,

        [switch]$SetCertificateAsPreferred,

        [ValidateRange(1, 36)]
        [int]$CertificateMonthsValid = 36,

        [ValidateRange(1, 600)]
        [int]$GraphWaitTimeoutSeconds = 120
    )

    if ($SetCertificateAsPreferred -and -not $CreateSigningCertificate) {
        throw 'SetCertificateAsPreferred requires CreateSigningCertificate.'
    }

    if (-not (Get-MgContext -ErrorAction SilentlyContinue)) {
        throw 'No Microsoft Graph connection is available. Run Connect-MgGraph with the required permissions first.'
    }

    $existing = Get-MgSamlExistingApp `
        -DisplayName $DisplayName `
        -IdentifierUri $IdentifierUri `
        -ReplyUrl $ReplyUrl

    if ($existing) {
        $app = $existing.Application
        $sp = $existing.ServicePrincipal
        $certificate = $null

        if ($CreateSigningCertificate) {
            $certificate = Get-MgSamlSigningCertificate -ServicePrincipalId $sp.Id

            if (-not $certificate) {
                if (-not $PSCmdlet.ShouldProcess($DisplayName, 'Create the missing SAML signing certificate')) {
                    return
                }

                $certificate = Add-MgServicePrincipalTokenSigningCertificate `
                    -ServicePrincipalId $sp.Id `
                    -DisplayName "CN=$DisplayName" `
                    -EndDateTime ((Get-Date).ToUniversalTime().AddMonths($CertificateMonthsValid)) `
                    -ErrorAction Stop
            }

            if ($SetCertificateAsPreferred -and $certificate.Thumbprint -and $sp.PreferredTokenSigningKeyThumbprint -ne $certificate.Thumbprint) {
                if ($PSCmdlet.ShouldProcess($DisplayName, 'Set the existing SAML signing certificate as preferred')) {
                    Update-MgServicePrincipal `
                        -ServicePrincipalId $sp.Id `
                        -BodyParameter @{ PreferredTokenSigningKeyThumbprint = $certificate.Thumbprint } `
                        -ErrorAction Stop
                    $sp = Get-MgServicePrincipal `
                        -ServicePrincipalId $sp.Id `
                        -Property Id,AppId,DisplayName,PreferredSingleSignOnMode,AppRoleAssignmentRequired,LoginUrl,LogoutUrl,SamlSingleSignOnSettings,KeyCredentials,PreferredTokenSigningKeyThumbprint,AppRoles `
                        -ErrorAction Stop
                }
            }
        }

        $claimsPolicy = Invoke-MgGraphRequest `
            -Method GET `
            -Uri "https://graph.microsoft.com/beta/servicePrincipals/$($sp.Id)/claimsPolicy" `
            -ErrorAction Stop

        return [pscustomobject]@{
            DisplayName = $sp.DisplayName
            AppId = $sp.AppId
            ApplicationObjectId = $app.Id
            ServicePrincipalId = $sp.Id
            PreferredSingleSignOnMode = $sp.PreferredSingleSignOnMode
            IdentifierUri = $app.IdentifierUris
            ReplyUrl = $app.Web.RedirectUris
            SignOnUrl = $sp.LoginUrl
            RelayState = $sp.SamlSingleSignOnSettings.RelayState
            LogoutUrl = $sp.LogoutUrl
            RequireAssignment = $sp.AppRoleAssignmentRequired
            Certificate = $certificate
            PreferredTokenSigningKeyThumbprint = $sp.PreferredTokenSigningKeyThumbprint
            FederationMetadataUrl = "https://login.microsoftonline.com/$((Get-MgContext).TenantId)/federationmetadata/2007-06/federationmetadata.xml?appid=$($sp.AppId)"
            ClaimsPolicy = $claimsPolicy
            Application = $app
            ServicePrincipal = $sp
            ReusedExisting = $true
        }
    }

    if (-not $PSCmdlet.ShouldProcess($DisplayName, 'Create and configure a SAML enterprise application')) {
        return
    }

    $templateId = '8adf8e6e-67b2-4cf2-a259-e3dc5476c621'
    $instantiatedApp = Invoke-MgInstantiateApplicationTemplate `
        -ApplicationTemplateId $templateId `
        -DisplayName $DisplayName `
        -ErrorAction Stop

    $applicationObjectId = $instantiatedApp.Application.Id
    $servicePrincipalId = $instantiatedApp.ServicePrincipal.Id
    $appId = $instantiatedApp.Application.AppId

    if (-not $applicationObjectId -or -not $servicePrincipalId -or -not $appId) {
        throw 'Template instantiation completed but did not return the expected application and service principal identifiers.'
    }

    try {
        $deadline = (Get-Date).AddSeconds($GraphWaitTimeoutSeconds)
        $lastGraphError = $null
        $sp = $null
        $app = $null

        do {
            try {
                $sp = Get-MgServicePrincipal `
                    -ServicePrincipalId $servicePrincipalId `
                    -Property Id,AppId,DisplayName,PreferredSingleSignOnMode,AppRoleAssignmentRequired,LoginUrl,LogoutUrl,SamlSingleSignOnSettings,KeyCredentials,PreferredTokenSigningKeyThumbprint,AppRoles `
                    -ErrorAction Stop
                $app = Get-MgApplication `
                    -ApplicationId $applicationObjectId `
                    -Property Id,AppId,DisplayName,IdentifierUris,Web `
                    -ErrorAction Stop
            }
            catch {
                $lastGraphError = $_
                $sp = $null
                $app = $null
            }

            if (-not ($sp -and $app)) {
                Start-Sleep -Seconds 3
            }
        } until (($sp -and $app) -or ((Get-Date) -ge $deadline))

        if (-not ($sp -and $app)) {
            throw "The new application was not readable before the Graph timeout. Last error: $($lastGraphError.Exception.Message)"
        }

        $spBody = @{
            PreferredSingleSignOnMode = 'saml'
            AppRoleAssignmentRequired = [bool]$RequireAssignment
        }

        if ($PSBoundParameters.ContainsKey('SignOnUrl')) {
            $spBody.LoginUrl = $SignOnUrl
        }

        if ($PSBoundParameters.ContainsKey('LogoutUrl')) {
            $spBody.LogoutUrl = $LogoutUrl
        }

        if ($PSBoundParameters.ContainsKey('RelayState')) {
            $spBody.SamlSingleSignOnSettings = @{ RelayState = $RelayState }
        }

        Update-MgServicePrincipal `
            -ServicePrincipalId $servicePrincipalId `
            -BodyParameter $spBody `
            -ErrorAction Stop

        $webConfig = @{ RedirectUris = @($ReplyUrl) }

        if ($PSBoundParameters.ContainsKey('SignOnUrl')) {
            $webConfig.HomePageUrl = $SignOnUrl
        }
        elseif ($app.Web.HomePageUrl) {
            $webConfig.HomePageUrl = $app.Web.HomePageUrl
        }

        if ($PSBoundParameters.ContainsKey('LogoutUrl')) {
            $webConfig.LogoutUrl = $LogoutUrl
        }
        elseif ($app.Web.LogoutUrl) {
            $webConfig.LogoutUrl = $app.Web.LogoutUrl
        }

        if ($app.Web.ImplicitGrantSettings) {
            $webConfig.ImplicitGrantSettings = $app.Web.ImplicitGrantSettings
        }

        Update-MgApplication `
            -ApplicationId $applicationObjectId `
            -BodyParameter @{
                IdentifierUris = @($IdentifierUri)
                Web = $webConfig
            } `
            -ErrorAction Stop

        $certificate = $null

        if ($CreateSigningCertificate) {
            $certificate = Add-MgServicePrincipalTokenSigningCertificate `
                -ServicePrincipalId $servicePrincipalId `
                -DisplayName "CN=$DisplayName" `
                -EndDateTime ((Get-Date).ToUniversalTime().AddMonths($CertificateMonthsValid)) `
                -ErrorAction Stop

            if ($SetCertificateAsPreferred) {
                if (-not $certificate.Thumbprint) {
                    throw 'The signing certificate was created without a thumbprint and could not be made preferred.'
                }

                Update-MgServicePrincipal `
                    -ServicePrincipalId $servicePrincipalId `
                    -BodyParameter @{ PreferredTokenSigningKeyThumbprint = $certificate.Thumbprint } `
                    -ErrorAction Stop
            }
        }

        $additionalClaims = @(
            foreach ($claim in @($SamlClaims)) {
                if ($null -ne $claim) {
                    ConvertTo-MgSamlSourcedClaim @claim
                }
            }
            foreach ($claim in @($ValueClaims)) {
                if ($null -ne $claim) {
                    ConvertTo-MgSamlValueClaim @claim
                }
            }
            foreach ($claim in @($CustomClaims)) {
                if ($null -ne $claim) {
                    $claim
                }
            }
        )

        $claimsPolicy = Set-MgSamlClaimsPolicy `
            -ServicePrincipalId $servicePrincipalId `
            -IncludeStandardClaims $IncludeStandardClaims `
            -NameIdSourceAttribute $NameIdSourceAttribute `
            -NameIdFormat $NameIdFormat `
            -AdditionalClaims $additionalClaims `
            -Confirm:$false

        $updatedSp = Get-MgServicePrincipal `
            -ServicePrincipalId $servicePrincipalId `
            -Property Id,AppId,DisplayName,PreferredSingleSignOnMode,AppRoleAssignmentRequired,LoginUrl,LogoutUrl,SamlSingleSignOnSettings,KeyCredentials,PreferredTokenSigningKeyThumbprint,AppRoles `
            -ErrorAction Stop
        $updatedApp = Get-MgApplication `
            -ApplicationId $applicationObjectId `
            -Property Id,AppId,DisplayName,IdentifierUris,Web `
            -ErrorAction Stop

        if ($updatedSp.PreferredSingleSignOnMode -ne 'saml') {
            throw "The service principal did not persist PreferredSingleSignOnMode = 'saml'."
        }

        [pscustomobject]@{
            DisplayName = $updatedSp.DisplayName
            AppId = $updatedSp.AppId
            ApplicationObjectId = $updatedApp.Id
            ServicePrincipalId = $updatedSp.Id
            PreferredSingleSignOnMode = $updatedSp.PreferredSingleSignOnMode
            IdentifierUri = $updatedApp.IdentifierUris
            ReplyUrl = $updatedApp.Web.RedirectUris
            SignOnUrl = $updatedSp.LoginUrl
            RelayState = $updatedSp.SamlSingleSignOnSettings.RelayState
            LogoutUrl = $updatedSp.LogoutUrl
            RequireAssignment = $updatedSp.AppRoleAssignmentRequired
            Certificate = $certificate
            PreferredTokenSigningKeyThumbprint = $updatedSp.PreferredTokenSigningKeyThumbprint
            FederationMetadataUrl = "https://login.microsoftonline.com/$((Get-MgContext).TenantId)/federationmetadata/2007-06/federationmetadata.xml?appid=$($updatedSp.AppId)"
            ClaimsPolicy = $claimsPolicy
            Application = $updatedApp
            ServicePrincipal = $updatedSp
            ReusedExisting = $false
        }
    }
    catch {
        $message = "SAML application configuration failed after template instantiation. Application object ID: $applicationObjectId; service principal ID: $servicePrincipalId; app ID: $appId. The partially created resources were not deleted. $($_.Exception.Message)"
        throw [System.InvalidOperationException]::new($message, $_.Exception)
    }
}

function ConvertTo-PemCertificate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Base64Certificate
    )

    if ($Base64Certificate -is [byte[]]) {
        $cleanBase64 = [Convert]::ToBase64String($Base64Certificate)
    }
    elseif ($Base64Certificate -is [string]) {
        $cleanBase64 = $Base64Certificate -replace '\s', ''
    }
    else {
        throw "Base64Certificate must be a Base64 string or byte array, not '$($Base64Certificate.GetType().FullName)'."
    }

    if ([string]::IsNullOrWhiteSpace($cleanBase64)) {
        throw 'Base64Certificate cannot be empty.'
    }

    [Convert]::FromBase64String($cleanBase64) | Out-Null

    $lines = for ($i = 0; $i -lt $cleanBase64.Length; $i += 64) {
        $length = [Math]::Min(64, $cleanBase64.Length - $i)
        $cleanBase64.Substring($i, $length)
    }

    @(
        '-----BEGIN CERTIFICATE-----'
        $lines
        '-----END CERTIFICATE-----'
    ) -join [Environment]::NewLine
}

function Save-MgAppCertificate {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [object]$Certificate,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DisplayName,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OutPath
    )

    if (-not $Certificate.Key) {
        throw 'The certificate object does not contain a public certificate in its Key property.'
    }

    $outputDirectory = Get-Item -LiteralPath $OutPath -ErrorAction Stop
    if (-not $outputDirectory.PSIsContainer) {
        throw "OutPath '$OutPath' is not a directory."
    }

    $invalidPattern = '[{0}]' -f [Regex]::Escape((-join [IO.Path]::GetInvalidFileNameChars()))
    $safeDisplayName = $DisplayName -replace $invalidPattern, '_'
    $certificatePath = Join-Path $outputDirectory.FullName "$safeDisplayName.cer"
    $pem = (ConvertTo-PemCertificate -Base64Certificate $Certificate.Key) + [Environment]::NewLine
    [IO.File]::WriteAllText($certificatePath, $pem, [Text.UTF8Encoding]::new($false))

    Get-Item -LiteralPath $certificatePath
}

function Save-MgAppFederationXml {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$AppId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DisplayName,

        [string]$TenantId = (Get-MgContext).TenantId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OutPath
    )

    if (-not $TenantId) {
        throw 'TenantId was not supplied and could not be read from the Microsoft Graph context.'
    }

    $outputDirectory = Get-Item -LiteralPath $OutPath -ErrorAction Stop
    if (-not $outputDirectory.PSIsContainer) {
        throw "OutPath '$OutPath' is not a directory."
    }

    $encodedTenantId = [Uri]::EscapeDataString($TenantId)
    $encodedAppId = [Uri]::EscapeDataString($AppId)
    $uri = "https://login.microsoftonline.com/$encodedTenantId/federationmetadata/2007-06/federationmetadata.xml?appid=$encodedAppId"
    $invalidPattern = '[{0}]' -f [Regex]::Escape((-join [IO.Path]::GetInvalidFileNameChars()))
    $safeDisplayName = $DisplayName -replace $invalidPattern, '_'
    $metadataPath = Join-Path $outputDirectory.FullName "$safeDisplayName.xml"
    Invoke-WebRequest -Method GET -Uri $uri -OutFile $metadataPath -ErrorAction Stop

    $metadataFile = Get-Item -LiteralPath $metadataPath -ErrorAction Stop
    if ($metadataFile.Length -eq 0) {
        throw "Federation metadata download created an empty file at '$metadataPath'."
    }

    $metadataFile
}

function Compress-MgAppArtifact {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DisplayName,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [IO.FileInfo]$CertificateFile,

        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [IO.FileInfo]$MetadataFile,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$OutPath
    )

    $outputDirectory = Get-Item -LiteralPath $OutPath -ErrorAction Stop
    if (-not $outputDirectory.PSIsContainer) {
        throw "OutPath '$OutPath' is not a directory."
    }

    foreach ($artifact in @($CertificateFile, $MetadataFile)) {
        if (-not $artifact.Exists) {
            throw "Artifact '$($artifact.FullName)' does not exist and cannot be archived."
        }
    }

    $invalidPattern = '[{0}]' -f [Regex]::Escape((-join [IO.Path]::GetInvalidFileNameChars()))
    $safeDisplayName = $DisplayName -replace $invalidPattern, '_'
    $timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmssfffZ')
    $archivePath = Join-Path $outputDirectory.FullName "$safeDisplayName-$timestamp.zip"

    Compress-Archive `
        -LiteralPath $CertificateFile.FullName, $MetadataFile.FullName `
        -DestinationPath $archivePath `
        -CompressionLevel Optimal `
        -ErrorAction Stop

    Get-Item -LiteralPath $archivePath -ErrorAction Stop
}
