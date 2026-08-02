# NexRoute 🧭

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](../LICENSE)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows)](COMPATIBILITY.md)
[![Flowseal baseline](https://img.shields.io/badge/Flowseal-1.10.0-6f42c1)](UPSTREAM.md)
[![Version](https://img.shields.io/badge/version-0.3.2-24e1d6)](../.service/version.txt)

NexRoute is a command-line route-control toolkit for DPI desynchronization strategies on Windows 10 and Windows 11.

> [!IMPORTANT]
> NexRoute is not a VPN, proxy or anonymity service. It locally manages `winws` and WinDivert and does not change the public IP address.

## Version 0.3.2 — verifiable build provenance

Version `0.3.2` adds GitHub build provenance attestations for the official release assets:

- the release workflow creates a Sigstore-backed attestation for the package ZIP and matching `.sha256` file;
- only the minimum OIDC and attestation permissions are granted;
- both subjects are verified with `gh attestation verify` before the GitHub Release is published;
- a Pester contract protects the action version, permissions, subject list and release-step ordering;
- users can verify that a downloaded asset was produced by the `Onmaynec/NexRoute` workflow from a specific source commit;
- attestations complement SHA-256, the upstream lock and patch report, but do not replace Windows Authenticode signing.

Verification after downloading the release:

```powershell
gh attestation verify .\NexRoute-0.3.2-win-x64.zip --repo Onmaynec/NexRoute
gh attestation verify .\NexRoute-0.3.2-win-x64.zip.sha256 --repo Onmaynec/NexRoute
```

See [ATTESTATIONS.md](ATTESTATIONS.md) for the trust boundary and verification details.

## Secure automatic updates

NexRoute includes a stable-channel updater for official `Onmaynec/NexRoute` GitHub Releases:

- `nexroute.bat` checks for a newer version before opening Control Node when automatic updates are enabled;
- automatic checks use a 24-hour cooldown stored in `.service/update-state.json`;
- the `CHECK UPDATES` menu entry opens the full Update Center;
- `nexroute-update.cmd` provides manual update checks and rollback;
- draft and prerelease builds are rejected;
- each accepted release must contain exactly one package ZIP and its matching `.sha256` asset;
- the updater verifies the asset name, semantic version, SHA-256, mandatory package files, 21 strategies and 23 patch records before installation;
- the current installation is backed up before any files are replaced;
- language, Service Matrix state, caches and user-managed lists are preserved;
- a failed installation automatically restores the previous package;
- the newest four update backups are retained in the sibling `NexRoute-backups` directory;
- a per-installation mutex prevents concurrent updater processes from changing the same package.

Network or GitHub failures in automatic mode do not block the current NexRoute version from starting. See [UPDATES.md](UPDATES.md) for the complete update and rollback contract.

## Reproducible build contract

NexRoute `0.3.x` uses a declarative Flowseal contract. An online build can save the verified Flowseal archive:

```powershell
pwsh ./scripts/Build-Release.ps1 `
  -Version 0.3.2 `
  -OutputDirectory ./artifacts `
  -UpstreamCachePath ./cache/zapret-discord-youtube-1.10.0.zip
```

The same verified archive can then be used without contacting the Flowseal release API:

```powershell
pwsh ./scripts/Build-Release.ps1 `
  -Version 0.3.2 `
  -OutputDirectory ./artifacts-offline `
  -UpstreamArchive ./cache/zapret-discord-youtube-1.10.0.zip
```

The offline file must match the committed SHA-256 and required archive structure. Matching the file name alone is not sufficient.

## Package provenance

Every release package contains:

```text
.service/upstream-manifest.json
.service/upstream-lock.json
.service/patch-report.json
NEXROUTE_BUILD_INFO.txt
```

The upstream lock records the exact Flowseal asset, size and SHA-256. The patch report records the 21 strategy targets plus `service.bat` and Strategy Lab, including operation counts and file hashes before and after each patch. These files do not contain user-managed domain/IP list contents.

Starting with `0.3.2`, GitHub build provenance attestations additionally bind the published ZIP and checksum digests to the release workflow, repository and source commit.

## Service Matrix v2

The matrix covers YouTube, Discord, ChatGPT, FaceTime, Snapchat, Viber, Signal, X, Instagram, Facebook, Telegram, LinkedIn, TikTok, WhatsApp and CaseBattle.

Each profile defines domains, critical endpoints, TCP/UDP ports, IPv4 resolution hosts and optional CIDR sources. Enabled services receive isolated hostlist/IPSet and TCP/UDP filter groups. A shared domain is excluded only when every owning profile is disabled.

State schema v2 supports migration and backups. Remote IP sources use strict IPv4 CIDR validation and a 14-day last-known-good cache. Privacy-safe Diagnostics excludes user-managed list contents and external local paths.

## Update state and backups

Updater state is stored in:

```text
.service/update-state.json
```

It records the installed and latest discovered versions, last/next check time, operation status, backup path and installed package SHA-256.

Before an update, NexRoute creates a complete package backup in:

```text
../NexRoute-backups/
```

The updater preserves language selection, Service Matrix state, IP-source cache, update/game flags and user-managed list/IPSet files. Rollback creates an additional safety backup before restoring the previous version.

## Quick start

1. Download `NexRoute-0.3.2-win-x64.zip` and its `.sha256` file from GitHub Releases.
2. Verify the checksum and, optionally, both build provenance attestations.
3. Extract the complete archive to a new folder.
4. Run `NexRoute.lnk`, `nexroute.bat` or `service.bat` as administrator.
5. Select and install a strategy.
6. Configure `[14] SERVICE MATRIX`.
7. Enable automatic updates through `[6] CHECK UPDATES` when desired.
8. Use `nexroute-update.cmd` for an immediate check or rollback.
9. Use `[12] STRATEGY LAB` when endpoint testing is needed.

Do not run BAT or CMD launchers directly from the ZIP archive.

## Validation

```powershell
pwsh ./scripts/Test-Repository.ps1
Invoke-Pester -Path ./tests -CI -Output Detailed
```

CI covers:

- PowerShell AST parsing for `.ps1` and `.psm1` files;
- Service Matrix, upstream-contract, updater and release-attestation Pester suites;
- offline updater fixtures for stable-release discovery, installation, state preservation, checksum mismatch, prerelease rejection, cooldown and rollback;
- the locked Flowseal `1.10.0` archive;
- online and offline Windows package builds;
- 23 tracked patch targets, 21 real strategies and 15 service profiles;
- runtime generation, Diagnostics, EN/RU UI pages, Update Center wiring, icon generation and final package SHA-256;
- creation and self-verification of attestations for the ZIP and `.sha256` before release publication.

## Limitations

Network effectiveness depends on the ISP, region, DNS configuration, application version and selected strategy. The `0.3.2` runtime is IPv4-focused; IPv6-only endpoints require separate future support.

The upstream lock, updater checksum and GitHub build provenance attestation protect integrity and verifiable build origin. They are not Windows Authenticode publisher signatures.

## Licensing

Original NexRoute code, documentation and branding use the MIT License. Flowseal, zapret and WinDivert remain subject to their respective licenses and notices. See [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).
