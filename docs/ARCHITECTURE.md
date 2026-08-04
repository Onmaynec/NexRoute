# Архитектура NexRoute 0.6.0 🏗️

## Принцип

NexRoute не заменяет сетевой движок zapret. Проект создаёт контролируемый Windows distribution поверх immutable Flowseal `1.10.0`, добавляя service isolation, diagnostics, native desktop tools, transactional updates и verifiable release evidence.

```text
Immutable Flowseal 1.10.0 archive
        │
        ├── winws + WinDivert + payloads
        ├── 21 strategy launchers
        ├── lists / utils / service.bat
        └── committed SHA-256 + required paths
                       │
                       ▼
              Build-Release / Build-Package
        ├── validates upstream identity
        ├── applies 23 tracked patch targets
        ├── copies NexRoute overlay/runtime
        ├── compiles 4 native Windows tools
        ├── generates icon and shortcut
        ├── verifies package behavior
        └── creates ZIP + SHA-256
                       │
                       ▼
                 Release workflow
        ├── online and offline rebuild gates
        ├── signed validation JSON/Markdown
        ├── 4-subject artifact attestation
        ├── verification before publication
        └── stable GitHub Release
```

## Control layer

| Компонент | Ответственность |
|---|---|
| `overlay/.service/nexroute-console.ps1` | arrow-key Control Node и feature routing |
| `overlay/.service/nexroute-services.ps1` | Service Matrix controller и runtime generation |
| `overlay/.service/next/nexroute-runtime-extensions.ps1` | deterministic loading order новых runtime modules |
| `overlay/.service/next/nexroute-workers.ps1` | worker lifecycle и persisted state |
| `overlay/.service/next/nexroute-worker-plans.ps1` | service/address-family plans и scope validation |
| `overlay/.service/nexroute-worker-host.ps1` | packaged worker entrypoint |
| `overlay/.service/next/nexroute-strategy-lab-v2.ps1` | measurements, history, scoring и recommendations |
| `overlay/.service/next/nexroute-update-transaction.ps1` | detached update transaction и rollback |
| `overlay/.service/next/nexroute-attestation-v2.ps1` | four-subject release verification и receipt install |

## Per-service runtime

Service Matrix создаёт отдельный worker plan для каждого enabled service assignment.

Worker identity включает:

- service ID;
- strategy ID;
- address family;
- PID file;
- log file;
- hostlist/IPSet paths;
- TCP/UDP capture scope;
- persisted health/failover state.

Supervisor отклоняет duplicate capture scopes до запуска. Stop/failover одного worker не завершает unrelated processes.

```text
Service Matrix state
        │
        ▼
Worker plan catalog
        │
        ├── youtube / ipv4 / strategy A / PID + log
        ├── youtube / ipv6 / strategy A / PID + log
        ├── discord / dual-stack / strategy B / PID + log
        └── telegram / ipv4 / strategy C / PID + log
```

## Deterministic failover

Health state использует:

- consecutive-failure threshold;
- recovery threshold;
- cooldown;
- maximum switch count;
- persisted history;
- synthetic healthy/degraded/failed probes.

Failover заменяет только failed service worker. Healthy PIDs сохраняются.

## Address-family contract

IPv6 support не ограничивается CIDR parsing.

Runtime содержит:

- IPv4/IPv6 classification;
- A/AAAA family filtering;
- family-selected TCP и HTTP probes;
- IPv4-only, IPv6-only и dual-stack plans;
- non-overlapping scopes;
- explicit unsupported limitation при отсутствии upstream capability.

Live ISP behavior остаётся вне synthetic CI proof.

## Strategy Lab measurement layer

Strategy Lab сохраняет schema-versioned history в:

```text
.service/history/strategy-lab/
```

Measurement contract:

- download: streamed multi-megabyte payload, bytes, elapsed time и Mbps;
- YouTube: HLS master manifest, variant playlist и media segment;
- realtime: TCP/TLS reachability отдельно от UDP readiness;
- scoring: availability, throughput, latency, jitter, loss и explicit readiness fields.

