# NexRoute 🧭

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](../LICENSE)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows)](COMPATIBILITY.md)
[![Flowseal baseline](https://img.shields.io/badge/Flowseal-1.10.0-6f42c1)](UPSTREAM.md)
[![Version](https://img.shields.io/badge/version-0.6.0-24e1d6)](../.service/version.txt)

NexRoute is a local Windows route-control toolkit for DPI desynchronization strategies. It manages `winws` and WinDivert, service-specific filter scopes, release verification, and rollback on Windows 10 and Windows 11 x64.

> NexRoute is not a VPN, proxy, or anonymity service. It does not change the public IP address.

## Version 0.6.0 — production-hardening and behavioral validation

Version 0.6.0 adds a verifiable runtime and release contract:

- isolated per-service workers with unique process state, logs, strategies, and non-overlapping filter scopes;
- deterministic failover thresholds, recovery, cooldown, maximum-switch limits, and synthetic fault injection;
- streamed throughput measurement, HLS manifest/segment readiness, and separate TCP/TLS and UDP transport results;
- pinned transactional DNS-over-TLS and platform-gated Windows DoH;
- stable adapter identities and restart-safe network-profile reconciliation;
- IPv4-only, IPv6-only, and dual-stack synthetic worker coverage;
- native tray, notifier, Strategy Lab Dashboard, and Validation Viewer executables;
- Windows `ToastGeneric` delivery with explicit `ToastNotifier.Setting` checks and native balloon/legacy fallback;
- reversible evidence-based repair transactions and a validated Strategy Builder;
- portable GitHub artifact-attestation verification without a preinstalled GitHub CLI;
- detached update transactions and migration fixtures from 0.4.1 and 0.5.0.

See [RELEASE_0.6.0_ACCEPTANCE.md](RELEASE_0.6.0_ACCEPTANCE.md).

## Release assets and verification

A complete 0.6.0 release contains four related assets:

```text
NexRoute-0.6.0-win-x64.zip
NexRoute-0.6.0-win-x64.zip.sha256
NexRoute-0.6.0-validation.json
NexRoute-0.6.0-validation.md
```

All four subjects are covered by one GitHub artifact attestation. The portable verifier checks immutable release URLs, the package checksum, and every attested subject before installing the validation report and matching local verification receipt.

Manual verification:

```powershell
gh attestation verify .\NexRoute-0.6.0-win-x64.zip --repo Onmaynec/NexRoute
gh attestation verify .\NexRoute-0.6.0-win-x64.zip.sha256 --repo Onmaynec/NexRoute
gh attestation verify .\NexRoute-0.6.0-validation.json --repo Onmaynec/NexRoute
gh attestation verify .\NexRoute-0.6.0-validation.md --repo Onmaynec/NexRoute
```

The Validation Viewer does not automatically trust imported JSON. A document remains `attestation-not-verified` until a digest-matched local receipt exists. Wrong product/version documents, duplicate check IDs, unknown statuses, and inconsistent overall status are rejected.

## Product capabilities

- 21 real Flowseal strategies;
- 15 Service Matrix profiles;
- per-service worker isolation and deterministic failover;
- Strategy Lab history, scoring, recommendations, and native Dashboard;
- privacy-safe Diagnostics;
- stable updater with checksum, attestation, backup, health checks, and rollback;
- native tray and notification delivery fallback;
- signed machine-readable and human-readable validation reports;
- locked Flowseal upstream and tracked patch report.

## Quick start

1. Download the ZIP, checksum, and both validation reports from the same GitHub Release.
2. Verify them with the bundled portable verifier or `gh attestation verify`.
3. Fully extract the archive into a new directory.
4. Run `NexRoute.lnk`, `nexroute.bat`, or `service.bat` as administrator.
5. Select a strategy and configure `[14] SERVICE MATRIX`.
6. Use `[12] STRATEGY LAB` to compare strategies.
7. Use the tray to open the Dashboard and Validation Viewer.
8. Use `[6] CHECK UPDATES` or `nexroute-update.cmd` for updates and rollback.

Do not run BAT or CMD launchers directly from the ZIP archive.

## Honest limitations

Automated CI proves source contracts, online/offline package construction, native binary self-tests, synthetic workers, updater rollback, package identities, and signed validation reports. It does not claim to prove ISP-specific bypass behavior, a visible toast in a signed-in desktop session, physical adapter transitions, live DoH routing, or full live IPv6 bypass. Those capabilities remain `experimental` or `unsupported` until real-machine evidence exists.

Build provenance verifies the release workflow, repository, source commit, and asset digests. It does not replace Windows Authenticode code signing.

## Licensing

Original NexRoute code, website, documentation, and branding use the MIT License. Flowseal, zapret, and WinDivert remain subject to their own licenses and notices.
