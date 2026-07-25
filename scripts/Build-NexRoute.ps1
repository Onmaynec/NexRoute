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
$tempPath = Join-Path ([System.IO.Path]::GetTempPath()) ("nexroute-build-{0}" -f [guid]::NewGuid().ToString('N'))
$downloadPath = Join-Path $tempPath 'upstream.zip'
$extractPath = Join-Path $tempPath 'upstream'
$distributionPath = Join-Path $tempPath ("NexRoute-{0}-win-x64" -f $Version)

$headers = @{
    'Accept' = 'application/vnd.github+json'
    'User-Agent' = 'NexRoute-Release-Builder'
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
    $directory = Split-Path -Parent $Destination
    if ($directory) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function Write-Utf8NoBom {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Replace-RequiredPattern {
    param(
        [Parameter(Mandatory)][string]$Content,
        [Parameter(Mandatory)][string]$Pattern,
        [Parameter(Mandatory)][string]$Replacement,
        [Parameter(Mandatory)][string]$Name
    )
    $regex = [regex]::new($Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $regex.IsMatch($Content)) {
        throw "Unable to locate upstream block: $Name"
    }
    return $regex.Replace($Content, $Replacement, 1)
}

function Add-AsciiHookAfterFirstLine {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Hook
    )
    $content = [System.IO.File]::ReadAllText($Path)
    if ($content -match 'NEXROUTE_PROFILE_BOOT') { return }
    $match = [regex]::Match($content, '^(?<first>[^\r\n]*)(?<newline>\r?\n)')
    if (-not $match.Success) {
        throw "Strategy file has no first line: $Path"
    }
    $patched = $match.Groups['first'].Value + "`r`n" + $Hook + "`r`n" + $content.Substring($match.Length)
    [System.IO.File]::WriteAllText($Path, $patched, [System.Text.Encoding]::ASCII)
}

try {
    New-Item -ItemType Directory -Path $tempPath, $extractPath, $outputPath -Force | Out-Null

    Write-Step "Resolving Flowseal release $UpstreamVersion"
    $releaseUrl = "https://api.github.com/repos/Flowseal/zapret-discord-youtube/releases/tags/$UpstreamVersion"
    $release = Invoke-RestMethod -Uri $releaseUrl -Headers $headers -Method Get
    $zipAssets = @($release.assets | Where-Object { $_.name -match '^zapret-discord-youtube.*\.zip$' -and $_.browser_download_url } | Sort-Object size -Descending)
    if ($zipAssets.Count -eq 0) {
        throw "The Flowseal release $UpstreamVersion has no binary ZIP asset."
    }

    $asset = $zipAssets[0]
    Write-Step ("Downloading official asset: {0}" -f $asset.name)
    Invoke-WebRequest -Uri $asset.browser_download_url -Headers $headers -OutFile $downloadPath -UseBasicParsing
    if ((Get-Item -LiteralPath $downloadPath).Length -lt 1024) {
        throw 'Downloaded upstream archive is unexpectedly small.'
    }

    Write-Step 'Extracting upstream archive'
    Expand-Archive -LiteralPath $downloadPath -DestinationPath $extractPath -Force
    $serviceFile = Get-ChildItem -LiteralPath $extractPath -Filter 'service.bat' -File -Recurse | Where-Object { Test-Path -LiteralPath (Join-Path $_.Directory.FullName 'general.bat') } | Select-Object -First 1
    if (-not $serviceFile) {
        throw 'Unable to locate the Flowseal distribution root.'
    }

    $upstreamRoot = $serviceFile.Directory.FullName
    $requiredUpstreamFiles = @(
        'service.bat',
        'general.bat',
        'bin/winws.exe',
        'bin/WinDivert.dll',
        'bin/WinDivert64.sys',
        'lists/list-general.txt',
        'lists/list-google.txt',
        'utils/test zapret.ps1'
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

    Write-Step 'Installing NexRoute 0.2 terminal runtime'
    $distributionServiceDirectory = Join-Path $distributionPath '.service'
    New-Item -ItemType Directory -Path $distributionServiceDirectory -Force | Out-Null
    Copy-RequiredFile -Source (Join-Path $repositoryRoot 'overlay/.service/nexroute-ui.ps1') -Destination (Join-Path $distributionServiceDirectory 'nexroute-ui.ps1')
    Copy-RequiredFile -Source (Join-Path $repositoryRoot 'overlay/.service/nexroute-services.ps1') -Destination (Join-Path $distributionServiceDirectory 'nexroute-services.ps1')
    Copy-RequiredFile -Source (Join-Path $repositoryRoot 'overlay/.service/services.json') -Destination (Join-Path $distributionServiceDirectory 'services.json')
    Copy-RequiredFile -Source (Join-Path $repositoryRoot 'overlay/.service/New-NexRouteIcon.ps1') -Destination (Join-Path $distributionServiceDirectory 'New-NexRouteIcon.ps1')
    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'overlay/.service/i18n') -Destination (Join-Path $distributionServiceDirectory 'i18n') -Recurse -Force
    Set-Content -LiteralPath (Join-Path $distributionServiceDirectory 'language.txt') -Value 'RU' -Encoding ascii
    Set-Content -LiteralPath (Join-Path $distributionServiceDirectory 'version.txt') -Value $Version -Encoding ascii

    $servicePath = Join-Path $distributionPath 'service.bat'
    $serviceContent = [System.IO.File]::ReadAllText($servicePath)
    $serviceContent = [regex]::Replace($serviceContent, 'set "LOCAL_VERSION=[^"]+"', ('set "LOCAL_VERSION={0}"' -f $Version), 1)
    $serviceContent = $serviceContent.Replace('https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/main/.service/version.txt', 'https://raw.githubusercontent.com/Onmaynec/NexRoute/main/.service/version.txt')
    $serviceContent = $serviceContent.Replace('https://github.com/Flowseal/zapret-discord-youtube/releases/tag/', 'https://github.com/Onmaynec/NexRoute/releases/tag/')
    $serviceContent = $serviceContent.Replace('https://github.com/Flowseal/zapret-discord-youtube/releases/latest', 'https://github.com/Onmaynec/NexRoute/releases/latest')
    $serviceContent = $serviceContent.Replace('sc description %SRVCNAME% "Zapret DPI bypass software"', 'sc description %SRVCNAME% "NexRoute route control service"')

    $menuBlock = @'
:: MENU ================================
setlocal EnableDelayedExpansion
set "NEXROUTE_LANGUAGE_FILE=%~dp0.service\language.txt"
set "NEXROUTE_UI=%~dp0.service\nexroute-ui.ps1"
set "NEXROUTE_SERVICES=%~dp0.service\nexroute-services.ps1"
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
    powershell -NoProfile -ExecutionPolicy Bypass -File "!NEXROUTE_UI!" -Mode Menu -Root "%~dp0" -ChoiceFile "!NEXROUTE_MENU_CHOICE_FILE!" -LanguageFile "!NEXROUTE_LANGUAGE_FILE!"
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
    echo  ^| [08] Sync IPSet                                                           ^|
    echo  ^| [09] Sync hosts                                                           ^|
    echo  ^| [10] Check NexRoute releases                                              ^|
    echo  ^| [11] Run diagnostics                                                      ^|
    echo  ^| [12] Run tests                                                            ^|
    echo  ^| [13] Switch language                                                      ^|
    echo  ^| [14] Service bypass matrix                                                ^|
    echo  ^| [00] Exit                                                                 ^|
    echo  +============================================================================+
    echo.
    set /p "menu_choice=  Enter command [0-14]: "
)

if "!menu_choice!"=="1" (call :nexroute_action deploy&goto service_install)
if "!menu_choice!"=="2" (call :nexroute_action remove&goto service_remove)
if "!menu_choice!"=="3" goto service_status
if "!menu_choice!"=="4" (call :nexroute_action game&goto game_switch)
if "!menu_choice!"=="5" goto ipset_switch
if "!menu_choice!"=="6" (call :nexroute_action updatecheck&goto check_updates_switch)
if "!menu_choice!"=="7" goto replace_active_fakes
if "!menu_choice!"=="8" goto ipset_update
if "!menu_choice!"=="9" goto hosts_update
if "!menu_choice!"=="10" (call :nexroute_action releases&goto service_check_updates)
if "!menu_choice!"=="11" goto service_diagnostics
if "!menu_choice!"=="12" goto run_tests
if "!menu_choice!"=="13" goto nexroute_toggle_language
if "!menu_choice!"=="14" goto nexroute_services_matrix
if "!menu_choice!"=="0" exit /b
goto menu

:nexroute_toggle_language
if /I "!NEXROUTE_LANG!"=="RU" (>"!NEXROUTE_LANGUAGE_FILE!" echo EN) else (>"!NEXROUTE_LANGUAGE_FILE!" echo RU)
goto menu

:nexroute_action
if exist "!NEXROUTE_UI!" powershell -NoProfile -ExecutionPolicy Bypass -File "!NEXROUTE_UI!" -Mode Action -Root "%~dp0" -ActionId "%~1" -LanguageFile "!NEXROUTE_LANGUAGE_FILE!"
exit /b

:nexroute_services_matrix
if exist "!NEXROUTE_UI!" powershell -NoProfile -ExecutionPolicy Bypass -File "!NEXROUTE_UI!" -Mode Services -Root "%~dp0" -LanguageFile "!NEXROUTE_LANGUAGE_FILE!"
goto menu


:: LOAD USER LISTS =====================
'@
    $serviceContent = Replace-RequiredPattern -Content $serviceContent -Pattern ':: MENU =+.*?:: LOAD USER LISTS =+' -Replacement $menuBlock -Name 'main menu'

    $serviceContent = $serviceContent.Replace(
        "if not exist \"%LISTS_PATH%list-exclude-user.txt\" (`r`n    echo domain.example.abc>\"%LISTS_PATH%list-exclude-user.txt\"`r`n)`r`n`r`nexit /b",
        "if not exist \"%LISTS_PATH%list-exclude-user.txt\" (`r`n    echo domain.example.abc>\"%LISTS_PATH%list-exclude-user.txt\"`r`n)`r`n`r`nif exist \"%~dp0.service\nexroute-services.ps1\" powershell -NoProfile -ExecutionPolicy Bypass -File \"%~dp0.service\nexroute-services.ps1\" -Mode Apply -Root \"%~dp0\" >nul 2>&1`r`n`r`nexit /b"
    )

    $statusBlock = @'
:service_status
chcp 65001 > nul
if exist "!NEXROUTE_UI!" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "!NEXROUTE_UI!" -Mode Status -Root "%~dp0" -LanguageFile "!NEXROUTE_LANGUAGE_FILE!"
) else (
    call :test_service zapret
    call :test_service WinDivert
    pause
)
goto menu

