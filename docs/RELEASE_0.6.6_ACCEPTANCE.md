# NexRoute 0.6.6 — критерии готовности релиза

## Версия и документация

- [ ] `.service/version.txt`, website package и lockfile содержат 0.6.6;
- [ ] README, RU/EN docs и сайт используют Flowseal 1.10.3 и корректные версии;
- [ ] актуальные инструкции содержат 22 upstream-стратегии, 24 patch targets и 15 сервисных профилей;
- [ ] сборочные примеры используют 0.6.6 и pinned archive 1.10.3;
- [ ] архивные документы сохранены и не выданы за текущие;
- [ ] регрессионные проверки отклоняют устаревшие версии и числа.

## Updater и совместимость

- [ ] переход 0.6.5 → 0.6.6 сохраняет пользовательские данные побайтно;
- [ ] принудительная ошибка post-update health вызывает rollback;
- [ ] повторная установка той же версии возвращает `current`;
- [ ] classic UI, Strategy Lab и upstream contracts сохранены.

## Package и публикация

- [ ] source/Pester tests успешны;
- [ ] website typecheck и production build успешны;
- [ ] online/offline Windows package tests и launcher smoke успешны;
- [ ] Release содержит ZIP, checksum, validation JSON и Markdown;
- [ ] release workflow проверяет attestations перед публикацией;
- [ ] stable updater видит 0.6.6 после публикации.

## Ограничения

CI проверяет source/package contracts и synthetic scenarios. Реальные ISP, уведомления в пользовательской сессии, физические IPv6/DNS-переходы требуют отдельной проверки; их нельзя автоматически отмечать `passed`.
