# pwsh-session-delta

A local-first PowerShell 7 tool that captures privacy-aware snapshots inside two Windows PowerShell sessions and reports observable differences that may affect command resolution, without claiming root cause.

## Why

A command may look different in a terminal, IDE terminal, or coding-agent shell. Capture inside each actual session, then compare the files offline. Differences are observations, not proof of causation.

## What it compares

PowerShell version; current directory; candidates for user-specified commands; same-name aliases; function definition digests; process PATH, PSModulePath, PATHEXT, and PSModuleAutoLoadingPreference.

Path sequences preserve ordering, duplicates and empty entries. Candidate collections preserve multiplicity but have no execution-priority meaning.

It does not run targets (including --help/--version), autoload target modules for discovery, infer a winner, fix problems, scan all environment variables, change the registry, or require administrator access. No server, upload, telemetry, GUI, AI, or full-system/network diagnosis is included.

## Validated environments

Validated on Windows ARM64 with PowerShell 7.6.5 and 7.6.6.

Only these exact runtimes are qualified for command discovery. Other versions return RuntimeNotQualified for command observations. Other Windows architectures may be compatible but are unverified. Linux, macOS, WSL and Windows PowerShell 5.1 are outside scope. The manifest's PowerShellVersion=7.0 is a loading minimum, not a compatibility certification.

This is an unpublished source project. Automated gates passed; a user-reported manual two-session check passed on Windows ARM64 / 7.6.6. See [evidence](docs/stage5-prepublication-audit.md). Version metadata is prepared for 0.1.0; no release or Gallery package has been published.

## Install from a local source checkout

Obtain a source checkout and open PowerShell in its root directory. No build step is needed:

```powershell
$PSVersionTable.PSVersion
Import-Module .\src\PwshSessionDelta\PwshSessionDelta.psd1 -Force
```

Runtime dependencies are PowerShell's bundled .NET and Microsoft.PowerShell.Utility. Pester is a development dependency. There is no published package to install yet.

## Quick start: Session A / Session B

Open two independent PowerShell windows. Run these commands at each top-level prompt from the checkout directory. Use identical CommandName spelling in both sessions. Existing snapshot files are never overwritten; choose fresh names when repeating the example.

Session A:

```powershell
Import-Module .\src\PwshSessionDelta\PwshSessionDelta.psd1 -Force
Export-PwshSessionSnapshot -CommandName git,pwsh `
    -LiteralPath (Join-Path $env:TEMP 'A.snapshot.json')
```

Session B:

```powershell
Import-Module .\src\PwshSessionDelta\PwshSessionDelta.psd1 -Force
Export-PwshSessionSnapshot -CommandName git,pwsh `
    -LiteralPath (Join-Path $env:TEMP 'B.snapshot.json')
```

In either imported session:

```powershell
$inputs = @{
    ReferencePath = Join-Path $env:TEMP 'A.snapshot.json'
    DifferencePath = Join-Path $env:TEMP 'B.snapshot.json'
}
$result = Compare-PwshSessionSnapshot @inputs
$result.summary
Compare-PwshSessionSnapshot @inputs -Format Json
Compare-PwshSessionSnapshot @inputs -Format Markdown
```

Paths use literal-path semantics. Export writes JSON and returns redacted observations. Compare returns an object or formatted string; it does not write files or read the local secret. The tool never creates Session B for you.

## Output and three-state semantics

| Result | Meaning |
| --- | --- |
| Confirmed difference | Complete comparable observations differ |
| No observed difference | Complete comparable observations are equal |
| Unable to determine | Observations are incomplete or identities cannot safely be compared |

Two unknown observations are not equal. Explicit absence is distinct from unknown. Invalid JSON, missing fields, unsupported snapshot structures, or unreadable files cause terminating errors.

The [synthetic JSON example](docs/example-comparison.json) contains:

```json
{"status":"Confirmed difference","confirmedDifferences":2,"noObservedDifferences":7,"unableToDetermine":1}
```

The corresponding [Markdown example](docs/example-comparison.md) lists version/candidate differences and PATH uncertainty. These are synthetic examples, not user snapshots. Counts describe observation leaves, not a count or ranking of problems.

## Privacy

Local-first: snapshots are redacted by default and never uploaded. HMAC-SHA256 protects command/path/module identities, alias targets and function definitions. Full Function source is not saved.

A random secret is created under the current Windows user's LocalApplicationData/pwsh-session-delta directory, with a protected ACL. It never enters snapshots or reports. Snapshots carry scheme/version and a non-secret keyId. The same user on the same machine using the same secret obtains stable identities; cross-user/cross-machine compatibility is not guaranteed.

Missing, unreadable, damaged or insecure existing key state stops Export. No silent key replacement or plaintext fallback occurs. Do not delete key state as a repair shortcut. Compare only reads its two input snapshots; incompatible private identities become unknown while independent fields remain comparable.

Pseudonyms still reveal equality, order, counts and some session metadata. Preview reports before sharing. Redaction is not a promise of anonymity or zero risk. Never share the key directory.

## Safe command discovery

Discovery escapes literal input, adds its own wildcard, uses Get-Command -All -ListImported with restricted command types, then filters exact names and supported extension associations. It does not fall back to exact Get-Command, which can autoload a module. Unloaded module candidates are outside the policy. Targets are never invoked.

Candidate order is not a winner. No candidate observed does not prove global absence or inability to execute. See [research](docs/command-discovery-research.md) and [scope](PROJECT-SCOPE.md).

## Known limitations

- Only Windows ARM64 and the two listed PowerShell versions are validated.
- Schema 1 query identity hashes original spelling. Use identical CommandName spelling in A/B; different tokens cannot be recovered and case-folded offline.
- Special-character external names can have discovery omissions and conservatively return unknown.
- Relative, empty, inaccessible, network or unsafe PATH entries can prevent external discovery. Caller-local scopes may yield unknown; capture at the actual top-level prompt.
- Cross-key command queries cannot be reliably paired; cross-machine/user identities are not guaranteed compatible.
- Only recorded fields are compared. Captures are sequential, not atomic; equal paths/digests do not prove equal behavior.
- No winner/root-cause inference, input authenticity certification or hostile-session sandbox is provided.

## Testing

In a qualified, non-administrator Windows shell:

```powershell
Install-Module Pester -RequiredVersion 5.9.0 -Scope CurrentUser -Repository PSGallery
New-Item -ItemType Directory -Path .\artifacts -Force | Out-Null
.\tests\Invoke-Stage3Tests.ps1 -ResultPath .\artifacts\test-results.json
```

You can instead pass -PesterManifest for an existing local Pester 5.9.0 installation; see [test instructions](tests/README.md). Tests use temporary fixtures. Positive controls deliberately exercise test fixtures in disposable processes; product negative controls do not execute diagnostic targets.

The [CI workflow](.github/workflows/test.yml) pins PowerShell 7.6.6 and Pester 5.9.0 on Windows ARM64. It has not run on GitHub yet. Hosted Windows runners are elevated, so non-administrator behavior and manual real-session verification remain local release gates even if CI passes.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md). Keep changes focused and preserve privacy/no-execution/no-autoload contracts. Primary Maintainer: laweit-lxy.

## Security

Follow [SECURITY.md](SECURITY.md) for private reporting. Do not put real snapshots, private paths or secrets in public issues.

## License

MIT License; see [LICENSE](LICENSE).