'@
    $serviceContent = Replace-RequiredPattern -Content $serviceContent -Pattern ':service_status\r?\n.*?(?=:test_service)' -Replacement $statusBlock -Name 'status page'

    $pickerBlock = @'
:: Searching for strategy launchers through NexRoute selector
set "selectedFile="
set "NEXROUTE_STRATEGY_CHOICE=%TEMP%\nexroute-strategy-!RANDOM!-!RANDOM!.txt"
if exist "!NEXROUTE_STRATEGY_CHOICE!" del /q "!NEXROUTE_STRATEGY_CHOICE!" >nul 2>&1
if exist "!NEXROUTE_UI!" powershell -NoProfile -ExecutionPolicy Bypass -File "!NEXROUTE_UI!" -Mode StrategyPicker -Root "%~dp0" -ChoiceFile "!NEXROUTE_STRATEGY_CHOICE!" -LanguageFile "!NEXROUTE_LANGUAGE_FILE!"
if exist "!NEXROUTE_STRATEGY_CHOICE!" (
    set /p selectedFile=<"!NEXROUTE_STRATEGY_CHOICE!"
    del /q "!NEXROUTE_STRATEGY_CHOICE!" >nul 2>&1
)
if not defined selectedFile goto menu
if "!selectedFile!"=="0" goto menu
if not exist "!selectedFile!" (
    echo Selected strategy was not found: !selectedFile!
    pause
    goto menu
)
set "choice=1"
set "file1=!selectedFile!"

