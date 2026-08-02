from pathlib import Path
from textwrap import dedent


def read(path: str) -> str:
    return Path(path).read_text(encoding="utf-8-sig")


def write(path: str, text: str) -> None:
    Path(path).write_text(text, encoding="utf-8", newline="\n")


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    count = text.count(old)
    if count != 1:
        raise RuntimeError(f"{path}: expected one match, got {count} for {old[:100]!r}")
    write(path, text.replace(old, new, 1))


# Parser fix found by the first materializer run.
replace_once(
    "overlay/.service/next/nexroute-network.ps1",
    "@('Network',Get-NrActiveNetworkKey)",
    "@('Network',(Get-NrActiveNetworkKey))",
)

Path(".service/version.txt").write_text("0.5.0\n", encoding="ascii")
replace_once("website/package.json", '  "version": "0.4.1",', '  "version": "0.5.0",')

for path in (".github/workflows/validate.yml", "scripts/Test-Repository.ps1"):
    write(path, read(path).replace("0.4.1", "0.5.0"))

repo_test = read("scripts/Test-Repository.ps1")
repo_test = repo_test.replace(
    "'tests/ServiceMatrix.Tests.ps1','tests/UpstreamContract.Tests.ps1','tests/Updater.Tests.ps1','tests/ReleaseAttestation.Tests.ps1',",
    "'tests/ServiceMatrix.Tests.ps1','tests/UpstreamContract.Tests.ps1','tests/Updater.Tests.ps1','tests/ReleaseAttestation.Tests.ps1','tests/NextInterface.Tests.ps1',",
)
repo_test = repo_test.replace(
    "'overlay/.service/nexroute-services-entry.ps1','overlay/.service/services.json',",
    "'overlay/.service/nexroute-services-entry.ps1','overlay/.service/services.json',\n"
    "    'overlay/service.bat','overlay/nexroute-update.cmd','overlay/nexroute-tray.cmd',\n"
    "    'overlay/.service/nexroute-console.ps1','overlay/.service/nexroute-monitor.ps1','overlay/.service/nexroute-tray.ps1',\n"
    "    'overlay/.service/next/nexroute-common.ps1','overlay/.service/next/nexroute-strategies.ps1','overlay/.service/next/nexroute-network.ps1',\n"
    "    'overlay/.service/next/nexroute-diagnostics.ps1','overlay/.service/next/nexroute-management.ps1','overlay/.service/next/nexroute-update.ps1',",
)
marker = "$serviceMatrixTests = Get-Content -LiteralPath (Join-Path $root 'tests/ServiceMatrix.Tests.ps1') -Raw\n"
guard = dedent("""\
$nextInterface = Get-Content -LiteralPath (Join-Path $root 'overlay/.service/nexroute-console.ps1') -Raw
$nextCommon = Get-Content -LiteralPath (Join-Path $root 'overlay/.service/next/nexroute-common.ps1') -Raw
$serviceNetwork = Get-Content -LiteralPath (Join-Path $root 'overlay/.service/i18n/nexroute-services-network.ps1') -Raw
foreach ($token in @('>[+]','UpArrow','DownArrow','Installing Config','Check Update','Confirm-NrY','Invoke-NrStrategyLab','ConvertTo-ValidatedIpCidr')) {
    Assert-True (($nextInterface + $nextCommon + $serviceNetwork + $buildWrapper) -match [regex]::Escape($token)) "NexRoute 0.5.0 control suite contains $token"
}

$serviceMatrixTests = Get-Content -LiteralPath (Join-Path $root 'tests/ServiceMatrix.Tests.ps1') -Raw
""")
if marker not in repo_test:
    raise RuntimeError("Test-Repository insertion anchor not found")
repo_test = repo_test.replace(marker, guard, 1)
write("scripts/Test-Repository.ps1", repo_test)

package_test = read("scripts/Test-Package.ps1")
package_test = package_test.replace(
    "'service.bat','nexroute.bat','NexRoute.lnk','general.bat','utils/test zapret.ps1','bin/winws.exe',",
    "'service.bat','nexroute.bat','nexroute-update.cmd','nexroute-tray.cmd','NexRoute.lnk','general.bat','utils/test zapret.ps1','bin/winws.exe',",
)
package_test = package_test.replace(
    "'.service/nexroute-ui.ps1','.service/nexroute-services.ps1','.service/services.json',",
    "'.service/nexroute-ui.ps1','.service/nexroute-services.ps1','.service/services.json',\n"
    "    '.service/legacy-service.bat','.service/nexroute-console.ps1','.service/nexroute-monitor.ps1','.service/nexroute-tray.ps1',\n"
    "    '.service/next/nexroute-common.ps1','.service/next/nexroute-strategies.ps1','.service/next/nexroute-network.ps1',\n"
    "    '.service/next/nexroute-diagnostics.ps1','.service/next/nexroute-management.ps1','.service/next/nexroute-update.ps1',",
)
anchor = "$allBatchFiles = @(Get-ChildItem -LiteralPath $extractPath -Filter '*.bat' -File)\n"
checks = dedent(r"""\
$nextScripts = @(Get-ChildItem -LiteralPath (Join-Path $extractPath '.service') -Filter '*.ps1' -File -Recurse | Where-Object { $_.FullName -match '[\\/]next[\\/]|nexroute-(console|monitor|tray)\.ps1$' })
foreach ($nextScript in $nextScripts) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($nextScript.FullName, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        $details = ($parseErrors | ForEach-Object { "$($_.Extent.StartLineNumber):$($_.Extent.StartColumnNumber) $($_.Message)" }) -join '; '
        throw "NexRoute 0.5.0 script has syntax errors: $($nextScript.Name): $details"
    }
}
$newService = Get-Content -LiteralPath (Join-Path $extractPath 'service.bat') -Raw
if ($newService -notmatch 'nexroute-console\.ps1') { throw 'service.bat does not launch the arrow-key control node.' }
$nextConsole = Get-Content -LiteralPath (Join-Path $extractPath '.service/next/nexroute-common.ps1') -Raw
if ($nextConsole -notmatch [regex]::Escape('>[+]') -or $nextConsole -notmatch "'UpArrow'" -or $nextConsole -notmatch "'DownArrow'") { throw 'Arrow-key [+] menu contract is missing.' }

$allBatchFiles = @(Get-ChildItem -LiteralPath $extractPath -Filter '*.bat' -File)
""")
if anchor not in package_test:
    raise RuntimeError("Test-Package insertion anchor not found")
