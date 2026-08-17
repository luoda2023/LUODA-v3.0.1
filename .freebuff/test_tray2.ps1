Add-Type @"
using System;
using System.Runtime.InteropServices;
public class TrayTest2 {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowW(string cls, string win);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
}
"@
$title = [string]([char]0x70B9) + [string]([char]0x804A)   # 点聊
$w = [TrayTest2]::FindWindowW("FLUTTER_RUNNER_WIN32_WINDOW", $title)
Write-Output "HWND: $w"
if ($w -ne [IntPtr]::Zero) {
  Write-Output ("visible before: " + [TrayTest2]::IsWindowVisible($w))
  [TrayTest2]::ShowWindow($w, 0) | Out-Null   # SW_HIDE
  Start-Sleep -Milliseconds 500
  Write-Output ("visible after hide: " + [TrayTest2]::IsWindowVisible($w))
  [TrayTest2]::ShowWindow($w, 5) | Out-Null   # SW_SHOW
  [TrayTest2]::SetForegroundWindow($w) | Out-Null
  Start-Sleep -Milliseconds 500
  Write-Output ("visible after show: " + [TrayTest2]::IsWindowVisible($w))
} else {
  Write-Output "window not found"
}
