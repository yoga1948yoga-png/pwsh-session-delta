#Requires -Version 7.0
param([string] $PesterManifest, [string] $ResultPath=(Join-Path $PSScriptRoot '../docs/stage3-test-results.json'), [switch] $AllowElevatedTestHost)
$ErrorActionPreference='Stop'
if ($PesterManifest) { Import-Module $PesterManifest -MinimumVersion 5.9.0 -Force }
else { Import-Module Pester -MinimumVersion 5.9.0 -Force }
$sourceRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../src'))
$before=@{}
foreach ($file in Get-ChildItem -LiteralPath $sourceRoot -File -Recurse) { $before[$file.FullName]=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash }
$validation=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../docs/stage3-validation.md'))
if (-not [IO.File]::Exists($validation)) { throw 'ValidationDocumentRequiredForPrivacyScan' }
$global:DeltaReleaseDenied=$null; $global:DeltaReleaseEvidence=$null; $global:DeltaReleaseRoot=$null
try {
    $paths=@('Export.Tests.ps1','Session.Tests.ps1','Compare.Tests.ps1','Release.Tests.ps1') | ForEach-Object { Join-Path $PSScriptRoot $_ }
    $result=Invoke-Pester -Path $paths -Output Detailed -PassThru
    $unchanged=$true
    foreach ($file in $before.Keys) { if ((Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -cne $before[$file]) { $unchanged=$false } }
    $cleaned=$null -ne $global:DeltaReleaseRoot -and -not [IO.Directory]::Exists($global:DeltaReleaseRoot)
    $principal=[Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    $report=[ordered]@{
        stage='3'
        runKind=$(if ($AllowElevatedTestHost) {'CI compatibility; non-admin gate not certified'} else {'Local release gate'})
        environment=[ordered]@{powerShell=$PSVersionTable.PSVersion.ToString();pester=(Get-Module Pester).Version.ToString();windows=[Runtime.InteropServices.RuntimeInformation]::OSDescription;osArchitecture=[string][Runtime.InteropServices.RuntimeInformation]::OSArchitecture;processArchitecture=[string][Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture;elevated=$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}
        total=$result.TotalCount;pass=$result.PassedCount;fail=$result.FailedCount;skip=$result.SkippedCount
        evidence=$global:DeltaReleaseEvidence;productionFilesUnchanged=$unchanged;releaseFixtureCleaned=$cleaned
        finalOutputPrivacyScan=$false
        tests=@($result.Tests | ForEach-Object { [ordered]@{name=$_.ExpandedName;result=[string]$_.Result} })
    }
    if (-not $global:DeltaReleaseDenied -or -not $global:DeltaReleaseEvidence.privacyArtifactsPassed) { throw 'PrivacyEvidenceMissing' }
    $json=ConvertTo-Json -InputObject $report -Depth 12
    foreach ($text in @($json,[IO.File]::ReadAllText($validation))) {
        foreach ($private in $global:DeltaReleaseDenied) {
            if ($private -and $text.Contains($private,[StringComparison]::OrdinalIgnoreCase)) { throw 'FinalOutputPrivacyLeak' }
        }
    }
    $report.finalOutputPrivacyScan=$true
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath),(ConvertTo-Json -InputObject $report -Depth 12),[Text.UTF8Encoding]::new($false))
    # Read-back checks the actual saved artifact, not just the pre-write serialization.
    foreach ($private in $global:DeltaReleaseDenied) {
        if ($private -and [IO.File]::ReadAllText([IO.Path]::GetFullPath($ResultPath)).Contains($private,[StringComparison]::OrdinalIgnoreCase)) { throw 'SavedResultPrivacyLeak' }
    }
    if ($result.FailedCount -or $result.SkippedCount -or $result.NotRunCount -or -not $cleaned -or -not $unchanged -or ($report.environment.elevated -and -not $AllowElevatedTestHost)) { exit 1 }
} finally {
    Remove-Variable DeltaReleaseDenied,DeltaReleaseEvidence,DeltaReleaseRoot -Scope Global -ErrorAction SilentlyContinue
}
