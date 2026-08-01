@echo off
chcp 65001 > nul
cd /d "%~dp0"
title NexRoute Secure Update Center

if not exist "%~dp0.service\nexroute-updater.ps1" (
    echo [NexRoute] Updater module not found.
    echo [NexRoute] Download the complete package from GitHub Releases.
    pause
    exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0.service\nexroute-updater.ps1" -Mode Menu -Root "%~dp0"
if errorlevel 1 (
    echo.
    echo [NexRoute] Update operation failed.
    pause
    exit /b 1
)
