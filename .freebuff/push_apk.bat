@echo off
J:\codex-work\.toolchains\android-sdk\platform-tools\adb.exe -s 7358bbbb push J:\codex-work\LUODA-v3.0.1\flutter\build\app\outputs\flutter-apk\app-release.apk /data/local/tmp/app.apk
J:\codex-work\.toolchains\android-sdk\platform-tools\adb.exe -s 7358bbbb shell pm install -r -d /data/local/tmp/app.apk
