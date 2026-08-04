@echo off
setlocal EnableExtensions DisableDelayedExpansion
for %%I in ("%~dp0.") do set "NEXROUTE_ROOT=%%~fI"
set "NEXROUTE_LEGACY=%NEXROUTE_ROOT%\.service\legacy-service.bat"
set "NEXROUTE_CONSOLE=%NEXROUTE_ROOT%\.service\nexroute-console.ps1"
set "NEXROUTE_EXIT_CODE=0"

if /I "%~1"=="--update" goto :run_update
if /I "%~1"=="--status" goto :run_status
if /I "%~1"=="--lab" goto :run_lab
if not "%~1"=="" if exist "%NEXROUTE_LEGACY%" goto :run_legacy

goto :ensure_admin

:run_update
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%NEXROUTE_CONSOLE%" -Root "%NEXROUTE_ROOT%" -Update
set "NEXROUTE_EXIT_CODE=%ERRORLEVEL%"
goto :exit

:run_status
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%NEXROUTE_CONSOLE%" -Root "%NEXROUTE_ROOT%" -Status
set "NEXROUTE_EXIT_CODE=%ERRORLEVEL%"
goto :exit

:run_lab
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%NEXROUTE_CONSOLE%" -Root "%NEXROUTE_ROOT%" -Lab
set "NEXROUTE_EXIT_CODE=%ERRORLEVEL%"
goto :exit

:run_legacy
call "%NEXROUTE_LEGACY%" %*
set "NEXROUTE_EXIT_CODE=%ERRORLEVEL%"
goto :exit

:ensure_admin
net session >nul 2>&1
if errorlevel 1 goto :elevate

goto :run_console

:elevate
set "NEXROUTE_LAUNCHER=%~f0"
set "NEXROUTE_WORKDIR=%NEXROUTE_ROOT%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath $env:NEXROUTE_LAUNCHER -Verb RunAs -WorkingDirectory $env:NEXROUTE_WORKDIR"
set "NEXROUTE_EXIT_CODE=%ERRORLEVEL%"
goto :exit

:run_console
if not exist "%NEXROUTE_CONSOLE%" goto :missing_console
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%NEXROUTE_CONSOLE%" -Root "%NEXROUTE_ROOT%"
set "NEXROUTE_EXIT_CODE=%ERRORLEVEL%"
goto :exit

:missing_console
echo NexRoute console module is missing: %NEXROUTE_CONSOLE%
pause
set "NEXROUTE_EXIT_CODE=2"

:exit
endlocal & exit /b %NEXROUTE_EXIT_CODE%
