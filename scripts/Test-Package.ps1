[CmdletBinding()]
param(
    [string]$ArtifactsDirectory = (Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts'),
    [string]$ExtractDirectory,
    [switch]$SkipRuntime
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$artifactsPath = [System.IO.Path]::GetFullPath($ArtifactsDirectory)
$zip = Get-ChildItem -LiteralPath $artifactsPath -Filter 'NexRoute-*-win-x64.zip' -File | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
$checksum = if ($zip) { Get-Item -LiteralPath ($zip.FullName + '.sha256') -ErrorAction SilentlyContinue } else { $null }
if (-not $zip -or -not $checksum) { throw 'Build output is incomplete.' }
if ($zip.Length -lt 1MB) { throw 'Release archive is unexpectedly small.' }

$expectedHash = ((Get-Content -LiteralPath $checksum.FullName -Raw) -split '\s+')[0].Trim().ToLowerInvariant()
$actualHash = (Get-FileHash -LiteralPath $zip.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
if ($expectedHash -ne $actualHash) { throw "SHA-256 mismatch: expected $expectedHash, got $actualHash" }

if (-not $ExtractDirectory) { $ExtractDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ("nexroute-package-test-{0}" -f [guid]::NewGuid().ToString('N')) }
$extractPath = [System.IO.Path]::GetFullPath($ExtractDirectory)
if (Test-Path -LiteralPath $extractPath) { Remove-Item -LiteralPath $extractPath -Recurse -Force }
New-Item -ItemType Directory -Path $extractPath -Force | Out-Null
Expand-Archive -LiteralPath $zip.FullName -DestinationPath $extractPath -Force

$required = @(
    'service.bat','nexroute.bat','nexroute-update.cmd','nexroute-tray.cmd','NexRoute.lnk','general.bat','utils/test zapret.ps1','bin/winws.exe',
    'bin/WinDivert.dll','bin/WinDivert64.sys','.service/nexroute.ico',
    '.service/nexroute-ui.ps1','.service/nexroute-services.ps1','.service/services.json',
    '.service/legacy-service.bat','.service/nexroute-console.ps1','.service/nexroute-monitor.ps1','.service/nexroute-tray.ps1','.service/nexroute-worker-host.ps1',
    '.service/next/nexroute-common.ps1','.service/next/nexroute-strategies.ps1','.service/next/nexroute-network.ps1',
    '.service/next/nexroute-diagnostics.ps1','.service/next/nexroute-management.ps1','.service/next/nexroute-update.ps1',
    '.service/next/nexroute-workers.ps1','.service/next/nexroute-media.ps1','.service/next/nexroute-strategy-lab-v2.ps1','.service/next/nexroute-update-transaction.ps1',
    '.service/services-state.json','.service/i18n/ru.json','.service/i18n/en.json',
    '.service/i18n/nexroute-theme.ps1','.service/i18n/nexroute-pages.ps1',
    '.service/i18n/nexroute-services-ui.ps1','.service/language.txt','.service/version.txt',
    'assets/nexroute-mark.svg','docs/SERVICES.md','NEXROUTE_BUILD_INFO.txt'
)
foreach ($relativePath in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $extractPath $relativePath) -PathType Leaf)) { throw "Built package is missing $relativePath" }
}

$nextScripts = @(Get-ChildItem -LiteralPath (Join-Path $extractPath '.service') -Filter '*.ps1' -File -Recurse | Where-Object { $_.FullName -match '[\\/]next[\\/]|nexroute-(console|monitor|tray|worker-host)\.ps1$' })
foreach ($nextScript in $nextScripts) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($nextScript.FullName, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count -gt 0) {
        $details = ($parseErrors | ForEach-Object { "$($_.Extent.StartLineNumber):$($_.Extent.StartColumnNumber) $($_.Message)" }) -join '; '
        throw "NexRoute 0.6.0 script has syntax errors: $($nextScript.Name): $details"
    }
}
$newService = Get-Content -LiteralPath (Join-Path $extractPath 'service.bat') -Raw
if ($newService -notmatch 'nexroute-console\.ps1') { throw 'service.bat does not launch the arrow-key control node.' }
$nextConsole = Get-Content -LiteralPath (Join-Path $extractPath '.service/next/nexroute-common.ps1') -Raw
if ($nextConsole -notmatch [regex]::Escape('>[+]') -or $nextConsole -notmatch "'UpArrow'" -or $nextConsole -notmatch "'DownArrow'") { throw 'Arrow-key [+] menu contract is missing.' }

