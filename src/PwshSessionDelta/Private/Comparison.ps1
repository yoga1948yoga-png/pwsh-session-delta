function ConvertTo-DeltaCanonical($Value) {
    if ($Value -is [System.Collections.IDictionary]) {
        $ordered=[ordered]@{}
        $keys=[string[]]@($Value.Keys); [Array]::Sort($keys,[StringComparer]::Ordinal)
        foreach ($key in $keys) { $ordered[$key]=ConvertTo-DeltaCanonical $Value[$key] }
        return ,$ordered
    }
    if ($Value -is [array]) { return ,@($Value | ForEach-Object { ConvertTo-DeltaCanonical $_ }) }
    return $Value
}
function Get-DeltaCanonicalJson($Value) {
    ConvertTo-Json -InputObject (ConvertTo-DeltaCanonical $Value) -Depth 32 -Compress
}
function Get-DeltaBag($Values) {
    $bag=[System.Collections.Generic.Dictionary[string,int]]::new([StringComparer]::Ordinal)
    foreach ($value in $Values) {
        # All and only schema-v1 identity fields, in canonical property order.
        $identity=Get-DeltaCanonicalJson $value
        if ($bag.ContainsKey($identity)) { $bag[$identity]++ } else { $bag.Add($identity,1) }
    }
    return ,$bag
}
function Compare-DeltaBags($Reference, $Difference) {
    $a=Get-DeltaBag $Reference; $b=Get-DeltaBag $Difference
    $keys=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($key in $a.Keys) { $null=$keys.Add($key) }; foreach ($key in $b.Keys) { $null=$keys.Add($key) }
    $sorted=[string[]]@($keys); [Array]::Sort($sorted,[StringComparer]::Ordinal)
    $aOnly=@(); $bOnly=@(); $both=@()
    foreach ($key in $sorted) {
        $ac=0; $bc=0; $null=$a.TryGetValue($key,[ref]$ac); $null=$b.TryGetValue($key,[ref]$bc)
        $common=[Math]::Min($ac,$bc)
        $identity=ConvertFrom-Json -InputObject $key -AsHashtable
        if ($common) { $both+=@{identity=$identity;count=$common} }
        if ($ac -gt $common) { $aOnly+=@{identity=$identity;count=$ac-$common} }
        if ($bc -gt $common) { $bOnly+=@{identity=$identity;count=$bc-$common} }
    }
    return [ordered]@{referenceOnly=$aOnly;differenceOnly=$bOnly;both=$both}
}
function Get-DeltaObservationSummary($Observation) {
    if ($null -eq $Observation) { return $null }
    # Observation values are represented by field values or bag details, not duplicated here.
    return [ordered]@{status=$Observation.status;reasonCode=$Observation.reasonCode}
}
function Compare-DeltaObservation($Reference, $Difference, [string] $Category, [bool] $IdentityCompatible, [bool] $Bag=$false) {
    $result=[ordered]@{category=$Category;status=$null;reference=(Get-DeltaObservationSummary $Reference);difference=(Get-DeltaObservationSummary $Difference);reasonCode=$null;explanation=$null;details=$null}
    if ($Reference.status -eq 'Unable to determine' -or $Difference.status -eq 'Unable to determine') {
        $result.status='Unable to determine'; $result.reasonCode='ObservationUnknown'; $result.explanation='At least one observation is incomplete.'
    } elseif ($Reference.status -eq 'No observed value' -or $Difference.status -eq 'No observed value') {
        if ($Reference.status -eq $Difference.status) {
            $result.status='No observed difference'; $result.reasonCode='BothAbsent'; $result.explanation='Both observations explicitly record absence.'
        } else {
            $result.status='Confirmed difference'; $result.reasonCode='PresenceChanged'; $result.explanation='One observation records presence; the other records absence.'
            if ($Bag -and $IdentityCompatible) {
                $aValues=@(); $bValues=@()
                if ($Reference.status -eq 'Confirmed observation') { $aValues=$Reference.value }
                if ($Difference.status -eq 'Confirmed observation') { $bValues=$Difference.value }
                $result.details=Compare-DeltaBags $aValues $bValues
            }
        }
    } elseif (-not $IdentityCompatible) {
        $result.status='Unable to determine'; $result.reasonCode='PrivacyIdentityIncompatible'; $result.explanation='These values require a shared supported redaction identity.'
    } else {
        if ($Bag) {
            $result.details=Compare-DeltaBags $Reference.value $Difference.value
            $equal=$result.details.referenceOnly.Count -eq 0 -and $result.details.differenceOnly.Count -eq 0
        } else {
            $equal=(Get-DeltaCanonicalJson $Reference.value) -ceq (Get-DeltaCanonicalJson $Difference.value)
            $result.details=[ordered]@{referenceValue=$Reference.value;differenceValue=$Difference.value}
        }
        if ($equal) { $result.status='No observed difference'; $result.reasonCode='ValuesEqual'; $result.explanation='The recorded values are equal under this comparison policy.' }
        else { $result.status='Confirmed difference'; $result.reasonCode='ValuesDifferent'; $result.explanation='The recorded values differ under this comparison policy.' }
    }
    return $result
}
function Get-DeltaCommandGroups($Commands) {
    $groups=[System.Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach ($command in $Commands) {
        $key=$command.query.digest
        if (-not $groups.ContainsKey($key)) { $groups[$key]=[System.Collections.Generic.List[object]]::new() }
        $groups[$key].Add($command)
    }
    return ,$groups
}
function Test-DeltaDuplicateConsistency($Group) {
    if ($null -eq $Group -or $Group.Count -le 1) { return $true }
    foreach ($command in $Group) {
        foreach ($field in @('internalCandidates','externalCandidates','aliases','functions')) {
            $a=$Group[0][$field]; $b=$command[$field]
            if ($a.status -cne $b.status -or $a.reasonCode -cne $b.reasonCode) { return $false }
            if ($a.status -eq 'Confirmed observation') {
                $bag=Compare-DeltaBags $a.value $b.value
                if ($bag.referenceOnly.Count -or $bag.differenceOnly.Count) { return $false }
            }
        }
    }
    return $true
}
function New-DeltaComparison($Reference, $Difference) {
    $privacyCompatible=$Reference.privacy.redactionScheme -ceq 'HMAC-SHA256' -and $Reference.privacy.redactionVersion -eq 1 -and (Get-DeltaCanonicalJson $Reference.privacy) -ceq (Get-DeltaCanonicalJson $Difference.privacy)
    $fields=@(); $commands=@(); $leaves=[System.Collections.Generic.List[object]]::new()
    foreach ($field in @('powerShellVersion','workingDirectory','path','psModulePath','pathExt','moduleAutoLoadingPreference')) {
        $compatible=$privacyCompatible -or $field -in @('powerShellVersion','pathExt','moduleAutoLoadingPreference')
        $leaf=Compare-DeltaObservation $Reference.observations[$field] $Difference.observations[$field] $field $compatible
        $fields+=,$leaf; $leaves.Add($leaf)
    }
    $a=Get-DeltaCommandGroups $Reference.commands; $b=Get-DeltaCommandGroups $Difference.commands
    $keys=[System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($key in $a.Keys) { $null=$keys.Add($key) }; foreach ($key in $b.Keys) { $null=$keys.Add($key) }
    $sorted=[string[]]@($keys); [Array]::Sort($sorted,[StringComparer]::Ordinal)
    foreach ($key in $sorted) {
        $ag=$null; $bg=$null; $null=$a.TryGetValue($key,[ref]$ag); $null=$b.TryGetValue($key,[ref]$bg)
        $reason=$null
        if (-not $privacyCompatible) { $reason='PrivacyIdentityIncompatible' }
        elseif ($null -eq $ag -or $null -eq $bg) { $reason='QueryNotCapturedBothSides' }
        elseif (-not (Test-DeltaDuplicateConsistency $ag) -or -not (Test-DeltaDuplicateConsistency $bg)) { $reason='ConflictingDuplicateQuery' }
        $results=@()
        if ($reason) {
            $results+=,[ordered]@{category='query';status='Unable to determine';reference=$null;difference=$null;reasonCode=$reason;explanation='A reliable pair of command observations could not be established.';details=$null}
        } else {
            foreach ($field in @('internalCandidates','externalCandidates','aliases','functions')) { $results+=,(Compare-DeltaObservation $ag[0][$field] $bg[0][$field] $field $true $true) }
        }
        foreach ($leaf in $results) { $leaves.Add($leaf) }
        $commands+=,[ordered]@{queryDigest=$key;referenceOccurrences=$(if ($null -eq $ag) {0} else {$ag.Count});differenceOccurrences=$(if ($null -eq $bg) {0} else {$bg.Count});results=$results}
    }
    $confirmed=0; $equal=0; $unknown=0
    foreach ($leaf in $leaves) {
        switch ($leaf.status) { 'Confirmed difference' {$confirmed++} 'No observed difference' {$equal++} 'Unable to determine' {$unknown++} }
    }
    $status=if ($confirmed) {'Confirmed difference'} elseif ($unknown) {'Unable to determine'} else {'No observed difference'}
    # Only projected schema metadata, never filenames or complete source snapshots.
    return [ordered]@{
        comparisonSchemaVersion=1
        reference=[ordered]@{snapshotSchemaVersion=$Reference.schemaVersion;discoveryPolicyVersion=$Reference.capture.discoveryPolicyVersion;privacy=$Reference.privacy}
        difference=[ordered]@{snapshotSchemaVersion=$Difference.schemaVersion;discoveryPolicyVersion=$Difference.capture.discoveryPolicyVersion;privacy=$Difference.privacy}
        summary=[ordered]@{status=$status;confirmedDifferences=$confirmed;noObservedDifferences=$equal;unableToDetermine=$unknown}
        fieldResults=$fields;commandResults=$commands
        notes=@('Differences are observations, not proof of causation.','Candidate-only policy: no execution winner is inferred.','Query identities are case-sensitive input HMACs in snapshot schema 1. Unmatched queries are not candidate differences.','Presence and absence can be compared without comparing private values. Unpaired queries cannot be associated across incompatible keys.')
    }
}
function ConvertTo-DeltaMarkdownText([string] $Text) {
    return $Text.Replace('&','&amp;').Replace('<','&lt;').Replace('>','&gt;').Replace('|','&#124;').Replace('`','&#96;').Replace('[','&#91;').Replace(']','&#93;').Replace('*','&#42;').Replace('_','&#95;').Replace("`r",' ').Replace("`n",' ')
}
function Format-DeltaFieldValue($Value) {
    if ($Value -is [array]) {
        $parts=@(); $index=0
        foreach ($item in $Value) { $parts+=('['+$index+'] '+(Format-DeltaFieldValue $item)); $index++ }
        return $parts -join '; '
    }
    if ($Value -is [System.Collections.IDictionary]) {
        if ($Value.Contains('digest')) { return $Value.kind+':'+$Value.digest }
        return ('effectiveValue={0}; explicitlySet={1}' -f $Value.effectiveValue,$Value.explicitlySet)
    }
    if ($Value -ceq '') { return '(empty entry)' }
    return ConvertTo-DeltaMarkdownText ([string]$Value)
}
function Format-DeltaObservationPair($Leaf) {
    if ($null -eq $Leaf.reference -or $null -eq $Leaf.difference) { return $null }
    $a=$Leaf.reference.status; $b=$Leaf.difference.status
    if ($Leaf.reference.reasonCode) { $a+=' / '+$Leaf.reference.reasonCode }
    if ($Leaf.difference.reasonCode) { $b+=' / '+$Leaf.difference.reasonCode }
    return 'Reference: '+$a+'; Difference: '+$b+'.'
}
function ConvertTo-DeltaMarkdown($Result) {
    $lines=[System.Collections.Generic.List[string]]::new()
    $lines.Add('# PowerShell session comparison'); $lines.Add('')
    $lines.Add('## Snapshot metadata'); $lines.Add('')
    foreach ($side in @('reference','difference')) {
        $metadata=$Result[$side]
        $lines.Add(('- {0}: schema {1}, discovery policy {2}, redaction {3} v{4}, keyId {5}' -f $side,$metadata.snapshotSchemaVersion,$metadata.discoveryPolicyVersion,(ConvertTo-DeltaMarkdownText $metadata.privacy.redactionScheme),$metadata.privacy.redactionVersion,$metadata.privacy.keyId))
    }
    $lines.Add(''); $lines.Add('## Summary'); $lines.Add('')
    $lines.Add(('Overall: {0}. Confirmed differences: {1}; No observed differences: {2}; Unable to determine: {3}.' -f $Result.summary.status,$Result.summary.confirmedDifferences,$Result.summary.noObservedDifferences,$Result.summary.unableToDetermine))
    foreach ($status in @('Confirmed difference','No observed difference','Unable to determine')) {
        $lines.Add(''); $lines.Add('## '+$status); $lines.Add('')
        $found=$false
        foreach ($field in $Result.fieldResults) {
            if ($field.status -eq $status) {
                $found=$true; $lines.Add(('- {0}: {1} ({2})' -f $field.category,$field.explanation,$field.reasonCode))
                if ($field.reasonCode -in @('ObservationUnknown','PresenceChanged')) { $lines.Add('  - '+(Format-DeltaObservationPair $field)) }
                if ($field.status -eq 'Confirmed difference' -and $null -ne $field.details) {
                    $lines.Add('  - Reference: '+(Format-DeltaFieldValue $field.details.referenceValue))
                    $lines.Add('  - Difference: '+(Format-DeltaFieldValue $field.details.differenceValue))
                }
            }
        }
        if (-not $found) { $lines.Add('No session fields in this category.') }
    }
    $lines.Add(''); $lines.Add('## Command observations'); $lines.Add('')
    foreach ($command in $Result.commandResults) {
        $lines.Add(('### Query {0}' -f $command.queryDigest)); $lines.Add('')
        $lines.Add(('Captured occurrences: reference {0}, difference {1}.' -f $command.referenceOccurrences,$command.differenceOccurrences)); $lines.Add('')
        foreach ($leaf in $command.results) {
            $lines.Add(('- {0}: {1} — {2} ({3})' -f $leaf.category,$leaf.status,$leaf.explanation,$leaf.reasonCode))
            if ($leaf.reasonCode -in @('ObservationUnknown','PresenceChanged')) { $lines.Add('  - '+(Format-DeltaObservationPair $leaf)) }
            if ($null -ne $leaf.details) {
                foreach ($side in @('referenceOnly','differenceOnly','both')) {
                    foreach ($entry in $leaf.details[$side]) {
                        # Flat identity labels, not a JSON dump or a priority list.
                        $parts=@()
                        foreach ($key in @('type','name','module','path','target','definitionDigest')) {
                            if ($entry.identity.Contains($key)) {
                                $value=$entry.identity[$key]
                                if ($value -is [System.Collections.IDictionary]) { $value=$value.digest }
                                if ($null -eq $value) { $value='none' }
                                $parts+=($key+'='+(ConvertTo-DeltaMarkdownText ([string]$value)))
                            }
                        }
                        $lines.Add(('  - {0}, count {1}: {2}' -f $side,$entry.count,($parts -join '; ')))
                    }
                }
            }
        }
        $lines.Add('')
    }
    $lines.Add('## Privacy and limitations'); $lines.Add('')
    foreach ($note in $Result.notes) { $lines.Add('- '+$note) }
    return $lines -join "`n"
}
