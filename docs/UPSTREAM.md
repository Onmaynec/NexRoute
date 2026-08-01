# Upstream baseline 🔗

## Зафиксированная основа

NexRoute `0.3.0` основан на официальном релизе:

```text
Repository: Flowseal/zapret-discord-youtube
Release:    1.10.0
Asset:      zapret-discord-youtube-1.10.0.zip
```

Точная идентичность архива хранится в `.service/upstream-manifest.json`. Release-сборка не использует плавающий `latest` и не принимает архив только по совпадению имени.

## Декларативный manifest

Manifest schema v1 описывает:

| Поле | Назначение |
|---|---|
| `repository` | GitHub repository в формате `owner/name` |
| `tag` | точный Release tag |
| `assetPattern` | единственный допустимый ZIP asset |
| `minimumBytes` | защита от пустого/ошибочного ответа |
| `expectedSha256` | committed SHA-256 официального архива |
| `requiredPaths` | обязательная структура внутри ZIP |

Абсолютные пути, `..`, дубликаты и повреждённые regex отклоняются до загрузки или распаковки.

## Как проходит online resolution

1. Build обращается к GitHub Release API по точному tag.
2. Выбирается ровно один asset, совпадающий с `assetPattern`.
3. Проверяются фактический размер и SHA-256.
4. Когда GitHub API предоставляет `digest`, он также сравнивается с загруженным файлом.
5. Архив временно распаковывается, чтобы проверить обязательные файлы и distribution root.
6. Только после этого проверенный ZIP передаётся старому base builder через локальный proxy.

Base builder по-прежнему выполняет свою обычную проверку и распаковку, но получает уже зафиксированные байты, а не выполняет независимую непроверенную загрузку.

## Офлайн-сборка

После одной online resolution архив можно сохранить:

```powershell
pwsh ./scripts/Build-Release.ps1 `
  -Version 0.3.0 `
  -OutputDirectory ./artifacts `
  -UpstreamCachePath ./cache/zapret-discord-youtube-1.10.0.zip
```

Затем собрать пакет без обращения к upstream:

```powershell
pwsh ./scripts/Build-Release.ps1 `
  -Version 0.3.0 `
  -OutputDirectory ./artifacts-offline `
  -UpstreamArchive ./cache/zapret-discord-youtube-1.10.0.zip
```

Офлайн-файл проходит тот же SHA-256 и structural contract. Переименование другого ZIP в ожидаемое имя не поможет.

## Lock внутри Release

Готовый пакет содержит:

```text
.service/upstream-manifest.json
.service/upstream-lock.json
```

`upstream-lock.json` записывает:

- repository;
- tag;
- asset name;
- фактический размер;
- SHA-256;
- список обязательных путей;
- количество обнаруженных strategy BAT.

Lock не содержит локальных путей runner-а или времени сборки, поэтому online/offline-пакеты подтверждают одну и ту же upstream-идентичность.

## Patch contract

NexRoute не заменяет Flowseal целиком. Build выполняет ограниченный набор проверяемых изменений:

- runtime hooks во всех 21 strategy BAT;
- маршруты Control Node и безопасный reinstall в `service.bat`;
- динамические Service Matrix targets и локализацию Strategy Lab.

Каждый target записывается в `.service/patch-report.json` с hashes до/после. Anchors должны иметь точное ожидаемое количество совпадений. Если новый upstream изменит структуру файла, build завершится ошибкой до публикации.

## Переход на новый Flowseal

Перед обновлением tag необходимо:

1. изучить release notes и лицензионные изменения;
2. обновить manifest и получить новый официальный SHA-256;
3. проверить required paths и число стратегий;
4. запустить patch contract и устранить все anchor mismatches;
5. выполнить online/offline CI;
6. проверить Windows 10/11, установку службы, Strategy Lab и Service Matrix;
7. выпустить новую версию NexRoute — не менять уже опубликованный asset задним числом.

## Функциональная граница

Flowseal сохраняет собственные `winws`, WinDivert, стратегии, payloads и базовые списки. NexRoute добавляет Control Node, EN/RU UI, Service Matrix, managed user lists, диагностику, runtime isolation, release metadata и проверяемый build/provenance layer.
