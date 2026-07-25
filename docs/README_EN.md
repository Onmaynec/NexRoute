# NexRoute 🧭

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](../LICENSE)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows)](COMPATIBILITY.md)
[![Flowseal baseline](https://img.shields.io/badge/Flowseal-1.10.0-6f42c1)](UPSTREAM.md)
[![Version](https://img.shields.io/badge/version-0.1.1-cyan)](../.service/version.txt)

NexRoute is a command-line toolkit for managing DPI desynchronization strategies on Windows 10 and Windows 11.

> [!IMPORTANT]
> NexRoute is not a VPN, proxy or anonymity service. It locally manages `winws` and WinDivert and does not change the user's public IP address.

## ✨ Version 0.1.1

- Functional parity with Flowseal release `1.10.0`
- Discord Web/CDN/Voice and YouTube strategy coverage inherited from upstream
- TCP, UDP and QUIC strategy support
- Windows service installation and removal
- Game Filter and IPSet Filter
- Diagnostics, strategy tests, hosts/IPSet updates and fake-payload replacement
- Compatibility with Flowseal user lists
- Russian and English terminal interface
- ASCII-safe PowerShell renderer that avoids CMD encoding corruption
- Branded ASCII logo, structured panels and colored state badges
- Startup animation for the control center
- Action animation for every menu operation
- Profile boot animation for every strategy BAT launcher
- Release-only binaries with SHA-256 checksums

## 🖥️ Terminal UI design

The upstream service logic remains inside `service.bat`, but the visual layer is rendered by `.service/nexroute-ui.ps1`.

The PowerShell source contains ASCII characters only. Russian strings are stored as Base64-encoded UTF-8 and decoded explicitly at runtime. This prevents the mojibake that occurs when a UTF-8 BAT file is interpreted through an OEM Windows code page.

The renderer provides:

- a NexRoute ASCII logo;
- control-node header with version and Flowseal baseline;
- active profile, language and privilege information;
- separate Service, Filter, Data and Toolkit panels;
- colored filter states;
- animated progress bars;
- a clean ASCII fallback menu when the renderer cannot be started.

## 🚀 Quick start

1. Download `NexRoute-0.1.1-win-x64.zip` and its `.sha256` file from GitHub Releases.
2. Verify the checksum.
3. Unblock the ZIP in Windows file properties when the option is available.
4. Extract it to a folder such as `C:\NexRoute`.
5. Run `nexroute.bat` or `service.bat`.
6. Approve the administrator prompt.
7. Test available strategies and install the working strategy as a Windows service.

Do not run BAT files directly from inside the ZIP archive.

When a strategy file is launched directly, NexRoute displays a short profile boot sequence and checks that `winws.exe` and the WinDivert driver are present before handing control back to the original strategy.

## 🛠️ Building

```powershell
pwsh ./scripts/Build-NexRoute.ps1 `
  -Version 0.1.1 `
  -UpstreamVersion 1.10.0 `
  -OutputDirectory ./artifacts
```

The builder resolves the official Flowseal release asset, validates required files, installs the terminal UI runtime, patches the service menu, injects launch animations into strategy BAT files and creates a ZIP plus SHA-256 checksum.

## 🧪 Validation

```powershell
pwsh ./scripts/Test-Repository.ps1
```

CI builds and extracts the final Windows package, then verifies:

- PowerShell syntax;
- ASCII-safe UI source;
- no direct Cyrillic literals in generated `service.bat`;
- action animation wiring;
- profile boot hooks in every strategy launcher;
- required `winws` and WinDivert files;
- SHA-256 integrity.

## ⚖️ Licensing

Original NexRoute code and documentation use the MIT License. Flowseal, zapret and WinDivert remain subject to their own licenses and notices. See [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).
