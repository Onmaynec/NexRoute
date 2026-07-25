# Матрица обхода сервисов 🌐

NexRoute `0.2.0` добавляет управляемую матрицу доменных профилей. Она открывается через пункт **[14] Матрица сервисов** в `service.bat`.

## 🎛️ Управление

- `↑` / `↓` — перемещение по списку;
- `SPACE` — включить или выключить выбранный сервис;
- `A` — включить все профили;
- `N` — выключить все профили;
- `ENTER` — сохранить и применить;
- `ESC` — отменить изменения.

Состояние хранится в `.service/services-state.json`. Определения сервисов находятся в `.service/services.json`.

## 🧩 Как применяются профили

NexRoute не перезаписывает пользовательские строки. Скрипт создаёт только управляемые блоки:

```text
# NEXROUTE-SERVICES-BEGIN
...
# NEXROUTE-SERVICES-END
```

в `lists/list-general-user.txt` и:

```text
# NEXROUTE-DISABLED-SERVICES-BEGIN
...
# NEXROUTE-DISABLED-SERVICES-END
```

в `lists/list-exclude-user.txt`.

Включённые сервисы добавляются в пользовательский hostlist. Выключенные сервисы добавляются в исключения. Благодаря этому можно отключить даже встроенные профили YouTube и Discord, не изменяя upstream-списки Flowseal.

## 📋 Сервисы версии 0.2.0

| Сервис | Режим | По умолчанию | Основные домены |
|---|---|---:|---|
| YouTube | baseline | ВКЛ | `youtube.com`, `googlevideo.com`, `ytimg.com` |
| Discord | baseline | ВКЛ | `discord.com`, `discord.gg`, `discord.media` |
| ChatGPT | web | ВЫКЛ | `chatgpt.com`, `openai.com`, `oaistatic.com` |
| FaceTime | experimental | ВЫКЛ | Apple/iCloud control domains |
| Snapchat | web | ВЫКЛ | `snapchat.com`, `snap.com`, `sc-cdn.net` |
| Viber | experimental | ВЫКЛ | `viber.com`, `viber.net`, `viber.me` |
| Signal | experimental | ВЫКЛ | `signal.org`, `signal.group`, `signal.link`, VoIP domains |
| X (Twitter) | web | ВЫКЛ | `x.com`, `twitter.com`, `t.co`, `twimg.com` |
| Instagram | web | ВЫКЛ | `instagram.com`, `cdninstagram.com` |
| Facebook | web | ВЫКЛ | `facebook.com`, `fbcdn.net`, `fbsbx.com` |
| Telegram | web | ВЫКЛ | `telegram.org`, `t.me`, `telegra.ph` |
| LinkedIn | web | ВЫКЛ | `linkedin.com`, `licdn.com` |
| TikTok | web | ВЫКЛ | `tiktok.com`, `tiktokcdn.com`, `tiktokv.com` |
| WhatsApp | experimental | ВЫКЛ | `whatsapp.com`, `whatsapp.net`, `wa.me` |
| Кейс батл | web | ВЫКЛ | `casebattle.net` |

## ⚠️ Ограничения

Матрица управляет доменами, которые обрабатываются существующими стратегиями `winws`. Это не гарантирует полную работу голосовых и видеозвонков.

FaceTime, Signal, Viber и WhatsApp могут использовать дополнительные UDP-порты, динамические адреса и медиареле. Поэтому они помечены как **experimental**. Веб-интерфейс, авторизация и управляющие соединения могут работать отдельно от звонков и медиатрафика.

Официальные технические источники, использованные для экспериментальных профилей:

- Apple: FaceTime/iMessage firewall and port documentation;
- Signal: Firewall and Internet settings (`*.signal.org`, Signal link/group/VoIP domains);
- Viber: desktop TCP/UDP ports `80`, `443`, `4244`, `5242`, `5243`, `7985`.

## 🛡️ Совместимость

Пользовательские строки вне управляемых блоков сохраняются. При миграции с Flowseal можно копировать:

```text
lists/list-general-user.txt
lists/list-exclude-user.txt
lists/ipset-exclude-user.txt
```

При первом запуске NexRoute добавит собственные блоки, не удаляя существующие домены.
