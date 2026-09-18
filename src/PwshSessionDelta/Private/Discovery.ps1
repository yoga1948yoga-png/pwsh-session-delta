function Get-DeltaCommandObservation([string] $Name, [byte[]] $Key, $PathExt, [bool] $CallerScopeVisible) {
    $result = [ordered]@{ query=(Get-DeltaToken $Key command $Name); internalCandidates=$null; externalCandidates=$null; aliases=$null; functions=$null }
    $invalid = [string]::IsNullOrWhiteSpace($Name)
    foreach ($character in $Name.ToCharArray()) {
        if ([char]::IsWhiteSpace($character) -or [char]::IsControl($character) -or $character -in @('\','/',':',';','|','&','>','<','"',"'")) { $invalid=$true }
    }
    if ($invalid) {
        foreach ($field in 'internalCandidates','externalCandidates','aliases','functions') { $result[$field]=New-DeltaObservation -ReasonCode UnsupportedCommandForm }
        return [pscustomobject]$result
    }
    # Explicitly qualified releases only; future patch/minor versions remain unknown.
    $qualifiedVersions = @('7.6.5', '7.6.6')
    if ($PSVersionTable.PSVersion.ToString() -cnotin $qualifiedVersions) {
        foreach ($field in 'internalCandidates','externalCandidates','aliases','functions') { $result[$field]=New-DeltaObservation -ReasonCode RuntimeNotQualified }
        return [pscustomobject]$result
    }
    $pattern = [System.Management.Automation.WildcardPattern]::Escape($Name) + '*'
    try {
        if (-not $CallerScopeVisible) { throw 'CallerScopeNotVisible' }
        # Restrict this branch to session commands so unsafe PATH does not stop aliases/functions.
        $internal = @(Microsoft.PowerShell.Core\Get-Command -Name $pattern -All -ListImported -CommandType Alias,Function,Filter,Cmdlet -ErrorAction Stop)
        $candidates=[Collections.Generic.List[object]]::new()
        $aliases=[Collections.Generic.List[object]]::new()
        $functions=[Collections.Generic.List[object]]::new()
        foreach ($command in $internal) {
            if (-not [string]::Equals($command.Name,$Name,[StringComparison]::OrdinalIgnoreCase)) { continue }
            $nameToken=Get-DeltaToken $Key command $command.Name
            $moduleToken=if ($command.ModuleName) { Get-DeltaToken $Key module $command.ModuleName } else { $null }
            $candidates.Add([pscustomobject]@{name=$nameToken;type=[string]$command.CommandType;module=$moduleToken})
            if ($command.CommandType -eq 'Alias') {
                $aliases.Add([pscustomobject]@{name=$nameToken;target=(Get-DeltaToken $Key alias-target $command.Definition)})
            } elseif ($command.CommandType -in 'Function','Filter') {
                $functions.Add([pscustomobject]@{name=$nameToken;definitionDigest=(Get-DeltaDigest $Key function $command.Definition)})
            }
        }
        $result.internalCandidates=New-DeltaObservation -Value @($candidates) -Absent:($candidates.Count -eq 0)
        $result.aliases=New-DeltaObservation -Value @($aliases) -Absent:($aliases.Count -eq 0)
        $result.functions=New-DeltaObservation -Value @($functions) -Absent:($functions.Count -eq 0)
    } catch {
        $reason=if ($CallerScopeVisible) { 'LookupFailed' } else { 'CallerScopeNotVisible' }
        foreach ($field in 'internalCandidates','aliases','functions') { $result[$field]=New-DeltaObservation -ReasonCode $reason }
    }
    $externalReason=$null
    if ($Name.IndexOfAny([char[]]'*?[]`') -ge 0) { $externalReason='LiteralExternalNameNotQualified' }
    elseif ($PathExt.status -eq 'Unable to determine') { $externalReason='InvalidPathExt' }
    else {
        try {
            $rawPath=[Environment]::GetEnvironmentVariable('PATH','Process')
            if ($null -ne $rawPath) {
                foreach ($entry in $rawPath.Split(';',[StringSplitOptions]::None)) {
                    if (-not (Test-DeltaLocalPath $entry -Directory)) { $externalReason='UnsafeSearchPath'; break }
                }
            }
        } catch { $externalReason='UnsafeSearchPath' }
    }
    if ($externalReason) { $result.externalCandidates=New-DeltaObservation -ReasonCode $externalReason }
    else {
        try {
            $external=@(Microsoft.PowerShell.Core\Get-Command -Name $pattern -All -ListImported -CommandType Application,ExternalScript -ErrorAction Stop)
            $candidates=[Collections.Generic.List[object]]::new()
            foreach ($command in $external) {
                $match=[string]::Equals($command.Name,$Name,[StringComparison]::OrdinalIgnoreCase)
                if (-not $match -and -not [IO.Path]::HasExtension($Name)) {
                    foreach ($extension in @($PathExt.value) + @('.ps1')) {
                        if ($extension -and [string]::Equals($command.Name,$Name+$extension,[StringComparison]::OrdinalIgnoreCase)) { $match=$true }
                    }
                }
                if (-not $match) { continue }
                if (-not (Test-DeltaLocalPath $command.Path)) { throw 'UnsafeSearchPath' }
                $candidates.Add([pscustomobject]@{name=(Get-DeltaToken $Key command $command.Name);type=[string]$command.CommandType;path=(Get-DeltaToken $Key path $command.Path)})
            }
            $result.externalCandidates=New-DeltaObservation -Value @($candidates) -Absent:($candidates.Count -eq 0)
        } catch { $result.externalCandidates=New-DeltaObservation -ReasonCode LookupFailed }
    }
    [pscustomobject]$result
}
