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

function Add-AsciiHookAfterFirstLine {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Hook
    )

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -eq 0) {
        throw "Cannot inject launcher into empty strategy file: $Path"
    }

    $probeLength = [Math]::Min(128, $bytes.Length)
    $probe = [System.Text.Encoding]::ASCII.GetString($bytes, 0, $probeLength)
    if ($probe -notmatch '(?im)^\s*@echo\s+off\s*$') {
        throw "Strategy file does not start with @echo off: $Path"
    }

    if ($probe -match 'NEXROUTE_PROFILE_BOOT') {
        return
    }

    $insertAt = -1
    for ($i = 0; $i -lt $bytes.Length; $i++) {
        if ($bytes[$i] -eq 10) {
            $insertAt = $i + 1
            break
        }
    }

    if ($insertAt -lt 0) {
        throw "Cannot locate first line ending in strategy file: $Path"
    }

    $hookBytes = [System.Text.Encoding]::ASCII.GetBytes($Hook)
    $stream = [System.IO.MemoryStream]::new()
    try {
        $stream.Write($bytes, 0, $insertAt)
        $stream.Write($hookBytes, 0, $hookBytes.Length)
        $stream.Write($bytes, $insertAt, $bytes.Length - $insertAt)
        [System.IO.File]::WriteAllBytes($Path, $stream.ToArray())
    }
    finally {
        $stream.Dispose()
    }
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

    Write-Step 'Installing terminal UI runtime'
    $distributionServiceDirectory = Join-Path $distributionPath '.service'
    New-Item -ItemType Directory -Path $distributionServiceDirectory -Force | Out-Null
    Copy-RequiredFile `
        -Source (Join-Path $repositoryRoot 'overlay/.service/nexroute-ui.ps1') `
        -Destination (Join-Path $distributionServiceDirectory 'nexroute-ui.ps1')

    Set-Content -LiteralPath (Join-Path $distributionServiceDirectory 'language.txt') -Value 'RU' -Encoding ascii
    Set-Content -LiteralPath (Join-Path $distributionServiceDirectory 'version.txt') -Value $Version -Encoding ascii

    Write-Step 'Applying NexRoute service control panel'
    $servicePath = Join-Path $distributionPath 'service.bat'
    $serviceContent = [System.IO.File]::ReadAllText($servicePath)

    $serviceContent = [regex]::Replace(
        $serviceContent,
        'set "LOCAL_VERSION=[^"]+"',
        ('set "LOCAL_VERSION={0}"' -f $Version),
        [System.Text.RegularExpressions.RegexOptions]::None
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
    $menuRegex = [regex]::new($menuPattern)
    if (-not $menuRegex.IsMatch($serviceContent)) {
        throw 'Unable to locate the upstream service menu block. The pinned upstream format may have changed.'
    }

    $menuBlock = @'
:: MENU ================================
setlocal EnableDelayedExpansion
set "NEXROUTE_LANGUAGE_FILE=%~dp0.service\language.txt"
set "NEXROUTE_UI=%~dp0.service\nexroute-ui.ps1"
title NexRoute // Control Node v!LOCAL_VERSION!

:menu
chcp 65001 > nul

call :ipset_switch_status
call :game_switch_status
call :check_updates_switch_status
call :get_strategy_name

set "NEXROUTE_LANG=RU"
if exist "!NEXROUTE_LANGUAGE_FILE!" set /p NEXROUTE_LANG=<"!NEXROUTE_LANGUAGE_FILE!"
if /I not "!NEXROUTE_LANG!"=="RU" if /I not "!NEXROUTE_LANG!"=="EN" set "NEXROUTE_LANG=RU"

set "NEXROUTE_VERSION=!LOCAL_VERSION!"
set "NEXROUTE_BASELINE=1.10.0"
set "NEXROUTE_STRATEGY=!CurrentStrategy!"
set "NEXROUTE_GAME_STATUS=!GameFilterStatus!"
set "NEXROUTE_IPSET_STATUS=!IPsetStatus!"
set "NEXROUTE_UPDATE_STATUS=!CheckUpdatesStatus!"
set "NEXROUTE_UI_ANIMATE=0"
if not defined NEXROUTE_UI_BOOTED set "NEXROUTE_UI_ANIMATE=1"

set "menu_choice="
set "NEXROUTE_MENU_CHOICE_FILE=%TEMP%\nexroute-choice-!RANDOM!-!RANDOM!.txt"
if exist "!NEXROUTE_MENU_CHOICE_FILE!" del /q "!NEXROUTE_MENU_CHOICE_FILE!" >nul 2>&1

if exist "!NEXROUTE_UI!" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "!NEXROUTE_UI!" -Mode Menu -ChoiceFile "!NEXROUTE_MENU_CHOICE_FILE!" -LanguageFile "!NEXROUTE_LANGUAGE_FILE!"
    set "NEXROUTE_UI_BOOTED=1"
)

if exist "!NEXROUTE_MENU_CHOICE_FILE!" (
    set /p menu_choice=<"!NEXROUTE_MENU_CHOICE_FILE!"
    del /q "!NEXROUTE_MENU_CHOICE_FILE!" >nul 2>&1
)

