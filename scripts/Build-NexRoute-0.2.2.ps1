[CmdletBinding()]
param(
    [Parameter()][ValidatePattern('^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$')][string]$Version,
    [Parameter()][string]$UpstreamVersion = '1.10.0',
    [Parameter()][string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
if (-not $Version) { $Version = (Get-Content -LiteralPath (Join-Path $repositoryRoot '.service/version.txt') -Raw).Trim() }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repositoryRoot 'artifacts' }
$outputPath = [System.IO.Path]::GetFullPath($OutputDirectory)
$baseBuilder = Join-Path $PSScriptRoot 'Build-NexRoute.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("nexroute-v022-{0}" -f [guid]::NewGuid().ToString('N'))
$packageRoot = Join-Path $tempRoot 'package'

function Write-Step {
    param([string]$Message)
    Write-Host ("[NexRoute 0.2.2] {0}" -f $Message) -ForegroundColor Cyan
}

function Write-AsciiFile {
    param([string]$Path, [string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.Encoding]::ASCII)
}

function Patch-NexRouteStrategy {
    param([System.IO.FileInfo]$File)

    $lines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in [System.IO.File]::ReadAllLines($File.FullName)) { $lines.Add($line) }
    if ($lines -contains 'rem NEXROUTE_SERVICE_FILTERS_V2') { return }

    $hookIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match 'nexroute-services\.ps1.+-Mode Apply') { $hookIndex = $i; break }
    }
    if ($hookIndex -lt 0) { throw "Strategy has no Service Matrix apply hook: $($File.Name)" }
    $lines.Insert($hookIndex + 1, 'rem NEXROUTE_SERVICE_FILTERS_V2')
    $lines.Insert($hookIndex + 2, 'if exist "%~dp0.service\services-runtime.cmd" call "%~dp0.service\services-runtime.cmd"')

    $startIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '(?i)^\s*start\s+.+winws\.exe') { $startIndex = $i; break }
    }
    if ($startIndex -lt 0) { throw "Strategy has no winws command: $($File.Name)" }

    $endIndex = $startIndex
    while ($endIndex -lt ($lines.Count - 1) -and $lines[$endIndex].TrimEnd().EndsWith('^')) { $endIndex++ }
    $lines[$endIndex] = $lines[$endIndex].TrimEnd() + ' ^'
    $lines.Insert($endIndex + 1, '%NEXROUTE_SERVICE_TCP_ARGS% ^')
    $lines.Insert($endIndex + 2, '%NEXROUTE_SERVICE_UDP_ARGS%')
    [System.IO.File]::WriteAllLines($File.FullName, $lines, [System.Text.Encoding]::ASCII)
}

