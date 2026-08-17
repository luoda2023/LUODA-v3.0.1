@echo off
set LDESK_DEBUG_API=1
set LDESK_DEBUG_API_TOKEN=testtoken1234567890
cd /d J:\codex-work\LUODA-v3.0.1\flutter\build\windows\x64\runner\Release
start "" LDesk.exe --connect 980966@36.134.211.189:21118?key=4c7252bdf61cba1775651c16cf5427da033384815f7b17389cb2f48cecbaa969
