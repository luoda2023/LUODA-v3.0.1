$adb = 'J:\codex-work\.toolchains\android-sdk\platform-tools\adb.exe'
$dev = '7358bbbb'
while ($true) {
  & $adb -s $dev shell input keyevent KEYCODE_WAKEUP 2>$null | Out-Null
  & $adb -s $dev shell input swipe 540 1600 540 800 80 2>$null | Out-Null
  Start-Sleep -Milliseconds 600
}