function Patch-NexRouteServiceBat {
    param([string]$Path)

    $content = [System.IO.File]::ReadAllText($Path)
    $nl = "`r`n"

    if ($content -notmatch 'NEXROUTE_REFRESH_MATRIX_V2') {
        $handler = @'
rem NEXROUTE_REFRESH_MATRIX_V2
if /I "%~1"=="refresh_matrix" (
    setlocal EnableExtensions EnableDelayedExpansion
    set "NEXROUTE_REFRESH_FILE=%~2"
    if not defined NEXROUTE_REFRESH_FILE exit /b 2
    goto service_install
)

'@ -replace "`n", $nl
        $anchor = 'if "%1"=="admin" ('
        if (-not $content.Contains($anchor)) { throw 'Unable to patch refresh_matrix command route.' }
        $content = $content.Replace($anchor, $handler + $anchor)
    }

    $content = $content.Replace('if "!menu_choice!"=="4" (call :nexroute_action game&goto game_switch)', 'if "!menu_choice!"=="4" goto nexroute_game_filter')
    $content = $content.Replace('if "!menu_choice!"=="6" (call :nexroute_action updatecheck&goto check_updates_switch)', 'if "!menu_choice!"=="6" goto nexroute_update_watch')

    if ($content -notmatch ':nexroute_game_filter') {
        $routes = @'
:nexroute_game_filter
if exist "!NEXROUTE_UI!" powershell -NoProfile -ExecutionPolicy Bypass -File "!NEXROUTE_UI!" -Mode GameFilter -LanguageFile "!NEXROUTE_LANGUAGE_FILE!"
goto menu

:nexroute_update_watch
if exist "!NEXROUTE_UI!" powershell -NoProfile -ExecutionPolicy Bypass -File "!NEXROUTE_UI!" -Mode UpdateWatch -LanguageFile "!NEXROUTE_LANGUAGE_FILE!"
goto menu

'@ -replace "`n", $nl
        $anchor = ':nexroute_services_matrix'
        if (-not $content.Contains($anchor)) { throw 'Unable to add styled Game Filter and Update Watch routes.' }
        $content = $content.Replace($anchor, $routes + $anchor)
    }

    if ($content -notmatch 'NEXROUTE_REFRESH_INSTALL_V2') {
        $refreshInstall = @'
rem NEXROUTE_REFRESH_INSTALL_V2
if exist "%~dp0.service\nexroute-services.ps1" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0.service\nexroute-services.ps1" -Mode Apply -Root "%~dp0" >nul 2>&1
if exist "%~dp0.service\services-runtime.cmd" call "%~dp0.service\services-runtime.cmd"
if defined NEXROUTE_REFRESH_FILE (
    set "selectedFile=!NEXROUTE_REFRESH_FILE!"
    if not exist "!selectedFile!" set "selectedFile=%~dp0!NEXROUTE_REFRESH_FILE!"
    if not exist "!selectedFile!" exit /b 3
    set "choice=1"
    set "file1=!selectedFile!"
    goto nexroute_refresh_parse
)

'@ -replace "`n", $nl
        $anchor = ':: Searching for strategy launchers through NexRoute selector'
        if (-not $content.Contains($anchor)) { throw 'Unable to patch non-interactive strategy reinstall.' }
        $content = $content.Replace($anchor, $refreshInstall + $anchor)
        $content = $content.Replace(':: Args that should be followed by value', ':nexroute_refresh_parse' + $nl + ':: Args that should be followed by value')
    }

    $expandLine = 'call set "ARGS=%%ARGS:EXCL_MARK=^!%%"'
    if ($content.Contains($expandLine) -and $content -notmatch 'NEXROUTE_EXPAND_RUNTIME_ARGS') {
        $content = $content.Replace($expandLine, $expandLine + $nl + 'rem NEXROUTE_EXPAND_RUNTIME_ARGS' + $nl + 'call set "ARGS=%%ARGS%%"')
    }

    $registryLine = 'reg add "HKLM\System\CurrentControlSet\Services\zapret" /v zapret-discord-youtube /t REG_SZ /d "!filename!" /f'
    if ($content.Contains($registryLine) -and $content -notmatch 'if defined NEXROUTE_REFRESH_FILE exit /b 0') {
        $content = $content.Replace($registryLine, $registryLine + $nl + 'if defined NEXROUTE_REFRESH_FILE exit /b 0')
    }

    Write-AsciiFile -Path $Path -Content $content
}

