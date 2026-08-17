@echo off
set ADB=J:\codex-work\.toolchains\android-sdk\platform-tools\adb.exe
%ADB% -s 7358bbbb uninstall com.luoda.remote
%ADB% -s 7358bbbb install -r -d J:\codex-work\LUODA-v3.0.1\flutter\build\app\outputs\flutter-apk\app-release.apk
