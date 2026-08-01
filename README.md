<div align="center">

<img src="assets/nexroute-mark.svg" width="150" alt="NexRoute emblem">

# NexRoute 🧭

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows)](docs/COMPATIBILITY.md)
[![Flowseal baseline](https://img.shields.io/badge/Flowseal-1.10.0-6f42c1)](docs/UPSTREAM.md)
[![Version](https://img.shields.io/badge/version-0.3.0-24e1d6)](.service/version.txt)

**Консольная система управления стратегиями обхода DPI для Windows 10 и Windows 11.**

[English](docs/README_EN.md) · [Сервисы](docs/SERVICES.md) · [Upstream](docs/UPSTREAM.md) · [Архитектура](docs/ARCHITECTURE.md) · [Сборка](docs/RELEASES.md)

</div>

> [!IMPORTANT]
> NexRoute не является VPN, прокси или средством анонимизации. Проект локально управляет `winws` и WinDivert, не меняет публичный IP-адрес и применяет выбранную стратегию к трафику включённых сервисов.

## Что изменилось в 0.3.0 🔐

Версия `0.3.0` переводит интеграцию Flowseal и патчи сборки на проверяемый декларативный контракт.

- `.service/upstream-manifest.json` фиксирует repository, tag, имя release-asset, минимальный размер, обязательные пути и SHA-256;
- официальный архив Flowseal сначала загружается и полностью проверяется, а базовый builder получает его через локальный verified proxy;
- подмена asset, несовпадение размера, GitHub digest или SHA-256 останавливают сборку до распаковки релиза;
- пакет содержит `.service/upstream-lock.json` с фактической идентичностью использованного архива;
- пакет содержит `.service/patch-report.json` с ID патчей, целями, количеством операций и SHA-256 файлов до/после изменения;
- все `21` стратегии, `service.bat` и Strategy Lab образуют ровно **23 отслеживаемые patch-targets**;
- важные anchors теперь имеют ожидаемое число совпадений: изменение структуры upstream приводит к понятной ошибке вместо частично пропатченного ZIP;
- `Build-Release.ps1` поддерживает офлайн-сборку через `-UpstreamArchive`;
- CI выполняет онлайн-сборку, сохраняет проверенный архив, затем повторяет сборку полностью офлайн и сравнивает upstream lock, 21 стратегию, 15 сервисов и patch report;
- добавлены Pester-тесты manifest schema, path traversal, locked digest, повреждённого SHA-256, отсутствующих файлов и локального release proxy.

## Проверяемое происхождение сборки 🧾

Источником истины является:

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

## Онлайн- и офлайн-сборка 📦

Онлайн-сборка с сохранением проверенного upstream-архива:

```powershell
pwsh ./scripts/Build-Release.ps1 `
  -Version 0.3.0 `
  -OutputDirectory ./artifacts `
  -UpstreamCachePath ./cache/zapret-discord-youtube-1.10.0.zip
```

Повторная сборка без обращения к Flowseal/GitHub Release API:

```powershell
pwsh ./scripts/Build-Release.ps1 `
  -Version 0.3.0 `
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

Каждая из 21 настоящей стратегии Flowseal получает отдельные доменные и IP-фильтры TCP/UDP. Общий домен исключается только тогда, когда выключены все использующие его сервисы. `nexroute.bat` остаётся launcher-ом меню и не считается отдельной стратегией.

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

## Быстрый старт 🚀

1. Скачайте `NexRoute-0.3.0-win-x64.zip` и `.sha256` из Releases.
2. Полностью распакуйте архив в новую папку.
3. Запустите `NexRoute.lnk`, `nexroute.bat` или `service.bat` от имени администратора.
4. Выберите стратегию и установите её как службу.
5. Настройте `[14] SERVICE MATRIX`.
6. При необходимости запустите `[12] STRATEGY LAB`.

Не запускайте BAT-файлы непосредственно из ZIP.

## Системные требования 🪟

- Windows 10 x64 или Windows 11 x64;
- Windows PowerShell 5.1+;
- права администратора;
- `curl.exe` для Strategy Lab.

## Проверки Release ✅

CI проверяет:

- PowerShell AST parsing для `.ps1` и `.psm1`;
- Service Matrix и upstream contract через Pester `5.6.1`;
- pinned Flowseal `1.10.0` и locked SHA-256;
- обязательную структуру upstream ZIP;
- онлайн- и офлайн-сборку;
- ровно 23 patch-targets и уникальные patch IDs;
- hashes до/после каждого изменённого файла;
- 21 стратегию и 15 сервисных профилей;
- runtime, Diagnostics, EN/RU страницы, иконку и SHA-256 итогового ZIP.

## Ограничения ⚠️

Эффективность обхода зависит от провайдера, региона, DNS, версии приложений и конфигурации DPI. В `0.3.0` сетевой runtime обрабатывает IPv4; IPv6-only endpoints требуют отдельной будущей поддержки.

Locked upstream защищает воспроизводимость исходной основы, но не является цифровой подписью самого NexRoute Release. Проверяйте опубликованный `.sha256`; полноценная подпись и provenance attestation планируются отдельно.

## Лицензирование ⚖️

Собственный код и документация NexRoute распространяются по MIT. Flowseal, zapret и WinDivert сохраняют собственные лицензии и уведомления. См. [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Автор 👤

**Onmaynec** — [@Onmaynec](https://github.com/Onmaynec)

---

**NexRoute 0.3.0** · Baseline: **Flowseal 1.10.0** · Windows 10/11 x64