$transactionPath = Join-Path $extractPath '.service/next/nexroute-update-transaction.ps1'
. $transactionPath
$controlNodeSmoke = Test-NrUpdatedControlNode -Root $extractPath -TimeoutSeconds 30
if (-not [bool]$controlNodeSmoke.passed) {
    throw "Built package control node smoke failed with exit code $($controlNodeSmoke.exitCode): $($controlNodeSmoke.message)"
}

$allBatchFiles = @(Get-ChildItem -LiteralPath $extractPath -Filter '*.bat' -File)
foreach ($batchFile in $allBatchFiles) {
    $batchContent = Get-Content -LiteralPath $batchFile.FullName -Raw
    if ($batchContent -match '-Root\s+"%~dp0"') {
        throw "Published archive contains an unsafe Root argument: $($batchFile.Name)"
    }
}

$servicePath = Join-Path $extractPath '.service/legacy-service.bat'
$service = Get-Content -LiteralPath $servicePath -Raw
if ($service -notmatch 'if "!menu_choice!"=="14" goto nexroute_services_matrix') { throw 'legacy-service.bat is missing option 14.' }
foreach ($token in @('-Mode Menu','-Mode Action','-Mode Status','-Mode StrategyPicker','-Mode PayloadManager','-Mode IpSetSwitch','-Mode SyncIpSet','-Mode SyncHosts','-Mode TestsIntro','-Mode Services')) {
    if ($service -notmatch [regex]::Escape($token)) { throw "legacy-service.bat is missing $token" }
}

$testLabPath = Join-Path $extractPath 'utils/test zapret.ps1'
$testLabBytes = [System.IO.File]::ReadAllBytes($testLabPath)
if ($testLabBytes.Length -lt 3 -or $testLabBytes[0] -ne 0xEF -or $testLabBytes[1] -ne 0xBB -or $testLabBytes[2] -ne 0xBF) {
    throw 'Strategy Lab must be encoded as UTF-8 with BOM for Windows PowerShell 5.1.'
}

$testLabTokens = $null
$testLabParseErrors = $null
[void][System.Management.Automation.Language.Parser]::ParseFile($testLabPath, [ref]$testLabTokens, [ref]$testLabParseErrors)
if ($testLabParseErrors.Count -gt 0) {
    $details = ($testLabParseErrors | ForEach-Object { "$($_.Extent.StartLineNumber):$($_.Extent.StartColumnNumber) $($_.Message)" }) -join '; '
    throw "Strategy Lab has PowerShell syntax errors: $details"
}

if (Get-Command powershell.exe -ErrorAction SilentlyContinue) {
    $escapedTestLabPath = $testLabPath.Replace("'", "''")
    $probe = "`$tokens=`$null; `$errors=`$null; [void][System.Management.Automation.Language.Parser]::ParseFile('$escapedTestLabPath',[ref]`$tokens,[ref]`$errors); if (`$errors.Count -gt 0) { `$errors | ForEach-Object { Write-Error `$_.Message }; exit 1 }"
    & powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command $probe
    if ($LASTEXITCODE -ne 0) { throw 'Strategy Lab does not parse in Windows PowerShell 5.1.' }
}

