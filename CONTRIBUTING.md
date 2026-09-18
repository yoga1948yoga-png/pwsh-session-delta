# Contributing

Primary Maintainer: laweit-lxy. This is a small project maintained by a beginner; keep changes easy to explain and review. No CLA, committee or formal RFC process is required.

## Development

Once a public repository exists, fork it, clone your fork using its actual URL, and create a focused branch. Until then, use a local source checkout; no repository URL is advertised yet.

Use Windows and PowerShell 7.6.5 or 7.6.6. Current validation covers ARM64 only. Import src/PwshSessionDelta/PwshSessionDelta.psd1 directly; no build system is needed.

Run the complete suite in a non-administrator shell from the project root:

```powershell
Install-Module Pester -RequiredVersion 5.9.0 -Scope CurrentUser -Repository PSGallery
New-Item -ItemType Directory -Path .\artifacts -Force | Out-Null
.\tests\Invoke-Stage3Tests.ps1 -ResultPath .\artifacts\test-results.json
```

Or pass -PesterManifest for an existing local Pester 5.9.0 manifest. The runner never installs dependencies. See tests/README.md for individual suites and CI/local-gate differences.

## Issues and PRs

- For ordinary bugs, include version/architecture, minimal synthetic reproduction, expected/actual observations and sanitized error codes. Preview attachments. Never commit real user snapshots, secrets, private paths or Function source.
- For feature requests, explain the problem and why existing observed fields are insufficient. Discuss scope before implementing large changes.
- Keep PRs small and focused. Explain the reason, resulting behavior and tests. New behavior needs meaningful Pester tests. Check examples and links for documentation edits.
- Preserve privacy, no-execution, no-autoload, ACL and no-overwrite contracts. Discovery/runtime qualification changes require reproducible evidence and full release tests; never enable future versions speculatively.
- Preserve schema compatibility and conservative unknown results. Do not add winner or root-cause inference.
- Use test-owned temporary directories, bounded subprocesses and cleanup. Do not add opaque binaries or product runtime dependencies for testing.

Security-sensitive reports follow SECURITY.md privately, not a public issue. The maintainer reviews changes directly.
