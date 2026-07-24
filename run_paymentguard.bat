@echo off
title PaymentGuard PH - One-Click Launcher
color 0A

:: 1. Configuration (Paths)
set "JAVA_PATH=C:\Program Files\Java\jdk-22"
set "PROJECT_PATH=C:\Users\mjhay\Desktop\Programming\Antigravity\Personal Projects\PAYMENTGUARD PH"

:: 2. Set JAVA_HOME
set "JAVA_HOME=%JAVA_PATH%"

echo =======================================================
echo    PAYMENTGUARD PH: Launching Mobile and Web Apps...
echo =======================================================
echo.

:: 3. Launch Web App (Chrome) in a new window
echo [1/2] Launching Web Dashboard on Chrome...
start "PaymentGuard - WEB" cmd /k "set JAVA_HOME=%JAVA_PATH% && cd /d "%PROJECT_PATH%" && flutter run -d chrome"

:: Small delay to prevent Gradle/Build lock conflicts
timeout /t 3 /nobreak > nul

:: 4. Launch Mobile App (Android Phone) in a new window
echo [2/2] Launching Mobile App on Android Phone...
start "PaymentGuard - ANDROID" cmd /k "set JAVA_HOME=%JAVA_PATH% && cd /d "%PROJECT_PATH%" && flutter run"

echo.
echo =======================================================
echo SUCCESS! Both app instances are running in new windows.
echo =======================================================
echo.
pause