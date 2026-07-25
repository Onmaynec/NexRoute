# Архитектура NexRoute 🏗️

## 🎯 Принцип

NexRoute не переписывает сетевой движок `zapret`. Проект создаёт контролируемый Windows-дистрибутив поверх зафиксированного upstream-релиза Flowseal и изменяет только собственные слои: терминальный интерфейс, брендинг, ссылки обновления, документацию и release automation.

```text
Flowseal release 1.10.0
        │
        ├── strategies / lists / utils
        ├── winws + WinDivert + payloads
        └── upstream service.bat
                │
                ▼
      Build-NexRoute.ps1
        ├── validates upstream archive
        ├── preserves upstream functionality
        ├── installs nexroute-ui.ps1
        ├── replaces only the service menu block
        ├── injects profile boot hooks into strategy BAT files
        ├── replaces NexRoute update endpoints
        ├── adds notices and documentation
        └── generates ZIP + SHA-256
```

## 🖥️ Терминальный слой

В версии `0.1.1` отображение меню вынесено из BAT в отдельный файл:

```text
overlay/.service/nexroute-ui.ps1
```

`service.bat` продолжает отвечать за:

- запрос прав администратора;
- чтение статусов;
- установку и удаление службы;
- Game Filter и IPSet Filter;
- диагностику;
- обновления;
- запуск upstream-инструментов.

`nexroute-ui.ps1` отвечает только за:

- ASCII-логотип;
- панели меню;
- цветовые статусы;
- переключение RU/EN;
- анимацию загрузки;
- анимацию операций;
- анимацию запуска профилей;
- получение пользовательского выбора через временный файл.

Такое разделение не меняет сетевые аргументы `winws` и не вмешивается в алгоритмы обхода.

## 🔤 Модель кодировок

Источник `nexroute-ui.ps1` состоит только из ASCII-символов. Русские строки хранятся в Base64 как UTF-8 и декодируются во время выполнения:

```text
Base64 UTF-8 → System.Text.Encoding.UTF8 → Console output
```

В сгенерированном `service.bat` нет прямых кириллических литералов. Поэтому CMD не может ошибочно интерпретировать русский UTF-8 текст как OEM-кодировку и превратить его в повреждённые символы.

Если PowerShell renderer отсутствует или завершается ошибкой, `service.bat` показывает минимальное английское ASCII-меню, сохраняя доступ к функциям.

## 🚀 Запуск стратегий

Сборщик добавляет после первой строки каждого корневого strategy BAT файла ASCII-hook:

```bat
rem NEXROUTE_PROFILE_BOOT
if exist "%~dp0.service\nexroute-ui.ps1" powershell ... -Mode Launch ...
```

Hook:

1. показывает профиль и анимацию загрузки;
2. проверяет наличие `bin\winws.exe`;
3. проверяет наличие `bin\WinDivert64.sys`;
4. возвращает управление неизменённому upstream BAT-файлу.

Оригинальные команды `winws` не переписываются.

## 📦 Разделение исходников и дистрибутива

### Git-репозиторий

Содержит только:

- PowerShell-скрипты сборки и проверки;
- overlay-файлы NexRoute;
- GitHub Actions;
- документацию;
- лицензии и уведомления.

### GitHub Release

Дополнительно содержит:

- `winws.exe`;
- WinDivert DLL/driver;
- `.bin` payload-файлы;
- стратегии `general*.bat`;
- списки и upstream-утилиты;
- `.service/nexroute-ui.ps1`;
- `.service/language.txt`.

Это исключает бинарники из Git-истории и позволяет точно фиксировать их происхождение.

## 🧩 Компоненты

| Компонент | Ответственность |
|---|---|
| `scripts/Build-NexRoute.ps1` | получение upstream asset, проверка, overlay, упаковка |
| `scripts/Test-Repository.ps1` | политика репозитория, версии, синтаксис, UI и отсутствие бинарников |
| `overlay/nexroute.bat` | основная точка входа в консольный менеджер |
| `overlay/.service/nexroute-ui.ps1` | интерфейс, локализация и анимации |
| patched `service.bat` | маршрутизация меню и полная upstream-логика |
| strategy BAT hooks | анимированный запуск профиля без изменения `winws`-аргументов |
| `.service/version.txt` | единый источник версии NexRoute |
| GitHub Actions | CI, artifact build и публикация Release |

## 🔐 Граница доверия

Сборщик принимает только asset официального GitHub Release `Flowseal/zapret-discord-youtube`. Перед упаковкой проверяется наличие основных файлов: `service.bat`, `general.bat`, `winws.exe`, WinDivert и ключевых списков.

SHA-256 итогового NexRoute ZIP публикуется отдельным файлом. Это подтверждает целостность NexRoute-архива после сборки, но не является цифровой подписью автора.

## 🧪 Контроль сборки

Windows smoke-build распаковывает итоговый ZIP и проверяет:

- наличие UI runtime;
- PowerShell-синтаксис UI;
- ASCII-only исходник renderer-а;
- отсутствие кириллицы в сгенерированном `service.bat`;
- подключение `-Mode Action`;
- наличие `NEXROUTE_PROFILE_BOOT` во всех strategy BAT;
- наличие движка и драйвера;
- соответствие SHA-256.

## 🔄 Обновление upstream

Переход на новую версию Flowseal должен выполняться отдельным Pull Request:

1. изменить pinned upstream version;
2. изучить changelog и diff upstream;
3. проверить, что regex-патч меню всё ещё применим;
4. проверить, что все strategy BAT начинаются с `@echo off`;
5. собрать Release artifact;
6. проверить интерфейс и служебные операции на Windows 10/11;
7. обновить `docs/UPSTREAM.md` и changelog NexRoute.
