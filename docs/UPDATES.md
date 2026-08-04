# 🔄 Безопасные обновления NexRoute 0.6.0

NexRoute использует stable-only updater с checksum, portable artifact-attestation verification, detached replacement transaction, post-update health policy и automatic rollback.

## Required release assets

Для версии `X.Y.Z` updater требует ровно четыре связанных файла:

```text
NexRoute-X.Y.Z-win-x64.zip
NexRoute-X.Y.Z-win-x64.zip.sha256
NexRoute-X.Y.Z-validation.json
NexRoute-X.Y.Z-validation.md
```

Release отклоняется, если отсутствует хотя бы один asset, URL не указывает на immutable official GitHub Release path или tag/version не совпадают.

## Verification flow

До изменения установки updater выполняет:

1. stable-only metadata validation;
2. rejection draft/prerelease;
3. exact asset-name and immutable URL validation;
4. download или controlled local copy четырёх assets;
5. SHA-256 comparison checksum и ZIP;
6. portable attestation verification каждого subject с repository/signer constraints;
7. validation JSON schema check;
8. product/version/status/check IDs consistency check;
9. package extraction и structural verification;
10. проверку 21 strategy, 15 service profiles и 23 patch records.

Tampered checksum, missing asset, mutable URL, failed attestation или invalid signed JSON завершают flow до установки.

## Portable verifier

Заранее установленный GitHub CLI не требуется. NexRoute использует pinned portable GitHub CLI archive с committed SHA-256.

Verifier:

- устанавливается в integrity-checked cache;
- отклоняет ZIP path traversal;
- переустанавливается при изменении cached executable;
- проверяет package, checksum, validation JSON и validation Markdown;
- ограничивает repository и signer `Onmaynec/NexRoute`.

## Attestation receipt

После успешной проверки updater атомарно устанавливает:

```text
.service/release-validation.json
.service/release-validation.md
.service/release-validation.json.attestation-receipt.json
```

Receipt содержит report SHA-256, repository, release version, verifier identity, source asset и список verified subjects.

Validation Viewer доверяет report только когда receipt помечен verified и `reportSha256` совпадает с текущим JSON. Простое копирование JSON не создаёт trusted state.

## Detached update transaction

После verification отдельный helper:

1. принимает transaction handoff;
2. создаёт full backup;
3. останавливает старые NexRoute/winws processes;
4. извлекает verified package в staging;
5. сохраняет user-managed state;
6. заменяет locked files;
7. запускает новую control node;
8. проверяет general Internet и хотя бы один configured protected service;
9. commits transaction только после health success.

Старая instance завершает работу только после принятого handoff.

## Automatic rollback

Rollback запускается при:

- download или checksum failure;
- attestation verification failure;
- invalid package structure;
- extraction failure;
- file replacement failure;
- невозможности запуска новой control node;
- failed post-update health policy.

Rollback восстанавливает точный backup и запускает предыдущую версию. Automated migration fixtures покрывают:

```text
0.4.1 -> 0.6.0
0.5.0 -> 0.6.0
```

## Автоматический режим

Auto update включается через `CHECK UPDATES` или `nexroute-update.cmd`.

`nexroute.bat` выполняет pre-launch check с 24-часовым cooldown. Network failure записывается в state, но не блокирует запуск текущей версии.

```text
.service/update-state.json
```

Установка не выполняется без явного пользовательского подтверждения.

## Ручной Update Center

```text
nexroute-update.cmd
```

Доступны действия:

- включить/выключить automatic checks;
- проверить stable release;
- установить verified update;
- откатиться к последнему backup.

## Сохраняемые данные

Updater сохраняет:

- `.service/language.txt`;
- `.service/services-state.json`;
- `.service/update-state.json`;
- `.service/ui-settings.json`;
- Strategy Lab и operational history;
- verified caches;
- local backup metadata;
- пользовательские domain/IPSet files;
- user-managed lists и enabled flags.

## Резервные копии

```text
NexRoute-backups/
```

Хранятся последние четыре backup sets. Перед manual rollback создаётся safety copy текущей installation.

## Trust boundary

Checksum подтверждает целостность ZIP относительно checksum asset. Artifact attestation связывает четыре digests с repository workflow и source commit. Validation report показывает автоматические доказательства и ограничения. Эти механизмы не являются Windows Authenticode code signing отдельных binaries.
