@echo off
:: ============================================================================
:: GMWF Windows Defender Firewall Auto-Configuration Script
:: Configures permanent Inbound and Outbound rules for seamless LAN communication
:: ============================================================================

setlocal enabledelayedexpansion

echo ====================================================================
echo  GMWF Firewall Configuration Helper
echo  Permanently allowing Inbound and Outbound communication across LAN
echo ====================================================================

:: Determine app directory (defaults to current dir or script parent)
set "APP_DIR=%~dp0"
if exist "%APP_DIR%gmwf.exe" (
    set "EXE_PATH=%APP_DIR%gmwf.exe"
    set "PYTHON_PATH=%APP_DIR%python\python.exe"
) else if exist "%APP_DIR%..\gmwf.exe" (
    set "EXE_PATH=%APP_DIR%..\gmwf.exe"
    set "PYTHON_PATH=%APP_DIR%..\python\python.exe"
) else if exist "%ProgramFiles%\GMWF\gmwf.exe" (
    set "EXE_PATH=%ProgramFiles%\GMWF\gmwf.exe"
    set "PYTHON_PATH=%ProgramFiles%\GMWF\python\python.exe"
) else if exist "%ProgramFiles(x86)%\GMWF\gmwf.exe" (
    set "EXE_PATH=%ProgramFiles(x86)%\GMWF\gmwf.exe"
    set "PYTHON_PATH=%ProgramFiles(x86)%\GMWF\python\python.exe"
) else (
    set "EXE_PATH=E:\GMWF\gmwf\build\windows\x64\runner\Release\gmwf.exe"
    set "PYTHON_PATH=%APP_DIR%python-3.12.10-embed-amd64\python.exe"
)

echo [1/6] Cleaning legacy or duplicate firewall rules...
netsh advfirewall firewall delete rule name="GMWF Application (Inbound)" >nul 2>&1
netsh advfirewall firewall delete rule name="GMWF Application (Outbound)" >nul 2>&1
netsh advfirewall firewall delete rule name="GMWF Python Service (Inbound)" >nul 2>&1
netsh advfirewall firewall delete rule name="GMWF Python Service (Outbound)" >nul 2>&1
netsh advfirewall firewall delete rule name="GMWF LAN Sync and ADMS (TCP-In)" >nul 2>&1
netsh advfirewall firewall delete rule name="GMWF LAN Sync and ADMS (TCP-Out)" >nul 2>&1
netsh advfirewall firewall delete rule name="GMWF UDP Discovery and Biometrics (UDP-In)" >nul 2>&1
netsh advfirewall firewall delete rule name="GMWF UDP Discovery and Biometrics (UDP-Out)" >nul 2>&1
netsh advfirewall firewall delete rule name="GMWF_LAN_Server" >nul 2>&1
netsh advfirewall firewall delete rule name="GMWF_LAN" >nul 2>&1
netsh advfirewall firewall delete rule name="GMWF_ZKTeco_ADMS_8088" >nul 2>&1
netsh advfirewall firewall delete rule name="GMWF_ZKTeco_UDP_4370" >nul 2>&1
netsh advfirewall firewall delete rule name="GMWF_LAN_UDP_53280" >nul 2>&1
netsh advfirewall firewall delete rule name="GMWF_ZKTeco_UDP" >nul 2>&1

echo [2/6] Configuring GMWF.exe Inbound and Outbound rules (All Profiles)...
if exist "%EXE_PATH%" (
    netsh advfirewall firewall add rule name="GMWF Application (Inbound)" dir=in action=allow program="%EXE_PATH%" enable=yes profile=any
    netsh advfirewall firewall add rule name="GMWF Application (Outbound)" dir=out action=allow program="%EXE_PATH%" enable=yes profile=any
    echo       Added rule for: %EXE_PATH%
) else (
    netsh advfirewall firewall add rule name="GMWF Application (Inbound)" dir=in action=allow program="%ProgramFiles%\GMWF\gmwf.exe" enable=yes profile=any
    netsh advfirewall firewall add rule name="GMWF Application (Outbound)" dir=out action=allow program="%ProgramFiles%\GMWF\gmwf.exe" enable=yes profile=any
    echo       Configured for default installation path: %ProgramFiles%\GMWF\gmwf.exe
)

echo [3/6] Configuring Python Service Inbound and Outbound rules (All Profiles)...
if exist "%PYTHON_PATH%" (
    netsh advfirewall firewall add rule name="GMWF Python Service (Inbound)" dir=in action=allow program="%PYTHON_PATH%" enable=yes profile=any
    netsh advfirewall firewall add rule name="GMWF Python Service (Outbound)" dir=out action=allow program="%PYTHON_PATH%" enable=yes profile=any
    echo       Added rule for: %PYTHON_PATH%
)

echo [4/6] Allowing Realtime Sync and ADMS Ports (TCP 53281, 8088, 8080, 8081)...
netsh advfirewall firewall add rule name="GMWF LAN Sync and ADMS (TCP-In)" dir=in action=allow protocol=TCP localport=53281,8088,8080,8081 enable=yes profile=any
netsh advfirewall firewall add rule name="GMWF LAN Sync and ADMS (TCP-Out)" dir=out action=allow protocol=TCP localport=53281,8088,8080,8081 enable=yes profile=any

echo [5/6] Allowing UDP Discovery and Hardware Biometric Ports (UDP 45454, 53280, 4370)...
netsh advfirewall firewall add rule name="GMWF UDP Discovery and Biometrics (UDP-In)" dir=in action=allow protocol=UDP localport=45454,53280,4370 enable=yes profile=any
netsh advfirewall firewall add rule name="GMWF UDP Discovery and Biometrics (UDP-Out)" dir=out action=allow protocol=UDP localport=45454,53280,4370 enable=yes profile=any

echo [6/6] Verifying active firewall rules...
netsh advfirewall firewall show rule name="GMWF LAN Sync and ADMS (TCP-In)" >nul 2>&1
if %ERRORLEVEL% equ 0 (
    echo.
    echo ====================================================================
    echo  SUCCESS: All GMWF LAN Firewall Rules are active and verified!
    echo  Inbound and Outbound traffic will NOT be blocked by Windows Firewall.
    echo ====================================================================
) else (
    echo.
    echo  WARNING: Administrator privileges may be required.
    echo  Please right-click this script and choose "Run as administrator".
)
