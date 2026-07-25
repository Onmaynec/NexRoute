# Архитектура NexRoute 🏗️

## 🎯 Принцип

NexRoute не переписывает сетевой движок `zapret`. Проект создаёт контролируемый Windows-дистрибутив поверх закреплённого релиза Flowseal `1.10.0` и добавляет собственные слои управления.

```text
Flowseal 1.10.0 Release ZIP
        │
        ├── winws + WinDivert + payloads
        ├── general*.bat
        ├── lists / utils
        └── upstream service.bat
                  │
                  ▼
        Build-NexRoute.ps1
          ├── validates upstream package
          ├── copies the functional baseline
          ├── patches service.bat routes
          ├── injects animated strategy hooks
          ├── adds unified terminal runtime
          ├── adds service domain matrix
          ├── brands the test laboratory
          ├── generates icon + shortcut
          └── creates ZIP + SHA-256
```

## 🧩 Компоненты версии 0.2.0

| Компонент | Ответственность |
|---|---|
| `overlay/.service/nexroute-ui.ps1` | визуализация главного меню и внутренних экранов |
| `overlay/.service/nexroute-services.ps1` | состояние сервисов и managed-блоки доменных списков |
| `overlay/.service/services.json` | 15 определений сервисов и доменные пакеты |
| `overlay/.service/i18n/*.json` | русская и английская локализации |
| `overlay/.service/New-NexRouteIcon.ps1` | генерация `.ico` и `NexRoute.lnk` |
| `assets/nexroute-mark.svg` | исходный векторный знак бренда |
| `scripts/Build-NexRoute.ps1` | reproducible release assembly |
| `scripts/Test-Repository.ps1` | структура, версии, JSON, PowerShell и policy checks |

## 🖥️ Терминальный слой

`service.bat` остаётся точкой системной интеграции и хранит upstream-операции. Отрисовка вынесена в PowerShell, чтобы:

- не зависеть от OEM-кодировки CMD;
- корректно выводить RU/EN;
- использовать цвета, progress bars и keyboard navigation;
- оформлять все экраны в одном стиле;
- тестировать страницы отдельно от сетевой логики.

Поддерживаемые режимы renderer-а:

```text
Menu
Action
Launch
Status
StrategyPicker
PayloadManager
IpSetSwitch
SyncIpSet
SyncHosts
TestsIntro
TestHeader
Services
Screen
```

## 🌐 Матрица сервисов

Матрица хранит состояние в:

```text
.service/services-state.json
```

При применении создаются управляемые блоки:

```text
lists/list-general-user.txt
  # NEXROUTE-SERVICES-BEGIN
  ...enabled domains...
  # NEXROUTE-SERVICES-END

lists/list-exclude-user.txt
  # NEXROUTE-DISABLED-SERVICES-BEGIN
  ...disabled domains...
  # NEXROUTE-DISABLED-SERVICES-END
```

Строки пользователя вне маркеров сохраняются. Перед каждым ручным запуском стратегии матрица применяется повторно, поэтому состояние и hostlist остаются синхронизированными.

## 🎬 Поток запуска стратегии

```text
user starts general*.bat
        │
        ├── apply service matrix
        ├── render PROFILE BOOT animation
        ├── validate winws.exe
        ├── validate WinDivert64.sys
        └── continue original Flowseal launcher
```

Сетевые параметры стратегии не генерируются UI-слоем.

## 🎨 Брендинг

В Git хранится только SVG-источник. Во время Windows release-build скрипт `New-NexRouteIcon.ps1` создаёт:

```text
.service/nexroute.ico
NexRoute.lnk
```

Ярлык указывает на `service.bat`, использует рабочий каталог дистрибутива и собственный значок NexRoute.

## 📦 Разделение исходников и Release

### Git-репозиторий

Содержит:

- PowerShell/BAT overlay;
- JSON-конфигурации;
- SVG branding;
- документацию;
- CI/CD;
- лицензии.

### GitHub Release

Дополнительно содержит:

- `winws.exe`;
- WinDivert DLL/driver;
- payload `.bin`;
- стратегии Flowseal;
- сгенерированные `.ico` и `.lnk`;
- итоговый ZIP и SHA-256.

## 🔐 Граница доверия

Сборщик принимает ZIP-asset официального GitHub Release Flowseal `1.10.0` и проверяет обязательные компоненты до применения overlay. Итоговый SHA-256 подтверждает целостность опубликованного NexRoute ZIP, но не является цифровой подписью.

## 🔄 Обновление upstream

Переход на новую версию Flowseal выполняется отдельным Pull Request:

1. изучить release notes и diff upstream;
2. изменить pinned version;
3. проверить все regex-патчи `service.bat`;
4. собрать и распаковать Release artifact;
5. выполнить Windows PowerShell 5.1 smoke tests;
6. проверить service matrix и пользовательские списки;
7. протестировать Windows 10/11 и основные сетевые сценарии;
8. обновить changelog и документацию.
