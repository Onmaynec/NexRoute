# Сборка и публикация Releases 📦

## 🎯 Политика

Исполняемые компоненты NexRoute публикуются только в GitHub Releases. В Git запрещены `.exe`, `.dll`, `.sys`, `.bin`, `.ico`, `.lnk` и архивы.

Каждый Release собирается заново из `main`. Значок и ярлык также генерируются во время сборки.

## 🛠️ Локальная сборка

```powershell
pwsh ./scripts/Test-Repository.ps1

pwsh ./scripts/Build-NexRoute.ps1 `
  -Version 0.2.0 `
  -UpstreamVersion 1.10.0 `
  -OutputDirectory ./artifacts
```

Результат:

```text
artifacts/
├── NexRoute-0.2.0-win-x64.zip
└── NexRoute-0.2.0-win-x64.zip.sha256
```

## 🔎 Что проверяет сборка

- официальный Flowseal asset получен по тегу `1.10.0`;
- присутствуют `winws.exe`, `WinDivert.dll`, `WinDivert64.sys`;
- установлены UI, service controller, i18n и `services.json`;
- `service.bat` подключён к Status, StrategyPicker, PayloadManager, IPSet/hosts sync, Tests и Services;
- `service.bat` не содержит прямой кириллицы;
- все strategy BAT содержат animation + service-matrix hooks;
- создано ровно 15 сервисных профилей;
- managed-блоки добавлены без удаления пользовательских строк;
- сгенерированы `.service/nexroute.ico` и `NexRoute.lnk`;
- test laboratory содержит NexRoute header;
- ZIP распаковывается и имеет ожидаемый размер;
- SHA-256 совпадает с независимо вычисленным значением.

## 🤖 GitHub Actions

Workflow `Validate repository` выполняет:

1. проверку структуры и документации;
2. PowerShell AST parsing;
3. валидацию JSON/i18n/service definitions;
4. Windows smoke-build;
5. распаковку и инспекцию Release ZIP;
6. запуск неинтерактивных RU/EN экранов через Windows PowerShell 5.1;
7. проверку managed hostlist/exclude blocks;
8. проверку иконки, ярлыка и strategy hooks;
9. загрузку временного artifact.

## 🚀 Публичный Release

1. обновить `.service/version.txt`, README и CHANGELOG;
2. добавить `.github/release-notes/vX.Y.Z.md`;
3. слить PR в `main`;
4. создать тег:

   ```bash
   git tag -a v0.2.0 -m "NexRoute 0.2.0"
   git push origin v0.2.0
   ```

5. release workflow повторно соберёт пакет из `main`;
6. GitHub Release получает ZIP и `.sha256`.

Для автоматической первой публикации версии допускается одноразовый workflow `publish-v0.2.0.yml`, который должен безопасно завершаться, если тег или Release уже существуют.

## ✅ Release checklist

- [ ] repository validation проходит
- [ ] PowerShell 5.1 runtime tests проходят
- [ ] 15 сервисов присутствуют и имеют домены
- [ ] RU/EN интерфейс запускается
- [ ] Status/Strategy/Payload/IPSet/Hosts/Tests/Services страницы проверены
- [ ] icon и shortcut созданы
- [ ] managed-блоки не удаляют пользовательские строки
- [ ] Windows smoke-build проходит
- [ ] установка/удаление службы проверены вручную
- [ ] YouTube и Discord проверены на реальной сети
- [ ] experimental-сервисы не заявлены как гарантированно рабочие
- [ ] SHA-256 опубликован
- [ ] THIRD_PARTY_NOTICES присутствует в архиве

## 🔙 Откат

Не заменяйте содержимое уже опубликованного ZIP без изменения версии. При критической ошибке создайте новую patch-версию и временно пометьте проблемный Release как pre-release или удалите его assets.
