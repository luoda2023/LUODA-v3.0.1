$adb = "J:\codex-work\.toolchains\android-sdk\platform-tools\adb.exe"
$dev = "7358bbbb"
while ($true) {
    $wake = & $adb -s $dev shell "dumpsys power | grep mWakefulness= | head -1" 2>$null
    if ($wake -notmatch "Awake") {
        & $adb -s $dev shell input keyevent KEYCODE_WAKEUP 2>$null | Out-Null
        & $adb -s $dev shell wm dismiss-keyguard 2>$null | Out-Null
        Start-Sleep -Seconds 1
    }
    & $adb -s $dev shell input tap 400 60 2>$null | Out-Null
    Start-Sleep -Seconds 18
}
