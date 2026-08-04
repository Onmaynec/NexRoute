@echo off
setlocal EnableExtensions DisableDelayedExpansion
for %%I in ("%~dp0.") do set "NEXROUTE_ROOT=%%~fI"

if not exist "%NEXROUTE_ROOT%\service.bat" (
    echo [NexRoute] service.bat not found.
    echo [NexRoute] Download the complete package from GitHub Releases.
    endlocal & exit /b 2
)

call "%NEXROUTE_ROOT%\service.bat" --update
set "NEXROUTE_EXIT_CODE=%ERRORLEVEL%"
endlocal & exit /b %NEXROUTE_EXIT_CODE%
