@echo off
title PaymentGuard PH - Interactive Launcher
color 0A

:: 1. Auto-cleanup lingering background processes to prevent startup locks
echo Cleaning up existing processes...
taskkill /F /IM dart.exe 2>nul
taskkill /F /IM java.exe 2>nul
cls

:: 2. Configuration Variables & Path Setup
set "JAVA_HOME=C:\Program Files\Java\jdk-22"
set "PROJECT_PATH=C:\Users\mjhay\Desktop\Programming\Antigravity\Personal Projects\PAYMENTGUARD PH"
set "ANDROID_SDK_TOOLS=%LOCALAPPDATA%\Android\Sdk\platform-tools"

:: Auto-locate ADB if not present in system PATH
where adb >nul 2>nul
if %errorlevel% neq 0 (
    if exist "%ANDROID_SDK_TOOLS%\adb.exe" (
        set "PATH=%ANDROID_SDK_TOOLS%;%PATH%"
    ) else if exist "C:\Android\platform-tools\adb.exe" (
        set "PATH=C:\Android\platform-tools;%PATH%"
    )
)

:MENU
cls
echo =======================================================
echo          PAYMENTGUARD PH - LAUNCH MENU
echo =======================================================
echo.
echo   [1] Run BOTH (Android Phone + Web)
echo   [2] Run ANDROID PHONE Only
echo   [3] Run WEB Dashboard Only
echo   [4] Exit
echo.
echo =======================================================
set /p choice="Pumili ng option (1, 2, 3, o 4): "

if "%choice%"=="1" goto BOTH
if "%choice%"=="2" goto MOBILE
if "%choice%"=="3" goto WEB
if "%choice%"=="4" exit

echo.
echo [!] Mali ang na-type mo, pakipili lang sa 1, 2, 3, o 4.
timeout /t 2 >nul
goto MENU

:BOTH
call :SELECT_BROWSER
if "%BROWSER%"=="" goto MENU

call :CHECK_ANDROID
if "%CANCEL_ANDROID%"=="1" goto MENU

echo.
echo [1/2] Launching Web Dashboard (%BROWSER%)...
start "PaymentGuard - WEB" cmd /k "cd /d "%PROJECT_PATH%" && flutter run -d %BROWSER%"

timeout /t 3 /nobreak > nul

echo [2/2] Launching Android Mobile App...
start "PaymentGuard - ANDROID" cmd /k "cd /d "%PROJECT_PATH%" && flutter run"
goto END

:MOBILE
call :CHECK_ANDROID
if "%CANCEL_ANDROID%"=="1" goto MENU

echo.
echo Launching ANDROID Mobile App...
start "PaymentGuard - ANDROID" cmd /k "cd /d "%PROJECT_PATH%" && flutter run"
goto END

:WEB
call :SELECT_BROWSER
if "%BROWSER%"=="" goto MENU

echo.
echo Launching Web Dashboard (%BROWSER%)...
start "PaymentGuard - WEB" cmd /k "cd /d "%PROJECT_PATH%" && flutter run -d %BROWSER%"
goto END

:: =======================================================
:: SUBROUTINE: SELECT BROWSER
:: =======================================================
:SELECT_BROWSER
set "BROWSER="
cls
echo =======================================================
echo             SELECT WEB BROWSER TARGET
echo =======================================================
echo.
echo   [1] Google Chrome (-d chrome)
echo   [2] Microsoft Edge (-d edge)
echo   [3] Web Server / Default (-d web-server)
echo   [4] Back to Main Menu
echo.
echo =======================================================
set /p bchoice="Pumili ng browser (1, 2, 3, o 4): "

if "%bchoice%"=="1" set "BROWSER=chrome" & exit /b
if "%bchoice%"=="2" set "BROWSER=edge" & exit /b
if "%bchoice%"=="3" set "BROWSER=web-server" & exit /b
if "%bchoice%"=="4" goto :EOF

echo.
echo [!] Mali ang na-type mo, pakipili lang sa 1, 2, 3, o 4.
timeout /t 2 >nul
goto SELECT_BROWSER

:: =======================================================
:: SUBROUTINE: CHECK ANDROID DEVICE & WIRELESS DEBUGGING
:: =======================================================
:CHECK_ANDROID
set "CANCEL_ANDROID=0"
cls
echo Checking for ADB installation...

:: Verify ADB availability
where adb >nul 2>nul
if %errorlevel% neq 0 (
    echo.
    echo [ERROR] Hindi mahanap ang 'adb.exe'.
    echo Siguraduhing nakakabit ang Android SDK Platform-Tools sa Android Studio.
    echo.
    pause
    set "CANCEL_ANDROID=1"
    exit /b
)

echo Checking for connected Android devices...

:: Scan ADB for connected devices
set "DEVICE_FOUND=0"
for /f "tokens=1,2" %%A in ('adb devices ^| findstr /v "List of devices attached"') do (
    if "%%B"=="device" set "DEVICE_FOUND=1"
)

if "%DEVICE_FOUND%"=="1" (
    echo.
    echo [OK] Active Android device detected!
    timeout /t 1 >nul
    exit /b
)

echo.
echo =======================================================
echo      NO ACTIVE ANDROID DEVICE DETECTED!
echo =======================================================
echo  Pumili ng paraan para ikonekta ang phone mo:
echo.
echo   [1] Connect via Wireless Debugging (Naka-pair na dati)
echo   [2] Pair + Connect New Device (Wireless Debugging)
echo   [3] Re-scan Devices (USB Cable / Emulator)
echo   [4] Back to Main Menu
echo.
echo =======================================================
set /p adb_choice="Pumili ng option (1, 2, 3, o 4): "

if "%adb_choice%"=="1" goto ADB_CONNECT
if "%adb_choice%"=="2" goto ADB_PAIR
if "%adb_choice%"=="3" goto CHECK_ANDROID
if "%adb_choice%"=="4" set "CANCEL_ANDROID=1" & exit /b

echo.
echo [!] Mali ang na-type mo, pakipili lang sa 1, 2, 3, o 4.
timeout /t 2 >nul
goto CHECK_ANDROID

:ADB_PAIR
echo.
echo -------------------------------------------------------
echo  PAIRING INSTRUCTIONS:
echo  1. Sa phone: Developer Options ^> Wireless Debugging
echo  2. i-tap ang "Pair device with pairing code"
echo -------------------------------------------------------
set /p pair_ip="IP & Pairing Port (e.g. 192.168.1.15:38123): "
set /p pair_code="6-digit Pairing Code: "
echo.
echo Pairing with %pair_ip%...
adb pair %pair_ip% %pair_code%
echo.
pause
goto ADB_CONNECT

:ADB_CONNECT
echo.
echo -------------------------------------------------------
echo  CONNECT INSTRUCTIONS:
echo  Gamitin ang IP address ^& Port na makikita sa main screen
echo  ng Wireless Debugging (Nag-iiba ang port tuwing on/off).
echo -------------------------------------------------------
set /p conn_ip="IP & Port to connect (e.g. 192.168.1.15:43211): "
echo.
echo Connecting to %conn_ip%...
adb connect %conn_ip%
echo.
timeout /t 2 >nul
goto CHECK_ANDROID

:END
echo.
echo =======================================================
echo Success! Na-launch na ang napili mong platform.
echo =======================================================
timeout /t 3 >nul
exit