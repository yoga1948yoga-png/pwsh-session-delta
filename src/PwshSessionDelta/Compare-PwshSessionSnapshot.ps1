function Compare-PwshSessionSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $ReferencePath,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string] $DifferencePath,
        [ValidateSet('Object','Json','Markdown')][string] $Format='Object'
    )
    # Resolving the caller's input filenames is not a diagnostic session lookup.
    # ReadAllText uses literal paths and is the only file read in this operation.
    try { $referenceFile=$PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($ReferencePath); $reference=Read-DeltaSnapshot $referenceFile }
    catch { throw [InvalidOperationException]::new('InvalidReferenceSnapshot') }
    try { $differenceFile=$PSCmdlet.SessionState.Path.GetUnresolvedProviderPathFromPSPath($DifferencePath); $difference=Read-DeltaSnapshot $differenceFile }
    catch { throw [InvalidOperationException]::new('InvalidDifferenceSnapshot') }
    $result=New-DeltaComparison $reference $difference
    switch ($Format) {
        'Json' { ConvertTo-Json -InputObject $result -Depth 32 }
        'Markdown' { ConvertTo-DeltaMarkdown $result }
        default { [pscustomobject]$result }
    }
}
