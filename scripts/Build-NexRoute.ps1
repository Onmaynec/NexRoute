[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$')][string]$Version,
    [ValidatePattern('^\d+\.\d+\.\d+[A-Za-z0-9.-]*$')][string]$UpstreamVersion = '1.10.0',
    [string]$OutputDirectory
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$repositoryRoot = Split-Path -Parent $PSScriptRoot
if (-not $Version) { $Version = (Get-Content (Join-Path $repositoryRoot '.service/version.txt') -Raw).Trim() }
if (-not $OutputDirectory) { $OutputDirectory = Join-Path $repositoryRoot 'artifacts' }
$outputPath = [IO.Path]::GetFullPath($OutputDirectory)
$tempPath = Join-Path ([IO.Path]::GetTempPath()) ('nexroute-build-' + [guid]::NewGuid().ToString('N'))
$downloadPath = Join-Path $tempPath 'upstream.zip'
$extractPath = Join-Path $tempPath 'upstream'
$distributionPath = Join-Path $tempPath ('NexRoute-{0}-win-x64' -f $Version)
$headers = @{ Accept='application/vnd.github+json'; 'User-Agent'='NexRoute-Release-Builder'; 'X-GitHub-Api-Version'='2022-11-28' }
function Step([string]$Message) { Write-Host ('[NexRoute] ' + $Message) -ForegroundColor Cyan }
function Copy-Required([string]$Source,[string]$Destination) {
    if (-not (Test-Path $Source -PathType Leaf)) { throw "Required file not found: $Source" }
    $dir = Split-Path -Parent $Destination
    if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Copy-Item $Source $Destination -Force
}
function Inject-AfterLabel([string]$Content,[string]$Label,[string]$Hook) {
    $pattern = '(?im)^' + [regex]::Escape($Label) + '\s*$'
    if (-not [regex]::IsMatch($Content,$pattern)) { throw "Unable to locate service label: $Label" }
    return [regex]::Replace($Content,$pattern,($Label + "`r`n" + $Hook),1)
}
function Add-StrategyHook([string]$Path,[string]$Hook) {
    $bytes = [IO.File]::ReadAllBytes($Path)
    $probe = [Text.Encoding]::ASCII.GetString($bytes,0,[Math]::Min(160,$bytes.Length))
    if ($probe -match 'NEXROUTE_PROFILE_BOOT') { return }
    $pos = -1
    for ($i=0;$i -lt $bytes.Length;$i++) { if ($bytes[$i] -eq 10) { $pos=$i+1; break } }
    if ($pos -lt 0) { throw "No first line ending in $Path" }
    $hookBytes=[Text.Encoding]::ASCII.GetBytes($Hook)
    $ms=[IO.MemoryStream]::new()
    try { $ms.Write($bytes,0,$pos); $ms.Write($hookBytes,0,$hookBytes.Length); $ms.Write($bytes,$pos,$bytes.Length-$pos); [IO.File]::WriteAllBytes($Path,$ms.ToArray()) } finally { $ms.Dispose() }
}
try {
    New-Item -ItemType Directory -Path $tempPath,$extractPath,$outputPath -Force | Out-Null
    Step "Resolving Flowseal release $UpstreamVersion"
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/Flowseal/zapret-discord-youtube/releases/tags/$UpstreamVersion" -Headers $headers
    $asset = @($release.assets | Where-Object { $_.name -match '^zapret-discord-youtube.*\.zip$' } | Sort-Object size -Descending)[0]
    if (-not $asset) { throw 'Official upstream ZIP asset not found.' }
    Step ('Downloading ' + $asset.name)
    Invoke-WebRequest -Uri $asset.browser_download_url -Headers $headers -OutFile $downloadPath -UseBasicParsing
    Expand-Archive $downloadPath $extractPath -Force
    $serviceFile = Get-ChildItem $extractPath -Filter service.bat -File -Recurse | Where-Object { Test-Path (Join-Path $_.Directory.FullName 'general.bat') } | Select-Object -First 1
    if (-not $serviceFile) { throw 'Flowseal distribution root not found.' }
    $upstreamRoot=$serviceFile.Directory.FullName
    foreach ($required in @('service.bat','general.bat','bin/winws.exe','bin/WinDivert.dll','bin/WinDivert64.sys','lists/list-general.txt','lists/list-google.txt')) {
        if (-not (Test-Path (Join-Path $upstreamRoot $required))) { throw "Upstream file missing: $required" }
    }
    Step 'Copying Flowseal baseline'
    Copy-Item $upstreamRoot $distributionPath -Recurse -Force
    $serviceDir=Join-Path $distributionPath '.service'
    New-Item -ItemType Directory -Path $serviceDir -Force | Out-Null
    foreach ($name in @('nexroute-ui.ps1','nexroute-console.ps1','nexroute-pages.ps1','nexroute-services.ps1')) {
        Copy-Required (Join-Path $repositoryRoot ('overlay/.service/' + $name)) (Join-Path $serviceDir $name)
    }
    Set-Content (Join-Path $serviceDir 'language.txt') 'RU' -Encoding ascii
    Set-Content (Join-Path $serviceDir 'version.txt') $Version -Encoding ascii
    Copy-Required (Join-Path $repositoryRoot 'assets/nexroute-mark.svg') (Join-Path $distributionPath 'assets/nexroute-mark.svg')

    Step 'Applying NexRoute control node'
    $servicePath=Join-Path $distributionPath 'service.bat'
    $service=[IO.File]::ReadAllText($servicePath)
    $service=[regex]::Replace($service,'set "LOCAL_VERSION=[^"]+"',('set "LOCAL_VERSION={0}"' -f $Version),1)
    $service=$service.Replace('https://raw.githubusercontent.com/Flowseal/zapret-discord-youtube/main/.service/version.txt','https://raw.githubusercontent.com/Onmaynec/NexRoute/main/.service/version.txt')
    $service=$service.Replace('https://github.com/Flowseal/zapret-discord-youtube/releases/tag/','https://github.com/Onmaynec/NexRoute/releases/tag/')
    $service=$service.Replace('https://github.com/Flowseal/zapret-discord-youtube/releases/latest','https://github.com/Onmaynec/NexRoute/releases/latest')
    $service=$service.Replace('sc description %SRVCNAME% "Zapret DPI bypass software"','sc description %SRVCNAME% "NexRoute packet orchestration service"')

    $menuPattern='(?s):: MENU =+.*?:: LOAD USER LISTS =+'
    $menu=@'
:: MENU ================================
setlocal EnableDelayedExpansion
set "NEXROUTE_LANGUAGE_FILE=%~dp0.service\language.txt"
set "NEXROUTE_UI=%~dp0.service\nexroute-console.ps1"
set "NEXROUTE_PAGES=%~dp0.service\nexroute-pages.ps1"
set "NEXROUTE_SERVICES=%~dp0.service\nexroute-services.ps1"
title NexRoute // Control Node v!LOCAL_VERSION!
:menu
chcp 65001 > nul
call :ipset_switch_status
call :game_switch_status
call :check_updates_switch_status
call :get_strategy_name
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
powershell -NoProfile -ExecutionPolicy Bypass -File "!NEXROUTE_UI!" -Mode Menu -ChoiceFile "!NEXROUTE_MENU_CHOICE_FILE!" -LanguageFile "!NEXROUTE_LANGUAGE_FILE!"
set "NEXROUTE_UI_BOOTED=1"
if exist "!NEXROUTE_MENU_CHOICE_FILE!" set /p menu_choice=<"!NEXROUTE_MENU_CHOICE_FILE!"
if exist "!NEXROUTE_MENU_CHOICE_FILE!" del /q "!NEXROUTE_MENU_CHOICE_FILE!" >nul 2>&1
if "!menu_choice!"=="1" (call :nexroute_action deploy&goto service_install)
if "!menu_choice!"=="2" (call :nexroute_action remove&goto service_remove)
if "!menu_choice!"=="3" (call :nexroute_action status&goto service_status)
if "!menu_choice!"=="4" (call :nexroute_action game&goto game_switch)
if "!menu_choice!"=="5" (call :nexroute_action ipset&goto ipset_switch)
if "!menu_choice!"=="6" (call :nexroute_action updatecheck&goto check_updates_switch)
if "!menu_choice!"=="7" (call :nexroute_action payload&goto replace_active_fakes)
if "!menu_choice!"=="8" (call :nexroute_action syncipset&goto ipset_update)
if "!menu_choice!"=="9" (call :nexroute_action synchosts&goto hosts_update)
if "!menu_choice!"=="10" (call :nexroute_action releases&goto service_check_updates)
if "!menu_choice!"=="11" (call :nexroute_action diagnostics&goto service_diagnostics)
if "!menu_choice!"=="12" (call :nexroute_action tests&goto run_tests)
if "!menu_choice!"=="13" goto nexroute_toggle_language
if "!menu_choice!"=="14" (call :nexroute_action services&goto nexroute_service_matrix)
if "!menu_choice!"=="0" exit /b
goto menu
:nexroute_toggle_language
set "NEXROUTE_LANG=RU"
if exist "!NEXROUTE_LANGUAGE_FILE!" set /p NEXROUTE_LANG=<"!NEXROUTE_LANGUAGE_FILE!"
if /I "!NEXROUTE_LANG!"=="RU" (>"!NEXROUTE_LANGUAGE_FILE!" echo EN) else (>"!NEXROUTE_LANGUAGE_FILE!" echo RU)
goto menu
:nexroute_service_matrix
powershell -NoProfile -ExecutionPolicy Bypass -File "!NEXROUTE_SERVICES!" -RootPath "%~dp0" -LanguageFile "!NEXROUTE_LANGUAGE_FILE!"
goto menu
:nexroute_action
powershell -NoProfile -ExecutionPolicy Bypass -File "!NEXROUTE_UI!" -Mode Action -ActionId "%~1" -LanguageFile "!NEXROUTE_LANGUAGE_FILE!"
exit /b

:: LOAD USER LISTS =====================
'@
    if (-not [regex]::IsMatch($service,$menuPattern)) { throw 'Upstream menu block not found.' }
    $service=[regex]::Replace($service,$menuPattern,$menu,1)

    $hooks=@{
        ':service_status'='if exist "%~dp0.service\nexroute-pages.ps1" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0.service\nexroute-pages.ps1" -Page status -LanguageFile "%~dp0.service\language.txt"'
        ':service_remove'='if exist "%~dp0.service\nexroute-pages.ps1" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0.service\nexroute-pages.ps1" -Page remove -LanguageFile "%~dp0.service\language.txt"'
        ':service_install'='if exist "%~dp0.service\nexroute-pages.ps1" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0.service\nexroute-pages.ps1" -Page strategy -LanguageFile "%~dp0.service\language.txt"'
        ':replace_active_fakes'='if exist "%~dp0.service\nexroute-pages.ps1" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0.service\nexroute-pages.ps1" -Page payload -LanguageFile "%~dp0.service\language.txt"'
        ':run_tests'='if exist "%~dp0.service\nexroute-pages.ps1" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0.service\nexroute-pages.ps1" -Page tests -LanguageFile "%~dp0.service\language.txt"'
        ':ipset_update'='if exist "%~dp0.service\nexroute-pages.ps1" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0.service\nexroute-pages.ps1" -Page sync-ipset -LanguageFile "%~dp0.service\language.txt"'
        ':hosts_update'='if exist "%~dp0.service\nexroute-pages.ps1" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0.service\nexroute-pages.ps1" -Page sync-hosts -LanguageFile "%~dp0.service\language.txt"'
        ':service_diagnostics'='if exist "%~dp0.service\nexroute-pages.ps1" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0.service\nexroute-pages.ps1" -Page diagnostics -LanguageFile "%~dp0.service\language.txt"'
        ':service_check_updates'='if exist "%~dp0.service\nexroute-pages.ps1" powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0.service\nexroute-pages.ps1" -Page updates -LanguageFile "%~dp0.service\language.txt"'
    }
    foreach ($entry in $hooks.GetEnumerator()) { $service=Inject-AfterLabel $service $entry.Key $entry.Value }
    [IO.File]::WriteAllText($servicePath,$service,[Text.UTF8Encoding]::new($false))

    Step 'Injecting animated profile boot'
    $strategyHook="rem NEXROUTE_PROFILE_BOOT`r`nif exist \"%~dp0.service\nexroute-console.ps1\" powershell -NoProfile -ExecutionPolicy Bypass -File \"%~dp0.service\nexroute-console.ps1\" -Mode Launch -Profile \"%~n0\" -LanguageFile \"%~dp0.service\language.txt\"`r`n"
    $strategyFiles=@(Get-ChildItem $distributionPath -Filter '*.bat' -File | Where-Object { $_.Name -notin @('service.bat','nexroute.bat') })
    foreach ($file in $strategyFiles) { Add-StrategyHook $file.FullName $strategyHook }

    Step 'Adding project metadata'
    foreach ($name in @('README.md','LICENSE','THIRD_PARTY_NOTICES.md')) { Copy-Required (Join-Path $repositoryRoot $name) (Join-Path $distributionPath $name) }
    Copy-Required (Join-Path $repositoryRoot 'overlay/nexroute.bat') (Join-Path $distributionPath 'nexroute.bat')
    if (Test-Path (Join-Path $repositoryRoot 'docs')) { Copy-Item (Join-Path $repositoryRoot 'docs') (Join-Path $distributionPath 'docs') -Recurse -Force }
    @("NexRoute version: $Version","Flowseal baseline: $UpstreamVersion","Service profiles: 15","Styled service pages: 9","Animated strategy launchers: $($strategyFiles.Count)","Build UTC: $([DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ'))") | Set-Content (Join-Path $distributionPath 'NEXROUTE_BUILD_INFO.txt') -Encoding utf8
    $archiveName="NexRoute-$Version-win-x64.zip"
    $archivePath=Join-Path $outputPath $archiveName
    if (Test-Path $archivePath) { Remove-Item $archivePath -Force }
    Compress-Archive (Join-Path $distributionPath '*') $archivePath -CompressionLevel Optimal
    $hash=Get-FileHash $archivePath -Algorithm SHA256
    $checksumPath=$archivePath + '.sha256'
    Set-Content $checksumPath (("{0}  {1}" -f $hash.Hash.ToLowerInvariant(),$archiveName)) -Encoding ascii
    [pscustomobject]@{ Version=$Version; UpstreamVersion=$UpstreamVersion; StrategyCount=$strategyFiles.Count; Archive=$archivePath; Checksum=$checksumPath; Sha256=$hash.Hash.ToLowerInvariant() }
} finally {
    if (Test-Path $tempPath) { Remove-Item $tempPath -Recurse -Force -ErrorAction SilentlyContinue }
}
