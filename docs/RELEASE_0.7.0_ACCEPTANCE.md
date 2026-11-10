# NexRoute 0.7.0 — критерии готовности

## Schema и миграция

- [ ] 21 профиль перенесён без изменения исходных ID, параметров и имён BAT;
- [ ] реализована schema v1 и единственный canonical parser;
- [ ] unknown fields, modes, payload/list paths и capture scopes fail closed;
- [ ] отсутствующие payload-файлы останавливают генератор до изменения BAT;
- [ ] golden fixtures сравнивают значения и полные BAT-байты с генератором 0.6.3;
- [ ] runtime Apply не перезаписывает установленную стратегию.

## Интеграция и provenance

- [ ] package содержит JSON manifest и reader;
- [ ] Strategy Builder/preview/worker используют его метаданные;
- [ ] refresh report, patch report и validation report содержат SHA-256 manifest и профильные digests;
- [ ] package test повторно проверяет все hashes;
- [ ] Flowseal 1.10.3, 22 upstream BAT, 24 patch targets и 15 профилей Service Matrix сохранены.

## Проверки и публикация

- [ ] repository validation и полный Pester suite проходят;
- [ ] website typecheck и production build проходят;
- [ ] Windows online/offline package и launcher checks проходят;
- [ ] updater 0.6.6 → 0.7.0 и rollback проходят;
- [ ] stable Release v0.7.0 содержит четыре проверенных assets;
- [ ] Issue #54 закрывается только после успешной публикации.

Hosted CI не подтверждает DPI у конкретного провайдера, видимые уведомления на любой Windows-системе и physical IPv6/DNS transitions.
