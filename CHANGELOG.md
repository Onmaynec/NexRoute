# Changelog 📝

Все заметные изменения NexRoute документируются в этом файле. Версии используют Semantic Versioning.

## [Unreleased]

Пока нет изменений.

## [0.2.1] - 2026-07-25

### Fixed

- устранено падение почти всех пунктов `service.bat` с ошибкой `GetFullPath: Illegal characters in path`;
- добавлено восстановление аргументов `ChoiceFile`, `LanguageFile`, `ActionId`, `Profile` и `ScreenId`, которые Windows могла поглотить после `-Root "%~dp0"`;
- BAT-файлы автоматически очищаются от небезопасного аргумента после первого успешного запуска UI;
- исправлены сценарии установки стратегии и открытия матрицы сервисов;
- устранён откат в примитивное fallback-меню при штатной работе renderer-а.

### Changed

- главная панель возвращена к визуальному дизайну NexRoute `0.1.1`;
- Status, Strategy Picker, Payload Manager, IPSet, hosts, Tests и Service Matrix оформлены в том же стиле;
- UI разделён на dispatcher, classic theme, pages и service-matrix modules;
- CI воспроизводит пользовательский malformed-Root сценарий и проверяет автоматическое исправление BAT-файлов.

### Preserved

- Flowseal baseline `1.10.0`;
- 15 сервисных профилей версии `0.2.0`;
- Game Filter, IPSet, fake payload и upstream-стратегии;
- Windows 10/11 x64 и RU/EN.

## [0.2.0] - 2026-07-25

### Added

- матрица из 15 сервисных профилей;
- оформленные внутренние страницы и анимации;
- собственный значок NexRoute.

### Known issue

- аргумент `-Root "%~dp0"` мог повреждать командную строку и ломать пункты меню. Исправлено в `0.2.1`.

## [0.1.1] - 2026-07-25

### Fixed

- устранено повреждение русских строк в CMD;
- визуальный слой вынесен в ASCII-safe PowerShell renderer;
- добавлены анимации запуска стратегий и операций `service.bat`.

## [0.1.0] - 2026-07-25

### Added

- структура NexRoute;
- pinned baseline Flowseal `1.10.0`;
- воспроизводимая сборка и SHA-256;
- RU/EN документация и GitHub Actions.
