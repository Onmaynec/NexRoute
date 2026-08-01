# Проверка происхождения сборки NexRoute 🔏

NexRoute публикует не только SHA-256 итогового ZIP, но и подписанную GitHub artifact attestation для двух release assets:

```text
NexRoute-X.Y.Z-win-x64.zip
NexRoute-X.Y.Z-win-x64.zip.sha256
```

Attestation связывает имя и digest файлов с конкретным запуском release workflow в репозитории `Onmaynec/NexRoute`. Подпись создаётся с краткоживущим сертификатом Sigstore через официальный action `actions/attest@v4`.

## Онлайн-проверка через GitHub CLI

Установите актуальный GitHub CLI и выполните:

```powershell
gh attestation verify .\NexRoute-X.Y.Z-win-x64.zip --repo Onmaynec/NexRoute
```

Успешная проверка подтверждает, что digest загруженного ZIP присутствует в подписанной attestation, созданной workflow этого репозитория.

После этого отдельно проверьте опубликованный checksum:

```powershell
$expected = (Get-Content .\NexRoute-X.Y.Z-win-x64.zip.sha256 -Raw).Split()[0].Trim().ToLowerInvariant()
$actual = (Get-FileHash .\NexRoute-X.Y.Z-win-x64.zip -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actual -ne $expected) { throw 'SHA-256 mismatch.' }
```

## Что именно подтверждается

Attestation подтверждает:

- репозиторий, запустивший сборку;
- workflow и commit, из которого получены assets;
- имена и SHA-256 release-файлов;
- подпись и прозрачность Sigstore.

Внутри самого ZIP дополнительно остаются:

```text
.service/upstream-manifest.json
.service/upstream-lock.json
.service/patch-report.json
NEXROUTE_BUILD_INFO.txt
```

Эти файлы связывают релиз NexRoute с закреплённым архивом Flowseal и перечнем применённых патчей.

## Граница доверия

Artifact attestation не является Windows Authenticode-подписью исполняемых файлов. Она доказывает происхождение опубликованного архива и его digest, но не заменяет будущую кодовую подпись издателя.
