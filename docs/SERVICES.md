# Service Matrix v2

NexRoute `0.2.2` использует матрицу сервисов не только как доменный список. Каждый профиль описывает полный набор данных, который может быть подключён к стратегиям и тестам.

## Схема

| Поле | Назначение |
|---|---|
| `domains` | Домены для `list-general-user.txt` и исключений |
| `testTargets` | Реальные HTTP/TLS endpoints для Strategy Lab |
| `tcpPorts` | Дополнительные TCP-порты перехвата |
| `udpPorts` | Дополнительные UDP-порты, включая media/STUN/QUIC |
| `resolveHosts` | Хосты для динамического DNS-разрешения в IPv4 `/32` |
| `ipCidrs` | Статические IPv4-подсети |
| `ipSources` | Удалённые источники IPv4 CIDR |

## Что создаётся при применении

- `lists/list-general-user.txt` — управляемый блок включённых доменов;
- `lists/list-exclude-user.txt` — управляемый блок отключённых доменов;
- `lists/list-services-enabled.txt` — отдельный hostlist Service Matrix;
- `lists/ipset-services-user.txt` — разрешённые IP endpoints и внешние CIDR;
- `.service/services-runtime.cmd` — агрегированные TCP/UDP-порты и winws arguments.

## Подключение к стратегиям

Сборщик патчит все 21 настоящую конфигурацию Flowseal `1.10.0`: `general.bat` и все варианты `general (...)`.

- расширяет `--wf-tcp` и `--wf-udp` портами включённых сервисов;
- подключает отдельный TCP-фильтр по hostlist/IPSet;
- подключает отдельный UDP-фильтр по hostlist/IPSet;
- применяет матрицу перед каждым ручным запуском;
- применяет runtime-параметры при установке стратегии как службы.

`nexroute.bat` является launcher-ом главного меню, а не отдельной сетевой стратегией, поэтому он исключён из Strategy Lab.

## Перезапуск службы

После `ENTER` в `[14] SERVICE MATRIX` контроллер:

1. сохраняет состояние;
2. пересобирает домены, IP и порты;
3. определяет установленную стратегию из реестра;
4. повторно создаёт службу `zapret` с обновлённой командной строкой;
5. запускает службу.

Если служба не установлена, матрица сохраняется без ошибки и будет применена при следующем запуске/установке.

## Strategy Lab

Для каждого включённого профиля лаборатория получает несколько целей. Типичные роли:

- `web`;
- `app`;
- `api`;
- `cdn`;
- `media`;
- `gateway`;
- `updates`;
- `signalling`.

Стандартный режим выполняет HTTP, TLS 1.2, TLS 1.3 и latency checks. DPI-режим TCP 16–20 КБ использует прежнюю suite Flowseal.

## Профили

| Профиль | Покрытие |
|---|---|
| YouTube | Web, API, изображения, видео, QUIC |
| Discord | Web/Desktop, Gateway, CDN, media, updates, voice/video |
| ChatGPT | Web, API, auth, static, files |
| FaceTime | iCloud/push signalling, STUN, RTP audio/video ranges |
| Snapchat | Web/Desktop, account, CDN, calls |
| Viber | Desktop, account, media, voice/video ports |
| Signal | Desktop bootstrap, chat gateway, storage, attachments, updates |
| X | Web, API, images, video |
| Instagram | Web/App, API, CDN, media/calls |
| Facebook | Web/App, Graph API, CDN, Messenger/calls |
| Telegram | Web/Desktop, API, media, official DC CIDR source |
| LinkedIn | Web, API, media, static assets |
| TikTok | Web/App, API, video CDN |
| WhatsApp | Web/Desktop, messaging, CDN, media, STUN/TURN and voice |
| CaseBattle | Web application and static resources |

## Ограничения

IP-адреса CDN и медиареле меняются. DNS-разрешение выполняется при применении матрицы, но некоторые приложения могут использовать дополнительные адреса, IPv6 или динамические peer-to-peer соединения. Портовое и доменное покрытие повышает вероятность работы, но не является универсальной гарантией для любого DPI.
