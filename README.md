<div align="center">
  
# NexRoute 🧭

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows)](docs/COMPATIBILITY.md)
[![Flowseal baseline](https://img.shields.io/badge/Flowseal-1.10.0-6f42c1)](docs/UPSTREAM.md)
[![Version](https://img.shields.io/badge/version-0.3.2-24e1d6)](.service/version.txt)

**Консольная система управления стратегиями обхода DPI для Windows 10 и Windows 11.**

[English](docs/README_EN.md) · [Сервисы](docs/SERVICES.md) · [Обновления](docs/UPDATES.md) · [Attestations](docs/ATTESTATIONS.md) · [Upstream](docs/UPSTREAM.md) · [Архитектура](docs/ARCHITECTURE.md) · [Сборка](docs/RELEASES.md)

</div>

> [!IMPORTANT]
> NexRoute не является VPN, прокси или средством анонимизации. Проект локально управляет `winws` и WinDivert, не меняет публичный IP-адрес и применяет выбранную стратегию к трафику включённых сервисов.

## Что изменилось в 0.3.2 🧾

Версия `0.3.2` добавляет проверяемое происхождение официальных release assets.

- GitHub Actions создаёт Sigstore-backed build provenance attestation для ZIP и соответствующего `.sha256`;
- release workflow получает только минимально необходимые OIDC/attestation permissions;
- оба assets проверяются командой `gh attestation verify` до публикации GitHub Release;
- Pester-контракт фиксирует версию `actions/attest`, permissions, состав подписываемых файлов и порядок release-шагов;
- пользователь может проверить, что скачанный файл создан workflow репозитория `Onmaynec/NexRoute` из конкретного commit;
- attestation дополняет SHA-256, upstream lock и patch report, но не заменяет Windows Authenticode code signing.

Проверка после загрузки релиза:

```powershell
gh attestation verify .\NexRoute-0.3.2-win-x64.zip --repo Onmaynec/NexRoute
gh attestation verify .\NexRoute-0.3.2-win-x64.zip.sha256 --repo Onmaynec/NexRoute
```

Подробности: [docs/ATTESTATIONS.md](docs/ATTESTATIONS.md).

## Безопасное обновление 🔄

NexRoute содержит встроенный stable-updater:

- `nexroute.bat` проверяет новую версию перед запуском, когда автообновление включено;
- повторная автоматическая проверка выполняется не чаще одного раза в 24 часа;
- пункт `CHECK UPDATES` открывает Update Center;
- отдельный `nexroute-update.cmd` позволяет проверить обновление или выполнить rollback вручную;
- draft и prerelease-релизы не устанавливаются;
- updater требует ровно два официальных assets: `NexRoute-X.Y.Z-win-x64.zip` и соответствующий `.sha256`;
- архив проверяется по имени, версии, SHA-256, обязательным файлам, 21 стратегии и 23 patch records;
- перед установкой создаётся полная резервная копия;
- язык, Service Matrix state, кеши и пользовательские списки сохраняются;
- ошибка установки автоматически восстанавливает предыдущую версию;
- последние четыре backup-набора хранятся в соседней директории `NexRoute-backups`;
- защита mutex не позволяет двум updater-процессам изменять установку одновременно.

Подробности: [docs/UPDATES.md](docs/UPDATES.md).

## Проверяемое происхождение сборки 🧾

NexRoute `0.3.x` использует декларативный контракт Flowseal:

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

`upstream-lock.json` подтверждает конкретный Flowseal asset, его размер и SHA-256. `patch-report.json` подтверждает, какие файлы NexRoute изменил и какими стали их hashes. Содержимое пользовательских списков в provenance-файлы не записывается.

Официальный архив Flowseal сначала загружается и проверяется. Подмена asset, несовпадение размера, GitHub digest, SHA-256 или обязательной структуры останавливают сборку до упаковки NexRoute.

Начиная с `0.3.2`, GitHub build provenance attestation дополнительно связывает SHA-256 опубликованных assets с release workflow, репозиторием и source commit.

## Онлайн- и офлайн-сборка 📦

Онлайн-сборка с сохранением проверенного upstream-архива:

```powershell
pwsh ./scripts/Build-Release.ps1 `
  -Version 0.3.2 `
  -OutputDirectory ./artifacts `
  -UpstreamCachePath ./cache/zapret-discord-youtube-1.10.0.zip
```

Повторная сборка без обращения к Flowseal/GitHub Release API:

```powershell
pwsh ./scripts/Build-Release.ps1 `
  -Version 0.3.2 `
  -OutputDirectory ./artifacts-offline `
  -UpstreamArchive ./cache/zapret-discord-youtube-1.10.0.zip
```

Офлайн-архив обязан совпасть с SHA-256 из manifest. Простое совпадение имени файла недостаточно.

## Service Matrix v2 🧩

Матрица содержит 15 профилей: YouTube, Discord, ChatGPT, FaceTime, Snapchat, Viber, Signal, X, Instagram, Facebook, Telegram, LinkedIn, TikTok, WhatsApp и CaseBattle.

Для каждого профиля описаны `domains`, `testTargets`, `tcpPorts`, `udpPorts`, `resolveHosts`, `ipCidrs` и `ipSources`.

При применении создаются общие совместимые списки и отдельные файлы каждого включённого сервиса:

```text
lists/list-services-enabled.txt
lists/ipset-services-user.txt
lists/list-service-<service>.txt
lists/ipset-service-<service>.txt
.service/services-runtime.cmd
.service/ip-source-status.json
```

Каждая из 21 настоящей стратегии Flowseal получает отдельные доменные и IP-фильтры TCP/UDP. Общий домен исключается только тогда, когда выключены все использующие его сервисы. `nexroute.bat` и `nexroute-update.cmd` являются launcher-файлами и не считаются стратегиями.

## Состояние и диагностика 🩺

Service Matrix хранит состояние по schema v2:

```json
{
  "schemaVersion": 2,
  "updatedAtUtc": "...",
  "services": {
    "youtube": true,
    "discord": true
  }
}
```

Старый плоский JSON мигрируется с backup. Повреждённое состояние сохраняется отдельно и заменяется безопасными значениями по умолчанию.

Privacy-safe отчёт создаётся командой:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .service\nexroute-services.ps1 `
  -Mode Diagnostics `
  -Root .
```

Отчёт содержит версию, включённые ID сервисов, количество сгенерированных записей, статусы IP-источников, hashes runtime-файлов, Windows/PowerShell и состояние службы. Имена пользователей, содержимое пользовательских списков и внешние пути не включаются.

Updater хранит отдельное состояние:

```text
.service/update-state.json
```

В нём записываются текущая и последняя найденная версия, время следующей проверки, результат операции, путь к backup и SHA-256 установленного пакета.

## Быстрый старт 🚀

1. Скачайте `NexRoute-0.3.2-win-x64.zip` и `.sha256` из Releases.
2. При необходимости проверьте оба файла через `gh attestation verify`.
3. Полностью распакуйте архив в новую папку.
4. Запустите `NexRoute.lnk`, `nexroute.bat` или `service.bat` от имени администратора.
5. Выберите стратегию и установите её как службу.
6. Настройте `[14] SERVICE MATRIX`.
7. Включите автообновление через `[6] CHECK UPDATES`, если оно требуется.
8. Для ручной проверки или rollback используйте `nexroute-update.cmd`.
9. При необходимости запустите `[12] STRATEGY LAB`.

Не запускайте BAT/CMD-файлы непосредственно из ZIP.

## Системные требования 🪟

- Windows 10 x64 или Windows 11 x64;
- Windows PowerShell 5.1+;
- права администратора для установки и перезапуска службы;
- `curl.exe` для Strategy Lab;
- доступ к GitHub Releases для онлайн-обновлений;
- GitHub CLI только для дополнительной проверки build provenance attestation.

## Проверки Release ✅

CI проверяет:

- PowerShell AST parsing для `.ps1` и `.psm1`;
- Service Matrix, upstream contract, updater и release attestation contract через Pester `5.6.1`;
- updater fixtures без обращения к реальному NexRoute Release;
- stable-only metadata, checksum mismatch, сохранение пользовательского state, cooldown и rollback;
- pinned Flowseal `1.10.0` и locked SHA-256;
- обязательную структуру upstream ZIP;
- онлайн- и офлайн-сборку;
- ровно 23 patch-targets и уникальные patch IDs;
- hashes до/после каждого изменённого файла;
- 21 стратегию и 15 сервисных профилей;
- runtime, Diagnostics, EN/RU страницы, Update Center, иконку и SHA-256 итогового ZIP;
- создание и self-verification attestations для ZIP и `.sha256` до публикации релиза.

## Ограничения ⚠️

Эффективность обхода зависит от провайдера, региона, DNS, версии приложений и конфигурации DPI. В `0.3.2` сетевой runtime обрабатывает IPv4; IPv6-only endpoints требуют отдельной будущей поддержки.

Locked upstream, checksum updater-а и GitHub build provenance attestation защищают целостность и проверяемое происхождение сборки. Они не являются Windows Authenticode-подписью издателя.

## Лицензирование ⚖️

Собственный код и документация NexRoute распространяются по MIT. Flowseal, zapret и WinDivert сохраняют собственные лицензии и уведомления. См. [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Автор 👤

**Onmaynec** — [@Onmaynec](https://github.com/Onmaynec)

---

**NexRoute 0.3.2** · Baseline: **Flowseal 1.10.0** · Windows 10/11 x64
