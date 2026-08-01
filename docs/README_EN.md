# NexRoute 🧭

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](../LICENSE)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows)](COMPATIBILITY.md)
[![Flowseal baseline](https://img.shields.io/badge/Flowseal-1.10.0-6f42c1)](UPSTREAM.md)
[![Version](https://img.shields.io/badge/version-0.3.0-24e1d6)](../.service/version.txt)

NexRoute is a command-line route-control toolkit for DPI desynchronization strategies on Windows 10 and Windows 11.

> [!IMPORTANT]
> NexRoute is not a VPN, proxy or anonymity service. It locally manages `winws` and WinDivert and does not change the public IP address.

## Version 0.3.0

Version `0.3.0` makes the Flowseal foundation and every build-time patch independently auditable:

- `.service/upstream-manifest.json` pins the repository, release tag, asset pattern, minimum size, required paths and SHA-256;
- the official Flowseal archive is verified before the legacy base builder can consume it;
- `.service/upstream-lock.json` records the exact asset identity embedded in the package;
- `.service/patch-report.json` records patch IDs, relative targets, operation counts and SHA-256 values before and after each modification;
- all 21 real strategies, `service.bat` and Strategy Lab form exactly 23 tracked patch targets;
- patch anchors require an exact match count and fail closed when the upstream structure changes;
- `Build-Release.ps1 -UpstreamArchive` supports a fully offline rebuild from a previously verified archive;
- CI performs an online build followed by an offline rebuild and compares the upstream lock, patch report, 21 strategies and 15 services;
- Pester covers manifest validation, path traversal, locked digests, SHA mismatches, missing archive files and the local verified proxy.

## Reproducible build contract

An online build can save the verified Flowseal archive:

```powershell
pwsh ./scripts/Build-Release.ps1 `
  -Version 0.3.0 `
  -OutputDirectory ./artifacts `
  -UpstreamCachePath ./cache/zapret-discord-youtube-1.10.0.zip
```

The same verified archive can then be used without contacting the Flowseal release API:

```powershell
pwsh ./scripts/Build-Release.ps1 `
  -Version 0.3.0 `
  -OutputDirectory ./artifacts-offline `
  -UpstreamArchive ./cache/zapret-discord-youtube-1.10.0.zip
```

The offline file must match the committed SHA-256 and the required archive structure. Matching the file name alone is not sufficient.

## Package provenance

Every release package contains:

```text
.service/upstream-manifest.json
.service/upstream-lock.json
.service/patch-report.json
NEXROUTE_BUILD_INFO.txt
```

These files do not contain local runner paths, user names or user-managed domain/IP list contents.

## Service Matrix v2

The matrix covers YouTube, Discord, ChatGPT, FaceTime, Snapchat, Viber, Signal, X, Instagram, Facebook, Telegram, LinkedIn, TikTok, WhatsApp and CaseBattle.

Each profile defines domains, critical endpoints, TCP/UDP ports, IPv4 resolution hosts and optional CIDR sources. Enabled services receive isolated hostlist/IPSet and TCP/UDP filter groups. A shared domain is excluded only when every owning profile is disabled.

State schema v2 supports migration and backups. Remote IP sources use strict IPv4 CIDR validation and a 14-day last-known-good cache. Privacy-safe Diagnostics excludes user-managed list contents and external local paths.

## Quick start

1. Download `NexRoute-0.3.0-win-x64.zip` and its `.sha256` file from GitHub Releases.
2. Verify the checksum.
3. Extract the complete archive to a new folder.
4. Run `NexRoute.lnk`, `nexroute.bat` or `service.bat` as administrator.
5. Select and install a strategy.
6. Configure `[14] SERVICE MATRIX` and use `[12] STRATEGY LAB` when needed.

Do not run BAT files directly from the ZIP archive.

## Validation

```powershell
pwsh ./scripts/Test-Repository.ps1
Invoke-Pester -Path ./tests -CI -Output Detailed
```

Windows CI builds and verifies the online and offline packages, all 21 actual strategies, 15 service profiles, the upstream lock, 23 patch records, runtime generation, Diagnostics, UI rendering, icon generation and the final ZIP checksum.

## Limitations

Network effectiveness depends on the ISP, region, DNS configuration, application version and selected strategy. The `0.3.0` runtime is IPv4-focused; IPv6-only endpoints require separate future support.

The upstream lock protects build reproducibility but is not a digital signature for the NexRoute release itself. Verify the published `.sha256` file. Signed releases and provenance attestations are planned separately.

## Licensing

Original NexRoute code, documentation and branding use the MIT License. Flowseal, zapret and WinDivert remain subject to their respective licenses and notices. See [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).
