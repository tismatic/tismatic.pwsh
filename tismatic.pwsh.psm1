$sourceDirectories = @(
    'tismatic.ActiveDirectory'
    'tismatic.graph'
    'tismatic.graph.customapp'
    'tismatic.hybrid'
    'tismatic.ninja'
    'tismatic.powerautomate'
    'tismatic.utils'
)

foreach ($sourceDirectory in $sourceDirectories) {
    $sourcePath = Join-Path -Path $PSScriptRoot -ChildPath $sourceDirectory
    $sourceFiles = Get-ChildItem -LiteralPath $sourcePath -File -Filter '*.ps1' |
        Sort-Object -Property FullName

    foreach ($sourceFile in $sourceFiles) {
        try {
            . $sourceFile.FullName
        }
        catch {
            throw "Failed to load '$($sourceFile.FullName)': $($_.Exception.Message)"
        }
    }
}
