# Changelog 📝

Все заметные изменения NexRoute документируются в этом файле. Версии используют Semantic Versioning.

## [Unreleased]

Пока нет изменений.

## [0.4.1] - 2026-08-02

### Fixed

- череп в консольном логотипе центрируется относительно полной ширины ASCII-надписи `NEXROUTE`;
- удалено влияние хвостовых пробелов ASCII-графики на визуальное выравнивание;
- устранено исключение форматирования строки и завершение интерфейса во время анимации первого запуска;
- строка прогресса больше не использует составной оператор `-f`;
- package regression suite запускает реальный первый экран с `NEXROUTE_UI_ANIMATE=1` в Windows PowerShell 5.1.

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
