@echo off
setlocal enabledelayedexpansion
title GMWF LAN Network Pressure and Real Device Chaos Audit
cls
echo ======================================================================
echo    GMWF LAN Network Pressure and Real Device Chaos Audit
echo ======================================================================
echo.

cd /d "%~dp0"

:: 1. Check if compiled standalone executable exists (Requires NO Dart or Flutter)
set "EXE_CMD="
if exist "%~dp0gmwf_pressure_test.exe" (
    set "EXE_CMD=%~dp0gmwf_pressure_test.exe"
) else if exist "%~dp0build\windows\x64\runner\Release\gmwf_pressure_test.exe" (
    set "EXE_CMD=%~dp0build\windows\x64\runner\Release\gmwf_pressure_test.exe"
)

if defined EXE_CMD (
    echo [OK] Launching standalone GMWF Network Pressure Test engine...
    echo.
    "!EXE_CMD!" %*
    set "TEST_EXIT=!ERRORLEVEL!"
    goto :CHECK_RESULT
)

:: 2. Fallback to Dart SDK if on dev PC
where dart >nul 2>nul
if !ERRORLEVEL! equ 0 (
    echo [INFO] Running via system Dart SDK...
    dart run tool/flood_token_stress_test.dart %*
    set "TEST_EXIT=!ERRORLEVEL!"
    goto :CHECK_RESULT
)

:: 3. Check common Flutter SDK locations on developer PC
if exist "E:\flutter\bin\dart.bat" (
    echo [INFO] Running via Flutter SDK at E:\flutter\bin\dart.bat...
    call "E:\flutter\bin\dart.bat" run tool/flood_token_stress_test.dart %*
    set "TEST_EXIT=!ERRORLEVEL!"
    goto :CHECK_RESULT
)
if exist "C:\flutter\bin\dart.bat" (
    echo [INFO] Running via Flutter SDK at C:\flutter\bin\dart.bat...
    call "C:\flutter\bin\dart.bat" run tool/flood_token_stress_test.dart %*
    set "TEST_EXIT=!ERRORLEVEL!"
    goto :CHECK_RESULT
)

:: 4. If neither is found
echo ======================================================================
echo [ERROR] Neither 'gmwf_pressure_test.exe' nor 'dart' was found.
echo.
echo Standalone executable 'gmwf_pressure_test.exe' must be placed in:
echo   %~dp0
echo.
echo No Dart or Flutter SDK is needed if 'gmwf_pressure_test.exe' is present.
echo ======================================================================
echo.
pause
exit /b 1

:CHECK_RESULT
echo.
echo ======================================================================
if "!TEST_EXIT!"=="0" (
    echo [SUCCESS] Audit completed successfully!
    echo * Full report saved directly to your Desktop.
    echo * Copied to your Windows Clipboard: press Ctrl+V to paste anywhere.
    echo * Opened automatically in Notepad for your review.
) else (
    echo [WARNING] Audit ended with code !TEST_EXIT!. Check output above.
)
echo ======================================================================
echo Press any key to exit this window...
pause >nul
