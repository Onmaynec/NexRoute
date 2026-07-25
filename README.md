<div align="center">

<img src="assets/nexroute-mark.svg" width="150" alt="NexRoute emblem">

# NexRoute 🧭

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows)](docs/COMPATIBILITY.md)
[![Upstream](https://img.shields.io/badge/Flowseal%20baseline-1.10.0-6f42c1)](docs/UPSTREAM.md)
[![Version](https://img.shields.io/badge/version-0.2.0-24e1d6)](.service/version.txt)

**Консольная система управления стратегиями обхода DPI для Windows 10 и Windows 11.**

[English](docs/README_EN.md) · [Сервисы](docs/SERVICES.md) · [Архитектура](docs/ARCHITECTURE.md) · [Сборка](docs/RELEASES.md) · [Безопасность](SECURITY.md)

</div>

> [!IMPORTANT]
> NexRoute не является VPN, прокси или средством анонимизации. Проект локально управляет `winws` и WinDivert, не меняет публичный IP-адрес и применяет стратегии к выбранному трафику.

> [!WARNING]
> WinDivert является системным драйвером перехвата трафика и может определяться защитным ПО как RiskTool/PUA. Загружайте архивы только из официального раздела **Releases** и проверяйте SHA-256.

## 🎯 О проекте

NexRoute — функциональный консольный форк `Flowseal/zapret-discord-youtube`. Версия `0.2.0` использует официальный релиз Flowseal **1.10.0** как закреплённую сетевую основу, сохраняет upstream-стратегии и добавляет собственный интерфейс, сервисную матрицу, анимации, брендинг и воспроизводимый release-процесс.

## ✨ Возможности версии 0.2.0

- ✅ Полный baseline Flowseal `1.10.0`
- ✅ Все штатные стратегии `general*.bat`, включая `ALT`, `FAKE`, `SIMPLE FAKE` и `EXP`
- ✅ Поддержка TCP, UDP и QUIC в рамках upstream-стратегий
- ✅ Discord Web/CDN/Voice и YouTube
- ✅ Game Filter и IPSet Filter
- ✅ Установка выбранной стратегии как службы Windows
- ✅ Полностью переработанный RU/EN консольный интерфейс
- ✅ Единый дизайн главного меню, статуса, выбора стратегии, fake-payload, IPSet/hosts и тестов
- ✅ Анимации запуска профиля, установки, удаления, синхронизации и диагностики
- ✅ **Service Bypass Matrix** с 15 переключаемыми сервисами
- ✅ Сохранение пользовательских строк вне управляемых блоков
- ✅ Собственный значок NexRoute и ярлык `NexRoute.lnk`
- ✅ Release ZIP с SHA-256; исполняемые компоненты публикуются только в Releases

## 🌐 Матрица обхода сервисов

Пункт **[14] Матрица сервисов** позволяет включать и выключать:

- YouTube
- Discord
- ChatGPT
- FaceTime
- Snapchat
- Viber
- Signal
- X (Twitter)
- Instagram
- Facebook
- Telegram
- LinkedIn
- TikTok
- WhatsApp
- Кейс батл (`casebattle.net`)

Управление выполняется клавишами `↑`, `↓`, `SPACE`, `A`, `N`, `ENTER` и `ESC`.

Подробности и ограничения: [docs/SERVICES.md](docs/SERVICES.md).

## 🚀 Быстрый старт

1. Откройте раздел **Releases**.
2. Скачайте:

   ```text
   NexRoute-0.2.0-win-x64.zip
   NexRoute-0.2.0-win-x64.zip.sha256
   ```

3. Проверьте SHA-256.
4. В свойствах ZIP нажмите **Разблокировать**, если Windows показывает такую кнопку.
5. Полностью распакуйте архив, например в:

   ```text
   C:\NexRoute
   ```

6. Запустите `NexRoute.lnk`, `nexroute.bat` или `service.bat` от имени администратора.
7. Откройте **Лабораторию стратегий**, выберите рабочий профиль и установите его как службу.
8. Настройте **Матрицу сервисов**.

Не запускайте BAT-файлы непосредственно из ZIP.

## 🖥️ Системные требования

- Windows 10 x64
- Windows 11 x64
- Windows PowerShell 5.1+
- права администратора для установки службы и WinDivert

Windows 7/8, x86 и ARM64 официально не поддерживаются.

## 🧰 Интерфейс Control Node

Главная панель разделена на блоки:

| Раздел | Возможности |
|---|---|
| Service Control | установка, удаление и телеметрия службы |
| Filter Matrix | Game Filter, IPSet и проверка обновлений |
| Data Channels | SYNC IPSET, SYNC HOSTS, release channel |
| Other Service Bypass | управление 15 доменными профилями |
| System Toolkit | диагностика, тесты и смена языка |

Все ключевые операции используют единый PowerShell-renderer с цветными состояниями, ASCII-логотипом и progress-анимациями.

## 📂 Структура репозитория

```text
NexRoute/
├── .github/
│   ├── ISSUE_TEMPLATE/
│   ├── release-notes/
│   └── workflows/
├── .service/
│   └── version.txt
├── assets/
│   └── nexroute-mark.svg
├── docs/
│   ├── ARCHITECTURE.md
│   ├── COMPATIBILITY.md
│   ├── README_EN.md
│   ├── RELEASES.md
│   ├── SERVICES.md
│   └── UPSTREAM.md
├── overlay/
│   ├── nexroute.bat
│   └── .service/
│       ├── i18n/
│       ├── New-NexRouteIcon.ps1
│       ├── nexroute-services.ps1
│       ├── nexroute-ui.ps1
│       └── services.json
├── scripts/
│   ├── Build-NexRoute.ps1
│   └── Test-Repository.ps1
├── CHANGELOG.md
├── LICENSE
├── THIRD_PARTY_NOTICES.md
└── README.md
```

`winws.exe`, WinDivert, payload-файлы и готовые архивы не хранятся в Git. Release workflow получает официальный asset Flowseal `1.10.0`, применяет overlay NexRoute и создаёт итоговый пакет.

## 🔄 Совместимость с Flowseal

Сохраняются пользовательские файлы:

```text
lists/list-general-user.txt
lists/list-exclude-user.txt
lists/ipset-exclude-user.txt
lists/ipset-all.txt
```

NexRoute добавляет только блоки между маркерами `NEXROUTE-SERVICES-BEGIN/END` и `NEXROUTE-DISABLED-SERVICES-BEGIN/END`. Остальные пользовательские строки не удаляются.

## 🛠️ Локальная сборка

```powershell
pwsh ./scripts/Test-Repository.ps1

pwsh ./scripts/Build-NexRoute.ps1 `
  -Version 0.2.0 `
  -UpstreamVersion 1.10.0 `
  -OutputDirectory ./artifacts
```

Результат:

```text
artifacts/
├── NexRoute-0.2.0-win-x64.zip
└── NexRoute-0.2.0-win-x64.zip.sha256
```

## 🧪 Проверки

CI проверяет:

- PowerShell AST всех собственных скриптов;
- 15 определений сервисов и уникальность идентификаторов;
- ASCII-safe исходник терминального renderer-а;
- отсутствие бинарников в Git;
- патчи всех экранов `service.bat`;
- сборку и распаковку Release ZIP;
- наличие `winws.exe`, WinDivert, иконки и ярлыка;
- управляемые блоки hostlist/exclude-list;
- запуск неинтерактивных режимов UI через Windows PowerShell 5.1;
- SHA-256 итогового архива.

## ⚠️ Ограничения

Результат сетевого обхода зависит от провайдера, региона, конфигурации DPI, DNS и выбранной стратегии.

FaceTime, Signal, Viber и WhatsApp используют динамические адреса, UDP и медиареле. Их профили помечены как experimental: доменные соединения могут работать отдельно от голосовых и видеозвонков.

## 🐛 Сообщения об ошибках

Перед созданием Issue:

1. Запустите **Diagnostic Core**.
2. Удалите конфликтующие WinDivert-службы.
3. Проверьте несколько стратегий.
4. Укажите Windows 10/11, провайдера, стратегию и точный текст ошибки.

## 🤝 Вклад в проект

1. Создайте Fork.
2. Создайте ветку `feature/<name>` или `fix/<name>`.
3. Не добавляйте исполняемые бинарники и архивы.
4. Запустите `scripts/Test-Repository.ps1`.
5. Откройте Pull Request с результатами проверок.

Подробности: [CONTRIBUTING.md](CONTRIBUTING.md).

## ⚖️ Лицензирование

Собственный код, документация и branding NexRoute распространяются по MIT. Flowseal, zapret и WinDivert сохраняют собственные лицензии и copyright-уведомления. См. [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## 👤 Автор

**Onmaynec**

- GitHub: [@Onmaynec](https://github.com/Onmaynec)

## 🙏 Благодарности

- `bol-van/zapret` — оригинальный сетевой движок и `winws`
- `Flowseal/zapret-discord-youtube` — Windows baseline, стратегии и списки
- WinDivert contributors — драйвер и библиотека перехвата пакетов
- авторы upstream-диагностики и DPI-checkers

---

**NexRoute 0.2.0** · Baseline: **Flowseal 1.10.0** · Windows 10/11 x64