$uiPath = Join-Path $extractPath '.service/nexroute-ui.ps1'
$themePath = Join-Path $extractPath '.service/i18n/nexroute-theme.ps1'
$theme = Get-Content -LiteralPath $themePath -Raw
if ($theme -notmatch [regex]::Escape('| \ | || ____|\ \/ /|  _ \ / _ \| | | |_   _| ____|')) { throw 'Classic 0.1.1 logo layout is missing.' }

$servicesPath = Join-Path $extractPath '.service/services.json'
$controllerPath = Join-Path $extractPath '.service/nexroute-services.ps1'
$services = @((Get-Content -LiteralPath $servicesPath -Raw -Encoding UTF8 | ConvertFrom-Json).services)
if ($services.Count -ne 15) { throw "Expected 15 services, got $($services.Count)." }
& $controllerPath -Mode Validate -Root $extractPath
& $controllerPath -Mode Apply -Root $extractPath

$strategyFiles = @($allBatchFiles | Where-Object { $_.Name -notin @('service.bat','nexroute.bat') })
if ($strategyFiles.Count -eq 0) { throw 'No strategy files were found.' }
foreach ($strategyFile in $strategyFiles) {
    $content = Get-Content -LiteralPath $strategyFile.FullName -Raw
    if ($content -notmatch 'NEXROUTE_PROFILE_BOOT') { throw "Missing launch hook: $($strategyFile.Name)" }
    if ($content -notmatch 'nexroute-services\.ps1') { throw "Missing service matrix hook: $($strategyFile.Name)" }
}

if (-not $SkipRuntime) {
    $languagePath = Join-Path $extractPath '.service/language.txt'
    Set-Content -LiteralPath $languagePath -Value 'RU' -Encoding ascii

    # Regression guard for already-downloaded 0.2.0 packages: the dispatcher must
    # still recover a command line where the trailing slash swallowed arguments.
    $malformed = $extractPath + '\" -ActionId "deploy" -LanguageFile "' + $languagePath + '"'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $uiPath -Mode Action -Root $malformed -NonInteractive
    if ($LASTEXITCODE -ne 0) { throw 'Renderer failed to recover the malformed Root argument shown in user reports.' }

    foreach ($language in @('RU','EN')) {
        Set-Content -LiteralPath $languagePath -Value $language -Encoding ascii
        $calls = @(
            @('-Mode','Menu','-NonInteractive'),
            @('-Mode','Action','-ActionId','deploy','-NonInteractive'),
            @('-Mode','Launch','-Profile','general (ALT)','-NonInteractive'),
            @('-Mode','Status','-NonInteractive'),
            @('-Mode','StrategyPicker','-NonInteractive'),
            @('-Mode','PayloadManager','-NonInteractive'),
            @('-Mode','Services','-NonInteractive'),
            @('-Mode','TestsIntro','-NonInteractive'),
            @('-Mode','TestHeader','-NonInteractive'),
            @('-Mode','Screen','-ScreenId','diagnostics','-NonInteractive')
        )
        foreach ($arguments in $calls) {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $uiPath -LanguageFile $languagePath @arguments
            if ($LASTEXITCODE -ne 0) { throw "$language renderer failed: $($arguments -join ' ')" }
        }
    }
}

Write-Host "Verified package: $($zip.Name)" -ForegroundColor Green
Write-Host "Control node: service.bat --status passed (exit code $($controlNodeSmoke.exitCode))" -ForegroundColor Green
Write-Host "Strategy Lab: UTF-8 BOM + Windows PowerShell parser verified" -ForegroundColor Green
Write-Host "Strategies: $($strategyFiles.Count)" -ForegroundColor Green
Write-Host "Services: $($services.Count)" -ForegroundColor Green
Write-Host "SHA-256: $actualHash" -ForegroundColor Green

[pscustomobject]@{
    Archive = $zip.FullName
    Checksum = $checksum.FullName
    ExtractPath = $extractPath
    Sha256 = $actualHash
    StrategyCount = $strategyFiles.Count
    ServiceCount = $services.Count
    ControlNodeExitCode = $controlNodeSmoke.exitCode
}
