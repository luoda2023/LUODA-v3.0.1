Get-ChildItem 'J:\codex-work\LUODA-v3.0.1\flutter' -Recurse -Filter *.apk -ErrorAction SilentlyContinue | Select-Object FullName, LastWriteTime, Length | Format-Table -AutoSize
