function New-DeltaObservation($Value, [string] $ReasonCode, [switch] $Absent) {
    $status = 'Confirmed observation'
    if ($ReasonCode) { $status = 'Unable to determine'; $Value = $null }
    elseif ($Absent) { $status = 'No observed value'; $Value = $null }
    [pscustomobject][ordered]@{ status=$status; reasonCode=$(if ($ReasonCode) { $ReasonCode } else { $null }); value=$Value }
}

function Test-DeltaCallerScope {
    $scriptBlockFrames=0
    foreach ($frame in @(Microsoft.PowerShell.Utility\Get-PSCallStack)) {
        if ($frame.FunctionName -in 'Test-DeltaCallerScope','Export-PwshSessionSnapshot') { continue }
        # A module cannot promise visibility into a caller function/script's private locals.
        if ($frame.ScriptName -or $frame.FunctionName -ne '<ScriptBlock>') { return $false }
        $scriptBlockFrames++
    }
    return ($scriptBlockFrames -le 1)
}

function Get-DeltaDigest([byte[]] $Key, [string] $Domain, [AllowEmptyString()][string] $Text, [switch] $KeyId) {
    $hmac = [Security.Cryptography.HMACSHA256]::new($Key)
    try {
        $inputText = if ($KeyId) { 'pwsh-session-delta:key-id:v1' } else { "pwsh-session-delta:redaction:v1`0$Domain`0$Text" }
        [BitConverter]::ToString($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($inputText))).Replace('-','').ToLowerInvariant()
    } finally { $hmac.Dispose() }
}

function Get-DeltaToken([byte[]] $Key, [string] $Kind, [AllowEmptyString()][string] $Text) {
    [pscustomobject][ordered]@{ kind=$Kind; digest=(Get-DeltaDigest $Key $Kind $Text) }
}

function Get-DeltaEnvironment([string] $Name, [byte[]] $Key, [switch] $Extensions) {
    try {
        $raw = [Environment]::GetEnvironmentVariable($Name, [EnvironmentVariableTarget]::Process)
        if ($null -eq $raw) { return (New-DeltaObservation -Absent) }
        $items = [Collections.Generic.List[object]]::new()
        foreach ($part in $raw.Split(';', [StringSplitOptions]::None)) {
            if ($Extensions) {
                if ($part -ne '' -and $part -notmatch '^\.[A-Za-z0-9]+$') { return (New-DeltaObservation -ReasonCode InvalidPathExt) }
                $items.Add($part)
            } else { $items.Add((Get-DeltaToken $Key path $part)) }
        }
        New-DeltaObservation -Value @($items)
    } catch { New-DeltaObservation -ReasonCode EnvironmentReadFailed }
}

# Read only local fixed-drive paths; reject links before following them.
# Missing paths, relative entries and empty PATH entries cannot be qualified.
function Test-DeltaLocalPath([string] $Path, [switch] $Directory) {
    try {
        if ($Path -notmatch '^[A-Za-z]:[\\/]') { return $false }
        $full = [IO.Path]::GetFullPath($Path)
        if ([IO.DriveInfo]::new([IO.Path]::GetPathRoot($full)).DriveType -ne [IO.DriveType]::Fixed) { return $false }
        $walk = [IO.Path]::GetPathRoot($full)
        foreach ($part in $full.Substring($walk.Length).Split([char]'\', [StringSplitOptions]::RemoveEmptyEntries)) {
            $walk = [IO.Path]::Combine($walk, $part)
            if (([IO.File]::GetAttributes($walk) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
        }
        if ($Directory) {
            if (-not [IO.Directory]::Exists($full)) { return $false }
            # Force a bounded access check; discard the first directory entry.
            $enumerator = [IO.Directory]::EnumerateFileSystemEntries($full).GetEnumerator()
            try { $null = $enumerator.MoveNext() } finally { $enumerator.Dispose() }
        }
        return $true
    } catch { return $false }
}
