# Сборка и публикация Releases 📦

## 🎯 Политика

Бинарные компоненты NexRoute публикуются только в GitHub Releases. В Git-репозитории запрещены файлы `.exe`, `.dll`, `.sys`, `.bin` и архивы.

Каждый Release должен собираться заново из `main`, а не копироваться из локальной папки разработчика.

## 🛠️ Локальная сборка

```powershell
pwsh ./scripts/Test-Repository.ps1

pwsh ./scripts/Build-NexRoute.ps1 `
  -Version 0.1.1 `
  -UpstreamVersion 1.10.0 `
  -OutputDirectory ./artifacts
```

Результат:

```text
artifacts/
├── NexRoute-0.1.1-win-x64.zip
└── NexRoute-0.1.1-win-x64.zip.sha256
```

## 🔎 Что проверяет сборка

Сборщик и CI должны подтвердить:

- официальный upstream asset Flowseal найден по закреплённому тегу;
- присутствуют `winws.exe`, `WinDivert.dll` и `WinDivert64.sys`;
- установлен `.service/nexroute-ui.ps1`;
- UI source состоит только из ASCII-символов;
- `service.bat` подключён к renderer-у и action-анимациям;
- `service.bat` не содержит прямых кириллических литералов;
- каждый strategy BAT содержит `NEXROUTE_PROFILE_BOOT`;
- итоговый ZIP имеет ожидаемый размер;
- SHA-256 из файла совпадает с независимо вычисленным значением.

## 🤖 GitHub Actions

### Проверка Pull Request

Workflow `Validate repository` выполняет:

1. проверку структуры и документации;
2. PowerShell AST parsing;
3. проверку ASCII-safe UI;
4. Windows smoke-build;
5. распаковку итогового ZIP;
6. инспекцию `service.bat`, UI runtime и strategy hooks;
7. загрузку временного artifact.

### Ручная проверка сборки

1. Откройте **Actions**.
2. Выберите `Build and publish release`.
3. Нажмите **Run workflow**.
4. Укажите версию только при необходимости.
5. Скачайте artifact после завершения workflow.

Ручной запуск стандартного workflow не создаёт публичный Release без тега.

### Публичный Release

Стандартный процесс:

1. обновить `.service/version.txt`, README и CHANGELOG;
2. добавить release notes;
3. слить подготовленный PR в `main`;
4. создать аннотированный тег, совпадающий с версией:

   ```bash
   git tag -a v0.1.1 -m "NexRoute 0.1.1"
   git push origin v0.1.1
   ```

5. workflow проверит соответствие тега файлу версии;
6. после успешной сборки GitHub CLI создаст Release и прикрепит ZIP + SHA-256.

Для bootstrap-релизов допускается одноразовый workflow `publish-vX.Y.Z.yml`, который после merge самостоятельно создаёт тег и Release. Такой workflow должен быть идемпотентным и безопасно завершаться, если Release уже существует.

## ✅ Release checklist

- [ ] `scripts/Test-Repository.ps1` проходит
- [ ] pinned Flowseal version проверена
- [ ] changelog upstream изучен
- [ ] PowerShell UI parsing проходит
- [ ] UI source состоит только из ASCII
- [ ] сгенерированный `service.bat` не содержит кириллицу
- [ ] action-анимации подключены
- [ ] все strategy BAT содержат launch-hook
- [ ] Windows smoke-build проходит
- [ ] установка и удаление службы работают
- [ ] ручной запуск strategy BAT работает
- [ ] Discord Web/CDN/Voice проверены на реальной сети
- [ ] YouTube Web/Video проверены на реальной сети
- [ ] Game Filter и IPSet Filter проверены
- [ ] переключение RU/EN сохраняется
- [ ] SHA-256 опубликован
- [ ] THIRD_PARTY_NOTICES присутствует в архиве

## 🔙 Откат

GitHub Releases являются неизменяемыми артефактами версии. При критической ошибке:

1. пометьте релиз как pre-release или удалите ошибочный asset;
2. создайте исправление с новой patch-версией;
3. не заменяйте содержимое уже опубликованного ZIP без изменения версии;
4. временно укажите предыдущую стабильную версию в README.
