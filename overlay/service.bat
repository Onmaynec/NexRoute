@echo off
setlocal EnableExtensions
set "NEXROUTE_ROOT=%~dp0"
set "NEXROUTE_LEGACY=%~dp0.service\legacy-service.bat"
set "NEXROUTE_CONSOLE=%~dp0.service\nexroute-console.ps1"

if not "%~1"=="" (
    if /I "%~1"=="--update" (
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%NEXROUTE_CONSOLE%" -Root "%NEXROUTE_ROOT%" -Update
        exit /b %errorlevel%
    )
    if /I "%~1"=="--status" (
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%NEXROUTE_CONSOLE%" -Root "%NEXROUTE_ROOT%" -Status
        exit /b %errorlevel%
    )
    if /I "%~1"=="--lab" (
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%NEXROUTE_CONSOLE%" -Root "%NEXROUTE_ROOT%" -Lab
        exit /b %errorlevel%
    )
    if exist "%NEXROUTE_LEGACY%" (
        call "%NEXROUTE_LEGACY%" %*
        exit /b %errorlevel%
    )
)

net session >nul 2>&1
if not "%errorlevel%"=="0" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath '%~f0' -Verb RunAs -WorkingDirectory '%~dp0'"
    exit /b 0
)

if not exist "%NEXROUTE_CONSOLE%" (
    echo NexRoute console module is missing: %NEXROUTE_CONSOLE%
    pause
    exit /b 2
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%NEXROUTE_CONSOLE%" -Root "%NEXROUTE_ROOT%"
exit /b %errorlevel%
