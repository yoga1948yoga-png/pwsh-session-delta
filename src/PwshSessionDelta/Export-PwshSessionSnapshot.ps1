function Export-PwshSessionSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string[]] $CommandName,
        [Parameter(Mandatory)][string] $LiteralPath
    )
    $key=$null
    $failure='InvalidOutputPath'
    $callerScopeVisible=Test-DeltaCallerScope
    try {
        if ($CommandName.Count -eq 0) { throw 'InvalidOutputPath' }
        $provider=$null; $drive=$null
        $outputPath=$PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($LiteralPath,[ref]$provider,[ref]$drive)
        if ($provider.Name -ne 'FileSystem') { throw 'InvalidOutputPath' }
        $parent=[IO.Path]::GetDirectoryName($outputPath)
        $stateDirectory=Get-DeltaStateDirectory
        if ($outputPath.StartsWith($stateDirectory.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or
            [string]::Equals($outputPath,$stateDirectory,[StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-DeltaLocalPath $parent -Directory)) { throw 'InvalidOutputPath' }
        if ([IO.File]::Exists($outputPath) -or [IO.Directory]::Exists($outputPath)) { $failure='OutputExists'; throw 'OutputExists' }
        $failure='SecretUnavailable'
        $key=Get-DeltaSecret
        $failure='SnapshotWriteFailed'
        $pathExt=Get-DeltaEnvironment PATHEXT $key -Extensions
        $pathObservation=Get-DeltaEnvironment PATH $key
        $modulePathObservation=Get-DeltaEnvironment PSModulePath $key
        try {
            $location=$PSCmdlet.SessionState.Path.CurrentLocation
            $cwd=if ($location.Provider.Name -eq 'FileSystem') { New-DeltaObservation -Value (Get-DeltaToken $key path $location.Path) } else { New-DeltaObservation -ReasonCode LocationUnavailable }
        } catch { $cwd=New-DeltaObservation -ReasonCode LocationUnavailable }
        try {
            if (-not $callerScopeVisible) { throw 'PreferenceUnavailable' }
            $preference=$PSCmdlet.SessionState.PSVariable.Get('PSModuleAutoLoadingPreference')
            $explicit=$null -ne $preference
            $effective=if ($explicit) { [string]$preference.Value } else { 'All' }
            if ($effective -notin 'All','None','ModuleQualified') { throw 'PreferenceUnavailable' }
            $autoLoad=New-DeltaObservation -Value ([pscustomobject]@{explicitlySet=$explicit;effectiveValue=$effective})
        } catch { $autoLoad=New-DeltaObservation -ReasonCode PreferenceUnavailable }
        $commands=[Collections.Generic.List[object]]::new()
        foreach ($name in $CommandName) { $commands.Add((Get-DeltaCommandObservation $name $key $pathExt $callerScopeVisible)) }
        $snapshot=[pscustomobject][ordered]@{
            schemaVersion=1
            capture=[pscustomobject]@{model='current-session';discoveryPolicyVersion=1}
            privacy=[pscustomobject]@{redactionScheme='HMAC-SHA256';redactionVersion=1;keyId=(Get-DeltaDigest $key '' '' -KeyId)}
            observations=[pscustomobject][ordered]@{
                powerShellVersion=(New-DeltaObservation -Value $PSVersionTable.PSVersion.ToString())
                workingDirectory=$cwd
                path=$pathObservation
                psModulePath=$modulePathObservation
                pathExt=$pathExt
                moduleAutoLoadingPreference=$autoLoad
            }
            commands=@($commands)
        }
        $json=Microsoft.PowerShell.Utility\ConvertTo-Json -InputObject $snapshot -Depth 16 -ErrorAction Stop
        Write-DeltaSnapshotFile $json $outputPath
        # Return only the same redacted plain object, never FileInfo or a secret path.
        $snapshot
    } catch {
        $record=[Management.Automation.ErrorRecord]::new([InvalidOperationException]::new($failure),$failure,[Management.Automation.ErrorCategory]::InvalidOperation,$null)
        $PSCmdlet.ThrowTerminatingError($record)
    } finally {
        if ($null -ne $key) { [Array]::Clear($key,0,$key.Length) }
    }
}
