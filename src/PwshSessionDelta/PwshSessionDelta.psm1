#Requires -Version 7.0
if (-not $IsWindows) {
    throw 'PwshSessionDelta supports Windows with PowerShell 7 only.'
}

. $PSScriptRoot/Private/Observation.ps1
. $PSScriptRoot/Private/Privacy.ps1
. $PSScriptRoot/Private/Discovery.ps1
. $PSScriptRoot/Private/Storage.ps1
. $PSScriptRoot/Export-PwshSessionSnapshot.ps1
. $PSScriptRoot/Private/SnapshotValidation.ps1
. $PSScriptRoot/Private/Comparison.ps1
. $PSScriptRoot/Compare-PwshSessionSnapshot.ps1
Export-ModuleMember -Function Export-PwshSessionSnapshot,Compare-PwshSessionSnapshot -Cmdlet @() -Variable @() -Alias @()
