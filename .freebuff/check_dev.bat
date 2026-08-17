@echo off
set ADB=J:\codex-work\.toolchains\android-sdk\platform-tools\adb.exe
echo === df ===
%ADB% -s 7358bbbb shell df -h /data
echo === install sessions ===
%ADB% -s 7358bbbb shell pm list staged-sessions
%ADB% -s 7358bbbb shell pm list install-sessions
echo === tmp files ===
%ADB% -s 7358bbbb shell ls -la /data/local/tmp
