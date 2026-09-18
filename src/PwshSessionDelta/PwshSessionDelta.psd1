@{
    RootModule = 'PwshSessionDelta.psm1'
    ModuleVersion = '0.1.0'
    GUID = '972c22af-254f-44bc-8158-b95834daed69'
    Author = 'laweit-lxy'
    Copyright = '(c) 2026 laweit-lxy. MIT License.'
    Description = 'Local privacy-aware current-session snapshots and offline observation comparison.'
    PowerShellVersion = '7.0'
    CompatiblePSEditions = @('Core')
    RequiredModules = @('Microsoft.PowerShell.Utility')
    FunctionsToExport = @('Export-PwshSessionSnapshot','Compare-PwshSessionSnapshot')
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    # No repository exists yet: omit ProjectUri/LicenseUri rather than inventing URLs.
    PrivateData = @{ PSData = @{ Tags = @('Windows','PowerShell','Diagnostics','Privacy') } }
}
