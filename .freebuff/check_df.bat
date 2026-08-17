@echo off
set ADB=J:\codex-work\.toolchains\android-sdk\platform-tools\adb.exe
%ADB% -s 7358bbbb shell df -h /data
%ADB% -s 7358bbbb shell df -h