:: Args that should be followed by value
'@
    $serviceContent = Replace-RequiredPattern -Content $serviceContent -Pattern ':: Searching for \.bat files.*?:: Args that should be followed by value' -Replacement $pickerBlock -Name 'strategy selector'

    $serviceContent = [regex]::Replace(
        $serviceContent,
        '(reg add "HKLM\\System\\CurrentControlSet\\Services\\zapret" /v zapret-discord-youtube /t REG_SZ /d "!filename!" /f)\r?\n\r?\npause\r?\ngoto menu',
        '$1' + "`r`nif exist \"!NEXROUTE_UI!\" powershell -NoProfile -ExecutionPolicy Bypass -File \"!NEXROUTE_UI!\" -Mode Status -Root \"%~dp0\" -LanguageFile \"!NEXROUTE_LANGUAGE_FILE!\"`r`ngoto menu",
        1
    )

    $payloadBlock = @'
:: REPLACE ACTIVE FAKES =================
:replace_active_fakes
chcp 65001 > nul
if exist "!NEXROUTE_UI!" powershell -NoProfile -ExecutionPolicy Bypass -File "!NEXROUTE_UI!" -Mode PayloadManager -Root "%~dp0" -LanguageFile "!NEXROUTE_LANGUAGE_FILE!"
goto menu


