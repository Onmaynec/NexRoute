@echo off
setlocal
set "ROOT=%~dp0"
set "MODE=%~1"
if not defined MODE set "MODE=Install"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%.service\next\nexroute-tray-install.ps1" -Mode "%MODE%" -Root "%ROOT%"
set "EXITCODE=%ERRORLEVEL%"
endlocal & exit /b %EXITCODE%
