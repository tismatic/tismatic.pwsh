# Retrieves a list of trusted Active Directory domains in the current forest.
function Get-TrustedAdDomains {
    $domainList = @()
    try {
        $forest = Get-ADForest -ErrorAction Stop
        $domainList += $forest.Domains
    }
    catch {
        try { $domainList += (Get-ADDomain -ErrorAction Stop).DNSRoot } catch {}
    }

    try { $domainList += (Get-ADTrust -Filter * | Select-Object -ExpandProperty Name) } catch {}

    $domainList | Sort-Object -Unique
}