:: IPSET SWITCH =======================
'@
    $serviceContent = Replace-RequiredPattern -Content $serviceContent -Pattern ':: REPLACE ACTIVE FAKES =+.*?:: IPSET SWITCH =+' -Replacement $payloadBlock -Name 'payload manager'

    $ipsetSwitchBlock = @'
:ipset_switch
chcp 65001 > nul
if exist "!NEXROUTE_UI!" powershell -NoProfile -ExecutionPolicy Bypass -File "!NEXROUTE_UI!" -Mode IpSetSwitch -Root "%~dp0" -LanguageFile "!NEXROUTE_LANGUAGE_FILE!"
goto menu


:: IPSET UPDATE =======================
'@
    $serviceContent = Replace-RequiredPattern -Content $serviceContent -Pattern ':ipset_switch\r?\n.*?:: IPSET UPDATE =+' -Replacement $ipsetSwitchBlock -Name 'IPSet mode page'

    $ipsetUpdateBlock = @'
:ipset_update
chcp 65001 > nul
if exist "!NEXROUTE_UI!" powershell -NoProfile -ExecutionPolicy Bypass -File "!NEXROUTE_UI!" -Mode SyncIpSet -Root "%~dp0" -LanguageFile "!NEXROUTE_LANGUAGE_FILE!"
goto menu


:: HOSTS UPDATE =======================
'@
    $serviceContent = Replace-RequiredPattern -Content $serviceContent -Pattern ':ipset_update\r?\n.*?:: HOSTS UPDATE =+' -Replacement $ipsetUpdateBlock -Name 'IPSet synchronization page'

    $hostsBlock = @'
:hosts_update
chcp 65001 > nul
if exist "!NEXROUTE_UI!" powershell -NoProfile -ExecutionPolicy Bypass -File "!NEXROUTE_UI!" -Mode SyncHosts -Root "%~dp0" -LanguageFile "!NEXROUTE_LANGUAGE_FILE!"
goto menu


:: RUN TESTS =============================
'@
    $serviceContent = Replace-RequiredPattern -Content $serviceContent -Pattern ':hosts_update\r?\n.*?:: RUN TESTS =+' -Replacement $hostsBlock -Name 'hosts synchronization page'

    $testsBlock = @'
:run_tests
chcp 65001 >nul
powershell -NoProfile -Command "if ($PSVersionTable.PSVersion.Major -ge 3) { exit 0 } else { exit 1 }" >nul 2>&1
if !errorlevel! neq 0 (
    echo PowerShell 3.0 or newer is required.
    pause
    goto menu
)
if exist "!NEXROUTE_UI!" powershell -NoProfile -ExecutionPolicy Bypass -File "!NEXROUTE_UI!" -Mode TestsIntro -Root "%~dp0" -LanguageFile "!NEXROUTE_LANGUAGE_FILE!"
start "NexRoute Strategy Lab" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0utils\test zapret.ps1"
goto menu


:: Get strategy name
'@
    $serviceContent = Replace-RequiredPattern -Content $serviceContent -Pattern ':run_tests\r?\n.*?:: Get strategy name' -Replacement $testsBlock -Name 'test launcher page'

    $serviceContent = $serviceContent.Replace(
        ":service_diagnostics`r`nchcp 437 > nul`r`ncls",
        ":service_diagnostics`r`nchcp 65001 > nul`r`nif exist \"!NEXROUTE_UI!\" powershell -NoProfile -ExecutionPolicy Bypass -File \"!NEXROUTE_UI!\" -Mode Screen -ScreenId diagnostics -Root \"%~dp0\" -LanguageFile \"!NEXROUTE_LANGUAGE_FILE!\""
    )

    Write-Utf8NoBom -Path $servicePath -Content $serviceContent

    Write-Step 'Injecting animated profile boots into strategy launchers'
    $strategyHook = @'
