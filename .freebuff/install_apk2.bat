@echo off
set ADB=J:\codex-work\.toolchains\android-sdk\platform-tools\adb.exe
"%ADB%" install -r "J:\codex-work\LUODA-v3.0.1\flutter\build\app\outputs\flutter-apk\app-release.apk"
echo EXIT=%ERRORLEVEL%
