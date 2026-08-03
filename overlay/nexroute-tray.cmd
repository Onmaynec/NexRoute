@echo off
setlocal
set "ROOT=%~dp0"
set "NATIVE=%ROOT%.service\native\NexRoute.Tray.exe"
if exist "%NATIVE%" (
    start "NexRoute Tray" "%NATIVE%" --root "%ROOT%"
    endlocal & exit /b 0
)
powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%ROOT%.service\nexroute-tray.ps1" -Root "%ROOT%"
set "EXITCODE=%ERRORLEVEL%"
endlocal & exit /b %EXITCODE%
