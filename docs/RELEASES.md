# Сборка и публикация Releases 📦

## 🎯 Политика

Бинарные компоненты NexRoute публикуются только в GitHub Releases. В Git-репозитории запрещены файлы `.exe`, `.dll`, `.sys`, `.bin` и архивы.

## 🛠️ Локальная сборка

```powershell
pwsh ./scripts/Test-Repository.ps1

pwsh ./scripts/Build-NexRoute.ps1 `
  -Version 0.1.0 `
  -UpstreamVersion 1.10.0 `
  -OutputDirectory ./artifacts
```

Результат:

```text
artifacts/
├── NexRoute-0.1.0-win-x64.zip
└── NexRoute-0.1.0-win-x64.zip.sha256
```

## 🤖 GitHub Actions

### Ручная проверка сборки

1. Откройте **Actions**.
2. Выберите `Build and publish release`.
3. Нажмите **Run workflow**.
4. Укажите версию только при необходимости.
5. Скачайте artifact после завершения workflow.

Ручной запуск не создаёт публичный Release.

### Публичный Release

1. Обновите `.service/version.txt` и документацию.
2. Слейте подготовленный PR в `main`.
3. Создайте аннотированный тег, совпадающий с версией:

   ```bash
   git tag -a v0.1.0 -m "NexRoute 0.1.0"
   git push origin v0.1.0
   ```

4. Workflow проверит соответствие тега файлу версии.
5. После успешной сборки GitHub CLI создаст Release и прикрепит ZIP + SHA-256.

## ✅ Release checklist

- [ ] `scripts/Test-Repository.ps1` проходит
- [ ] pinned Flowseal version проверена
- [ ] changelog upstream изучен
- [ ] Windows 10 x64 протестирована
- [ ] Windows 11 x64 протестирована
- [ ] установка и удаление службы работают
- [ ] ручной запуск `general*.bat` работает
- [ ] Discord Web/CDN/Voice проверены
- [ ] YouTube Web/Video проверены
- [ ] Game Filter и IPSet Filter проверены
- [ ] обновление hosts/IPSet проверено
- [ ] переключение RU/EN сохраняется
- [ ] SHA-256 опубликован
- [ ] THIRD_PARTY_NOTICES присутствует в архиве

## 🔙 Откат

GitHub Releases являются неизменяемыми артефактами версии. При критической ошибке:

1. пометьте релиз как pre-release или удалите ошибочный asset;
2. создайте исправление с новой patch-версией;
3. не заменяйте содержимое уже опубликованного ZIP без изменения версии;
4. временно укажите предыдущую стабильную версию в README.
