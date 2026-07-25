# NexRoute 🧭

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](../LICENSE)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows)](COMPATIBILITY.md)
[![Flowseal baseline](https://img.shields.io/badge/Flowseal-1.10.0-6f42c1)](UPSTREAM.md)
[![Version](https://img.shields.io/badge/version-0.2.2-24e1d6)](../.service/version.txt)

NexRoute is a command-line route-control toolkit for DPI desynchronization strategies on Windows 10 and Windows 11.

> [!IMPORTANT]
> NexRoute is not a VPN, proxy or anonymity service. It locally manages `winws` and WinDivert and does not change the public IP address.

## Version 0.2.2

- fixes `[09] SYNC HOSTS` with a null-safe managed merge, dated backup, atomic replacement and DNS cache flush;
- upgrades the 15-profile Service Matrix to schema v2 with domains, real endpoints, TCP/UDP ports, resolved IPv4 addresses and optional CIDR sources;
- injects enabled-service filters into all 21 actual Flowseal `1.10.0` strategies;
- excludes `nexroute.bat` from Strategy Lab because it is a menu launcher, not a network strategy;
- adds enabled-service web/API/CDN/media/gateway probes to every Strategy Lab run;
- reinstalls and restarts the active `zapret` service after Service Matrix changes;
- keeps Russian and English UI, with English as the default;
- replaces raw Game Filter and Update Watch prompts with styled Control Node pages;
- generates a multi-resolution Windows icon based on the supplied NexRoute visual motif.

## Service Matrix v2

Each profile can define:

```text
domains
testTargets
tcpPorts
udpPorts
resolveHosts
ipCidrs
ipSources
```

Applying the matrix creates managed hostlists, an IPv4 set and `.service/services-runtime.cmd`. These values are connected to each actual strategy as separate TCP and UDP filters.

The matrix covers YouTube, Discord, ChatGPT, FaceTime, Snapchat, Viber, Signal, X, Instagram, Facebook, Telegram, LinkedIn, TikTok, WhatsApp and CaseBattle.

## Strategy Lab

The lab keeps the baseline Discord, YouTube, Google, Cloudflare and DNS checks and adds multiple critical endpoints for every enabled service. Standard checks cover HTTP, TLS 1.2, TLS 1.3 and latency. The TCP 16–20 KB DPI mode is preserved.

A full run contains 21 real strategy configurations. The previous apparent 22nd entry was `nexroute.bat`, which only opens the control interface.

## Quick start

1. Download `NexRoute-0.2.2-win-x64.zip` and its `.sha256` file from GitHub Releases.
2. Verify the checksum.
3. Extract the complete archive to a new folder.
4. Run `NexRoute.lnk`, `nexroute.bat` or `service.bat` as administrator.
5. Select and install a strategy.
6. Configure `[14] SERVICE MATRIX` and use `[12] STRATEGY LAB` when needed.

Do not run BAT files directly from the ZIP archive.

## Building

```powershell
pwsh ./scripts/Test-Repository.ps1

pwsh ./scripts/Build-NexRoute-0.2.2.ps1 `
  -Version 0.2.2 `
  -UpstreamVersion 1.10.0 `
  -OutputDirectory ./artifacts
```

The release builder downloads the pinned Flowseal asset, applies the NexRoute overlay and network integration, patches all 21 actual strategies, generates the icon and shortcut, and creates a ZIP plus SHA-256 checksum.

## Limitations

Network effectiveness depends on the ISP, region, DNS configuration, application version and selected strategy. Dynamic media relays, IPv6 paths and peer-to-peer traffic cannot be guaranteed in every network.

## Licensing

Original NexRoute code, documentation and branding use the MIT License. Flowseal, zapret and WinDivert remain subject to their respective licenses and notices. See [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).
