<div align="center">

<img src="assets/nexroute-mark.svg" width="150" alt="NexRoute emblem">

# NexRoute 🧭

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D6?logo=windows)](docs/COMPATIBILITY.md)
[![Flowseal baseline](https://img.shields.io/badge/Flowseal-1.10.0-6f42c1)](docs/UPSTREAM.md)
[![Version](https://img.shields.io/badge/version-0.2.1-24e1d6)](.service/version.txt)

**Консольная система управления стратегиями обхода DPI для Windows 10 и Windows 11.**

[English](docs/README_EN.md) · [Сервисы](docs/SERVICES.md) · [Архитектура](docs/ARCHITECTURE.md) · [Сборка](docs/RELEASES.md)

</div>

> [!IMPORTANT]
> NexRoute не является VPN или прокси. Проект локально управляет `winws` и WinDivert, не меняет публичный IP-адрес и применяет выбранные стратегии к указанному трафику.

## 🔧 Что исправлено в 0.2.1

Версия `0.2.1` исправляет критический дефект `0.2.0`, из-за которого пункты меню падали с ошибкой:

```text
Exception calling "GetFullPath": Illegal characters in path.
```

Причина заключалась в передаче `-Root "%~dp0"`: путь `%~dp0` заканчивается обратным слэшем, из-за чего Windows могла поглотить следующие параметры командной строки.

Исправление:

- восстанавливает визуальный дизайн главной панели из NexRoute `0.1.1`;
- применяет тот же стиль к статусу, выбору стратегии, payload, синхронизации, тестам и матрице сервисов;
- восстанавливает параметры, которые были поглощены повреждённым аргументом `Root`;
- автоматически удаляет небезопасный `-Root "%~dp0"` из BAT-файлов после первого запуска;
- проверяет сценарии пунктов `1` и `14` в Windows PowerShell 5.1;
- сохраняет 15 сервисных профилей версии `0.2.0`.

## ✨ Возможности

- Flowseal `1.10.0` как закреплённая функциональная основа;
- все штатные `general*.bat` стратегии;
- Discord Web/CDN/Voice и YouTube;
- Game Filter и IPSet Filter;
- установка выбранной стратегии как службы Windows;
- RU/EN интерфейс;
- классический Control Node дизайн из `0.1.1`;
- анимации запуска, IPSet, hosts, тестов и применения сервисной матрицы;
- собственный значок и ярлык `NexRoute.lnk`;
- ZIP и SHA-256 только через GitHub Releases.

## 🌐 Матрица сервисов

Пункт **[14] Матрица сервисов** управляет следующими профилями:

- YouTube;
- Discord;
- ChatGPT;
- FaceTime;
- Snapchat;
- Viber;
- Signal;
- X (Twitter);
- Instagram;
- Facebook;
- Telegram;
- LinkedIn;
- TikTok;
- WhatsApp;
- CaseBattle.

Управление: `↑`, `↓`, `SPACE`, `A`, `N`, `ENTER`, `ESC`.

Подробности и ограничения: [docs/SERVICES.md](docs/SERVICES.md).

## 🚀 Быстрый старт

1. Откройте GitHub Releases.
2. Скачайте:

   ```text
   NexRoute-0.2.1-win-x64.zip
   NexRoute-0.2.1-win-x64.zip.sha256
   ```

3. Полностью распакуйте архив в новую папку.
4. Не запускайте BAT-файлы непосредственно из ZIP.
5. Запустите `NexRoute.lnk`, `nexroute.bat` или `service.bat` от имени администратора.
6. Выберите стратегию и настройте матрицу сервисов.

## 🖥️ Системные требования

- Windows 10 x64;
- Windows 11 x64;
- Windows PowerShell 5.1+;
- права администратора для службы и WinDivert.

## 🧪 Проверки Release

CI выполняет:

- PowerShell AST parsing всех модулей;
- реальную Windows-сборку;
- распаковку ZIP;
- проверку SHA-256;
- проверку 15 сервисов;
- запуск RU/EN страниц через Windows PowerShell 5.1;
- воспроизведение повреждённого `Root` из пользовательского отчёта;
- проверку автоматического исправления BAT-файлов;
- проверку главного дизайна `0.1.1`.

## ⚠️ Ограничения

Эффективность зависит от провайдера, региона, DNS и конфигурации DPI. FaceTime, Signal, Viber и WhatsApp являются экспериментальными доменными профилями; статический hostlist не гарантирует работу звонков и медиареле.

## ⚖️ Лицензирование

Собственный код и документация NexRoute распространяются по MIT. Flowseal, zapret и WinDivert сохраняют собственные лицензии и уведомления. См. [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## 👤 Автор

**Onmaynec** — [@Onmaynec](https://github.com/Onmaynec)

---

**NexRoute 0.2.1** · Baseline: **Flowseal 1.10.0** · Windows 10/11 x64
