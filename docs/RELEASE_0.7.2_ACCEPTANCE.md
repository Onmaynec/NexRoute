# NexRoute 0.7.2 — критерии готовности релиза

## Worker process ownership
- [ ] Worker записывает PID, processStartedUtc, executable и generation.
- [ ] При несовпадении process identity чужой процесс не завершается.
- [ ] Старые PID-only записи не используются как доказательство владения.
- [ ] Повторный запуск того же normalized service ID отклоняется.
- [ ] Аргументы запуска безопасно обрабатываются на Windows PowerShell 5.1.
- [ ] Supervisor один на установку; операции сериализованы.

## Supervisor
- [ ] Failover затрагивает только проблемный сервис.
- [ ] Cooldown и лимит роста задержки исключают постоянные перезапуски.
- [ ] Три последовательных успешных health checks сбрасывают счётчик переключений.
- [ ] Без проверенных fallback стратегия не выбирается случайным образом.
- [ ] INCONCLUSIVE-кандидаты не попадают в автоматическую последовательность.
- [ ] Ошибка fallback не завершает управление здоровыми workers.

## Service Matrix и UX
- [ ] Проверяются дубли ID и полные совпадения filter tokens.
- [ ] В отчёте отмечены совпадения доменов, вложенные домены, IPv4/IPv6 CIDR.
- [ ] Неполная проверка scope отмечается как partial.
- [ ] Команды Inspect/StartService/StopService/RestartService протестированы.
- [ ] Консоль показывает PID, generation, errors, cooldown и пары пересечений.
- [ ] Privacy-safe diagnostics содержат только агрегированные counts.

## Выпуск
- [ ] Repository validation и Pester suite зелёные.
- [ ] Website typecheck/build зелёные.
- [ ] Windows online/offline package и launcher checks зелёные.
- [ ] Updater 0.7.1 → 0.7.2 и rollback зелёные.
- [ ] Опубликован stable release с ZIP, SHA-256 и двумя validation reports.
- [ ] Подтверждена аттестация артефактов.

Hosted CI не подтверждает реальную совместимость каждого VPN, провайдера, сетевого адаптера и внешнего WinDivert фильтра.
