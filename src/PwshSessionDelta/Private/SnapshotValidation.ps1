# Closed schema-v1 validation. Never echo input text or parser exceptions.
function Assert-DeltaKeys($Object, [string[]] $Keys) {
    if ($Object -isnot [System.Collections.IDictionary] -or $Object.Count -ne $Keys.Count) { throw 'InvalidSnapshot' }
    foreach ($key in $Keys) { if ($key -cnotin @($Object.Keys)) { throw 'InvalidSnapshot' } }
}
function Assert-DeltaDigest($Value) {
    if ($Value -isnot [string] -or $Value -cnotmatch '^[0-9a-f]{64}\z') { throw 'InvalidSnapshot' }
}
function Assert-DeltaToken($Value, [string] $Kind) {
    Assert-DeltaKeys $Value @('kind','digest')
    if ($Value.kind -isnot [string] -or $Value.kind -cne $Kind) { throw 'InvalidSnapshot' }
    Assert-DeltaDigest $Value.digest
}
function Assert-DeltaJsonKeys($Element) {
    if ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Object) {
        $seen=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($property in $Element.EnumerateObject()) {
            if (-not $seen.Add($property.Name)) { throw 'InvalidSnapshot' }
            Assert-DeltaJsonKeys $property.Value
        }
    } elseif ($Element.ValueKind -eq [System.Text.Json.JsonValueKind]::Array) {
        foreach ($item in $Element.EnumerateArray()) { Assert-DeltaJsonKeys $item }
    }
}
function Assert-DeltaSnapshotObservation($Observation, [string] $Field) {
    Assert-DeltaKeys $Observation @('status','reasonCode','value')
    if ($Observation.status -isnot [string]) { throw 'InvalidSnapshot' }
    if ($Observation.status -ceq 'Unable to determine') {
        if ($null -ne $Observation.value -or $Observation.reasonCode -isnot [string] -or $Observation.reasonCode -cnotin @('UnsupportedCommandForm','LookupFailed','UnsafeSearchPath','LiteralExternalNameNotQualified','RuntimeNotQualified','LocationUnavailable','EnvironmentReadFailed','InvalidPathExt','PreferenceUnavailable','CallerScopeNotVisible')) { throw 'InvalidSnapshot' }
        return
    }
    if ($null -ne $Observation.reasonCode) { throw 'InvalidSnapshot' }
    if ($Observation.status -ceq 'No observed value') {
        if ($null -ne $Observation.value) { throw 'InvalidSnapshot' }; return
    }
    if ($Observation.status -cne 'Confirmed observation' -or $null -eq $Observation.value) { throw 'InvalidSnapshot' }
    $v=$Observation.value
    switch -CaseSensitive ($Field) {
        'powerShellVersion' { if ($v -isnot [string] -or $v -cnotmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:\.[0-9]+)?(?:-[A-Za-z0-9.-]+)?\z') { throw 'InvalidSnapshot' } }
        'workingDirectory' { Assert-DeltaToken $v 'path' }
        'moduleAutoLoadingPreference' {
            Assert-DeltaKeys $v @('explicitlySet','effectiveValue')
            if ($v.explicitlySet -isnot [bool] -or $v.effectiveValue -isnot [string] -or $v.effectiveValue -cnotin @('All','None','ModuleQualified')) { throw 'InvalidSnapshot' }
        }
        default {
            if ($v -isnot [array] -or $v.Count -eq 0) { throw 'InvalidSnapshot' }
            foreach ($item in $v) {
                switch -CaseSensitive ($Field) {
                    { $_ -cin @('path','psModulePath') } { Assert-DeltaToken $item 'path' }
                    'pathExt' { if ($item -isnot [string] -or ($item -ne '' -and $item -cnotmatch '^\.[A-Za-z0-9]+\z')) { throw 'InvalidSnapshot' } }
                    'internalCandidates' {
                        Assert-DeltaKeys $item @('name','type','module'); Assert-DeltaToken $item.name 'command'
                        if ($item.type -isnot [string] -or $item.type -cnotin @('Alias','Function','Filter','Cmdlet')) { throw 'InvalidSnapshot' }
                        if ($null -ne $item.module) { Assert-DeltaToken $item.module 'module' }
                    }
                    'externalCandidates' {
                        Assert-DeltaKeys $item @('name','type','path'); Assert-DeltaToken $item.name 'command'; Assert-DeltaToken $item.path 'path'
                        if ($item.type -isnot [string] -or $item.type -cnotin @('Application','ExternalScript')) { throw 'InvalidSnapshot' }
                    }
                    'aliases' { Assert-DeltaKeys $item @('name','target'); Assert-DeltaToken $item.name 'command'; Assert-DeltaToken $item.target 'alias-target' }
                    'functions' { Assert-DeltaKeys $item @('name','definitionDigest'); Assert-DeltaToken $item.name 'command'; Assert-DeltaDigest $item.definitionDigest }
                    default { throw 'InvalidSnapshot' }
                }
            }
        }
    }
}
function Read-DeltaSnapshot([string] $Path) {
    $document=$null
    try {
        $json=[IO.File]::ReadAllText($Path,[Text.UTF8Encoding]::new($false,$true))
        $document=[System.Text.Json.JsonDocument]::Parse($json)
        Assert-DeltaJsonKeys $document.RootElement
        $s=ConvertFrom-Json -InputObject $json -AsHashtable -Depth 64
        Assert-DeltaKeys $s @('schemaVersion','capture','privacy','observations','commands')
        if ($s.schemaVersion -isnot [long] -or $s.schemaVersion -ne 1) { throw 'InvalidSnapshot' }
        Assert-DeltaKeys $s.capture @('model','discoveryPolicyVersion')
        if ($s.capture.model -isnot [string] -or $s.capture.model -cne 'current-session' -or $s.capture.discoveryPolicyVersion -isnot [long] -or $s.capture.discoveryPolicyVersion -ne 1) { throw 'InvalidSnapshot' }
        Assert-DeltaKeys $s.privacy @('redactionScheme','redactionVersion','keyId')
        if ($s.privacy.redactionScheme -isnot [string] -or $s.privacy.redactionScheme -cnotmatch '^[A-Za-z0-9-]{1,32}\z' -or $s.privacy.redactionVersion -isnot [long] -or $s.privacy.redactionVersion -lt 1) { throw 'InvalidSnapshot' }
        Assert-DeltaDigest $s.privacy.keyId
        $fields=@('powerShellVersion','workingDirectory','path','psModulePath','pathExt','moduleAutoLoadingPreference')
        Assert-DeltaKeys $s.observations $fields
        foreach ($field in $fields) { Assert-DeltaSnapshotObservation $s.observations[$field] $field }
        if ($s.commands -isnot [array]) { throw 'InvalidSnapshot' }
        foreach ($command in $s.commands) {
            Assert-DeltaKeys $command @('query','internalCandidates','externalCandidates','aliases','functions')
            Assert-DeltaToken $command.query 'command'
            foreach ($field in @('internalCandidates','externalCandidates','aliases','functions')) { Assert-DeltaSnapshotObservation $command[$field] $field }
        }
        return $s
    } catch { throw 'InvalidSnapshot' }
    finally { if ($null -ne $document) { $document.Dispose() } }
}
