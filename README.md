<div align="center">

<img src="assets/nexroute-mark.svg" width="150" alt="NexRoute emblem">

# NexRoute 🧭

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows)](docs/COMPATIBILITY.md)
[![Flowseal baseline](https://img.shields.io/badge/Flowseal-1.10.0-6f42c1)](docs/UPSTREAM.md)
[![Version](https://img.shields.io/badge/version-0.2.2-24e1d6)](.service/version.txt)

**Консольная система управления стратегиями обхода DPI для Windows 10 и Windows 11.**

[English](docs/README_EN.md) · [Сервисы](docs/SERVICES.md) · [Архитектура](docs/ARCHITECTURE.md) · [Сборка](docs/RELEASES.md)

</div>

> [!IMPORTANT]
> NexRoute не является VPN, прокси или средством анонимизации. Проект локально управляет `winws` и WinDivert, не меняет публичный IP-адрес и применяет выбранную стратегию к трафику включённых сервисов.

## Что изменилось в 0.2.2

- исправлен `[09] SYNC HOSTS`: больше нет вызова метода у `$null`, системный `hosts` обновляется автоматически через управляемый блок;
- пользовательские строки `hosts` сохраняются, перед записью создаётся резервная копия с датой, после обновления очищается DNS-кэш;
- Service Matrix переведена на схему v2: домены, критические endpoints, TCP/UDP-порты, динамически разрешённые IP и внешние IP-источники;
- включённые сервисы реально добавляются во **все 21 настоящую стратегию Flowseal** — `general.bat` и каждый вариант `general (...)`;
- `nexroute.bat` больше не ошибочно считается 22-й стратегией в Strategy Lab: это только launcher главного меню;
- установленная служба `zapret` автоматически переустанавливается и перезапускается после сохранения матрицы;
- Strategy Lab получает несколько реальных целей каждого включённого сервиса: сайт, API, CDN, media, gateway или update endpoint;
- Telegram использует официальный динамический список IP-подсетей, а остальные профили получают IP через DNS-разрешение критических endpoints;
- Game Filter и Update Watch перенесены в оформленные страницы Control Node;
- английский язык установлен по умолчанию, русская локализация переписана нормальными техническими терминами;
- новый значок NexRoute генерируется по мотивам приложенного логотипа в многоразмерный `.ico` и назначается ярлыку;
- добавлены дополнительные анимации загрузки, пересборки матрицы, сетевых проверок и перезапуска службы.

## Service Matrix v2

Матрица содержит 15 профилей:

- YouTube;
- Discord;
- ChatGPT;
- FaceTime;
- Snapchat;
- Viber;
- Signal;
- X (Twitter);
- Instagram;
- Facebook;
- Telegram;
- LinkedIn;
- TikTok;
- WhatsApp;
- CaseBattle.

Для каждого профиля описаны:

```text
domains
testTargets
tcpPorts
udpPorts
resolveHosts
ipCidrs
ipSources
```

При сохранении создаются:

```text
lists/list-services-enabled.txt
lists/ipset-services-user.txt
.service/services-runtime.cmd
```

Эти данные подключаются к каждой стратегии как отдельные TCP/UDP-фильтры. Отключённые сервисы остаются в управляемом блоке исключений.

## Strategy Lab

Лаборатория тестирует базовые Discord/YouTube/Google/Cloudflare цели и дополняет их endpoint-ами всех включённых профилей. Проверки выполняются для каждой конфигурации и включают HTTP, TLS 1.2, TLS 1.3 и задержку. DPI-режим TCP 16–20 КБ сохранён.

Чем больше сервисов включено, тем дольше выполняется полный прогон 21 настоящей стратегии. `nexroute.bat` исключён из списка тестов, поскольку он не содержит отдельной сетевой конфигурации.

## Безопасная синхронизация hosts

`[09] SYNC HOSTS`:

1. загружает набор Flowseal без кэширования;
2. проверяет формат строк;
3. удаляет только старый блок `NEXROUTE-HOSTS-BEGIN/END`;
4. сохраняет все пользовательские строки вне блока;
5. создаёт backup в `.service/backups`;
6. записывает новый файл через временный файл в каталоге системного `hosts`;
7. выполняет `ipconfig /flushdns`.

## Быстрый старт

1. Скачайте `NexRoute-0.2.2-win-x64.zip` и `.sha256` из Releases.
2. Полностью распакуйте архив в новую папку.
3. Запустите `NexRoute.lnk`, `nexroute.bat` или `service.bat` от имени администратора.
4. Выберите стратегию и установите её как службу.
5. Настройте `[14] SERVICE MATRIX`.
6. При необходимости запустите `[12] STRATEGY LAB`.

Не запускайте BAT-файлы непосредственно из ZIP.

## Системные требования

- Windows 10 x64;
- Windows 11 x64;
- Windows PowerShell 5.1+;
- права администратора;
- `curl.exe` для Strategy Lab.

## Проверки Release

CI проверяет:

- синтаксис PowerShell;
- схему 15 сервисов и реальные test targets;
- сборку на Windows из Flowseal `1.10.0`;
- ровно 21 пропатченную настоящую стратегию;
- исключение `nexroute.bat` из Strategy Lab;
- runtime-фильтры TCP/UDP и Service Matrix hooks;
- временное включение Telegram и фактическое изменение hostlist, портов и тестовых целей;
- EN/RU страницы в Windows PowerShell 5.1;
- исправление malformed `-Root`;
- структуру многоразмерной иконки;
- SHA-256 итогового ZIP.

## Ограничения

Эффективность обхода зависит от провайдера, региона, DNS, версии приложений и конфигурации DPI. NexRoute расширяет покрытие доменов, IP и портов, но не может гарантировать работу каждого медиареле в любой сети без проверки на конкретном провайдере.

## Лицензирование

Собственный код и документация NexRoute распространяются по MIT. Flowseal, zapret и WinDivert сохраняют собственные лицензии и уведомления. См. [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Автор

**Onmaynec** — [@Onmaynec](https://github.com/Onmaynec)

---

**NexRoute 0.2.2** · Baseline: **Flowseal 1.10.0** · Windows 10/11 x64
