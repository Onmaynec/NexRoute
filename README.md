<div align="center">

<img src="assets/nexroute-mark.svg" width="150" alt="NexRoute emblem">

# NexRoute 🧭

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows)](docs/COMPATIBILITY.md)
[![Flowseal baseline](https://img.shields.io/badge/Flowseal-1.10.0-6f42c1)](docs/UPSTREAM.md)
[![Version](https://img.shields.io/badge/version-0.2.3-24e1d6)](.service/version.txt)

**Консольная система управления стратегиями обхода DPI для Windows 10 и Windows 11.**

[English](docs/README_EN.md) · [Сервисы](docs/SERVICES.md) · [Архитектура](docs/ARCHITECTURE.md) · [Сборка](docs/RELEASES.md)

</div>

> [!IMPORTANT]
> NexRoute не является VPN, прокси или средством анонимизации. Проект локально управляет `winws` и WinDivert, не меняет публичный IP-адрес и применяет выбранную стратегию к трафику включённых сервисов.

## Что изменилось в 0.2.3

- устранён конфликт общих доменов: домен попадает в исключения только тогда, когда выключены **все** использующие его профили;
- для каждого включённого сервиса создаются собственные hostlist/IPSet и отдельные TCP/UDP `--new`-группы, поэтому широкие медиапорты одного приложения больше не объединяются с адресами остальных;
- состояние Service Matrix переведено на схему v2; старый плоский JSON мигрируется автоматически с резервной копией;
- повреждённое состояние сохраняется как backup и заменяется безопасными настройками по умолчанию;
- порты и IPv4 CIDR проходят строгую семантическую проверку;
- внешние IP-источники используют last-known-good кэш с TTL **14 дней** и статусом `fresh/cache/failed`;
- добавлен privacy-safe экспорт **Diagnostics** без содержимого пользовательских доменных/IP-списков;
- добавлены поведенческие тесты Pester `5.6.1`: общие домены, миграция, corrupt JSON, идемпотентность, изоляция runtime и диагностика;
- release pipeline стал версионно-независимым: `Build-Release.ps1`, `Test-Release.ps1` и `.github/workflows/release.yml`;
- после успешной публикации `v0.2.3` workflow закрывает устаревшие tracking issues `#7–#10` и PR `#4`.

## Service Matrix v2

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

Каждая из 21 настоящей стратегии Flowseal получает отдельные доменные и IP-фильтры TCP/UDP. `nexroute.bat` остаётся launcher-ом меню и не считается отдельной стратегией.

## Миграция состояния

Старый файл вида:

```json
{"youtube":true,"discord":true}
```

автоматически преобразуется в:

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

Перед миграцией создаётся `.service/services-state.v1.backup.json`. Для повреждённого JSON используется `.service/services-state.invalid.backup.json`.

## Диагностика

Контроллер поддерживает режим:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .service\nexroute-services.ps1 `
  -Mode Diagnostics `
  -Root .
```

Отчёт содержит версию, включённые ID сервисов, количество сгенерированных записей, статусы IP-источников, SHA-256 runtime-файла, версию Windows/PowerShell и состояние службы. Содержимое пользовательских списков, имена пользователей и внешние пути не включаются.

## Быстрый старт

1. Скачайте `NexRoute-0.2.3-win-x64.zip` и `.sha256` из Releases.
2. Полностью распакуйте архив в новую папку.
3. Запустите `NexRoute.lnk`, `nexroute.bat` или `service.bat` от имени администратора.
4. Выберите стратегию и установите её как службу.
5. Настройте `[14] SERVICE MATRIX`.
6. При необходимости запустите `[12] STRATEGY LAB`.

Не запускайте BAT-файлы непосредственно из ZIP.

## Системные требования

- Windows 10 x64 или Windows 11 x64;
- Windows PowerShell 5.1+;
- права администратора;
- `curl.exe` для Strategy Lab.

## Проверки Release

CI проверяет синтаксис PowerShell, 15 профилей, строгие порты/CIDR, Pester-сценарии, сборку из Flowseal `1.10.0`, ровно 21 стратегию, отдельные runtime-группы сервисов, Diagnostics, EN/RU страницы, иконку и SHA-256 итогового ZIP.

## Ограничения

Эффективность обхода зависит от провайдера, региона, DNS, версии приложений и конфигурации DPI. В версии `0.2.3` обрабатывается IPv4; приложения с IPv6-only endpoints могут требовать отдельной будущей поддержки.

## Лицензирование

Собственный код и документация NexRoute распространяются по MIT. Flowseal, zapret и WinDivert сохраняют собственные лицензии и уведомления. См. [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Автор

**Onmaynec** — [@Onmaynec](https://github.com/Onmaynec)

---

**NexRoute 0.2.3** · Baseline: **Flowseal 1.10.0** · Windows 10/11 x64
