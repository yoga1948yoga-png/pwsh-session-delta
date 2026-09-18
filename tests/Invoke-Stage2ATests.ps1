#Requires -Version 7.0
param([string] $PesterManifest, [string] $ResultPath)
$ErrorActionPreference='Stop'
if ($PesterManifest) { Import-Module $PesterManifest -MinimumVersion 5.9.0 -Force }
else { Import-Module Pester -MinimumVersion 5.9.0 -Force }
$result=Invoke-Pester -Path (Join-Path $PSScriptRoot 'Export.Tests.ps1'),(Join-Path $PSScriptRoot 'Session.Tests.ps1') -Output Detailed -PassThru
if ($ResultPath) {
    # Save only sanitized test names/status. Never persist complete Pester/runtime objects.
    $report=[ordered]@{
        stage='2A';powerShell=$PSVersionTable.PSVersion.ToString();pester=(Get-Module Pester).Version.ToString()
        passed=$result.PassedCount;failed=$result.FailedCount;skipped=$result.SkippedCount
        tests=@($result.Tests | ForEach-Object { [ordered]@{name=$_.Name;result=[string]$_.Result} })
    }
    [IO.File]::WriteAllText([IO.Path]::GetFullPath($ResultPath),($report | ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
}
if ($result.FailedCount -gt 0) { exit 1 }
