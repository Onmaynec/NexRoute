# Changelog 📝

Все заметные изменения NexRoute документируются в этом файле.

Формат основан на Keep a Changelog, версии используют Semantic Versioning.

## [Unreleased]

Пока нет изменений.

## [0.1.1] - 2026-07-25

### Fixed

- устранено повреждение русских строк в `service.bat` из-за несовместимости UTF-8 и OEM-кодовых страниц CMD;
- удалены прямые кириллические литералы из генерируемого BAT-меню;
- добавлен ASCII fallback, если PowerShell renderer недоступен.

### Added

- отдельный терминальный renderer `.service/nexroute-ui.ps1`;
- ASCII-логотип NexRoute и брендированный экран Control Node;
- структурированные панели Service Control, Filter Matrix, Data Channels и System Toolkit;
- цветовые статусы фильтров, языка и привилегий;
- загрузочная анимация интерфейса;
- анимация запуска каждой операции меню;
- анимация запуска каждого strategy BAT файла;
- проверка наличия `winws.exe` и `WinDivert64.sys` перед передачей управления стратегии;
- Base64 UTF-8 локализация RU/EN в ASCII-safe PowerShell source;
- расширенный Windows smoke-build с распаковкой и инспекцией Release ZIP;
- CI-проверка отсутствия прямой кириллицы в `service.bat`;
- CI-проверка launch-hook во всех стратегиях.

### Compatibility

- Windows 10 x64;
- Windows 11 x64;
- PowerShell 5.1+;
- пользовательские списки Flowseal;
- все стратегии и инструменты официального релиза Flowseal 1.10.0.

## [0.1.0] - 2026-07-25

### Added

- структура проекта NexRoute;
- pinned baseline Flowseal `1.10.0`;
- воспроизводимый PowerShell release builder;
- проверка отсутствия бинарников в Git;
- первоначальное двуязычное RU/EN оформление `service.bat`;
- обновление ссылок сервиса на Releases NexRoute;
- SHA-256 для release archive;
- GitHub Actions для CI и публикации релиза;
- русская и английская документация;
- правила совместимости со списками Flowseal;
- third-party notices и security policy.

### Known issue

- прямой UTF-8 текст внутри BAT-файла мог отображаться повреждёнными символами в CMD/Windows Terminal в зависимости от кодовой страницы. Исправлено в `0.1.1`.
