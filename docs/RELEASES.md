# Сборка и публикация NexRoute 0.6.0 📦

## Политика

Исполняемые компоненты публикуются только через GitHub Releases. В Git запрещены generated `.exe`, `.dll`, `.sys`, `.bin`, `.ico`, `.lnk` и архивы.

Release собирается заново из `main` и считается готовым только после прохождения automated acceptance gate. Hardware- и ISP-dependent возможности не превращаются в `passed` без реального evidence: они остаются `experimental` или `unsupported` в signed validation report.

Критерии версии: [RELEASE_0.6.0_ACCEPTANCE.md](RELEASE_0.6.0_ACCEPTANCE.md).

## Каноническая версия

Единственный package version source:

```text
.service/version.txt
```

Для 0.6.0 это значение обязано совпадать с:

- `website/package.json`;
- README и CHANGELOG;
- release notes `v0.6.0.md`;
- smoke artifact names;
- package `.service/version.txt`;
- validation report `version`.

`Test-Repository.ps1` блокирует рассинхронизацию.

## Подготовка окружения

```powershell
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module Pester -RequiredVersion 5.6.1 -Scope CurrentUser -Force

pwsh ./scripts/Test-Repository.ps1
Invoke-Pester -Path ./tests -CI -Output Detailed
```

## Immutable upstream

`.service/upstream-manifest.json` фиксирует:

- `Flowseal/zapret-discord-youtube`;
- tag `1.10.0`;
- единственный допустимый archive asset;
- committed SHA-256;
- минимальный размер;
- required paths.

Release builder использует предварительно проверенный локальный archive. Имя файла без совпадающего digest и структуры недостаточно.

## Online build через verified cache

```powershell
pwsh ./scripts/Build-Release.ps1 `
  -Version 0.6.0 `
  -OutputDirectory ./artifacts `
  -UpstreamCachePath ./cache/zapret-discord-youtube-1.10.0.zip

pwsh ./scripts/Test-Release.ps1 `
  -ArtifactsDirectory ./artifacts `
  -ExtractDirectory ./artifacts-test

pwsh ./scripts/Test-V06Desktop.ps1 `
  -ExtractDirectory ./artifacts-test
```

Package build компилирует системным .NET Framework compiler:

```text
.service/native/NexRoute.Tray.exe
.service/native/NexRoute.Notifier.exe
.service/native/NexRoute.Dashboard.exe
.service/native/NexRoute.Validation.exe
```

Компиляция не использует NuGet, `dotnet restore` или build-time rewrite Dashboard source.

## Полностью offline rebuild

```powershell
pwsh ./scripts/Build-Release.ps1 `
  -Version 0.6.0 `
  -OutputDirectory ./artifacts-offline `
  -UpstreamArchive ./cache/zapret-discord-youtube-1.10.0.zip

pwsh ./scripts/Test-Release.ps1 `
  -ArtifactsDirectory ./artifacts-offline `
  -ExtractDirectory ./artifacts-offline-test `
  -SkipRuntime

pwsh ./scripts/Test-V06Desktop.ps1 `
  -ExtractDirectory ./artifacts-offline-test
```

Offline rebuild выполняет те же package, native desktop, notification и Validation Viewer fixtures. Online/offline upstream digest, patch target count, strategy count и service count обязаны совпадать.

## Patch provenance

Release ZIP содержит:

```text
.service/upstream-manifest.json
.service/upstream-lock.json
.service/patch-report.json
NEXROUTE_BUILD_INFO.txt
```

Patch report содержит ровно 23 target-а:

- 21 реальную Flowseal strategy;
- `service.bat`;
- `utils/test zapret.ps1`.

Для каждой записи обязательны unique ID, relative target, operation count и разные before/after SHA-256.

## Package-level acceptance

`Test-Release.ps1` и `Test-V06Desktop.ps1` проверяют:

- package version и archive name;
- checksum и upstream lock;
- 23 tracked patch targets, 21 strategy и 15 service profiles;
- Windows PowerShell 5.1 parsing и Strategy Lab BOM;
- native assembly names, hashes и deterministic self-tests;
- Dashboard reading Strategy Lab history fixture;
- Validation Viewer schema/product/version/status checks;
- trust transition `attestation-not-verified -> attestation-receipt-matched`;
- notification delivery contract `windows-toast -> native-balloon`;
- отсутствие temporary history files;
- required launchers и portable verifier.

## Signed validation report

После package verification workflow создаёт:

```text
NexRoute-0.6.0-validation.json
NexRoute-0.6.0-validation.md
```

JSON schema v1 содержит:

- repository/workflow/commit provenance;
- Windows runner environment;
- release identities и native binary hashes;
- required automated checks;
- explicit `passed`, `experimental`, `unsupported` или `failed` status;
- limitations без ложного hardware success.

Failed required check блокирует publication.

## Release assets

Финальный Release содержит четыре связанных файла:

```text
NexRoute-0.6.0-win-x64.zip
NexRoute-0.6.0-win-x64.zip.sha256
NexRoute-0.6.0-validation.json
NexRoute-0.6.0-validation.md
```

Все четыре subjects входят в одну GitHub artifact attestation. Workflow проверяет каждую attestation до `gh release create`.

## GitHub Actions gate

Pull request workflow выполняет:

1. repository contract и PowerShell AST parsing;
2. полный Pester behavioral suite;
3. website typecheck и production/static build;
4. Windows online package build;
5. online package и desktop verification;
6. полностью offline rebuild;
7. offline package и desktop verification;
8. upload smoke archive и diagnostics logs.

Release workflow из `main` дополнительно:

1. повторяет source, behavior, package и offline gates;
2. генерирует signed validation JSON/Markdown;
3. attests ZIP, checksum и оба reports;
4. проверяет четыре attestations;
5. публикует Release;
6. закрывает superseded tracking items только после успешного publication.

## Публичный Release

1. обновить `.service/version.txt`, website package, README и CHANGELOG;
2. добавить `.github/release-notes/vX.Y.Z.md`;
3. обновить acceptance contract;
4. убедиться, что PR CI полностью зелёный;
5. проверить explicit hardware/ISP limitations;
6. слить PR в `main`;
7. release workflow создаст tag, assets, validation reports и attestations.

Не создавайте tag вручную: release workflow является владельцем автоматической публикации.

## Release checklist ✅

- [ ] repository version равен 0.6.0 во всех canonical surfaces
- [ ] PowerShell AST parsing проходит
- [ ] все Pester acceptance tests проходят
- [ ] website typecheck и build проходят
- [ ] upstream manifest содержит committed SHA-256
- [ ] online/offline upstream SHA совпадает
- [ ] patch report содержит 23 unique targets
- [ ] 21 strategy и 15 service profiles валидны
- [ ] native tray/notifier/dashboard/viewer скомпилированы
- [ ] online/offline desktop self-tests проходят
- [ ] notification channels подтверждены
- [ ] validation trust states подтверждены
- [ ] signed report не содержит failed required checks
- [ ] четыре assets attested и verified
- [ ] release notes и limitations актуальны
- [ ] THIRD_PARTY_NOTICES присутствует

## Откат Release 🔙

Не заменяйте содержимое опубликованного asset без новой версии. При критической ошибке создайте patch release. Не обновляйте upstream lock автоматически: сначала проверьте причину изменения digest и содержимое archive.
