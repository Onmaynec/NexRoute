@echo off
setlocal EnableExtensions DisableDelayedExpansion
chcp 65001 > nul
for %%I in ("%~dp0.") do set "NEXROUTE_ROOT=%%~fI"
cd /d "%NEXROUTE_ROOT%"
title NexRoute

if not exist "%NEXROUTE_ROOT%\service.bat" (
    echo [NexRoute] service.bat not found.
    echo [NexRoute] Download the complete package from GitHub Releases.
    pause
    endlocal & exit /b 1
)

if "%~1"=="" if exist "%NEXROUTE_ROOT%\.service\nexroute-updater.ps1" if exist "%NEXROUTE_ROOT%\utils\check_updates.enabled" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%NEXROUTE_ROOT%\.service\nexroute-updater.ps1" -Mode Auto -Root "%NEXROUTE_ROOT%" -NonInteractive -WarningAction SilentlyContinue
)

call "%NEXROUTE_ROOT%\service.bat" %*
set "NEXROUTE_EXIT_CODE=%ERRORLEVEL%"
endlocal & exit /b %NEXROUTE_EXIT_CODE%
