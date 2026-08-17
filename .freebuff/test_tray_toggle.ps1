Add-Type @"
using System;
using System.Runtime.InteropServices;
public class TrayTest {
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindowW(string cls, string win);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
}
"@
$w = [TrayTest]::FindWindowW("FLUTTER_RUNNER_WIN32_WINDOW", "点聊")
Write-Output "HWND: $w"
if ($w -ne [IntPtr]::Zero) {
  Write-Output ("visible before: " + [TrayTest]::IsWindowVisible($w))
  [TrayTest]::ShowWindow($w, 0) | Out-Null   # SW_HIDE
  Start-Sleep -Milliseconds 500
  Write-Output ("visible after hide: " + [TrayTest]::IsWindowVisible($w))
  [TrayTest]::ShowWindow($w, 5) | Out-Null   # SW_SHOW
  Start-Sleep -Milliseconds 500
  Write-Output ("visible after show: " + [TrayTest]::IsWindowVisible($w))
} else {
  Write-Output "window not found"
}
