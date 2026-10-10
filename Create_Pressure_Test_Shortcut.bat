@echo off
title Create GMWF Pressure Test Shortcut on Desktop
cls
echo ======================================================================
echo    Creating Desktop Shortcut for GMWF Network Pressure Test...
echo ======================================================================
echo.

cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0tool\create_shortcut.ps1"

echo.
echo ======================================================================
echo Done! Check your Desktop for "GMWF Network Pressure Test".
echo Press any key to close this window...
echo ======================================================================
pause >nul