function Patch-NexRouteTestLab {
    param([string]$Path)

    $content = [System.IO.File]::ReadAllText($Path)
    if ($content -match 'NEXROUTE_DYNAMIC_TARGETS_V2') { return }
    $nl = "`r`n"
    $languageBootstrap = @'
# NEXROUTE_TEST_LANGUAGE_V2
$nrLanguagePath = Join-Path (Split-Path $PSScriptRoot) '.service\language.txt'
$nrLanguage = 'EN'
if (Test-Path -LiteralPath $nrLanguagePath -PathType Leaf) {
    try { $nrLanguage = (Get-Content -LiteralPath $nrLanguagePath -Raw -Encoding ASCII).Trim().ToUpperInvariant() } catch { }
}

'@ -replace "`n", $nl
    if ($content.Contains('# NEXROUTE_TEST_HEADER')) {
        $content = $content.Replace('# NEXROUTE_TEST_HEADER', '# NEXROUTE_TEST_HEADER' + $nl + $languageBootstrap)
    }
    else {
        $content = $languageBootstrap + $content
    }

    # Upstream counted nexroute.bat as a 22nd configuration even though it is only
    # a launcher. Strategy Lab must test the 21 actual Flowseal strategy BAT files.
    $content = $content.Replace(
        'Where-Object { $_.Name -notlike "service*" }',
        'Where-Object { $_.Name -notlike "service*" -and $_.Name -ne "nexroute.bat" }'
    )

    $block = @'
    # NEXROUTE_DYNAMIC_TARGETS_V2
    $nrServiceRoot = Split-Path $PSScriptRoot
    $nrController = Join-Path $nrServiceRoot '.service\nexroute-services.ps1'
    if (Test-Path -LiteralPath $nrController -PathType Leaf) {
        try {
            $nrJson = & $nrController -Mode TestTargets -Root $nrServiceRoot | Select-Object -Last 1
            $nrTargets = if ($nrJson) { @($nrJson | ConvertFrom-Json) } else { @() }
            foreach ($nrTarget in $nrTargets) {
                $nrName = if ($nrLanguage -eq 'RU') { [string]$nrTarget.NameRu } else { [string]$nrTarget.NameEn }
                if (-not [string]::IsNullOrWhiteSpace($nrName) -and -not [string]::IsNullOrWhiteSpace([string]$nrTarget.Value)) {
                    Add-OrSet -dict $rawTargets -key $nrName -val ([string]$nrTarget.Value)
                }
            }
            Write-Host $(if ($nrLanguage -eq 'RU') { "[INFO] Добавлено целей из матрицы сервисов: $($nrTargets.Count)" } else { "[INFO] Service Matrix targets added: $($nrTargets.Count)" }) -ForegroundColor Cyan
        }
        catch {
            Write-Host $(if ($nrLanguage -eq 'RU') { "[WARN] Не удалось загрузить цели матрицы сервисов." } else { "[WARN] Unable to load Service Matrix targets." }) -ForegroundColor Yellow
        }
    }

'@ -replace "`n", $nl
    $anchor = '    foreach ($key in $rawTargets.Keys) {'
    if (-not $content.Contains($anchor)) { throw 'Unable to inject Service Matrix targets into Strategy Lab.' }
    $content = $content.Replace($anchor, $block + $anchor)

    $content = $content.Replace('Write-Host "Select test type:" -ForegroundColor Cyan', 'Write-Host $(if ($nrLanguage -eq ''RU'') { ''Выберите тип проверки:'' } else { ''Select test type:'' }) -ForegroundColor Cyan')
    $content = $content.Replace('Write-Host "  [1] Standard tests (HTTP/ping)" -ForegroundColor Gray', 'Write-Host $(if ($nrLanguage -eq ''RU'') { ''  [1] Стандартная проверка (HTTP/ping)'' } else { ''  [1] Standard tests (HTTP/ping)'' }) -ForegroundColor Gray')
    $content = $content.Replace('Write-Host "  [2] DPI checkers (TCP 16-20 freeze)" -ForegroundColor Gray', 'Write-Host $(if ($nrLanguage -eq ''RU'') { ''  [2] DPI-проверка (зависание TCP 16-20 КБ)'' } else { ''  [2] DPI checkers (TCP 16-20 freeze)'' }) -ForegroundColor Gray')
    $content = $content.Replace('$choice = Read-Host "Enter 1 or 2"', '$choice = Read-Host $(if ($nrLanguage -eq ''RU'') { ''Введите 1 или 2'' } else { ''Enter 1 or 2'' })')
    $content = $content.Replace('Write-Host "Select test run mode:" -ForegroundColor Cyan', 'Write-Host $(if ($nrLanguage -eq ''RU'') { ''Выберите режим запуска:'' } else { ''Select test run mode:'' }) -ForegroundColor Cyan')
    $content = $content.Replace('Write-Host "  [1] All configs" -ForegroundColor Gray', 'Write-Host $(if ($nrLanguage -eq ''RU'') { ''  [1] Все конфигурации'' } else { ''  [1] All configs'' }) -ForegroundColor Gray')
    $content = $content.Replace('Write-Host "  [2] Selected configs" -ForegroundColor Gray', 'Write-Host $(if ($nrLanguage -eq ''RU'') { ''  [2] Выбранные конфигурации'' } else { ''  [2] Selected configs'' }) -ForegroundColor Gray')
    $content = $content.Replace('Write-Host "Available configs:" -ForegroundColor Cyan', 'Write-Host $(if ($nrLanguage -eq ''RU'') { ''Доступные конфигурации:'' } else { ''Available configs:'' }) -ForegroundColor Cyan')
    $content = $content.Replace('Write-Host "All tests finished." -ForegroundColor Green', 'Write-Host $(if ($nrLanguage -eq ''RU'') { ''Все проверки завершены.'' } else { ''All tests finished.'' }) -ForegroundColor Green')
    $content = $content.Replace('Write-Host "=== ANALYTICS ===" -ForegroundColor Cyan', 'Write-Host $(if ($nrLanguage -eq ''RU'') { ''=== ИТОГОВАЯ АНАЛИТИКА ==='' } else { ''=== ANALYTICS ==='' }) -ForegroundColor Cyan')
    [System.IO.File]::WriteAllText($Path, $content, (New-Object System.Text.UTF8Encoding($false)))
}

