# Service Matrix и worker runtime — NexRoute 0.7.2

## Изоляция

Каждый активный сервис может получить отдельный процесс `winws` со своими hostlist/ipset файлами. Перед запуском проверяются уникальность service ID, filter tokens и привязка каждого `winws`-аргумента к файлам выбранного сервиса.

Наличие отдельных файлов само по себе не гарантирует непересекающиеся области перехвата: домены могут совпадать, а IP-подсети — быть вложенными. Новый анализатор сравнивает доменные и IPv4/IPv6 CIDR области и показывает пары сервисов с числом пересечений. Учитывается до 256 записей на список одного сервиса, после чего отчёт получает `partial`. Это не даёт ложного обещания полного анализа огромных IPSET.

Найденный overlap — сигнал к проверке приоритетов. Общие домены не удаляются автоматически, чтобы не нарушать работу сервисов.

## Жизненный цикл

В `.service/workers/<service>.json` сохраняются PID, path executable, processStartedUtc, generation, strategy, consecutiveFailures, consecutiveFailovers, healthyCycles и cooldownUntilUtc. Завершение разрешено только при совпадении существующего процесса с записанным временем запуска и executable path.

Если PID переиспользован или identity проверить нельзя, процесс не завершается; worker получает `identity-unverified` и требует ручной проверки. Состояния `failed` и `stopped` не подвергаются бесконечным попыткам запуска.

Windows PowerShell 5.1 поддерживается без `ProcessStartInfo.ArgumentList`. Supervisor использует один mutex на установку, а операции изменения состояния — отдельный mutex, чтобы исключить одновременный restart и stop.

## Failover

После 3 неудачных проверок (настройка `FailureThreshold`) supervisor выбирает следующий проверенный кандидат только для соответствующего сервиса. Начальный cooldown — 30 секунд, затем экспоненциально увеличивается максимум до 300 секунд. После 3 последовательных успешных проверок серия переключений сбрасывается. Здоровые workers продолжают работать.

Стратегии с результатом `INCONCLUSIVE` из Strategy Lab не считаются подтверждёнными альтернативами. Если кандидатов нет, supervisor не переключается на произвольный BAT: сервис помечается `NR-WORKER-NO-FALLBACK`.

## Управление

Из классического Control Node: `Diagnostic Core → Управление процессами сервисов`. Показаны PID, generation, health, cooldown, количество неудач и предупреждения о пересечениях. Доступны отдельные действия «Запустить», «Остановить», «Перезапустить» для выбранного сервиса.

Для скриптов:

~~~powershell
powershell.exe -NoProfile -File .service/nexroute-worker-host.ps1 -Mode Inspect -Root . -Json
powershell.exe -NoProfile -File .service/nexroute-worker-host.ps1 -Mode RestartService -Root . -ServiceId discord -Json
powershell.exe -NoProfile -File .service/nexroute-worker-host.ps1 -Mode StopService -Root . -ServiceId discord -Json
powershell.exe -NoProfile -File .service/nexroute-worker-host.ps1 -Mode StartService -Root . -ServiceId discord -Json
~~~

Ручной `StopService` не отключает остальные сервисы. `StartService` использует сохранённую выбранную стратегию, если она ещё присутствует в конфигурации.

## Безопасность и диагностика

В локальном `Inspect` видны имена стратегий, ID сервисов и PID. В публичный ZIP/clipboard попадают только количественные агрегаты: сколько workers работает, сколько требует внимания, число потенциальных пересечений и степень покрытия анализа. Raw hostlist, ipset, PID, DNS, IP и пользовательские пути не экспортируются.

После обновления с v0.7.1 у уже запущенных процессов могут отсутствовать новые поля identity. Для безопасности NexRoute не будет завершать PID вслепую. Остановите старый supervisor и workers вручную после проверки процесса либо выполните штатный Restart после выхода старых процессов.

## Проверки

`Invoke-Pester -Path ./tests/WorkerRuntime072.Tests.ps1,./tests/WorkerHost.Tests.ps1,./tests/WorkerSupervisor.Tests.ps1 -CI`

Автоматические тесты проверяют жизненный цикл дочерних процессов, ошибочные PID, cooldown, overlap detection, PS 5.1 quoting и адресные операции. Работа реального DPI у провайдера этим не подтверждается.
