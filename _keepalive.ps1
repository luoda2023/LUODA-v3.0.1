param([string]$dev="7358bbbb")
$adb = "D:\Program Files\LDPlayer14\adb.exe"
for ($i=0; $i -lt 60; $i++) {
    & $adb -s $dev shell input keyevent KEYCODE_WAKEUP 2>$null | Out-Null
    & $adb -s $dev shell input swipe 540 2000 540 1200 100 2>$null | Out-Null  # 点亮
    Start-Sleep -Seconds 2
}
