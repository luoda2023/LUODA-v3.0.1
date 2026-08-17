Add-Type @'
using System;
using System.Runtime.InteropServices;
public class Focus {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
}
'@
$h = [IntPtr]3935734
[Focus]::ShowWindow($h, 9) | Out-Null   # SW_RESTORE
[Focus]::SetForegroundWindow($h) | Out-Null
[Focus]::BringWindowToTop($h) | Out-Null
Start-Sleep -Milliseconds 800
Write-Output "focused"
