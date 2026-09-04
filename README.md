# tismatic.pwsh

A collection of PowerShell utilities and quality-of-life functions for Microsoft 365, Active Directory, and systems administration.

## Requirements

- PowerShell 7.4 or newer
- Windows for functions that use Active Directory or other Windows-only APIs

Product-specific modules are optional and are only needed when calling functions that use them. Depending on the command, these can include `ActiveDirectory`, `Microsoft.Graph`, `ExchangeOnlineManagement`, `Az.Accounts`, `ImportExcel`, `PowerLiquid`, `NinjaOne`, and `GraphExtensions`.

## Import

Import the manifest directly from the repository:

```powershell
Import-Module ./tismatic.pwsh.psd1
```

After installing the repository directory in a PowerShell module path, import it by name:

```powershell
Import-Module tismatic.pwsh
```

List the commands exported by the module:

```powershell
Get-Command -Module tismatic.pwsh
```

## Layout

The root module loads the function files from the existing `tismatic.*` directories. Files under `scratch/` are retained for reference but are not imported or exported by the module.
