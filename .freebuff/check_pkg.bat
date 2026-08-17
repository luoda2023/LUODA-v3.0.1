@echo off
set ADB=J:\codex-work\.toolchains\android-sdk\platform-tools\adb.exe
%ADB% -s 7358bbbb shell pm list packages | findstr luoda
%ADB% -s 7358bbbb shell am start -n com.luoda.remote/.MainActivity
