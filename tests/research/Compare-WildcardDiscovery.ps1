#Requires -Version 7.0
# Research only. Run in a disposable pwsh -NoProfile process, never dot-source.
# Setup imports ONLY a synthetic loaded fixture. No measured query imports or invokes targets.
param([string] $ResultPath, [string] $ExpectedVersion='7.6.5')
$ErrorActionPreference = 'Stop'
if (-not $IsWindows -or $PSVersionTable.PSVersion.ToString() -cne $ExpectedVersion) { throw 'Research runtime does not match ExpectedVersion' }
$root = [IO.Path]::Combine([IO.Path]::GetTempPath(), 'pwsh-delta-stage15-' + [guid]::NewGuid())
$oldPath = $env:PATH; $oldModulePath = $env:PSModulePath; $oldPathExt = $env:PATHEXT
$rows = [Collections.Generic.List[object]]::new()
$checks = [Collections.Generic.List[string]]::new()
function Assert-Research([bool] $Condition, [string] $Label) {
    if (-not $Condition) { throw "Research assertion failed: $Label" }
    $checks.Add($Label)
}
function Get-LoadedIdentity {
    (@((Microsoft.PowerShell.Core\Get-Module -All).ForEach({ $_.Name + ':' + $_.Version }) | Sort-Object)) -join '|'
}
function Get-MarkerCount { @([IO.Directory]::GetFiles($root, '*.marker', [IO.SearchOption]::AllDirectories)).Count }
function Get-MarkerBytes {
    $total = 0L
    foreach ($file in [IO.Directory]::GetFiles($root, '*.marker', [IO.SearchOption]::AllDirectories)) { $total += [IO.FileInfo]::new($file).Length }
    $total
}
function Measure-Discovery([string] $Name, [bool] $ListImported, [string] $Order, [string] $ExtOrder) {
    $pattern = [System.Management.Automation.WildcardPattern]::Escape($Name) + '*'
    $before = Get-LoadedIdentity
    $markers = Get-MarkerCount
    $markerBytes = Get-MarkerBytes
    if ($ListImported) {
        $found = @(Microsoft.PowerShell.Core\Get-Command -Name $pattern -All -ListImported -ErrorAction Stop)
    } else {
        $found = @(Microsoft.PowerShell.Core\Get-Command -Name $pattern -All -ErrorAction Stop)
    }
    $raw = [Collections.Generic.List[object]]::new()
    $accepted = [Collections.Generic.List[object]]::new()
    foreach ($command in $found) {
        $kind = [string]$command.CommandType
        $pathLabel = $null
        if ($kind -in 'Application','ExternalScript') { $pathLabel = $command.Path.Replace($root, '<FIXTURE>') }
        $record = [pscustomobject]@{ Name=$command.Name; Type=$kind; Path=$pathLabel; Module=$command.ModuleName }
        $raw.Add($record)
        $match = [string]::Equals($command.Name, $Name, [StringComparison]::OrdinalIgnoreCase)
        # Name association only, never an execution winner.
        if (-not $match -and $kind -in 'Application','ExternalScript' -and -not [IO.Path]::HasExtension($Name)) {
            foreach ($extension in @($env:PATHEXT.Split(';')) + @('.ps1')) {
                if ($extension -and [string]::Equals($command.Name, $Name + $extension, [StringComparison]::OrdinalIgnoreCase)) { $match = $true }
            }
        }
        if ($match) { $accepted.Add($record) }
    }
    Assert-Research ($before -ceq (Get-LoadedIdentity)) "Unchanged modules: $Name / $ListImported / $Order / $ExtOrder"
    Assert-Research ($markers -eq (Get-MarkerCount) -and $markerBytes -eq (Get-MarkerBytes)) "No new or appended code markers: $Name / $ListImported / $Order / $ExtOrder"
    $rows.Add([pscustomobject]@{ Name=$Name; Pattern=$pattern; ListImported=$ListImported; PathOrder=$Order; PathExtOrder=$ExtOrder; Raw=@($raw); Accepted=@($accepted); ModuleSetChanged=$false; NewCodeMarkers=0; MarkerBytesChanged=$false })
}
try {
    [void][IO.Directory]::CreateDirectory($root)
    foreach ($flavor in 'Loaded','Unloaded') {
        $dir = [IO.Path]::Combine($root, 'Delta' + $flavor)
        [void][IO.Directory]::CreateDirectory($dir)
        $source = @'
using System.IO;
using System.Management.Automation;
namespace DeltaFLAVOR {
    public class Initializer : IModuleAssemblyInitializer {
        public void OnImport() { File.AppendAllText(Path.Combine(Path.GetDirectoryName(typeof(Initializer).Assembly.Location), "import.marker"), "imported\n"); }
    }
    [Cmdlet("Get", "DeltaFLAVORProbe")]
    public class Probe : PSCmdlet {
        public Probe() { File.WriteAllText(Path.Combine(Path.GetDirectoryName(typeof(Probe).Assembly.Location), "constructor.marker"), "constructed"); }
        protected override void ProcessRecord() { File.WriteAllText(Path.Combine(Path.GetDirectoryName(typeof(Probe).Assembly.Location), "execute.marker"), "executed"); }
    }
}
'@.Replace('FLAVOR', $flavor)
        Add-Type -TypeDefinition $source -OutputAssembly ([IO.Path]::Combine($dir, 'Delta' + $flavor + '.dll'))
        $manifest = "@{ RootModule='Delta$flavor.dll'; ModuleVersion='0.0.1'; CmdletsToExport=@('Get-Delta${flavor}Probe'); FunctionsToExport=@(); AliasesToExport=@(); VariablesToExport=@() }"
        [IO.File]::WriteAllText([IO.Path]::Combine($dir, 'Delta' + $flavor + '.psd1'), $manifest)
    }
    # Setup only: a loaded-module test needs a deliberately loaded fixture.
    Microsoft.PowerShell.Core\Import-Module ([IO.Path]::Combine($root, 'DeltaLoaded', 'DeltaLoaded.psd1'))
    Assert-Research ([IO.File]::Exists([IO.Path]::Combine($root, 'DeltaLoaded', 'import.marker'))) 'Setup imported loaded binary fixture'
    Assert-Research (-not [IO.File]::Exists([IO.Path]::Combine($root, 'DeltaUnloaded', 'import.marker'))) 'Unloaded fixture starts unimported'
    $env:PSModulePath = $root
    $PSModuleAutoLoadingPreference = 'All'
    $a = [IO.Path]::Combine($root, 'A space 中文'); $b = [IO.Path]::Combine($root, 'B space 中文')
    foreach ($dir in $a,$b) {
        [void][IO.Directory]::CreateDirectory($dir)
        foreach ($name in 'delta-native.exe','delta-mixed.exe','delta[box].exe') {
            [IO.File]::Copy([IO.Path]::Combine($PSHOME, 'pwsh.exe'), [IO.Path]::Combine($dir, $name))
        }
        foreach ($ext in '.cmd','.bat') {
            foreach ($stem in 'delta-mixed','delta-batch') {
                [IO.File]::WriteAllText([IO.Path]::Combine($dir, $stem + $ext), '@echo executed>"%~dp0batch.marker"')
            }
        }
        [IO.File]::WriteAllText([IO.Path]::Combine($dir, 'delta-mixed.ps1'), @'
dynamicparam { [IO.File]::WriteAllText([IO.Path]::Combine($PSScriptRoot, 'dynamic.marker'), 'executed') }
end { [IO.File]::WriteAllText([IO.Path]::Combine($PSScriptRoot, 'script.marker'), 'executed') }
'@)
    }
    $global:DeltaResearchMarker = [IO.Path]::Combine($root, 'function.marker')
    function Get-DeltaFunctionProbe { [IO.File]::WriteAllText($global:DeltaResearchMarker, 'executed') }
    Set-Alias -Name delta-alias -Value Get-DeltaFunctionProbe
    $literalNames = @('delta*literal','delta?literal','delta[literal','delta]literal','delta[literal]','delta`literal')
    foreach ($name in $literalNames + @('deltaZZliteral','deltaXliteral','deltal','delta[box]')) { Set-Alias -Name $name -Value Get-DeltaFunctionProbe }
    $names = @('delta-alias','Get-DeltaFunctionProbe','Get-DeltaLoadedProbe','Get-DeltaUnloadedProbe','delta-native.exe','delta-native','delta-batch.cmd','delta-batch.bat','delta-mixed.ps1','delta-mixed','delta-missing','delta[box]','delta[box].exe') + $literalNames
    foreach ($order in 'AB','BA') {
        $env:PATH = if ($order -eq 'AB') { "$a;$b" } else { "$b;$a" }
        foreach ($extOrder in 'EXE-CMD-BAT','BAT-CMD-EXE') {
            $env:PATHEXT = if ($extOrder -eq 'EXE-CMD-BAT') { '.EXE;.CMD;.BAT' } else { '.BAT;.CMD;.EXE' }
            foreach ($name in $names) {
                foreach ($listImported in $false,$true) { Measure-Discovery $name $listImported $order $extOrder }
            }
        }
    }
    foreach ($name in @('delta-alias','Get-DeltaFunctionProbe','Get-DeltaLoadedProbe','delta-native.exe','delta-batch.cmd','delta-batch.bat','delta-mixed.ps1')) {
        $pair = @($rows | Where-Object { $_.Name -ceq $name -and $_.PathOrder -eq 'AB' -and $_.PathExtOrder -eq 'EXE-CMD-BAT' })
        Assert-Research ($pair.Count -eq 2 -and $pair[0].Accepted.Count -gt 0 -and $pair[1].Accepted.Count -gt 0) "Both variants observe $name"
    }
    foreach ($name in $literalNames) {
        foreach ($row in @($rows | Where-Object { $_.Name -ceq $name })) {
            Assert-Research ($row.Accepted.Count -eq 1 -and $row.Accepted[0].Name -ceq $name) "Literal name preserved: $name / $($row.ListImported) / $($row.PathOrder) / $($row.PathExtOrder)"
        }
    }
    foreach ($left in @($rows | Where-Object { -not $_.ListImported })) {
        $right = @($rows | Where-Object { $_.ListImported -and $_.Name -ceq $left.Name -and $_.PathOrder -eq $left.PathOrder -and $_.PathExtOrder -eq $left.PathExtOrder })[0]
        if ($left.Name -eq 'Get-DeltaUnloadedProbe') {
            Assert-Research ($left.Accepted.Count -eq 1 -and $right.Accepted.Count -eq 0) 'ListImported excludes unloaded Cmdlet'
        } else {
            Assert-Research (($left.Accepted | ConvertTo-Json -Compress -Depth 4) -ceq ($right.Accepted | ConvertTo-Json -Compress -Depth 4)) "Variants agree: $($left.Name) / $($left.PathOrder) / $($left.PathExtOrder)"
        }
    }
    Assert-Research ([IO.File]::Exists([IO.Path]::Combine($a, 'delta[box].exe'))) 'Literal bracket executable exists on disk'
    foreach ($row in @($rows | Where-Object { $_.Name -eq 'delta[box].exe' })) {
        Assert-Research ($row.Accepted.Count -eq 0) 'Known limitation: escaped bracket external query misses existing file'
    }
    Assert-Research ((Get-MarkerCount) -eq 1) 'Only setup import marker exists after all queries'
    $report = [ordered]@{ Experiment='Stage 1.5 wildcard comparison'; PowerShell=$PSVersionTable.PSVersion.ToString(); Platform='Windows'; MeasuredQueries=$rows.Count; SetupImports=@('DeltaLoaded'); FinalMarkerCount=Get-MarkerCount; AssertionsPassed=$checks.Count; KnownLimitation='Escaped bracket external names miss existing files in both variants; never interpret that empty result as absence.'; NativeExecutionEvidence='No target invocation in query code; copied pwsh host only. No native process tracing/sentinel; not an independent proof of no executable launch.'; Rows=@($rows) }
    $json = $report | ConvertTo-Json -Depth 8
    if ($ResultPath) { [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath), $json, [Text.UTF8Encoding]::new($false)) }
    [pscustomobject]@{ Queries=$rows.Count; Assertions=$checks.Count; Markers=Get-MarkerCount; ResultWritten=[bool]$ResultPath }
}
finally {
    $env:PATH=$oldPath; $env:PSModulePath=$oldModulePath; $env:PATHEXT=$oldPathExt
    Microsoft.PowerShell.Core\Remove-Module DeltaLoaded,DeltaUnloaded -ErrorAction SilentlyContinue
    $resolved = [IO.Path]::GetFullPath($root)
    $boundary = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\') + '\'
    if (-not $resolved.StartsWith($boundary, [StringComparison]::OrdinalIgnoreCase) -or -not [IO.Path]::GetFileName($resolved).StartsWith('pwsh-delta-stage15-')) { throw 'Unsafe cleanup path' }
    if ([IO.Directory]::Exists($resolved)) {
        try { [IO.Directory]::Delete($resolved, $true) }
        catch { Write-Warning "Fixture DLL locked; remove after process exit: $resolved" }
    }
}
