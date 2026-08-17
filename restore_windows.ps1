Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinShow {
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
}
"@
# LDesk main window
$main = [IntPtr]592070
$remote = [IntPtr]526418
[WinShow]::ShowWindow($main, 9) | Out-Null   # SW_RESTORE
[WinShow]::ShowWindow($remote, 9) | Out-Null
[WinShow]::SetForegroundWindow($main) | Out-Null
Start-Sleep -Milliseconds 800
[WinShow]::BringWindowToTop($main) | Out-Null
[WinShow]::SetForegroundWindow($main) | Out-Null
Write-Host "main visible=$([WinShow]::IsWindowVisible($main)) iconic=$([WinShow]::IsIconic($main))"
Write-Host "remote visible=$([WinShow]::IsWindowVisible($remote)) iconic=$([WinShow]::IsIconic($remote))"