rem NEXROUTE_PROFILE_BOOT
if exist "%~dp0.service\nexroute-services.ps1" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0.service\nexroute-services.ps1" -Mode Apply -Root "%~dp0" >nul 2>&1
if exist "%~dp0.service\nexroute-ui.ps1" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0.service\nexroute-ui.ps1" -Mode Launch -Root "%~dp0" -Profile "%~n0" -LanguageFile "%~dp0.service\language.txt"
'@ -replace "`n", "`r`n"
    $strategyFiles = @(Get-ChildItem -LiteralPath $distributionPath -Filter '*.bat' -File | Where-Object { $_.Name -notin @('service.bat', 'nexroute.bat') })
    if ($strategyFiles.Count -eq 0) { throw 'No strategy BAT files were found.' }
    foreach ($strategyFile in $strategyFiles) {
        Add-AsciiHookAfterFirstLine -Path $strategyFile.FullName -Hook $strategyHook
    }

    Write-Step 'Branding the PowerShell test laboratory'
    $testPath = Join-Path $distributionPath 'utils/test zapret.ps1'
    $testContent = [System.IO.File]::ReadAllText($testPath)
    if ($testContent -notmatch 'NEXROUTE_TEST_HEADER') {
        $testHeader = @'
# NEXROUTE_TEST_HEADER
$nrUi = Join-Path (Split-Path $PSScriptRoot) '.service\nexroute-ui.ps1'
$nrLanguage = Join-Path (Split-Path $PSScriptRoot) '.service\language.txt'
if (Test-Path -LiteralPath $nrUi) {
    & $nrUi -Mode TestHeader -Root (Split-Path $PSScriptRoot) -LanguageFile $nrLanguage
}

'@
        Write-Utf8NoBom -Path $testPath -Content ($testHeader + $testContent)
    }

    Write-Step 'Adding documentation, branding and metadata'
    Copy-RequiredFile -Source (Join-Path $repositoryRoot 'README.md') -Destination (Join-Path $distributionPath 'README.md')
    Copy-RequiredFile -Source (Join-Path $repositoryRoot 'LICENSE') -Destination (Join-Path $distributionPath 'LICENSE')
    Copy-RequiredFile -Source (Join-Path $repositoryRoot 'THIRD_PARTY_NOTICES.md') -Destination (Join-Path $distributionPath 'THIRD_PARTY_NOTICES.md')
    Copy-RequiredFile -Source (Join-Path $repositoryRoot 'overlay/nexroute.bat') -Destination (Join-Path $distributionPath 'nexroute.bat')
    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'docs') -Destination (Join-Path $distributionPath 'docs') -Recurse -Force
    Copy-Item -LiteralPath (Join-Path $repositoryRoot 'assets') -Destination (Join-Path $distributionPath 'assets') -Recurse -Force

    & (Join-Path $distributionServiceDirectory 'New-NexRouteIcon.ps1') -Root $distributionPath | Out-Null
    & (Join-Path $distributionServiceDirectory 'nexroute-services.ps1') -Mode Apply -Root $distributionPath | Out-Null

    $buildInfo = @"
NexRoute version: $Version
Flowseal baseline: $UpstreamVersion
Flowseal release id: $($release.id)
Flowseal asset: $($asset.name)
Terminal UI: unified PowerShell renderer for menu, status, strategy, payload, sync and test screens
Service matrix: 15 configurable domain packs
Animated strategy launchers: $($strategyFiles.Count)
Custom icon: .service/nexroute.ico + NexRoute.lnk
Build UTC: $([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))
Source repository: https://github.com/Onmaynec/NexRoute
"@
    Set-Content -LiteralPath (Join-Path $distributionPath 'NEXROUTE_BUILD_INFO.txt') -Value $buildInfo -Encoding utf8

    $archiveName = "NexRoute-$Version-win-x64.zip"
    $archivePath = Join-Path $outputPath $archiveName
    if (Test-Path -LiteralPath $archivePath) { Remove-Item -LiteralPath $archivePath -Force }
    Write-Step "Creating $archiveName"
    Compress-Archive -Path (Join-Path $distributionPath '*') -DestinationPath $archivePath -CompressionLevel Optimal

    $hash = Get-FileHash -LiteralPath $archivePath -Algorithm SHA256
    $checksumPath = "$archivePath.sha256"
    Set-Content -LiteralPath $checksumPath -Value ("{0}  {1}" -f $hash.Hash.ToLowerInvariant(), $archiveName) -Encoding ascii

    Write-Step "Build completed: $archivePath"
    Write-Step "SHA-256: $($hash.Hash.ToLowerInvariant())"

    [pscustomobject]@{
        Version = $Version
        UpstreamVersion = $UpstreamVersion
        UpstreamAsset = $asset.name
        StrategyCount = $strategyFiles.Count
        ServiceCount = 15
        Archive = $archivePath
        Checksum = $checksumPath
        Sha256 = $hash.Hash.ToLowerInvariant()
    }
}
finally {
    if (Test-Path -LiteralPath $tempPath) {
        Remove-Item -LiteralPath $tempPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}
