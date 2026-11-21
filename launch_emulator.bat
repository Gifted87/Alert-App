@echo off
title Android Emulator - Pixel_AlertApp
echo ========================================================
echo   Starting Android Virtual Device (Pixel_AlertApp)...
echo ========================================================

:: Start emulator GUI window on your desktop
start "" "C:\src\android-sdk\emulator\emulator.exe" -avd Pixel_AlertApp

echo Waiting for emulator to boot up...
adb wait-for-device
echo Emulator connected! Installing latest build with exact Geist typography...
adb install -r "C:\Users\hp\Documents\Web-Projects\Alert-App\build\app\outputs\flutter-apk\app-debug.apk"
echo Launching TenX Institutional Trading Terminal...
adb shell am start -n com.example.alert_app/.MainActivity
echo ========================================================
echo   Success! TenX is now running on your emulator.
echo ========================================================
pause