package_test = package_test.replace(anchor, checks, 1)
write("scripts/Test-Package.ps1", package_test)

readme = read("README.md")
readme = readme.replace("version-0.4.1-24e1d6", "version-0.5.0-24e1d6", 1)
new_section = dedent("""\
## Что изменилось в 0.5.0 🧭

Версия `0.5.0` переводит NexRoute на управление стрелками без цифрового ввода и добавляет крупный набор средств автоматизации, мониторинга и диагностики.

- основное меню использует `>[+]`, стрелки, Enter и Escape;
- `[+] Check Update` после подтверждения `Y` загружает, проверяет и устанавливает стабильный релиз, выполняет post-update проверки и запускает новую версию;
- Strategy Lab сохраняет историю, измеряет latency, jitter, packet loss и download rate, оценивает YouTube/Discord/Telegram и рекомендует лучшую стратегию;
- доступны автоматический failover, стратегии по отдельным сервисам, мониторинг, трей и уведомления;
- добавлены DNS diagnostics, plain DNS/DoH/DoT, сетевые профили, backup manager, export/import, custom profiles/strategies, logs и diagnostic ZIP;
- Service Matrix принимает IPv4 и IPv6 CIDR, резолвит A/AAAA и проверяет IPv6 readiness;
- beginner/advanced modes, светлая/тёмная темы, accent colors, hotkeys, local statistics и JSON/CSV export.

Подробная архитектура: [docs/NEXT_CONTROL.md](docs/NEXT_CONTROL.md).

""")
readme = readme.replace("## Что изменилось в 0.4.1 🧪", new_section + "## Что изменилось в 0.4.1 🧪", 1)
readme = readme.replace("NexRoute-0.4.1-win-x64.zip", "NexRoute-0.5.0-win-x64.zip")
readme = readme.replace("-Version 0.4.1", "-Version 0.5.0")
readme = readme.replace("**NexRoute 0.4.1**", "**NexRoute 0.5.0**")
write("README.md", readme)

changelog = read("CHANGELOG.md")
entry = dedent("""\
## [0.5.0] - 2026-08-02

### Added

- arrow-key `>[+]` control node without numeric menu input;
- confirmed one-action stable update installation and automatic restart;
- Strategy Lab scoring, sorting, history, comparison, recommendations and automatic failover;
- per-service strategies, tray controls, notifications and continuous availability monitoring;
- DNS/DoH/DoT management, network profiles, conflict checks, service repair and reset tools;
- backup selection, configuration export/import, custom profiles/strategies, logs, diagnostics and statistics;
- IPv6 CIDR, A/AAAA resolution and IPv6 readiness support.

### Changed

- English and Russian interface labels were fully renamed;
- automatic background checks never install without explicit `Y` confirmation.

""")
changelog = changelog.replace("Пока нет изменений.\n\n## [0.4.1]", "Пока нет изменений.\n\n" + entry + "## [0.4.1]", 1)
write("CHANGELOG.md", changelog)

en = read("docs/README_EN.md")
en = en.replace("version-0.4.1-24e1d6", "version-0.5.0-24e1d6", 1)
section = dedent("""\
## Version 0.5.0 — arrow-key control and automation suite

Version 0.5.0 replaces numeric menu input with a `>[+]` arrow-key interface and adds confirmed one-action updates, strategy scoring/failover, per-service strategies, monitoring, tray controls, DNS encryption modes, backup/configuration managers, diagnostics, statistics, and IPv6 support.

See [NEXT_CONTROL.md](NEXT_CONTROL.md).

""")
en = en.replace("## Version 0.4.1 — Strategy Lab compatibility fix", section + "## Version 0.4.1 — Strategy Lab compatibility fix", 1)
en = en.replace("NexRoute-0.4.1-win-x64.zip", "NexRoute-0.5.0-win-x64.zip")
write("docs/README_EN.md", en)
