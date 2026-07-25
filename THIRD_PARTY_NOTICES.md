# Third-Party Notices

NexRoute contains original project files and produces release archives that include third-party components. Each component remains governed by its own license and copyright notices.

## Flowseal/zapret-discord-youtube

- Project: `Flowseal/zapret-discord-youtube`
- Baseline used by NexRoute 0.1.0: `1.10.0`
- License: MIT
- Role: Windows service manager, strategies, domain/IP lists, diagnostics, tests and release layout

NexRoute modifies the presentation, branding, update endpoints and release process while preserving upstream attribution and functional compatibility.

## bol-van/zapret

- Project: `bol-van/zapret`
- License: MIT
- Role: original DPI desynchronization implementation and `winws`

## WinDivert

- Project: `basil00/WinDivert`
- License options declared by the upstream project: GNU LGPL v3 or GNU GPL v2
- Role: Windows packet capture, filtering and reinjection driver/library

WinDivert is not authored by NexRoute. Release users must retain all accompanying upstream notices and comply with the selected WinDivert licensing terms.

## Binary distribution policy

Binary files are not committed to the NexRoute Git repository. The release workflow downloads the official Flowseal release asset for the pinned upstream version, applies the NexRoute overlay and publishes a new archive with a SHA-256 checksum.

## No endorsement

The upstream projects and their contributors do not necessarily endorse NexRoute. Product names and project names are used only to identify compatibility and component origin.
