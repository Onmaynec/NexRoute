# Changelog 📝

Все заметные изменения NexRoute документируются в этом файле.

Формат основан на Keep a Changelog, версии используют Semantic Versioning.

## [Unreleased]

Пока нет изменений.

## [0.2.0] - 2026-07-25

### Added

- единый Control Node для главного меню и внутренних страниц;
- оформленные экраны статуса, удаления службы, выбора стратегии, payload-хранилища, тестов, диагностики и проверки релизов;
- расширенные анимации `SYNC IPSET` и `SYNC HOSTS`;
- раздел `OTHER SERVICE BYPASS`;
- управляемая матрица из 15 сервисных профилей;
- профили YouTube, Discord, ChatGPT, FaceTime, Snapchat, Viber, Signal, X/Twitter, Instagram, Facebook, Telegram, LinkedIn, TikTok, WhatsApp и Case Battle;
- собственный знак NexRoute в формате SVG;
- отдельные PowerShell-модули `nexroute-console.ps1`, `nexroute-pages.ps1` и `nexroute-services.ps1`;
- CI-проверки каталога доменов, сервисной матрицы и новых UI-модулей.

### Changed

- `service.bat` теперь содержит пункт `14` для управления обходом отдельных сервисов;
- страницы upstream получают единый заголовок, цветовые состояния и анимацию подготовки;
- выбранные сервисы записываются в совместимый `lists/list-general-user.txt`;
- пользовательские записи сохраняются, NexRoute изменяет только блок между маркерами `NEXROUTE SERVICES BEGIN/END`.

### Compatibility

- Windows 10 x64;
- Windows 11 x64;
- PowerShell 5.1+;
- Flowseal `1.10.0`;
- пользовательские списки Flowseal.

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
- расширенный Windows smoke-build с распаковкой и инспекцией Release ZIP.

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
