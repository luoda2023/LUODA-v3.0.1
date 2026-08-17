@echo off
set ADB=J:\codex-work\.toolchains\android-sdk\platform-tools\adb.exe
%ADB% -s 7358bbbb shell df -h /data/local/tmp
%ADB% -s 7358bbbb shell ls -la /data/local/tmp/app.apk
%ADB% -s 7358bbbb shell ps -A | findstr -i "install package"
%ADB% version
