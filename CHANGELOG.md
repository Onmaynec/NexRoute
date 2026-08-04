# Changelog 📝

Все заметные изменения NexRoute документируются в этом файле. Версии используют Semantic Versioning.

## [Unreleased]

Пока нет изменений.

## [0.6.2] - 2026-08-04

### Fixed

- first-run diagnostics больше не обращается к отсутствующим свойствам старой схемы и не падает с `PropertyNotFoundException`;
- diagnostic report гарантированно предоставляет совместимые поля `administrator`, `runtime.zapret`, `network` и `conflicts[].detected`;
- `service.bat` и `nexroute.bat` открывают основной интерфейс после первой диагностики;
- заголовок консоли берётся из `.service/version.txt`, поэтому больше не показывает `NexRoute 0.5.0`;
- ручная проверка обновлений использует API-independent `nexroute-updater-entry.ps1`;
- GitHub API rate limit больше не выводится пользователю как сырая ошибка `Invoke-RestMethod`;
- stable release определяется через публичный `/releases/latest` endpoint с последовательными `Invoke-WebRequest`, `HttpWebRequest` и `curl.exe` fallback;
- если публичный endpoint недоступен, updater завершается понятной fail-closed ошибкой без перехода к rate-limited API.

### Validation

- online и offline ZIP проверяют first-run diagnostic compatibility;
- updater `Check` выполняется через deterministic `v0.6.2` fixture без обращения к `api.github.com`;
- package gate продолжает запускать `service.bat`, `nexroute.bat` и `nexroute-update.cmd` из пути с пробелами и кириллицей.

## [0.6.1] - 2026-08-04

### Fixed

- `service.bat` больше не передаёт PowerShell root-path с завершающим обратным слешем, повреждающим закрывающую кавычку Windows command line;
- `nexroute.bat`, `service.bat` и `nexroute-update.cmd` корректно запускаются из каталогов с пробелами и кириллицей;
- BAT/CMD launchers сохраняют реальный exit code вместо преждевременного `%ERRORLEVEL%` expansion внутри блоков;
- automatic update warning не ломает обычный запуск control node и не выполняется для служебных `--status`/`--lab` вызовов;
- `nexroute-update.cmd` получил детерминированный `--status` smoke mode для package validation.

### Validation

- Windows package gate копирует готовую сборку в путь `NexRoute 0.6.1 Hot Fix Тест ...` и реально запускает все три пользовательских launcher;
- regression gate отклоняет `GetFullPath`, `Illegal characters in path`, `MethodInvocationException`, `ArgumentException` и ненулевые exit codes.

## [0.6.0] - 2026-08-03

### Added

- isolated per-service `winws` workers with unique PID, log, strategy and filter scope;
- deterministic failover thresholds, cooldown, recovery and synthetic fault injection;
- IPv4-only, IPv6-only and dual-stack worker plans with explicit capability limitations;
- streamed multi-megabyte download measurements and HLS manifest/segment playback readiness;
- separate TCP/TLS and UDP transport-readiness results for Discord and Telegram;
- pinned transactional DNS-over-TLS resolver and platform-gated Windows DoH support;
- stable adapter identities, restart reconciliation and synthetic network-profile events;
- native Windows tray controller, notification fallback executable, Strategy Lab Dashboard and Validation Viewer;
- Windows `ToastGeneric` delivery with `ToastNotifier.Setting` checks and native balloon/legacy fallback;
- atomic notification history containing attempted channels and failure reasons;
- evidence-based conflict and repair wizard with backups, verification and rollback;
- validated Strategy Builder whose preview and launched worker share the same argv contract;
- portable GitHub artifact-attestation verifier without a preinstalled GitHub CLI;
- signed JSON and Markdown validation reports covering package identity, desktop self-tests and honest limitations;
- digest-matched local attestation receipt consumed by the Validation Viewer;
- detached update transaction and migration fixtures for `0.4.1 -> 0.6.0` and `0.5.0 -> 0.6.0`.

### Changed

- canonical repository, website and package version is now `0.6.0`;
- release assets now include ZIP, checksum and both validation report formats in one attestation;
- CI uses Node 24-based `actions/checkout@v6`, `actions/setup-node@v6` and `actions/upload-artifact@v7`;
- online and fully offline builds execute the same native desktop and notification delivery fixtures;
- imported validation JSON remains untrusted until a matching local verification receipt exists;
- hardware- and ISP-dependent capabilities are reported as `experimental` or `unsupported`, never synthetic success.

### Security

- updater verifies immutable release URLs, package checksum and all four attested subjects before installing validation evidence;
- wrong product/version, duplicate check IDs, unknown statuses and inconsistent `overallStatus` are rejected;
- failed required validation checks block release publication;
- notification policy denial and unknown `ToastNotifier.Setting` values fail closed to deterministic fallback;
- tampered, incomplete and offline attestation fixtures fail closed.

## [0.5.0] - 2026-08-02

### Added

