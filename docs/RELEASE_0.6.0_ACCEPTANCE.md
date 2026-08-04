# NexRoute 0.6.0 production-hardening acceptance

Version 0.6.0 is not considered complete when a function name or menu entry merely exists. Every item below requires a behavioral test or an explicitly documented hardware/OS validation result.

## Multi-service runtime

- A supervisor creates one isolated `winws` worker per enabled service assignment.
- Every worker has a unique PID file, log file, service identifier and filter scope.
- Starting YouTube and Discord assignments produces two live processes with non-overlapping generated command lines.
- Stopping one assignment does not terminate the other.
- Duplicate WinDivert capture scopes are rejected before launch.

## Automatic failover

- Health decisions use configurable consecutive-failure and recovery thresholds.
- Synthetic probes can force healthy, degraded and failed states without internet access.
- A failed service switches only its assigned worker to the next eligible strategy.
- Cooldown and maximum-switch limits prevent loops.
- Restart and failover history survives process restart.

## Strategy Lab measurements

- Download speed uses a configurable multi-megabyte payload and reports transferred bytes, elapsed time and Mbps.
- YouTube readiness tests manifest/segment retrieval and sustained transfer rather than only `generate_204`.
- Discord and Telegram tests report TCP/TLS reachability plus UDP transport readiness. They must not claim to measure real call MOS without an authenticated call session.
- Results state exactly what was measured and do not label HTTP latency as voice quality.

## DNS encryption

- DoH uses Windows-supported encrypted DNS configuration where available.
- DoT is provided only through a bundled, pinned local resolver/proxy with verified checksum and explicit lifecycle management.
- The application verifies that queries actually pass through the selected encrypted resolver.
- Unsupported Windows versions receive a clear unsupported result instead of a false success.

## Native desktop controller

- Tray controller is a compiled Windows executable with a single-instance lock, startup registration, clean shutdown and crash recovery.
- Notifications have a toast path and a deterministic fallback when toast is disabled or unavailable.
- Light/dark themes and accent colors affect an actual desktop UI, not only console colors.
- Statistics charts are interactive and read the same local history used by the TUI.
- A compiled Validation Viewer exposes every signed-report check and limitation without converting `experimental` or `unsupported` into success.
- Imported report JSON is informational until its schema, package version and local attestation-verification receipt are consistent.
- Wrong-product, wrong-version, duplicate-check, unsupported-status and failed-required inconsistencies are rejected before display.

## Conflict and repair wizard

- Diagnostics distinguish findings from guesses.
- Firewall, VPN, WinDivert and known security-product findings include evidence and reversible repair actions.
- The wizard creates a backup before changing firewall, DNS, routes, adapters or services.
- Every repair action has a rollback test.
- Unknown antivirus products are reported as unknown, never as compatible.

## Network profiles

- Adapter changes are detected through Windows network events and reconciled after restart.
- Ethernet, Wi-Fi and public/private network profiles are matched by stable identifiers.
- Applying a new profile is idempotent and recorded in history.
- Tests simulate adapter arrival, removal and profile changes.

## Strategy builder

- The builder exposes validated fields for filters, ports, desync modes, repeats, fake payloads and list files.
- Unsafe combinations are blocked before saving.
- Generated commands round-trip through parser and serializer tests.
- Preview matches the command passed to the worker.

## Release provenance without GitHub CLI

- The updater verifies release asset SHA-256.
- The updater verifies GitHub artifact attestation through an embedded verifier or Sigstore-compatible library.
- No external `gh` installation is required.
- Offline and tampered-attestation fixtures fail closed.

## IPv6

- IPv6 support means more than parsing CIDR and AAAA records.
- Generated filters include IPv6 traffic where supported by the pinned upstream runtime.
- Tests launch IPv4-only, IPv6-only and dual-stack workers with synthetic endpoints.
- If the pinned upstream cannot provide a feature, the UI reports the exact limitation and does not claim full IPv6 bypass.

## Seamless updater

- Upgrade tests cover 0.4.1 -> 0.6.0 and 0.5.0 -> 0.6.0 fixtures.
- A detached helper stops old processes, replaces locked files, preserves user data and starts the new version.
- Failure during download, verification, extraction, replacement and first launch triggers rollback.
- The old instance exits only after the helper has accepted the transaction.
- Post-update health failure can restore the previous version.

## Release gate

The release workflow must fail unless all automated acceptance tests pass. Hardware-dependent checks must be attached to the release as a signed validation report. Unverified capabilities must be marked experimental or unsupported in the UI and release notes.

The workflow must generate and attest both `NexRoute-<version>-validation.json` and `NexRoute-<version>-validation.md`. The JSON report uses schema version 1 and records release identities, runner/OS provenance, required automated checks and explicit `passed`, `experimental`, `unsupported` or `failed` statuses. Any failed required check blocks publication; experimental and unsupported checks remain visible limitations rather than false successes.

The online and fully offline package builds must both compile `NexRoute.Validation.exe`, verify its SHA-256, run its deterministic report fixture, prove the unverified and receipt-matched trust states, and include the result as required check `native-validation.self-test` in the signed validation report. Release notes must exist before publication and must repeat the hardware/ISP limitations from the report.

Before attestation, the validation generator must extract the finalized release ZIP and execute the packaged notification broker with deterministic runners. It must prove a successful `windows-toast` path and a `DisabledByGroupPolicy` transition to `native-balloon` in the exact attempt order. The signed report records this as required check `notifications.delivery-contract`; visible toast and balloon rendering remains a separate `notifications.interactive` experimental check until validated in a signed-in Windows 10/11 desktop session.
