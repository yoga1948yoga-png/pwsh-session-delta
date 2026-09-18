# Real independent process fixtures. This is a test harness, never product behavior.
BeforeAll {
    $manifest=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../src/PwshSessionDelta/PwshSessionDelta.psd1'))
    $pwsh=Join-Path $PSHOME 'pwsh.exe'
    $root=Join-Path $TestDrive 'independent sessions'
    [void][IO.Directory]::CreateDirectory($root)
    $sharedState=Join-Path $root 'state'
    function Invoke-TestSession([string] $Session, [switch] $Nested) {
        $output=Join-Path $root ($Session+'.snapshot.json')
        # Only synthetic paths are interpolated; single quotes are escaped as PowerShell literals.
        $code=@'
$ErrorActionPreference='Stop'
Import-Module 'MANIFEST'
$module=Get-Module PwshSessionDelta
& $module { $script:FixtureState='STATE'; function script:Get-DeltaStateDirectory { $script:FixtureState } }
$env:PATH='BIN'
$env:PATHEXT='.EXE;.CMD;.BAT'
SETUP
$before=@(Get-Module -All | ForEach-Object { $_.Name+':'+$_.Version }) -join '|'
$snapshot=Export-PwshSessionSnapshot -CommandName DeltaSessionAlias,DeltaSessionFunction,Get-Command -LiteralPath 'OUTPUT'
$after=@(Get-Module -All | ForEach-Object { $_.Name+':'+$_.Version }) -join '|'
if ($before -cne $after) { throw 'Unexpected module import during Export' }
'@
        $setup=if ($Session -eq 'A') { "function global:DeltaSessionFunction { throw 'PRIVATE_DEFINITION_A' }; Set-Alias -Name DeltaSessionAlias -Value DeltaSessionFunction -Scope Global; `$global:PSModuleAutoLoadingPreference='None'" } elseif ($Session -eq 'Default') { '' } else { '$global:PSModuleAutoLoadingPreference=''All''' }
        $code=$code.Replace('MANIFEST',$manifest.Replace("'","''")).Replace('STATE',$sharedState.Replace("'","''")).Replace('BIN',$root.Replace("'","''")).Replace('OUTPUT',$output.Replace("'","''")).Replace('SETUP',$setup)
        if ($Nested) { $code=$code.Replace('$snapshot=Export-', 'function Invoke-NestedCapture { $PSModuleAutoLoadingPreference=''ModuleQualified''; function DeltaSessionFunction { throw ''PRIVATE_NESTED'' }; $snapshot=Export-').Replace('$after=@(', '}; Invoke-NestedCapture; $after=@(') }
        $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
        & $pwsh -NoProfile -NonInteractive -EncodedCommand $encoded
        if ($LASTEXITCODE -ne 0) { throw 'Independent test session failed' }
        Get-Content -LiteralPath $output -Raw | ConvertFrom-Json
    }
}
Describe 'Actual current-session Export in two independent pwsh processes' {
    It 'A01 A02 A15 A17 independently captures A and B with stable keyId and different observations' {
        $a=Invoke-TestSession A
        $b=Invoke-TestSession B
        $a.privacy.keyId | Should -Be $b.privacy.keyId
        $a.commands[0].query.digest | Should -Be $b.commands[0].query.digest
        $a.commands[0].aliases.status | Should -Be 'Confirmed observation'
        $b.commands[0].aliases.status | Should -Be 'No observed value'
        $a.commands[1].functions.status | Should -Be 'Confirmed observation'
        $b.commands[1].functions.status | Should -Be 'No observed value'
        $a.commands[2].internalCandidates.value[0].type | Should -Be Cmdlet
        $a.observations.moduleAutoLoadingPreference.value.effectiveValue | Should -Be None
        $b.observations.moduleAutoLoadingPreference.value.effectiveValue | Should -Be All
    }
    It 'A17 real nested caller locals are unknown, not falsely absent' {
        $s=Invoke-TestSession Nested -Nested
        $s.commands[1].functions.reasonCode | Should -Be CallerScopeNotVisible
        $s.observations.moduleAutoLoadingPreference.reasonCode | Should -Be PreferenceUnavailable
    }
    It 'A17 an unset preference is recorded as implicit All' {
        $s=Invoke-TestSession Default
        $s.observations.moduleAutoLoadingPreference.value.explicitlySet | Should -BeFalse
        $s.observations.moduleAutoLoadingPreference.value.effectiveValue | Should -Be All
    }
    It 'A20 concurrent first creators either share the winner key or fail closed and retry' {
        $raceState=Join-Path $root 'concurrent-state'
        $barrier=Join-Path $root 'start-race'
        $processes=@()
        foreach ($number in 1,2) {
            $code=@'
$ErrorActionPreference='Stop'
Import-Module 'MANIFEST'
$m=Get-Module PwshSessionDelta
& $m { $script:FixtureState='STATE'; function script:Get-DeltaStateDirectory { $script:FixtureState } }
$env:PATH='BIN'
$deadline=[DateTime]::UtcNow.AddSeconds(20)
while (-not [IO.File]::Exists('BARRIER')) { if ([DateTime]::UtcNow -gt $deadline) { exit 2 }; [Threading.Thread]::Sleep(10) }
try {
 $s=Export-PwshSessionSnapshot -CommandName delta-race -LiteralPath 'OUTPUT'
 $r=@{status='Success';keyId=$s.privacy.keyId}
} catch { $r=@{status=$_.Exception.Message;keyId=$null} }
[IO.File]::WriteAllText('RESULT',($r | ConvertTo-Json))
'@
            $code=$code.Replace('MANIFEST',$manifest.Replace("'","''")).Replace('STATE',$raceState.Replace("'","''")).Replace('BIN',$root.Replace("'","''")).Replace('BARRIER',$barrier.Replace("'","''")).Replace('OUTPUT',(Join-Path $root "race-$number.snapshot.json").Replace("'","''")).Replace('RESULT',(Join-Path $root "race-$number.result.json").Replace("'","''"))
            $start=[Diagnostics.ProcessStartInfo]::new($pwsh)
            $start.UseShellExecute=$false; $start.CreateNoWindow=$true
            foreach ($argument in @('-NoProfile','-NonInteractive','-EncodedCommand',[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code)))) { $start.ArgumentList.Add($argument) }
            $processes += [Diagnostics.Process]::Start($start)
        }
        [IO.File]::WriteAllText($barrier,'start')
        try {
            foreach ($process in $processes) { $process.WaitForExit(30000) | Should -BeTrue; $process.ExitCode | Should -Be 0 }
        } finally { foreach ($process in $processes) { if (-not $process.HasExited) { $process.Kill() }; $process.Dispose() } }
        $results=@(1,2 | ForEach-Object { Get-Content (Join-Path $root "race-$_.result.json") -Raw | ConvertFrom-Json })
        @($results | Where-Object status -eq Success).Count | Should -BeGreaterThan 0
        foreach ($result in $results) { $result.status | Should -BeIn @('Success','SecretUnavailable') }
        $savedState=$sharedState
        $sharedState=$raceState
        try { $retry=Invoke-TestSession RaceRetry } finally { $sharedState=$savedState }
        foreach ($result in $results | Where-Object status -eq Success) { $result.keyId | Should -Be $retry.privacy.keyId }
        @(Get-ChildItem -LiteralPath $raceState).Count | Should -Be 2
    }
}
