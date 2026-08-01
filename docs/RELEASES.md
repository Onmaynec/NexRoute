# Сборка и публикация Releases 📦

## Политика

Исполняемые компоненты NexRoute публикуются только в GitHub Releases. В Git запрещены `.exe`, `.dll`, `.sys`, `.bin`, `.ico`, `.lnk` и архивы.

Каждый Release собирается заново из `main`. Flowseal фиксируется manifest-ом, значок и ярлык генерируются во время сборки, а все изменения upstream-файлов записываются в patch report.

## Подготовка окружения

```powershell
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module Pester -RequiredVersion 5.6.1 -Scope CurrentUser -Force

pwsh ./scripts/Test-Repository.ps1
Invoke-Pester -Path ./tests -CI -Output Detailed
```

## Онлайн-сборка

```powershell
pwsh ./scripts/Build-Release.ps1 `
  -Version 0.3.0 `
  -OutputDirectory ./artifacts `
  -UpstreamCachePath ./cache/zapret-discord-youtube-1.10.0.zip

pwsh ./scripts/Test-Release.ps1 `
  -ArtifactsDirectory ./artifacts `
  -ExtractDirectory ./artifacts-test
```

Результат:

```text
artifacts/
├── NexRoute-0.3.0-win-x64.zip
└── NexRoute-0.3.0-win-x64.zip.sha256
```

## Офлайн-повтор

Проверенный archive из `-UpstreamCachePath` можно использовать без сети:

```powershell
pwsh ./scripts/Build-Release.ps1 `
  -Version 0.3.0 `
  -OutputDirectory ./artifacts-offline `
  -UpstreamArchive ./cache/zapret-discord-youtube-1.10.0.zip

pwsh ./scripts/Test-Release.ps1 `
  -ArtifactsDirectory ./artifacts-offline `
  -ExtractDirectory ./artifacts-offline-test `
  -SkipRuntime
```

Офлайн-сборка не отключает проверки: archive name, size, SHA-256, required paths и patch contract остаются обязательными.

## Upstream contract

`.service/upstream-manifest.json` фиксирует:

- `Flowseal/zapret-discord-youtube`;
- tag `1.10.0`;
- единственный допустимый ZIP asset;
- committed SHA-256;
- минимальный размер;
- обязательные файлы внутри архива.

При online build дополнительно проверяются GitHub asset size и `digest`, если поле предоставлено API. Base builder получает архив через локальный verified proxy.

## Patch provenance

Release ZIP содержит:

```text
.service/upstream-manifest.json
.service/upstream-lock.json
.service/patch-report.json
NEXROUTE_BUILD_INFO.txt
```

Patch report должен содержать ровно 23 target-а:

- 21 реальную Flowseal strategy;
- `service.bat`;
- `utils/test zapret.ps1`.

Для каждой записи обязательны уникальный ID, относительный target, число операций и разные SHA-256 до/после.

## Что проверяет package test

- версия пакета совпадает с `.service/version.txt`;
- upstream lock совпадает с manifest;
- locked archive сообщает 21 strategy;
- patch report содержит 23 уникальные записи;
- все strategy BAT имеют Service Matrix V4 hooks;
- `service.bat` имеет refresh/reinstall V4 contract;
- Strategy Lab подключает динамические targets V4;
- 15 Service Matrix profiles валидны;
- отдельные service hostlist/IPSet не смешиваются;
- privacy-safe Diagnostics создаётся;
- EN/RU UI запускается через Windows PowerShell;
- multi-resolution icon создан;
- ZIP checksum совпадает с независимо вычисленным SHA-256.

## GitHub Actions

Workflow `Validate repository` выполняет:

1. source validation и PowerShell AST parsing `.ps1`/`.psm1`;
2. Pester Service Matrix tests;
3. Pester upstream contract tests;
4. online Windows build с сохранением verified upstream cache;
5. package verification;
6. полный offline rebuild из cache;
7. повторную package verification;
8. сравнение upstream SHA, patch targets, стратегий и сервисов;
9. загрузку логов и smoke ZIP.

Workflow `Build and publish NexRoute` повторяет все критические проверки из `main`, публикует только online-пакет и не создаёт Release, если committed upstream SHA отсутствует или не совпадает.

## Публичный Release

1. обновить `.service/version.txt`, README и CHANGELOG;
2. обновить `.service/upstream-manifest.json`, когда меняется Flowseal asset;
3. добавить `.github/release-notes/vX.Y.Z.md`;
4. убедиться, что dependent PR основан на уже принятой предыдущей версии;
5. слить PR в `main`;
6. release workflow создаст tag `vX.Y.Z`, ZIP и `.sha256` после успешных online/offline проверок.

Не создавайте tag вручную до успешного merge: workflow является единственным владельцем автоматической публикации.

## Release checklist ✅

- [ ] repository validation проходит
- [ ] все Pester tests проходят
- [ ] upstream manifest содержит 64-символьный SHA-256
- [ ] online и offline upstream SHA совпадают
- [ ] upstream lock сообщает 21 strategy
- [ ] patch report содержит 23 уникальных target-а
- [ ] 15 сервисов присутствуют и валидны
- [ ] RU/EN интерфейс запускается
- [ ] managed-блоки не удаляют пользовательские строки
- [ ] Windows smoke-build проходит
- [ ] установка/удаление службы проверены вручную
- [ ] YouTube и Discord проверены на реальной сети
- [ ] SHA-256 опубликован
- [ ] THIRD_PARTY_NOTICES присутствует в архиве

## Откат 🔙

Не заменяйте содержимое уже опубликованного ZIP без изменения версии. При критической ошибке создайте новую patch-версию и временно пометьте проблемный Release как pre-release или удалите его assets.

При неожиданном изменении upstream asset сборка должна упасть по SHA-256. Сначала выясните причину; не обновляйте lock автоматически без анализа содержимого.
