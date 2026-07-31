# Service Matrix v2

NexRoute `0.2.3` использует матрицу сервисов как источник доменных, IP- и транспортных фильтров для всех 21 настоящих стратегий Flowseal `1.10.0`.

## Схема профиля

| Поле | Назначение |
|---|---|
| `domains` | Домены сервиса |
| `testTargets` | Реальные HTTP/TLS endpoints для Strategy Lab |
| `tcpPorts` | TCP-порты перехвата |
| `udpPorts` | UDP-порты, включая media/STUN/QUIC |
| `resolveHosts` | Хосты для DNS-разрешения в IPv4 `/32` |
| `ipCidrs` | Статические IPv4-подсети |
| `ipSources` | Удалённые источники IPv4 CIDR |

Порты должны находиться в диапазоне `1-65535`; диапазон должен быть возрастающим. CIDR проверяется через `System.Net.IPAddress` и допускает только IPv4 с префиксом `0-32`.

## Правило общих доменов

Контроллер сначала строит карту владения доменами. Домен включается, если активен хотя бы один использующий его профиль. В `list-exclude-user.txt` он попадает только когда выключены все владельцы.

Например, `fbcdn.net` используется Instagram, Facebook и WhatsApp. Включение любого из этих профилей не позволяет остальным выключенным профилям добавить `fbcdn.net` в исключения.

## Изолированные runtime-группы

Для каждого включённого профиля создаются:

```text
lists/list-service-<id>.txt
lists/ipset-service-<id>.txt
```

В `.service/services-runtime.cmd` формируются отдельные `--new`-группы для доменов и IP конкретного профиля с его собственными TCP/UDP-портами. Это предотвращает cross-product, при котором широкий UDP-диапазон одного приложения применялся к адресам всех включённых сервисов.

Общие совместимые файлы сохраняются:

```text
lists/list-services-enabled.txt
lists/ipset-services-user.txt
```

## Состояние и миграция

`services-state.json` использует схему:

```json
{
  "schemaVersion": 2,
  "updatedAtUtc": "2026-08-01T00:00:00Z",
  "services": {
    "youtube": true,
    "discord": true
  }
}
```

Старый плоский JSON мигрируется с backup `services-state.v1.backup.json`. Повреждённый файл сохраняется как `services-state.invalid.backup.json`, после чего создаётся валидное состояние по умолчанию.

## Внешние IP-источники

Успешно проверенные данные сохраняются в `.service/cache/ip-sources`. Максимальный возраст last-known-good кэша — 14 дней. Статусы источников записываются в `.service/ip-source-status.json`:

- `fresh` — источник успешно обновлён;
- `cache` — использована свежая кэшированная копия;
- `failed` — обновление не удалось и допустимого кэша нет.

## Diagnostics

Режим `Diagnostics` экспортирует JSON с версией, ID включённых сервисов, числом сгенерированных записей, статусами источников, SHA-256 runtime и данными окружения. Содержимое пользовательских доменных/IP-списков не копируется.

## Профили

Матрица содержит YouTube, Discord, ChatGPT, FaceTime, Snapchat, Viber, Signal, X, Instagram, Facebook, Telegram, LinkedIn, TikTok, WhatsApp и CaseBattle.

## Ограничения

Версия `0.2.3` разрешает и валидирует IPv4. CDN и медиареле могут менять адреса; IPv6-only и peer-to-peer endpoints потребуют отдельного расширения.
