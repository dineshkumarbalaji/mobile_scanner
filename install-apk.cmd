@echo off
REM Install-APK.cmd - Helper script to install APK on Android device/emulator

echo Cleaning previous build...
cd /d "%~dp0"
call flutter clean

echo Building APK...
call flutter build apk --debug

echo Finding APK file...
for /r "build" %%f in (app-debug.apk) do (
    set "APK_PATH=%%f"
)

if not defined APK_PATH (
    echo Error: APK not found!
    exit /b 1
)

echo.
echo Found APK: %APK_PATH%
echo Installing on device...

REM Use ADB with proper quoting
adb install -r "%APK_PATH%"

if %errorlevel% equ 0 (
    echo.
    echo Installation successful!
    echo Launching app...
    adb shell am start -n com.example.mobile_scanner/com.example.mobile_scanner.MainActivity
) else (
    echo.
    echo Installation failed with error code: %errorlevel%
    exit /b %errorlevel%
)
