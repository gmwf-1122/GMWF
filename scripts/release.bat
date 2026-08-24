@echo off
if "%~1"=="" (
    echo [ERROR] Please provide a release version number.
    echo Usage: scripts\release.bat 1.3.8
    exit /b 1
)

py -3 scripts/release_app.py %1
