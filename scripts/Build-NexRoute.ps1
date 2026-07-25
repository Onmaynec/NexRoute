[CmdletBinding()]
param(
    [Parameter()]
    [ValidatePattern('^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$')]
    [string]$Version,

    [Parameter()]
    [ValidatePattern('^\d+\.\d+\.\d+[A-Za-z0-9.-]*$')]
    [string]$UpstreamVersion = '1.10.0',

    [Parameter()]
    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$repositoryRoot = Split-Path -Parent $PSScriptRoot

if (-not $Version) {
    $Version = (Get-Content -LiteralPath (Join-Path $repositoryRoot '.service/version.txt') -Raw).Trim()
}

if (-not $OutputDirectory) {
    $OutputDirectory = Join-Path $repositoryRoot 'artifacts'
}

$outputPath = [System.IO.Path]::GetFullPath($OutputDirectory)
$tempPath = Join-Path ([System.IO.Path]::GetTempPath()) ("nexroute-build-{0}" -f ([guid]::NewGuid().ToString('N')))
$downloadPath = Join-Path $tempPath 'upstream.zip'
$extractPath = Join-Path $tempPath 'upstream'
$distributionPath = Join-Path $tempPath ("NexRoute-{0}-win-x64" -f $Version)

$headers = @{
    'Accept'               = 'application/vnd.github+json'
    'User-Agent'           = 'NexRoute-Release-Builder'
    'X-GitHub-Api-Version' = '2022-11-28'
}

function Write-Step {
    param([Parameter(Mandatory)][string]$Message)
    Write-Host ("[NexRoute] {0}" -f $Message) -ForegroundColor Cyan
}

function Copy-RequiredFile {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) {
        throw "Required source file not found: $Source"
    }

    $destinationDirectory = Split-Path -Parent $Destination
    if ($destinationDirectory) {
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
    }

    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

try {
    New-Item -ItemType Directory -Path $tempPath, $extractPath, $outputPath -Force | Out-Null

    Write-Step "Resolving Flowseal release $UpstreamVersion"
    $releaseUrl = "https://api.github.com/repos/Flowseal/zapret-discord-youtube/releases/tags/$UpstreamVersion"
    $release = Invoke-RestMethod -Uri $releaseUrl -Headers $headers -Method Get

    $zipAssets = @(
        $release.assets |
            Where-Object {
                $_.name -match '^zapret-discord-youtube.*\.zip$' -and
                $_.browser_download_url
            } |
            Sort-Object -Property size -Descending
    )

    if ($zipAssets.Count -eq 0) {
        throw "The Flowseal release $UpstreamVersion has no binary ZIP asset matching zapret-discord-youtube*.zip."
    }

    $asset = $zipAssets[0]
    Write-Step ("Downloading official asset: {0}" -f $asset.name)
    Invoke-WebRequest -Uri $asset.browser_download_url -Headers $headers -OutFile $downloadPath -UseBasicParsing

    if ((Get-Item -LiteralPath $downloadPath).Length -lt 1024) {
        throw 'Downloaded upstream archive is unexpectedly small.'
    }

    Write-Step 'Extracting upstream archive'
    Expand-Archive -LiteralPath $downloadPath -DestinationPath $extractPath -Force

    $serviceFile = Get-ChildItem -LiteralPath $extractPath -Filter 'service.bat' -File -Recurse |
        Where-Object {
            Test-Path -LiteralPath (Join-Path $_.Directory.FullName 'general.bat')
        } |
        Select-Object -First 1

    if (-not $serviceFile) {
        throw 'Unable to locate the Flowseal distribution root (service.bat + general.bat).'
    }

    $upstreamRoot = $serviceFile.Directory.FullName
    $requiredUpstreamFiles = @(
        'service.bat',
        'general.bat',
        'bin/winws.exe',
        'bin/WinDivert.dll',
        'bin/WinDivert64.sys',
        'lists/list-general.txt',
        'lists/list-google.txt'
    )

    foreach ($relativePath in $requiredUpstreamFiles) {
        if (-not (Test-Path -LiteralPath (Join-Path $upstreamRoot $relativePath))) {
            throw "The upstream archive is incomplete. Missing: $relativePath"
        }
    }

    Write-Step 'Copying Flowseal functional baseline'
    Copy-Item -LiteralPath $upstreamRoot -Destination $distributionPath -Recurse -Force

    $licensesPath = Join-Path $distributionPath 'licenses'
    New-Item -ItemType Directory -Path $licensesPath -Force | Out-Null

    $upstreamLicense = Join-Path $distributionPath 'LICENSE.txt'
    if (Test-Path -LiteralPath $upstreamLicense) {
        Move-Item -LiteralPath $upstreamLicense -Destination (Join-Path $licensesPath 'FLOWSEAL-MIT.txt') -Force
    }

    Write-Step 'Applying NexRoute branding and bilingual service menu'
    $servicePath = Join-Path $distributionPath 'service.bat'
    $serviceContent = [System.IO.File]::ReadAllText($servicePath)

    $serviceContent = [regex]::Replace(
        $serviceContent,
        'set "LOCAL_VERSION=[^"]+"',
        ('set "LOCAL_VERSION={0}"' -f $Version),
        1
    )

    $serviceContent = $serviceContent.Replace(
        'https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/main/.service/version.txt',
        'https://raw.githubusercontent.com/Onmaynec/NexRoute/main/.service/version.txt'
    )
    $serviceContent = $serviceContent.Replace(
        'https://github.com/Flowseal/zapret-discord-youtube/releases/tag/',
        'https://github.com/Onmaynec/NexRoute/releases/tag/'
    )
    $serviceContent = $serviceContent.Replace(
        'https://github.com/Flowseal/zapret-discord-youtube/releases/latest',
        'https://github.com/Onmaynec/NexRoute/releases/latest'
    )
    $serviceContent = $serviceContent.Replace(
        'sc description %SRVCNAME% "Zapret DPI bypass software"',
        'sc description %SRVCNAME% "NexRoute DPI strategy service"'
    )

    $menuPattern = '(?s):: MENU =+.*?:: LOAD USER LISTS =+'
    if (-not [regex]::IsMatch($serviceContent, $menuPattern)) {
        throw 'Unable to locate the upstream service menu block. The pinned upstream format may have changed.'
    }

    $menuBlock = @'
:: MENU ================================
setlocal EnableDelayedExpansion
set "NEXROUTE_LANGUAGE_FILE=%~dp0.service\language.txt"
set "NEXROUTE_LANG=RU"
if exist "!NEXROUTE_LANGUAGE_FILE!" set /p NEXROUTE_LANG=<"!NEXROUTE_LANGUAGE_FILE!"
if /I not "!NEXROUTE_LANG!"=="RU" if /I not "!NEXROUTE_LANG!"=="EN" set "NEXROUTE_LANG=RU"

title NexRoute Control Center v!LOCAL_VERSION!

:menu
cls
chcp 65001 > nul
color 0B

call :ipset_switch_status
call :game_switch_status
call :check_updates_switch_status
call :get_strategy_name

set "menu_choice=null"

echo.
echo  ============================================================================
echo                         N E X R O U T E
echo                      CONTROL CENTER v!LOCAL_VERSION!
echo  ============================================================================
echo   Flowseal baseline: 1.10.0
echo   !CurrentStrategy!
echo  ----------------------------------------------------------------------------
echo.

if /I "!NEXROUTE_LANG!"=="EN" goto menu_en

:menu_ru
echo   СЛУЖБА
echo      [1] Установить выбранную стратегию как службу
echo      [2] Удалить службы NexRoute / WinDivert
echo      [3] Проверить состояние
echo.
echo   НАСТРОЙКИ
echo      [4] Игровой фильтр          [!GameFilterStatus!]
echo      [5] IPSet-фильтр            [!IPsetStatus!]
echo      [6] Проверка обновлений     [!CheckUpdatesStatus!]
echo      [7] Заменить активные fake-payload
echo.
echo   ОБНОВЛЕНИЯ
echo      [8] Обновить IPSet
echo      [9] Обновить hosts
echo     [10] Проверить релизы NexRoute
echo.
echo   ИНСТРУМЕНТЫ
echo     [11] Запустить диагностику
echo     [12] Запустить тесты
echo     [13] Switch language: English
echo.
echo      [0] Выход
echo.
set /p menu_choice=   Выберите пункт [0-13]: 
goto menu_dispatch

:menu_en
echo   SERVICE
echo      [1] Install selected strategy as a service
echo      [2] Remove NexRoute / WinDivert services
echo      [3] Check status
echo.
echo   SETTINGS
echo      [4] Game Filter             [!GameFilterStatus!]
echo      [5] IPSet Filter            [!IPsetStatus!]
echo      [6] Update Check            [!CheckUpdatesStatus!]
echo      [7] Replace active fake payloads
echo.
echo   UPDATES
echo      [8] Update IPSet
echo      [9] Update hosts
echo     [10] Check NexRoute releases
echo.
echo   TOOLS
echo     [11] Run diagnostics
echo     [12] Run tests
echo     [13] Переключить язык: Русский
echo.
echo      [0] Exit
echo.
set /p menu_choice=   Select option [0-13]: 

:menu_dispatch
if "!menu_choice!"=="1" goto service_install
if "!menu_choice!"=="2" goto service_remove
if "!menu_choice!"=="3" goto service_status
if "!menu_choice!"=="4" goto game_switch
if "!menu_choice!"=="5" goto ipset_switch
if "!menu_choice!"=="6" goto check_updates_switch
if "!menu_choice!"=="7" goto replace_active_fakes
if "!menu_choice!"=="8" goto ipset_update
if "!menu_choice!"=="9" goto hosts_update
if "!menu_choice!"=="10" goto service_check_updates
if "!menu_choice!"=="11" goto service_diagnostics
if "!menu_choice!"=="12" goto run_tests
if "!menu_choice!"=="13" goto nexroute_toggle_language
if "!menu_choice!"=="0" exit /b
goto menu

:nexroute_toggle_language
if /I "!NEXROUTE_LANG!"=="RU" (
    set "NEXROUTE_LANG=EN"
) else (
    set "NEXROUTE_LANG=RU"
)
>"!NEXROUTE_LANGUAGE_FILE!" echo !NEXROUTE_LANG!
goto menu


:: LOAD USER LISTS =====================
'@

    $serviceContent = [regex]::Replace($serviceContent, $menuPattern, $menuBlock, 1)
    [System.IO.File]::WriteAllText(
        $servicePath,
        $serviceContent,
        [System.Text.UTF8Encoding]::new($false)
    )

    Write-Step 'Adding NexRoute documentation and metadata'
    Copy-RequiredFile -Source (Join-Path $repositoryRoot 'README.md') -Destination (Join-Path $distributionPath 'README.md')
    Copy-RequiredFile -Source (Join-Path $repositoryRoot 'LICENSE') -Destination (Join-Path $distributionPath 'LICENSE')
    Copy-RequiredFile -Source (Join-Path $repositoryRoot 'THIRD_PARTY_NOTICES.md') -Destination (Join-Path $distributionPath 'THIRD_PARTY_NOTICES.md')
    Copy-RequiredFile -Source (Join-Path $repositoryRoot 'overlay/nexroute.bat') -Destination (Join-Path $distributionPath 'nexroute.bat')

    $distributionServiceDirectory = Join-Path $distributionPath '.service'
    New-Item -ItemType Directory -Path $distributionServiceDirectory -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $distributionServiceDirectory 'version.txt') -Value $Version -Encoding ascii

    $docsSource = Join-Path $repositoryRoot 'docs'
    if (Test-Path -LiteralPath $docsSource -PathType Container) {
        Copy-Item -LiteralPath $docsSource -Destination (Join-Path $distributionPath 'docs') -Recurse -Force
    }

    $buildInfo = @"
NexRoute version: $Version
Flowseal baseline: $UpstreamVersion
Flowseal release id: $($release.id)
Flowseal asset: $($asset.name)
Build UTC: $([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))
Source repository: https://github.com/Onmaynec/NexRoute
"@
    Set-Content -LiteralPath (Join-Path $distributionPath 'NEXROUTE_BUILD_INFO.txt') -Value $buildInfo -Encoding utf8

    $archiveName = "NexRoute-$Version-win-x64.zip"
    $archivePath = Join-Path $outputPath $archiveName
    if (Test-Path -LiteralPath $archivePath) {
        Remove-Item -LiteralPath $archivePath -Force
    }

    Write-Step "Creating $archiveName"
    Compress-Archive -Path (Join-Path $distributionPath '*') -DestinationPath $archivePath -CompressionLevel Optimal

    $hash = Get-FileHash -LiteralPath $archivePath -Algorithm SHA256
    $checksumPath = "$archivePath.sha256"
    $checksumLine = "{0}  {1}" -f $hash.Hash.ToLowerInvariant(), $archiveName
    Set-Content -LiteralPath $checksumPath -Value $checksumLine -Encoding ascii

    Write-Step "Build completed: $archivePath"
    Write-Step "SHA-256: $($hash.Hash.ToLowerInvariant())"

    [pscustomobject]@{
        Version         = $Version
        UpstreamVersion = $UpstreamVersion
        UpstreamAsset   = $asset.name
        Archive         = $archivePath
        Checksum        = $checksumPath
        Sha256          = $hash.Hash.ToLowerInvariant()
    }
}
finally {
    if (Test-Path -LiteralPath $tempPath) {
        Remove-Item -LiteralPath $tempPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}
