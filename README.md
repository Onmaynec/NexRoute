<div align="center">

# NexRoute 🧭

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows)](docs/COMPATIBILITY.md)
[![Upstream](https://img.shields.io/badge/Flowseal%20baseline-1.10.0-6f42c1)](docs/UPSTREAM.md)
[![Release](https://img.shields.io/badge/version-0.1.0--dev-orange)](.service/version.txt)

**Консольный набор для управления стратегиями обхода DPI в Windows 10 и Windows 11.**

[English documentation](docs/README_EN.md) · [Архитектура](docs/ARCHITECTURE.md) · [Сборка релиза](docs/RELEASES.md) · [Безопасность](SECURITY.md)

</div>

> [!IMPORTANT]
> NexRoute не является VPN или прокси, не изменяет публичный IP-адрес и не обеспечивает анонимность. Проект локально управляет `winws` и WinDivert, применяя стратегии только к выбранному трафику.

> [!WARNING]
> WinDivert является системным драйвером перехвата трафика и может определяться антивирусами как RiskTool/PUA. Загружайте готовые архивы только из официального раздела **Releases** данного репозитория и проверяйте SHA-256.

## 🎯 О проекте

NexRoute создаётся как функциональный форк `Flowseal/zapret-discord-youtube`. Первая версия использует официальный релиз Flowseal **1.10.0** как зафиксированную функциональную основу и сохраняет совместимость с его стратегиями, списками доменов/IP, пользовательскими файлами и диагностическими инструментами.

Главные отличия NexRoute — более аккуратный двуязычный консольный интерфейс, прозрачная сборка релизов, документированное происхождение компонентов и отсутствие бинарных файлов в Git-истории.

## ✨ Возможности версии 0.1.0

- ✅ Функциональный baseline Flowseal `1.10.0`
- ✅ Все штатные стратегии `general*.bat`, включая `ALT`, `FAKE`, `SIMPLE FAKE` и `EXP`
- ✅ Обработка TCP, UDP и QUIC для поддерживаемых upstream-сценариев
- ✅ Поддержка Discord Web/CDN/Voice и YouTube
- ✅ Game Filter и IPSet Filter
- ✅ Установка выбранной стратегии как службы Windows
- ✅ Проверка состояния `zapret`, `winws.exe` и WinDivert
- ✅ Замена активных fake-payload файлов
- ✅ Обновление IPSet и hosts
- ✅ Диагностика конфликтующих служб, DNS, прокси и системных компонентов
- ✅ Тестирование стратегий и DPI
- ✅ Совместимость с пользовательскими списками Flowseal
- ✅ Консольный интерфейс на русском и английском языках
- ✅ Release ZIP с SHA-256; бинарники публикуются только в Releases

## 🚀 Быстрый старт

1. Откройте раздел **Releases** и скачайте архив `NexRoute-0.1.0-win-x64.zip`.
2. Скачайте соответствующий файл `.sha256` и проверьте контрольную сумму.
3. Откройте свойства ZIP и нажмите **Разблокировать**, если такая опция отображается.
4. Распакуйте архив в путь без кириллицы и специальных символов, например:

   ```text
   C:\NexRoute
   ```

5. Запустите `service.bat` от имени администратора.
6. Выберите язык, протестируйте стратегии и установите рабочую стратегию как службу.

Для ручной проверки можно запускать любой файл `general*.bat` напрямую.

## 🧰 Основные функции service.bat

| Раздел | Возможности |
|---|---|
| Service | установка, удаление и проверка службы |
| Settings | Game Filter, IPSet Filter, автообновление, замена fake-payload |
| Updates | IPSet, hosts и проверка релизов NexRoute |
| Tools | диагностика, стандартные тесты и DPI-checkers |
| Language | переключение RU/EN с сохранением выбора |

## 📂 Структура репозитория

```text
NexRoute/
├── .github/
│   ├── ISSUE_TEMPLATE/       # Формы Issues
│   └── workflows/            # Проверка и сборка Releases
├── .service/
│   └── version.txt           # Версия NexRoute
├── docs/                     # Документация проекта
├── overlay/                  # Файлы, накладываемые на upstream-архив
├── scripts/
│   ├── Build-NexRoute.ps1    # Воспроизводимая сборка Release ZIP
│   └── Test-Repository.ps1   # Проверка структуры и конфигурации
├── LICENSE                   # Лицензия собственного кода NexRoute
├── THIRD_PARTY_NOTICES.md    # Сторонние компоненты и авторство
└── README.md
```

Бинарные файлы `winws.exe`, WinDivert и payload-файлы **не хранятся в репозитории**. Release workflow загружает официальный архив upstream-релиза, применяет контролируемые изменения NexRoute и создаёт итоговый дистрибутив.

## 🔄 Совместимость с Flowseal

NexRoute 0.1.0 совместим со следующими пользовательскими файлами:

```text
lists/list-general-user.txt
lists/list-exclude-user.txt
lists/ipset-exclude-user.txt
lists/ipset-all.txt
```

При миграции рекомендуется сначала удалить службы старой сборки через её `service.bat`, затем скопировать пользовательские списки в NexRoute и установить стратегию заново.

## 🛠️ Сборка

Требования:

- Windows 10/11 или Windows runner GitHub Actions
- PowerShell 5.1+
- доступ к GitHub API и Releases

```powershell
pwsh ./scripts/Build-NexRoute.ps1 `
  -Version 0.1.0 `
  -UpstreamVersion 1.10.0 `
  -OutputDirectory ./artifacts
```

Скрипт автоматически выбирает официальный ZIP-asset Flowseal, проверяет структуру, применяет патч консольного интерфейса и создаёт SHA-256.

## 🧪 Проверки

```powershell
pwsh ./scripts/Test-Repository.ps1
```

CI проверяет версии, обязательные документы, отсутствие бинарников в Git и корректность release workflow.

## 🐛 Сообщения об ошибках

Перед созданием Issue:

1. Запустите `service.bat` → **Diagnostics**.
2. Убедитесь, что Secure DNS настроен.
3. Проверьте несколько стратегий.
4. Укажите Windows 10/11, провайдера, выбранную стратегию и точный текст ошибки.

Используйте шаблон **Bug report** в разделе Issues.

## 🤝 Вклад в проект

1. Создайте Fork.
2. Создайте ветку `feature/<name>` или `fix/<name>`.
3. Не добавляйте бинарники, архивы и пользовательские списки.
4. Запустите `scripts/Test-Repository.ps1`.
5. Откройте Pull Request с описанием изменений и проверки.

Подробности: [CONTRIBUTING.md](CONTRIBUTING.md).

## ⚖️ Лицензирование

Собственный код и документация NexRoute распространяются по лицензии MIT. Компоненты Flowseal, zapret и WinDivert сохраняют свои лицензии, copyright-уведомления и условия распространения. См. [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## 👤 Автор

**Onmaynec**

- GitHub: [@Onmaynec](https://github.com/Onmaynec)

## 🙏 Благодарности

- `bol-van/zapret` — оригинальный проект и `winws`
- `Flowseal/zapret-discord-youtube` — Windows-сборка, стратегии, списки и сервисный менеджер
- WinDivert contributors — драйвер и библиотека перехвата пакетов
- участники upstream-проектов и авторы стратегий/payload-файлов

---

**NexRoute 0.1.0** · Upstream baseline: **Flowseal 1.10.0** · Windows 10/11 x64
