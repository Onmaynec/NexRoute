# Совместимость NexRoute 0.6.0 🖥️

## Поддерживаемые платформы

| Платформа | Статус |
|---|---|
| Windows 10 x64 | target platform |
| Windows 11 x64 | target platform |
| Windows 7/8/8.1 | не поддерживаются |
| Windows x86 | не поддерживается |
| Windows ARM64 | не валидировалась |
| Linux/macOS | package runtime не поддерживается |

Control Node поддерживает Windows PowerShell 5.1+. Native tray, notifier, Dashboard и Validation Viewer собираются как .NET Framework Windows executables.

## Терминалы и desktop session

| Среда | Статус |
|---|---|
| Windows Terminal | рекомендуется |
| Classic `cmd.exe` | поддерживается через PowerShell renderer |
| PowerShell console host | поддерживается |
| Signed-in Explorer session | требуется для interactive tray/toast/Dashboard validation |
| Запуск BAT/CMD из ZIP | не поддерживается |

RU/EN данные хранятся в UTF-8 resources. Final Strategy Lab script проверяется через Windows PowerShell 5.1 и сохраняется с UTF-8 BOM.

## IPv4 и IPv6

NexRoute 0.6.0 различает address families на уровне runtime contract:

- IPv4 и IPv6 literal/CIDR parsing;
- A/AAAA resolution с family filtering;
- family-specific TCP/HTTP probes;
- IPv4-only worker plan;
- IPv6-only worker plan;
- non-overlapping dual-stack workers;
- fail-closed limitation, если pinned upstream не рекламирует требуемую family.

CI запускает реальные synthetic worker processes для трёх режимов. Это доказывает command/process contract, но не ISP-specific bypass в пользовательской сети.

Signed validation report оставляет live IPv4/IPv6 bypass `experimental` или `unsupported` до real-machine evidence.

## Service profiles

Service Matrix содержит 15 profiles и поддерживает:

- domains и test targets;
- TCP/UDP ports;
- A/AAAA resolve hosts;
- IPv4/IPv6 literals и CIDR;
- checked external IP sources;
- отдельные per-service hostlist/IPSet и worker scopes.

Shared domain остаётся active, пока включён хотя бы один owner. Duplicate WinDivert capture scope отклоняется до launch.

## Windows notifications

Notification broker использует каскад:

```text
Windows ToastGeneric
        ↓ disabled/unavailable/error
NexRoute.Notifier.exe native balloon
        ↓ unavailable/error
legacy PowerShell or console fallback
```

Перед toast delivery проверяется `ToastNotifier.Setting`:

- `Enabled`;
- `DisabledForApplication`;
- `DisabledForUser`;
- `DisabledByGroupPolicy`;
- `DisabledByManifest`;
- unknown values fail closed.

CI подтверждает порядок каналов и history contract, но visible notification в interactive Windows session остаётся отдельным experimental check.

## DNS encryption

### DNS-over-TLS

DoT использует bundled pinned resolver с SHA-256 verification, loopback lifecycle, direct/system probes и transactional DNS rollback.

### DNS-over-HTTPS

DoH применяется только если target Windows exposes `Set-DnsClientDohServerAddress`. Наличие cmdlet не считается доказательством live encrypted routing: требуется проверка конкретного adapter и resolver.

## Network profiles

Adapter identity использует interface GUID, а не только изменяемый interface index. Synthetic tests покрывают:

- Ethernet/Wi-Fi snapshots;
- public/private category migration;
- arrival/removal events;
- restart reconciliation;
- corrupt state backup.

Physical adapter events на реальном устройстве остаются experimental.

## Возможные конфликты

- GoodbyeDPI и другие WinDivert tools;
- AdGuard и системные traffic filters;
- Killer, SmartByte и Intel Connectivity services;
- VPN clients и corporate endpoint filters;
- antivirus quarantine WinDivert;
- нестандартные proxy, route и DNS settings.

Conflict wizard отделяет evidence от guesses. Unknown security product не объявляется compatible.

## Миграция

Updater содержит automated migration fixtures:

```text
0.4.1 -> 0.6.0
0.5.0 -> 0.6.0
```

Detached transaction сохраняет user state и выполняет rollback при failed verification, replacement, launch или health policy.

Для ручной чистой миграции:

1. удалите старую service через её launcher;
2. перезагрузите Windows при stuck WinDivert state;
3. скачайте четыре verified release assets;
4. распакуйте 0.6.0 в новую директорию;
5. переносите только user-managed lists/state, а не old binaries или generated `.service/native`;
6. запустите package от администратора;
7. проверьте Service Matrix, Strategy Lab, tray и Validation Viewer.

## Честные ограничения

Hosted CI не доказывает:

- обход DPI у конкретного ISP;
- visible tray/toast behavior в user session;
- Dashboard mouse/theme rendering на каждом Windows build;
- physical network transitions;
- live DoH routing;
- full live IPv6 bypass.

Эти пункты остаются явными limitations в signed validation report.