try {
    if (-not (Test-Path -LiteralPath $baseBuilder -PathType Leaf)) { throw "Base builder not found: $baseBuilder" }
    New-Item -ItemType Directory -Path $outputPath, $packageRoot -Force | Out-Null

    Write-Step 'Building Flowseal 1.10.0 baseline with NexRoute overlay'
    & $baseBuilder -Version $Version -UpstreamVersion $UpstreamVersion -OutputDirectory $outputPath

    $zipPath = Join-Path $outputPath ("NexRoute-{0}-win-x64.zip" -f $Version)
    $checksumPath = $zipPath + '.sha256'
    if (-not (Test-Path -LiteralPath $zipPath -PathType Leaf)) { throw "Base package was not created: $zipPath" }

    Write-Step 'Expanding package for 0.2.2 network integration'
    Expand-Archive -LiteralPath $zipPath -DestinationPath $packageRoot -Force

    $serviceDirectory = Join-Path $packageRoot '.service'
    $coreController = Join-Path $serviceDirectory 'nexroute-services-core.ps1'
    $controller = Join-Path $serviceDirectory 'nexroute-services.ps1'
    Copy-Item -LiteralPath $controller -Destination $coreController -Force
    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'overlay/.service/nexroute-services-entry.ps1') -Destination $controller -Force
    Set-Content -LiteralPath (Join-Path $serviceDirectory 'language.txt') -Value 'EN' -Encoding ASCII

    Write-Step 'Applying full Service Matrix runtime'
    & $controller -Mode Apply -Root $packageRoot | Out-Null

    $strategyFiles = @(Get-ChildItem -LiteralPath $packageRoot -Filter '*.bat' -File | Where-Object { $_.Name -notin @('service.bat', 'nexroute.bat') })
    if ($strategyFiles.Count -ne 21) { throw "Expected 21 real strategy BAT files, got $($strategyFiles.Count)." }
    foreach ($strategyFile in $strategyFiles) { Patch-NexRouteStrategy -File $strategyFile }

    Write-Step 'Patching service reinstall, styled settings and Strategy Lab targets'
    Patch-NexRouteServiceBat -Path (Join-Path $packageRoot 'service.bat')
    Patch-NexRouteTestLab -Path (Join-Path $packageRoot 'utils\test zapret.ps1')

    Write-Step 'Regenerating multi-resolution NexRoute icon and shortcut'
    & (Join-Path $serviceDirectory 'New-NexRouteIcon.ps1') -Root $packageRoot | Out-Null

    $buildInfoPath = Join-Path $packageRoot 'NEXROUTE_BUILD_INFO.txt'
    Add-Content -LiteralPath $buildInfoPath -Value @(
        'Service Matrix schema: 2',
        'Strategy integration: 21/21 real Flowseal BAT profiles',
        'Strategy Lab launcher exclusion: nexroute.bat',
        'Dynamic filters: domain + resolved IPv4/IP source + TCP/UDP ports',
        'Strategy Lab: enabled-service web/API/CDN/media/gateway targets',
        'Default language: EN',
        'Icon: NexRoute supplied artwork motif, multi-resolution ICO'
    ) -Encoding UTF8

    Write-Step 'Repacking verified 0.2.2 artifact'
    Remove-Item -LiteralPath $zipPath -Force
    if (Test-Path -LiteralPath $checksumPath) { Remove-Item -LiteralPath $checksumPath -Force }
    Compress-Archive -Path (Join-Path $packageRoot '*') -DestinationPath $zipPath -CompressionLevel Optimal
    $hash = Get-FileHash -LiteralPath $zipPath -Algorithm SHA256
    Set-Content -LiteralPath $checksumPath -Value ("{0}  {1}" -f $hash.Hash.ToLowerInvariant(), (Split-Path $zipPath -Leaf)) -Encoding ASCII

    Write-Step ("Created {0}" -f $zipPath)
    Write-Step ("SHA-256 {0}" -f $hash.Hash)
}
finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
