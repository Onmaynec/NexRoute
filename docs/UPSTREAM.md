# Upstream baseline 🔗

## Зафиксированная версия

NexRoute `0.1.0` основан на официальном релизе:

```text
Repository: Flowseal/zapret-discord-youtube
Release:    1.10.0
Commit:     9503dc0
Released:   2026-07-22
```

## Функции baseline 1.10.0

- стратегии `general`, `ALT`, `FAKE TLS AUTO`, `SIMPLE FAKE` и экспериментальная `EXP`;
- Discord UDP/Voice и GameFilter UDP fake-payloads;
- замена активных fake-файлов через `service.bat`;
- обновление IPSet и hosts;
- очистка кэша Discord и Discord PTB;
- диагностика системных конфликтов;
- Standard tests и DPI checkers;
- служба Windows и WinDivert integration.

## Правила обновления

NexRoute не использует плавающую ссылку `latest` для функциональной основы. Версия upstream задаётся явно, чтобы одна и та же версия NexRoute всегда собиралась из одного и того же релиза Flowseal.

Перед переходом на новый upstream необходимо:

1. проверить release notes и commit/tag;
2. сравнить структуру `service.bat`;
3. пересмотреть новые стратегии, payloads и списки;
4. проверить лицензии/уведомления;
5. обновить тесты и документацию;
6. выполнить Windows 10/11 regression testing.

## Граница изменений NexRoute

NexRoute 0.1.0 изменяет:

- название и оформление консольного менеджера;
- русский/английский интерфейс меню;
- ссылки проверки обновлений;
- описание Windows-службы;
- документацию, build metadata и release pipeline.

Сетевые параметры стратегий Flowseal 1.10.0 в первой версии сохраняются без функционального переписывания.
