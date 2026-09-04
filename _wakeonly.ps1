$adb = 'J:\codex-work\.toolchains\android-sdk\platform-tools\adb.exe'
$dev = '7358bbbb'
while ($true) {
  & $adb -s $dev shell input keyevent KEYCODE_WAKEUP 2>$null | Out-Null
  Start-Sleep -Milliseconds 900
}
