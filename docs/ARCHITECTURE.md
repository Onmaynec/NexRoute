# Архитектура NexRoute 🏗️

## 🎯 Принцип

NexRoute не переписывает сетевой движок `zapret`. Проект создаёт контролируемый Windows-дистрибутив поверх зафиксированного upstream-релиза Flowseal и изменяет только собственные слои: оформление CLI, брендинг, ссылки обновления, документацию и release automation.

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
        ├── patches service menu RU/EN
        ├── replaces NexRoute update endpoints
        ├── adds notices and documentation
        └── generates ZIP + SHA-256
```

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
- списки и upstream-утилиты.

Это исключает бинарники из Git-истории и позволяет точно фиксировать их происхождение.

## 🧩 Компоненты

| Компонент | Ответственность |
|---|---|
| `scripts/Build-NexRoute.ps1` | получение upstream asset, проверка, overlay, упаковка |
| `scripts/Test-Repository.ps1` | политика репозитория, версии, синтаксис и отсутствие бинарников |
| `overlay/nexroute.bat` | альтернативная точка входа в консольный менеджер |
| patched `service.bat` | двуязычное меню и полная upstream-логика |
| `.service/version.txt` | единый источник версии NexRoute |
| GitHub Actions | CI, artifact build и публикация Release |

## 🔐 Граница доверия

Сборщик принимает только asset официального GitHub Release `Flowseal/zapret-discord-youtube`. Перед упаковкой проверяется наличие основных файлов: `service.bat`, `general.bat`, `winws.exe`, WinDivert и ключевых списков.

SHA-256 итогового NexRoute ZIP публикуется отдельным файлом. Это подтверждает целостность NexRoute-архива после сборки, но не является цифровой подписью автора.

## 🔄 Обновление upstream

Переход на новую версию Flowseal должен выполняться отдельным Pull Request:

1. изменить pinned upstream version;
2. изучить changelog и diff upstream;
3. проверить, что regex-патч меню всё ещё применим;
4. собрать Release artifact;
5. проверить все стратегии и служебные операции на Windows 10/11;
6. обновить `docs/UPSTREAM.md` и changelog NexRoute.
