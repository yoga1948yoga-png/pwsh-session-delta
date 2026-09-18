function Publish-DeltaSnapshotFile([string] $Temporary, [string] $Destination) {
    [IO.File]::Move($Temporary,$Destination,$false)
}

function Write-DeltaSnapshotFile([string] $Json, [string] $Destination) {
    # Explicit output folder, never an implicit working-directory/repository default.
    $temporary=[IO.Path]::Combine([IO.Path]::GetDirectoryName($Destination),'.pwsh-session-delta-'+[guid]::NewGuid().ToString('N')+'.tmp')
    try {
        $stream=[IO.FileStream]::new($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try {
            $bytes=[Text.UTF8Encoding]::new($false).GetBytes($Json)
            $stream.Write($bytes,0,$bytes.Length)
            $stream.Flush($true)
        } finally { $stream.Dispose() }
        Publish-DeltaSnapshotFile $temporary $Destination
    } finally {
        # This is our exact unique staging file, not a directory or wildcard cleanup.
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}
