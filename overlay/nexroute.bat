@echo off
chcp 65001 > nul
cd /d "%~dp0"
title NexRoute

if not exist "%~dp0service.bat" (
    echo [NexRoute] service.bat not found.
    echo [NexRoute] Download the complete package from GitHub Releases.
    pause
    exit /b 1
)

call "%~dp0service.bat" %*