- arrow-key `>[+]` control node without numeric menu input;
- confirmed one-action stable update installation and automatic restart;
- Strategy Lab scoring, sorting, history, comparison, recommendations and automatic failover;
- per-service strategies, tray controls, notifications and continuous availability monitoring;
- DNS/DoH/DoT management, network profiles, conflict checks, service repair and reset tools;
- backup selection, configuration export/import, custom profiles/strategies, logs, diagnostics and statistics;
- IPv6 CIDR, A/AAAA resolution and IPv6 readiness support.

### Changed

- English and Russian interface labels were fully renamed;
- automatic background checks never install without explicit `Y` confirmation.

## [0.4.1] - 2026-08-02

### Fixed

- пункт `[12] STRATEGY LAB` больше не падает с ошибками парсера в Windows PowerShell 5.1;
- `utils/test zapret.ps1` финализируется как UTF-8 с BOM, поэтому русские строки не превращаются в mojibake `Р…`;
- проверка готового ZIP подтверждает BOM и отсутствие синтаксических ошибок через `powershell.exe`;
- online и полностью offline release builds выполняют одинаковый regression test лаборатории.

## [0.4.0] - 2026-08-02

### Added

- production-ready многостраничный сайт в каталоге `website/`;
- Next.js App Router, React, TypeScript, Tailwind CSS, Motion и Lucide Icons;
- страницы Home, Features, Download, Docs, Security, FAQ, Changelog и кастомная 404;
- documentation layout с sidebar, mobile drawer, search, table of contents, code copy и Previous/Next;
- структурированная документация Getting Started, Service Matrix, Strategy Lab, Updates, Security, Diagnostics, Architecture и Compatibility;
- GitHub API integration для стабильного release, assets, даты, release notes, stars и forks;
- fallback-состояния без выдуманной версии при недоступности API;
- interactive HTML/CSS product mockups Service Matrix, Strategy Lab, update flow и route graph;
- SEO metadata, canonical URLs, Open Graph, Twitter cards, sitemap, robots, manifest и SoftwareApplication JSON-LD;
- инструкции запуска, сборки и Vercel deployment в `website/README.md` и `docs/WEBSITE.md`;
- отдельный website job в GitHub Actions для typecheck и production build.

### Changed

- repository contract теперь проверяет обязательные website routes, components, GitHub integration и отсутствие placeholder-кода;
- README и release metadata обновлены до NexRoute 0.4.0.

## [0.3.2] - 2026-08-02

### Added

- GitHub build provenance attestations для официального ZIP и соответствующего `.sha256` asset;
- self-verification обоих release assets через `gh attestation verify` до публикации GitHub Release;
- документация `docs/ATTESTATIONS.md`;
- Pester-контракт для attestation permissions, action version, subjects и порядка release-шагов.

### Security

- SHA-256 assets связывается с release workflow, репозиторием и source commit через Sigstore-backed attestation.

## [0.3.1] - 2026-08-01

### Added

- встроенный stable-updater;
- автоматическая проверка GitHub Releases с 24-часовым cooldown;
- ручной Update Center `nexroute-update.cmd`;
- полная резервная копия, rollback и сохранение пользовательского state;
- updater Pester fixtures и `docs/UPDATES.md`.

### Security

- draft/prerelease rejection, строгий checksum asset, официальный release path и mutex установки.

## [0.3.0] - 2026-08-01

### Added

- декларативный upstream manifest и locked Flowseal SHA-256;
- online/offline upstream resolution;
- `upstream-lock.json`, `patch-report.json` и воспроизводимый release pipeline;
- Pester-тесты path traversal, digest mismatch, missing files и local release proxy.

## [0.2.3] - 2026-08-01

### Added

- изолированные hostlist/IPSet и TCP/UDP группы каждого сервиса;
- Service Matrix state schema v2, strict ports/CIDR, 14-day last-known-good cache и privacy-safe Diagnostics;
- universal release scripts и workflow.

### Fixed

- общие домены больше не попадают одновременно во включённый и исключающий блок;
- предотвращён cross-product широких портов и адресов разных сервисов;
- повреждённое состояние восстанавливается безопасно.

## [0.2.2] - 2026-07-25

### Added

- Service Matrix schema v2;
- runtime-файлы сервисов;
- Strategy Lab probes;
- автоматическая переустановка активной стратегии;
- оформленные Game Filter и Update Watch;
- многоразмерная иконка NexRoute.

### Fixed

- SYNC HOSTS, сохранение пользовательских строк и исключение launcher из Strategy Lab.

## [0.2.1] - 2026-07-25

### Fixed

- malformed `-Root` в service actions;
- восстановлены аргументы PowerShell и classic Control Node UI.

## [0.2.0] - 2026-07-25

### Added

- матрица из 15 сервисных профилей;
- внутренние страницы и собственный значок NexRoute.

## [0.1.1] - 2026-07-25

### Fixed

- устранено повреждение русских строк в CMD;
- визуальный слой вынесен в ASCII-safe PowerShell renderer.

## [0.1.0] - 2026-07-25

### Added

- структура NexRoute;
- pinned baseline Flowseal 1.10.0;
- воспроизводимая сборка и SHA-256.
