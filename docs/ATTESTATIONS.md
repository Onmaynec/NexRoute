# Проверка происхождения NexRoute 0.6.0 🔏

NexRoute публикует одну GitHub artifact attestation для четырёх release subjects:

```text
NexRoute-X.Y.Z-win-x64.zip
NexRoute-X.Y.Z-win-x64.zip.sha256
NexRoute-X.Y.Z-validation.json
NexRoute-X.Y.Z-validation.md
```

Attestation связывает имя и digest каждого файла с release workflow, repository и source commit `Onmaynec/NexRoute`. Workflow использует официальный `actions/attest@v4`, а затем проверяет каждый subject до публикации GitHub Release.

## Portable verification

NexRoute package включает возможность проверки без заранее установленного `gh`.

Pinned portable verifier:

- загружает точный GitHub CLI archive;
- проверяет committed SHA-256;
- отклоняет archive path traversal;
- использует integrity-checked cache;
- проверяет repository и signer constraints;
- требует успешную attestation verification всех четырёх subjects.

При offline или tampered fixture verification завершается fail-closed.

## Ручная проверка через GitHub CLI

```powershell
gh attestation verify .\NexRoute-X.Y.Z-win-x64.zip --repo Onmaynec/NexRoute
gh attestation verify .\NexRoute-X.Y.Z-win-x64.zip.sha256 --repo Onmaynec/NexRoute
gh attestation verify .\NexRoute-X.Y.Z-validation.json --repo Onmaynec/NexRoute
gh attestation verify .\NexRoute-X.Y.Z-validation.md --repo Onmaynec/NexRoute
```

После этого отдельно сравните package checksum:

```powershell
$expected = (Get-Content .\NexRoute-X.Y.Z-win-x64.zip.sha256 -Raw).Split()[0].Trim().ToLowerInvariant()
$actual = (Get-FileHash .\NexRoute-X.Y.Z-win-x64.zip -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -ne $expected) { throw 'SHA-256 mismatch.' }
```

## Signed validation report

`validation.json` использует schema version 1 и содержит:

- product и release version;
- overall status;
- repository/workflow/commit provenance;
- runner/OS environment;
- package, upstream и native binary identities;
- required automated checks;
- explicit limitations.

Допустимые check statuses:

```text
passed
experimental
unsupported
failed
```

Failed required check блокирует publication. Experimental и unsupported rows не считаются hardware success.

Перед установкой report verifier проверяет:

- `product == NexRoute`;
- package/report version match;
- supported schema/status values;
- non-empty unique check IDs;
- consistency `overallStatus` с checks;
- отсутствие скрытого failed required check.

## Local attestation receipt

После проверки всех subjects updater атомарно устанавливает:

```text
.service/release-validation.json
.service/release-validation.md
.service/release-validation.json.attestation-receipt.json
```

Receipt содержит:

- schema version;
- `verified=true`;
- report SHA-256;
- verification time;
- verifier identity;
- repository и release version;
- source asset;
- четыре verified subjects.

Validation Viewer сравнивает receipt digest с текущим report.

Trust states:

- `attestation-not-verified` — JSON валиден, но receipt отсутствует;
- `attestation-receipt-matched` — receipt verified и digest совпадает;
- `attestation-receipt-mismatch` — receipt не относится к текущему JSON;
- invalid/missing report states — schema или identity rejected.

Импорт JSON никогда не создаёт trusted state автоматически.

## Package provenance

Внутри ZIP дополнительно находятся:

```text
.service/upstream-manifest.json
.service/upstream-lock.json
.service/patch-report.json
NEXROUTE_BUILD_INFO.txt
```

Эти файлы связывают package с immutable Flowseal archive и 23 tracked patch targets.

## Что подтверждается

Совместно checksum, attestation, validation report и receipt подтверждают:

- digest опубликованных assets;
- repository, workflow и source commit;
- immutable upstream identity;
- package-level automated checks;
- отсутствие failed required release evidence;
- явные hardware/ISP limitations.

## Граница доверия

Artifact attestation не является Windows Authenticode-подписью binaries. Hosted CI также не доказывает visible interactive UI, physical network events или ISP-specific bypass. Эти пункты остаются experimental/unsupported до real-machine validation.
