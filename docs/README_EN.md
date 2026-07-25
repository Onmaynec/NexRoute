# NexRoute 🧭

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](../LICENSE)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows)](COMPATIBILITY.md)
[![Flowseal baseline](https://img.shields.io/badge/Flowseal-1.10.0-6f42c1)](UPSTREAM.md)

NexRoute is a command-line toolkit for managing DPI desynchronization strategies on Windows 10 and Windows 11.

> [!IMPORTANT]
> NexRoute is not a VPN, proxy or anonymity service. It locally manages `winws` and WinDivert and does not change the user's public IP address.

## ✨ Version 0.1.0 goals

- Functional parity with Flowseal release `1.10.0`
- Discord Web/CDN/Voice and YouTube strategy coverage inherited from upstream
- TCP, UDP and QUIC strategy support
- Windows service installation and removal
- Game Filter and IPSet Filter
- Diagnostics, strategy tests, hosts/IPSet updates and fake-payload replacement
- Compatibility with Flowseal user lists
- Russian and English console menu
- Release-only binaries with SHA-256 checksums

## 🚀 Quick start

1. Download `NexRoute-0.1.0-win-x64.zip` and its `.sha256` file from GitHub Releases.
2. Verify the checksum.
3. Unblock the ZIP in Windows file properties when the option is available.
4. Extract it to a path without Cyrillic or special characters, such as `C:\NexRoute`.
5. Run `service.bat` as administrator.
6. Test available strategies and install the working strategy as a Windows service.

## 🛠️ Building

```powershell
pwsh ./scripts/Build-NexRoute.ps1 `
  -Version 0.1.0 `
  -UpstreamVersion 1.10.0 `
  -OutputDirectory ./artifacts
```

The builder resolves the official Flowseal release asset, validates required files, applies the NexRoute console overlay and creates a ZIP plus SHA-256 checksum.

## ⚖️ Licensing

Original NexRoute code and documentation use the MIT License. Flowseal, zapret and WinDivert remain subject to their own licenses and notices. See [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).
