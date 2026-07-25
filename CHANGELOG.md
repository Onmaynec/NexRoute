# Changelog 📝

Все заметные изменения NexRoute документируются в этом файле. Версии используют Semantic Versioning.

## [Unreleased]

Пока нет изменений.

## [0.2.2] - 2026-07-25

### Added

- Service Matrix schema v2 с доменами, endpoints, TCP/UDP-портами, DNS-разрешением и внешними IP-источниками;
- runtime-файлы `list-services-enabled.txt`, `ipset-services-user.txt` и `services-runtime.cmd`;
- отдельные реальные Strategy Lab probes для web, API, CDN, media, gateway и update endpoints;
- автоматическая переустановка активной стратегии службы `zapret` после изменения матрицы;
- оформленные страницы Game Filter и Update Watch;
- многоразмерная `.ico`-иконка по мотивам нового логотипа NexRoute;
- дополнительные анимации применения фильтров, разрешения IP и перезапуска службы.

### Fixed

- устранено падение `[09] SYNC HOSTS` с `You cannot call a method on a null-valued expression`;
- системный `hosts` теперь обновляется автоматически, а не открывается для ручного слияния;
- пользовательские строки `hosts` сохраняются вне управляемого блока;
- после обновления `hosts` выполняется `ipconfig /flushdns`;
- русские названия служб и сетевых компонентов переписаны понятными терминами;
- английский язык установлен по умолчанию;
- `nexroute.bat` больше не считается 22-й стратегией в Strategy Lab.

### Changed

- все 21 настоящие BAT-конфигурации Flowseal получают расширенные Service Matrix TCP/UDP-фильтры;
- Strategy Lab динамически читает включённые сервисы и тестирует только реальные стратегии;
- Telegram получает официальные IP-подсети из `core.telegram.org/resources/cidr.txt`;
- release CI проверяет реальное изменение runtime-фильтров при включении Telegram.

## [0.2.1] - 2026-07-25

### Fixed

- устранено падение пунктов `service.bat` из-за `-Root "%~dp0"`;
- восстановлены поглощённые аргументы PowerShell;
- восстановлен classic Control Node UI.

## [0.2.0] - 2026-07-25

### Added

- матрица из 15 сервисных профилей;
- оформленные внутренние страницы и анимации;
- собственный значок NexRoute.

## [0.1.1] - 2026-07-25

### Fixed

- устранено повреждение русских строк в CMD;
- визуальный слой вынесен в ASCII-safe PowerShell renderer.

## [0.1.0] - 2026-07-25

### Added

- структура NexRoute;
- pinned baseline Flowseal `1.10.0`;
- воспроизводимая сборка и SHA-256.
