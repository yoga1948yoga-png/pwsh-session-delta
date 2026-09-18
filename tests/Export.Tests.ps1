#Requires -Version 7.0
# Pester 5.9; all diagnostic targets are synthetic and are never invoked.
BeforeAll {
    $modulePath=Join-Path $PSScriptRoot '../src/PwshSessionDelta/PwshSessionDelta.psd1'
    Import-Module $modulePath -Force
    $module=Get-Module PwshSessionDelta
    $root=Join-Path $TestDrive 'fixtures'
    [void][IO.Directory]::CreateDirectory($root)
    $bin=Join-Path $root 'bin space 中文'
    [void][IO.Directory]::CreateDirectory($bin)
    $state=Join-Path $root 'state'
    $global:DeltaTestState=$state
    $oldPath=$env:PATH; $oldModulePath=$env:PSModulePath; $oldExt=$env:PATHEXT
    $env:PATH=$bin; $env:PATHEXT='.EXE;.CMD;.BAT'
    function Export-TestSnapshot([string[]] $Names=@('delta-absent')) {
        Export-PwshSessionSnapshot -CommandName $Names -LiteralPath (Join-Path $root ([guid]::NewGuid().ToString()+'.snapshot.json'))
    }
}
AfterAll {
    $env:PATH=$oldPath; $env:PSModulePath=$oldModulePath; $env:PATHEXT=$oldExt
    Remove-Item -LiteralPath 'Function:/global:DeltaFunction' -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath 'Alias:/global:DeltaAlias' -ErrorAction SilentlyContinue
    Remove-Module PwshSessionDelta -ErrorAction SilentlyContinue
    Remove-Variable DeltaTestState -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Stage 2A Export observations' {
    BeforeEach {
        Mock Get-DeltaStateDirectory -ModuleName PwshSessionDelta { $global:DeltaTestState }
        # Pester wraps each case in functions; these cases deliberately use global fixtures.
        # Unmocked caller-scope behavior is exercised separately below and in Session.Tests.ps1.
        Mock Test-DeltaCallerScope -ModuleName PwshSessionDelta { $true }
    }
    It 'A20 creates a 32-byte protected secret and versioned UTF-8 JSON' {
        $target=Join-Path $root 'first.snapshot.json'
        $s=Export-PwshSessionSnapshot -CommandName delta-absent -LiteralPath $target
        $s.schemaVersion | Should -Be 1
        (Get-Item (Join-Path $state 'redaction-v1.key')).Length | Should -Be 32
        (& $module { Test-DeltaAcl (Get-DeltaStateDirectory) -Directory }) | Should -BeTrue
        (& $module { Test-DeltaAcl ([IO.Path]::Combine((Get-DeltaStateDirectory),'redaction-v1.key')) }) | Should -BeTrue
        (Get-Content $target -Raw | ConvertFrom-Json).privacy.keyId | Should -Be $s.privacy.keyId
        [IO.File]::ReadAllBytes($target)[0] | Should -Be 123
    }
    It 'A01 captures an alias only while it exists without resolving it' {
        Set-Alias -Name DeltaAlias -Value NeverInvokeThis -Scope Global
        $a=Export-TestSnapshot DeltaAlias
        Remove-Item -LiteralPath Alias:/DeltaAlias
        $b=Export-TestSnapshot DeltaAlias
        $a.commands[0].aliases.status | Should -Be 'Confirmed observation'
        $b.commands[0].aliases.status | Should -Be 'No observed value'
    }
    It 'A02 A03 hashes function source stably and does not expose or execute it' {
        function global:DeltaFunction { throw 'SENSITIVE_FUNCTION_SOURCE_73' }
        $a=Export-TestSnapshot DeltaFunction
        $b=Export-TestSnapshot DeltaFunction
        $a.commands[0].functions.value[0].definitionDigest | Should -Be $b.commands[0].functions.value[0].definitionDigest
        function global:DeltaFunction { throw 'DIFFERENT_PRIVATE_SOURCE_91' }
        $c=Export-TestSnapshot DeltaFunction
        $a.commands[0].functions.value[0].definitionDigest | Should -Not -Be $c.commands[0].functions.value[0].definitionDigest
        ($a | ConvertTo-Json -Depth 16) | Should -Not -Match 'SENSITIVE_FUNCTION_SOURCE_73'
        Remove-Item -LiteralPath Function:/DeltaFunction
        (Export-TestSnapshot DeltaFunction).commands[0].functions.status | Should -Be 'No observed value'
    }
    It 'A04 A07 A08 A16 preserves PATH order duplicate entries spaces Chinese and empty entries' {
        $env:PATH="$bin;;$bin;C:\private second"
        try {
            $a=Export-TestSnapshot
            $a.observations.path.value.Count | Should -Be 4
            $a.observations.path.value[0].digest | Should -Be $a.observations.path.value[2].digest
            $a.observations.path.value[0].digest | Should -Not -Be $a.observations.path.value[1].digest
            $env:PATH="C:\private second;$bin;;$bin"
            $b=Export-TestSnapshot
            $a.observations.path.value[3].digest | Should -Be $b.observations.path.value[0].digest
        } finally { $env:PATH=$bin }
    }
    It 'A06 distinguishes successful absence from unknown' {
        $s=Export-TestSnapshot delta-truly-absent
        $s.commands[0].internalCandidates.status | Should -Be 'No observed value'
        $s.commands[0].externalCandidates.status | Should -Be 'No observed value'
    }
    It 'A09 excludes original path command source and secret encodings' {
        $s=Export-TestSnapshot 'PrivateUserProjectCommand'
        $json=$s | ConvertTo-Json -Depth 16
        foreach ($sensitive in @($bin,$root,$env:USERNAME,$env:COMPUTERNAME,'PrivateUserProjectCommand')) {
            if ($sensitive) { $json.Contains($sensitive) | Should -BeFalse }
        }
        $bytes=[IO.File]::ReadAllBytes((Join-Path $state 'redaction-v1.key'))
        $json.Contains([Convert]::ToBase64String($bytes)) | Should -BeFalse
        $json.Contains([Convert]::ToHexString($bytes).ToLowerInvariant()) | Should -BeFalse
        [Array]::Clear($bytes,0,$bytes.Length)
    }
    It 'A11 discovers scripts and batch files without executing body or dynamicparam' {
        $scriptPath=Join-Path $bin 'delta-script.ps1'
        [IO.File]::WriteAllText($scriptPath,@'
dynamicparam { [IO.File]::WriteAllText([IO.Path]::Combine($PSScriptRoot,'dynamic.marker'),'executed') }
end { [IO.File]::WriteAllText([IO.Path]::Combine($PSScriptRoot,'script.marker'),'executed') }
'@)
        foreach ($ext in '.cmd','.bat') { [IO.File]::WriteAllText((Join-Path $bin ('delta-batch'+$ext)), '@echo executed>"%~dp0batch.marker"') }
        foreach ($name in 'delta-script.ps1','delta-batch.cmd','delta-batch.bat') {
            (Export-TestSnapshot $name).commands[0].externalCandidates.status | Should -Be 'Confirmed observation'
        }
        @(Get-ChildItem -LiteralPath $bin -Filter '*.marker').Count | Should -Be 0
    }
    # The former skipped native gate is replaced by executable positive/negative controls
    # in Release.Tests.ps1, included by Invoke-Stage3Tests.ps1.
    It 'A12 never autoloads an unloaded synthetic module and leaves loaded modules unchanged' {
        $mods=Join-Path $root 'modules'
        $fixture=Join-Path $mods 'DeltaUnloadedFixture'
        [void][IO.Directory]::CreateDirectory($fixture)
        [IO.File]::WriteAllText((Join-Path $fixture 'DeltaUnloadedFixture.psd1'),"@{RootModule='DeltaUnloadedFixture.psm1';ModuleVersion='1.0';FunctionsToExport=@('Get-DeltaUnloadedFixture')}" )
        [IO.File]::WriteAllText((Join-Path $fixture 'DeltaUnloadedFixture.psm1'),@'
[IO.File]::WriteAllText([IO.Path]::Combine($PSScriptRoot,'import.marker'),'imported')
function Get-DeltaUnloadedFixture { throw 'NEVER EXECUTE' }
Export-ModuleMember -Function Get-DeltaUnloadedFixture
'@)
        $env:PSModulePath=$mods
        try {
            $before=@(Get-Module -All | ForEach-Object { $_.Name+':'+$_.Version }) -join '|'
            $s=Export-TestSnapshot Get-DeltaUnloadedFixture
            $after=@(Get-Module -All | ForEach-Object { $_.Name+':'+$_.Version }) -join '|'
            $before | Should -Be $after
            $s.commands[0].internalCandidates.status | Should -Be 'No observed value'
            (Test-Path -LiteralPath (Join-Path $fixture 'import.marker')) | Should -BeFalse
        } finally { $env:PSModulePath=$oldModulePath }
    }
    It 'A13 a lookup exception produces unknown while other observations succeed' {
        Mock Get-Command -ModuleName PwshSessionDelta { throw 'PRIVATE_ERROR_SHOULD_NOT_LEAK' }
        $s=Export-TestSnapshot delta-error
        $s.commands[0].internalCandidates.status | Should -Be 'Unable to determine'
        $s.observations.powerShellVersion.status | Should -Be 'Confirmed observation'
        ($s | ConvertTo-Json -Depth 16) | Should -Not -Match 'PRIVATE_ERROR_SHOULD_NOT_LEAK'
    }
    It 'A14 keeps duplicate executable candidates but excludes prefix lookalikes' {
        $second=Join-Path $root 'second bin'
        [void][IO.Directory]::CreateDirectory($second)
        foreach ($folder in $bin,$second) { [IO.File]::Copy((Join-Path $PSHOME 'pwsh.exe'),(Join-Path $folder 'delta-native.exe'),$true) }
        [IO.File]::Copy((Join-Path $PSHOME 'pwsh.exe'),(Join-Path $bin 'delta-native-lookalike.exe'),$true)
        $env:PATH="$bin;$second"
        try {
            $s=Export-TestSnapshot delta-native
            $s.commands[0].externalCandidates.value.Count | Should -Be 2
            $s.commands[0].externalCandidates.value[0].path.digest | Should -Not -Be $s.commands[0].externalCandidates.value[1].path.digest
        } finally { $env:PATH=$bin }
    }
    It 'A15 repeated exports reuse keyId and stable command pseudonyms' {
        $a=Export-TestSnapshot delta-key
        $b=Export-TestSnapshot delta-key
        $a.privacy.keyId | Should -Be $b.privacy.keyId
        $a.commands[0].query.digest | Should -Be $b.commands[0].query.digest
    }
    It 'A14 retains same-name alias and function independently of external candidates' {
        function global:DeltaCollision { throw 'NEVER EXECUTE COLLISION' }
        Set-Alias -Name DeltaCollision -Value NeverInvokeCollision -Scope Global
        try {
            $s=Export-TestSnapshot DeltaCollision
            $s.commands[0].aliases.value.Count | Should -Be 1
            $s.commands[0].functions.value.Count | Should -Be 1
            $s.commands[0].internalCandidates.value.Count | Should -Be 2
        } finally {
            Remove-Item -LiteralPath Alias:/DeltaCollision
            Remove-Item -LiteralPath Function:/DeltaCollision
        }
    }
    It 'A16 distinguishes missing versus empty process environment and preserves PSModulePath entries' {
        $env:PSModulePath="$bin;;$bin"
        try {
            $s=Export-TestSnapshot
            $s.observations.psModulePath.value.Count | Should -Be 3
            Remove-Item Env:/PATHEXT
            (Export-TestSnapshot).observations.pathExt.status | Should -Be 'No observed value'
            [Environment]::SetEnvironmentVariable('PATHEXT','','Process')
            $empty=Export-TestSnapshot
            $empty.observations.pathExt.status | Should -Be 'Confirmed observation'
            $empty.observations.pathExt.value.Count | Should -Be 1
        } finally { $env:PSModulePath=$oldModulePath; $env:PATHEXT='.EXE;.CMD;.BAT' }
    }
    It 'A17 preserves process paths and autoload preference' {
        $before=@($env:PATH,$env:PSModulePath,$env:PATHEXT,$PSModuleAutoLoadingPreference) -join '|'
        $null=Export-TestSnapshot
        (@($env:PATH,$env:PSModulePath,$env:PATHEXT,$PSModuleAutoLoadingPreference) -join '|') | Should -Be $before
    }
    It 'A17 unavailable caller scope is unknown rather than absent' {
        Mock Test-DeltaCallerScope -ModuleName PwshSessionDelta { $false }
        $s=Export-TestSnapshot delta-hidden-local
        $s.commands[0].aliases.reasonCode | Should -Be 'CallerScopeNotVisible'
        $s.commands[0].functions.status | Should -Be 'Unable to determine'
        $s.observations.moduleAutoLoadingPreference.reasonCode | Should -Be 'PreferenceUnavailable'
    }
    It 'A18 treats wildcard syntax literally and marks external completeness unknown' {
        foreach ($name in 'delta*literal','delta?literal','delta[literal','delta]literal','delta`literal') {
            Set-Alias -Name $name -Value NeverInvoke -Scope Global
            try {
                $s=Export-TestSnapshot $name
                $s.commands[0].aliases.value.Count | Should -Be 1
                $s.commands[0].externalCandidates.reasonCode | Should -Be 'LiteralExternalNameNotQualified'
            } finally { Remove-Item -LiteralPath ('Alias:/'+$name) }
        }
    }
    It 'A18 rejects unsupported command input without lookup' {
        $s=Export-TestSnapshot @('SomeModule\Get-Thing','cmd --help','C:\private.exe')
        foreach ($c in $s.commands) { $c.internalCandidates.reasonCode | Should -Be 'UnsupportedCommandForm' }
    }
    It 'A18 rejects an unsafe external search path but retains internal observations' {
        $env:PATH='\\uncontacted.invalid\share'
        try {
            $s=Export-TestSnapshot Get-Command
            $s.commands[0].externalCandidates.reasonCode | Should -Be 'UnsafeSearchPath'
            $s.commands[0].internalCandidates.status | Should -Be 'Confirmed observation'
        } finally { $env:PATH=$bin }
    }
    It 'A20 refuses to overwrite existing output and secret' {
        $target=Join-Path $root 'keep.snapshot.json'
        [IO.File]::WriteAllText($target,'ORIGINAL')
        { Export-PwshSessionSnapshot -CommandName delta -LiteralPath $target } | Should -Throw '*OutputExists*'
        [IO.File]::ReadAllText($target) | Should -Be 'ORIGINAL'
        { Export-PwshSessionSnapshot -CommandName delta -LiteralPath (Join-Path $state 'redaction-v1.key') } | Should -Throw '*InvalidOutputPath*'
    }
    It 'A20 fails closed for existing state without key or with corrupt key' {
        $bad=Join-Path $root 'bad-state'
        [void][IO.Directory]::CreateDirectory($bad)
        $global:DeltaTestState=$bad
        try {
            { Export-TestSnapshot } | Should -Throw '*SecretUnavailable*'
            [IO.File]::WriteAllText((Join-Path $bad 'redaction-v1.key'),'bad')
            { Export-TestSnapshot } | Should -Throw '*SecretUnavailable*'
            [IO.File]::ReadAllText((Join-Path $bad 'redaction-v1.key')) | Should -Be 'bad'
        } finally { $global:DeltaTestState=$state }
    }
    It 'A20 rejects permissive ACL and simulated unreadable secret without replacement' {
        Mock Test-DeltaAcl -ModuleName PwshSessionDelta { $false }
        { Export-TestSnapshot } | Should -Throw '*SecretUnavailable*'
    }
    It 'A20 leaves no final file when serialization fails' {
        Mock ConvertTo-Json -ModuleName PwshSessionDelta { throw 'PRIVATE_SERIALIZATION_ERROR' }
        $target=Join-Path $root 'failed.snapshot.json'
        { Export-PwshSessionSnapshot -CommandName delta -LiteralPath $target } | Should -Throw '*SnapshotWriteFailed*'
        (Test-Path -LiteralPath $target) | Should -BeFalse
        @(Get-ChildItem -LiteralPath $root -Filter '.pwsh-session-delta-*.tmp').Count | Should -Be 0
    }
    It 'A20 corrupt but otherwise protected secret fails closed' {
        $global:DeltaTestState=Join-Path $root 'corrupt-protected-state'
        try {
            $null=Export-TestSnapshot
            $keyPath=Join-Path $global:DeltaTestState 'redaction-v1.key'
            [IO.File]::WriteAllBytes($keyPath,[byte[]]@(1,2,3))
            { Export-TestSnapshot } | Should -Throw '*SecretUnavailable*'
            (Get-Item -LiteralPath $keyPath).Length | Should -Be 3
        } finally { $global:DeltaTestState=$state }
    }
    It 'A20 exclusive reader lock causes safe failure without replacement' {
        $keyPath=Join-Path $state 'redaction-v1.key'
        $lock=[IO.FileStream]::new($keyPath,'Open','Read','None')
        try { { Export-TestSnapshot } | Should -Throw '*SecretUnavailable*' }
        finally { $lock.Dispose() }
        (Export-TestSnapshot).privacy.keyId | Should -Not -BeNullOrEmpty
    }
    It 'A20 same-length key corruption or a missing integrity marker fails closed' {
        $global:DeltaTestState=Join-Path $root 'same-length-corrupt-state'
        try {
            $null=Export-TestSnapshot
            $keyPath=Join-Path $global:DeltaTestState 'redaction-v1.key'
            $bytes=[IO.File]::ReadAllBytes($keyPath)
            $bytes[0]=$bytes[0] -bxor 1
            [IO.File]::WriteAllBytes($keyPath,$bytes)
            { Export-TestSnapshot } | Should -Throw '*SecretUnavailable*'
            $bytes[0]=$bytes[0] -bxor 1
            [IO.File]::WriteAllBytes($keyPath,$bytes)
            [Array]::Clear($bytes,0,$bytes.Length)
            [IO.File]::Delete((Join-Path $global:DeltaTestState 'redaction-v1.id'))
            { Export-TestSnapshot } | Should -Throw '*SecretUnavailable*'
        } finally { $global:DeltaTestState=$state }
    }
    It 'A20 a real broad ACL on a test-only key is rejected and not repaired' {
        $global:DeltaTestState=Join-Path $root 'broad-acl-state'
        try {
            $null=Export-TestSnapshot
            $file=[IO.FileInfo]::new((Join-Path $global:DeltaTestState 'redaction-v1.key'))
            $acl=[IO.FileSystemAclExtensions]::GetAccessControl($file)
            $rule=[Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new('S-1-1-0'),'Read','Allow')
            $acl.AddAccessRule($rule)
            [IO.FileSystemAclExtensions]::SetAccessControl($file,$acl)
            { Export-TestSnapshot } | Should -Throw '*SecretUnavailable*'
            $after=[IO.FileSystemAclExtensions]::GetAccessControl($file)
            @($after.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier]) | Where-Object { $_.IdentityReference.Value -eq 'S-1-1-0' }).Count | Should -Be 1
        } finally { $global:DeltaTestState=$state }
    }
    It 'A20 failure after full staging cleans temporary file and leaves no final output' {
        Mock Publish-DeltaSnapshotFile -ModuleName PwshSessionDelta { throw 'SYNTHETIC_RENAME_FAILURE' }
        $target=Join-Path $root 'rename-failure.snapshot.json'
        { Export-PwshSessionSnapshot -CommandName delta -LiteralPath $target } | Should -Throw '*SnapshotWriteFailed*'
        (Test-Path -LiteralPath $target) | Should -BeFalse
        @(Get-ChildItem -LiteralPath $root -Filter '.pwsh-session-delta-*.tmp').Count | Should -Be 0
    }
    It 'A20 target created by another writer wins without overwrite' {
        Mock Publish-DeltaSnapshotFile -ModuleName PwshSessionDelta {
            param($Temporary,$Destination)
            [IO.File]::WriteAllText($Destination,'OTHER_WRITER')
            [IO.File]::Move($Temporary,$Destination,$false)
        }
        $target=Join-Path $root 'racing-output.snapshot.json'
        { Export-PwshSessionSnapshot -CommandName delta -LiteralPath $target } | Should -Throw '*SnapshotWriteFailed*'
        [IO.File]::ReadAllText($target) | Should -Be 'OTHER_WRITER'
        @(Get-ChildItem -LiteralPath $root -Filter '.pwsh-session-delta-*.tmp').Count | Should -Be 0
    }
    It 'A13 invalid PATHEXT is unknown and does not leak raw text' {
        $env:PATHEXT='PRIVATE_INVALID_EXTENSION_VALUE'
        try {
            $s=Export-TestSnapshot
            $s.observations.pathExt.reasonCode | Should -Be InvalidPathExt
            $s.commands[0].externalCandidates.status | Should -Be 'Unable to determine'
            ($s | ConvertTo-Json -Depth 16) | Should -Not -Match 'PRIVATE_INVALID_EXTENSION_VALUE'
        } finally { $env:PATHEXT='.EXE;.CMD;.BAT' }
    }
    It 'A12 observes already loaded module Cmdlets without importing anything for lookup' {
        $s=Export-TestSnapshot ConvertTo-Json
        $s.commands[0].internalCandidates.value[0].type | Should -Be Cmdlet
        $s.commands[0].internalCandidates.value[0].module.digest | Should -Not -BeNullOrEmpty
    }
    It 'A13 a non-filesystem current location is unknown and remains unchanged' {
        Push-Location Env:/
        try {
            $s=Export-TestSnapshot
            $s.observations.workingDirectory.reasonCode | Should -Be LocationUnavailable
            (Get-Location).Provider.Name | Should -Be Environment
        } finally { Pop-Location }
    }
}
