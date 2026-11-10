# Strategy Manifest — NexRoute 0.7.0

## Назначение

Для 21 специализированного профиля источником истины стал `overlay/.service/strategy-manifest.json` (schema v1, strategy set 0.7.0). Flowseal 1.10.3 поставляет 22 upstream BAT, включая `general (ALT13).bat`. Последний не относится к 21 изменённому профилю.

Исторические `nr063-*` ID, имена файлов и параметры сохранены. Это обеспечивает совместимость с уже установленными стратегиями, историей и Service Matrix.

## Структура

| Поле | Назначение |
|---|---|
| `schemaVersion`, `strategySetVersion` | структура и версия набора профилей |
| `sourceCatalogVersion`, `upstreamVersion` | исходный каталог 0.6.3, Flowseal 1.10.3 |
| `profiles[].id`, `displayName`, `file`, `family` | ID, имя, BAT и алгоритм |
| `tcp.modes`, `fooling`, `splitPositions`, `scopes` | TCP-режимы, split, ограничения перехвата |
| `udp.modes`, `scopes` | QUIC, Discord, fallback, GameFilter |
| `sni.primary`, `sni.secondary` | подставляемые в шаблон домены |
| `parameters` | seqOvl, repeats, quicRepeats, discordRepeats, cutoff |
| `fakePayloads`, `requiredLists` | разрешённые относительные ссылки на ресурсы |
| `compatibility`, `provenance` | совместимость и исходная версия профиля |

Модуль `nexroute-strategy-manifest.ps1` содержит canonical parser. Он запрещает неизвестные поля, режимы, файловые пути с выходом из каталога, широкие TCP/UDP scopes, дубликаты и некорректные параметры. Payload проверяется по наличию перед генерацией. JSON не содержит произвольных команд или URL.

## Путь от JSON к релизу

1. `Build-Release.ps1` переносит исходный manifest в пакет без преобразования.
2. `nexroute-strategy-refresh-build.ps1` читает проверенный каталог и передаёт нормализованные объекты в прежний генератор BAT.
3. Service Matrix patch применяется в обычном контролируемом порядке; пользовательский `Apply` никогда не вызывает этот генератор.
4. `strategy-refresh-report.json` хранит manifest SHA-256 и digests всех 21 профиля.
5. `patch-report.json` связывает те же значения с 24 tracked patch targets.
6. `Test-Release.ps1` повторно вычисляет digests, сверяет package со source и блокирует несоответствия.
7. Подписанный validation report публикует manifest SHA-256 и per-profile digests вместе с provenance релиза.

## Потребители

Strategy Builder показывает built-in profiles только для просмотра; пользовательские стратегии остаются отдельными валидированными конфигурациями. Strategy Preview показывает ID/family/modes из единой модели. Workers принимают существующее имя BAT или stable ID, находят связанный файл в локальном каталоге и запускают его прежним механизмом.

Для будущих семейств нужна отдельная проверка генератора и schema: просто изменить JSON недостаточно. Неконтролируемая загрузка профилей из сети не поддерживается.

## Тестирование

~~~powershell
pwsh ./scripts/Test-Repository.ps1
Invoke-Pester -Path ./tests/StrategyManifest070.Tests.ps1 -CI -Output Detailed
Invoke-Pester -Path ./tests/StrategyRefresh063.Tests.ps1 -CI -Output Detailed
~~~

Golden fixtures: `tests/fixtures/Strategy063.Catalog.json` и `tests/fixtures/Strategy063.Renderer.ps1`. Они воспроизводят исходные 21 спецификацию и старый генератор. Регрессионный тест сравнивает не только параметры, но и байты каждого BAT. Изменение fixture вместе с боевым кодом требует отдельного обоснования.

Доказательства CI относятся к source/package контрактам, а не к эффективности DPI у любого ISP, качеству голосовой связи или реальному оборудованию.