Native Dashboard читает те же history documents, что и terminal UI.

## DNS и network profiles

DoT использует pinned local resolver с checksum, loopback lifecycle, direct/system probes и DNS snapshot rollback.

DoH использует Windows platform capability только при наличии required cmdlet; live routing не объявляется без adapter-level evidence.

Network profile identity основана на interface GUID и category/media properties. Startup reconciliation восстанавливает состояние после restart.

## Native desktop layer

Системный .NET Framework compiler создаёт:

```text
NexRoute.Tray.exe
NexRoute.Notifier.exe
NexRoute.Dashboard.exe
NexRoute.Validation.exe
```

### Tray

- single-instance mutex;
- NotifyIcon menu;
- service actions;
- startup task management;
- Dashboard/Viewer launch;
- recovery paths.

### Notification broker

```text
ToastGeneric + ToastNotifier.Setting
        ↓ failure/disabled
NexRoute.Notifier native balloon
        ↓ unavailable
legacy PowerShell / console
```

Atomic history хранит channel, attempts и errors.

### Dashboard

- Strategy Lab data store;
- metric/strategy filters;
- interactive chart zoom/tooltips;
- light/dark/system themes;
- accent colors.

### Validation Viewer

- schema/product/version validation;
- unique check IDs;
- supported status validation;
- overall/check consistency;
- explicit limitations;
- local attestation receipt digest matching.

Builder компилирует repository C# sources напрямую. Build-time regex source rewrite запрещён acceptance test.

## Diagnostics and repair

Conflict diagnostics разделяет:

- evidence-backed findings;
- known product evidence;
- unknown products;
- absent/unproven conditions.

Repair transaction создаёт snapshot до изменений, выполняет apply, verification и rollback. Покрываются firewall, VPN metrics, WinDivert service, DNS, route/adapter и Defender exclusion cases.

## Strategy Builder

Builder использует typed definition для filters, ports, desync modes, repeats, fake payloads и list files.

Unsafe broad/unscoped/path-traversal/protocol-incompatible definitions отклоняются. Preview и launched worker получают один argv array; parser/serializer round-trip не должен менять command.

## Transactional updater

Updater flow:

```text
stable release metadata
        ↓
4 exact immutable assets
        ↓
checksum + 4 attestations
        ↓
signed JSON validation
        ↓
package structural verification
        ↓
backup + detached handoff
        ↓
stop / replace / start
        ↓
health policy
   ┌────┴────┐
 commit    rollback
```

Migration fixtures покрывают 0.4.1 и 0.5.0 -> 0.6.0.

## Release validation and trust

Workflow создаёт validation schema v1 с:

- environment/provenance;
- package/upstream/native identities;
- required automated checks;
- experimental/unsupported limitations;
- derived overall status.

ZIP, checksum, JSON и Markdown attested вместе. Portable verifier устанавливает report и digest-matched receipt атомарно.

## Source versus Release

### Git repository

- PowerShell/BAT/C# sources;
- JSON configuration;
- website;
- tests/workflows;
- documentation and licenses;
- no generated executable/archive artifacts.

### GitHub Release

- Flowseal runtime and strategies;
- generated icon/shortcut;
- four native executables;
- portable verifier and resolver;
- package provenance;
- ZIP + checksum;
- validation JSON + Markdown.

## Trust boundary

Automated gate proves source contracts, package identities, synthetic workers, updater rollback, native self-tests, online/offline rebuild and signed report consistency.

It does not prove ISP-specific bypass, visible interactive desktop behavior, physical adapters, live DoH routing or full live IPv6 bypass. Those remain explicit limitations.

Artifact attestation is not Windows Authenticode code signing.

## Upstream update process

Flowseal update requires a dedicated PR:

1. review release notes and source/asset changes;
2. verify exact archive and digest;
3. update manifest;
4. inspect all 23 patch targets;
5. rebuild online/offline;
6. run full behavioral and desktop gate;
7. validate Windows 10/11 live scenarios separately;
8. update changelog, release notes and limitations.
