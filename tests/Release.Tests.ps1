# Test-only controls; product code is unchanged.
BeforeAll {
    $manifest=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../src/PwshSessionDelta/PwshSessionDelta.psd1'))
    $pwsh=Join-Path $PSHOME 'pwsh.exe'
    Import-Module $manifest -Force
    $root=Join-Path $TestDrive ('release private 中文 '+[guid]::NewGuid().ToString('N'))
    [void][IO.Directory]::CreateDirectory($root)
    $sensitive='PRIVATE_'+[guid]::NewGuid().ToString('N')
    $state=Join-Path $root 'state'
    $bin1=Join-Path $root 'bin one'; $bin2=Join-Path $root 'bin two'
    [void][IO.Directory]::CreateDirectory($bin1); [void][IO.Directory]::CreateDirectory($bin2)
    $nativeName='delta'+[guid]::NewGuid().ToString('N')
    $nativePath=Join-Path $bin1 ($nativeName+'.exe')
    [IO.File]::Copy((Join-Path ([Environment]::SystemDirectory) 'choice.exe'),$nativePath)
    $shareable=[Collections.Generic.List[string]]::new()
    $global:DeltaReleaseEvidence=[ordered]@{}
    $global:DeltaReleaseRoot=$root
    function Quote-Literal([string] $Value) { "'"+$Value.Replace("'","''")+"'" }
    function Start-ReleaseProcess([string] $Code) {
        $start=[Diagnostics.ProcessStartInfo]::new($pwsh)
        $start.UseShellExecute=$false; $start.CreateNoWindow=$true
        $start.RedirectStandardInput=$true; $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
        foreach ($arg in @('-NoProfile','-NonInteractive','-EncodedCommand',[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Code)))) { $start.ArgumentList.Add($arg) }
        $process=[Diagnostics.Process]::Start($start)
        return @{Process=$process;Out=$process.StandardOutput.ReadToEndAsync();Err=$process.StandardError.ReadToEndAsync()}
    }
    function Stop-ReleaseProcess($Child) {
        if (-not $Child.Process.HasExited) { $Child.Process.Kill($true); $null=$Child.Process.WaitForExit(5000) }
        $Child.Process.Dispose()
    }
    function Invoke-ReleaseProcess([string] $Code) {
        $child=Start-ReleaseProcess $Code
        try {
            if (-not $child.Process.WaitForExit(30000)) { throw 'ReleaseFixtureTimeout' }
            if ($child.Process.ExitCode -ne 0) { throw 'ReleaseFixtureFailed' }
        } finally { Stop-ReleaseProcess $child }
    }
    function Get-NativeSentinelCount {
        $processes=[Diagnostics.Process]::GetProcessesByName($nativeName)
        try { return $processes.Count } finally { foreach ($process in $processes) { $process.Dispose() } }
    }
    function Stop-NativeSentinel {
        foreach ($process in [Diagnostics.Process]::GetProcessesByName($nativeName)) {
            try { $process.Kill($true); $null=$process.WaitForExit(5000) } finally { $process.Dispose() }
        }
    }
    function New-CaptureCode([string] $Output, [string] $Setup='', [string] $Names="'ReleaseAlias','ReleaseFunction','release-target.cmd'", [string] $SearchPath=$bin1) {
        $code=@'
$ErrorActionPreference='Stop'
Import-Module __MANIFEST__
$m=Get-Module PwshSessionDelta
& $m { $script:ReleaseState=__STATE__; function script:Get-DeltaStateDirectory { $script:ReleaseState } }
Set-Location -LiteralPath __ROOT__
$env:PATH=__PATH__
$env:PSModulePath=__MODULES__
$env:PATHEXT='.EXE;.CMD;.BAT'
$global:PSModuleAutoLoadingPreference='All'
__SETUP__
$snapshot=Export-PwshSessionSnapshot -CommandName __NAMES__ -LiteralPath __OUTPUT__
[IO.File]::WriteAllText(__RETURN__,($snapshot | ConvertTo-Json -Depth 32))
'@
        return $code.Replace('__MANIFEST__',(Quote-Literal $manifest)).Replace('__STATE__',(Quote-Literal $state)).Replace('__ROOT__',(Quote-Literal $root)).Replace('__PATH__',(Quote-Literal $SearchPath)).Replace('__MODULES__',(Quote-Literal (Join-Path $PSHOME 'Modules'))).Replace('__SETUP__',$Setup).Replace('__NAMES__',$Names).Replace('__OUTPUT__',(Quote-Literal $Output)).Replace('__RETURN__',(Quote-Literal ($Output+'.return.json')))
    }
    function Read-ReleaseJson([string] $Path) { ConvertFrom-Json ([IO.File]::ReadAllText($Path)) }
    function Save-ComparisonArtifacts([string] $A,[string] $B,[string] $Label) {
        $object=Compare-PwshSessionSnapshot -ReferencePath $A -DifferencePath $B
        $json=Compare-PwshSessionSnapshot -ReferencePath $A -DifferencePath $B -Format Json
        $markdown=Compare-PwshSessionSnapshot -ReferencePath $A -DifferencePath $B -Format Markdown
        foreach ($part in @(@{Suffix='object.json';Text=($object | ConvertTo-Json -Depth 32)},@{Suffix='json';Text=$json},@{Suffix='md';Text=$markdown})) {
            $path=Join-Path $root ($Label+'.'+$part.Suffix)
            [IO.File]::WriteAllText($path,$part.Text); $shareable.Add($path)
        }
        foreach ($path in @($A,$B,($A+'.return.json'),($B+'.return.json'))) { $shareable.Add($path) }
        return @{Object=$object;Json=(ConvertFrom-Json $json);Markdown=$markdown}
    }
}
AfterAll {
    Stop-NativeSentinel
    if ([IO.File]::Exists($nativePath)) { [IO.File]::Delete($nativePath) }
}
Describe 'Stage 3 formal release gates' {
    It 'A11 discovery code has no dynamic command invocation or target process launcher' {
        $errors=$null; $tokens=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../src/PwshSessionDelta/Private/Discovery.ps1'),[ref]$tokens,[ref]$errors)
        $errors.Count | Should -Be 0
        foreach ($command in $ast.FindAll({param($node) $node -is [Management.Automation.Language.CommandAst]},$true)) {
            $command.GetCommandName() | Should -BeIn @('Get-DeltaToken','New-DeltaObservation','Get-DeltaDigest','Test-DeltaLocalPath','Microsoft.PowerShell.Core\Get-Command')
            $command.InvocationOperator | Should -Be 'Unknown'
        }
        foreach ($call in $ast.FindAll({param($node) $node -is [Management.Automation.Language.InvokeMemberExpressionAst]},$true)) {
            $call.Member.Extent.Text | Should -Not -BeIn @('Invoke','InvokeReturnAsIs','Start','CreateProcess','ShellExecute')
        }
    }
    It 'A11 native positive control detects actual launch through a disposable pwsh host' {
        (Get-NativeSentinelCount) | Should -Be 0
        $child=Start-ReleaseProcess ('$ErrorActionPreference=''Stop''; & '+(Quote-Literal $nativePath))
        try {
            $deadline=[DateTime]::UtcNow.AddSeconds(10); $detected=$false
            do {
                if ((Get-NativeSentinelCount) -gt 0) { $detected=$true; break }
                [Threading.Thread]::Sleep(10)
            } while ([DateTime]::UtcNow -lt $deadline -and -not $child.Process.HasExited)
            $detected | Should -BeTrue
            [Threading.Thread]::Sleep(250)
            (Get-NativeSentinelCount) | Should -Be 1
            $global:DeltaReleaseEvidence.nativePositiveDetected=$true
        } finally { Stop-NativeSentinel; Stop-ReleaseProcess $child }
        (Get-NativeSentinelCount) | Should -Be 0
    }
    It 'A11 Export discovers the native sentinel without starting it' {
        $output=Join-Path $root 'native.snapshot.json'
        $code=New-CaptureCode -Output $output -Names (Quote-Literal ($nativeName+'.exe'))
        $child=Start-ReleaseProcess ($code+"`n[Threading.Thread]::Sleep(250)")
        $detected=$false
        try {
            $deadline=[DateTime]::UtcNow.AddSeconds(20)
            do {
                if ((Get-NativeSentinelCount) -gt 0) { $detected=$true; break }
                [Threading.Thread]::Sleep(10)
            } while (-not $child.Process.HasExited -and [DateTime]::UtcNow -lt $deadline)
            $detected | Should -BeFalse
            $child.Process.HasExited | Should -BeTrue
            $child.Process.ExitCode | Should -Be 0
            $s=Read-ReleaseJson $output
            $s.commands[0].externalCandidates.status | Should -Be 'Confirmed observation'
            $s.commands[0].externalCandidates.value[0].type | Should -Be 'Application'
            (Get-NativeSentinelCount) | Should -Be 0
            $global:DeltaReleaseEvidence.nativeNegativeDetected=$false
            $global:DeltaReleaseEvidence.nativeSnapshotProduced=$true
        } finally { Stop-NativeSentinel; Stop-ReleaseProcess $child }
        $shareable.Add($output); $shareable.Add($output+'.return.json')
    }
    It 'A12 binary positive control proves exact discovery autoloads <ModuleName> in a fresh process' -ForEach @(@{ModuleName='CimCmdlets';Command='Get-CimInstance';Assembly='Microsoft.Management.Infrastructure.CimCmdlets';Baseline=1},@{ModuleName='Microsoft.PowerShell.ThreadJob';Command='Start-ThreadJob';Assembly='Microsoft.PowerShell.ThreadJob';Baseline=0}) {
        $output=Join-Path $root ($ModuleName+'-control.json')
        $code=@'
$ErrorActionPreference='Stop'
Import-Module __MANIFEST__
$env:PSModulePath=__MODULES__
$global:PSModuleAutoLoadingPreference='All'
$beforeModule=@(Get-Module __BINARY_MODULE__).Count
$beforeAssembly=@([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq '__BINARY_ASSEMBLY__' }).Count
$command=Get-Command -Name __BINARY_COMMAND__ -ErrorAction Stop
$r=@{beforeModule=$beforeModule;beforeAssembly=$beforeAssembly;afterModule=@(Get-Module __BINARY_MODULE__).Count;afterAssembly=@([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq '__BINARY_ASSEMBLY__' }).Count;type=[string]$command.CommandType;source=$command.Source}
[IO.File]::WriteAllText(__OUTPUT__,($r | ConvertTo-Json))
'@
        Invoke-ReleaseProcess ($code.Replace('__BINARY_MODULE__',$ModuleName).Replace('__BINARY_ASSEMBLY__',$Assembly).Replace('__BINARY_COMMAND__',$Command).Replace('__MANIFEST__',(Quote-Literal $manifest)).Replace('__MODULES__',(Quote-Literal (Join-Path $PSHOME 'Modules'))).Replace('__OUTPUT__',(Quote-Literal $output)))
        $r=Read-ReleaseJson $output
        $r.beforeModule | Should -Be 0
        if ($ModuleName -eq 'CimCmdlets') { $r.beforeAssembly | Should -BeIn @(0,1) } else { $r.beforeAssembly | Should -Be 0 }
        $r.afterModule | Should -Be 1; $r.afterAssembly | Should -Be 1
        $r.type | Should -Be 'Cmdlet'; $r.source | Should -Be $ModuleName
        $global:DeltaReleaseEvidence[$ModuleName+'Positive']=$r
        $shareable.Add($output)
    }
    It 'A12 actual Export leaves <ModuleName> unloaded and its assembly baseline unchanged' -ForEach @(@{ModuleName='CimCmdlets';Command='Get-CimInstance';Assembly='Microsoft.Management.Infrastructure.CimCmdlets';Baseline=1},@{ModuleName='Microsoft.PowerShell.ThreadJob';Command='Start-ThreadJob';Assembly='Microsoft.PowerShell.ThreadJob';Baseline=0}) {
        $output=Join-Path $root ($ModuleName+'.snapshot.json'); $proof=Join-Path $root ($ModuleName+'-negative.json')
        $setup=@'
$beforeModule=@(Get-Module __BINARY_MODULE__).Count
$beforeAssembly=@([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq '__BINARY_ASSEMBLY__' }).Count
$beforeModules=@(Get-Module -All | ForEach-Object { $_.Name+':'+$_.Version }) -join '|'
'@
        $code=New-CaptureCode -Output $output -Names (Quote-Literal $Command) -Setup $setup
        $code+=@'

$r=@{
 beforeModule=$beforeModule;beforeAssembly=$beforeAssembly
 afterModule=@(Get-Module __BINARY_MODULE__).Count
 afterAssembly=@([AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { $_.GetName().Name -eq '__BINARY_ASSEMBLY__' }).Count
 modulesUnchanged=($beforeModules -ceq (@(Get-Module -All | ForEach-Object { $_.Name+':'+$_.Version }) -join '|'))
}
[IO.File]::WriteAllText(__PROOF__,($r | ConvertTo-Json))
'@
        Invoke-ReleaseProcess ($code.Replace('__BINARY_MODULE__',$ModuleName).Replace('__BINARY_ASSEMBLY__',$Assembly).Replace('__PROOF__',(Quote-Literal $proof)))
        $r=Read-ReleaseJson $proof
        $r.beforeModule | Should -Be 0
        if ($ModuleName -eq 'CimCmdlets') { $r.beforeAssembly | Should -BeIn @(0,1) } else { $r.beforeAssembly | Should -Be 0 }
        $r.afterModule | Should -Be 0; $r.afterAssembly | Should -Be $r.beforeAssembly
        $r.modulesUnchanged | Should -BeTrue
        $global:DeltaReleaseEvidence[$ModuleName+'Negative']=$r
        $s=Read-ReleaseJson $output
        foreach ($field in @('internalCandidates','externalCandidates','aliases','functions')) { $s.commands[0].$field.status | Should -Be 'No observed value' }
        $shareable.Add($output); $shareable.Add($output+'.return.json'); $shareable.Add($proof)
    }
    It 'A01 A03 A04 A05 actual independent captures produce expected end-to-end differences' {
        $a=Join-Path $root 'difference-A.json'; $b=Join-Path $root 'difference-B.json'
        $target1=Join-Path $bin1 'release-target.cmd'; $target2=Join-Path $bin2 'release-target.cmd'
        [IO.File]::WriteAllText($target1,'@echo NEVER_EXECUTE > "%~dp0execution.marker"')
        $setupA='function global:ReleaseFunction { throw '+(Quote-Literal ($sensitive+'_A'))+' }; Set-Alias -Name ReleaseAlias -Value ReleaseFunction -Scope Global'
        $setupB='function global:ReleaseFunction { throw '+(Quote-Literal ($sensitive+'_B'))+' }'
        Invoke-ReleaseProcess (New-CaptureCode -Output $a -Setup $setupA -SearchPath ($bin1+';'+$bin2))
        [IO.File]::Delete($target1)
        [IO.File]::WriteAllText($target2,'@echo NEVER_EXECUTE > "%~dp0execution.marker"')
        Invoke-ReleaseProcess (New-CaptureCode -Output $b -Setup $setupB -SearchPath ($bin2+';'+$bin1))
        $reports=Save-ComparisonArtifacts $a $b 'difference-report'
        $r=$reports.Object
        ($r.fieldResults | Where-Object category -eq path).status | Should -Be 'Confirmed difference'
        $s=Read-ReleaseJson $a
        foreach ($pair in @(@{Index=0;Field='aliases'},@{Index=1;Field='functions'},@{Index=2;Field='externalCandidates'})) {
            $command=$r.commandResults | Where-Object queryDigest -eq $s.commands[$pair.Index].query.digest
            ($command.results | Where-Object category -eq $pair.Field).status | Should -Be 'Confirmed difference'
        }
        $r.summary.status | Should -Be 'Confirmed difference'
        $r.summary.unableToDetermine | Should -Be 0
        $global:DeltaReleaseEvidence.differenceSummary=$r.summary
        $reports.Json.summary.confirmedDifferences | Should -Be $r.summary.confirmedDifferences
        $reports.Markdown | Should -Match 'aliases: Confirmed difference'
        $reports.Markdown | Should -Match 'functions: Confirmed difference'
        $reports.Markdown | Should -Match 'externalCandidates: Confirmed difference'
        $reports.Markdown | Should -Match 'path: The recorded values differ'
        [IO.File]::Exists((Join-Path $bin1 'execution.marker')) | Should -BeFalse
        [IO.File]::Exists((Join-Path $bin2 'execution.marker')) | Should -BeFalse
    }
    It 'A10 two independently exported identical fixtures have a wholly equal business summary' {
        $a=Join-Path $root 'same-A.json'; $b=Join-Path $root 'same-B.json'
        $setup='function global:ReleaseFunction { throw '+(Quote-Literal $sensitive)+' }; Set-Alias -Name ReleaseAlias -Value ReleaseFunction -Scope Global'
        Invoke-ReleaseProcess (New-CaptureCode -Output $a -Setup $setup -SearchPath ($bin1+';'+$bin2))
        Invoke-ReleaseProcess (New-CaptureCode -Output $b -Setup $setup -SearchPath ($bin1+';'+$bin2))
        $reports=Save-ComparisonArtifacts $a $b 'same-report'
        $reports.Object.summary.status | Should -Be 'No observed difference'
        $reports.Object.summary.confirmedDifferences | Should -Be 0
        $reports.Object.summary.unableToDetermine | Should -Be 0
        $reports.Object.summary.noObservedDifferences | Should -Be 18
        $global:DeltaReleaseEvidence.equalSummary=$reports.Object.summary
        $reports.Json.summary.status | Should -Be 'No observed difference'
        $reports.Markdown | Should -Match 'Confirmed differences: 0; No observed differences: 18; Unable to determine: 0'
    }
    It 'A09 final end-to-end artifacts return objects and errors contain no sensitive source or secret' {
        $key=[IO.File]::ReadAllBytes((Join-Path $state 'redaction-v1.key'))
        try {
            $denied=@($sensitive,$root,$bin1,$bin2,$env:USERNAME,$env:USERPROFILE,$env:COMPUTERNAME,[Convert]::ToBase64String($key),[Convert]::ToHexString($key),[Convert]::ToHexString($key).ToLowerInvariant())
            # In-memory only, for the driver's final test-results/validation scan; never serialize.
            $global:DeltaReleaseDenied=$denied
            $bad=Join-Path $root 'invalid-private-input.json'; [IO.File]::WriteAllText($bad,('{'+$sensitive))
            try { Compare-PwshSessionSnapshot -ReferencePath $bad -DifferencePath $bad; throw 'ExpectedInputRejection' }
            catch { $message=$_.Exception.Message }
            $message | Should -Be 'InvalidReferenceSnapshot'
            $shareable.Count | Should -BeGreaterThan 12
            $texts=@($message)+@($shareable | ForEach-Object { [IO.File]::ReadAllText($_) })
            foreach ($text in $texts) {
                foreach ($private in $denied) {
                    if ($private -and $text.Contains($private,[StringComparison]::OrdinalIgnoreCase)) { throw 'PrivacyOutputLeak' }
                }
            }
            $global:DeltaReleaseEvidence.privacyArtifactCount=$shareable.Count
            $global:DeltaReleaseEvidence.privacyArtifactsPassed=$true
        } finally { [Array]::Clear($key,0,$key.Length) }
    }
}
