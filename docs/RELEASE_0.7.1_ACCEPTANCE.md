# NexRoute 0.7.1 — критерии готовности релиза

## Strategy Lab

- [ ] Рейтинг использует HTTPS; DNS/TLS/ICMP/HLS/DPI остаются диагностическими признаками.
- [ ] Отсутствующий замер не превращается в фиктивный ноль или успех.
- [ ] Нужны повторные HTTPS-наблюдения и здоровые контрольные endpoints.
- [ ] HTTP 4xx, обрыв range и непроверенный TLS-сертификат не объявляются успешными.
- [ ] YouTube playback не объявляется без HLS-сегмента, voice не выводится из HTTPS.
- [ ] История не содержит IP, network key, приватные URL или ошибки с credentials.

## Диагностика

- [ ] Внутренний schema 3 и first-run compatibility сохранены.
- [ ] Health summary показывает коды состояний и следующий шаг.
- [ ] Clipboard/ZIP используют allowlist export schema 4 без сырых логов и monitor-state.
- [ ] IP, DNS servers, имена адаптеров, VPN, локальные пути и списки не попадают в экспорт.
- [ ] Pester проверяет отсутствие приватных маркеров в JSON.

## Выпуск

- [ ] Repository validation и Pester suite зелёные.
- [ ] Website typecheck и production build зелёные.
- [ ] Windows online/offline package, launcher checks и updater/rollback зелёные.
- [ ] Проверено наличие нового diagnostic module в ZIP.
- [ ] Stable v0.7.1 содержит ZIP, SHA-256, validation JSON/Markdown и проверенную GitHub attestation.

CI не измеряет работу DPI у конкретного провайдера, реальную UDP-связь или полный набор Windows hardware conditions.
