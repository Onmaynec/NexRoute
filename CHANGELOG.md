# Changelog 📝

Все заметные изменения NexRoute документируются в этом файле. Версии используют Semantic Versioning.

## [Unreleased]

Пока нет изменений.

## [0.2.3] - 2026-08-01

### Added

- отдельные hostlist/IPSet и TCP/UDP `--new`-группы для каждого включённого сервиса;
- schema v2 для `services-state.json` с автоматической миграцией и резервными копиями;
- строгая семантическая проверка портов и IPv4 CIDR;
- last-known-good кэш внешних IP-источников с TTL 14 дней;
- `.service/ip-source-status.json` со статусами `fresh`, `cache` и `failed`;
- privacy-safe режим `Diagnostics`;
- поведенческий набор Pester 5.6.1;
- универсальные release scripts и workflow.

### Fixed

- общий домен больше не попадает одновременно во включённый и исключающий блок;
- широкие порты Discord, WhatsApp, Instagram и других приложений больше не образуют общий cross-product с доменами/IP остальных сервисов;
- повреждённый state JSON больше не остаётся активным без восстановления;
- невалидные адреса наподобие `999.1.1.1/33` и порты вне `1-65535` отклоняются.

### Changed

- состояние хранится в объекте `{ schemaVersion, updatedAtUtc, services }`;
- runtime теперь генерируется основным контроллером, а package entry только делегирует ему выполнение;
- release CI использует `Build-Release.ps1`, `Test-Release.ps1` и `.github/workflows/release.yml`;
- после успешного релиза workflow закрывает superseded issues `#7-#10` и PR `#4`.

## [0.2.2] - 2026-07-25

### Added

- Service Matrix schema v2 с доменами, endpoints, TCP/UDP-портами, DNS-разрешением и внешними IP-источниками;
- runtime-файлы `list-services-enabled.txt`, `ipset-services-user.txt` и `services-runtime.cmd`;
- отдельные реальные Strategy Lab probes для web, API, CDN, media, gateway и update endpoints;
- автоматическая переустановка активной стратегии службы `zapret` после изменения матрицы;
- оформленные страницы Game Filter и Update Watch;
- многоразмерная `.ico`-иконка по мотивам нового логотипа NexRoute.

### Fixed

- устранено падение `[09] SYNC HOSTS`;
- пользовательские строки `hosts` сохраняются вне управляемого блока;
- `nexroute.bat` больше не считается 22-й стратегией в Strategy Lab.

## [0.2.1] - 2026-07-25

### Fixed

- устранено падение пунктов `service.bat` из-за malformed `-Root`;
- восстановлены поглощённые аргументы PowerShell и classic Control Node UI.

## [0.2.0] - 2026-07-25

### Added

- матрица из 15 сервисных профилей;
- оформленные внутренние страницы и собственный значок NexRoute.

## [0.1.1] - 2026-07-25

### Fixed

- устранено повреждение русских строк в CMD;
- визуальный слой вынесен в ASCII-safe PowerShell renderer.

## [0.1.0] - 2026-07-25

### Added

- структура NexRoute;
- pinned baseline Flowseal `1.10.0`;
- воспроизводимая сборка и SHA-256.