if not defined menu_choice (
    cls
    color 0B
    echo.
    echo  +============================================================================+
    echo  ^|                         NEXROUTE CONTROL NODE                              ^|
    echo  +============================================================================+
    echo  ^| [01] Deploy selected strategy as service                                  ^|
    echo  ^| [02] Remove NexRoute and WinDivert services                               ^|
    echo  ^| [03] Check system status                                                  ^|
    echo  ^| [04] Toggle Game Filter                                                   ^|
    echo  ^| [05] Switch IPSet Filter                                                  ^|
    echo  ^| [06] Toggle update checks                                                 ^|
    echo  ^| [07] Replace active fake payloads                                         ^|
    echo  ^| [08] Update IPSet                                                         ^|
    echo  ^| [09] Update hosts                                                         ^|
    echo  ^| [10] Check NexRoute releases                                              ^|
    echo  ^| [11] Run diagnostics                                                      ^|
    echo  ^| [12] Run tests                                                            ^|
    echo  ^| [13] Switch language                                                      ^|
    echo  ^| [00] Exit                                                                 ^|
    echo  +============================================================================+
    echo.
    set /p "menu_choice=  Enter command [0-13]: "
)

if "!menu_choice!"=="1" (
    call :nexroute_action deploy
    goto service_install
)
if "!menu_choice!"=="2" (
    call :nexroute_action remove
    goto service_remove
)
if "!menu_choice!"=="3" (
    call :nexroute_action status
    goto service_status
)
if "!menu_choice!"=="4" (
    call :nexroute_action game
    goto game_switch
)
if "!menu_choice!"=="5" (
    call :nexroute_action ipset
    goto ipset_switch
)
if "!menu_choice!"=="6" (
    call :nexroute_action updatecheck
    goto check_updates_switch
)
if "!menu_choice!"=="7" (
    call :nexroute_action payload
    goto replace_active_fakes
)
if "!menu_choice!"=="8" (
    call :nexroute_action syncipset
    goto ipset_update
)
if "!menu_choice!"=="9" (
    call :nexroute_action synchosts
    goto hosts_update
)
if "!menu_choice!"=="10" (
    call :nexroute_action releases
    goto service_check_updates
)
if "!menu_choice!"=="11" (
    call :nexroute_action diagnostics
    goto service_diagnostics
)
if "!menu_choice!"=="12" (
    call :nexroute_action tests
    goto run_tests
)
if "!menu_choice!"=="13" goto nexroute_toggle_language
if "!menu_choice!"=="0" exit /b
goto menu

:nexroute_toggle_language
if /I "!NEXROUTE_LANG!"=="RU" (
    >"!NEXROUTE_LANGUAGE_FILE!" echo EN
) else (
    >"!NEXROUTE_LANGUAGE_FILE!" echo RU
)
goto menu

:nexroute_action
if exist "!NEXROUTE_UI!" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "!NEXROUTE_UI!" -Mode Action -ActionId "%~1" -LanguageFile "!NEXROUTE_LANGUAGE_FILE!"
)
exit /b


:: LOAD USER LISTS =====================
'@

    $serviceContent = $menuRegex.Replace($serviceContent, $menuBlock, 1)
    [System.IO.File]::WriteAllText(
        $servicePath,
        $serviceContent,
        [System.Text.UTF8Encoding]::new($false)
    )

    Write-Step 'Injecting animated profile boot into strategy launchers'
    $strategyHook = @'
rem NEXROUTE_PROFILE_BOOT
if exist "%~dp0.service\nexroute-ui.ps1" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0.service\nexroute-ui.ps1" -Mode Launch -Profile "%~n0" -LanguageFile "%~dp0.service\language.txt"
'@ -replace "`n", "`r`n"

    $strategyFiles = @(
        Get-ChildItem -LiteralPath $distributionPath -Filter '*.bat' -File |
            Where-Object { $_.Name -notin @('service.bat', 'nexroute.bat') }
    )

    if ($strategyFiles.Count -eq 0) {
        throw 'No strategy BAT files were found for terminal boot injection.'
    }

    foreach ($strategyFile in $strategyFiles) {
        Add-AsciiHookAfterFirstLine -Path $strategyFile.FullName -Hook $strategyHook
    }

    Write-Step 'Adding NexRoute documentation and metadata'
    Copy-RequiredFile -Source (Join-Path $repositoryRoot 'README.md') -Destination (Join-Path $distributionPath 'README.md')
    Copy-RequiredFile -Source (Join-Path $repositoryRoot 'LICENSE') -Destination (Join-Path $distributionPath 'LICENSE')
    Copy-RequiredFile -Source (Join-Path $repositoryRoot 'THIRD_PARTY_NOTICES.md') -Destination (Join-Path $distributionPath 'THIRD_PARTY_NOTICES.md')
    Copy-RequiredFile -Source (Join-Path $repositoryRoot 'overlay/nexroute.bat') -Destination (Join-Path $distributionPath 'nexroute.bat')

    $docsSource = Join-Path $repositoryRoot 'docs'
    if (Test-Path -LiteralPath $docsSource -PathType Container) {
        Copy-Item -LiteralPath $docsSource -Destination (Join-Path $distributionPath 'docs') -Recurse -Force
    }

    $buildInfo = @"
NexRoute version: $Version
Flowseal baseline: $UpstreamVersion
Flowseal release id: $($release.id)
Flowseal asset: $($asset.name)
Terminal UI: PowerShell console renderer with ASCII-safe source
Animated strategy launchers: $($strategyFiles.Count)
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
        StrategyCount   = $strategyFiles.Count
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
