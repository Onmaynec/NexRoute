# Changelog 📝

Все заметные изменения NexRoute документируются в этом файле. Формат основан на Keep a Changelog, версии используют Semantic Versioning.

## [Unreleased]

Пока нет изменений.

## [0.2.0] - 2026-07-25

### Added

- единый PowerShell-renderer для главного меню и внутренних экранов;
- оформленная телеметрия состояния `zapret`, WinDivert и `winws.exe`;
- новый экран выбора стратегий с метками `STABLE`, `ADVANCED`, `EXPERIMENTAL`;
- новый fake-payload vault;
- анимированные экраны `SYNC IPSET` и `SYNC HOSTS`;
- оформление запуска конфигурационных тестов и заголовок тестовой PowerShell-сессии;
- Service Bypass Matrix с 15 переключаемыми профилями;
- профили ChatGPT, FaceTime, Snapchat, Viber, Signal, X, Instagram, Facebook, Telegram, LinkedIn, TikTok, WhatsApp и CaseBattle;
- управляемые блоки в `list-general-user.txt` и `list-exclude-user.txt`;
- пользовательская клавиатурная навигация в матрице сервисов;
- собственный SVG-значок NexRoute;
- генерация Windows `.ico` и ярлыка `NexRoute.lnk` во время release-build;
- RU/EN JSON-локализации интерфейса;
- документация `docs/SERVICES.md`.

### Changed

- версия повышена с `0.1.1` до `0.2.0`;
- переработаны страницы статуса, установки стратегии, IPSet mode, fake-payload и тестов;
- все strategy BAT применяют сервисную матрицу перед запуском;
- README и техническая документация обновлены под новую архитектуру;
- CI проверяет 15 сервисных профилей, все UI-маршруты, иконку, ярлык и управляемые списки.

### Compatibility

- сохранён Flowseal baseline `1.10.0`;
- сетевые аргументы upstream-стратегий не заменены новой реализацией;
- Windows 10 x64 и Windows 11 x64;
- пользовательские строки вне managed-блоков сохраняются.

### Limitations

- FaceTime, Signal, Viber и WhatsApp являются экспериментальными доменными профилями;
- голосовые/видеосоединения могут требовать дополнительных UDP-портов и динамических медиареле;
- фактическая эффективность зависит от провайдера и конфигурации DPI.

## [0.1.1] - 2026-07-25

### Fixed

- устранено повреждение русских строк в CMD;
- визуальный слой вынесен в ASCII-safe PowerShell renderer;
- добавлены анимации запуска стратегий и операций `service.bat`.

## [0.1.0] - 2026-07-25

### Added

- структура проекта NexRoute;
- pinned baseline Flowseal `1.10.0`;
- воспроизводимый PowerShell release builder;
- проверка отсутствия бинарников в Git;
- двуязычное RU/EN оформление `service.bat`;
- SHA-256 для release archive;
- GitHub Actions для CI и публикации релизов;
- русская и английская документация;
- third-party notices и security policy.
