@echo off
setlocal EnableExtensions
set "ROOT=%~dp0"
set "VALIDATOR=%ROOT%.service\native\NexRoute.Validation.exe"

if exist "%VALIDATOR%" (
  start "NexRoute Validation" "%VALIDATOR%" --root "%ROOT%"
  exit /b 0
)

echo NexRoute Validation Viewer is missing:
echo   %VALIDATOR%
exit /b 2
