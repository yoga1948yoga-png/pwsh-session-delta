BeforeAll {
    $project=Split-Path $PSScriptRoot
    Import-Module (Join-Path $project 'src/PwshSessionDelta/PwshSessionDelta.psd1') -Force
    $fixture=[IO.File]::ReadAllText((Join-Path $project 'docs/example-snapshot.json'))
    function New-Fixture { ConvertFrom-Json $fixture -AsHashtable }
    function Copy-Fixture($Value) { ConvertFrom-Json (ConvertTo-Json -InputObject $Value -Depth 32) -AsHashtable }
    function Token($Kind, $Character) { @{kind=$Kind;digest=([string]$Character)*64} }
    function Observed($Value) { @{status='Confirmed observation';reasonCode=$null;value=$Value} }
    function Unknown { @{status='Unable to determine';reasonCode='LookupFailed';value=$null} }
    function Run-Comparison($A,$B,[string]$Format='Object') {
        [IO.File]::WriteAllText($referencePath,(ConvertTo-Json -InputObject $A -Depth 32))
        [IO.File]::WriteAllText($differencePath,(ConvertTo-Json -InputObject $B -Depth 32))
        Compare-PwshSessionSnapshot -ReferencePath $referencePath -DifferencePath $differencePath -Format $Format
    }
    function Field($Result,$Name) { $Result.fieldResults | Where-Object category -EQ $Name }
    function CommandField($Result,$Name) { $Result.commandResults[0].results | Where-Object category -EQ $Name }
}
Describe 'Offline schema-v1 snapshot comparison' {
    BeforeEach {
        $a=New-Fixture; $b=New-Fixture
        $referencePath=Join-Path $TestDrive '参考 [a] 空格.json'
        $differencePath=Join-Path $TestDrive '比较 [b] 空格.json'
    }
    It 'A10 equal snapshots with literal Unicode filenames have no observed differences' {
        $r=Run-Comparison $a $b
        $r.summary.status | Should -Be 'No observed difference'
        $r.summary.noObservedDifferences | Should -Be 10
        $r.summary.unableToDetermine | Should -Be 0
    }
    It 'A05 external candidate path identity changes' {
        $b.commands[0].externalCandidates.value[0].path=Token path a
        $r=CommandField (Run-Comparison $a $b) externalCandidates
        $r.status | Should -Be 'Confirmed difference'
        $r.details.referenceOnly.Count | Should -Be 1
        $r.details.differenceOnly.Count | Should -Be 1
    }
    It 'A04 ordered path fields preserve order: <Name>' -ForEach @(@{Name='path'},@{Name='psModulePath'}) {
        $a.observations[$Name]=Observed @((Token path a),(Token path b))
        $b.observations[$Name]=Observed @((Token path b),(Token path a))
        (Field (Run-Comparison $a $b) $Name).status | Should -Be 'Confirmed difference'
    }
    It 'A16 path duplicate multiplicity is meaningful' {
        $a.observations.path=Observed @((Token path a),(Token path a),(Token path b))
        $b.observations.path=Observed @((Token path a),(Token path b))
        (Field (Run-Comparison $a $b) path).status | Should -Be 'Confirmed difference'
    }
    It 'A16 PATHEXT order duplicates and empty entries are preserved' {
        $a.observations.pathExt=Observed @('.EXE','','.CMD','.EXE')
        $b.observations.pathExt=Observed @('.CMD','','.EXE','.EXE')
        (Field (Run-Comparison $a $b) pathExt).status | Should -Be 'Confirmed difference'
        $b.observations.pathExt=Observed @('.EXE','','.CMD')
        (Field (Run-Comparison $a $b) pathExt).status | Should -Be 'Confirmed difference'
    }
    It 'A13 one-sided unknown propagates without blocking independent fields' {
        $b.observations.path=Unknown
        $b.observations.powerShellVersion.value='7.6.4'
        $r=Run-Comparison $a $b
        (Field $r path).status | Should -Be 'Unable to determine'
        (Field $r powerShellVersion).status | Should -Be 'Confirmed difference'
        $r.summary.confirmedDifferences | Should -Be 1
        $r.summary.noObservedDifferences | Should -Be 8
        $r.summary.unableToDetermine | Should -Be 1
        $r.summary.status | Should -Be 'Confirmed difference'
    }
    It 'A13 two unknown observations never count as equal' {
        $a.observations.path=Unknown; $b.observations.path=Unknown
        $r=Run-Comparison $a $b
        (Field $r path).status | Should -Be 'Unable to determine'
        $r.summary.status | Should -Be 'Unable to determine'
    }
    It 'Unknown command observations propagate individually: <Name>' -ForEach @(@{Name='internalCandidates'},@{Name='externalCandidates'},@{Name='aliases'},@{Name='functions'}) {
        $a.commands[0][$Name]=Unknown; $b.commands[0][$Name]=Unknown
        $r=Run-Comparison $a $b
        (CommandField $r $Name).status | Should -Be 'Unable to determine'
        $r.summary.unableToDetermine | Should -Be 1
    }
    It 'A01 A02 absence versus presence differs: <Name>' -ForEach @(@{Name='aliases'},@{Name='functions'}) {
        $value=if ($Name -eq 'aliases') {@{name=(Token command a);target=(Token alias-target b)}} else {@{name=(Token command a);definitionDigest=('b'*64)}}
        $b.commands[0][$Name]=Observed @($value)
        $result=CommandField (Run-Comparison $a $b) $Name
        $result.status | Should -Be 'Confirmed difference'
        $result.details.referenceOnly.Count | Should -Be 0
        $result.details.differenceOnly.Count | Should -Be 1
    }
    It 'Explicit absence on both sides is equal' {
        (CommandField (Run-Comparison $a $b) aliases).reasonCode | Should -Be 'BothAbsent'
    }
    It 'A03 Function compatible digests compare equal then different without source' {
        $a.commands[0].functions=Observed @(@{name=(Token command a);definitionDigest=('b'*64)})
        $b.commands[0].functions=Copy-Fixture $a.commands[0].functions
        (CommandField (Run-Comparison $a $b) functions).status | Should -Be 'No observed difference'
        $b.commands[0].functions.value[0].definitionDigest='c'*64
        (CommandField (Run-Comparison $a $b) functions).status | Should -Be 'Confirmed difference'
    }
    It 'Alias targets compare without following the target' {
        $a.commands[0].aliases=Observed @(@{name=(Token command a);target=(Token alias-target b)})
        $b.commands[0].aliases=Copy-Fixture $a.commands[0].aliases
        (CommandField (Run-Comparison $a $b) aliases).status | Should -Be 'No observed difference'
        $b.commands[0].aliases.value[0].target=Token alias-target c
        (CommandField (Run-Comparison $a $b) aliases).status | Should -Be 'Confirmed difference'
    }
    It 'A15 incompatible privacy metadata only blocks dependent identities: <Part>' -ForEach @(@{Part='keyId';Value=('a'*64)},@{Part='redactionVersion';Value=2},@{Part='redactionScheme';Value='Other-Scheme'}) {
        $a.commands[0].functions=Observed @(@{name=(Token command a);definitionDigest=('b'*64)})
        $b.commands[0].functions=Copy-Fixture $a.commands[0].functions
        $b.privacy[$Part]=$Value
        $b.observations.powerShellVersion.value='7.6.4'
        $r=Run-Comparison $a $b
        (Field $r path).status | Should -Be 'Unable to determine'
        (Field $r workingDirectory).status | Should -Be 'Unable to determine'
        (Field $r powerShellVersion).status | Should -Be 'Confirmed difference'
        (Field $r pathExt).status | Should -Be 'No observed difference'
        (Field $r moduleAutoLoadingPreference).status | Should -Be 'No observed difference'
        $r.commandResults[0].results[0].reasonCode | Should -Be 'PrivacyIdentityIncompatible'
        $r.commandResults[0].results.Count | Should -Be 1
    }
    It 'Explicit presence status is comparable without shared private identity' {
        $b.privacy.keyId='a'*64
        $b.observations.psModulePath=Observed @((Token path a))
        (Field (Run-Comparison $a $b) psModulePath).reasonCode | Should -Be 'PresenceChanged'
    }
    It 'Command query array reordering produces identical reports' {
        $other=Copy-Fixture $a.commands[0]; $other.query=Token command a
        $a.commands+=,$other; $b.commands=@($other,$b.commands[0])
        $r=Run-Comparison $a $b
        $r.summary.status | Should -Be 'No observed difference'
        $j=Run-Comparison $a $b Json
        $b.commands=@($b.commands[1],$b.commands[0])
        (Run-Comparison $a $b Json) | Should -BeExactly $j
    }
    It 'Missing query is unknown while common query continues' {
        $other=Copy-Fixture $a.commands[0]; $other.query=Token command a; $a.commands+=,$other
        $r=Run-Comparison $a $b
        $r.summary.unableToDetermine | Should -Be 1
        $r.summary.noObservedDifferences | Should -Be 10
        @($r.commandResults.results | Where-Object reasonCode -EQ QueryNotCapturedBothSides).Count | Should -Be 1
    }
    It 'Case-distinct query HMACs are unmatched rather than guessed' {
        $b.commands[0].query=Token command b
        $r=Run-Comparison $a $b
        $r.summary.unableToDetermine | Should -Be 2
        $r.summary.confirmedDifferences | Should -Be 0
    }
    It 'Identical duplicate queries collapse and preserve occurrence counts' {
        $a.commands+=,(Copy-Fixture $a.commands[0])
        $r=Run-Comparison $a $b
        $r.commandResults.Count | Should -Be 1
        $r.commandResults[0].referenceOccurrences | Should -Be 2
        $r.summary.status | Should -Be 'No observed difference'
    }
    It 'Conflicting duplicate queries are unknown' {
        $a.commands+=,(Copy-Fixture $a.commands[0]); $a.commands[1].externalCandidates=Unknown
        $r=Run-Comparison $a $b
        $r.commandResults[0].results[0].reasonCode | Should -Be 'ConflictingDuplicateQuery'
    }
    It 'Candidate reordering is ignored but multiplicity retained: <Name>' -ForEach @(@{Name='externalCandidates'},@{Name='internalCandidates'}) {
        if ($Name -eq 'externalCandidates') { $one=$a.commands[0].externalCandidates.value[0] }
        else { $one=@{type='Cmdlet';name=(Token command a);module=(Token module b)} }
        $two=Copy-Fixture $one; $two.name=Token command c
        $a.commands[0][$Name]=Observed @($one,$two,$one)
        $b.commands[0][$Name]=Observed @($two,$one,$one)
        (CommandField (Run-Comparison $a $b) $Name).status | Should -Be 'No observed difference'
        $b.commands[0][$Name]=Observed @($one,$two)
        $r=CommandField (Run-Comparison $a $b) $Name
        $r.status | Should -Be 'Confirmed difference'
        $r.details.referenceOnly[0].count | Should -Be 1
        $r.details.both.Count | Should -Be 2
    }
    It 'Explicit preference setting is part of scalar identity' {
        $b.observations.moduleAutoLoadingPreference.value.explicitlySet=$true
        (Field (Run-Comparison $a $b) moduleAutoLoadingPreference).status | Should -Be 'Confirmed difference'
    }
    It 'A19 rejects invalid structure: <Label>' -ForEach @(
        @{Label='schema';Edit={$b.schemaVersion=2}},
        @{Label='missing top-level';Edit={$b.Remove('capture')}},
        @{Label='schema string';Edit={$b.schemaVersion='1'}},
        @{Label='missing keyId';Edit={$b.privacy.Remove('keyId')}},
        @{Label='wrong commands type';Edit={$b.commands=@{}}},
        @{Label='wrong digest';Edit={$b.commands[0].query.digest='private text'}},
        @{Label='wrong boolean';Edit={$b.observations.moduleAutoLoadingPreference.value.explicitlySet='false'}},
        @{Label='type is array';Edit={$b.commands[0].externalCandidates.value[0].type=@('Application')}},
        @{Label='token kind is array';Edit={$b.commands[0].query.kind=@('command')}},
        @{Label='empty successful candidate array';Edit={$b.commands[0].externalCandidates.value=@()}},
        @{Label='digest newline';Edit={$b.commands[0].query.digest+="`n"}},
        @{Label='wrong array';Edit={$b.observations.path.value=$b.observations.path.value[0]}},
        @{Label='unknown carries value';Edit={$b.observations.path.status='Unable to determine';$b.observations.path.reasonCode='LookupFailed'}},
        @{Label='raw extra field';Edit={$b.commands[0].functions.source='private source'}},
        @{Label='incorrect key casing';Edit={$b['SchemaVersion']=$b.schemaVersion;$b.Remove('schemaVersion')}},
        @{Label='unknown reason';Edit={$b.observations.path=Unknown;$b.observations.path.reasonCode='PRIVATE_SOURCE'}}
    ) {
        . $Edit
        { Run-Comparison $a $b } | Should -Throw '*InvalidDifferenceSnapshot*'
    }
    It 'A19 malformed JSON and exact or case-conflicting duplicate keys fail' -ForEach @(
        @{Json='{'},@{Json='{"schemaVersion":1,"schemaVersion":1}'},@{Json='{"schemaVersion":1,"SchemaVersion":1}'},@{Json='{"nested":{"a":1,"A":2}}'},@{Json='{"a":1,}'},@{Json='/*comment*/ {}'}
    ) {
        [IO.File]::WriteAllText($referencePath,$Json)
        { Compare-PwshSessionSnapshot $referencePath $differencePath } | Should -Throw '*InvalidReferenceSnapshot*'
    }
    It 'Unreadable missing input is a terminating input failure' {
        { Compare-PwshSessionSnapshot (Join-Path $TestDrive 'missing.json') $differencePath } | Should -Throw '*InvalidReferenceSnapshot*'
    }
    It 'Invalid UTF-8 fails without exposing parser details' {
        [IO.File]::WriteAllBytes($referencePath,[byte[]]@(0xff,0xfe,0xff))
        { Compare-PwshSessionSnapshot $referencePath $differencePath } | Should -Throw '*InvalidReferenceSnapshot*'
    }
    It 'Unsupported redaction versions are not assumed compatible even when equal' {
        $a.privacy.redactionVersion=2; $b.privacy.redactionVersion=2
        (Field (Run-Comparison $a $b) path).status | Should -Be 'Unable to determine'
    }
    It 'A19 JSON and Markdown render the same structured mixed result' {
        $b.observations.path=Unknown; $b.observations.powerShellVersion.value='7.6.4'
        $object=Run-Comparison $a $b
        $json=Run-Comparison $a $b Json
        $parsed=ConvertFrom-Json $json
        $parsed.summary.confirmedDifferences | Should -Be $object.summary.confirmedDifferences
        $parsed.summary.unableToDetermine | Should -Be 1
        $parsed.commandResults[0].results[1].details.both[0].identity.path.digest | Should -Be $a.commands[0].externalCandidates.value[0].path.digest
        $markdown=Run-Comparison $a $b Markdown
        $markdown | Should -Match 'Confirmed differences: 1; No observed differences: 8; Unable to determine: 1'
        $markdown | Should -Match 'Differences are observations, not proof of causation\.'
        $markdown | Should -Not -Match '\{"'
        $json | Should -Not -Match ([regex]::Escape($referencePath))
        $markdown | Should -Not -Match 'ScriptBlock|PRIVATE_SOURCE'
    }
    It 'Markdown safely escapes syntax and preserves non-ASCII' {
        $escaped=& (Get-Module PwshSessionDelta) { ConvertTo-DeltaMarkdownText "中文|<x>[y]*_``&`n" }
        $escaped | Should -BeExactly '中文&#124;&lt;x&gt;&#91;y&#93;&#42;&#95;&#96;&amp; '
    }
    It 'A17 A20 offline operation never calls discovery or secret helpers and leaves state unchanged' {
        Mock Get-Command { throw 'LIVE_LOOKUP' } -ModuleName PwshSessionDelta
        Mock Get-DeltaSecret { throw 'SECRET_READ' } -ModuleName PwshSessionDelta
        Mock Get-DeltaEnvironment { throw 'ENV_READ' } -ModuleName PwshSessionDelta
        Mock Get-Alias { throw 'ALIAS_READ' } -ModuleName PwshSessionDelta
        Mock Get-Item { throw 'LIVE_ITEM_READ' } -ModuleName PwshSessionDelta
        Mock Import-Module { throw 'TARGET_IMPORT' } -ModuleName PwshSessionDelta
        $beforePath=$env:PATH; $beforeModules=$env:PSModulePath; $beforePreference=$PSModuleAutoLoadingPreference
        $beforeFunctions=@(Get-ChildItem Function: | Select-Object -ExpandProperty Name) -join '|'
        $beforeAliases=@(Get-Alias | ForEach-Object { $_.Name+'='+$_.Definition }) -join '|'
        $r=Run-Comparison $a $b
        $r.summary.status | Should -Be 'No observed difference'
        $env:PATH | Should -BeExactly $beforePath
        $env:PSModulePath | Should -BeExactly $beforeModules
        $PSModuleAutoLoadingPreference | Should -Be $beforePreference
        (@(Get-ChildItem Function: | Select-Object -ExpandProperty Name) -join '|') | Should -BeExactly $beforeFunctions
        (@(Get-Alias | ForEach-Object { $_.Name+'='+$_.Definition }) -join '|') | Should -BeExactly $beforeAliases
        foreach ($name in @('Get-Command','Get-DeltaSecret','Get-DeltaEnvironment','Get-Alias','Get-Item','Import-Module')) { Should -Invoke $name -ModuleName PwshSessionDelta -Times 0 -Exactly }
    }
}
