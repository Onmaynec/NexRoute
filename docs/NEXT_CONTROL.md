# NexRoute 0.5.0 control architecture

NexRoute 0.5.0 uses an arrow-key PowerShell TUI as the only primary interactive menu. The original verified batch service engine is retained internally as `.service/legacy-service.bat` and is called only for low-level installation and compatibility commands.

## Controls

- `Up` / `Down`: move selection;
- `Enter`: open the selected `[+]` action;
- `Escape`: return;
- `Space`: toggle an item in multi-select screens;
- `Y`: confirm an update, destructive reset, purge, or rollback.

No numeric menu input is required.

## Runtime files

- `.service/nexroute-console.ps1` — main control node;
- `.service/nexroute-monitor.ps1` — availability and automatic recovery loop;
- `.service/nexroute-tray.ps1` — tray controller and notifications;
- `.service/next/*.ps1` — menu, strategy, DNS, diagnostics, update, backup, and statistics modules;
- `.service/next-state.json` — local v3 preferences and automation state;
- `.service/history/` — Strategy Lab, availability, restart, and strategy history;
- `.service/logs/nexroute.jsonl` — structured local logs.

## Safety

Stable updates still require the official release asset and matching SHA-256 file. A full backup is created before replacement, preserved user state is restored, and installation failures roll back automatically. Automatic background checks do not install a release without explicit confirmation.
