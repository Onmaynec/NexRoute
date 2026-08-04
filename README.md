<div align="center">

# NexRoute 🧭

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows)](docs/COMPATIBILITY.md)
[![Flowseal baseline](https://img.shields.io/badge/Flowseal-1.10.0-6f42c1)](docs/UPSTREAM.md)
[![Version](https://img.shields.io/badge/version-0.6.1-24e1d6)](.service/version.txt)

**Локальная Windows-система управления стратегиями обхода DPI с изолированными сервисными workers, проверяемыми обновлениями и честным release validation.**

[Website source](website/README.md) · [English](docs/README_EN.md) · [Сервисы](docs/SERVICES.md) · [Обновления](docs/UPDATES.md) · [Attestations](docs/ATTESTATIONS.md) · [Upstream](docs/UPSTREAM.md) · [Архитектура](docs/ARCHITECTURE.md) · [Сборка](docs/RELEASES.md)

</div>

> [!IMPORTANT]
> NexRoute не является VPN, прокси или средством анонимизации. Проект локально управляет `winws` и WinDivert, не меняет публичный IP-адрес и применяет выбранные стратегии только к трафику включённых сервисов.

## NexRoute 0.6.1 — Hot Bug Fix 🩹

Версия `0.6.1` исправляет критическую ошибку запуска официального Windows-пакета `0.6.0`.

- `service.bat` больше не передаёт `%~dp0` с завершающим `\` внутри кавычек;
- `nexroute.bat`, `service.bat` и `nexroute-update.cmd` работают из папок с пробелами и кириллицей;
- launchers корректно возвращают фактический exit code;
- automatic update warning не прерывает обычный запуск интерфейса;
- Windows CI реально запускает все три entry point из каталога `NexRoute 0.6.1 Hot Fix Тест <guid>`.

Полный функциональный baseline остаётся от версии 0.6.0 и описан ниже.

## NexRoute 0.6.0 🚀

Версия `0.6.0` переводит проект от набора деклараций к проверяемому production-контракту.

### Изолированный runtime и failover

- каждый включённый сервис может работать в отдельном `winws` worker с собственными PID, логом, стратегией и filter scope;
- пересекающиеся WinDivert scopes отклоняются до запуска;
- остановка или сбой одного сервиса не завершает остальные workers;
- failover использует consecutive-failure/recovery thresholds, cooldown и maximum-switch limits;
- synthetic healthy/degraded/failed probes проверяют переключение без зависимости от интернета;
- история workers и failover восстанавливается после перезапуска control node.

### Strategy Lab и измерения

- download probe реально передаёт многомегабайтный payload и считает bytes, elapsed time и Mbps;
- YouTube readiness проверяет HLS manifest, variant playlist и media segment;
- Discord и Telegram разделяют TCP/TLS reachability и UDP transport readiness;
- HTTP latency не называется качеством звонка или MOS;
- нативный Dashboard читает ту же историю Strategy Lab, поддерживает фильтры, zoom, темы и accent colors.

### DNS, adapters и IPv6

- DoH используется только когда Windows предоставляет соответствующий platform capability;
- DoT работает через bundled pinned resolver с проверкой SHA-256 и transactional rollback;
- Ethernet/Wi-Fi и public/private profiles сопоставляются по стабильным adapter identities;
- IPv4-only, IPv6-only и dual-stack worker plans проверяются отдельными synthetic fixtures;
- live ISP и hardware-dependent возможности остаются `experimental` или `unsupported`, пока нет реального machine evidence.

### Нативные Windows-инструменты

- `NexRoute.Tray.exe` — single-instance tray controller со startup registration и recovery paths;
- `NexRoute.Notifier.exe` — deterministic native balloon fallback;
- Windows notification broker сначала использует `ToastGeneric`, проверяет `ToastNotifier.Setting`, затем переходит на native balloon и legacy/console fallback;
- `NexRoute.Dashboard.exe` отображает Strategy Lab history;
- `NexRoute.Validation.exe` показывает signed release checks и ограничения;
- `nexroute-validation.cmd` открывает Validation Viewer напрямую;
- tray-меню содержит `Open Validation Report`.

### Безопасное редактирование, ремонт и обновление

- conflict wizard отделяет evidence-backed findings от предположений;
- firewall, VPN, WinDivert, route, DNS, adapter и service repairs создают backup и имеют rollback contract;
- неизвестные security products не объявляются совместимыми;
- Strategy Builder валидирует filters, ports, desync modes, repeats, fake payloads и list files;
- preview и запускаемый worker используют один и тот же argv contract;
- updater выполняет detached transaction, сохраняет пользовательские данные и автоматически откатывает failed health check;
- migration fixtures покрывают `0.4.1 -> 0.6.0`, `0.5.0 -> 0.6.0` и `0.6.0 -> 0.6.1`.

Подробный production-hardening критерий: [docs/RELEASE_0.6.0_ACCEPTANCE.md](docs/RELEASE_0.6.0_ACCEPTANCE.md).

## Проверяемый релиз 🔏

Для версии 0.6.1 публикуются четыре связанных asset:

```text
NexRoute-0.6.1-win-x64.zip
NexRoute-0.6.1-win-x64.zip.sha256
NexRoute-0.6.1-validation.json
NexRoute-0.6.1-validation.md
```

Все четыре файла входят в одну GitHub artifact attestation. Portable verifier проверяет immutable release URLs, SHA-256 package и attestation каждого subject. После успешной проверки validation report и digest-matched receipt атомарно устанавливаются в `.service`.

Дополнительная ручная проверка:

```powershell
gh attestation verify .\NexRoute-0.6.1-win-x64.zip --repo Onmaynec/NexRoute
gh attestation verify .\NexRoute-0.6.1-win-x64.zip.sha256 --repo Onmaynec/NexRoute
gh attestation verify .\NexRoute-0.6.1-validation.json --repo Onmaynec/NexRoute
gh attestation verify .\NexRoute-0.6.1-validation.md --repo Onmaynec/NexRoute
```

Validation Viewer не доверяет импортированному JSON автоматически. До появления matching local receipt документ отображается как `attestation-not-verified`. Wrong product/version, duplicate check IDs, неизвестные статусы и несогласованный `overallStatus` отклоняются.

Подробности: [docs/ATTESTATIONS.md](docs/ATTESTATIONS.md).

## Быстрый старт 🪟

1. Скачайте ZIP, `.sha256` и оба validation report из одного GitHub Release.
2. Проверьте assets через встроенный portable verifier или `gh attestation verify`.
3. Полностью распакуйте архив в новую папку.
4. Запустите `NexRoute.lnk`, `nexroute.bat` или `service.bat` от имени администратора.
5. Выберите стратегию и настройте `[14] SERVICE MATRIX`.
6. Запустите `[12] STRATEGY LAB` для сравнения стратегий.
7. Используйте tray для service actions, Dashboard и Validation Viewer.
8. Настройте обновления через `[6] CHECK UPDATES` или `nexroute-update.cmd`.

Не запускайте BAT/CMD-файлы непосредственно из ZIP.

## Service Matrix v2 🧩

Матрица содержит 15 профилей: YouTube, Discord, ChatGPT, FaceTime, Snapchat, Viber, Signal, X, Instagram, Facebook, Telegram, LinkedIn, TikTok, WhatsApp и CaseBattle.

Для каждого профиля описаны `domains`, `testTargets`, `tcpPorts`, `udpPorts`, `resolveHosts`, `ipCidrs` и `ipSources`. Каждая из 21 реальной стратегии получает отдельные доменные и IP-фильтры TCP/UDP.

Runtime-файлы:

```text
lists/list-services-enabled.txt
lists/ipset-services-user.txt
lists/list-service-<service>.txt
lists/ipset-service-<service>.txt
.service/services-runtime.cmd
.service/ip-source-status.json
```

## Безопасное обновление 🔄

NexRoute содержит stable-only updater:

- `nexroute.bat` выполняет automatic update check с 24-часовым cooldown;
- установка требует явного подтверждения пользователя;
- draft и prerelease releases отклоняются;
- updater требует точные asset names, checksum и attestation verification;
- перед replacement создаётся backup;
- язык, Service Matrix state, caches и пользовательские lists сохраняются;
- failure during verification, extraction, replacement, launch или health check вызывает rollback;
- состояние хранится в `.service/update-state.json`;
- последние четыре backup-набора сохраняются в `NexRoute-backups`.

Подробности: [docs/UPDATES.md](docs/UPDATES.md).

## Воспроизводимая сборка 🧾

NexRoute использует immutable Flowseal `1.10.0` archive с locked SHA-256.

В package создаются:

```text
.service/upstream-manifest.json
.service/upstream-lock.json
.service/patch-report.json
NEXROUTE_BUILD_INFO.txt
```

Онлайн-сборка через предварительно проверенный cache:

```powershell
pwsh ./scripts/Build-Release.ps1 `
  -Version 0.6.1 `
  -OutputDirectory ./artifacts `
  -UpstreamCachePath ./cache/zapret-discord-youtube-1.10.0.zip
```

Полностью offline rebuild:

```powershell
pwsh ./scripts/Build-Release.ps1 `
  -Version 0.6.1 `
  -OutputDirectory ./artifacts-offline `
  -UpstreamArchive ./cache/zapret-discord-youtube-1.10.0.zip
```

Offline package обязан использовать тот же upstream digest, 23 tracked patch targets, 21 strategies и 15 service profiles.

## Diagnostics 🩺

Privacy-safe отчёт:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .service\nexroute-services.ps1 `
  -Mode Diagnostics `
  -Root .
```

Отчёт содержит версию, ID включённых сервисов, количество runtime-записей, статусы IP sources, hashes runtime-файлов, Windows/PowerShell и состояние службы. Имена пользователей, содержимое пользовательских списков и внешние пути не включаются.

## Сайт 🌐

Исходный код официального сайта находится в `website/`.

```bash
cd website
cp .env.example .env.local
npm install
npm run dev
```

Production validation выполняет TypeScript typecheck и Next.js build.

## Системные требования

- Windows 10 x64 или Windows 11 x64;
- Windows PowerShell 5.1+;
- права администратора для установки и управления WinDivert/service runtime;
- `curl.exe` для отдельных Strategy Lab probes;
- доступ к GitHub Releases для online updates;
- подписанная Windows desktop session для проверки интерактивных tray, toast и Dashboard behaviors.

## CI и release gate ✅

Pull request gate проверяет:

- PowerShell AST parsing;
- Pester behavioral acceptance suite;
- website typecheck и production build;
- pinned upstream SHA-256 и 23 patch targets;
- online package build и extraction self-test;
- полностью offline rebuild и повторный self-test;
- native tray, notifier, Dashboard и Validation Viewer assemblies;
- notification channels `windows-toast -> native-balloon`;
- validation trust states `attestation-not-verified -> attestation-receipt-matched`;
- фактический запуск `service.bat`, `nexroute.bat` и `nexroute-update.cmd` из пути с пробелами и кириллицей;
- package SHA-256, report consistency и updater rollback fixtures.

Release workflow дополнительно создаёт JSON/Markdown validation report, подписывает четыре assets, проверяет attestations и только после этого создаёт GitHub Release.

## Честные ограничения ⚠️

Автоматизация не доказывает:

- эффективность обхода DPI у конкретного ISP;
- реальный interactive toast в пользовательской Windows session;
- Dashboard mouse/theme rendering на каждом Windows build;
- физические Ethernet/Wi-Fi transitions;
- live DoH routing на целевом adapter;
- полный IPv6 bypass в сети пользователя.

Эти пункты остаются `experimental` или `unsupported` в signed validation report. Locked upstream, checksum и GitHub provenance защищают целостность и происхождение сборки, но не являются Windows Authenticode-подписью издателя.

## Лицензирование ⚖️

Собственный код, сайт и документация NexRoute распространяются по MIT. Flowseal, zapret и WinDivert сохраняют собственные лицензии и уведомления. См. [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Автор 👤

**Onmaynec** — [@Onmaynec](https://github.com/Onmaynec)

---

**NexRoute 0.6.1** · Baseline: **Flowseal 1.10.0** · Windows 10/11 x64
