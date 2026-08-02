<div align="center">

# NexRoute 🧭

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows)](docs/COMPATIBILITY.md)
[![Flowseal baseline](https://img.shields.io/badge/Flowseal-1.10.0-6f42c1)](docs/UPSTREAM.md)
[![Version](https://img.shields.io/badge/version-0.5.0-24e1d6)](.service/version.txt)

**Консольная система управления стратегиями обхода DPI для Windows 10 и Windows 11.**

[Website source](website/README.md) · [English](docs/README_EN.md) · [Сервисы](docs/SERVICES.md) · [Обновления](docs/UPDATES.md) · [Attestations](docs/ATTESTATIONS.md) · [Upstream](docs/UPSTREAM.md) · [Архитектура](docs/ARCHITECTURE.md) · [Сборка](docs/RELEASES.md)

</div>

> [!IMPORTANT]
> NexRoute не является VPN, прокси или средством анонимизации. Проект локально управляет `winws` и WinDivert, не меняет публичный IP-адрес и применяет выбранную стратегию к трафику включённых сервисов.

## Что изменилось в 0.5.0 🧭

Версия `0.5.0` переводит NexRoute на управление стрелками без цифрового ввода и добавляет крупный набор средств автоматизации, мониторинга и диагностики.

- основное меню использует `>[+]`, стрелки, Enter и Escape;
- `[+] Check Update` после подтверждения `Y` загружает, проверяет и устанавливает стабильный релиз, выполняет post-update проверки и запускает новую версию;
- Strategy Lab сохраняет историю, измеряет latency, jitter, packet loss и download rate, оценивает YouTube/Discord/Telegram и рекомендует лучшую стратегию;
- доступны автоматический failover, стратегии по отдельным сервисам, мониторинг, трей и уведомления;
- добавлены DNS diagnostics, plain DNS/DoH/DoT, сетевые профили, backup manager, export/import, custom profiles/strategies, logs и diagnostic ZIP;
- Service Matrix принимает IPv4 и IPv6 CIDR, резолвит A/AAAA и проверяет IPv6 readiness;
- beginner/advanced modes, светлая/тёмная темы, accent colors, hotkeys, local statistics и JSON/CSV export.

Подробная архитектура: [docs/NEXT_CONTROL.md](docs/NEXT_CONTROL.md).

## Что изменилось в 0.4.1 🧪

Версия `0.4.1` исправляет запуск пункта `[12] STRATEGY LAB` в стандартном Windows PowerShell 5.1.

- финальная копия `utils/test zapret.ps1` сохраняется как UTF-8 с BOM;
- русские строки больше не превращаются в набор символов `Р…` и не ломают синтаксический анализатор;
- готовый release ZIP проверяется на наличие BOM и отсутствие PowerShell parse errors;
- отдельный regression probe запускается через `powershell.exe`, то есть через тот же Windows PowerShell, который использует пункт 12;
- онлайн- и полностью офлайн-сборки проходят одинаковую проверку.

## Что изменилось в 0.4.0 🌐

Версия `0.4.0` добавляет production-ready исходный код официального многостраничного сайта NexRoute.

- Next.js App Router, TypeScript, Tailwind CSS 4, Motion и Lucide Icons;
- страницы Home, Features, Download, Docs, Security, FAQ и Changelog;
- отдельные документы Getting Started, Service Matrix, Strategy Lab, Updates, Security, Diagnostics, Architecture и Compatibility;
- получение последнего стабильного GitHub Release, assets, даты и release notes через публичный GitHub API;
- fallback-состояние без выдуманной версии, если GitHub API недоступен;
- интерактивные HTML/CSS product mockups вместо тяжёлых изображений и canvas-сцен;
- responsive navigation, мобильный docs drawer, search, table of contents и copy-кнопки;
- Open Graph, Twitter cards, JSON-LD, sitemap, robots, manifest и кастомная 404;
- keyboard navigation, focus states и `prefers-reduced-motion`;
- отдельный GitHub Actions job для typecheck и production build сайта;
- инструкция запуска и деплоя на Vercel в `website/README.md` и `docs/WEBSITE.md`.

Сайт находится в каталоге:

```text
website/
```

Локальный запуск:

```bash
cd website
cp .env.example .env.local
npm install
npm run dev
```

## Проверяемые релизы 🔏

GitHub Actions создаёт Sigstore-backed build provenance attestation для ZIP и соответствующего `.sha256`. Оба assets проверяются до публикации GitHub Release.

```powershell
gh attestation verify .\NexRoute-0.5.0-win-x64.zip --repo Onmaynec/NexRoute
gh attestation verify .\NexRoute-0.5.0-win-x64.zip.sha256 --repo Onmaynec/NexRoute
```

Подробности: [docs/ATTESTATIONS.md](docs/ATTESTATIONS.md).

## Безопасное обновление 🔄

NexRoute содержит встроенный stable-updater:

- `nexroute.bat` проверяет новую версию перед запуском, когда автообновление включено;
- повторная автоматическая проверка выполняется не чаще одного раза в 24 часа;
- пункт `CHECK UPDATES` открывает Update Center;
- `nexroute-update.cmd` позволяет проверить обновление или выполнить rollback вручную;
- draft и prerelease-релизы не устанавливаются;
- updater требует архив `NexRoute-X.Y.Z-win-x64.zip` и соответствующий `.sha256`;
- архив проверяется по имени, версии, SHA-256, обязательным файлам, 21 стратегии и 23 patch records;
- перед установкой создаётся полная резервная копия;
- язык, Service Matrix state, кеши и пользовательские списки сохраняются;
- ошибка установки автоматически восстанавливает предыдущую версию;
- последние четыре backup-набора хранятся в соседней директории `NexRoute-backups`.

Состояние updater хранится в `.service/update-state.json`. Подробности: [docs/UPDATES.md](docs/UPDATES.md).

## Проверяемое происхождение сборки 🧾

NexRoute использует декларативный контракт Flowseal:

```text
.service/upstream-manifest.json
```

В Release ZIP создаются:

```text
.service/upstream-manifest.json
.service/upstream-lock.json
.service/patch-report.json
NEXROUTE_BUILD_INFO.txt
```

`upstream-lock.json` подтверждает конкретный Flowseal asset, размер и SHA-256. `patch-report.json` фиксирует изменённые файлы, patch IDs и hashes до/после. Содержимое пользовательских списков в provenance-файлы не записывается.

Онлайн-сборка:

```powershell
pwsh ./scripts/Build-Release.ps1 `
  -Version 0.5.0 `
  -OutputDirectory ./artifacts `
  -UpstreamCachePath ./cache/zapret-discord-youtube-1.10.0.zip
```

Полностью офлайн-повтор:

```powershell
pwsh ./scripts/Build-Release.ps1 `
  -Version 0.5.0 `
  -OutputDirectory ./artifacts-offline `
  -UpstreamArchive ./cache/zapret-discord-youtube-1.10.0.zip
```

Офлайн-архив обязан совпасть с locked SHA-256 и обязательной структурой. Простого совпадения имени недостаточно.

## Service Matrix v2 🧩

Матрица содержит 15 профилей: YouTube, Discord, ChatGPT, FaceTime, Snapchat, Viber, Signal, X, Instagram, Facebook, Telegram, LinkedIn, TikTok, WhatsApp и CaseBattle.

Для каждого профиля описаны `domains`, `testTargets`, `tcpPorts`, `udpPorts`, `resolveHosts`, `ipCidrs` и `ipSources`. Каждая из 21 реальной стратегии получает отдельные доменные и IP-фильтры TCP/UDP.

Создаваемые runtime-файлы:

```text
lists/list-services-enabled.txt
lists/ipset-services-user.txt
lists/list-service-<service>.txt
lists/ipset-service-<service>.txt
.service/services-runtime.cmd
.service/ip-source-status.json
```

## Состояние и Diagnostics 🩺

Service Matrix хранит состояние по schema v2 и мигрирует старый плоский JSON с backup. Повреждённое состояние сохраняется отдельно и заменяется безопасными значениями по умолчанию.

Privacy-safe отчёт:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .service\nexroute-services.ps1 `
  -Mode Diagnostics `
  -Root .
```

Отчёт содержит версию, включённые ID сервисов, количество runtime-записей, статусы IP-источников, hashes runtime-файлов, Windows/PowerShell и состояние службы. Имена пользователей, содержимое пользовательских списков и внешние пути не включаются.

## Быстрый старт 🚀

1. Скачайте `NexRoute-0.5.0-win-x64.zip` и `.sha256` из Releases.
2. При необходимости проверьте оба файла через `gh attestation verify`.
3. Полностью распакуйте архив в новую папку.
4. Запустите `NexRoute.lnk`, `nexroute.bat` или `service.bat` от имени администратора.
5. Выберите стратегию и установите её как службу.
6. Настройте `[14] SERVICE MATRIX`.
7. Используйте `[12] STRATEGY LAB` для последовательного сравнения стратегий.
8. Настройте обновления через `[6] CHECK UPDATES` или `nexroute-update.cmd`.

Не запускайте BAT/CMD-файлы непосредственно из ZIP.

## Системные требования 🪟

- Windows 10 x64 или Windows 11 x64;
- Windows PowerShell 5.1+;
- права администратора для установки и перезапуска службы;
- `curl.exe` для отдельных функций Strategy Lab;
- доступ к GitHub Releases для онлайн-обновлений;
- GitHub CLI только для дополнительной проверки build provenance.

## Проверки CI ✅

CI проверяет:

- PowerShell AST parsing для `.ps1` и `.psm1`;
- Service Matrix, upstream contract, updater и release attestation contract через Pester `5.6.1`;
- stable-only metadata, checksum mismatch, cooldown, state preservation и rollback;
- pinned Flowseal `1.10.0`, locked SHA-256 и обязательную структуру upstream ZIP;
- online/offline сборку, 23 patch-targets, 21 стратегию и 15 сервисных профилей;
- UTF-8 BOM и синтаксис готовой Strategy Lab через Windows PowerShell 5.1;
- SHA-256 и self-verification attestations до публикации релиза;
- структуру сайта, обязательные маршруты, TypeScript typecheck и production build Next.js.

## Ограничения ⚠️

Эффективность зависит от провайдера, региона, DNS, версии приложений и конфигурации DPI. Текущий сетевой runtime ориентирован на IPv4; IPv6-only endpoints требуют отдельного расширения.

Locked upstream, checksum updater-а и GitHub build provenance защищают целостность и происхождение сборки, но не являются Windows Authenticode-подписью издателя.

## Лицензирование ⚖️

Собственный код, сайт и документация NexRoute распространяются по MIT. Flowseal, zapret и WinDivert сохраняют собственные лицензии и уведомления. См. [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Автор 👤

**Onmaynec** — [@Onmaynec](https://github.com/Onmaynec)

---

**NexRoute 0.5.0** · Baseline: **Flowseal 1.10.0** · Windows 10/11 x64
