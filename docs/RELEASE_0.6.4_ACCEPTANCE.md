# NexRoute 0.6.4 release acceptance

This document separates automated evidence from checks that still require a real Windows machine or real field observations. A green hosted CI run is necessary, but it is not a substitute for the manual gates below.

## Scope

0.6.4 is the hardening release for issues #50, #51, #52 and #53. The 0.7.0 strategy-manifest redesign is explicitly outside this release.

## Automated gates

The release candidate must pass all of these checks on the exact commit proposed for release.

### Repository and supply chain

- `scripts/Test-Repository.ps1` passes.
- The complete Pester suite passes.
- `scripts/Test-GitHubActionsPinning.ps1` reports `passed`.
- Every external action in `.github/workflows/*.yml` is a reviewed full commit SHA with the expected semantic-version comment.
- Website typecheck and static build pass.

### Strategy Lab ranking

- Repeated critical-service observations are ranked above secondary checks.
- Flapping 1-of-3 and 2-of-3 histories receive lower stability than stable histories with comparable availability.
- Missing optional telemetry remains null/unavailable and is never converted to zero.
- Insufficient observations and failed controls produce `inconclusive` with a null score.
- Controls gate eligibility and do not contribute positive score.
- Endpoint and protocol pass rates are stored.
- Exact ties use the documented deterministic strategy-id tie-break.
- New schema-3 history remains readable by the CLI and native Dashboard; legacy history still follows the legacy display path.

### Privacy-safe field evidence implementation

- The same source log and candidate SHA-256 produce byte-identical canonical receipts.
- A receipt validates against both candidate and source-log hashes.
- Modified receipts and modified source logs fail closed.
- Unknown targets/statuses, incomplete targets, split success across strategies, critical failures and control failures fail closed.
- Extra receipt fields fail closed.
- Canonical receipts do not publish provider, location, username, SSID, MAC address, absolute local path or wall-clock verification time.

### Updater and package

- Online package build and verification pass.
- Offline rebuild from the verified pinned upstream cache passes.
- Online and offline package locks agree.
- Patch report contains exactly 23 tracked targets.
- Native tray, notifier, Dashboard and validation viewer package checks pass.
- Windows launchers and first-run diagnostic compatibility checks pass.
- Real published 0.6.2 -> 0.6.3 migration evidence passes on a Windows runner.
- The migration path contains spaces and non-ASCII characters without publishing that absolute path in evidence.
- A second updater run reports current/idempotent.
- Forced post-update health failure restores the prior version and preserved user state.

### Release provenance

- Release archive, checksum and validation artifacts are produced.
- GitHub build provenance is generated for the release subjects.
- `gh attestation verify` succeeds for every attested subject before release publication.

## Manual gates before final publication

These checks must not be inferred from hosted CI.

### Windows 10 and Windows 11

On at least one supported Windows 10 x64 machine and one supported Windows 11 x64 machine:

1. Install or unpack the previous stable 0.6.3 release into a normal user path.
2. Preserve a representative Service Matrix state, custom services, user domain/IP lists, language/UI state and Strategy Lab history.
3. Update to the 0.6.4 release candidate through the user-facing updater path.
4. Confirm the expected version and state after restart.
5. Launch `nexroute.bat`, `service.bat` and `nexroute-update.cmd`.
6. Open the native Dashboard and validation viewer.
7. Run Strategy Lab against at least Discord and YouTube critical targets plus controls.
8. Confirm that an inconclusive/control-failure run is not presented as a successful ranked result.
9. Confirm that the best-strategy explanation agrees between CLI and Dashboard.
10. Exercise rollback from a deliberately failed post-update health check in a disposable test installation.

Record OS build, package SHA-256, candidate commit SHA and pass/fail results. Do not publish usernames, absolute local paths, provider/location identity or raw logs unless separately reviewed.

### Real field evidence

The privacy-safe receipt implementation must be exercised with a real Strategy Lab log from a representative network:

1. Generate the receipt with `scripts/New-StrategyLabFieldEvidence.ps1`.
2. Run `-PrivacyReview` and inspect excluded categories.
3. Validate the receipt with `scripts/Test-StrategyLabFieldEvidence.ps1` against the source log and candidate SHA-256.
4. Publish only the minimised canonical receipt if publication is desired; keep the raw log private by default.

A synthetic fixture proving receipt behavior is automated evidence for the implementation. It is not a substitute for a real field observation proving a specific strategy works on a real network.

## Release decision

0.6.4 may be merged as release-ready source only when all automated gates are green. Final GitHub Release publication should additionally have the manual Windows and real-field checks recorded, or the release decision must explicitly document which manual evidence is still pending instead of claiming it was performed.
