function Get-DeltaStateDirectory {
    [IO.Path]::Combine([Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData), 'pwsh-session-delta')
}

function Test-DeltaAcl([string] $Path, [switch] $Directory) {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        try { $sid = $identity.User.Value } finally { $identity.Dispose() }
        $item = if ($Directory) { [IO.DirectoryInfo]::new($Path) } else { [IO.FileInfo]::new($Path) }
        $acl = [IO.FileSystemAclExtensions]::GetAccessControl($item)
        $owner = $acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
        # In elevated Windows processes, creating an object assigns BUILTIN\Administrators (S-1-5-32-544)
        # as the default owner instead of the specific user's SID. Allowing this group does not lower
        # security because elevation requires the user to already be an administrator. The ACL still
        # strictly blocks all other users and confines access.
        if ($owner -ne $sid -and $owner -ne 'S-1-5-32-544') { return $false }
        if ($Directory -and -not $acl.AreAccessRulesProtected) { return $false }
        $userAllowed = $false
        foreach ($rule in $acl.GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])) {
            if ($rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow) { return $false }
            if ($rule.IdentityReference.Value -notin @($sid,'S-1-5-18','S-1-5-32-544')) { return $false }
            if (($rule.IdentityReference.Value -eq $sid -or $rule.IdentityReference.Value -eq 'S-1-5-32-544') -and ($rule.FileSystemRights -band [Security.AccessControl.FileSystemRights]::FullControl) -eq [Security.AccessControl.FileSystemRights]::FullControl) { $userAllowed=$true }
        }
        return $userAllowed
    } catch { return $false }
}

function Get-DeltaSecret {
    $key = $null
    $createdKey=$false
    try {
        $directory = Get-DeltaStateDirectory
        $parent = [IO.Path]::GetDirectoryName($directory)
        if (-not (Test-DeltaLocalPath $parent -Directory)) { throw 'SecretUnavailable' }
        $file = [IO.Path]::Combine($directory,'redaction-v1.key')
        $idFile=[IO.Path]::Combine($directory,'redaction-v1.id')
        if (-not [IO.Directory]::Exists($directory)) {
            $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
            try { $sid = $identity.User } finally { $identity.Dispose() }
            $security = [Security.AccessControl.DirectorySecurity]::new()
            $security.SetOwner($sid)
            $security.SetAccessRuleProtection($true,$false)
            foreach ($principal in @($sid, [Security.Principal.SecurityIdentifier]::new('S-1-5-18'))) {
                $rule = [Security.AccessControl.FileSystemAccessRule]::new($principal,'FullControl','ContainerInherit, ObjectInherit','None','Allow')
                $security.AddAccessRule($rule)
            }
            [void][IO.Directory]::CreateDirectory($directory)
            [IO.FileSystemAclExtensions]::SetAccessControl([IO.DirectoryInfo]::new($directory),$security)
            if (-not (Test-DeltaLocalPath $directory -Directory) -or -not (Test-DeltaAcl $directory -Directory)) { throw 'SecretUnavailable' }
            $key = [byte[]]::new(32)
            $random=[Security.Cryptography.RandomNumberGenerator]::Create()
            try { $random.GetBytes($key) } finally { $random.Dispose() }
            # CreateNew and FileShare.None: never replace another session's key.
            try {
                $stream = [IO.FileStream]::new($file,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
                try { $stream.Write($key,0,$key.Length); $stream.Flush($true); $createdKey=$true } finally { $stream.Dispose() }
            } catch {
                # A competing creator may have won. Read it below; never overwrite.
                if (-not [IO.File]::Exists($file)) { throw 'SecretUnavailable' }
            } finally { [Array]::Clear($key,0,$key.Length); $key=$null }
        }
        # Existing directory is the minimal state marker. Missing key is fatal.
        if (-not (Test-DeltaLocalPath $directory -Directory) -or -not (Test-DeltaAcl $directory -Directory)) { throw 'SecretUnavailable' }
        if (-not (Test-DeltaLocalPath $file) -or -not (Test-DeltaAcl $file)) { throw 'SecretUnavailable' }
        $stream = [IO.FileStream]::new($file,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
        try {
            if ($stream.Length -ne 32) { throw 'SecretUnavailable' }
            $key = [byte[]]::new(32)
            if ($stream.Read($key,0,32) -ne 32) { throw 'SecretUnavailable' }
        } finally { $stream.Dispose() }
        $keyId=Get-DeltaDigest $key '' '' -KeyId
        if ($createdKey) {
            $stream=[IO.FileStream]::new($idFile,'CreateNew','Write','None')
            try { $bytes=[Text.Encoding]::ASCII.GetBytes($keyId); $stream.Write($bytes,0,$bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
        }
        if (-not (Test-DeltaLocalPath $idFile) -or -not (Test-DeltaAcl $idFile) -or
            [IO.FileInfo]::new($idFile).Length -ne 64 -or [IO.File]::ReadAllText($idFile) -cne $keyId) { throw 'SecretUnavailable' }
        return ,$key
    } catch {
        if ($null -ne $key) { [Array]::Clear($key,0,$key.Length) }
        throw 'SecretUnavailable'
    }
}
