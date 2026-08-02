# NexRoute 🧭

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](../LICENSE)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows)](COMPATIBILITY.md)
[![Flowseal baseline](https://img.shields.io/badge/Flowseal-1.10.0-6f42c1)](UPSTREAM.md)
[![Version](https://img.shields.io/badge/version-0.4.0-24e1d6)](../.service/version.txt)

NexRoute is a command-line route-control toolkit for DPI desynchronization strategies on Windows 10 and Windows 11 x64.

> NexRoute is not a VPN, proxy, or anonymity service. It locally manages winws and WinDivert and does not change the public IP address.

## Version 0.4.0 — official website source

Version 0.4.0 adds a production-ready multi-page project website in `website/`:

- Next.js App Router, React, TypeScript, Tailwind CSS, Motion, and Lucide Icons;
- Home, Features, Download, Documentation, Security, FAQ, Changelog, and custom 404 pages;
- interactive HTML/CSS product previews for Service Matrix, Strategy Lab, update flow, and route graphs;
- public GitHub API integration for the latest stable release and repository stats;
- stable-only filtering and honest fallback states when GitHub is unavailable;
- responsive documentation sidebar, mobile drawer, search, table of contents, and code copy buttons;
- canonical URLs, Open Graph, Twitter cards, sitemap, robots, manifest, and SoftwareApplication JSON-LD;
- a dedicated GitHub Actions website typecheck and production build job;
- local build and Vercel deployment documentation.

See [WEBSITE.md](WEBSITE.md) and [../website/README.md](../website/README.md).

## Product capabilities

- 21 real Flowseal strategies;
- 15 Service Matrix profiles;
- Strategy Lab endpoint testing;
- privacy-safe Diagnostics;
- stable updater with SHA-256 verification;
- full backup before installation and automatic rollback on failure;
- GitHub/Sigstore build provenance attestations for the ZIP and checksum asset;
- locked Flowseal upstream and tracked patch report.

## Quick start

1. Download `NexRoute-0.4.0-win-x64.zip` and its `.sha256` asset from Releases.
2. Optionally verify both assets with `gh attestation verify`.
3. Fully extract the archive into a new directory.
4. Run `NexRoute.lnk`, `nexroute.bat`, or `service.bat` as administrator.
5. Select and install a strategy.
6. Configure `[14] SERVICE MATRIX`.
7. Use `[12] STRATEGY LAB` when testing is needed.
8. Use `[6] CHECK UPDATES` or `nexroute-update.cmd` for updates and rollback.

Do not run BAT or CMD launchers directly from the ZIP archive.

## Build provenance verification

```powershell
gh attestation verify .\NexRoute-0.4.0-win-x64.zip --repo Onmaynec/NexRoute
```

Build provenance verifies the release workflow, repository, source commit, and asset digest. It does not replace Windows Authenticode code signing.

## Licensing

Original NexRoute code, website, documentation, and branding use the MIT License. Flowseal, zapret, and WinDivert remain subject to their own licenses and notices.
