@echo off
setlocal
powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0.service\nexroute-tray.ps1" -Root "%~dp0"
endlocal
