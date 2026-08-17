Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinFront {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern IntPtr SetFocus(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
}
"@
[WinFront]::ShowWindow([IntPtr]526418, 9) | Out-Null
[WinFront]::SetForegroundWindow([IntPtr]526418) | Out-Null
Start-Sleep -Milliseconds 600
[WinFront]::BringWindowToTop([IntPtr]526418) | Out-Null
[WinFront]::SetForegroundWindow([IntPtr]526418) | Out-Null
Start-Sleep -Milliseconds 600
Write-Host "focused"
