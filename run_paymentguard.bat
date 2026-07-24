@echo off
title PaymentGuard PH - Interactive Launcher
color 0A

:: 1. Auto-cleanup lingering background processes to prevent startup locks
echo Cleaning up existing processes...
taskkill /F /IM dart.exe 2>nul
taskkill /F /IM java.exe 2>nul
cls

:: 2. Configuration Variables (Awtomatikong ipapasa sa sub-windows)
set "JAVA_HOME=C:\Program Files\Java\jdk-22"
set "PROJECT_PATH=C:\Users\mjhay\Desktop\Programming\Antigravity\Personal Projects\PAYMENTGUARD PH"

:MENU
cls
echo =======================================================
echo          PAYMENTGUARD PH - LAUNCH MENU
echo =======================================================
echo.
echo   [1] Run BOTH (Android Phone + Chrome Web)
echo   [2] Run ANDROID PHONE Only
echo   [3] Run CHROME WEB Only
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
echo.
echo [1/2] Launching Chrome Web Dashboard...
start "PaymentGuard - WEB" cmd /k "cd /d "%PROJECT_PATH%" && flutter run -d chrome"

timeout /t 3 /nobreak > nul

echo [2/2] Launching Android Mobile App...
start "PaymentGuard - ANDROID" cmd /k "cd /d "%PROJECT_PATH%" && flutter run"
goto END

:MOBILE
echo.
echo Launching ANDROID Mobile App...
start "PaymentGuard - ANDROID" cmd /k "cd /d "%PROJECT_PATH%" && flutter run"
goto END

:WEB
echo.
echo Launching CHROME Web Dashboard...
start "PaymentGuard - WEB" cmd /k "cd /d "%PROJECT_PATH%" && flutter run -d chrome"
goto END

:END
echo.
echo =======================================================
echo Success! Na-launch na ang napili mong platform.
echo =======================================================
timeout /t 3 >nul
exit