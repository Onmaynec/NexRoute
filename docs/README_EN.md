# NexRoute 🧭

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](../LICENSE)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows)](COMPATIBILITY.md)
[![Flowseal baseline](https://img.shields.io/badge/Flowseal-1.10.0-6f42c1)](UPSTREAM.md)
[![Version](https://img.shields.io/badge/version-0.2.0-24e1d6)](../.service/version.txt)

NexRoute is a command-line route-control toolkit for DPI desynchronization strategies on Windows 10 and Windows 11.

> [!IMPORTANT]
> NexRoute is not a VPN, proxy or anonymity service. It locally manages `winws` and WinDivert and does not change the public IP address.

## ✨ Version 0.2.0

- Flowseal `1.10.0` functional baseline
- unified Russian/English PowerShell terminal renderer
- styled main menu, status, strategy picker, payload vault, IPSet/hosts sync and test launcher
- animated strategy boot and system operations
- 15-profile Service Bypass Matrix
- custom NexRoute SVG mark, generated Windows icon and launcher shortcut
- user-list compatibility through managed blocks
- release-only executable components with SHA-256 checksums

## 🌐 Service Bypass Matrix

The matrix controls:

- YouTube and Discord
- ChatGPT
- FaceTime
- Snapchat
- Viber
- Signal
- X (Twitter)
- Instagram and Facebook
- Telegram
- LinkedIn
- TikTok
- WhatsApp
- CaseBattle

Use `Up/Down`, `Space`, `A`, `N`, `Enter` and `Escape` inside the matrix screen.

See [SERVICES.md](SERVICES.md) for domain packs and limitations.

## 🚀 Quick start

1. Download `NexRoute-0.2.0-win-x64.zip` and its `.sha256` file from GitHub Releases.
2. Verify the checksum.
3. Unblock the ZIP in Windows file properties when available.
4. Extract the complete archive to `C:\NexRoute` or another simple path.
5. Run `NexRoute.lnk`, `nexroute.bat` or `service.bat` as administrator.
6. Test profiles, install a working strategy and configure the Service Matrix.

## 🛠️ Building

```powershell
pwsh ./scripts/Test-Repository.ps1

pwsh ./scripts/Build-NexRoute.ps1 `
  -Version 0.2.0 `
  -UpstreamVersion 1.10.0 `
  -OutputDirectory ./artifacts
```

The builder downloads the official pinned Flowseal asset, validates its structure, applies the NexRoute overlay, generates the custom icon/shortcut and creates a ZIP plus SHA-256 checksum.

## ⚠️ Limitations

FaceTime, Signal, Viber and WhatsApp are experimental domain profiles. Their call/media paths may use dynamic IP addresses, relays and additional UDP ports that cannot be represented by a static hostlist alone.

Network effectiveness depends on the ISP, region, DNS configuration and selected strategy.

## ⚖️ Licensing

Original NexRoute code, documentation and branding use the MIT License. Flowseal, zapret and WinDivert remain subject to their respective licenses and notices. See [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).
