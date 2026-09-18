# Stage 5 — repository preparation

This stage prepares local source for public hosting, not a release. No remote, tag, package, release or push is created.

## Evidence and status

Stage 0–3 and 4.1 evidence is retained as historical engineering evidence. Older documents describe the status at their own stage; later completion is recorded here rather than rewriting historical test results. [Stage 4](stage4-manual-validation.md) is explicitly user-reported manual evidence: 4 confirmed differences, 14 equal observations, 0 unknown on Windows ARM64 / PowerShell 7.6.6.

Stage 5 reruns all 102 formal tests on the same validated 7.6.6 ARM64 installation without elevation. The actual machine-readable result is [stage5-test-results.json](stage5-test-results.json). Historical research results and synthetic examples remain useful, privacy-reviewed evidence; none are deleted merely to reduce file count.

Final local result: 102 total, 102 PASS, 0 FAIL, 0 SKIP. OS API version Microsoft Windows 10.0.26200; OS/process Arm64; PowerShell 7.6.6; Pester 5.9.0; elevated=false. Test fixture cleanup and final output privacy checks passed. Product source hashes did not change during the run; the only production-file preparation change before it was manifest metadata, not behavior.

## License and metadata

MIT is a small permissive license suitable for this source tool; its standard text is retained without extra restrictions or CLA. Copyright is 2026 laweit-lxy, using the existing Git public name, not a fabricated company or a private email. Text reference: [OSI MIT](https://opensource.org/license/mit).

Manifest: RootModule and GUID unchanged; ModuleVersion prepared as 0.1.0; Author/Copyright added; existing concise Description, PowerShellVersion=7.0 loading minimum, Core edition, Utility dependency and exactly two public exports retained. PrivateData only contains descriptive tags. ProjectUri and LicenseUri are omitted until real URLs exist. Version metadata does not publish anything.

## CI design and boundaries

One job, windows-11-arm, fixed PowerShell 7.6.6 ARM64 archive and Pester 5.9.0 package, both checked against fixed SHA-256. Checkout is pinned to its v4.2.2 commit; workflow token has contents:read only and checkout credentials are not persisted. Triggers are push, pull_request and manual dispatch; no pull_request_target, publishing, services, matrix, artifact upload or release permissions.

The runner's preinstalled PowerShell only bootstraps downloads; all product tests run with the explicit downloaded qualified executable. A manifest/import/export check precedes all four formal test files, including native positive/negative controls and CimCmdlets/ThreadJob positive/negative controls. No tests are removed or marked Skip for CI.

[GitHub runner documentation](https://docs.github.com/en/actions/reference/runners/github-hosted-runners) lists windows-11-arm and states Windows VMs are administrator/UAC-disabled. Therefore the test runner's explicit AllowElevatedTestHost switch permits that host solely for CI compatibility. Results record elevation and runKind; all test, skip, privacy and cleanup failures still fail the run. The default local command still rejects elevated runs. This is test orchestration, not a changed product requirement.

A11/A12 test bodies can run in this CI design, but hosted execution has not been performed because no remote exists. Non-admin behavior, real desktop sessions and final local release gates remain mandatory. Do not treat an eventual elevated CI pass as non-admin qualification. If host behavior breaks a fixture, investigate and retain the local gate; do not silently skip it.

Official fixed runtime asset: [PowerShell v7.6.6](https://github.com/PowerShell/PowerShell/releases/tag/v7.6.6). Workflow URLs/hash values were checked against release metadata; future versions never enter the product qualified set automatically.

## Hygiene and maintainability

The whole project is checked, including hidden workflow, source, tests, docs, JSON, Markdown and manifest. Local username/profile/TEMP/machine values, email and the specifically identified private home prefix are checked by value without writing those values into the report. Binary/key/log/temp/snapshot artifacts are inventoried. Known literal test data (synthetic private-path strings and intentionally public example keys) are distinguished from actual credentials.

No real user snapshots or redaction key files are intended for inclusion. .gitignore covers diagnostics, key/id files, transient logs/results and artifacts; reviewed docs examples/results remain visible. Historical research TEMP identifiers are generalized for public documentation while preserving experiment findings and the recorded cleanup limitation. Old research remnants are outside this project and are not imported or packaged.

The project remains source PowerShell plus Pester, with one small CI workflow. No build framework, runtime dependency, governance hierarchy, release automation or product logic refactor is added. The workflow's few fixed hashes/versions are explicit maintenance points.

Final audit covered all 48 public candidate files (including hidden workflow, excluding .git internals): no actual sensitive-value hits, no exe/dll/key/log/tmp or real snapshot artifacts, and no broken relative Markdown links. Ignore checks confirm artifacts/snapshots, snapshot suffixes, key and key-id files are excluded while reviewed docs examples and evidence are not ignored. No real secret or personal information was found to remove; a historical unique TEMP run identifier was generalized, not an experiment result. Source code's synthetic test strings remain intentional fixtures.

Both workflow run blocks parsed successfully as PowerShell. YAML/job/permissions/paths were statically reviewed; no hosted workflow success is claimed. Pester package hash matches the existing verified local package; PowerShell archive digest and checkout commit were checked against official GitHub metadata. Test-ModuleManifest succeeds with 0.1.0 and exactly the two expected exports.

## Git and publication boundary

The surrounding workspace had its own Git repository; it was not the project's standalone repository. A dedicated local repository is initialized in this project so unrelated workspace files cannot accidentally be published. No origin or other remote is configured, and no commit/tag/release is created during preparation. Final status is reviewed before any later publication step.

Creating the public repository is a later authorized action. Before accepting private vulnerability reports on GitHub, the maintainer must enable Private Vulnerability Reporting; SECURITY.md does not claim it exists already. No security email or project URL is invented.
