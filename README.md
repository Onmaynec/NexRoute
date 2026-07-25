<div align="center">

# NexRoute 🧭

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows)](docs/COMPATIBILITY.md)
[![Upstream](https://img.shields.io/badge/Flowseal%20baseline-1.10.0-6f42c1)](docs/UPSTREAM.md)
[![Release](https://img.shields.io/badge/version-0.2.0-cyan)](.service/version.txt)

**Консольный набор для управления стратегиями обхода DPI в Windows 10 и Windows 11.**

[English documentation](docs/README_EN.md) · [Архитектура](docs/ARCHITECTURE.md) · [Сборка](docs/RELEASES.md) · [Безопасность](SECURITY.md)

</div>

> [!IMPORTANT]
> NexRoute не является VPN, прокси или средством анонимизации. Проект локально управляет `winws` и WinDivert и не изменяет публичный IP-адрес.

> [!WARNING]
> WinDivert является системным драйвером. Антивирус может классифицировать его как RiskTool/PUA. Загружайте готовые архивы только из официальных Releases и проверяйте SHA-256.

## 🎯 О проекте

NexRoute — функциональный форк `Flowseal/zapret-discord-youtube`, основанный на зафиксированном релизе Flowseal **1.10.0**. Сетевые стратегии и аргументы `winws` сохраняются, а поверх них развивается отдельный терминальный интерфейс, система профилей сервисов, документация и воспроизводимая сборка.

## ✨ Возможности версии 0.2.0

- ✅ Полная функциональная база Flowseal `1.10.0`
- ✅ Windows 10 и Windows 11 x64
- ✅ Единый Control Node вместо необработанных страниц BAT
- ✅ Оформленные страницы статуса, удаления службы, выбора стратегии, fake-payload и тестов
- ✅ Расширенные анимации `SYNC IPSET` и `SYNC HOSTS`
- ✅ Отдельный раздел **Other Service Bypass / Обход других сервисов**
- ✅ Включение и отключение профилей сервисов без ручного редактирования списков
- ✅ Совместимость с `list-general-user.txt`
- ✅ Собственный знак NexRoute вместо символики исходного проекта
- ✅ Release ZIP и отдельный SHA-256

## 🌐 Матрица сервисов

Версия `0.2.0` содержит профили:

| Категория | Сервисы |
|---|---|
| Видео и AI | YouTube, ChatGPT, TikTok |
| Мессенджеры | Discord, FaceTime, Snapchat, Viber, Signal, Telegram, WhatsApp |
| Социальные сети | X / Twitter, Instagram, Facebook, LinkedIn |
| Дополнительно | Case Battle (`casebattle.net`) |

Состояние хранится в `.service/services-enabled.txt`. При сохранении NexRoute изменяет только собственный блок между маркерами `NEXROUTE SERVICES BEGIN/END` в `lists/list-general-user.txt`, не удаляя пользовательские записи.

После изменения матрицы переустановите или перезапустите активную стратегию-службу, чтобы `winws` перечитал список доменов.

## 🖥️ Интерфейс

Главное меню разделено на блоки:

```text
NEXROUTE PACKET ORCHESTRATOR
├── SERVICE CONTROL
├── FILTER MATRIX
├── DATA CHANNELS
├── SYSTEM TOOLKIT
└── OTHER SERVICE BYPASS
```

Страницы операций получают собственные заголовки, цветовые состояния и анимации подготовки. Внутренняя логика Flowseal остаётся доступной и продолжает выполнять реальные системные действия.

## 🚀 Быстрый старт

1. Скачайте `NexRoute-0.2.0-win-x64.zip` и файл `.sha256` из Releases.
2. Проверьте контрольную сумму.
3. Полностью распакуйте архив, например в `C:\NexRoute`.
4. Запустите `nexroute.bat` или `service.bat`.
5. Подтвердите права администратора.
6. Выберите рабочую стратегию и установите её как службу.
7. Откройте пункт **SERVICE MATRIX**, включите нужные сервисы и сохраните конфигурацию.

## 📂 Структура

```text
NexRoute/
├── assets/
│   └── nexroute-mark.svg
├── overlay/
│   ├── .service/
│   │   ├── nexroute-console.ps1
│   │   ├── nexroute-pages.ps1
│   │   ├── nexroute-services.ps1
│   │   └── nexroute-ui.ps1
│   └── nexroute.bat
├── scripts/
│   ├── Build-NexRoute.ps1
│   └── Test-Repository.ps1
├── docs/
├── LICENSE
└── README.md
```

Бинарные файлы `winws.exe`, WinDivert и payload-файлы не хранятся в Git. Release workflow получает официальный upstream-архив, накладывает компоненты NexRoute и формирует итоговый пакет.

## 🛠️ Сборка

```powershell
pwsh ./scripts/Build-NexRoute.ps1 `
  -Version 0.2.0 `
  -UpstreamVersion 1.10.0 `
  -OutputDirectory ./artifacts
```

## 🧪 Проверки

```powershell
pwsh ./scripts/Test-Repository.ps1
```

CI должен проверить PowerShell-синтаксис, структуру пакета, наличие UI runtime, все strategy hooks, upstream-бинарники и SHA-256.

## ⚖️ Лицензирование

Собственный код и документация NexRoute распространяются по MIT License. Flowseal, zapret и WinDivert сохраняют собственные лицензии и уведомления. См. [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## 👤 Автор

**Onmaynec** · [@Onmaynec](https://github.com/Onmaynec)

---

**NexRoute 0.2.0** · Flowseal baseline **1.10.0** · Windows 10/11 x64
