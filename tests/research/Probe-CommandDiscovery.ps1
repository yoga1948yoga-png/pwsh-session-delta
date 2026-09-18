#Requires -Version 7.0
<#
Design research, NOT the product collector or a substitute for Pester acceptance tests.
Run in a disposable pwsh -NoProfile process. Uses synthetic fixtures only.
The unsafe exact-name controls intentionally may import OUR fixture module.
#>
$ErrorActionPreference = 'Stop'
if (-not $IsWindows) { throw 'This probe requires Windows and PowerShell 7.' }
$root = [IO.Path]::Combine([IO.Path]::GetTempPath(), 'pwsh-delta-probe-' + [guid]::NewGuid())
$oldPath = $env:PATH
$oldModulePath = $env:PSModulePath
$results = [Collections.Generic.List[object]]::new()
function Assert-Probe([string] $Name, [bool] $Passed) {
    $results.Add([pscustomobject]@{ Check = $Name; Passed = $Passed })
    if (-not $Passed) { throw "Probe failed: $Name" }
}
try {
    [void][IO.Directory]::CreateDirectory($root)
    $moduleDir = [IO.Path]::Combine($root, 'DeltaAutoloadFixture')
    [void][IO.Directory]::CreateDirectory($moduleDir)
    [IO.File]::WriteAllText([IO.Path]::Combine($moduleDir, 'DeltaAutoloadFixture.psd1'), @'
@{ RootModule='DeltaAutoloadFixture.psm1'; ModuleVersion='0.0.1'; FunctionsToExport=@('Get-DeltaAutoloadSentinel'); CmdletsToExport=@(); AliasesToExport=@() }
'@)
    [IO.File]::WriteAllText([IO.Path]::Combine($moduleDir, 'DeltaAutoloadFixture.psm1'), @'
[IO.File]::WriteAllText([IO.Path]::Combine($PSScriptRoot, 'import.marker'), 'imported')
function Get-DeltaAutoloadSentinel { throw 'Target must never run.' }
Export-ModuleMember -Function Get-DeltaAutoloadSentinel
'@)
    $env:PSModulePath = $root
    $PSModuleAutoLoadingPreference = 'All'
    $marker = [IO.Path]::Combine($moduleDir, 'import.marker')
    $null = Microsoft.PowerShell.Core\Get-Command -Name 'Get-DeltaAutoloadSentinel*'
    Assert-Probe 'Wildcard alone does not import fixture' (-not [IO.File]::Exists($marker))
    $visible = @(Microsoft.PowerShell.Core\Get-Command -Name 'Get-DeltaAutoloadSentinel*' -ListImported -All)
    Assert-Probe 'ListImported excludes unloaded fixture' ($visible.Count -eq 0 -and -not [IO.File]::Exists($marker))
    $null = Microsoft.PowerShell.Core\Get-Command -Name 'Get-DeltaAutoloadSentinel'
    Assert-Probe 'Unsafe exact-name positive control DOES import fixture' ([IO.File]::Exists($marker))
    Microsoft.PowerShell.Core\Remove-Module DeltaAutoloadFixture
    [IO.File]::Delete($marker)

    $probeModulePath = [IO.Path]::Combine($root, 'DeltaDiscoveryProbe.psm1')
    [IO.File]::WriteAllText($probeModulePath, @'
function Invoke-DeltaDiscoveryProbe {
    param([string] $Name, [switch] $Exact)
    $PSModuleAutoLoadingPreference = 'None'
    $pattern = [System.Management.Automation.WildcardPattern]::Escape($Name) + '*'
    if ($Exact) { $pattern = $Name }
    foreach ($item in @(Microsoft.PowerShell.Core\Get-Command -Name $pattern -ListImported -All -ErrorAction Stop)) {
        if ($Exact -or [string]::Equals($item.Name, $Name, [StringComparison]::OrdinalIgnoreCase)) {
            # Allowlist only: never emit a raw CommandInfo or read parameter metadata.
            [pscustomobject]@{ Name = $item.Name; Kind = [string]$item.CommandType }
        }
    }
}
Export-ModuleMember -Function Invoke-DeltaDiscoveryProbe
'@)
    Microsoft.PowerShell.Core\Import-Module $probeModulePath
    $absent = @(Invoke-DeltaDiscoveryProbe 'Get-DeltaAutoloadSentinel')
    Assert-Probe 'Guarded module query does not import fixture' ($absent.Count -eq 0 -and -not [IO.File]::Exists($marker))
    $exactAbsent = $false
    try { $exactAbsent = @(Invoke-DeltaDiscoveryProbe 'Get-DeltaAutoloadSentinel' -Exact).Count -eq 0 }
    catch [System.Management.Automation.CommandNotFoundException] { $exactAbsent = $true }
    $results.Add([pscustomobject]@{ Check = "REJECTED exact + ListImported + local None: imported=$([IO.File]::Exists($marker))"; Passed = $null })
    Microsoft.PowerShell.Core\Remove-Module DeltaAutoloadFixture -ErrorAction SilentlyContinue
    if ([IO.File]::Exists($marker)) { [IO.File]::Delete($marker) }
    Assert-Probe 'Caller preference unchanged' ($PSModuleAutoLoadingPreference -eq 'All')
    function Get-DeltaLocalFunction { throw 'Function must never run.' }
    Set-Alias -Name deltaLocalAlias -Value Get-DeltaLocalFunction
    Assert-Probe 'Module sees caller function' (@(Invoke-DeltaDiscoveryProbe 'Get-DeltaLocalFunction').Count -eq 1)
    Assert-Probe 'Module sees caller alias' (@(Invoke-DeltaDiscoveryProbe 'deltaLocalAlias').Count -eq 1)
    Assert-Probe 'Core cmdlet remains visible' (@(Invoke-DeltaDiscoveryProbe 'Get-Command').Count -eq 1)

    $bin = [IO.Path]::Combine($root, 'space 中文')
    [void][IO.Directory]::CreateDirectory($bin)
    [IO.File]::WriteAllText([IO.Path]::Combine($bin, 'delta-script.ps1'), @'
dynamicparam { [IO.File]::WriteAllText([IO.Path]::Combine($PSScriptRoot, 'dynamic.marker'), 'executed') }
end { [IO.File]::WriteAllText([IO.Path]::Combine($PSScriptRoot, 'run.marker'), 'executed') }
'@)
    $env:PATH = $bin
    $scriptFound = @(Invoke-DeltaDiscoveryProbe 'delta-script.ps1')
    Assert-Probe 'Script in space and Unicode PATH discovered' ($scriptFound.Count -eq 1)
    Assert-Probe 'Script body and dynamicparam not executed' (-not [IO.File]::Exists([IO.Path]::Combine($bin, 'run.marker')) -and -not [IO.File]::Exists([IO.Path]::Combine($bin, 'dynamic.marker')))
    $null = Invoke-DeltaDiscoveryProbe 'delta-script.ps1' -Exact
    Assert-Probe 'Guarded exact script query also does not execute' (-not [IO.File]::Exists([IO.Path]::Combine($bin, 'run.marker')) -and -not [IO.File]::Exists([IO.Path]::Combine($bin, 'dynamic.marker')))
    [IO.File]::Copy([IO.Path]::Combine($PSHOME, 'pwsh.exe'), [IO.Path]::Combine($bin, 'delta-native.exe'))
    $native = @(Invoke-DeltaDiscoveryProbe 'delta-native' -Exact)
    Assert-Probe 'Guarded exact query resolves extensionless executable name' ($native.Count -eq 1 -and $native[0].Name -eq 'delta-native.exe')
    Assert-Probe 'Missing name has no observed candidate' (@(Invoke-DeltaDiscoveryProbe 'delta-not-present').Count -eq 0)
    $results
    [pscustomobject]@{ PowerShell = [string]$PSVersionTable.PSVersion; Platform = $PSVersionTable.Platform; Check = 'Research only; not product acceptance' }
}
finally {
    $env:PATH = $oldPath
    $env:PSModulePath = $oldModulePath
    Microsoft.PowerShell.Core\Remove-Module DeltaDiscoveryProbe, DeltaAutoloadFixture -ErrorAction SilentlyContinue
    # Delete only the unique fixture directory after verifying its resolved boundary.
    $resolved = [IO.Path]::GetFullPath($root)
    $tempBoundary = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($tempBoundary, [StringComparison]::OrdinalIgnoreCase) -or
        -not [IO.Path]::GetFileName($resolved).StartsWith('pwsh-delta-probe-')) {
        throw 'Refusing fixture cleanup outside the expected temporary directory.'
    }
    if ([IO.Directory]::Exists($resolved)) { [IO.Directory]::Delete($resolved, $true) }
}
